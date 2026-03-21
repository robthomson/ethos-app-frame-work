--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ok, PrefsPage = pcall(require, "app.lib.prefs_page")

if not ok or type(PrefsPage) ~= "table" then
    local chunk = assert(loadfile("app/lib/prefs_page.lua"))
    PrefsPage = chunk()
end

local LOG_LEVEL_CHOICES = {
    {"Off", 1},
    {"Info", 2},
    {"Debug", 3}
}

local API_VERSION_CHOICES = {
    {"12.08", 1},
    {"12.09", 2},
    {"12.10", 3}
}

local IDLE_GC_INTERVAL_CHOICES = {
    {"0.25s", 1},
    {"0.50s", 2},
    {"0.75s", 3},
    {"1.00s", 4},
    {"1.50s", 5},
    {"2.00s", 6}
}

local function copyTable(source)
    local out = {}

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
end

local function logLevelIndex(value)
    if value == "off" then
        return 1
    end
    if value == "debug" then
        return 3
    end
    return 2
end

local function logLevelValue(index)
    if index == 1 then
        return "off"
    end
    if index == 3 then
        return "debug"
    end
    return "info"
end

local function idleGcIntervalIndex(value)
    local seconds = tonumber(value) or 0.75

    if seconds <= 0.25 then
        return 1
    end
    if seconds <= 0.50 then
        return 2
    end
    if seconds <= 0.75 then
        return 3
    end
    if seconds <= 1.00 then
        return 4
    end
    if seconds <= 1.50 then
        return 5
    end
    return 6
end

local function idleGcIntervalValue(index)
    if index == 1 then
        return 0.25
    end
    if index == 2 then
        return 0.50
    end
    if index == 4 then
        return 1.00
    end
    if index == 5 then
        return 1.50
    end
    if index == 6 then
        return 2.00
    end
    return 0.75
end

local function readState(framework)
    local prefs = framework.preferences:section("developer", {})
    local config = framework.config and framework.config.developer or {}
    local state = copyTable(prefs)

    if state.loglevel == nil then
        state.loglevel = config.loglevel or "info"
    end
    if state.apiversion == nil then
        state.apiversion = 2
    end
    if state.memstats == nil then
        state.memstats = false
    end
    if state.taskprofiler == nil then
        state.taskprofiler = false
    end
    if state.logmsp == nil then
        state.logmsp = false
    end
    if state.logevents == nil then
        state.logevents = false
    end
    if state.idleGcEnabled == nil then
        state.idleGcEnabled = config.idleGcEnabled == true
    end
    if state.idleGcInterval == nil then
        state.idleGcInterval = config.idleGcInterval or 0.75
    end
    if state.idleGcStepK == nil then
        state.idleGcStepK = config.idleGcStepK or 32
    end

    return state
end

local function applyRuntimeSettings(app, state)
    local framework = app.framework
    local config = framework.config.developer or {}

    config.loglevel = state.loglevel
    config.memstats = state.memstats == true
    config.taskprofiler = state.taskprofiler == true
    config.idleGcEnabled = state.idleGcEnabled == true
    config.idleGcInterval = tonumber(state.idleGcInterval) or config.idleGcInterval or 0.75
    config.idleGcStepK = tonumber(state.idleGcStepK) or config.idleGcStepK or 32
    framework.config.developer = config

    framework.log:init({
        developer = framework.preferences.developer or {},
        minLevel = state.loglevel or config.loglevel or "info"
    })
    framework._profiler = framework.profiler.new(config)
    if framework._syncProfilerSession then
        framework:_syncProfilerSession()
    end
end

local Page = PrefsPage.create({
    title = "Development",
    subtitle = "Developer settings",
    navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
    readState = readState,
    sections = {
        {
            title = "Logging",
            fields = {
                {
                    kind = "choice",
                    label = "Log Level",
                    key = "loglevel",
                    choices = LOG_LEVEL_CHOICES,
                    get = function(state)
                        return logLevelIndex(state.loglevel)
                    end,
                    set = function(state, newValue)
                        state.loglevel = logLevelValue(newValue)
                    end
                },
                {kind = "boolean", label = "Log MSP Traffic", key = "logmsp", default = false},
                {kind = "boolean", label = "Log Events", key = "logevents", default = false}
            }
        },
        {
            title = "Simulation",
            fields = {
                {kind = "choice", label = "Simulation API Version", key = "apiversion", choices = API_VERSION_CHOICES, get = function(state) return tonumber(state.apiversion) or 2 end}
            }
        },
        {
            title = "Profiling",
            fields = {
                {kind = "boolean", label = "Memory Stats", key = "memstats", default = false},
                {kind = "boolean", label = "Task Profiler", key = "taskprofiler", default = false}
            }
        },
        {
            title = "Garbage Collection",
            fields = {
                {kind = "boolean", label = "Enable Idle GC", key = "idleGcEnabled", default = true},
                {
                    kind = "choice",
                    label = "Idle GC Interval",
                    key = "idleGcInterval",
                    choices = IDLE_GC_INTERVAL_CHOICES,
                    get = function(state)
                        return idleGcIntervalIndex(state.idleGcInterval)
                    end,
                    set = function(state, newValue)
                        state.idleGcInterval = idleGcIntervalValue(newValue)
                    end
                },
                {kind = "number", label = "Idle GC Step", key = "idleGcStepK", min = 1, max = 256, suffix = "K", get = function(state) return tonumber(state.idleGcStepK) or 32 end}
            }
        }
    },
    save = function(_, app, state)
        local developer = app.framework.preferences:section("developer", {})
        local ok
        local err

        for key, value in pairs(state) do
            developer[key] = value
        end

        ok, err = app.framework.preferences:save()
        if ok == false then
            app.framework.log:error("Failed saving developer preferences: %s", tostring(err))
            return false
        end

        applyRuntimeSettings(app, state)
        return true
    end
})

return Page
