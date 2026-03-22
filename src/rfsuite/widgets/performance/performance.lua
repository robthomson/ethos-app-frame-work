--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Developer-focused widget for memory and scheduler performance stats.
]] --

local runtime = require("runtime")
local ethos_events = require("framework.utils.ethos_events")

local widget = {}
local cpuRowBuffer = {}
local memoryRowBuffer = {}
local runtimeRowBuffer = {}
local consoleLineBuffer = {}
local MEMORY_AVERAGE_WINDOW_SECONDS = 5.0
local MEMORY_AVERAGE_DISPLAY_SECONDS = 2.0

local function trimMemorySamples(samples, now)
    local cutoff = (now or os.clock()) - MEMORY_AVERAGE_WINDOW_SECONDS

    while #samples > 0 and (samples[1].time or 0) < cutoff do
        table.remove(samples, 1)
    end
end

local function sampleMemoryAverage(instance, session, now)
    local samples = instance.memorySamples
    local current = tonumber(session:get("luaMemoryKB", 0)) or 0

    samples[#samples + 1] = {
        time = now or os.clock(),
        value = current
    }

    trimMemorySamples(samples, now)
end

local function refreshMemoryAverage(instance, now)
    local samples = instance.memorySamples
    local total = 0
    local index

    trimMemorySamples(samples, now)

    if #samples == 0 then
        return instance.displayMemoryAverageKB or instance.memoryAverageKB or 0
    end

    for index = 1, #samples do
        total = total + (tonumber(samples[index].value) or 0)
    end

    instance.memoryAverageKB = total / #samples
    return instance.memoryAverageKB
end

local function fontSmall()
    return FONT_XS or FONT_STD
end

local function fontTitle()
    return FONT_XS_BOLD or FONT_STD_BOLD or FONT_BOLD or FONT_XS or FONT_STD
end

local function drawTextRight(xRight, y, text)
    lcd.font(fontSmall())
    local tw = 0
    if lcd.getTextSize then
        tw = lcd.getTextSize(text)
    end
    lcd.drawText(xRight - tw, y, text)
end

local function drawMetric(x, y, w, label, value)
    lcd.font(fontSmall())
    lcd.drawText(x, y, label)
    drawTextRight(x + w, y, value)
end

local function drawCardFrame(x, y, w, h, title)
    lcd.drawRectangle(x, y, w, h)
    lcd.font(fontTitle())
    lcd.drawText(x + 6, y + 4, title)
end

local function drawRows(x, y, w, rows)
    local rowY = y + 24
    local rowGap = 18
    local i

    for i = 1, #rows, 2 do
        drawMetric(x + 6, rowY, w - 12, rows[i], rows[i + 1])
        rowY = rowY + rowGap
    end
end

local function drawConsole(x, y, w, h, lines)
    local lineY = y + 24
    local lineGap = 16
    local maxY = y + h - 14
    local i

    for i = 1, #lines do
        if lineY > maxY then
            break
        end
        lcd.font(fontSmall())
        lcd.drawText(x + 6, lineY, lines[i])
        lineY = lineY + lineGap
    end
end

local function cpuRows(session, rows)
    rows[1] = "Loop Last"
    rows[2] = string.format("%.3f ms", session:get("taskLoopLastMs", 0))
    rows[3] = "Loop Avg"
    rows[4] = string.format("%.3f ms", session:get("taskLoopAvgMs", 0))
    rows[5] = "Loop Max"
    rows[6] = string.format("%.3f ms", session:get("taskLoopMaxMs", 0))
    rows[7] = "Top Task"
    rows[8] = string.format("%s / %.3f ms", session:get("topTaskName", "n/a"), session:get("topTaskAvgMs", 0))
    return rows
end

local function memoryRows(session, rows, instance)
    rows[1] = "Lua Used"
    rows[2] = string.format("%.1f KB", session:get("luaMemoryKB", 0))
    rows[3] = "Lua Avg 5s"
    rows[4] = string.format("%.1f KB", tonumber(instance and instance.displayMemoryAverageKB) or 0)
    rows[5] = "Lua Peak"
    rows[6] = string.format("%.1f KB", session:get("luaMemoryPeakKB", 0))
    rows[7] = "Lua Free"
    rows[8] = string.format("%.1f KB", session:get("luaFreeRamKB", 0))
    rows[9] = "System Free"
    rows[10] = string.format("%.1f KB", session:get("systemFreeRamKB", 0))
    return rows
end

