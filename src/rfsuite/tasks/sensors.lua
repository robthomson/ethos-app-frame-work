--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local TelemetryConfig = require("telemetry.config")
local BatteryConfig = require("telemetry.battery")
local ModuleLoader = require("framework.utils.module_loader")

local SensorsTask = {}
local SENSOR_LOST_MUTE_SECONDS = 10.0
local SENSOR_LOST_REFRESH_SECONDS = 1.0
local PROVIDER_MODULES = {
    elrs = "sensors.providers.elrs",
    frsky = "sensors.providers.frsky",
    msp = "sensors.providers.msp",
    sim = "sensors.providers.sim",
    smart = "sensors.providers.smart"
}
local PROVIDER_FACTORIES = {}

local function loadModule(moduleName)
    local result
    local path

    result = PROVIDER_FACTORIES[moduleName]
    if result ~= nil then
        return result
    end

    path = string.gsub(moduleName, "%.", "/") .. ".lua"
    result = ModuleLoader.requireOrLoad(moduleName, path)
    PROVIDER_FACTORIES[moduleName] = result
    return result
end

local function unloadApi(mspTask, apiName, api)
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end

    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(apiName)
    end
end

function SensorsTask:_resetTelemetryConfigBootstrap()
    self.telemetryConfigReadInFlight = false
    self.telemetryConfigReadRetryAt = 0
end

function SensorsTask:_resetBatteryConfigBootstrap()
    self.batteryConfigReadInFlight = false
    self.batteryConfigReadRetryAt = 0
end

function SensorsTask:_resetSensorLostMute()
    self.sensorLostMuteUntil = 0
    self.sensorLostMuteRefreshAt = 0
    self.sensorLostMuteModuleId = nil
end

function SensorsTask:_armSensorLostMute(now)
    self.sensorLostMuteUntil = (now or os.clock()) + SENSOR_LOST_MUTE_SECONDS
    self.sensorLostMuteRefreshAt = 0
    self.sensorLostMuteModuleId = nil
end

function SensorsTask:armSensorLostMute(seconds)
    local now = os.clock()
    local duration = tonumber(seconds) or SENSOR_LOST_MUTE_SECONDS

    if duration <= 0 then
        return
    end

    self.sensorLostMuteUntil = math.max(self.sensorLostMuteUntil or 0, now + duration)
    self.sensorLostMuteRefreshAt = 0
    self.sensorLostMuteModuleId = nil
    self:_muteSensorLostDuringStartup(now)
end

function SensorsTask:_telemetryModuleId()
    local session = self.framework.session
    local moduleId = session:get("telemetryModuleNumber", nil)
    local sensor

    if type(moduleId) == "number" then
        return moduleId
    end

    sensor = session:get("telemetrySensor", nil)
    if sensor and type(sensor.module) == "function" then
        moduleId = sensor:module()
        if type(moduleId) == "number" then
            return moduleId
        end
    end

    return nil
end

function SensorsTask:_muteSensorLostDuringStartup(now)
    local transport
    local moduleId
    local module
    local duration
    local moduleIndex

    if not model or type(model.getModule) ~= "function" then
        return
    end

    if (self.sensorLostMuteUntil or 0) <= now then
        return
    end

    transport = self:_transportName()
    if transport == "sim" then
        return
    end

    moduleId = self:_telemetryModuleId()

    if type(moduleId) == "number" and self.sensorLostMuteModuleId == moduleId and now < (self.sensorLostMuteRefreshAt or 0) then
        return
    end

    duration = math.max(0.5, (self.sensorLostMuteUntil or now) - now)

    if type(moduleId) == "number" then
        module = model.getModule(moduleId)
        if module and type(module.muteSensorLost) == "function" then
            pcall(function()
                module:muteSensorLost(duration)
            end)
            self.sensorLostMuteModuleId = moduleId
        end
    else
        for moduleIndex = 0, 1 do
            module = model.getModule(moduleIndex)
            if module and type(module.muteSensorLost) == "function" then
                pcall(function()
                    module:muteSensorLost(duration)
                end)
            end
        end
        self.sensorLostMuteModuleId = "all"
    end

    self.sensorLostMuteRefreshAt = now + SENSOR_LOST_REFRESH_SECONDS
