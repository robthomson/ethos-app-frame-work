--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Ethos system tool wrapper for the framework app surface.
]] --

local runtime = require("runtime")
local ethos_events = require("framework.utils.ethos_events")

local tool = {
    name = runtime.config.toolName,
    icon = runtime.icon
}

function tool.create()
    runtime.openApp()
end

function tool.wakeup()
    runtime.wakeupApp()
end

function tool.paint()
    runtime.paintApp()
end

function tool.event(widget, category, value, x, y)
    local _ = widget
    local fw = runtime.ensureFramework()
    local developer = fw and fw.preferences and fw.preferences:section("developer", {}) or {}

    if developer.logevents == true or developer.logevents == "true" then
        ethos_events.debug("app", category, value, x, y, {throttleSame = true, level = "info"})
    else
        ethos_events.debug("app", category, value, x, y, {throttleSame = true})
    end
    return runtime.eventApp(category, value, x, y)
end

function tool.close()
    runtime.closeApp()
end

return tool
