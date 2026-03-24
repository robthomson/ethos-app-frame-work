--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()

local MSP_RAW_IMU = 102
local MSP_ALTITUDE = 109
local MSP_SONAR = 58
local MSP_DEBUG = 254

local SOURCES = {
    {label = "@i18n(sensors.gyro.x)@", packet = "raw_imu", group = "gyro", idx = 1},
    {label = "@i18n(sensors.gyro.y)@", packet = "raw_imu", group = "gyro", idx = 2},
    {label = "@i18n(sensors.gyro.z)@", packet = "raw_imu", group = "gyro", idx = 3},
    {label = "@i18n(sensors.accel.x)@", packet = "raw_imu", group = "accel", idx = 1},
    {label = "@i18n(sensors.accel.y)@", packet = "raw_imu", group = "accel", idx = 2},
    {label = "@i18n(sensors.accel.z)@", packet = "raw_imu", group = "accel", idx = 3},
    {label = "@i18n(sensors.mag.x)@", packet = "raw_imu", group = "mag", idx = 1},
    {label = "@i18n(sensors.mag.y)@", packet = "raw_imu", group = "mag", idx = 2},
    {label = "@i18n(sensors.mag.z)@", packet = "raw_imu", group = "mag", idx = 3},
    {label = "@i18n(sensors.altitude)@", packet = "altitude"},
    {label = "@i18n(sensors.sonar)@", packet = "sonar"},
    {label = "@i18n(sensors.debug.value_0)@", packet = "debug", idx = 1},
    {label = "@i18n(sensors.debug.value_1)@", packet = "debug", idx = 2},
    {label = "@i18n(sensors.debug.value_2)@", packet = "debug", idx = 3},
    {label = "@i18n(sensors.debug.value_3)@", packet = "debug", idx = 4},
    {label = "@i18n(sensors.debug.value_4)@", packet = "debug", idx = 5},
    {label = "@i18n(sensors.debug.value_5)@", packet = "debug", idx = 6},
    {label = "@i18n(sensors.debug.value_6)@", packet = "debug", idx = 7},
    {label = "@i18n(sensors.debug.value_7)@", packet = "debug", idx = 8}
}

local function writeS16(v)
    if v < 0 then
        v = v + 0x10000
    end
    return v % 256, math.floor(v / 256) % 256
end

local function writeS32(v)
    if v < 0 then
        v = v + 0x100000000
    end
    return v % 256, math.floor(v / 256) % 256, math.floor(v / 65536) % 256, math.floor(v / 16777216) % 256
end

