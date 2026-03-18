--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local Provider = {}
Provider.__index = Provider

local os_clock = os.clock
local math_floor = math.floor
local string_format = string.format
local system_getSource = system.getSource
local model_createSensor = model.createSensor

local CRSF_FRAME_CUSTOM_TELEM = 0x88
local REFRESH_INTERVAL_MS = 2500
local DEFAULT_POP_BUDGET_SECONDS = 0.2
local DEFAULT_PUBLISH_BUDGET_PER_FRAME = 50
local DEFAULT_MAX_FRAMES_PER_WAKEUP = 4
local DEFAULT_DIAG_LOG_COOLDOWN_SECONDS = 2.0
local DEFAULT_WAKEUP_BUDGET_LOG_EVERY = 25
local SID_LOOKUP_MODULE = "sensors.providers.elrs_sid_lookup"
local SID_LOOKUP_PATH = "sensors/providers/elrs_sid_lookup.lua"
local SENSOR_LIST_MODULE = "sensors.providers.elrs_sensors"
local SENSOR_LIST_PATH = "sensors/providers/elrs_sensors.lua"

local META_UID = {
    [0xEE01] = true,
    [0xEE02] = true,
    [0xEE03] = true,
    [0xEE04] = true,
    [0xEE05] = true,
    [0xEE06] = true
}

local function loadLuaModule(moduleName, path)
    local ok
    local result
    local chunk
    local loadErr

    ok, result = pcall(require, moduleName)
    if ok then
        return result
    end

    if not loadfile then
        return nil, result
    end

    chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr or result
    end

    ok, result = pcall(chunk)
    if ok then
        return result
    end

    return nil, result
end

local function unloadLuaModule(moduleName)
    if package and type(package.loaded) == "table" then
        package.loaded[moduleName] = nil
    end
end

local function loadTransientLuaModule(moduleName, path)
    local result
    local err

    result, err = loadLuaModule(moduleName, path)
    unloadLuaModule(moduleName)
    return result, err
end

local function decNil(_, pos)
    return nil, pos
end

local function decU8(data, pos)
    return data[pos], pos + 1
end

local function decS8(data, pos)
    local value, ptr = decU8(data, pos)
    return value < 0x80 and value or value - 0x100, ptr
end

local function decU16(data, pos)
    return (data[pos] << 8) | data[pos + 1], pos + 2
end

local function decS16(data, pos)
    local value, ptr = decU16(data, pos)
    return value < 0x8000 and value or value - 0x10000, ptr
end

local function decU12U12(data, pos)
    local a = ((data[pos] & 0x0F) << 8) | data[pos + 1]
    local b = ((data[pos] & 0xF0) << 4) | data[pos + 2]
    return a, b, pos + 3
end

local function decS12S12(data, pos)
    local a, b, ptr = decU12U12(data, pos)
    return a < 0x0800 and a or a - 0x1000, b < 0x0800 and b or b - 0x1000, ptr
end

local function decU24(data, pos)
    return (data[pos] << 16) | (data[pos + 1] << 8) | data[pos + 2], pos + 3
end

local function decS24(data, pos)
    local value, ptr = decU24(data, pos)
    return value < 0x800000 and value or value - 0x1000000, ptr
end

local function decU32(data, pos)
    return (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3], pos + 4
end

local function decS32(data, pos)
    local value, ptr = decU32(data, pos)
    return value < 0x80000000 and value or value - 0x100000000, ptr
end

local function decCellV(data, pos)
    local value, ptr = decU8(data, pos)
    return value > 0 and value + 200 or 0, ptr
end

local function nowMs()
    return math_floor(os_clock() * 1000)
end

