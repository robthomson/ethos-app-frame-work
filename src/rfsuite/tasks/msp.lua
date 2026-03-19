--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local MSPTask = {}

local protocols = require("tasks.mspcore.protocols")
local codecFactory = require("tasks.mspcore.codec")
local queueFactory = require("tasks.mspcore.queue")
local sportTransportFactory = require("tasks.mspcore.transport_sport")
local crsfTransportFactory = require("tasks.mspcore.transport_crsf")
local mspHelper = require("mspapi.helper")
local mspRegistry = require("mspapi.registry")
local mspApiCore = require("mspapi.core")
local mspApiFactory = require("mspapi.factory")
local utils = require("lib.utils")
local LIFECYCLE_ALIASES = {
    connected = "onconnect",
    disconnected = "ondisconnect",
    transportChanged = "ontransportchange"
}

local function summarizeBytes(buffer, limit)
    local values = {}
    local maxItems = tonumber(limit) or 24
    local index
    local count

    if type(buffer) ~= "table" then
        return ""
    end

    count = #buffer
    for index = 1, math.min(count, maxItems) do
        values[#values + 1] = tostring(buffer[index])
    end

    if count > maxItems then
        values[#values + 1] = "..."
    end

    return table.concat(values, ",")
end

local function splitVersionStringToNumbers(versionString)
    local parts = {0}

    if not versionString then
        return nil
    end

    for token in tostring(versionString):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(token)
    end

    return parts
end

local function moduleEnabled(module)
    if not module or not module.enable then
        return false
    end

    local ok, enabled = pcall(module.enable, module)
    return ok and enabled == true
end

local function getModule(index)
    if not model or not model.getModule then
        return nil
    end

    local ok, module = pcall(model.getModule, index)
    if ok then
        return module
    end

    return nil
end

local function getSource(descriptor)
    if not system or not system.getSource then
        return nil
    end

    local ok, source = pcall(system.getSource, descriptor)
    if ok then
        return source
    end

    return nil
end

local function getSourceState(source)
    local ok
    local state

    if not source or type(source.state) ~= "function" then
        return nil
    end

    ok, state = pcall(source.state, source)
    if ok then
        return state
    end

    return nil
end

local function versionParts(value)
    local parts = {}
    for token in tostring(value):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(token)
    end
    return parts
end

local function versionGe(a, b)
    local left = versionParts(a)
    local right = versionParts(b)
    local len = math.max(#left, #right)
    local i

    for i = 1, len do
        local lv = left[i] or 0
        local rv = right[i] or 0
        if lv ~= rv then
            return lv > rv
        end
    end

    return true
end

function MSPTask:_clearLinkSession()
    self.framework.session:setMultiple({
        apiVersionInvalid = false,
        apiProbeState = "idle",
        apiProbeStartedAt = 0,
        apiProbeReadyAt = 0,
        apiProbeRetryAt = 0,
        telemetryType = "disconnected",
        telemetrySourcePresent = false,
        telemetryLinkActive = false,
        telemetryState = false,
        isConnected = false,
        isConnecting = false,
        mspBusy = false,
        mspQueueDepth = 0,
        mspTransport = "disconnected",
        connectionTransport = "disconnected",
        mspProtocolVersion = self.framework.config.mspProtocolVersion or 1
    })

    self.framework.session:clearKeys({
        "apiVersion",
        "telemetrySensor",
        "telemetryModule",
        "telemetryModuleNumber",
        "telemetryConfig",
        "crsfTelemetryMode",
        "crsfTelemetryLinkRate",
        "crsfTelemetryLinkRatio",
        "fcVersion",
        "rfVersion",
        "mcu_id",
        "modelPreferences",
        "modelPreferencesFile",
        "flightMode",
        "currentFlightMode",
        "sensorStats",
        "timer",
        "flightCounted",
        "defaultRateProfile",
        "defaultRateProfileName"
    })
end

function MSPTask:_probeWarmupDelay()
    local policy = self.framework.config.msp or {}

    if system and system.getVersion and system.getVersion().simulation then
        return 0
    end

    if self.telemetryType == "sport" then
        return policy.probeWarmupSport or 0.35
    end

    if self.telemetryType == "crsf" then
        return policy.probeWarmupCrsf or 0.10
    end

    return 0
end

function MSPTask:_isMspLoggingEnabled()
    local developer = self.framework and self.framework.preferences and self.framework.preferences:section("developer", {}) or {}
    return developer.logmsp == true
end

function MSPTask:_logMspTraffic(kind, message, payload, extra)
    local command
    local apiName
    local data

    if self:_isMspLoggingEnabled() ~= true then
        return
    end

    command = message and message.command or "?"
    apiName = message and message.apiName or message and message.apiname or nil

    if kind == "tx" then
        data = summarizeBytes(payload, 24)
        self.framework.log:info(
            "[msp] tx cmd=%s api=%s payload=[%s]",
            tostring(command),
            tostring(apiName or "-"),
            data
        )
    elseif kind == "rx" then
        data = summarizeBytes(payload, 24)
        self.framework.log:info(
            "[msp] rx cmd=%s api=%s error=%s payload=[%s]",
            tostring(command),
            tostring(apiName or "-"),
            tostring(extra == true),
            data
        )
    elseif kind == "timeout" then
        self.framework.log:warn(
            "[msp] %s cmd=%s api=%s",
            tostring(extra or "timeout"),
            tostring(command),
            tostring(apiName or "-")
        )
    end
end

function MSPTask:_armApiProbe(now)
    local startedAt = now or os.clock()

    self.pendingApiProbe = true
    self.connectNotBefore = startedAt + self:_probeWarmupDelay()
    self.nextProbeRetryAt = 0
    self.lastProbeWaitReason = nil
    self.framework.session:setMultiple({
        apiProbeState = "armed",
        apiProbeStartedAt = startedAt,
        apiProbeReadyAt = self.connectNotBefore,
        apiProbeRetryAt = 0
    })
end

function MSPTask:_setProbeWait(reason, message, ...)
    if self.lastProbeWaitReason == reason then
        return
    end

    self.lastProbeWaitReason = reason
    self.framework.session:set("apiProbeState", reason or "waiting")
    if message then
        self.framework.log:connect(message, ...)
    end
end

function MSPTask:_resetSubsystem()
    self.apiProbeInFlight = false
    self.connecting = false
    self.connected = false
    self.pendingApiProbe = false
    self.connectNotBefore = 0
    self.nextProbeRetryAt = 0
    self.connectAttemptStartedAt = nil
    self.lastProbeWaitReason = nil
    self.framework.session:setMultiple({
        apiProbeState = "idle",
        apiProbeStartedAt = 0,
        apiProbeReadyAt = 0,
        apiProbeRetryAt = 0
    })

    if self.codec then
        self.codec:clear()
    end
    if self.queue then
        self.queue:clear()
    end
    if self.transport and self.transport.reset then
        self.transport:reset()
    end
    if self.api and self.api.resetData then
        self.api:resetData()
    end

    self:_clearLinkSession()
end

function MSPTask:_emitLifecycle(eventName, payload)
    local alias = LIFECYCLE_ALIASES[eventName]

    self.framework:_emit("msp:" .. eventName, payload)
    if alias then
        self.framework:_emit(alias, payload)
    end
end

function MSPTask:_setConnectionState(state, updates)
    local values = updates or {}

    values.connectionState = state
    values.isConnected = (state == "connected")
    values.isConnecting = (state == "connecting")
    values.connectionTransport = values.connectionTransport or self.telemetryType or "disconnected"
    values.mspTransport = values.mspTransport or self.telemetryType or "disconnected"
    values.connectionLastChangedAt = values.connectionLastChangedAt or os.clock()

    self.framework.session:setMultiple(values)
end

function MSPTask:_beginConnecting(now, reason)
    local session = self.framework.session
    local payload

    if self.connecting or self.connected or not self.telemetryType then
        return
    end

    self.connecting = true
    self.connected = false
    self.connectAttemptStartedAt = now or os.clock()

    self:_setConnectionState("connecting", {
        connectionStartedAt = now,
        connectionReason = reason or "transport_detected"
    })

    payload = {
        transport = self.telemetryType,
        reason = reason or "transport_detected",
        at = now
    }

    self.framework.log:connect("Connection")
    self.framework.log:connect("Transport: %s", tostring(self.telemetryType or "disconnected"))
    self:_armApiProbe(now)
    session:set("connectionLastEvent", "connecting")
    self:_emitLifecycle("connecting", payload)
end

function MSPTask:_markConnected(now, details)
    local session = self.framework.session
    local token
    local payload

    if self.connected and session:get("connectionState", "disconnected") == "connected" then
        return
    end

    self.connectionToken = (self.connectionToken or 0) + 1
    token = self.connectionToken
    self.connecting = false
    self.connected = true

    self:_setConnectionState("connected", {
        connectionToken = token,
        connectionStartedAt = session:get("connectionStartedAt", now),
        connectCount = session:get("connectCount", 0) + 1
    })

    payload = {
        transport = self.telemetryType,
        apiVersion = details and details.apiVersion or session:get("apiVersion", nil),
        protocolVersion = details and details.protocolVersion or session:get("mspProtocolVersion", 1),
        invalid = details and details.invalid or session:get("apiVersionInvalid", false),
        connectionToken = token,
        at = now
    }

    self.framework.log:connect("Connected")
    self.pendingApiProbe = false
    self.connectNotBefore = 0
    self.nextProbeRetryAt = 0
    self.connectAttemptStartedAt = nil
    self.lastProbeWaitReason = nil
    session:setMultiple({
        apiProbeState = "connected",
        apiProbeRetryAt = 0,
        apiProbeReadyAt = 0
    })
    session:set("connectionLastEvent", "connected")
    self:_emitLifecycle("connected", payload)
end

function MSPTask:_markDisconnected(reason, now, details)
    local session = self.framework.session
    local previousState = session:get("connectionState", "disconnected")
    local payload

    if previousState == "disconnected" and not self.connected and not self.connecting then
        return
    end

    payload = {
        reason = reason or "telemetry_lost",
        oldTransport = details and details.oldTransport or self.telemetryType or session:get("connectionTransport", "disconnected"),
        newTransport = details and details.newTransport or "disconnected",
        apiVersion = session:get("apiVersion", nil),
        protocolVersion = session:get("mspProtocolVersion", self.framework.config.mspProtocolVersion or 1),
        connectionToken = session:get("connectionToken", 0),
        at = now
    }

    self.connecting = false
    self.connected = false
    self.connectAttemptStartedAt = nil
    self.lastProbeWaitReason = nil
    session:setMultiple({
        apiProbeState = "idle",
        apiProbeStartedAt = 0,
        apiProbeReadyAt = 0,
        apiProbeRetryAt = 0
    })

    self:_setConnectionState("disconnected", {
        connectionReason = reason or "telemetry_lost",
        connectionTransport = "disconnected",
        mspTransport = "disconnected",
        disconnectCount = session:get("disconnectCount", 0) + 1
    })

    self.framework.log:connect("Disconnected: %s", tostring(reason or "telemetry_lost"))
    session:set("connectionLastEvent", "disconnected")
    self:_emitLifecycle("disconnected", payload)
end

function MSPTask:_selectTransport(telemetryType)
    local protocol

    self.transport = nil
    self.protocol = nil

    if not telemetryType then
        return
    end

    protocol = protocols.resolve(telemetryType)
    self.protocol = protocol
    if not protocol then
        return
    end

    if telemetryType == "sport" then
        self.transport = sportTransportFactory.new(self.framework.session)
    elseif telemetryType == "crsf" then
        self.transport = crsfTransportFactory.new()
    end

    self.queue:configure(protocol)
end

function MSPTask:_getTelemetryActiveSource()
    if self.telemetryActiveSource ~= nil then
        return self.telemetryActiveSource
    end

    if CATEGORY_SYSTEM_EVENT == nil or TELEMETRY_ACTIVE == nil then
        self.telemetryActiveSource = false
        return nil
    end

    self.telemetryActiveSource = getSource({
        category = CATEGORY_SYSTEM_EVENT,
        member = TELEMETRY_ACTIVE
    }) or false

    if self.telemetryActiveSource == false then
        return nil
    end

    return self.telemetryActiveSource
end

function MSPTask:_isRfLinkActive(hasTelemetrySource)
    local source
    local state

    if system and system.getVersion and system.getVersion().simulation then
        return self:_isSimulatorTelemetryActive()
    end

    if hasTelemetrySource ~= true then
        return false
    end

    source = self:_getTelemetryActiveSource()
    state = getSourceState(source)

    if type(state) == "boolean" then
        return state
    end

    return true
end

function MSPTask:_isSimulatorTelemetryActive()
    local value = utils.simSensors("simevent_telemetry_state")

    if value == nil then
        return true
    end

    return tonumber(value) == 0
end

function MSPTask:_detectTelemetry()
    local internalModule = getModule(0)
    local externalModule = getModule(1)
    local sportSource = {appId = 0xF101, subId = 0}
    local crsfSource = {crsfId = 0x14, subIdStart = 0, subIdEnd = 1}

    if system and system.getVersion and system.getVersion().simulation then
        return "sport", nil, nil, 0
    end

    if moduleEnabled(externalModule) then
        local crsfSensor = getSource(crsfSource)
        if crsfSensor then
            return "crsf", crsfSensor, externalModule, 1
        end

        local sportSensor = getSource(sportSource)
        if sportSensor then
            return "sport", sportSensor, externalModule, 1
        end
    end

    if moduleEnabled(internalModule) then
        local sportSensor = getSource(sportSource)
        if sportSensor then
            return "sport", sportSensor, internalModule, 0
        end
    end

    return nil, nil, nil, nil
end

function MSPTask:_updateTelemetryState()
    local session = self.framework.session
    local now = os.clock()
    local telemetryType, telemetrySensor, telemetryModule, telemetryModuleNumber = self:_detectTelemetry()
    local usingSimulator = system and system.getVersion and system.getVersion().simulation == true
    local hasTelemetrySource = telemetrySensor ~= nil or (usingSimulator and telemetryType ~= nil)
    local rfLinkActive = self:_isRfLinkActive(hasTelemetrySource)
    local linkRestored = hasTelemetrySource and rfLinkActive and self.rfLinkActive ~= true
    local transportChanged = telemetryType ~= self.telemetryType
    local oldTransport = self.telemetryType
    local values = self._telemetryStateValues

    if transportChanged then
        if oldTransport ~= nil then
            self:_markDisconnected(telemetryType and "transport_changed" or "telemetry_lost", now, {
                oldTransport = oldTransport,
                newTransport = telemetryType or "disconnected"
            })
        end

        self.telemetryType = telemetryType
        self:_resetSubsystem()
        self:_selectTransport(telemetryType)

        self.framework:_emit("msp:transport", telemetryType or "disconnected")
        if telemetryType then
            self.framework.log:connect("Transport detected: %s", telemetryType)
        end
        self:_emitLifecycle("transportChanged", {
            oldTransport = oldTransport or "disconnected",
            newTransport = telemetryType or "disconnected",
            at = now
        })

        if telemetryType and rfLinkActive then
            self:_beginConnecting(now, oldTransport and "transport_changed" or "transport_detected")
        end
    end

    if linkRestored and not transportChanged then
        self:_resetSubsystem()
        self:_selectTransport(telemetryType)
    end

    values.telemetryType = rfLinkActive and (telemetryType or "disconnected") or "disconnected"
    values.telemetrySensor = rfLinkActive and telemetrySensor or nil
    values.telemetryModule = rfLinkActive and telemetryModule or nil
    values.telemetryModuleNumber = rfLinkActive and telemetryModuleNumber or nil
    values.telemetrySourcePresent = rfLinkActive and hasTelemetrySource or false
    values.telemetryLinkActive = rfLinkActive
    values.telemetryState = rfLinkActive
    values.mspTransport = rfLinkActive and (telemetryType or "disconnected") or "disconnected"
    values.connectionTransport = rfLinkActive and (telemetryType or "disconnected") or "disconnected"
    session:setMultiple(values)

    if not hasTelemetrySource then
        if self.telemetryType ~= nil then
            self.telemetryType = nil
            self:_resetSubsystem()
        end
        self.rfLinkActive = false
        return false
    end

    if not rfLinkActive then
        if self.rfLinkActive ~= false then
            self.framework.log:connect("RF link lost")
            self:_markDisconnected("rf_link_down", now, {
                oldTransport = self.telemetryType or "disconnected",
                newTransport = self.telemetryType or "disconnected"
            })
            self:_resetSubsystem()
        end
        self.rfLinkActive = false
        return false
    end

    if linkRestored then
        self.framework.log:connect("RF link active")
        self:_beginConnecting(now, self.connected and "rf_link_restored" or "rf_link_active")
    end

    self.rfLinkActive = true
    return true
end

function MSPTask:_probeApiVersion(now)
    local session = self.framework.session
    local policy = self.framework.config.msp or {}
    local supported = self.framework.config.supportedMspApiVersion or {}
    local developerPrefs = self.framework.preferences and self.framework.preferences.developer or {}
    local selectedApiIndex = tonumber(developerPrefs.apiversion) or 1
    local simulatorApiVersion = supported[selectedApiIndex]
    local probeVersion
    local queued
    local queueReason

    if self.pendingApiProbe ~= true then
        return
    end
    if not session:get("telemetryState", false) then
        self:_setProbeWait("telemetry_down")
        return
    end
    if self.connectNotBefore and now < self.connectNotBefore then
        self:_setProbeWait("warmup", "API probe waiting: transport warmup")
        return
    end
    if self.nextProbeRetryAt and now < self.nextProbeRetryAt then
        self:_setProbeWait("retry_delay", "API probe waiting: retry delay")
        return
    end
    if session:get("apiVersion", nil) ~= nil or self.apiProbeInFlight then
        self:_setProbeWait(
            "inflight",
            "API probe waiting: in flight (api=%s, inflight=%s)",
            tostring(session:get("apiVersion", nil)),
            tostring(self.apiProbeInFlight == true)
        )
        return
    end
    if self.queue and (self.queue.current or self.queue:queueCount() > 0) then
        self:_setProbeWait("queue_busy", "API probe waiting: MSP queue busy")
        return
    end

    self.pendingApiProbe = false
    self.apiProbeInFlight = true
    self.lastProbeWaitReason = nil
    probeVersion = policy.probeProtocol or 1
    self.codec:setProtocolVersion(probeVersion)
    session:set("mspProtocolVersion", probeVersion)
    session:setMultiple({
        apiProbeState = "probing",
        apiProbeStartedAt = now,
        apiProbeReadyAt = 0,
        apiProbeRetryAt = 0
    })
    self.framework.log:connect("Probing API Version")

    queued, queueReason = self:queueCommand(1, {}, {
        timeout = 2.0,
        simulatorResponse = splitVersionStringToNumbers(simulatorApiVersion),
        onReply = function(_, buffer)
            local versionString
            local wantProto = probeVersion
            local supportedJoined = table.concat(supported, ",")
            local minApiVersion = policy.minApiVersion or {12, 0, 8}
            local minVersionString = string.format("%d.%02d", minApiVersion[1] or 0, minApiVersion[3] or 0)
            local versionSupported

            if buffer and #buffer >= 3 then
                versionString = string.format("%d.%02d", buffer[2] or 0, buffer[3] or 0)
            end

            versionSupported = versionString ~= nil
                and versionGe(versionString, minVersionString)
                and (supportedJoined == "" or supportedJoined:find(versionString, 1, true) ~= nil)

            session:set("apiVersionInvalid", versionSupported ~= true)

            if versionSupported ~= true then
                self.apiProbeInFlight = false
                self.pendingApiProbe = false
                self.connecting = false
                self.connected = false
                self.nextProbeRetryAt = 0
                self.connectNotBefore = 0
                self.connectAttemptStartedAt = nil
                self.lastProbeWaitReason = nil
                session:setMultiple({
                    apiVersion = nil,
                    isConnected = false,
                    isConnecting = false,
                    apiProbeState = "unsupported",
                    apiProbeRetryAt = 0,
                    apiProbeReadyAt = 0,
                    connectionState = "disconnected",
                    connectionReason = "unsupported_api_version",
                    connectionTransport = self.telemetryType or "disconnected",
                    mspTransport = self.telemetryType or "disconnected",
                    connectionLastChangedAt = os.clock()
                })
                self.framework.log:connect(
                    "Unsupported API Version: %s (requires %s or newer)",
                    tostring(versionString or "unknown"),
                    minVersionString
                )
                self.framework:_emit("msp:apiVersion", {
                    apiVersion = versionString,
                    protocolVersion = probeVersion,
                    invalid = true,
                    unsupported = true
                })
                return
            end

            if versionString and policy.allowAutoUpgrade and (policy.maxProtocol or 1) >= 2 then
                local minVersion = string.format("%d.%02d", policy.v2MinApiVersion[1] or 0, policy.v2MinApiVersion[3] or 0)
                if versionGe(versionString, minVersion) then
                    wantProto = 2
                end
            end

            session:set("apiVersion", versionString)
            session:set("mspProtocolVersion", wantProto)
            session:set("isConnected", versionString ~= nil)
            self.codec:setProtocolVersion(wantProto)
            self.apiProbeInFlight = false
            self.nextProbeRetryAt = 0
            self.connectNotBefore = 0
            session:setMultiple({
                apiProbeState = versionString and "reply" or "empty_reply",
                apiProbeRetryAt = 0,
                apiProbeReadyAt = 0
            })
            if versionString then
                self.framework.log:connect("API Version: %s", versionString)
            end
            if versionString and wantProto > probeVersion then
                self.framework.log:connect("Upgrading MSP Protocol: v%d -> v%d", probeVersion, wantProto)
            end
            if versionString then
                self:_markConnected(os.clock(), {
                    apiVersion = versionString,
                    protocolVersion = wantProto,
                    invalid = session:get("apiVersionInvalid", false)
                })
            end
            self.framework:_emit("msp:apiVersion", {
                apiVersion = versionString,
                protocolVersion = wantProto,
                invalid = session:get("apiVersionInvalid", false)
            })
        end,
        onError = function()
            self.apiProbeInFlight = false
            self.framework.log:connect("API Version probe failed")
            if self.connecting and session:get("telemetryState", false) then
                self.pendingApiProbe = true
                self.nextProbeRetryAt = os.clock() + (policy.probeRetryDelay or 0.75)
                session:setMultiple({
                    apiProbeState = "retry_delay",
                    apiProbeRetryAt = self.nextProbeRetryAt
                })
            end
        end,
        onExpire = function(_, reason, expireCount, maxExpireCount)
            self.framework.log:connect(
                "API Version probe expired: %s (%d/%d)",
                tostring(reason or "timeout"),
                tonumber(expireCount) or 0,
                tonumber(maxExpireCount) or 0
            )
        end
    })

    if queued ~= true then
        self.apiProbeInFlight = false
        self.pendingApiProbe = true
        self.nextProbeRetryAt = os.clock() + (policy.probeRetryDelay or 0.75)
        self.lastProbeWaitReason = nil
        session:setMultiple({
            apiProbeState = "retry_delay",
            apiProbeRetryAt = self.nextProbeRetryAt
        })
        self.framework.log:connect("API Version probe queue failed: %s", tostring(queueReason or "unknown"))
    end
end

function MSPTask:_checkConnectWatchdog(now)
    local session = self.framework.session
    local policy = self.framework.config.msp or {}
    local timeout = tonumber(policy.connectWatchdogTimeout) or 10.0
    local cooldown = tonumber(policy.connectWatchdogCooldown) or 3.0
    local startedAt
    local elapsed

    if self.connected or self.connecting ~= true then
        self.connectAttemptStartedAt = nil
        return false
    end

    if session:get("telemetryState", false) ~= true or not self.telemetryType then
        self.connectAttemptStartedAt = nil
        return false
    end

    if now < (self.connectWatchdogCooldownUntil or 0) then
        return false
    end

    startedAt = self.connectAttemptStartedAt or now
    self.connectAttemptStartedAt = startedAt
    elapsed = now - startedAt

    if elapsed < timeout then
        return false
    end

    self.framework.log:connect(
        "Connect watchdog: stalled for %.1fs, resetting MSP",
        elapsed
    )

    self.connectWatchdogCooldownUntil = now + cooldown
    self:_resetSubsystem()
    self:_selectTransport(self.telemetryType)
    self:_beginConnecting(now, "watchdog_retry")
    return true
end

function MSPTask:init(framework)
    self.framework = framework
    self.telemetryType = nil
    self.telemetryActiveSource = nil
    self.rfLinkActive = false
    self.apiProbeInFlight = false
    self.connecting = false
    self.connected = false
    self.pendingApiProbe = false
    self.connectNotBefore = 0
    self.nextProbeRetryAt = 0
    self.connectAttemptStartedAt = nil
    self.connectWatchdogCooldownUntil = 0
    self.lastProbeWaitReason = nil
    self.connectionToken = 0
    self.codec = codecFactory.new()
    self.queue = queueFactory.new()
    self.queue:setActivityHandler(function(_, now)
        local sensorsTask = self.framework and self.framework.getTask and self.framework:getTask("sensors") or nil
        local mspSensorProvider = sensorsTask and sensorsTask.providers and sensorsTask.providers.msp or nil

        if mspSensorProvider and mspSensorProvider.busyHeartbeat then
            mspSensorProvider:busyHeartbeat(now)
        end
    end)
    self.queue:setLogHandler(function(_, kind, message, payload, extra)
        self:_logMspTraffic(kind, message, payload, extra)
    end)
    self.mspQueue = self.queue
    self.mspHelper = mspHelper
    self.api = mspRegistry
    self.apicore = mspApiCore
    self.apifactory = mspApiFactory
    self.transport = nil
    self.protocol = nil
    self._telemetryStateValues = {}
    self._wakeupValues = {}

    self.framework.session:setMultiple({
        mspQueueDepth = 0,
        mspLastCommand = "idle",
        mspBusy = false,
        mspTransport = "disconnected",
        mspProtocolVersion = self.framework.config.mspProtocolVersion or 1,
        apiProbeState = "idle",
        apiProbeStartedAt = 0,
        apiProbeReadyAt = 0,
        apiProbeRetryAt = 0,
        telemetryType = "disconnected",
        isConnected = false,
        isConnecting = false,
        connectionState = "disconnected",
        connectionTransport = "disconnected",
        connectionToken = 0,
        connectionReason = "startup",
        connectionLastChangedAt = 0,
        connectionStartedAt = 0,
        connectionLastEvent = "startup",
        connectCount = 0,
        disconnectCount = 0,
        apiVersion = nil,
        apiVersionInvalid = false
    })
    self:_clearLinkSession()

    self.codec:setProtocolVersion(self.framework.config.mspProtocolVersion or 1)

    self.framework.log:info("[MSP] Task initialized")
end

function MSPTask:wakeup()
    local now = os.clock()
    local pending
    local active
    local values

    if not self:_updateTelemetryState() then
        return
    end

    self:_checkConnectWatchdog(now)
    self:_probeApiVersion(now)

    if self.transport and self.protocol and self.queue then
        active = self.queue:process(self.transport, self.protocol, self.codec, now)
    end

    pending = self.queue and (self.queue:queueCount() + (self.queue.current and 1 or 0)) or 0
    values = self._wakeupValues
    values.mspQueueDepth = pending
    values.mspBusy = active == true
    values.mspTransport = self.telemetryType or "disconnected"
    values.connectionTransport = self.telemetryType or "disconnected"
    self.framework.session:setMultiple(values)
end

function MSPTask:queueCommand(cmd, payload, options)
    local opts = options or {}
    local message = {
        command = cmd,
        payload = payload or {},
        timeout = opts.timeout,
        simulatorResponse = opts.simulatorResponse,
        expireHandler = function(_, reason, expireCount, maxExpireCount)
            if opts.onExpire then
                opts.onExpire(cmd, reason, expireCount, maxExpireCount)
            end
        end,
        processReply = function(_, buffer, errorFlag)
            self.framework.session:set("mspLastCommand", cmd)
            if opts.onReply then
                opts.onReply(cmd, buffer, errorFlag)
            end
            self.framework:_emit("msp:response", cmd)
        end,
        errorHandler = function(_, reason)
            if opts.onError then
                opts.onError(cmd, reason)
            end
            self.framework:_emit("msp:error", {command = cmd, reason = reason})
        end
    }

    if self.transport and self.telemetryType == "crsf" and self.transport.setWriteMode then
        self.transport:setWriteMode(payload ~= nil and #payload > 0)
    end

    return self.queue:add(message)
end

function MSPTask:close()
    self.framework.log:info("[MSP] Task closing")
    self:_markDisconnected("task_closed", os.clock(), {
        oldTransport = self.telemetryType or "disconnected",
        newTransport = "disconnected"
    })
    self:_resetSubsystem()
    self.framework.session:setMultiple({
        mspQueueDepth = 0,
        mspLastCommand = "closed",
        mspBusy = false,
        mspTransport = "disconnected",
        telemetryType = "disconnected",
        telemetrySourcePresent = false,
        telemetryLinkActive = false,
        telemetryState = false,
        connectionState = "disconnected",
        connectionTransport = "disconnected",
        apiVersion = nil
    })
    self.framework = nil
end

return MSPTask
