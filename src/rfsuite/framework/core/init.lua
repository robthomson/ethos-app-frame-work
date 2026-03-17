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
framework._appActive = false

-- State
framework._initialized = false
framework._running = false
framework._profiler = nil
framework._profilerSessionBuffer = {}
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

--[[ INITIALIZATION ]]

function framework:init(config)
    self.config = config or {}
    self._initialized = true
    
    -- Initialize preferences file path
    self.config.baseDir = self.config.baseDir or "ethos_framework"
    self.config.prefFile = self.config.prefFile or (self.config.baseDir .. "/preferences.ini")
    
    self.preferences = preferences_mod.new({
        path = self.config.prefFile,
        defaults = self.config.preferencesDefaults or self:_defaultPreferences()
    })
    self.log:init({
        developer = self.preferences.developer or {},
        minLevel = (self.config.developer and self.config.developer.loglevel) or (self.preferences.developer and self.preferences.developer.loglevel) or "info"
    })
    self._profiler = self.profiler.new(self.config.developer or {})
    self._idleGcLastAt = 0
    
    -- Initialize session state
    self.session:set("initialized", true)
    self.session:set("appActive", false)
    self.session:setMultiple({
        idleGcEnabled = self.config.developer and self.config.developer.idleGcEnabled == true or false,
        idleGcLastAt = 0,
        idleGcCycleComplete = false,
        idleGcRuns = 0
    })
    self:_syncProfilerSession()
    
    return self
end

function framework:_profileLog(line)
    self.log:info("%s", line)
end

function framework:_syncProfilerSession()
    local state = self._profiler
    local values = self._profilerSessionBuffer
    local loop = state and state.loop or nil
    local memory = state and state.memory or nil
    local taskCount = 0
    local topTaskName = "n/a"
    local topTaskAvgMs = 0
    local topTaskLastMs = 0
    local topTaskMaxMs = 0

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

    self.session:setMultiple(values)
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
    self._app = appModule
    
    if appModule.init then
        appModule:init(self)
    end
    
    self.session:set("appRegistered", true)
end

function framework:getApp()
    return self._app
end

function framework:isAppActive()
    return self._appActive
end

function framework:activateApp()
    self._appActive = true
    self.session:set("appActive", true)
    
    if self._app and self._app.onActivate then
        self._app:onActivate()
    end
    
    self:_emit("app:activated")
end

function framework:deactivateApp()
    self._appActive = false
    self.session:set("appActive", false)
    
    if self._app and self._app.onDeactivate then
        self._app:onDeactivate()
    end
    
    self:_emit("app:deactivated")
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

function framework:_wakeupTasks()
    if not self._initialized then
        return
    end

    local now = os.clock()

    for _, taskInfo in ipairs(self._taskOrder) do
        local meta = self._taskMetadata[taskInfo.name]
        if meta.enabled and meta.instance then
            if (now - meta.lastWakeup) >= meta.interval then
                local startedAt = os.clock()
                local ok, err = pcall(meta.instance.wakeup, meta.instance)
                local duration = os.clock() - startedAt
                if self._profiler then
                    self.profiler:recordTask(self._profiler, taskInfo.name, meta.interval, duration)
                end
                if not ok then
                    self.log:error("Task '%s' wakeup error: %s", taskInfo.name, tostring(err))
                end
                meta.lastWakeup = now
            end
        end
    end
end

function framework:_wakeupApp()
    if not self._initialized then
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

    local loopToken = self._profiler and self.profiler:beginLoop(self._profiler) or nil
    self:_wakeupTasks()
    self.callback:wakeup(self._callbackWakeupOptions)
    self:_runIdleGc(os.clock())

    if self._profiler then
        self.profiler:endLoop(self._profiler, loopToken)
        self:_syncProfilerSession()
    end
end

function framework:wakeupApp()
    self:_wakeupApp()
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
        profileStats = self._profiler and self.profiler:getSummary(self._profiler) or nil
    }
    return stats
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
