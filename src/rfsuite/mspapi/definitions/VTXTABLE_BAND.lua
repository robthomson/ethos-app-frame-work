--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "VTXTABLE_BAND"

-- LuaFormatter off
local MSP_API_STRUCTURE_READ_DATA = {
    { field = "band",           type = "U8",  apiVersion = {12, 0, 6}, simResponse = {1}, mandatory = false },
    { field = "name_length",    type = "U8",  apiVersion = {12, 0, 6}, simResponse = {8}, mandatory = false },
    { field = "name_1",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {65}, mandatory = false },
    { field = "name_2",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {66}, mandatory = false },
    { field = "name_3",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {67}, mandatory = false },
    { field = "name_4",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {68}, mandatory = false },
    { field = "name_5",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {69}, mandatory = false },
    { field = "name_6",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {70}, mandatory = false },
    { field = "name_7",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {71}, mandatory = false },
    { field = "name_8",         type = "U8",  apiVersion = {12, 0, 6}, simResponse = {72}, mandatory = false },
    { field = "band_letter",    type = "U8",  apiVersion = {12, 0, 6}, simResponse = {65}, mandatory = false },
    { field = "is_factory_band",type = "U8",  apiVersion = {12, 0, 6}, simResponse = {1}, mandatory = false },
    { field = "channel_count",  type = "U8",  apiVersion = {12, 0, 6}, simResponse = {8}, mandatory = false },
    { field = "freq_1",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {100, 22}, mandatory = false },
    { field = "freq_2",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {120, 22}, mandatory = false },
    { field = "freq_3",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {140, 22}, mandatory = false },
    { field = "freq_4",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {160, 22}, mandatory = false },
    { field = "freq_5",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {180, 22}, mandatory = false },
    { field = "freq_6",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {200, 22}, mandatory = false },
    { field = "freq_7",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {220, 22}, mandatory = false },
    { field = "freq_8",         type = "U16", apiVersion = {12, 0, 6}, simResponse = {240, 22}, mandatory = false },
}
-- LuaFormatter on

local MSP_API_STRUCTURE_READ, MSP_MIN_BYTES, MSP_API_SIMULATOR_RESPONSE = core.prepareStructureData(MSP_API_STRUCTURE_READ_DATA)

-- LuaFormatter off
local MSP_API_STRUCTURE_WRITE = {
    { field = "band",            type = "U8"  },
    { field = "name_length",     type = "U8"  },
    { field = "name_1",          type = "U8"  },
    { field = "name_2",          type = "U8"  },
    { field = "name_3",          type = "U8"  },
    { field = "name_4",          type = "U8"  },
    { field = "name_5",          type = "U8"  },
    { field = "name_6",          type = "U8"  },
    { field = "name_7",          type = "U8"  },
    { field = "name_8",          type = "U8"  },
    { field = "band_letter",     type = "U8"  },
    { field = "is_factory_band", type = "U8"  },
    { field = "channel_count",   type = "U8"  },
    { field = "freq_1",          type = "U16" },
    { field = "freq_2",          type = "U16" },
    { field = "freq_3",          type = "U16" },
    { field = "freq_4",          type = "U16" },
    { field = "freq_5",          type = "U16" },
    { field = "freq_6",          type = "U16" },
    { field = "freq_7",          type = "U16" },
    { field = "freq_8",          type = "U16" },
}
-- LuaFormatter on

local function parseRead(buf)
    local result = nil
    core.parseMSPData(API_NAME, buf, MSP_API_STRUCTURE_READ, nil, nil, function(parsed)
        result = parsed
    end)
    if result == nil then return nil, "parse_failed" end
    return result
end

local function buildReadPayload(payloadData, _, _, _, band)
    local readBand = tonumber(band)
    if readBand == nil then readBand = tonumber(payloadData.band) end
    if readBand == nil then readBand = 1 end
    return {readBand}
end

local function buildWritePayload(payloadData, _, _, state)
    return core.buildWritePayload(API_NAME, payloadData, MSP_API_STRUCTURE_WRITE, state.rebuildOnWrite == true)
end

return factory.create({
    name = API_NAME,
    readCmd = 137,
    writeCmd = 227,
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
