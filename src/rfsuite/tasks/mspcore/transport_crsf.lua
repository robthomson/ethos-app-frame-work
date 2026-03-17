--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local transport = {}

local CRSF_ADDRESS_BETAFLIGHT = 0xC8
local CRSF_ADDRESS_RADIO_TRANSMITTER = 0xEA
local CRSF_FRAMETYPE_MSP_REQ = 0x7A
local CRSF_FRAMETYPE_MSP_RESP = 0x7B
local CRSF_FRAMETYPE_MSP_WRITE = 0x7C

function transport.new()
    return setmetatable({
        sensor = nil,
        frameType = CRSF_FRAMETYPE_MSP_REQ,
        payload = {0, 0}
    }, {__index = transport})
end

function transport:_ensureSensor()
    if self.sensor then
        return self.sensor
    end

    if not crsf or not crsf.getSensor then
        return nil
    end

    self.sensor = crsf.getSensor()
    return self.sensor
end

function transport:setWriteMode(isWrite)
    if isWrite then
        self.frameType = CRSF_FRAMETYPE_MSP_WRITE
    else
        self.frameType = CRSF_FRAMETYPE_MSP_REQ
    end
end

function transport:mspSend(payload)
    local sensor = self:_ensureSensor()
    local i

    if not sensor then
        return false
    end

    self.payload[1] = CRSF_ADDRESS_BETAFLIGHT
    self.payload[2] = CRSF_ADDRESS_RADIO_TRANSMITTER

    for i = 1, #payload do
        self.payload[i + 2] = payload[i]
    end
    for i = #payload + 3, #self.payload do
        self.payload[i] = nil
    end

    return sensor:pushFrame(self.frameType, self.payload)
end

function transport:mspPoll()
    local sensor = self:_ensureSensor()
    local command
    local data
    local buffer
    local i

    if not sensor then
        return nil
    end

    command, data = sensor:popFrame(CRSF_FRAMETYPE_MSP_RESP)
    if not command or not data then
        return nil
    end

    if data[1] ~= CRSF_ADDRESS_RADIO_TRANSMITTER or data[2] ~= CRSF_ADDRESS_BETAFLIGHT then
        return nil
    end

    buffer = {}
    for i = 3, #data do
        buffer[#buffer + 1] = data[i]
    end

    return buffer
end

function transport:reset()
    self.sensor = nil
    self.frameType = CRSF_FRAMETYPE_MSP_REQ
end

return transport
