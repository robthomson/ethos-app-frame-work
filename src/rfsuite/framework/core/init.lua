--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Main Entry Point
  
  Initializes and manages the entire framework.
  Coordinates callbacks, events, registry, and session.
  
  Usage:
    local framework = require("framework")
    framework:init({toolName="Rotorflight", version="1.0"})
    
    function wakeup()
        framework:wakeup()
    end
    
    function paint()
        framework:paint()
    end
]] --

local framework = {}

-- Import framework modules
local callback_mod = require("framework.core.callback")
local preferences_mod = require("framework.core.preferences")
local session_mod = require("framework.core.session")
local events_mod = require("framework.events.events")
local registry_mod = require("framework.core.registry")
local log_mod = require("framework.utils.log")
local profiler_mod = require("framework.utils.profiler")

-- Initialize components
framework.callback = callback_mod
framework.session = session_mod
framework.events = events_mod
framework.registry = registry_mod
framework.log = log_mod
framework.profiler = profiler_mod

-- Configuration
framework.config = {}
framework.preferences = nil

-- Task management
framework._tasks = {}
framework._taskOrder = {}
framework._taskMetadata = {}

-- App management
framework._app = nil
framework._appModule = nil
framework._appLoader = nil
framework._appUnloader = nil
framework._appUnloadOnDeactivate = false
framework._appReleaseOnDeactivate = false
framework._appActive = false

-- State
framework._initialized = false
framework._running = false
framework._profiler = nil
framework._profilerSessionBuffer = {}
framework._profilerLastSyncAt = 0
framework._profilerSessionInitialized = false
framework._profilerSessionSyncInterval = 0.25
framework._memoryDebugHistory = {}
framework._idleGcLastAt = 0
framework._idleGcValues = {}
framework._callbackWakeupOptions = {
    maxCalls = 16,
    budgetMs = 4,
    categories = {"immediate", "timer", "events"}
}
framework._renderCallbackWakeupOptions = {
    maxCalls = 20,
    budgetMs = 8,
    category = "render"
}
framework._taskSchedulerOptions = {
    maxCriticalLoopMs = 4,
    maxLoopMs = 8,
    maxNormalTasksPerWakeup = 3,
    mspBusyBoostEnabled = true,
    mspBusyMaxNormalTasksPerWakeup = 0
}
framework._taskRoundRobinCursor = 1
framework._appBusyUiTick = 0

function framework:_defaultPreferences()
    return {
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
        }
    }
end

local function mergeTableOverrides(base, overrides)
    local merged = {}
    local key
    local value

    for key, value in pairs(base or {}) do
        merged[key] = value
    end

    for key, value in pairs(overrides or {}) do
        merged[key] = value
    end

    return merged
end

local function countKeys(tbl)
    local count = 0

    if type(tbl) ~= "table" then
        return 0
    end

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function sumValues(tbl)
    local total = 0
    local value

    if type(tbl) ~= "table" then
        return 0
    end

    for _, value in pairs(tbl) do
        if type(value) == "number" then
            total = total + value
        end
    end

    return total
end

