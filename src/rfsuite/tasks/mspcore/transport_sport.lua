--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local transport = {}

local LOCAL_SENSOR_ID = 0x0D
local SPORT_REMOTE_SENSOR_ID = 0x1B
local FPORT_REMOTE_SENSOR_ID = 0x00
local REQUEST_FRAME_ID = 0x30
local REPLY_FRAME_ID = 0x32

local function hasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

function transport.new(session)
    return setmetatable({
        session = session,
        sensor = nil,
        inReply = false,
        expectedSeq = nil
    }, {__index = transport})
end

function transport:_ensureSensor()
    local moduleNumber

    if self.sensor then
        return self.sensor
    end

    if not sport or not sport.getSensor then
        return nil
    end

    moduleNumber = self.session:get("telemetryModuleNumber", 0) or 0
    self.sensor = sport.getSensor({module = moduleNumber, primId = REPLY_FRAME_ID})
    return self.sensor
end

function transport:mspSend(payload)
    local sensor = self:_ensureSensor()
    local dataId
    local value

    if not sensor then
        return false
    end

    dataId = (payload[1] or 0) + ((payload[2] or 0) * 256)
    value = (payload[3] or 0) +
        ((payload[4] or 0) * 256) +
        ((payload[5] or 0) * 65536) +
        ((payload[6] or 0) * 16777216)

    return sensor:pushFrame({
        physId = LOCAL_SENSOR_ID,
        primId = REQUEST_FRAME_ID,
        appId = dataId,
        value = value
    })
end

function transport:mspPoll()
    local sensor = self:_ensureSensor()
    local frame
    local sensorId
    local frameId
    local dataId
    local value
    local status
    local seq
    local nextSeq

    if not sensor then
        return nil
    end

    frame = sensor:popFrame()
    if not frame then
        return nil
    end

    sensorId = frame:physId()
    frameId = frame:primId()
    dataId = frame:appId()
    value = frame:value()

    if frameId ~= REPLY_FRAME_ID then
        return nil
    end
    if sensorId ~= SPORT_REMOTE_SENSOR_ID and sensorId ~= FPORT_REMOTE_SENSOR_ID then
        return nil
    end

    status = dataId % 256
    seq = status % 16

    if hasFlag(status, 16) then
        self.inReply = true
        self.expectedSeq = seq
    elseif self.inReply then
        nextSeq = ((self.expectedSeq or 0) + 1) % 16
        if seq == self.expectedSeq then
            return nil
        end
        if seq ~= nextSeq then
            self.inReply = false
            self.expectedSeq = nil
            return nil
        end
        self.expectedSeq = seq
    else
        return nil
    end

    return {
        dataId % 256,
        math.floor(dataId / 256) % 256,
        value % 256,
        math.floor(value / 256) % 256,
        math.floor(value / 65536) % 256,
        math.floor(value / 16777216) % 256
    }
end

function transport:reset()
    self.sensor = nil
    self.inReply = false
    self.expectedSeq = nil
end

return transport
