--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local registry = require("mspapi.registry")

local core = {}

local utils = context.rfsuite.utils

local TYPE_SIZES = {
    U8 = 1, S8 = 1, U16 = 2, S16 = 2, U24 = 3, S24 = 3, U32 = 4, S32 = 4,
    U40 = 5, S40 = 5, U48 = 6, S48 = 6, U56 = 7, S56 = 7, U64 = 8, S64 = 8,
    U72 = 9, S72 = 9, U80 = 10, S80 = 10, U88 = 11, S88 = 11,
    U96 = 12, S96 = 12, U104 = 13, S104 = 13, U112 = 14, S112 = 14,
    U120 = 15, S120 = 15, U128 = 16, S128 = 16, U256 = 32, S256 = 32
}

local function getTypeSize(dataType)
    if dataType == nil then
        return TYPE_SIZES
    end
    return TYPE_SIZES[dataType] or 1
end

local function apiDataStore()
    return registry.apidata
end

local function shouldUseField(field)
    return not field.apiVersion or utils.apiVersionCompare(">=", field.apiVersion)
end

function core.scheduleWakeup(func)
    local callback = context.rfsuite.tasks.callback

    if callback and callback.now then
        callback.now(func)
    else
        func()
    end
end

function core.parseMSPData(apiName, buf, structure, processed, other, options)
    local parsedData = {}
    local positionmap = nil
    local currentByte = 1
    local store = apiDataStore()
    local keepBuffers = registry.isDeltaCacheEnabled(apiName)
    local completionCallback = nil
    local i

    if type(options) == "function" then
        completionCallback = options
    elseif type(options) == "table" then
        completionCallback = options.completionCallback
    end

    if keepBuffers then
        positionmap = {}
        store._lastReadMode[apiName] = "delta"
    else
        store._lastReadMode[apiName] = "no-delta"
    end

    buf.offset = 1

    for i = 1, #structure do
        local field = structure[i]
        local readFunction
        local data

        if shouldUseField(field) then
            readFunction = context.msp.mspHelper and context.msp.mspHelper["read" .. field.type] or nil
            if not readFunction then
                utils.log("Unknown MSP read type " .. tostring(field.type), "warn")
                return nil
            end

            data = readFunction(buf, field.byteorder or "little")
            parsedData[field.field] = data

            if keepBuffers then
                local size = getTypeSize(field.type)
                positionmap[field.field] = {start = currentByte, size = size}
                currentByte = currentByte + size
            end
        end
    end

    local final = {
        parsed = parsedData,
        buffer = keepBuffers and buf or nil,
        structure = structure,
        positionmap = positionmap,
        processed = processed,
        other = other,
        receivedBytesCount = keepBuffers and math.floor((buf.offset or 1) - 1) or math.floor((buf.offset or 1) - 1)
    }

    if keepBuffers then
        store.positionmap[apiName] = positionmap
        store.receivedBytes[apiName] = buf
        store.receivedBytesCount[apiName] = final.receivedBytesCount
        store.lastRead[apiName] = final
    end

    if completionCallback then
        completionCallback(final)
    end

    return final
end

function core.createHandlers()
    local completeHandler = nil
    local privateErrorHandler = nil

    return {
        setCompleteHandler = function(fn)
            if type(fn) ~= "function" then
                error("Complete handler requires function")
            end
            completeHandler = fn
        end,
        setErrorHandler = function(fn)
            if type(fn) ~= "function" then
                error("Error handler requires function")
            end
            privateErrorHandler = fn
        end,
        getCompleteHandler = function()
            return completeHandler
        end,
        getErrorHandler = function()
            return privateErrorHandler
        end
    }
end