local function runtimeRows(session, rows)
    local connected = session:get("isConnected", false) == true

    rows[1] = "Background"
    rows[2] = tostring(session:get("backgroundState", "waiting"))
    rows[3] = "MSP Transport"
    rows[4] = tostring(connected and session:get("mspTransport", "disconnected") or "disconnected")
    rows[5] = "API Version"
    rows[6] = tostring(connected and (session:get("apiVersion", "n/a") or "n/a") or "n/a")
    rows[7] = "MSP Proto"
    rows[8] = connected and ("v" .. tostring(session:get("mspProtocolVersion", 1))) or "n/a"
    rows[9] = "BG Ticks"
    rows[10] = tostring(session:get("backgroundWakeups", 0))
    rows[11] = "MSP Queue"
    rows[12] = tostring(session:get("mspQueueDepth", 0))
    return rows
end

function widget.create()
    return {
        lastInvalidate = 0,
        memorySamples = {},
        memoryAverageKB = 0,
        displayMemoryAverageKB = 0,
        lastMemoryAverageDisplayAt = 0
    }
end

function widget.wakeup(instance)
    local framework = runtime.ensureFramework()
    local session = framework and framework.session or nil
    local now = os.clock()

    runtime.backgroundStatus()

    if session then
        sampleMemoryAverage(instance, session, now)
        refreshMemoryAverage(instance, now)
        if (instance.lastMemoryAverageDisplayAt or 0) == 0
            or now - (instance.lastMemoryAverageDisplayAt or 0) >= MEMORY_AVERAGE_DISPLAY_SECONDS then
            instance.displayMemoryAverageKB = instance.memoryAverageKB
            instance.lastMemoryAverageDisplayAt = now
        end
    end

    if not lcd or not lcd.invalidate then
        return
    end

    local interval = (lcd.isVisible and lcd.isVisible()) and 0.25 or 1.0
    if now - (instance.lastInvalidate or 0) >= interval then
        lcd.invalidate()
        instance.lastInvalidate = now
    end
end

function widget.paint(instance)
    local framework = runtime.ensureFramework()
    local session = framework.session
    local log = framework.log
    local w, h = lcd.getWindowSize()
    local gap = 8
    local topPad = 4
    local totalW = w - 8
    local leftW
    local middleW
    local rightW
    local leftX = 4
    local middleX
    local rightX
    local cardY = topPad
    local topH = math.max(88, math.floor((h - cardY - gap * 2) / 2))
    local consoleY = cardY + topH + gap
    local consoleH = h - consoleY - 4
    local consoleLines
    local lineCount

    if w >= 360 then
        leftW = math.floor((totalW - gap * 2) / 3)
        middleW = leftW
        rightW = totalW - leftW - middleW - gap * 2
        middleX = leftX + leftW + gap
        rightX = middleX + middleW + gap

        drawCardFrame(leftX, cardY, leftW, topH, "CPU")
        drawRows(leftX, cardY, leftW, cpuRows(session, cpuRowBuffer))

        drawCardFrame(middleX, cardY, middleW, topH, "Memory")
        drawRows(middleX, cardY, middleW, memoryRows(session, memoryRowBuffer, instance))

        drawCardFrame(rightX, cardY, rightW, topH, "Runtime")
        drawRows(rightX, cardY, rightW, runtimeRows(session, runtimeRowBuffer))

        drawCardFrame(leftX, consoleY, totalW, consoleH, "Console")
        lineCount = math.max(3, math.floor((consoleH - 28) / 16))
        consoleLines = log and log.getRecentLines and log:getRecentLines(lineCount, {noTimestamp = false}, consoleLineBuffer) or consoleLineBuffer
        drawConsole(leftX, consoleY, totalW, consoleH, consoleLines)
    else
        local smallCardH = math.max(56, math.floor((topH - gap * 2) / 3))
        local top3Y = cardY + (smallCardH + gap) * 2

        drawCardFrame(leftX, cardY, totalW, smallCardH, "CPU")
        drawRows(leftX, cardY, totalW, cpuRows(session, cpuRowBuffer))

        drawCardFrame(leftX, cardY + smallCardH + gap, totalW, smallCardH, "Memory")
        drawRows(leftX, cardY + smallCardH + gap, totalW, memoryRows(session, memoryRowBuffer, instance))

        drawCardFrame(leftX, top3Y, totalW, smallCardH, "Runtime")
        drawRows(leftX, top3Y, totalW, runtimeRows(session, runtimeRowBuffer))

        drawCardFrame(leftX, consoleY, totalW, consoleH, "Console")
        lineCount = math.max(3, math.floor((consoleH - 28) / 16))
        consoleLines = log and log.getRecentLines and log:getRecentLines(lineCount, {noTimestamp = false}, consoleLineBuffer) or consoleLineBuffer
        drawConsole(leftX, consoleY, totalW, consoleH, consoleLines)
    end
end

function widget.event(widgetInstance, category, value, x, y)
    ethos_events.debug("widget.performance", category, value, x, y, {throttleSame = true})
    return false
end

function widget.close()
end

return widget