local function telemetrySlotsSignature(slots)
    local parts = {}
    local i

    for i = 1, #slots do
        parts[#parts + 1] = tostring(slots[i] or 0)
    end

    return table.concat(parts, ",")
end

local function syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
    if not sensor then
        return
    end

    if name ~= nil then
        pcall(sensor.name, sensor, name)
    end
    if moduleNumber ~= nil then
        pcall(sensor.module, sensor, moduleNumber)
    end
    if minValue ~= nil then
        pcall(sensor.minimum, sensor, minValue)
    end
    if maxValue ~= nil then
        pcall(sensor.maximum, sensor, maxValue)
    end
    if decimals ~= nil then
        pcall(sensor.decimals, sensor, decimals)
        pcall(sensor.protocolDecimals, sensor, decimals)
    end
    if unit ~= nil then
        pcall(sensor.unit, sensor, unit)
        pcall(sensor.protocolUnit, sensor, unit)
    end
end

function Provider.new(framework)
    local self = setmetatable({
        framework = framework,
        useRawValue = utils.ethosVersionAtLeast({26, 1, 0}),
        strictUntilConfig = false,
        publishBudgetPerFrame = DEFAULT_PUBLISH_BUDGET_PER_FRAME,
        diagLogCooldownSeconds = DEFAULT_DIAG_LOG_COOLDOWN_SECONDS,
        wakeupBudgetLogEvery = DEFAULT_WAKEUP_BUDGET_LOG_EVERY,
        popBudgetSeconds = (framework.config and framework.config.elrsPopBudgetSeconds) or DEFAULT_POP_BUDGET_SECONDS,
        maxFramesPerWakeup = (framework.config and framework.config.elrsMaxFramesPerWakeup) or DEFAULT_MAX_FRAMES_PER_WAKEUP,
        sensors = {},
        lastValues = {},
        lastTimes = {},
        cachedCrsfSensor = nil,
        sidLookup = nil,
        sensorListFactory = nil,
        relevantSig = nil,
        relevantSidSet = nil,
        sensorsList = {},
        activeSensorsListSig = nil,
        decoderExports = nil,
        telemetryFrameId = 0,
        telemetryFrameSkip = 0,
        telemetryFrameCount = 0,
        lastFrameMs = nil,
        haveFrameId = false,
        publishOverflowCount = 0,
        wakeupBudgetBreakCount = 0,
        parseBreakCount = 0,
        lastDiagLogAt = {
            publish_overflow = 0,
            wakeup_budget = 0,
            parse_break = 0
        }
    }, Provider)

    self.decoderExports = self:_buildDecoderExports()
    return self
end

function Provider:_sessionGet(key, default)
    return self.framework.session:get(key, default)
end

function Provider:_moduleNumber()
    local source = self:_sessionGet("telemetrySensor", nil)

    if source and type(source.module) == "function" then
        return source:module()
    end

    return self:_sessionGet("telemetryModuleNumber", 0) or 0
end

function Provider:_currentCrsfSensor()
    if self.cachedCrsfSensor then
        return self.cachedCrsfSensor
    end

    if crsf and crsf.getSensor ~= nil then
        self.cachedCrsfSensor = crsf.getSensor()
        return self.cachedCrsfSensor
    end

    return nil
end

function Provider:_popFrame(...)
    local sensor = self:_currentCrsfSensor()

    if sensor and sensor.popFrame then
        return sensor:popFrame(...)
    end
    if crsf and crsf.popFrame then
        return crsf.popFrame(...)
    end

    return nil
end

function Provider:_sidIsRelevant(sid)
    if META_UID[sid] then
        return true
    end

    if self.relevantSidSet == nil then
        return self.strictUntilConfig ~= true
    end

    return self.relevantSidSet[sid] == true
end

function Provider:_loadSidLookup()
    local sidLookup
    local sidLookupErr

    if self.sidLookup ~= nil then
        return self.sidLookup
    end

    sidLookup, sidLookupErr = loadTransientLuaModule(SID_LOOKUP_MODULE, SID_LOOKUP_PATH)
    if type(sidLookup) ~= "table" then
        utils.log("[elrs] Failed to load SID lookup table: " .. tostring(sidLookupErr or "invalid_table"), "error")
        sidLookup = {}
    end

    self.sidLookup = sidLookup
    return self.sidLookup
end

function Provider:_releaseSidLookup()
    self.sidLookup = nil
end

function Provider:_loadSensorListFactory()
    local sensorListFactory
    local sensorListFactoryErr

    if self.sensorListFactory ~= nil then
        return self.sensorListFactory
    end

    sensorListFactory, sensorListFactoryErr = loadTransientLuaModule(SENSOR_LIST_MODULE, SENSOR_LIST_PATH)
    if type(sensorListFactory) ~= "function" then
        utils.log("[elrs] Failed to load sensor list factory: " .. tostring(sensorListFactoryErr or "invalid_factory"), "error")
        sensorListFactory = function()
            return {}
        end
    end

    self.sensorListFactory = sensorListFactory
    return self.sensorListFactory
end

function Provider:_releaseSensorListFactory()
    self.sensorListFactory = nil
end

function Provider:_resetPublishedSensors()
    self.sensors = {}
    self.lastValues = {}
    self.lastTimes = {}
end

function Provider:_ensureTelemetrySensor(uid, name, unit, decimals, minValue, maxValue)
    local sensor = self.sensors[uid]
    local moduleNumber = self:_moduleNumber()

    if sensor then
        syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
        return sensor
    end

    sensor = system_getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = uid})
    if sensor then
        syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
        self.sensors[uid] = sensor
        return sensor
    end

    if self:_sessionGet("telemetryState", false) ~= true then
        return nil
    end

    sensor = model_createSensor({type = SENSOR_TYPE_DIY})
    sensor:appId(uid)
    syncSensorMetadata(sensor, name, unit, decimals, minValue or -1000000000, maxValue or 2147483647, moduleNumber)
    self.sensors[uid] = sensor
    return sensor
