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
    ethos_events.debug("tasks", category, value, x, y, {throttleSame = true})
    return false
end

function tasks.read()
    return nil
end

function tasks.write()
    return false
end

return tasks
