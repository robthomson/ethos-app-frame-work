--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Example widget surface for the framework.
]] --

local runtime = require("runtime")
local ethos_events = require("framework.utils.ethos_events")

local widget = {}

local function drawLine(y, text)
    lcd.drawText(6, y, text)
end

function widget.create()
    return {
        lastInvalidate = 0
    }
end

function widget.wakeup(instance)
    runtime.backgroundStatus()

    if not lcd or not lcd.invalidate then
        return
    end

    local now = os.clock()
    local interval = (lcd.isVisible and lcd.isVisible()) and 0.25 or 1.0
    if now - (instance.lastInvalidate or 0) >= interval then
        lcd.invalidate()
        instance.lastInvalidate = now
    end
end

function widget.paint()
    local framework = runtime.ensureFramework()
    local session = framework.session
    local backgroundAge = session:get("backgroundAge", -1)
    local luaMemoryKB = session:get("luaMemoryKB", 0)
    local luaMemoryPeakKB = session:get("luaMemoryPeakKB", 0)
    local topTaskName = session:get("topTaskName", "n/a")
    local topTaskAvgMs = session:get("topTaskAvgMs", 0)

    lcd.font(FONT_STD)
    lcd.color(lcd.RGB(255, 255, 255))

    drawLine(6, runtime.config.toolName)
    drawLine(26, "UI: " .. (framework:isAppActive() and "active" or "idle"))
    drawLine(46, "BG: " .. tostring(session:get("backgroundState", "waiting")))
    if backgroundAge >= 0 then
        drawLine(66, string.format("BG age: %.2fs", backgroundAge))
        drawLine(86, string.format("Telemetry: %.1fV %.1fA", session:get("telemetryVoltage", 0), session:get("telemetryCurrent", 0)))
        drawLine(106, "MSP queue: " .. tostring(session:get("mspQueueDepth", 0)))
        drawLine(126, string.format("Lua: %.1fKB peak %.1fKB", luaMemoryKB, luaMemoryPeakKB))
        drawLine(146, string.format("Top: %s %.3fms", topTaskName, topTaskAvgMs))
    else
        drawLine(66, "BG ticks: " .. tostring(session:get("backgroundWakeups", 0)))
        drawLine(86, string.format("Telemetry: %.1fV %.1fA", session:get("telemetryVoltage", 0), session:get("telemetryCurrent", 0)))
        drawLine(106, "MSP queue: " .. tostring(session:get("mspQueueDepth", 0)))
        drawLine(126, string.format("Lua: %.1fKB peak %.1fKB", luaMemoryKB, luaMemoryPeakKB))
        drawLine(146, string.format("Top: %s %.3fms", topTaskName, topTaskAvgMs))
    end
end

function widget.event(widgetInstance, category, value, x, y)
    ethos_events.debug("widget.status", category, value, x, y, {throttleSame = true})
    return false
end

function widget.close()
end

return widget
