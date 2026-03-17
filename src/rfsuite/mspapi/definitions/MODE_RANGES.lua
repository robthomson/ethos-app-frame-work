--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "MODE_RANGES"

local function buildSimulatorResponse()
    local response = {1, 0, 216, 40, 0, 0, 80, 120}
    for _ = 1, 18 do
        response[#response + 1] = 0
        response[#response + 1] = 0
        response[#response + 1] = 136
        response[#response + 1] = 136
    end
    return response
end

local SIMULATOR_RESPONSE = buildSimulatorResponse()

local function parseRead(buf)
    local helper = rfsuite.tasks and rfsuite.tasks.msp and rfsuite.tasks.msp.mspHelper
    if not helper then return nil, "msp_helper_missing" end

    local parsed = {}
    local ranges = {}

    buf.offset = 1
    while true do
        local modeId = helper.readU8(buf)
        if modeId == nil then break end

        local auxChannelIndex = helper.readU8(buf)
        local startStep = helper.readS8(buf)
        local endStep = helper.readS8(buf)
        if auxChannelIndex == nil or startStep == nil or endStep == nil then break end

        ranges[#ranges + 1] = {
            id = modeId,
            auxChannelIndex = auxChannelIndex,
            range = {
                start = 1500 + (startStep * 5),
                ["end"] = 1500 + (endStep * 5)
            }
        }
    end

    parsed.mode_ranges = ranges
    return {parsed = parsed, buffer = buf}
end

return factory.create({
    name = API_NAME,
    readCmd = 34,
    minBytes = 0,
    simulatorResponseRead = SIMULATOR_RESPONSE,
    parseRead = parseRead,
    readCompleteFn = function(state)
        return state.mspData ~= nil
    end
})
