--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Ethos background task wrapper for the framework task surface.
]] --

local runtime = require("runtime")
local ethos_events = require("framework.utils.ethos_events")

local tasks = {}

function tasks.init()
    local framework = runtime.ensureFramework()
    framework.session:setMultiple({
        backgroundRegistered = true,
        backgroundState = "starting"
    })
end

function tasks.wakeup()
    runtime.wakeupBackground()
end

function tasks.event(widget, category, value, x, y)
    local framework = runtime.ensureFramework()
    local developer = framework and framework.preferences and framework.preferences:section("developer", {}) or {}

    if developer.logevents == true or developer.logevents == "true" then
        ethos_events.debug("tasks", category, value, x, y, {throttleSame = true, level = "info"})
    else
        ethos_events.debug("tasks", category, value, x, y, {throttleSame = true})
    end
    return false
end

function tasks.read()
    return nil
end

function tasks.write()
    return false
end

return tasks
