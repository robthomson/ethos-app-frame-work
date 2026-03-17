--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local os_time = os.time

local function parseRead(buf, helper)
    if not helper then return nil, "msp_helper_missing" end

    buf.offset = 1
    local year = helper.readU16(buf)
    local month = helper.readU8(buf)
    local day = helper.readU8(buf)
    local hours = helper.readU8(buf)
    local minutes = helper.readU8(buf)
    local seconds = helper.readU8(buf)
    local milliseconds = helper.readU16(buf)

    if year == nil or month == nil or day == nil or hours == nil or minutes == nil or seconds == nil or milliseconds == nil then
        return nil, "parse_failed"
    end

    return {
        parsed = {
            year = year,
            month = month,
            day = day,
            hours = hours,
            minutes = minutes,
            seconds = seconds,
            milliseconds = milliseconds
        },
        buffer = buf,
        receivedBytesCount = #buf
    }
end

local function buildWritePayload(payloadData, _, helper)
    if not helper then return nil, "msp_helper_missing" end

    local payload = {}
    local seconds = payloadData.seconds
    local milliseconds = payloadData.milliseconds
    if seconds == nil then seconds = os_time() end
    if milliseconds == nil then milliseconds = 0 end

    helper.writeU32(payload, seconds)
    helper.writeU16(payload, milliseconds)
    return payload
end

return factory.create({
    name = "RTC",
    readCmd = 247,
    writeCmd = 246,
    minBytes = 9,
    simulatorResponseRead = {233, 7, 1, 1, 0, 0, 0, 0, 0},
    parseRead = parseRead,
    buildWritePayload = buildWritePayload
})
