--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local utils = assert(loadfile("app/modules/logs/lib/utils.lua"))()
local helpText = assert(loadfile("app/modules/logs/help.lua"))()

local SAMPLE_RATE = 1
local LOG_PADDING = 5
local LOG_CHUNK_SIZE = 1000

local ZOOM_LEVEL_TO_DECIMATION = {[1] = 5, [2] = 4, [3] = 2, [4] = 1, [5] = 1}
local ZOOM_LEVEL_TO_TIME = {[1] = 600, [2] = 300, [3] = 120, [4] = 60, [5] = 30}

local function buildLayout(app)
    local width, height = app:_windowSize()
    local top = (form and form.height and form.height() or 0) + 6
    local buttonHeight = app.radio.navbuttonHeight or 30
    local bottomPad = buttonHeight + 14
    local graphWidth = math.floor(width * (app.radio.logGraphWidthPercentage or 0.76))
    local zoomIndicatorWidth = 20
    local zoomIndicatorGap = 10
    local zoomButtonGap = 10
    local rightInset = 14
    local zoomIndicatorShift = 8

    return {
        width = width,
        height = height,
        graphX = 0,
        graphY = top,
        graphWidth = graphWidth,
        keyWidth = width - graphWidth,
        graphHeight = math.max(90, height - top - bottomPad),
        sliderY = height - buttonHeight - 6,
        sliderWidth = math.max(80, graphWidth - 10),
        buttonHeight = buttonHeight,
        zoomIndicatorWidth = zoomIndicatorWidth,
        zoomIndicatorGap = zoomIndicatorGap,
        zoomButtonGap = zoomButtonGap,
        rightInset = rightInset,
        zoomIndicatorShift = zoomIndicatorShift
    }
end

local function mapValue(x, inMin, inMax, outMin, outMax)
    if inMax == inMin then
        return outMin
    end

    return (x - inMin) * (outMax - outMin) / (inMax - inMin) + outMin
end

local function secondsToSamples(seconds)
    return math.floor(seconds * SAMPLE_RATE)
end

local function calculateZoomSteps(logLineCount)
    local logDurationSec = logLineCount / SAMPLE_RATE
    local level
    local desiredTime

    for level = 5, 1, -1 do
        desiredTime = ZOOM_LEVEL_TO_TIME[level]
        if logDurationSec >= desiredTime * 1.5 then
            return level
        end
    end

    return 1
end

local function calculateSeconds(totalSeconds, sliderValue)
    return math.floor(((sliderValue - 1) / 100) * totalSeconds)
end

