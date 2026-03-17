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

    if lcd and lcd.invalidate then
        lcd.invalidate()
    end
end

function tool.paint()
    runtime.paintApp()
end

function tool.event(category, value, x, y)
    ethos_events.debug("app", category, value, x, y, {throttleSame = true})
    return false
end

function tool.close()
    runtime.closeApp()
end

return tool