end

function Provider:_publishSensorValue(uid, value, unit, decimals, name, minValue, maxValue)
    local sensor
    local now
    local stale

    if value == nil or self:_sessionGet("telemetryState", false) ~= true or not self:_sidIsRelevant(uid) then
        return
    end

    sensor = self:_ensureTelemetrySensor(uid, name, unit, decimals, minValue, maxValue)
    if not sensor then
        return
    end

    now = nowMs()
    stale = (now - (self.lastTimes[uid] or 0)) >= REFRESH_INTERVAL_MS

    if self.lastValues[uid] ~= value or stale then
        if self.useRawValue and type(sensor.rawValue) == "function" then
            sensor:rawValue(value)
        else
            sensor:value(value)
        end
        self.lastValues[uid] = value
        self.lastTimes[uid] = now
    end

    if type(sensor.state) == "function" and sensor:state() == false then
        self.sensors[uid] = nil
        self.lastValues[uid] = nil
        self.lastTimes[uid] = nil
    end
end

function Provider:_refreshStaleSensors()
    local now = nowMs()
    local uid
    local sensor
    local value
    local lastTime

    for uid, sensor in pairs(self.sensors) do
        value = self.lastValues[uid]
        lastTime = self.lastTimes[uid]
        if sensor and value ~= nil and lastTime and (now - lastTime) > REFRESH_INTERVAL_MS then
            if self.useRawValue and type(sensor.rawValue) == "function" then
                sensor:rawValue(value)
            else
                sensor:value(value)
            end
            self.lastTimes[uid] = now
        end
    end
end

function Provider:_rebuildRelevantSidSet()
    local config = self:_sessionGet("telemetryConfig", nil)
    local sidLookup
    local signature
    local index
    local slotId
    local appIds
    local sidIndex

    if type(config) ~= "table" then
        self.relevantSig = nil
        self.relevantSidSet = nil
        return
    end

    signature = telemetrySlotsSignature(config)
    if self.relevantSig == signature and self.relevantSidSet ~= nil then
        return
    end

    self.relevantSig = signature
    self.relevantSidSet = {}
    sidLookup = self:_loadSidLookup()

    for index = 1, #config do
        slotId = config[index]
        appIds = sidLookup[slotId]
        if appIds then
            for sidIndex = 1, #appIds do
                if appIds[sidIndex] then
                    self.relevantSidSet[appIds[sidIndex]] = true
                end
            end
        end
    end

    self:_releaseSidLookup()
end

