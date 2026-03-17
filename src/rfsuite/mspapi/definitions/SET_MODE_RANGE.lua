--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "SET_MODE_RANGE"

return factory.create({
    name = API_NAME,
    writeCmd = 35,
    customWrite = function(suppliedPayload, state, emitComplete, emitError)
        local payload = suppliedPayload or state.payloadData.payload
        if type(payload) ~= "table" then return false, "missing_payload" end

        state.mspWriteComplete = false

        local uuid = state.uuid
        if not uuid then
            local utils = rfsuite and rfsuite.utils
            uuid = (utils and utils.uuid and utils.uuid()) or tostring(os.clock())
        end

        local message = {
            command = 35,
            apiname = API_NAME,
            payload = payload,
            processReply = function(self, buf)
                state.mspWriteComplete = true
                emitComplete(self, buf)
            end,
            errorHandler = function(self, err)
                emitError(self, err)
            end,
            simulatorResponse = {},
            uuid = uuid,
            timeout = state.timeout
        }

        return rfsuite.tasks.msp.mspQueue:add(message)
    end
})