local function pushHistory(history, entry, limit)
    if type(history) ~= "table" then
        return
    end

    history[#history + 1] = entry
    while #history > (limit or 8) do
        table.remove(history, 1)
    end
end

local function setSessionValues(session, values)
    local setter = session and (session.setMultipleSilent or session.setMultiple)

    if type(setter) ~= "function" then
        return
    end

    pcall(setter, session, values)
end

local function countLoadedModules(prefix)
    local loaded = package and package.loaded or nil
    local count = 0
    local name

    if type(loaded) ~= "table" then
        return 0
    end

    for name in pairs(loaded) do
        if type(name) == "string" and (prefix == nil or name:sub(1, #prefix) == prefix) then
            count = count + 1
        end
    end

    return count
end

local function isTruthy(value)
    return value == true or value == "true"
end

--[[ INITIALIZATION ]]

function framework:init(config)
    self.config = config or {}
    self._initialized = true
    
    -- Initialize preferences file path
    self.config.baseDir = self.config.baseDir or "ethos_framework"
    self.config.prefFile = self.config.prefFile or (((self.config.preferences or self.config.baseDir)) .. "/preferences.ini")
    
    self.preferences = preferences_mod.new({
        path = self.config.prefFile,
        defaults = self.config.preferencesDefaults or self:_defaultPreferences()
    })
    self.config.developer = mergeTableOverrides(self.config.developer or {}, self.preferences:section("developer", {}))
    self.log:init({
        developer = self.config.developer or {},
        minLevel = (self.config.developer and self.config.developer.loglevel) or "info"
    })
    self._profiler = self.profiler.new(self.config.developer or {})
    self._profilerLastSyncAt = 0
    self._profilerSessionInitialized = false
    self._profilerSessionSyncInterval = tonumber((self.config.developer or {}).profilerSessionSyncInterval) or 0.25
    self._idleGcLastAt = 0
    self._taskSchedulerOptions = {
        maxCriticalLoopMs = ((self.config.taskScheduler or {}).maxCriticalLoopMs) or 4,
        maxLoopMs = ((self.config.taskScheduler or {}).maxLoopMs) or 8,
        maxNormalTasksPerWakeup = ((self.config.taskScheduler or {}).maxNormalTasksPerWakeup) or 3,
        mspBusyBoostEnabled = ((self.config.taskScheduler or {}).mspBusyBoostEnabled) ~= false,
        mspBusyMaxNormalTasksPerWakeup = tonumber((self.config.taskScheduler or {}).mspBusyMaxNormalTasksPerWakeup) or 0
    }
    self._taskRoundRobinCursor = 1
    self._appBusyUiTick = 0
    
    -- Initialize session state
    self.session:set("initialized", true)
    self.session:set("appActive", false)
    self.session:setMultiple({
        appResident = false,
        appInactiveAt = 0,
        appCleanupPending = false,
        appCleanupDueAt = 0,
        appCleanupLastAt = 0,
        appCleanupRuns = 0,
        appCleanupReason = "startup",
        idleGcEnabled = self.config.developer and self.config.developer.idleGcEnabled == true or false,
        idleGcLastAt = 0,
        idleGcCycleComplete = false,
        idleGcRuns = 0
    })
    self:_syncProfilerSession(true)
    
    return self
end

function framework:_profileLog(line)
    self.log:info("%s", line)
end

function framework:_syncProfilerSession(force)
    local state = self._profiler
    local values = self._profilerSessionBuffer
    local now = os.clock()
    local syncInterval = tonumber(self._profilerSessionSyncInterval) or 0.25
    local loop = state and state.loop or nil
    local memory = state and state.memory or nil
    local taskCount = 0
    local topTaskName = "n/a"
    local topTaskAvgMs = 0
    local topTaskLastMs = 0
    local topTaskMaxMs = 0
    local enabled = state and state.enabled == true

    if force ~= true then
        if enabled ~= true then
            if self._profilerSessionInitialized == true then
                return
            end
        elseif syncInterval > 0 and (now - (self._profilerLastSyncAt or 0)) < syncInterval then
            return
        end
    end

    if state and state.taskprofiler and state.tasks then
        local bestAvg = nil

        for name, entry in pairs(state.tasks) do
            local runs = entry.runs or 0
            local avg = runs > 0 and ((entry.totalMs or 0) / runs) or 0

            taskCount = taskCount + 1
            if bestAvg == nil or avg > bestAvg then
                bestAvg = avg
                topTaskName = name
                topTaskAvgMs = avg
                topTaskLastMs = entry.lastMs or 0
                topTaskMaxMs = entry.maxMs or 0
            end
        end
    end

    values.profilerEnabled = state and state.enabled or false
    values.profilerMemstats = state and state.memstats or false
    values.profilerTaskprofiler = state and state.taskprofiler or false
    values.profilerTaskCount = taskCount
    values.taskLoopLastMs = loop and loop.lastMs or 0
    values.taskLoopAvgMs = loop and loop.avgMs or 0
    values.taskLoopMaxMs = loop and loop.maxMs or 0
    values.luaMemoryKB = memory and memory.currentKB or 0
    values.luaMemoryPeakKB = memory and memory.peakKB or 0
    values.luaMemoryDeltaKB = memory and memory.deltaKB or 0
    values.systemFreeRamKB = memory and memory.systemFreeKB or 0
    values.luaFreeRamKB = memory and memory.luaFreeKB or 0
    values.topTaskName = topTaskName
    values.topTaskAvgMs = topTaskAvgMs
    values.topTaskLastMs = topTaskLastMs
    values.topTaskMaxMs = topTaskMaxMs

    self.session:setMultipleSilent(values)
    self._profilerLastSyncAt = now
    self._profilerSessionInitialized = true
end

function framework:_runIdleGc(now)
    local developer = self.config and self.config.developer or nil
    local values = self._idleGcValues
    local ok
    local completed

    if type(collectgarbage) ~= "function" then
        return
    end

    if not developer or developer.idleGcEnabled ~= true then
        return
    end

    if self.session:get("mspBusy", false) == true
        or self.session:get("lifecycleActive", false) == true
        or self.session:get("isConnecting", false) == true then
        return
    end

    if (now - (self._idleGcLastAt or 0)) < (tonumber(developer.idleGcInterval) or 0.75) then
        return
    end

    self._idleGcLastAt = now
    ok, completed = pcall(collectgarbage, "step", tonumber(developer.idleGcStepK) or 32)
    if not ok then
        return
    end

    values.idleGcEnabled = true
    values.idleGcLastAt = now
    values.idleGcCycleComplete = completed == true
    values.idleGcRuns = self.session:get("idleGcRuns", 0) + 1
    self.session:setMultiple(values)
end

--[[ APP REGISTRATION ]]

function framework:registerApp(appModule, options)
    options = options or {}
    self._appModule = appModule
    self._appLoader = options.loader
    self._appUnloader = options.unload
    self._appUnloadOnDeactivate = options.unloadOnDeactivate == true
    self._appReleaseOnDeactivate = options.releaseOnDeactivate == true
    self._app = nil
    self.session:set("appRegistered", true)
end

function framework:getApp()
    return self._app
end

function framework:_clearAppScopedCaches()
    local mspMeta = self._taskMetadata and self._taskMetadata.msp or nil
    local mspTask = mspMeta and mspMeta.instance or nil

    if mspTask and mspTask.api and mspTask.api.reset then
        pcall(mspTask.api.reset, mspTask.api)
    elseif mspTask and mspTask.api and mspTask.api.resetData then
        pcall(mspTask.api.resetData, mspTask.api)
    end

    if self.log and self.log.reset then
        pcall(self.log.reset, self.log)
    end

    self._memoryDebugHistory = {}

    setSessionValues(self.session, {
        memDebugLabel = nil,
        memDebugLuaKB = 0,
        memDebugDeltaLuaKB = 0,
        memDebugPackageLoaded = 0,
        memDebugPackageLoadedApp = 0,
        memDebugCallbackQueued = 0,
        memDebugEventHandlers = 0,
        memDebugMspLoaded = 0,
        memDebugMspHelp = 0,
        memDebugMspHelpMiss = 0,
        memDebugMspDataApis = 0,
        memDebugMspDataEntries = 0,
        logQueueDepth = 0,
        logConnectDepth = 0,
        logDroppedConsole = 0,
        logDroppedConnect = 0
    })
end

function framework:_createAppInstance()
    if self._app ~= nil then
        return self._app
    end

    local appModule = self._appModule
    if type(appModule) ~= "table" then
        if type(self._appLoader) == "function" then
            local ok, loaded = pcall(self._appLoader, self)
            if ok then
                appModule = loaded
            else
                self.log:error("Failed to load app module: %s", tostring(loaded))
                return nil
            end
        end
    end

    if type(appModule) ~= "table" then
        return nil
    end

    local instance = setmetatable({}, {__index = appModule})
    if instance.init then
        instance:init(self)
    end

    self._app = instance
    self.session:set("appResident", true)
    return instance
end

function framework:isAppActive()
    return self._appActive
end

function framework:activateApp()
    local now = os.clock()
    self:_createAppInstance()
    self._appActive = true
    self.session:setMultipleSilent({
        appActive = true,
        appInactiveAt = 0,
        appCleanupPending = false,
        appCleanupDueAt = 0,
        appCleanupReason = "active",
        appResident = self._app ~= nil
    })
    
    if self._app and self._app.onActivate then
        self._app:onActivate()
    end
    self:captureMemoryDebug("app_open")
    
    self:_emit("app:activated")
end

function framework:deactivateApp()
    local now = os.clock()
    local delay = tonumber(self.config.app and self.config.app.idleCleanupDelay) or 5.0
    local shouldKeepResident = self._appUnloadOnDeactivate ~= true and self._appReleaseOnDeactivate ~= true and self._app ~= nil

    if self._app and self._app.onDeactivate then
        self._app:onDeactivate()
    end

    self._appActive = false
    self.session:setMultipleSilent({
        appActive = false,
        appInactiveAt = now,
        appCleanupPending = shouldKeepResident,
        appCleanupDueAt = shouldKeepResident and (now + math.max(0, delay)) or 0,
        appCleanupReason = "deactivate"
    })
    
    self:_emit("app:deactivated")

    if self._appUnloadOnDeactivate == true then
        if self._app and self._app.close then
            pcall(self._app.close, self._app)
        end
        self._app = nil
        if type(self._appUnloader) == "function" then
            pcall(self._appUnloader, self)
        end
        self:_clearAppScopedCaches()
        self.session:set("appResident", false)
        collectgarbage("collect")
        collectgarbage("collect")
    elseif self._appReleaseOnDeactivate == true then
        self._app = nil
        self:_clearAppScopedCaches()
        self.session:set("appResident", false)
        collectgarbage("collect")
        collectgarbage("collect")
    else
        self.session:set("appResident", self._app ~= nil)
    end
end

function framework:releaseInactiveApp(reason)
    if self._appActive == true then
        return false
    end

    if self._app and self._app.close then
        pcall(self._app.close, self._app)
    end
    self._app = nil

    if type(self._appUnloader) == "function" then
        pcall(self._appUnloader, self)
    end

    self:_clearAppScopedCaches()

    self.session:setMultipleSilent({
        appResident = false,
        appCleanupPending = false,
        appCleanupDueAt = 0,
        appCleanupReason = reason or "release"
    })
    collectgarbage("collect")
    collectgarbage("collect")
    self:captureMemoryDebug("app_release:" .. tostring(reason or "release"))
    return true
end

--[[ TASK REGISTRATION & SCHEDULING ]]

function framework:registerTask(name, taskClass, options)
    options = options or {}
    
    self._tasks[name] = taskClass
    self._taskMetadata[name] = {
        class = taskClass,
        priority = options.priority or 10,
        interval = options.interval or 0.1,
        lastWakeup = 0,
        critical = options.critical == true,
        enabled = options.enabled ~= false,
        instance = nil
    }
    
    -- Create task instance if not lazy-loaded
    if not options.lazy then
        self:_initializeTask(name)
    end
    
    return name
end

function framework:_initializeTask(name)
    local meta = self._taskMetadata[name]
    if meta.instance then
        return  -- Already initialized
    end
    
    local taskClass = meta.class
    local instance = setmetatable({}, {__index = taskClass})
    
    if instance.init then
        instance:init(self)
    end
    
    meta.instance = instance
    
    -- Add to ordered list by priority
    table.insert(self._taskOrder, {name = name, priority = meta.priority})
    table.sort(self._taskOrder, function(a, b)
        return a.priority > b.priority
    end)
end

function framework:getTask(name)
    local meta = self._taskMetadata[name]
    if not meta then
        return nil
    end
    
    if not meta.instance then
        self:_initializeTask(name)
    end
    
    return meta.instance
end

function framework:listTasks()
    local result = {}
    for name, meta in pairs(self._taskMetadata) do
        table.insert(result, {
            name = name,
            priority = meta.priority,
            critical = meta.critical == true,
            enabled = meta.enabled,
            initialized = meta.instance ~= nil
        })
    end
    return result
end

--[[ EVENT DELEGATION ]]

function framework:on(event, handler)
    return self.events:on(event, handler)
end

function framework:once(event, handler)
    return self.events:once(event, handler)
end

function framework:off(event, handler)
    self.events:off(event, handler)
end

function framework:_emit(event, ...)
    self.events:emit(event, ...)
end

--[[ CALLBACK DELEGATION ]]

function framework:callbackNow(func, category)
    return self.callback:now(func, category)
end

function framework:callbackInSeconds(seconds, func, category)
    return self.callback:inSeconds(seconds, func, category)
end

function framework:callbackEvery(seconds, func, category)
    return self.callback:every(seconds, func, category)
end

--[[ MAIN LOOP COORDINATION ]]

function framework:_taskIsDue(meta, now)
    return meta
        and meta.enabled
        and meta.instance
        and (now - (meta.lastWakeup or 0)) >= (meta.interval or 0)
end

function framework:_runTask(name, meta, now)
    local startedAt = os.clock()
    local ok
    local err
    local duration

    ok, err = pcall(meta.instance.wakeup, meta.instance)
    duration = os.clock() - startedAt

    if self._profiler then
        self.profiler:recordTask(self._profiler, name, meta.interval, duration)
    end

    if not ok then
        self.log:error("Task '%s' wakeup error: %s", name, tostring(err))
    end

    meta.lastWakeup = now
    return duration
end

function framework:_wakeupTasks()
    if not self._initialized then
        return
    end

    local now = os.clock()
    local scheduler = self._taskSchedulerOptions or {}
    local session = self.session
    local mspBusyBoost = scheduler.mspBusyBoostEnabled ~= false
        and session
        and session.get
        and session:get("mspBusy", false) == true
    local criticalDeadline =
        (tonumber(scheduler.maxCriticalLoopMs) or 0) > 0 and (now + ((tonumber(scheduler.maxCriticalLoopMs) or 0) / 1000.0))
        or nil
    local deadline = (tonumber(scheduler.maxLoopMs) or 0) > 0 and (now + ((tonumber(scheduler.maxLoopMs) or 0) / 1000.0)) or nil
    local maxNormalTasks = tonumber(scheduler.maxNormalTasksPerWakeup) or 0
    local normalRan = 0
    local totalTasks = #self._taskOrder
    local checked = 0
    local index
    local taskInfo
    local meta

    if mspBusyBoost == true then
        maxNormalTasks = tonumber(scheduler.mspBusyMaxNormalTasksPerWakeup)
        if maxNormalTasks == nil then
            maxNormalTasks = 0
        end
    end

    for _, taskInfo in ipairs(self._taskOrder) do
        if criticalDeadline and os.clock() >= criticalDeadline then
            break
        end

        local meta = self._taskMetadata[taskInfo.name]
        if meta and meta.critical == true and self:_taskIsDue(meta, now) then
            self:_runTask(taskInfo.name, meta, now)
        end
    end

    if totalTasks <= 0 or maxNormalTasks <= 0 then
        return
    end

    index = self._taskRoundRobinCursor or 1
    if index < 1 or index > totalTasks then
        index = 1
    end

    while checked < totalTasks and normalRan < maxNormalTasks do
        if deadline and os.clock() >= deadline then
            break
        end

        taskInfo = self._taskOrder[index]
        meta = taskInfo and self._taskMetadata[taskInfo.name] or nil
        if meta and meta.critical ~= true and self:_taskIsDue(meta, now) then
            self:_runTask(taskInfo.name, meta, now)
            normalRan = normalRan + 1
        end

        index = index + 1
        if index > totalTasks then
            index = 1
        end
        checked = checked + 1
    end

    self._taskRoundRobinCursor = index
end

function framework:_wakeupApp()
    if not self._initialized then
        return
    end

    local session = self.session
    local appConfig = self.config and self.config.app or {}
    local runNum = tonumber(appConfig.mspBusyUiRunNum) or 2
    local runDen = tonumber(appConfig.mspBusyUiRunDen) or 3
    local shouldRun = true

    if runNum < 0 then runNum = 0 end
    if runDen < 1 then runDen = 1 end
    if runNum > runDen then runNum = runDen end

    if session and session.get and session:get("mspBusy", false) == true then
        self._appBusyUiTick = ((self._appBusyUiTick or 0) % runDen) + 1
        shouldRun = self._appBusyUiTick <= runNum
    else
        self._appBusyUiTick = 0
    end

    if shouldRun ~= true then
        return
    end

    if self._appActive and self._app and self._app.wakeup then
        local ok, err = pcall(self._app.wakeup, self._app)
        if not ok then
            self.log:error("App wakeup error: %s", tostring(err))
        end
    end
end

function framework:wakeupTasks()
    if not self._initialized then
        return
    end

    local profilerEnabled = self._profiler and self._profiler.enabled == true
    local loopToken = profilerEnabled and self.profiler:beginLoop(self._profiler) or nil
    self:_wakeupTasks()
    self.callback:wakeup(self._callbackWakeupOptions)
    self:_runIdleGc(os.clock())

    if profilerEnabled then
        self.profiler:endLoop(self._profiler, loopToken)
        self:_syncProfilerSession()
    end
end

function framework:wakeupApp()
    self:_wakeupApp()
end

function framework:dispatchAppEvent(category, value, x, y)
    if not self._initialized or not self._appActive or not self._app or not self._app.event then
        return false
    end

    local ok, handled = pcall(self._app.event, self._app, category, value, x, y)
    if not ok then
        self.log:error("App event error: %s", tostring(handled))
        return false
    end

    return handled == true
end

function framework:wakeup()
    if not self._initialized then
        return
    end

    self:wakeupTasks()
    self:wakeupApp()
end

function framework:paintApp()
    if not self._initialized then
        return
    end

    if self._appActive and self._app and self._app.paint then
        local ok, err = pcall(self._app.paint, self._app)
        if not ok then
            self.log:error("App paint error: %s", tostring(err))
        end
    end

    self.callback:wakeup(self._renderCallbackWakeupOptions)
end

function framework:paint()
    self:paintApp()
end

--[[ STATS & MONITORING ]]

function framework:getStats()
    local stats = {
        initialized = self._initialized,
        appActive = self._appActive,
        tasksCount = #self._taskOrder,
        callbackStats = self.callback:getStats(),
        eventStats = self.events:listEvents(),
        registryStats = self.registry:getStats(),
        profileStats = self._profiler and self.profiler:getSummary(self._profiler) or nil,
        memoryDebug = self._memoryDebugHistory[#self._memoryDebugHistory]
    }
    return stats
end

function framework:isMemoryDebugEnabled()
    return isTruthy(self.config and self.config.developer and self.config.developer.memstats)
end

function framework:captureMemoryDebug(label)
    if self:isMemoryDebugEnabled() ~= true then
        return nil
    end

    local eventStats = self.events and self.events.listEvents and self.events:listEvents() or {}
    local callbackStats = self.callback and self.callback.getStats and self.callback:getStats() or {}
    local callbackQueues = callbackStats.queues or {}
    local previous = self._memoryDebugHistory[#self._memoryDebugHistory]
    local app = self:getApp()
    local appStats = app and app.getDebugStats and app:getDebugStats() or {}
    local mspMeta = self._taskMetadata and self._taskMetadata.msp or nil
    local mspTask = mspMeta and mspMeta.instance or nil
    local mspStats = mspTask and mspTask.api and mspTask.api.getStats and mspTask.api:getStats() or {}
    local luaKB = collectgarbage and collectgarbage("count") or 0
    local snapshot = {
        label = tostring(label or "snapshot"),
        time = os.clock(),
        luaKB = luaKB,
        deltaLuaKB = previous and (luaKB - (tonumber(previous.luaKB) or 0)) or 0,
        packageLoaded = countLoadedModules(nil),
        packageLoadedApp = countLoadedModules("app."),
        callbackQueued = tonumber(callbackStats.totalQueued) or 0,
        callbackQueues = countKeys(callbackQueues),
        eventNames = countKeys(eventStats),
        eventHandlers = sumValues(eventStats),
        mspLoaded = tonumber(mspStats.loadedCount) or 0,
        mspHelp = tonumber(mspStats.helpCount) or 0,
        mspHelpMiss = tonumber(mspStats.helpMissCount) or 0,
        mspDataApis = tonumber(mspStats.dataApiCount) or 0,
        mspDataEntries = tonumber(mspStats.dataEntryCount) or 0,
        appPathDepth = tonumber(appStats.pathDepth) or 0,
        appFormRefs = tonumber(appStats.formRefCount) or 0,
        appNodeItems = tonumber(appStats.currentNodeItems) or 0,
        appFormBuilds = tonumber(appStats.formBuildCount) or 0,
        appLuaTableCache = tonumber(appStats.luaTableCacheEntries) or 0,
        appMaskCache = tonumber(appStats.maskCacheEntries) or 0,
        appNodeSource = tostring(appStats.currentNodeSource or ""),
        appHasNode = appStats.hasCurrentNode == true
    }

    pushHistory(self._memoryDebugHistory, snapshot, 12)
    setSessionValues(self.session, {
        memDebugLabel = snapshot.label,
        memDebugLuaKB = snapshot.luaKB,
        memDebugDeltaLuaKB = snapshot.deltaLuaKB,
        memDebugPackageLoaded = snapshot.packageLoaded,
        memDebugPackageLoadedApp = snapshot.packageLoadedApp,
        memDebugCallbackQueued = snapshot.callbackQueued,
        memDebugEventHandlers = snapshot.eventHandlers,
        memDebugMspLoaded = snapshot.mspLoaded,
        memDebugMspHelp = snapshot.mspHelp,
        memDebugMspHelpMiss = snapshot.mspHelpMiss,
        memDebugMspDataApis = snapshot.mspDataApis,
        memDebugMspDataEntries = snapshot.mspDataEntries,
        memDebugAppPathDepth = snapshot.appPathDepth,
        memDebugAppFormRefs = snapshot.appFormRefs,
        memDebugAppNodeItems = snapshot.appNodeItems,
        memDebugAppFormBuilds = snapshot.appFormBuilds,
        memDebugAppLuaTableCache = snapshot.appLuaTableCache,
        memDebugAppMaskCache = snapshot.appMaskCache,
        memDebugAppNodeSource = snapshot.appNodeSource
    })

    if self.log and self.log.info then
        self.log:info(
            "[mem] %s lua=%.1f d=%+.1f pkg=%d/%d cb=%d ev=%d/%d msp=%d/%d/%d refs=%d cache=%d mask=%d path=%d builds=%d",
            snapshot.label,
            snapshot.luaKB,
            snapshot.deltaLuaKB,
            snapshot.packageLoaded,
            snapshot.packageLoadedApp,
            snapshot.callbackQueued,
            snapshot.eventNames,
            snapshot.eventHandlers,
            snapshot.mspLoaded,
            snapshot.mspHelp,
            snapshot.mspDataApis,
            snapshot.appFormRefs,
            snapshot.appLuaTableCache,
            snapshot.appMaskCache,
            snapshot.appPathDepth,
            snapshot.appFormBuilds
        )
    end

    return snapshot
end

function framework:printStats()
    local stats = self:getStats()
    local eventCount = 0
    for _, _ in pairs(stats.eventStats) do
        eventCount = eventCount + 1
    end
    self.log:info("=== Framework Stats ===")
    self.log:info("Initialized: %s", tostring(stats.initialized))
    self.log:info("App Active: %s", tostring(stats.appActive))
    self.log:info("Tasks: %s", tostring(stats.tasksCount))
    self.log:info("Callbacks Queued: %s", tostring(stats.callbackStats.totalQueued))
    self.log:info("Events: %s", tostring(eventCount))
    if stats.profileStats then
        self.log:info("Task Loop: %.3fms avg / %.3fms max", stats.profileStats.loop.avgMs, stats.profileStats.loop.maxMs)
        if stats.profileStats.memstats and self.config and self.config.developer and self.config.developer.logMemoryStats == true then
            self.log:info("Lua Memory: %.1fKB current / %.1fKB peak", stats.profileStats.memory.currentKB, stats.profileStats.memory.peakKB)
            self.log:info("Free RAM: %.1fKB system / %.1fKB lua", stats.profileStats.memory.systemFreeKB, stats.profileStats.memory.luaFreeKB)
        end
    end
end

--[[ CLEANUP ]]

function framework:close()
    -- Close all tasks
    for name, meta in pairs(self._taskMetadata) do
        if meta.instance and meta.instance.close then
            pcall(meta.instance.close, meta.instance)
        end
    end
    
    -- Close app
    if self._app and self._app.close then
        pcall(self._app.close, self._app)
    end
    self._app = nil
    self._appModule = nil
    self._appLoader = nil
    self._appUnloader = nil
    self._appUnloadOnDeactivate = false
    
    -- Clear callbacks and events
    self.callback:clearAll()
    self.events:clearAll()
    
    -- Clear registry
    self.registry:clear()
    
    self._initialized = false
    self._running = false
    self._profiler = nil
    self.log:close()
end

return framework
