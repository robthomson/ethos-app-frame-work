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

function SensorsTask:_resetTelemetryConfigBootstrap()
    self.telemetryConfigReadInFlight = false
    self.telemetryConfigReadRetryAt = 0
end

function SensorsTask:_resetBatteryConfigBootstrap()
    self.batteryConfigReadInFlight = false
    self.batteryConfigReadRetryAt = 0
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
    self:_resetTelemetryConfigBootstrap()
    self:_resetBatteryConfigBootstrap()

    framework:on("ontransportchange", function()
        self:_resetTransportProvider()
        self:_resetTelemetryConfigBootstrap()
        self:_resetBatteryConfigBootstrap()
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
        BatteryConfig.clearSession(self.framework.session)
        if self.providers.smart and self.providers.smart.reset then
            self.providers.smart:reset()
        end
        if self.providers.msp and self.providers.msp.reset then
            self.providers.msp:reset()
        end
    end)
end

function SensorsTask:wakeup()
    local transportProvider = self:_ensureTransportProvider()
    local session = self.framework.session
    local now = os.clock()

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

    if self.providers.msp and self.providers.msp.wakeup then
        self.providers.msp:wakeup()
    end

    if self.providers.smart and self.providers.smart.wakeup then
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
    self:_resetTelemetryConfigBootstrap()
    self:_resetBatteryConfigBootstrap()
    BatteryConfig.clearSession(self.framework.session)
end

function SensorsTask:close()
    self:reset()
    self.framework = nil
end

return SensorsTask