end

function SensorsTask:_primeTelemetryConfig(now)
    local session = self.framework.session
    local mspTask
    local api
    local loadErr
    local queued
    local queueErr

    if self:_transportName() == "sim" then
        return
    end

    if not session:get("isConnected", false) then
        return
    end

    if type(session:get("telemetryConfig", nil)) == "table" then
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = 0
        return
    end

    if session:get("apiVersion", nil) == nil or session:get("mspBusy", false) == true then
        return
    end

    if self.telemetryConfigReadInFlight == true then
        return
    end

    if (self.telemetryConfigReadRetryAt or 0) > now then
        return
    end

    mspTask = self.framework:getTask("msp")
    if not mspTask or not mspTask.mspQueue or mspTask.mspQueue:isProcessed() ~= true then
        return
    end

    if not mspTask.api or not mspTask.api.load then
        return
    end

    api, loadErr = mspTask.api.load("TELEMETRY_CONFIG")
    if not api then
        self.telemetryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] telemetry config load failed: %s", tostring(loadErr or "load_failed"))
        return
    end

    self.telemetryConfigReadInFlight = true
    api.setUUID("sensors-telemetry-config")
    api.setTimeout(3.0)
    api.setCompleteHandler(function()
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = 0
        TelemetryConfig.applyApiToSession(session, api, self.framework.log)
        unloadApi(mspTask, "TELEMETRY_CONFIG", api)
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = os.clock() + 0.75
        self.framework.log:warn("[sensors] telemetry config read failed: %s", tostring(errorMessage or "read_failed"))
        unloadApi(mspTask, "TELEMETRY_CONFIG", api)
    end)

    queued, queueErr = api.read()
    if queued ~= true then
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] telemetry config queue failed: %s", tostring(queueErr or "queue_failed"))
        unloadApi(mspTask, "TELEMETRY_CONFIG", api)
    end
end

function SensorsTask:_primeBatteryConfig(now)
    local session = self.framework.session
    local mspTask
    local api
    local loadErr
    local queued
    local queueErr

    if not session:get("isConnected", false) then
        return
    end

    if type(session:get("batteryConfig", nil)) == "table" then
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = 0
        return
    end

    if session:get("apiVersion", nil) == nil or session:get("mspBusy", false) == true then
        return
    end

    if self.batteryConfigReadInFlight == true then
        return
    end

    if (self.batteryConfigReadRetryAt or 0) > now then
        return
    end

    mspTask = self.framework:getTask("msp")
    if not mspTask or not mspTask.mspQueue or mspTask.mspQueue:isProcessed() ~= true then
        return
    end

    if not mspTask.api or not mspTask.api.load then
        return
    end

    api, loadErr = mspTask.api.load("BATTERY_CONFIG")
    if not api then
        self.batteryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] battery config load failed: %s", tostring(loadErr or "load_failed"))
        return
    end

    self.batteryConfigReadInFlight = true
    api.setUUID("sensors-battery-config")
    api.setTimeout(3.0)
    api.setCompleteHandler(function()
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = 0
        BatteryConfig.applyApiToSession(session, api, self.framework.log)
        unloadApi(mspTask, "BATTERY_CONFIG", api)
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = os.clock() + 0.75
        self.framework.log:warn("[sensors] battery config read failed: %s", tostring(errorMessage or "read_failed"))
        unloadApi(mspTask, "BATTERY_CONFIG", api)
    end)

    queued, queueErr = api.read()
    if queued ~= true then
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] battery config queue failed: %s", tostring(queueErr or "queue_failed"))
        unloadApi(mspTask, "BATTERY_CONFIG", api)
    end
end

function SensorsTask:_transportName()
    if system and system.getVersion and system.getVersion().simulation == true then
        return "sim"
    end

    return self.framework.session:get("telemetryType", "disconnected")
end

function SensorsTask:_resetTransportProvider()
    if self.transportProvider and self.transportProvider.reset then
        self.transportProvider:reset()
    end
    self.transportProvider = nil
    self.transportProviderName = nil
end

