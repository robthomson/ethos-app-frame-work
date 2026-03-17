--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "VTXTABLE_POWERLEVEL"

-- LuaFormatter off
local MSP_API_STRUCTURE_READ_DATA = {
    { field = "power_level",  type = "U8",  apiVersion = {12, 0, 6}, simResponse = {1}, mandatory = false },
    { field = "power_value",  type = "U16", apiVersion = {12, 0, 6}, simResponse = {25, 0}, mandatory = false },
    { field = "label_length", type = "U8",  apiVersion = {12, 0, 6}, simResponse = {3}, mandatory = false },
    { field = "label_1",      type = "U8",  apiVersion = {12, 0, 6}, simResponse = {50}, mandatory = false },
    { field = "label_2",      type = "U8",  apiVersion = {12, 0, 6}, simResponse = {53}, mandatory = false },
    { field = "label_3",      type = "U8",  apiVersion = {12, 0, 6}, simResponse = {77}, mandatory = false },
}
-- LuaFormatter on

local MSP_API_STRUCTURE_READ, MSP_MIN_BYTES, MSP_API_SIMULATOR_RESPONSE = core.prepareStructureData(MSP_API_STRUCTURE_READ_DATA)

local MSP_API_STRUCTURE_WRITE = {
    { field = "power_level",  type = "U8"  },
    { field = "power_value",  type = "U16" },
    { field = "label_length", type = "U8"  },
    { field = "label_1",      type = "U8"  },
    { field = "label_2",      type = "U8"  },
    { field = "label_3",      type = "U8"  },
}

local function parseRead(buf)
    local result = nil
    core.parseMSPData(API_NAME, buf, MSP_API_STRUCTURE_READ, nil, nil, function(parsed)
        result = parsed
    end)
    if result == nil then return nil, "parse_failed" end
    return result
end

local function buildReadPayload(payloadData, _, _, _, powerLevel)
    local readPower = tonumber(powerLevel)
    if readPower == nil then readPower = tonumber(payloadData.power_level) end
    if readPower == nil then readPower = 1 end
    return {readPower}
end

local function buildWritePayload(payloadData, _, _, state)
    return core.buildWritePayload(API_NAME, payloadData, MSP_API_STRUCTURE_WRITE, state.rebuildOnWrite == true)
end

return factory.create({
    name = API_NAME,
    readCmd = 138,
    writeCmd = 228,
    minBytes = MSP_MIN_BYTES,
    readStructure = MSP_API_STRUCTURE_READ,
    writeStructure = MSP_API_STRUCTURE_WRITE,
    simulatorResponseRead = MSP_API_SIMULATOR_RESPONSE,
    parseRead = parseRead,
    buildReadPayload = buildReadPayload,
    buildWritePayload = buildWritePayload,
    writeRequiresStructure = true,
    writeUuidFallback = true,
    initialRebuildOnWrite = true,
    readCompleteFn = function(state)
        return state.mspData ~= nil
    end
})
