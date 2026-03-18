--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Shared runtime bootstrap for Ethos app, background task, and widgets.
]] --

local framework = require("framework.core.init")
local App = require("app.app")
local LoggerTask = require("tasks.logger")
local MSPTask = require("tasks.msp")
local LifecycleTask = require("tasks.lifecycle")
local TelemetryTask = require("tasks.telemetry")
local FlightModeTask = require("tasks.flightmode")
local SensorsTask = require("tasks.sensors")
local TimerTask = require("tasks.timer")
local AudioTask = require("tasks.audio")

local runtime = {}
runtime._backgroundStatusValues = {}
runtime._backgroundStatusResult = {}

runtime.config = {
    toolName = "Rotorflight",
    version = "2.4.0",
    ethosVersion = {1, 6, 2},
    baseDir = "rfsuite",
    preferences = "rfsuite.user",
    preferencesDefaults = {
        general = {
            debugMode = false,
            enableProfiling = false
        },
        developer = {
            memstats = false,
            taskprofiler = false,
            apiversion = 2,
            logmsp = false,
            loglevel = "info"
        },
        events = {
            armflags = true,
            governor = true,
            voltage = true,
            pid_profile = true,
            rate_profile = true,
            temp_esc = false,
            escalertvalue = 90,
            adj_f = true,
            adj_v = true,
            smartfuel = true,
            smartfuelcallout = 0,
            smartfuelrepeats = 1,
            smartfuelhaptic = false,
            battery_profile = true,
            otherModelAnnounce = false
        },
        timer = {
            timeraudioenable = false,
            elapsedalertmode = 0,
            prealerton = false,
            prealertperiod = 30,
            prealertinterval = 10,
            postalerton = false,
            postalertperiod = 60,
            postalertinterval = 10
        }
    },
    supportedMspApiVersion = {"12.08", "12.09", "12.10"},
    msp = {
        probeProtocol = 1,
        maxProtocol = 2,
        allowAutoUpgrade = true,
        minApiVersion = {12, 0, 8},
        v2MinApiVersion = {12, 0, 9},
        probeRetryDelay = 0.75,
        probeWarmupSport = 0.35,
        probeWarmupCrsf = 0.10,
        connectWatchdogTimeout = 10.0,
        connectWatchdogCooldown = 3.0
    },
    taskScheduler = {
        maxLoopMs = 8,
        maxNormalTasksPerWakeup = 2
    },
    mspProtocolVersion = 1,
    bgTaskName = "Rotorflight [Background]",
    bgTaskKey = "rf2bg",
    developer = {
        memstats = true,
        taskprofiler = false,
        loglevel = "info",
        logMemoryStats = false,
        dumpInterval = 0,
        minDuration = 0,
        idleGcEnabled = true,
        idleGcInterval = 0.75,
        idleGcStepK = 32
    },
    backgroundWatchdog = {
        staleAfter = 0.75,
        missingAfter = 3.0
    }
}

runtime.icon = lcd and lcd.loadMask and lcd.loadMask("app/gfx/icon.png") or nil
runtime.framework = framework

