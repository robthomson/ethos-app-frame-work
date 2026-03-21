--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

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

local function prefBool(value, default)
    if value == nil then
        return default
    end
    if value == true or value == "true" or value == 1 or value == "1" then
        return true
    end
    if value == false or value == "false" or value == 0 or value == "0" then
        return false
    end
    return default
end

local function toNumber(value, default)
    local n = tonumber(value)
    if n == nil then
        return default
    end
    return n
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

local function addLine(container, label)
    if container and container.addLine then
        return container:addLine(label)
    end
    return form.addLine(label)
end

local function addChoice(container, label, choices, getter, setter)
    return form.addChoiceField(addLine(container, label), nil, choices, getter, setter)
end

local function addBoolean(container, label, getter, setter)
    return form.addBooleanField(addLine(container, label), nil, getter, setter)
end

local function addNumber(container, label, minValue, maxValue, getter, setter, suffix)
    local field = form.addNumberField(addLine(container, label), nil, minValue, maxValue, getter, setter)

    if field and field.suffix and suffix then
        field:suffix(suffix)
    end
    if field and field.minimum then
        field:minimum(minValue)
    end
    if field and field.maximum then
        field:maximum(maxValue)
    end

    return field
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

function Page:open(ctx)
    local state = readState(ctx.framework)
    local node = {
        title = ctx.item.title or "Development",
        subtitle = ctx.item.subtitle or "Developer settings",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false}
    }

    local function resetState()
        local fresh = readState(ctx.framework)

        for key in pairs(state) do
            state[key] = nil
        end
        for key, value in pairs(fresh) do
            state[key] = value
        end
    end

    function node:buildForm(app)
        addChoice(nil, "Log Level", LOG_LEVEL_CHOICES,
            function()
                return logLevelIndex(state.loglevel)
            end,
            function(newValue)
                state.loglevel = logLevelValue(newValue)
            end)

        addBoolean(nil, "Log MSP Traffic",
            function()
                return prefBool(state.logmsp, false)
            end,
            function(newValue)
                state.logmsp = newValue
            end)

        addBoolean(nil, "Log Events",
            function()
                return prefBool(state.logevents, false)
            end,
            function(newValue)
                state.logevents = newValue
            end)

        addChoice(nil, "Simulation API Version", API_VERSION_CHOICES,
            function()
                return toNumber(state.apiversion, 2)
            end,
            function(newValue)
                state.apiversion = newValue
            end)

        addBoolean(nil, "Memory Stats",
            function()
                return prefBool(state.memstats, false)
            end,
            function(newValue)
                state.memstats = newValue
            end)

        addBoolean(nil, "Task Profiler",
            function()
                return prefBool(state.taskprofiler, false)
            end,
            function(newValue)
                state.taskprofiler = newValue
            end)

        addBoolean(nil, "Enable Idle GC",
            function()
                return prefBool(state.idleGcEnabled, true)
            end,
            function(newValue)
                state.idleGcEnabled = newValue
            end)

        addChoice(nil, "Idle GC Interval", IDLE_GC_INTERVAL_CHOICES,
            function()
                return idleGcIntervalIndex(state.idleGcInterval)
            end,
            function(newValue)
                state.idleGcInterval = idleGcIntervalValue(newValue)
            end)

        addNumber(nil, "Idle GC Step", 1, 256,
            function()
                return tonumber(state.idleGcStepK) or 32
            end,
            function(newValue)
                state.idleGcStepK = newValue
            end,
            "K")
    end

    function node:save(app)
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
        app:_invalidateForm()
        return true
    end

    function node:reload(app)
        resetState()
        app:_invalidateForm()
        return true
    end

    return node
end

return Page
