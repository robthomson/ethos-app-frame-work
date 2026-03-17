--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "4WIF_ESC_FWD_PROG"

-- LuaFormatter off
local MSP_API_STRUCTURE_WRITE = {
    {field = "target", type = "U8", apiVersion = {12, 0, 8}, simResponse = {0}}
}
-- LuaFormatter on

local function buildWritePayload(payloadData, _, _, state)
    return core.buildWritePayload(API_NAME, payloadData, MSP_API_STRUCTURE_WRITE, state.rebuildOnWrite == true)
end

return factory.create({
    name = API_NAME,
    writeCmd = 244,
    writeStructure = MSP_API_STRUCTURE_WRITE,
    buildWritePayload = buildWritePayload,
    writeRequiresStructure = true,
    writeUuidFallback = true,
    initialRebuildOnWrite = true
})