function core.buildDeltaPayload(apiName, payload, apiStructure, positionmap, receivedBytes, receivedBytesCount)
    local byteStream = {}
    local i

    for i = 1, receivedBytesCount or 0 do
        byteStream[i] = receivedBytes and receivedBytes[i] or 0
    end

    for i = 1, #apiStructure do
        local fieldDef = apiStructure[i]
        local name = fieldDef.field
        local value
        local scale
        local writeFunction
        local tmp = {}
        local pm
        local maxBytes
        local idx

        if shouldUseField(fieldDef) and payload[name] ~= nil then
            value = payload[name]
            scale = fieldDef.scale or 1
            if fieldDef.decimals then
                scale = scale / (utils.decimalInc(fieldDef.decimals) or 1)
            end
            value = math.floor((value * scale) + 0.5)

            writeFunction = context.msp.mspHelper and context.msp.mspHelper["write" .. fieldDef.type] or nil
            if not writeFunction then
                error("Unknown type " .. tostring(fieldDef.type))
            end

            if fieldDef.byteorder then
                writeFunction(tmp, value, fieldDef.byteorder)
            else
                writeFunction(tmp, value)
            end

            pm = positionmap[name]
            if type(pm) == "table" and pm.start and pm.size then
                maxBytes = math.min(pm.size, #tmp)
                for idx = 1, maxBytes do
                    local pos = pm.start + idx - 1
                    if pos <= (receivedBytesCount or 0) then
                        byteStream[pos] = tmp[idx]
                    end
                end
            end
        end
    end

    return byteStream
end

function core.buildFullPayload(apiName, payload, apiStructure)
    local byteStream = {}
    local store = apiDataStore()
    local i

    for i = 1, #apiStructure do
        local fieldDef = apiStructure[i]
        local value
        local scale
        local writeFunction
        local tmp = {}
        local idx

        if shouldUseField(fieldDef) then
            value = payload[fieldDef.field]
            if value == nil then
                value = fieldDef.default or 0
            end

            scale = fieldDef.scale or 1
            if fieldDef.decimals then
                scale = scale / (utils.decimalInc(fieldDef.decimals) or 1)
            end
            value = math.floor((value * scale) + 0.5)

            writeFunction = context.msp.mspHelper and context.msp.mspHelper["write" .. fieldDef.type] or nil
            if not writeFunction then
                error("Unknown type " .. tostring(fieldDef.type))
            end

            if fieldDef.byteorder then
                writeFunction(tmp, value, fieldDef.byteorder)
            else
                writeFunction(tmp, value)
            end

            for idx = 1, #tmp do
                byteStream[#byteStream + 1] = tmp[idx]
            end
        end
    end

    store.lastWrite[apiName] = byteStream

    return byteStream
end

function core.buildWritePayload(apiName, payload, apiStructure, noDelta)
    local store = apiDataStore()
    local positionmap = store.positionmap[apiName]
    local receivedBytes = store.receivedBytes[apiName]
    local receivedBytesCount = store.receivedBytesCount[apiName]
    local useDelta = not noDelta and positionmap and receivedBytes and receivedBytesCount and registry.isDeltaCacheEnabled(apiName)

    if useDelta then
        store._lastWriteMode[apiName] = "delta"
        return core.buildDeltaPayload(apiName, payload, apiStructure, positionmap, receivedBytes, receivedBytesCount)
    end

    store._lastWriteMode[apiName] = noDelta and "rebuild" or "full"
    return core.buildFullPayload(apiName, payload, apiStructure)
end

function core.prepareStructureData(structure)
    local filtered = {}
    local minBytes = 0
    local simResponse = {}
    local i

    for i = 1, #structure do
        local param = structure[i]
        local size
        local j

        if shouldUseField(param) then
            filtered[#filtered + 1] = param

            if param.mandatory ~= false then
                minBytes = minBytes + getTypeSize(param.type)
            end

            if param.simResponse then
                for j = 1, #param.simResponse do
                    simResponse[#simResponse + 1] = param.simResponse[j]
                end
            else
                size = getTypeSize(param.type)
                for j = 1, size do
                    simResponse[#simResponse + 1] = 0
                end
            end
        end
    end

    return filtered, minBytes, simResponse
end

function core.filterByApiVersion(structure)
    local filtered = core.prepareStructureData(structure)
    return filtered
end

function core.calculateMinBytes(structure)
    local _, minBytes = core.prepareStructureData(structure)
    return minBytes
end

function core.buildSimResponse(structure)
    local _, _, simResponse = core.prepareStructureData(structure)
    return simResponse
end

return core
