--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "LED_STRIP_CONFIG"
local MSP_API_CMD_READ = 48
local MSP_API_CMD_WRITE = 49
local MSP_REBUILD_ON_WRITE = true
local LED_MAX_STRIP_LENGTH = 32

local MSP_API_STRUCTURE_READ_DATA = {}
for i = 1, LED_MAX_STRIP_LENGTH do
    MSP_API_STRUCTURE_READ_DATA[#MSP_API_STRUCTURE_READ_DATA + 1] = { field = "led_config_" .. i, type = "U64", apiVersion = {12, 0, 6}, simResponse = {0,0,0,0,0,0,0,0} }
end
MSP_API_STRUCTURE_READ_DATA[#MSP_API_STRUCTURE_READ_DATA + 1] = { field = "advanced_profile_support", type = "U8", apiVersion = {12, 0, 6}, simResponse = {1} }
MSP_API_STRUCTURE_READ_DATA[#MSP_API_STRUCTURE_READ_DATA + 1] = { field = "ledstrip_profile", type = "U8", apiVersion = {12, 0, 6}, simResponse = {0} }

local MSP_API_STRUCTURE_READ, MSP_MIN_BYTES, MSP_API_SIMULATOR_RESPONSE = core.prepareStructureData(MSP_API_STRUCTURE_READ_DATA)

local MSP_API_STRUCTURE_WRITE = {
    { field = "index",           type = "U8"  },
    { field = "led_config",      type = "U64" },
    { field = "ledstrip_profile",type = "U8"  },
}

local function parseRead(buf)
    local result = nil
    core.parseMSPData(API_NAME, buf, MSP_API_STRUCTURE_READ, nil, nil, function(parsed)
        result = parsed
    end)
    if result == nil then
        return nil, "parse_failed"
    end
    return result
end

local function buildWritePayload(payloadData, _, _, state)
    local writeStructure = MSP_API_STRUCTURE_WRITE
    if writeStructure == nil then return {} end
    return core.buildWritePayload(API_NAME, payloadData, writeStructure, state.rebuildOnWrite == true)
end

return factory.create({
    name = API_NAME,
    readCmd = MSP_API_CMD_READ,
    writeCmd = MSP_API_CMD_WRITE,
    minBytes = MSP_MIN_BYTES or 0,
    readStructure = MSP_API_STRUCTURE_READ,
    writeStructure = MSP_API_STRUCTURE_WRITE,
    simulatorResponseRead = MSP_API_SIMULATOR_RESPONSE or {},
    parseRead = parseRead,
    buildWritePayload = buildWritePayload,
    writeRequiresStructure = true,
    writeUuidFallback = true,
    initialRebuildOnWrite = (MSP_REBUILD_ON_WRITE == true),
    readCompleteFn = function(state)
        return state.mspData ~= nil
    end,
    exports = {
        simulatorResponse = MSP_API_SIMULATOR_RESPONSE,
    }
})