local function seedSession(fw)
    fw.session:setMultiple({
        toolName = runtime.config.toolName,
        backgroundTaskName = runtime.config.bgTaskName,
        backgroundRegistered = fw.session:get("backgroundRegistered", false),
        backgroundWakeups = fw.session:get("backgroundWakeups", 0),
        backgroundLastWakeupAt = fw.session:get("backgroundLastWakeupAt", 0),
        backgroundLastObservedAt = fw.session:get("backgroundLastObservedAt", 0),
        backgroundState = fw.session:get("backgroundState", "waiting"),
        backgroundHealthy = fw.session:get("backgroundHealthy", false),
        backgroundAge = fw.session:get("backgroundAge", 0),
        appWakeups = fw.session:get("appWakeups", 0),
        telemetryVoltage = fw.session:get("telemetryVoltage", 0),
        telemetryCurrent = fw.session:get("telemetryCurrent", 0),
        telemetryTemperature = fw.session:get("telemetryTemperature", 0),
        telemetryUpdates = fw.session:get("telemetryUpdates", 0),
        telemetryType = fw.session:get("telemetryType", "disconnected"),
        telemetrySourcePresent = fw.session:get("telemetrySourcePresent", false),
        telemetryLinkActive = fw.session:get("telemetryLinkActive", false),
        telemetryState = fw.session:get("telemetryState", false),
        telemetryConfig = fw.session:get("telemetryConfig", nil),
        crsfTelemetryMode = fw.session:get("crsfTelemetryMode", 0),
        crsfTelemetryLinkRate = fw.session:get("crsfTelemetryLinkRate", 0),
        crsfTelemetryLinkRatio = fw.session:get("crsfTelemetryLinkRatio", 0),
        isConnected = fw.session:get("isConnected", false),
        isConnecting = fw.session:get("isConnecting", false),
        isArmed = fw.session:get("isArmed", false),
        mcu_id = fw.session:get("mcu_id", nil),
        fcVersion = fw.session:get("fcVersion", nil),
        rfVersion = fw.session:get("rfVersion", nil),
        flightMode = fw.session:get("flightMode", nil),
        currentFlightMode = fw.session:get("currentFlightMode", nil),
        sensorStats = fw.session:get("sensorStats", nil),
        timer = fw.session:get("timer", nil),
        flightCounted = fw.session:get("flightCounted", nil),
        defaultRateProfile = fw.session:get("defaultRateProfile", nil),
        defaultRateProfileName = fw.session:get("defaultRateProfileName", nil),
        modelPreferences = fw.session:get("modelPreferences", nil),
        modelPreferencesFile = fw.session:get("modelPreferencesFile", nil),
        connectionState = fw.session:get("connectionState", "disconnected"),
        connectionTransport = fw.session:get("connectionTransport", "disconnected"),
        connectionToken = fw.session:get("connectionToken", 0),
        connectionReason = fw.session:get("connectionReason", "startup"),
        connectionLastChangedAt = fw.session:get("connectionLastChangedAt", 0),
        connectionStartedAt = fw.session:get("connectionStartedAt", 0),
        connectionLastEvent = fw.session:get("connectionLastEvent", "startup"),
        connectCount = fw.session:get("connectCount", 0),
        disconnectCount = fw.session:get("disconnectCount", 0),
        lifecycleActive = fw.session:get("lifecycleActive", false),
        lifecycleEvent = fw.session:get("lifecycleEvent", "idle"),
        lifecycleHook = fw.session:get("lifecycleHook", "idle"),
        lifecycleRunToken = fw.session:get("lifecycleRunToken", 0),
        lifecyclePendingCount = fw.session:get("lifecyclePendingCount", 0),
        lifecycleLastQueuedEvent = fw.session:get("lifecycleLastQueuedEvent", "none"),
        lifecycleLastCompletedEvent = fw.session:get("lifecycleLastCompletedEvent", "none"),
        lifecycleLastCompletedAt = fw.session:get("lifecycleLastCompletedAt", 0),
        lifecycleLastStartedAt = fw.session:get("lifecycleLastStartedAt", 0),
        postConnectComplete = fw.session:get("postConnectComplete", false),
        postConnectTransport = fw.session:get("postConnectTransport", "disconnected"),
        postConnectApiVersion = fw.session:get("postConnectApiVersion", nil),
        postConnectProtocolVersion = fw.session:get("postConnectProtocolVersion", runtime.config.mspProtocolVersion),
        postConnectAt = fw.session:get("postConnectAt", 0),
        postConnectToken = fw.session:get("postConnectToken", 0),
        lastTransportChangeAt = fw.session:get("lastTransportChangeAt", 0),
        lastTransportOld = fw.session:get("lastTransportOld", "disconnected"),
        lastTransportNew = fw.session:get("lastTransportNew", "disconnected"),
        mspQueueDepth = fw.session:get("mspQueueDepth", 0),
        mspBusy = fw.session:get("mspBusy", false),
        mspProtocolVersion = fw.session:get("mspProtocolVersion", runtime.config.mspProtocolVersion),
        apiVersion = fw.session:get("apiVersion", nil),
        apiVersionInvalid = fw.session:get("apiVersionInvalid", false),
        logQueueDepth = fw.session:get("logQueueDepth", 0),
        logConnectDepth = fw.session:get("logConnectDepth", 0),
        logDroppedConsole = fw.session:get("logDroppedConsole", 0),
        logDroppedConnect = fw.session:get("logDroppedConnect", 0),
        logLevel = fw.session:get("logLevel", runtime.config.developer.loglevel or "info"),
        profilerEnabled = fw.session:get("profilerEnabled", false),
        luaMemoryKB = fw.session:get("luaMemoryKB", 0),
        luaMemoryPeakKB = fw.session:get("luaMemoryPeakKB", 0),
        luaMemoryDeltaKB = fw.session:get("luaMemoryDeltaKB", 0),
        taskLoopLastMs = fw.session:get("taskLoopLastMs", 0),
        taskLoopAvgMs = fw.session:get("taskLoopAvgMs", 0),
        taskLoopMaxMs = fw.session:get("taskLoopMaxMs", 0),
        topTaskName = fw.session:get("topTaskName", "n/a"),
        topTaskAvgMs = fw.session:get("topTaskAvgMs", 0)
    })