local function paginateTable(data, stepSize, position, decimationFactor)
    local startIndex = math.max(1, position)
    local endIndex = math.min(startIndex + stepSize - 1, #data)
    local page = {}
    local index

    decimationFactor = decimationFactor or 1
    for index = startIndex, endIndex, decimationFactor do
        page[#page + 1] = data[index]
    end

    return page
end

local function padTable(tbl, padCount)
    local first
    local last
    local padded = {}
    local index

    if #tbl == 0 then
        return padded
    end

    first = tbl[1]
    last = tbl[#tbl]

    for index = 1, padCount do
        padded[#padded + 1] = first
    end
    for index = 1, #tbl do
        padded[#padded + 1] = tbl[index]
    end
    for index = 1, padCount do
        padded[#padded + 1] = last
    end

    return padded
end

local function getColumn(csvData, colIndex)
    local column = {}
    local start = 1
    local len = #csvData
    local newlinePos
    local row
    local colStart
    local colEnd
    local colCount

    while start <= len do
        newlinePos = csvData:find("\n", start)
        if not newlinePos then
            newlinePos = len + 1
        end

        row = csvData:sub(start, newlinePos - 1)
        colStart = 1
        colCount = 0

        while true do
            colEnd = row:find(",", colStart)
            if not colEnd then
                colEnd = #row + 1
            end

            colCount = colCount + 1
            if colCount == colIndex then
                column[#column + 1] = row:sub(colStart, colEnd - 1)
                break
            end

            colStart = colEnd + 1
            if colEnd == #row + 1 then
                break
            end
        end

        start = newlinePos + 1
    end

    return column
end

local function cleanColumn(data)
    local out = {}
    local index
    local value

    for index = 2, #data do
        value = tonumber(data[index])
        if value ~= nil then
            out[#out + 1] = value
        end
    end

    return out
end

local function getValueAtPercentage(array, percentage)
    local arraySize = #array
    local index

    if arraySize == 0 then
        return 0
    end

    index = math.ceil((percentage / 100) * arraySize)
    if index < 1 then
        index = 1
    elseif index > arraySize then
        index = arraySize
    end

    return array[index]
end

local function formatTime(seconds)
    local minutes = math.floor(seconds / 60)
    local remainder = seconds % 60

    return string.format("%02d:%02d", minutes, remainder)
end

local function findMaxNumber(numbers)
    local maxValue = numbers[1]
    local index

    if maxValue == nil then
        return 0
    end

    for index = 2, #numbers do
        if numbers[index] > maxValue then
            maxValue = numbers[index]
        end
    end

    return maxValue
end

local function findMinNumber(numbers)
    local minValue = numbers[1]
    local index

    if minValue == nil then
        return 0
    end

    for index = 2, #numbers do
        if numbers[index] < minValue then
            minValue = numbers[index]
        end
    end

    return minValue
end

local function findAverage(numbers)
    local sum = 0
    local index

    if #numbers == 0 then
        return 0
    end

    for index = 1, #numbers do
        sum = sum + numbers[index]
    end

    return sum / #numbers
end

local function drawGraph(points, color, pen, xStart, yStart, width, height, minVal, maxVal)
    local padding
    local xScale
    local yScale
    local index
    local x1
    local y1
    local x2
    local y2

    if #points < 2 then
        return
    end

    padding = math.max(5, math.floor(height * 0.1))
    yStart = yStart + (padding / 2)
    height = height - padding

    if maxVal == minVal then
        maxVal = maxVal + 1
        minVal = minVal - 1
    end

    lcd.color(color or COLOR_GREY)
    lcd.pen(pen or DOTTED)

    xScale = width / (#points - 1)
    yScale = height / (maxVal - minVal)

    for index = 1, #points - 1 do
        x1 = xStart + (index - 1) * xScale
        y1 = yStart + height - (points[index] - minVal) * yScale
        x2 = xStart + index * xScale
        y2 = yStart + height - (points[index + 1] - minVal) * yScale
        lcd.drawLine(x1, y1, x2, y2)
    end
end

local function drawKey(app, layout, laneData, laneY)
    local width = layout.width - layout.graphWidth - 10
    local boxPadding = 3
    local minimum = laneData.minimum
    local maximum = laneData.maximum
    local minText
    local maxText
    local truncMin
    local truncMax
    local textY
    local mmY
    local avgY
    local avgText
    local th

    lcd.font(app.radio.logKeyFont or FONT_S)
    _, th = lcd.getTextSize(laneData.keyname)
    lcd.color(laneData.color)
    lcd.drawFilledRectangle(layout.graphWidth, laneY, width, th + boxPadding)

    lcd.color(COLOR_BLACK)
    textY = laneY + ((th + boxPadding) / 2 - th / 2)
    lcd.drawText(layout.graphWidth + 5, textY, laneData.keyname, LEFT)

    lcd.font(app.radio.logKeyFontSmall or FONT_XS or FONT_XXS or FONT_STD)
    lcd.color((lcd.darkMode and lcd.darkMode()) and COLOR_WHITE or COLOR_BLACK)

    if laneData.keyfloor then
        minimum = math.floor(minimum)
        maximum = math.floor(maximum)
    end

    if laneData.keyunit == "rpm" and (minimum >= 10000 or maximum >= 10000) then
        truncMin = string.format("%.1fK", minimum / 10000)
        truncMax = string.format("%.1fK", maximum / 10000)
    end

    minText = laneData.keyminmax == 1 and ("↓ " .. tostring(truncMin or minimum) .. laneData.keyunit) or ""
    maxText = "↑ " .. tostring(truncMax or maximum) .. laneData.keyunit
    mmY = laneY + th + boxPadding + 2

    lcd.drawText(layout.graphWidth + 5, mmY, minText, LEFT)
    lcd.drawText(layout.width - layout.rightInset, mmY, maxText, RIGHT)

    if app.radio.logShowAvg == true then
        avgText = "Ø " .. tostring(math.floor((laneData.minimum + laneData.maximum) / 2)) .. laneData.keyunit
        avgY = mmY + th - 2
        lcd.drawText(layout.graphWidth + 5, avgY, avgText, LEFT)
    end
end

local function drawCurrentIndex(app, state, laneData, laneNumber)
    local layout = state.layout
    local sliderPadding = app.radio.logSliderPaddingLeft or 6
    local width = layout.graphWidth - sliderPadding
    local linePos = mapValue(state.sliderPosition, 1, 100, 1, width - 10) + sliderPadding
    local boxPadding = 3
    local idxPos
    local textAlign
    local boxPos
    local value
    local laneY
    local boxHeight
    local tw
    local th
    local timeText
    local currentSec
    local logDurSec
    local desiredWinSec
    local windowSec
    local windowLabel
    local labelY
    local zoomHeight
    local zoomOffsetY

    laneY = layout.graphY + (laneNumber - 1) * state.paintCache.laneHeight
    if linePos < 1 then
        linePos = 0
    end

    if state.sliderPosition > 50 then
        idxPos = linePos - (boxPadding * 2)
        textAlign = RIGHT
        boxPos = linePos - boxPadding
    else
        idxPos = linePos + (boxPadding * 2)
        textAlign = LEFT
        boxPos = linePos + boxPadding
    end

    value = getValueAtPercentage(laneData.points, state.sliderPosition)
    if laneData.keyfloor then
        value = math.floor(value)
    end
    value = tostring(value) .. laneData.keyunit

    lcd.font(app.radio.logKeyFont or FONT_S)
    tw, th = lcd.getTextSize(value)
    boxHeight = th + boxPadding

    if state.sliderPosition > 50 then
        boxPos = boxPos - tw - (boxPadding * 2)
    end

    lcd.color(laneData.color)
    lcd.drawFilledRectangle(boxPos, laneY, tw + (boxPadding * 2), boxHeight)
    lcd.color((lcd.darkMode and lcd.darkMode()) and COLOR_BLACK or COLOR_WHITE)
    lcd.drawText(idxPos, laneY + (boxHeight / 2 - th / 2), value, textAlign)

    if laneNumber ~= 1 then
        return
    end

    currentSec = calculateSeconds(state.logLineCount, state.sliderPosition)
    logDurSec = math.floor(state.logLineCount / SAMPLE_RATE)
    desiredWinSec = ZOOM_LEVEL_TO_TIME[state.zoomLevel] or ZOOM_LEVEL_TO_TIME[1]
    windowSec = math.min(desiredWinSec, logDurSec)
    if windowSec < 60 then
        windowLabel = string.format("%ds", windowSec)
    else
        windowLabel = string.format("%d:%02d", math.floor(windowSec / 60), windowSec % 60)
    end

    timeText = string.format("%s [+%s]", formatTime(math.floor(currentSec)), windowLabel)
    labelY = layout.graphHeight + layout.graphY - 10
    lcd.color(COLOR_WHITE)
    lcd.drawText(idxPos, labelY, timeText, textAlign)

    lcd.color((lcd.darkMode and lcd.darkMode()) and COLOR_WHITE or COLOR_BLACK)
    lcd.drawLine(linePos, layout.graphY - 5, linePos, layout.graphY + layout.graphHeight)

    lcd.color((lcd.darkMode and lcd.darkMode()) and lcd.RGB(40, 40, 40) or lcd.RGB(240, 240, 240))
    zoomHeight = 40 / state.zoomCount
    zoomOffsetY = (state.zoomCount - state.zoomLevel) * zoomHeight
    lcd.drawFilledRectangle(layout.zoomIndicatorX, layout.sliderY, layout.zoomIndicatorWidth, 40)
    lcd.color((lcd.darkMode and lcd.darkMode()) and COLOR_WHITE or COLOR_BLACK)
    lcd.drawFilledRectangle(layout.zoomIndicatorX, layout.sliderY + zoomOffsetY, layout.zoomIndicatorWidth, zoomHeight)
end

local function resetState(state)
    if state.fileHandle then
        pcall(function()
            state.fileHandle:close()
        end)
    end

    state.fileHandle = nil
    state.logDataRawParts = {}
    state.logDataRaw = nil
    state.logFileReadOffset = 0
    state.logDataRawReadComplete = false
    state.logData = {}
    state.logLineCount = 0
    state.processedLogData = false
    state.currentDataIndex = 1
    state.carriedOver = nil
    state.subStepSize = nil
    state.slowProgress = 0
    state.zoomLevel = 1
    state.zoomCount = 5
    state.sliderPosition = 1
    state.sliderPositionOld = 1
    state.error = nil
    state.paintCache = {
        points = {},
        stepSize = 0,
        position = 1,
        graphCount = 0,
        laneHeight = 0,
        decimationFactor = 1,
        needsUpdate = true
    }
end

local function beginLoad(node, showLoader)
    local state = node.state
    local filePath = utils.getLogDir(state.dirname) .. state.logfile
    local fileHandle, err = io.open(filePath, "rb")

    resetState(state)
    state.needsInitialLoad = false

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.logs.name)@",
            message = "Loading log data",
            detail = "Preparing reader.",
            closeWhenIdle = false,
            modal = true,
            progressValue = 0
        })
    end

    if not fileHandle then
        state.error = "Failed to open log file: " .. tostring(err or "unknown")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    state.fileHandle = fileHandle
    state.needsInitialLoad = false
    return true
end

local function readNextChunk(state)
    local chunk

    if state.logDataRawReadComplete == true or not state.fileHandle then
        return
    end

    state.fileHandle:seek("set", state.logFileReadOffset)
    chunk = state.fileHandle:read(LOG_CHUNK_SIZE)

    if chunk then
        state.logDataRawParts[#state.logDataRawParts + 1] = chunk
        state.logFileReadOffset = state.logFileReadOffset + #chunk
    else
        state.fileHandle:close()
        state.fileHandle = nil
        state.logDataRawReadComplete = true
        state.logDataRaw = table.concat(state.logDataRawParts)
        state.logDataRawParts = {}
    end
end

local function updatePaintCache(state)
    local logDurSec
    local desiredWinSec
    local winSec
    local maxPosition
    local index
    local entry
    local lane

    if not state.processedLogData or #state.logData == 0 then
        return
    end

    logDurSec = math.floor(state.logLineCount / SAMPLE_RATE)
    desiredWinSec = ZOOM_LEVEL_TO_TIME[state.zoomLevel] or ZOOM_LEVEL_TO_TIME[1]
    winSec = math.min(desiredWinSec, logDurSec)

    state.paintCache.stepSize = math.max(1, secondsToSamples(winSec))
    maxPosition = math.max(1, state.logLineCount - state.paintCache.stepSize + 1)
    state.paintCache.position = math.floor(mapValue(state.sliderPosition, 1, 100, 1, maxPosition))
    if state.paintCache.position < 1 then
        state.paintCache.position = 1
    end

    state.paintCache.graphCount = 0
    for index = 1, #state.logData do
        if state.logData[index].graph then
            state.paintCache.graphCount = state.paintCache.graphCount + 1
        end
    end

    if state.paintCache.graphCount < 1 then
        state.paintCache.points = {}
        state.paintCache.laneHeight = state.layout.graphHeight
        state.paintCache.needsUpdate = false
        return
    end

    state.paintCache.laneHeight = state.layout.graphHeight / state.paintCache.graphCount
    state.paintCache.decimationFactor = ZOOM_LEVEL_TO_DECIMATION[state.zoomLevel] or 1
    if state.zoomCount == 1 then
        state.paintCache.decimationFactor = 1
    end
    state.paintCache.points = {}

    lane = 0
    for index = 1, #state.logData do
        entry = state.logData[index]
        if entry.graph then
            lane = lane + 1
            state.paintCache.points[lane] = {
                points = paginateTable(entry.data, state.paintCache.stepSize, state.paintCache.position, state.paintCache.decimationFactor),
                color = entry.color,
                pen = entry.pen,
                minimum = entry.minimum,
                maximum = entry.maximum,
                keyname = entry.keyname,
                keyunit = entry.keyunit,
                keyminmax = entry.keyminmax,
                keyfloor = entry.keyfloor
            }
        end
    end

    state.paintCache.needsUpdate = false
end

local function processNextColumn(node)
    local state = node.state
    local columns = state.logColumns
    local column = columns[state.currentDataIndex]
    local rawColumn
    local cleanedColumn
    local data
    local progress

    if not column then
        return false
    end

    rawColumn = getColumn(state.logDataRaw or "", state.currentDataIndex + 1)
    cleanedColumn = cleanColumn(rawColumn)
    data = padTable(cleanedColumn, LOG_PADDING)

    state.logData[state.currentDataIndex] = {
        name = column.name,
        color = column.color,
        pen = column.pen,
        keyindex = column.keyindex,
        keyname = column.keyname,
        keyunit = column.keyunit,
        keyminmax = column.keyminmax,
        keyfloor = column.keyfloor,
        graph = column.graph,
        data = data,
        maximum = findMaxNumber(data),
        minimum = findMinNumber(data),
        average = findAverage(data)
    }

    progress = 20 + ((state.currentDataIndex / #columns) * 80)
    node.app.ui.updateLoader({
        message = "Processing log data",
        detail = string.format("Column %d of %d", state.currentDataIndex, #columns),
        progressValue = progress
    })

    if state.currentDataIndex >= #columns then
        state.logLineCount = #data
        if state.logLineCount < 1 then
            state.error = "No log samples found."
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
            return false
        end

        state.zoomCount = calculateZoomSteps(state.logLineCount)
        if state.zoomLevel > state.zoomCount then
            state.zoomLevel = state.zoomCount
        end
        state.processedLogData = true
        state.paintCache.needsUpdate = true
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        lcd.invalidate()
        state.currentDataIndex = state.currentDataIndex + 1
        return false
    end

    state.currentDataIndex = state.currentDataIndex + 1
    return true
end

function Page:open(ctx)
    local state = {
        dirname = ctx.item.dirname,
        logfile = ctx.item.logfile,
        modelName = ctx.item.modelName or "Unknown",
        logColumns = utils.getLogColumns(),
        fields = {},
        needsInitialLoad = true
    }
    local node = {
        title = utils.extractShortTimestamp(ctx.item.logfile),
        subtitle = state.modelName,
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = true, tool = false, help = true},
        app = ctx.app,
        state = state,
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "Loading log data",
            detail = "Preparing reader.",
            closeWhenIdle = false,
            modal = true,
            progressValue = 0
        }
    }

    resetState(state)

    function node:buildForm(app)
        local layout = buildLayout(app)
        local buttonAreaWidth = layout.keyWidth - layout.zoomIndicatorWidth - layout.zoomIndicatorGap - layout.rightInset
        local zoomButtonWidth = math.max(42, math.floor((buttonAreaWidth - layout.zoomButtonGap) / 2))
        local zoomOutX = layout.graphWidth
        local zoomInX = zoomOutX + zoomButtonWidth + layout.zoomButtonGap
        local zoomReady = state.processedLogData == true

        state.layout = layout
        state.fields = {}
        state.layout.zoomIndicatorX = math.min(
            layout.width - layout.rightInset - layout.zoomIndicatorWidth,
            zoomInX + zoomButtonWidth + layout.zoomIndicatorGap + layout.zoomIndicatorShift
        )

        if state.error then
            local line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.error))
            return
        end

        state.fields.slider = form.addSliderField(nil, {
            x = layout.graphX,
            y = layout.sliderY,
            w = layout.sliderWidth,
            h = layout.buttonHeight
        }, 1, 100,
        function()
            return state.sliderPosition
        end,
        function(newValue)
            state.sliderPosition = newValue
        end)

        state.fields.zoomOut = form.addButton(nil, {
            x = zoomOutX,
            y = layout.sliderY,
            w = zoomButtonWidth,
            h = layout.buttonHeight
        }, {
            text = "-",
            options = FONT_STD,
            press = function()
                if state.processedLogData ~= true then
                    return
                end
                if state.zoomLevel > 1 then
                    state.zoomLevel = state.zoomLevel - 1
                    state.paintCache.needsUpdate = true
                    lcd.invalidate()
                end
                if state.fields.zoomOut and state.fields.zoomOut.enable then
                    state.fields.zoomOut:enable(state.zoomLevel > 1)
                end
                if state.fields.zoomIn and state.fields.zoomIn.enable then
                    state.fields.zoomIn:enable(state.zoomLevel < state.zoomCount)
                end
            end
        })

        state.fields.zoomIn = form.addButton(nil, {
            x = zoomInX,
            y = layout.sliderY,
            w = zoomButtonWidth,
            h = layout.buttonHeight
        }, {
            text = "+",
            options = FONT_STD,
            press = function()
                if state.processedLogData ~= true then
                    return
                end
                if state.zoomLevel < state.zoomCount then
                    state.zoomLevel = state.zoomLevel + 1
                    state.paintCache.needsUpdate = true
                    lcd.invalidate()
                end
                if state.fields.zoomOut and state.fields.zoomOut.enable then
                    state.fields.zoomOut:enable(state.zoomLevel > 1)
                end
                if state.fields.zoomIn and state.fields.zoomIn.enable then
                    state.fields.zoomIn:enable(state.zoomLevel < state.zoomCount)
                end
            end
        })

        if state.fields.slider and state.fields.slider.step then
            state.fields.slider:step(1)
        end
        if state.fields.zoomOut and state.fields.zoomOut.enable then
            state.fields.zoomOut:enable(zoomReady and state.zoomLevel > 1)
        end
        if state.fields.zoomIn and state.fields.zoomIn.enable then
            state.fields.zoomIn:enable(zoomReady and state.zoomLevel < state.zoomCount)
        end
    end

    function node:reload()
        if state.fields.zoomOut and state.fields.zoomOut.enable then
            state.fields.zoomOut:enable(false)
        end
        if state.fields.zoomIn and state.fields.zoomIn.enable then
            state.fields.zoomIn:enable(false)
        end
        local ok = beginLoad(self, true)
        self.app:_invalidateForm()
        return ok
    end

    function node:wakeup(app)
        if state.needsInitialLoad == true then
            beginLoad(self, false)
        end

        if state.sliderPosition ~= state.sliderPositionOld or state.paintCache.needsUpdate == true then
            if state.layout then
                updatePaintCache(state)
                lcd.invalidate()
            end
            state.sliderPositionOld = state.sliderPosition
        end

        if state.fileHandle and not state.logDataRawReadComplete then
            readNextChunk(state)
            state.slowProgress = math.min(20, (state.slowProgress or 0) + 0.25)
            app.ui.updateLoader({
                message = "Loading log data",
                detail = "Reading CSV file.",
                progressValue = state.slowProgress
            })
            return
        end

        if state.logDataRawReadComplete and state.processedLogData ~= true and state.error == nil then
            processNextColumn(self)
        end
    end

    function node:paint()
        local laneNumber
        local laneData
        local laneY

        if state.processedLogData ~= true or not state.layout or not state.paintCache.points then
            return
        end

        for laneNumber = 1, #state.paintCache.points do
            laneData = state.paintCache.points[laneNumber]
            laneY = state.layout.graphY + (laneNumber - 1) * state.paintCache.laneHeight
            drawGraph(
                laneData.points,
                laneData.color,
                laneData.pen,
                state.layout.graphX,
                laneY,
                state.layout.graphWidth - 10,
                state.paintCache.laneHeight,
                laneData.minimum,
                laneData.maximum
            )
            drawKey(self.app, state.layout, laneData, laneY)
            drawCurrentIndex(self.app, state, laneData, laneNumber)
        end
    end

    function node:help()
        return utils.openHelpDialog((self.title or "@i18n(app.modules.logs.name)@") .. " Help", helpText.logs_tool)
    end

    function node:close()
        if state.fileHandle then
            pcall(function()
                state.fileHandle:close()
            end)
            state.fileHandle = nil
        end
        self.app.ui.clearProgressDialog(true)
    end

    return node
end

return Page
