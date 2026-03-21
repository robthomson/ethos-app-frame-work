--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local codec = {}

local function bxor(a, b)
    local result = 0
    local bit = 1

    while a > 0 or b > 0 do
        local abit = a % 2
        local bbit = b % 2
        if abit ~= bbit then
            result = result + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end

    return result
end

local function hasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

function codec.new()
    return setmetatable({
        protocolVersion = 1,
        txSeq = 0,
        rxSeq = 0,
        txBuffer = {},
        txIndex = 1,
        txCrc = 0,
        lastRequest = 0,
        rxBuffer = {},
        rxError = false,
        rxSize = 0,
        rxRequest = 0,
        rxStarted = false,
        rxCrc = 0,
        crcErrorCount = 0,
        lastRxCommand = 0
    }, {__index = codec})
end

function codec:setProtocolVersion(version)
    self.protocolVersion = (tonumber(version) == 2) and 2 or 1
    self:clear()
end

function codec:getProtocolVersion()
    return self.protocolVersion
end

function codec:clear()
    self.txSeq = 0
    self.txBuffer = {}
    self.txIndex = 1
    self.txCrc = 0
    self.lastRequest = 0
    self.rxBuffer = {}
    self.rxError = false
    self.rxSize = 0
    self.rxRequest = 0
    self.rxStarted = false
    self.rxSeq = 0
    self.rxCrc = 0
    self.lastRxCommand = 0
end

function codec:sendRequest(command, payload)
    local data = payload or {}
    local buffer = self.txBuffer
    local i

    if #buffer > 0 then
        return false, "tx_busy"
    end

    if self.protocolVersion == 1 then
        buffer[1] = #data
        buffer[2] = command % 256
        for i = 1, #data do
            buffer[i + 2] = data[i] % 256
        end
    else
        buffer[1] = 0
        buffer[2] = command % 256
        buffer[3] = math.floor(command / 256) % 256
        buffer[4] = #data % 256
        buffer[5] = math.floor(#data / 256) % 256
        for i = 1, #data do
            buffer[#buffer + 1] = data[i] % 256
        end
    end

    self.lastRequest = command
    self.txIndex = 1
    self.txCrc = 0

    return true
end

function codec:_statusByte(isStart)
    local versionBits = (self.protocolVersion == 2) and 64 or 32
    local status = (self.txSeq % 16) + versionBits
    if isStart then
        status = status + 16
    end
    return status
end

function codec:processTx(transport, protocol)
    local maxTx = protocol and protocol.maxTxBufferSize or 6
    local chunk = {}
    local i = 2
    local value

    if #self.txBuffer == 0 then
        return false
    end

    chunk[1] = self:_statusByte(self.txIndex == 1)
    self.txSeq = (self.txSeq + 1) % 16

    while i <= maxTx and self.txIndex <= #self.txBuffer do
        value = self.txBuffer[self.txIndex] or 0
        chunk[i] = value
        self.txIndex = self.txIndex + 1
        if self.protocolVersion == 1 then
            self.txCrc = bxor(self.txCrc, value)
        end
        i = i + 1
    end

    if self.protocolVersion == 1 then
        if i <= maxTx then
            chunk[i] = self.txCrc
            i = i + 1
            self.txBuffer = {}
            self.txIndex = 1
            self.txCrc = 0
        end
    else
        if self.txIndex > #self.txBuffer then
            self.txBuffer = {}
            self.txIndex = 1
            self.txCrc = 0
        end
    end

    while i <= maxTx do
        chunk[i] = 0
        i = i + 1
    end

    transport:mspSend(chunk)

    return #self.txBuffer > 0
end

function codec:_resetRx()
    self.rxBuffer = {}
    self.rxError = false
    self.rxSize = 0
    self.rxRequest = 0
    self.rxStarted = false
    self.rxSeq = 0
    self.rxCrc = 0
end

function codec:_receiveReply(packet, maxRx)
    local status = packet[1] or 0
    local versionBits = math.floor(status / 32) % 4
    local isStart = hasFlag(status, 16)
    local seq = status % 16
    local idx = 2
    local value

    if isStart then
        self.rxBuffer = {}
        self.rxError = status >= 128

        if self.protocolVersion == 2 then
            idx = idx + 1
            self.rxRequest = (packet[idx] or 0) + ((packet[idx + 1] or 0) * 256)
            idx = idx + 2
            self.rxSize = (packet[idx] or 0) + ((packet[idx + 1] or 0) * 256)
            idx = idx + 2
            self.rxStarted = (self.rxRequest == self.lastRequest)
        else
            self.rxSize = packet[idx] or 0
            idx = idx + 1
            self.rxRequest = self.lastRequest
            if versionBits == 1 then
                self.rxRequest = packet[idx] or 0
                idx = idx + 1
            end
            self.rxCrc = bxor(self.rxSize, self.rxRequest)
            self.rxStarted = (self.rxRequest == self.lastRequest)
        end
    else
        if (not self.rxStarted) or (((self.rxSeq + 1) % 16) ~= seq) then
            self:_resetRx()
            return nil
        end
    end

    while idx <= maxRx and #self.rxBuffer < self.rxSize do
        value = packet[idx]
        if value == nil then
            break
        end
        self.rxBuffer[#self.rxBuffer + 1] = value
        if self.protocolVersion == 1 then
            self.rxCrc = bxor(self.rxCrc, value)
        end
        idx = idx + 1
    end

    if #self.rxBuffer < self.rxSize then
        self.rxSeq = seq
        return false
    end

    self.rxStarted = false

    if self.protocolVersion == 1 then
        local rxCrc = packet[idx] or 0
        if self.rxCrc ~= rxCrc and versionBits == 0 then
            self.crcErrorCount = (tonumber(self.crcErrorCount) or 0) + 1
            self.lastRxCommand = self.rxRequest or self.lastRequest or 0
            self:_resetRx()
            return nil
        end
    end

    self.lastRxCommand = self.rxRequest or 0
    self.lastRequest = 0
    return true
end

function codec:pollReply(transport, protocol)
    local sliceSeconds = protocol and protocol.pollSliceSeconds or 0.006
    local slicePolls = protocol and protocol.pollSlicePolls or 4
    local maxRx = protocol and protocol.maxRxBufferSize or 6
    local deadline = os.clock() + sliceSeconds
    local polls = 0
    local packet
    local done

    while polls < slicePolls and os.clock() < deadline do
        polls = polls + 1
        packet = transport:mspPoll()
        if not packet then
            return nil, nil, nil
        end

        done = self:_receiveReply(packet, maxRx)
        if done == true then
            return self.rxRequest, self.rxBuffer, self.rxError
        end
    end

    return nil, nil, nil
end

return codec