end

function runtime.ensureFramework()
    if framework._initialized then
        return framework
    end

    framework:init(runtime.config)

    framework:registerTask("logger", LoggerTask, {
        priority = 5,
        interval = 0.10,
        enabled = true
    })

    framework:registerTask("msp", MSPTask, {
        priority = 25,
        interval = 0.05,
        critical = true,
        enabled = true
    })

    framework:registerTask("lifecycle", LifecycleTask, {
        priority = 20,
        interval = 0.05,
        critical = true,
        enabled = true
    })

    framework:registerTask("telemetry", TelemetryTask, {
        priority = 15,
        interval = 0.10,
        enabled = true
    })

    framework:registerTask("flightmode", FlightModeTask, {
        priority = 14,
        interval = 0.10,
        enabled = true
    })

    framework:registerTask("sensors", SensorsTask, {
        priority = 10,
        interval = 0.05,
        enabled = true
    })

    framework:registerTask("timer", TimerTask, {
        priority = 9,
        interval = 0.25,
        enabled = true
    })

    framework:registerTask("audio", AudioTask, {
        priority = 8,
        interval = 0.10,
        enabled = true
    })

    framework:registerApp(App)
    seedSession(framework)

    framework.log:connect("Framework initialized")
    framework:printStats()

    return framework
end

function runtime.backgroundStatus()
    local fw = runtime.ensureFramework()
    local session = fw.session
    local now = os.clock()
    local lastWakeupAt = session:get("backgroundLastWakeupAt", 0)
    local registered = session:get("backgroundRegistered", false)
    local wakeups = session:get("backgroundWakeups", 0)
    local age = wakeups > 0 and (now - lastWakeupAt) or math.huge
    local state = "waiting"
    local healthy = false
    local values = runtime._backgroundStatusValues
    local result = runtime._backgroundStatusResult

    if registered and wakeups > 0 then
        if age <= runtime.config.backgroundWatchdog.staleAfter then
            state = "running"
            healthy = true
        elseif age <= runtime.config.backgroundWatchdog.missingAfter then
            state = "stale"
        else
            state = "missing"
        end
    elseif registered then
        state = "starting"
    end

    values.backgroundLastObservedAt = now
    values.backgroundState = state
    values.backgroundHealthy = healthy
    values.backgroundAge = (age == math.huge) and -1 or age
    session:setMultiple(values)

    result.state = state
    result.healthy = healthy
    result.age = age
    return result
end

function runtime.openApp()
    local fw = runtime.ensureFramework()

    if not fw:isAppActive() then
        fw:activateApp()
    end
    fw.session:set("uiOpen", true)
    return fw
end

function runtime.closeApp()
    local fw = runtime.ensureFramework()

    if fw:isAppActive() then
        fw:deactivateApp()
    end
    fw.session:set("uiOpen", false)
    return fw
end

function runtime.wakeupBackground()
    local fw = runtime.ensureFramework()
    local now = os.clock()
    fw.session:setMultiple({
        backgroundRegistered = true,
        backgroundWakeups = fw.session:get("backgroundWakeups", 0) + 1,
        backgroundLastWakeupAt = now,
        backgroundState = "running",
        backgroundHealthy = true,
        backgroundAge = 0
    })
    fw:wakeupTasks()
    return fw
end

function runtime.wakeupApp()
    local fw = runtime.openApp()
    fw.session:set("appWakeups", fw.session:get("appWakeups", 0) + 1)
    runtime.backgroundStatus()
    fw:wakeupApp()
    return fw
end

function runtime.paintApp()
    local fw = runtime.openApp()
    runtime.backgroundStatus()
    fw:paintApp()
    return fw
end

return runtime
