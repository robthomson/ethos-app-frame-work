--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "REBOOT"

-- LuaFormatter off
local MSP_API_STRUCTURE_WRITE = {}
-- LuaFormatter on

local function buildWritePayload()
    -- Match the legacy suite and FC behaviour: reboot is issued as a bare
    -- command with no payload, even though some protocol notes mention a mode.
    return {}
end

local function validateWrite()
    local session = rfsuite.session
    local tasks = rfsuite.tasks
    local armflags = tasks and tasks.telemetry and tasks.telemetry.getSensor and tasks.telemetry.getSensor("armflags")
    local armedByFlags = (armflags == 1 or armflags == 3)
    if (session and session.isArmed) or armedByFlags then
        if rfsuite and rfsuite.utils and rfsuite.utils.log then
            rfsuite.utils.log("REBOOT API blocked while armed", "info")
        end
        return false, "armed_blocked"
    end
    return true
end

return factory.create({
    name = API_NAME,
    writeCmd = 68,
    writeStructure = MSP_API_STRUCTURE_WRITE,
    buildWritePayload = buildWritePayload,
    validateWrite = validateWrite,
    resolveWriteTimeout = function()
        return 1.0
    end,
    maxWriteRetries = 0,
    maxWriteExpireCount = 0,
    requeueWriteExpired = false,
    writeUuidFallback = true,
    initialRebuildOnWrite = false
})