function Provider:_rebuildActiveSensorsList(force)
    local signature = self.relevantSig or "__all__"
    local sensorListFactory
    local fullList
    local nextList
    local sid
    local sensor

    if not force and self.activeSensorsListSig == signature and next(self.sensorsList) ~= nil then
        return
    end

    sensorListFactory = self:_loadSensorListFactory()
    fullList = sensorListFactory(self.decoderExports)
    if type(fullList) ~= "table" then
        utils.log("[elrs] Sensor list factory did not return a table", "error")
        self.sensorsList = {}
        self.activeSensorsListSig = signature
        self:_releaseSensorListFactory()
        return
    end

    nextList = {}
    for sid, sensor in pairs(fullList) do
        if self:_sidIsRelevant(sid) then
            nextList[sid] = sensor
        else
            nextList[sid] = {dec = sensor.dec}
        end
    end

    self.sensorsList = nextList
    self.activeSensorsListSig = signature
    self:_releaseSensorListFactory()
end

function Provider:_logDiag(kind, message, level)
    local now = os_clock()
    local last = self.lastDiagLogAt[kind] or 0

    if now - last < (self.diagLogCooldownSeconds or DEFAULT_DIAG_LOG_COOLDOWN_SECONDS) then
        return
    end

    self.lastDiagLogAt[kind] = now
    utils.log(message, level or "debug")
end

function Provider:_muteSensorLost()
    local telemetrySensor = self:_sessionGet("telemetrySensor", nil)
    local module

    if not telemetrySensor or type(telemetrySensor.module) ~= "function" then
        return
    end

    module = model.getModule(telemetrySensor:module())
    if module and module.muteSensorLost ~= nil then
        module:muteSensorLost(5.0)
    end
end

function Provider:_crossfirePop()
    local command
    local data
    local fid
    local sid
    local ptr
    local published
    local publishOverflowed
    local tnow

    if self:_sessionGet("telemetryState", false) ~= true then
        self:_muteSensorLost()
        self:_resetPublishedSensors()
        return false
    end

    command, data = self:_popFrame(CRSF_FRAME_CUSTOM_TELEM)
    if not command or not data then
        return false
    end

    self:_rebuildRelevantSidSet()
    self:_rebuildActiveSensorsList()

    ptr = 3
    fid, ptr = decU8(data, ptr)
    if self.haveFrameId then
        local delta = (fid - self.telemetryFrameId) & 0xFF
        if delta > 1 then
            self.telemetryFrameSkip = self.telemetryFrameSkip + (delta - 1)
        end
    else
        self.haveFrameId = true
    end
    self.telemetryFrameId = fid
    self.telemetryFrameCount = self.telemetryFrameCount + 1

    tnow = nowMs()
    if self.lastFrameMs ~= nil then
        self:_publishSensorValue(0xEE03, tnow - self.lastFrameMs, UNIT_MILLISECOND, 0, "@i18n(sensors.debug.frame_delta_ms)@", 0, 60000)
    end
    self.lastFrameMs = tnow

    published = 0
    publishOverflowed = false

    for _ = 1, #data do
        local sensor
        local previousPtr
        local ok
        local value
        local nextPtr

        if ptr >= #data then
            break
        end

        sid, ptr = decU16(data, ptr)
        sensor = self.sensorsList[sid]
        if not sensor then
            self.parseBreakCount = self.parseBreakCount + 1
            self:_logDiag("parse_break", string_format("[elrs] telemetry parse break: unknown sid=0x%04X", sid), "info")
            break
        end

        previousPtr = ptr
        ok, value, nextPtr = pcall(sensor.dec, data, ptr)
        if not ok then
            self.parseBreakCount = self.parseBreakCount + 1
            self:_logDiag("parse_break", string_format("[elrs] telemetry parse break: sid=0x%04X decode error", sid), "info")
            break
        end

        ptr = nextPtr or previousPtr
        if ptr <= previousPtr then
            self.parseBreakCount = self.parseBreakCount + 1
            self:_logDiag("parse_break", string_format("[elrs] telemetry parse break: sid=0x%04X decoder made no progress", sid), "info")
            break
        end

        if value ~= nil and sensor.name ~= nil then
            if published < (self.publishBudgetPerFrame or DEFAULT_PUBLISH_BUDGET_PER_FRAME) then
                self:_publishSensorValue(sid, value, sensor.unit, sensor.prec, sensor.name, sensor.min, sensor.max)
                published = published + 1
            elseif not publishOverflowed then
                publishOverflowed = true
                self.publishOverflowCount = self.publishOverflowCount + 1
                self:_logDiag(
                    "publish_overflow",
                    string_format(
                        "[elrs] telemetry publish overflow: frameId=%d sid=0x%04X budget=%d",
                        self.telemetryFrameId,
                        sid,
                        self.publishBudgetPerFrame or DEFAULT_PUBLISH_BUDGET_PER_FRAME
                    ),
                    "info"
                )
            end
        end
    end

    self:_publishSensorValue(0xEE01, self.telemetryFrameCount, UNIT_RAW, 0, "@i18n(sensors.debug.frame_count)@", 0, 2147483647)
    self:_publishSensorValue(0xEE02, self.telemetryFrameSkip, UNIT_RAW, 0, "@i18n(sensors.debug.frame_skip)@", 0, 2147483647)

    return true
