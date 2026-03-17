--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local mspHelper = {}

local function normalizeByteOrder(byteorder)
    if byteorder == "big" then
        return "big"
    end

    return "little"
end

function mspHelper.readUInt(buf, numBytes, byteorder)
    local offset = buf.offset or 1
    local value = 0
    local i

    if not buf[offset] or not buf[offset + numBytes - 1] then
        return nil
    end

    if normalizeByteOrder(byteorder) == "big" then
        for i = 0, numBytes - 1 do
            value = value * 256 + (buf[offset + i] or 0)
        end
    else
        for i = numBytes - 1, 0, -1 do
            value = value * 256 + (buf[offset + i] or 0)
        end
    end

    buf.offset = offset + numBytes
    return value
end

function mspHelper.readSInt(buf, numBytes, byteorder)
    local value = mspHelper.readUInt(buf, numBytes, byteorder)
    local maxUnsigned

    if value == nil then
        return nil
    end

    maxUnsigned = 2 ^ (8 * numBytes)
    if value >= (maxUnsigned / 2) then
        value = value - maxUnsigned
    end

    return value
end

function mspHelper.writeUInt(buf, value, numBytes, byteorder)
    local bytes = {}
    local i

    value = tonumber(value) or 0

    for i = 1, numBytes do
        bytes[i] = value % 256
        value = math.floor(value / 256)
    end

    if normalizeByteOrder(byteorder) == "big" then
        for i = numBytes, 1, -1 do
            buf[#buf + 1] = bytes[i]
        end
    else
        for i = 1, numBytes do
            buf[#buf + 1] = bytes[i]
        end
    end
end

function mspHelper.writeSInt(buf, value, numBytes, byteorder)
    value = tonumber(value) or 0
    if value < 0 then
        value = value + (2 ^ (8 * numBytes))
    end
    mspHelper.writeUInt(buf, value, numBytes, byteorder)
end

for bits = 8, 512, 8 do
    local bytes = bits / 8

    mspHelper["readU" .. bits] = function(buf, byteorder)
        return mspHelper.readUInt(buf, bytes, byteorder)
    end

    mspHelper["readS" .. bits] = function(buf, byteorder)
        return mspHelper.readSInt(buf, bytes, byteorder)
    end

    mspHelper["writeU" .. bits] = function(buf, value, byteorder)
        mspHelper.writeUInt(buf, value, bytes, byteorder)
    end

    mspHelper["writeS" .. bits] = function(buf, value, byteorder)
        mspHelper.writeSInt(buf, value, bytes, byteorder)
    end
end

function mspHelper.readRAW(buf)
    return mspHelper.readU8(buf)
end

function mspHelper.writeRAW(buf, value)
    buf[#buf + 1] = (tonumber(value) or 0) % 256
end

return mspHelper