local function getRawImuSimResponse()
    local t = os.clock() * 3.5
    local b = {}
    local function push16(v)
        local l, h = writeS16(v)
        b[#b + 1] = l
        b[#b + 1] = h
    end

    push16(math.floor(math.sin(t) * 180))
    push16(math.floor(math.sin(t + 1.3) * 160))
    push16(math.floor(512 + math.sin(t + 0.4) * 70))
    push16(math.floor(math.sin(t * 1.2) * 220))
    push16(math.floor(math.sin(t * 1.1 + 1.1) * 200))
    push16(math.floor(math.sin(t * 0.9 + 2.0) * 170))
    push16(math.floor(math.sin(t * 0.8) * 120))
    push16(math.floor(math.sin(t * 0.7 + 0.7) * 140))
    push16(math.floor(math.sin(t * 0.6 + 1.8) * 90))
    return b
end

local function getAltitudeSimResponse()
    local t = os.clock() * 1.2
    return {writeS32(math.floor((100 + math.sin(t) * 40) * 100))}
end

local function getSonarSimResponse()
    local t = os.clock() * 1.5
    return {writeS32(math.floor(120 + math.sin(t) * 30))}
end

local function getDebugSimResponse()
    local t = os.clock() * 2.0
    local b = {}
    local index
    local b0
    local b1
    local b2
    local b3

    for index = 1, 8 do
        b0, b1, b2, b3 = writeS32(math.floor(math.sin(t + index * 0.6) * 1000))
        b[#b + 1] = b0
        b[#b + 1] = b1
        b[#b + 1] = b2
        b[#b + 1] = b3
    end

    return b
end

local function formatValue(v)
    local value = tonumber(v)

    if not value then
        return "-"
    end
    if math.abs(value) >= 100 then
        return string.format("%.1f", value)
    end
    return string.format("%.2f", value)
end

local function selectedSource(state)
    return SOURCES[state.selectedSourceIdx]
end

local function buildSourceChoices()
    local choices = {}
    local index

    for index = 1, #SOURCES do
        choices[#choices + 1] = {SOURCES[index].label, index}
    end

    return choices
end

local function resetSamples(state)
    state.samples = {}
    state.lastValueText = "-"
    state.lastStateText = "@i18n(app.modules.fblsensors.wait)@"
end

local function addSample(state, value)
    if type(value) ~= "number" then
        return
    end

    state.samples[#state.samples + 1] = value
    while #state.samples > state.maxSamples do
        table.remove(state.samples, 1)
    end
end

local function parseRawImu(state, helper, buf)
    local ax = helper.readS16(buf)
    local ay = helper.readS16(buf)
    local az = helper.readS16(buf)
    local gx = helper.readS16(buf)
    local gy = helper.readS16(buf)
    local gz = helper.readS16(buf)
    local mx = helper.readS16(buf)
    local my = helper.readS16(buf)
    local mz = helper.readS16(buf)

    if mz == nil then
        return false
    end

    state.rawImu = {
        accel = {ax / 512, ay / 512, az / 512},
        gyro = {gx * (4 / 16.4), gy * (4 / 16.4), gz * (4 / 16.4)},
        mag = {mx / 1090, my / 1090, mz / 1090}
    }
    return true
end

local function parseAltitude(state, helper, buf)
    local value = helper.readS32(buf)

    if value == nil then
        return false
    end
    state.altitude = value / 100
    return true
end

local function parseSonar(state, helper, buf)
    local value = helper.readS32(buf)

    if value == nil then
        return false
    end
    state.sonar = value
    return true
end

local function parseDebug(state, helper, buf)
    local debug = {}
    local index

    for index = 1, 8 do
        debug[index] = helper.readS32(buf)
        if debug[index] == nil then
            return false
        end
    end

    state.debug = debug
    return true
end

local function readSelectedValue(state)
    local source = selectedSource(state)
    local group

    if not source then
        return nil
    end

    if source.packet == "raw_imu" and state.rawImu then
        group = state.rawImu[source.group]
        return group and group[source.idx] or nil
    end
    if source.packet == "altitude" then
        return state.altitude
    end
    if source.packet == "sonar" then
        return state.sonar
    end
    if source.packet == "debug" and state.debug then
        return state.debug[source.idx]
    end

    return nil
end

local function drawGraph(state)
    local lcdW, lcdH = lcd.getWindowSize()
    local gx = 0
    local gy = math.floor(form.height() + 2)
    local gw = lcdW - 1
    local gh = lcdH - gy - 2
    local pad = 6
    local px = gx + pad
    local py = gy + pad
    local pw = gw - (pad * 2)
    local ph = gh - (pad * 2)
    local minV
    local maxV
    local index
    local value
    local n
    local prevX
    local prevY
    local x
    local y
    local norm
    local summary

    if gh < 30 or pw < 20 or ph < 20 then
        return
    end

    for index = 1, #state.samples do
        value = state.samples[index]
        if minV == nil or value < minV then
            minV = value
        end
        if maxV == nil or value > maxV then
            maxV = value
        end
    end

    if minV == nil or maxV == nil then
        minV = -1
        maxV = 1
    elseif minV == maxV then
        minV = minV - 1
        maxV = maxV + 1
    end

    summary = (selectedSource(state) and selectedSource(state).label or "-") .. "  " .. state.lastValueText .. "  " .. state.lastStateText

    lcd.color((lcd.darkMode and lcd.darkMode()) and lcd.RGB(230, 230, 230) or lcd.RGB(20, 20, 20))
    lcd.drawText(px, py - 2, summary, LEFT)

    lcd.color((lcd.darkMode and lcd.darkMode()) and lcd.GREY(80) or lcd.GREY(180))
    for index = 0, 4 do
        y = py + math.floor((ph * index) / 4 + 0.5)
        lcd.drawLine(px, y, px + pw, y)
    end

    n = #state.samples
    if n < 2 then
        return
    end

    lcd.color((lcd.darkMode and lcd.darkMode()) and lcd.RGB(255, 255, 255) or lcd.RGB(0, 0, 0))
    for index = 1, n do
        x = px + math.floor(((index - 1) * pw) / math.max(1, n - 1) + 0.5)
        norm = (state.samples[index] - minV) / (maxV - minV)
        y = py + ph - math.floor(norm * ph + 0.5)

        if prevX and prevY then
            lcd.drawLine(prevX, prevY, x, y)
        end
        prevX, prevY = x, y
    end

    if prevX and prevY then
        lcd.color((lcd.darkMode and lcd.darkMode()) and lcd.RGB(255, 200, 0) or lcd.RGB(0, 120, 255))
        lcd.drawFilledCircle(prevX, prevY, 2)
    end
end

local function queueRead(node, command, apiName, parser, simulatorResponse)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local helper = mspTask and mspTask.mspHelper or nil

    if state.pending ~= nil or not helper or state.closed == true then
        return false
    end

    state.pending = apiName
    state.pendingAt = os.clock()

    return mspTask:queueCommand(command, {}, {
        timeout = 1.0,
        simulatorResponse = simulatorResponse,
        onReply = function(_, buf)
            if state.closed == true then
                return
            end
            local ok = parser(state, helper, buf)
            state.pending = nil
            state.lastStateText = ok and "@i18n(app.modules.rfstatus.ok)@" or "@i18n(app.modules.validate_sensors.invalid)@"
        end,
        onError = function()
            if state.closed == true then
                return
            end
            state.pending = nil
            state.lastStateText = "@i18n(app.modules.validate_sensors.invalid)@"
        end
    })
end

local function requestSelectedPacket(node)
    local source = selectedSource(node.state)

    if not source then
        return
    end

    if source.packet == "raw_imu" then
        queueRead(node, MSP_RAW_IMU, "RAW_IMU", parseRawImu, getRawImuSimResponse())
    elseif source.packet == "altitude" then
        queueRead(node, MSP_ALTITUDE, "ALTITUDE", parseAltitude, getAltitudeSimResponse())
    elseif source.packet == "sonar" then
        queueRead(node, MSP_SONAR, "SONAR", parseSonar, getSonarSimResponse())
    elseif source.packet == "debug" then
        queueRead(node, MSP_DEBUG, "DEBUG", parseDebug, getDebugSimResponse())
    end
end

function Page:open(ctx)
    local state = {
        sourceChoices = buildSourceChoices(),
        selectedSourceIdx = 1,
        samples = {},
        maxSamples = 180,
        lastValueText = "-",
        lastStateText = "@i18n(app.modules.fblsensors.wait)@",
        lastSampleAt = 0,
        samplePeriod = 0.08,
        pending = nil,
        pendingAt = 0,
        pendingTimeout = 1.0,
        pollingEnabled = false,
        rawImu = nil,
        altitude = nil,
        sonar = nil,
        debug = nil,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.fblsensors.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.fblsensors.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = false},
        state = state
    }

    function node:buildForm(app)
        self.app = app
        form.addChoiceField(form.addLine("@i18n(app.modules.fblsensors.source)@"), nil, state.sourceChoices,
            function()
                return state.selectedSourceIdx
            end,
            function(newValue)
                state.selectedSourceIdx = tonumber(newValue) or 1
                resetSamples(state)
            end)
    end

    function node:paint()
        drawGraph(state)
    end

    function node:wakeup()
        local now = os.clock()
        local session = self.app.framework.session
        local mspTask = self.app.framework:getTask("msp")
        local value

        if diagnostics.isSimulation() ~= true and session:get("telemetryState", false) ~= true then
            return
        end

        if state.pollingEnabled ~= true then
            if self.app:isLoaderActive() == true then
                return
            end
            state.pollingEnabled = true
            state.lastSampleAt = 0
        end

        if state.pending ~= nil and (now - state.pendingAt) > state.pendingTimeout then
            state.pending = nil
            state.lastStateText = "@i18n(app.modules.validate_sensors.invalid)@"
        end

        if (now - state.lastSampleAt) < state.samplePeriod then
            return
        end
        state.lastSampleAt = now

        if mspTask and mspTask.mspQueue and mspTask.mspQueue.isProcessed and mspTask.mspQueue:isProcessed() == true then
            requestSelectedPacket(self)
        end

        value = readSelectedValue(state)
        if type(value) == "number" then
            addSample(state, value)
            state.lastValueText = formatValue(value)
        else
            state.lastValueText = "-"
        end

        lcd.invalidate()
    end

    function node:reload()
        resetSamples(state)
        state.pollingEnabled = false
        return true
    end

    function node:close()
        state.closed = true
        state.pending = nil
        state.pollingEnabled = false
        state.rawImu = nil
        state.altitude = nil
        state.sonar = nil
        state.debug = nil
        state.samples = {}
    end

    return node
end

return Page