end

function Provider:_buildDecoderExports()
    return {
        decNil = decNil,
        decU8 = decU8,
        decS8 = decS8,
        decU16 = decU16,
        decS16 = decS16,
        decU24 = decU24,
        decS24 = decS24,
        decU32 = decU32,
        decS32 = decS32,
        decCellV = decCellV,
        decCells = function(data, pos)
            return self:_decCells(data, pos)
        end,
        decControl = function(data, pos)
            return self:_decControl(data, pos)
        end,
        decAttitude = function(data, pos)
            return self:_decAttitude(data, pos)
        end,
        decAccel = function(data, pos)
            return self:_decAccel(data, pos)
        end,
        decLatLong = function(data, pos)
            return self:_decLatLong(data, pos)
        end,
        decAdjFunc = function(data, pos)
            return self:_decAdjFunc(data, pos)
        end
    }
end

function Provider:_decCells(data, pos)
    local count
    local value
    local voltage
    local index

    count, pos = decU8(data, pos)
    self:_publishSensorValue(0x1020, count, UNIT_RAW, 0, "@i18n(sensors.power.cell_count)@", 0, 15)

    for index = 1, count do
        value, pos = decU8(data, pos)
        value = value > 0 and value + 200 or 0
        voltage = (count << 24) | ((index - 1) << 16) | value
        self:_publishSensorValue(0x102F, voltage, UNIT_CELLS, 2, "@i18n(sensors.power.cell_voltages)@", 0, 455)
    end

    return nil, pos
end

function Provider:_decControl(data, pos)
    local roll
    local pitch
    local yaw
    local collective

    pitch, roll, pos = decS12S12(data, pos)
    yaw, collective, pos = decS12S12(data, pos)

    self:_publishSensorValue(0x1031, pitch, UNIT_DEGREE, 2, "@i18n(sensors.control.pitch)@", -4500, 4500)
    self:_publishSensorValue(0x1032, roll, UNIT_DEGREE, 2, "@i18n(sensors.control.roll)@", -4500, 4500)
    self:_publishSensorValue(0x1033, 3 * yaw, UNIT_DEGREE, 2, "@i18n(sensors.control.yaw)@", -9000, 9000)
    self:_publishSensorValue(0x1034, collective, UNIT_DEGREE, 2, "@i18n(sensors.control.collective)@", -4500, 4500)

    return nil, pos
end

function Provider:_decAttitude(data, pos)
    local pitch
    local roll
    local yaw

    pitch, pos = decS16(data, pos)
    roll, pos = decS16(data, pos)
    yaw, pos = decS16(data, pos)

    self:_publishSensorValue(0x1101, pitch, UNIT_DEGREE, 1, "@i18n(sensors.attitude.pitch)@", -1800, 3600)
    self:_publishSensorValue(0x1102, roll, UNIT_DEGREE, 1, "@i18n(sensors.attitude.roll)@", -1800, 3600)
    self:_publishSensorValue(0x1103, yaw, UNIT_DEGREE, 1, "@i18n(sensors.attitude.yaw)@", -1800, 3600)

    return nil, pos