function SensorsTask:_getProvider(name)
    local provider
    local moduleName
    local factory

    provider = self.providers[name]
    if provider ~= nil then
        return provider
    end

    moduleName = PROVIDER_MODULES[name]
    if not moduleName then
        return nil
    end

    factory = loadModule(moduleName)
    provider = factory and factory.new and factory.new(self.framework) or nil
    self.providers[name] = provider
    return provider
end

function SensorsTask:_ensureTransportProvider()
    local name = self:_transportName()

    if name ~= self.transportProviderName then
        self:_resetTransportProvider()
    end

    if name == "sim" then
        self.transportProvider = self:_getProvider("sim")
        self.transportProviderName = name
    elseif name == "crsf" then
        self.transportProvider = self:_getProvider("elrs")
        self.transportProviderName = name
    elseif name == "sport" then
        self.transportProvider = self:_getProvider("frsky")
        self.transportProviderName = name
    end

    return self.transportProvider
end

function SensorsTask:init(framework)
    self.framework = framework
    self.providers = {}
    self.transportProvider = nil
    self.transportProviderName = nil
    self.wakeupTick = 0
    self:_resetTelemetryConfigBootstrap()
    self:_resetBatteryConfigBootstrap()
    self:_armSensorLostMute(os.clock())

    framework:on("ontransportchange", function()
        self:_resetTransportProvider()
        self:_resetTelemetryConfigBootstrap()
        self:_resetBatteryConfigBootstrap()
        self:_armSensorLostMute(os.clock())
        BatteryConfig.clearSession(self.framework.session)
        if self:_getProvider("smart") and self.providers.smart.reset then
            self.providers.smart:reset()
        end
        if self:_getProvider("msp") and self.providers.msp.reset then
            self.providers.msp:reset()
        end
    end)
    framework:on("ondisconnect", function()
        self:_resetTransportProvider()
        self:_resetTelemetryConfigBootstrap()
        self:_resetBatteryConfigBootstrap()
        self:_resetSensorLostMute()
        BatteryConfig.clearSession(self.framework.session)
        if self:_getProvider("smart") and self.providers.smart.reset then
            self.providers.smart:reset()
        end
        if self:_getProvider("msp") and self.providers.msp.reset then
            self.providers.msp:reset()
        end
    end)
    framework:on("onconnect", function()
        self:_armSensorLostMute(os.clock())
    end)
end

function SensorsTask:wakeup()
    local transportProvider = self:_ensureTransportProvider()
    local mspProvider = self:_getProvider("msp")
    local smartProvider = self:_getProvider("smart")
    local session = self.framework.session
    local now = os.clock()
    local phase

    self:_muteSensorLostDuringStartup(now)
    if mspProvider and mspProvider.seedStartupPlaceholders then
        mspProvider:seedStartupPlaceholders(now)
    end
    if mspProvider and mspProvider.refresh then
        mspProvider:refresh(now)
    end
    if smartProvider and smartProvider.refresh then
        smartProvider:refresh(now)
    end

    if session:get("lifecycleActive", false) == true then
        return
    end

    if session:get("apiVersion", nil) == nil and self:_transportName() ~= "sim" then
        return
    end

    self:_primeTelemetryConfig(now)
    self:_primeBatteryConfig(now)

    if transportProvider and transportProvider.wakeup then
        transportProvider:wakeup()
    end

    self.wakeupTick = (self.wakeupTick or 0) + 1
    phase = self.wakeupTick % 2

    if phase == 0 and mspProvider and mspProvider.wakeup then
        mspProvider:wakeup()
    end

    if phase == 1
        and smartProvider
        and smartProvider.wakeup
        and session:get("postConnectComplete", false) == true
        and type(session:get("batteryConfig", nil)) == "table"
    then
        smartProvider:wakeup()
    end
end

function SensorsTask:reset()
    local name
    local provider

    for name, provider in pairs(self.providers or {}) do
        if provider and provider.reset then
            provider:reset()
        end
    end

    self.transportProvider = nil
    self.transportProviderName = nil
    self.wakeupTick = 0
    self:_resetTelemetryConfigBootstrap()
    self:_resetBatteryConfigBootstrap()
    BatteryConfig.clearSession(self.framework.session)
end

function SensorsTask:close()
    self:reset()
    self.framework = nil
end

return SensorsTask
