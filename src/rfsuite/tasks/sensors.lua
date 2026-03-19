--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local SimProvider = require("sensors.providers.sim")
local SmartProvider = require("sensors.providers.smart")
local ElrsProvider = require("sensors.providers.elrs")
local FrskyProvider = require("sensors.providers.frsky")
local MspProvider = require("sensors.providers.msp")
local TelemetryConfig = require("telemetry.config")
local BatteryConfig = require("telemetry.battery")

local SensorsTask = {}
local SENSOR_LOST_MUTE_SECONDS = 10.0
local SENSOR_LOST_REFRESH_SECONDS = 1.0

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
    local duration
    local moduleIndex

    if not system or type(system.muteSensorLost) ~= "function" then
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
        pcall(system.muteSensorLost, moduleId, duration)
        self.sensorLostMuteModuleId = moduleId
    else
        for moduleIndex = 0, 1 do
            pcall(system.muteSensorLost, moduleIndex, duration)
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
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = os.clock() + 0.75
        self.framework.log:warn("[sensors] telemetry config read failed: %s", tostring(errorMessage or "read_failed"))
    end)

    queued, queueErr = api.read()
    if queued ~= true then
        self.telemetryConfigReadInFlight = false
        self.telemetryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] telemetry config queue failed: %s", tostring(queueErr or "queue_failed"))
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
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = os.clock() + 0.75
        self.framework.log:warn("[sensors] battery config read failed: %s", tostring(errorMessage or "read_failed"))
    end)

    queued, queueErr = api.read()
    if queued ~= true then
        self.batteryConfigReadInFlight = false
        self.batteryConfigReadRetryAt = now + 0.75
        self.framework.log:warn("[sensors] battery config queue failed: %s", tostring(queueErr or "queue_failed"))
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

function SensorsTask:_ensureTransportProvider()
    local name = self:_transportName()

    if name ~= self.transportProviderName then
        self:_resetTransportProvider()
    end

    if name == "sim" then
        self.transportProvider = self.providers.sim
        self.transportProviderName = name
    elseif name == "crsf" then
        self.transportProvider = self.providers.elrs
        self.transportProviderName = name
    elseif name == "sport" then
        self.transportProvider = self.providers.frsky
        self.transportProviderName = name
    end

    return self.transportProvider
end

function SensorsTask:init(framework)
    self.framework = framework
    self.providers = {
        elrs = ElrsProvider.new(framework),
        frsky = FrskyProvider.new(framework),
        msp = MspProvider.new(framework),
        sim = SimProvider.new(framework),
        smart = SmartProvider.new(framework)
    }
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
        if self.providers.smart and self.providers.smart.reset then
            self.providers.smart:reset()
        end
        if self.providers.msp and self.providers.msp.reset then
            self.providers.msp:reset()
        end
    end)
    framework:on("ondisconnect", function()
        self:_resetTransportProvider()
        self:_resetTelemetryConfigBootstrap()
        self:_resetBatteryConfigBootstrap()
        self:_resetSensorLostMute()
        BatteryConfig.clearSession(self.framework.session)
        if self.providers.smart and self.providers.smart.reset then
            self.providers.smart:reset()
        end
        if self.providers.msp and self.providers.msp.reset then
            self.providers.msp:reset()
        end
    end)
    framework:on("onconnect", function()
        self:_armSensorLostMute(os.clock())
    end)
end

function SensorsTask:wakeup()
    local transportProvider = self:_ensureTransportProvider()
    local session = self.framework.session
    local now = os.clock()
    local phase

    self:_muteSensorLostDuringStartup(now)
    if self.providers.msp and self.providers.msp.seedStartupPlaceholders then
        self.providers.msp:seedStartupPlaceholders(now)
    end
    if self.providers.msp and self.providers.msp.refresh then
        self.providers.msp:refresh(now)
    end
    if self.providers.smart and self.providers.smart.refresh then
        self.providers.smart:refresh(now)
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

    if phase == 0 and self.providers.msp and self.providers.msp.wakeup then
        self.providers.msp:wakeup()
    end

    if phase == 1
        and self.providers.smart
        and self.providers.smart.wakeup
        and session:get("postConnectComplete", false) == true
        and type(session:get("batteryConfig", nil)) == "table"
    then
        self.providers.smart:wakeup()
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