end

function Provider:_decAccel(data, pos)
    local x
    local y
    local z

    x, pos = decS16(data, pos)
    y, pos = decS16(data, pos)
    z, pos = decS16(data, pos)

    self:_publishSensorValue(0x1111, x, UNIT_G, 2, "@i18n(sensors.accel.x)@", -4000, 4000)
    self:_publishSensorValue(0x1112, y, UNIT_G, 2, "@i18n(sensors.accel.y)@", -4000, 4000)
    self:_publishSensorValue(0x1113, z, UNIT_G, 2, "@i18n(sensors.accel.z)@", -4000, 4000)

    return nil, pos
end

function Provider:_decLatLong(data, pos)
    local latitude
    local longitude

    latitude, pos = decS32(data, pos)
    longitude, pos = decS32(data, pos)

    latitude = math_floor(latitude * 0.001)
    longitude = math_floor(longitude * 0.001)

    self:_publishSensorValue(0x1125, latitude, UNIT_DEGREE, 4, "@i18n(sensors.gps.latitude)@", -10000000000, 10000000000)
    self:_publishSensorValue(0x112B, longitude, UNIT_DEGREE, 4, "@i18n(sensors.gps.longitude)@", -10000000000, 10000000000)

    return nil, pos
end

function Provider:_decAdjFunc(data, pos)
    local func
    local value

    func, pos = decU16(data, pos)
    value, pos = decS32(data, pos)

    self:_publishSensorValue(0x1221, func, UNIT_RAW, 0, "@i18n(sensors.control.adjustment_source)@", 0, 255)
    self:_publishSensorValue(0x1222, value, UNIT_RAW, 0, "@i18n(sensors.control.adjustment_value)@")

    return nil, pos
end

function Provider:wakeup()
    local budget
    local deadline
    local popCount
    local maxFrames
    local frameIndex

    if not self:_sessionGet("isConnected", false) then
        return
    end

    self:_rebuildRelevantSidSet()

    if self:_sessionGet("telemetryState", false) and self:_sessionGet("telemetrySensor", nil) then
        budget = self.popBudgetSeconds or DEFAULT_POP_BUDGET_SECONDS
        deadline = budget > 0 and (os_clock() + budget) or nil
        maxFrames = tonumber(self.maxFramesPerWakeup) or DEFAULT_MAX_FRAMES_PER_WAKEUP
        popCount = 0

        for frameIndex = 1, maxFrames do
            if not self:_crossfirePop() then
                break
            end

            popCount = popCount + 1
            if deadline and os_clock() >= deadline then
                self.wakeupBudgetBreakCount = self.wakeupBudgetBreakCount + 1
                break
            end
        end

        self:_publishSensorValue(0xEE05, self.wakeupBudgetBreakCount, UNIT_RAW, 0, "@i18n(sensors.debug.wakeup_break)@", 0, 2147483647)
        self:_refreshStaleSensors()
    else
        self:_resetPublishedSensors()
    end
end

function Provider:reset()
    local uid
    local sensor

    for uid, sensor in pairs(self.sensors) do
        if sensor then
            sensor:reset()
        end
    end

    self:_resetPublishedSensors()
    self.cachedCrsfSensor = nil
    self.sidLookup = nil
    self.sensorListFactory = nil
    self.relevantSig = nil
    self.relevantSidSet = nil
    self.sensorsList = {}
    self.activeSensorsListSig = nil
    self.telemetryFrameId = 0
    self.telemetryFrameSkip = 0
    self.telemetryFrameCount = 0
    self.lastFrameMs = nil
    self.haveFrameId = false
    self.publishOverflowCount = 0
    self.wakeupBudgetBreakCount = 0
    self.parseBreakCount = 0
    self.lastDiagLogAt.publish_overflow = 0
    self.lastDiagLogAt.wakeup_budget = 0
    self.lastDiagLogAt.parse_break = 0
end

return Provider
