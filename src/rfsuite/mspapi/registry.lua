--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")

local api = {
    loaded = {},
    helpLoaded = {},
    apidata = {
        positionmap = {},
        receivedBytes = {},
        receivedBytesCount = {},
        lastRead = {},
        lastWrite = {},
        _lastReadMode = {},
        _lastWriteMode = {}
    },
    deltaCacheEnabled = false
}

local function loadDefinitionFromPath(name)
    local baseDir = framework and framework.config and framework.config.baseDir or "rfsuite"
    local path = "SCRIPTS:/" .. tostring(baseDir) .. "/mspapi/definitions/" .. tostring(name) .. ".lua"
    local chunk, loadErr
    local ok, moduleOrErr

    if not loadfile then
        return nil, "loadfile_unavailable"
    end

    chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr or ("unable_to_load_" .. tostring(path))
    end

    ok, moduleOrErr = pcall(chunk)
    if not ok then
        return nil, moduleOrErr
    end

    return moduleOrErr
end

local function loadHelp(name)
    local ok
    local moduleOrErr
    local baseDir
    local path
    local chunk
    local loadErr

    if type(name) ~= "string" or name == "" then
        return nil
    end

    if api.helpLoaded[name] ~= nil then
        return api.helpLoaded[name] or nil
    end

    ok, moduleOrErr = pcall(require, "mspapi.apihelp." .. name)
    if not ok then
        baseDir = framework and framework.config and framework.config.baseDir or "rfsuite"
        path = "SCRIPTS:/" .. tostring(baseDir) .. "/mspapi/apihelp/" .. tostring(name) .. ".lua"

        if type(loadfile) == "function" then
            chunk, loadErr = loadfile(path)
            if chunk then
                ok, moduleOrErr = pcall(chunk)
                if not ok then
                    moduleOrErr = nil
                end
            else
                moduleOrErr = nil
            end
        else
            moduleOrErr = nil
        end
    end

    if type(moduleOrErr) ~= "table" then
        api.helpLoaded[name] = false
        return nil
    end

    api.helpLoaded[name] = moduleOrErr
    return moduleOrErr
end

local function injectHelpIntoStructure(name, structure)
    local helpFields = loadHelp(name)
    local index
    local entry
    local bitIndex
    local bit
    local fieldName
    local bitName
    local composite

    if type(helpFields) ~= "table" or type(structure) ~= "table" then
        return
    end

    for index = 1, #structure do
        entry = structure[index]
        if type(entry) == "table" then
            fieldName = entry.field
            if entry.help == nil and type(fieldName) == "string" then
                entry.help = helpFields[fieldName]
            end

            if type(entry.bitmap) == "table" then
                for bitIndex = 1, #entry.bitmap do
                    bit = entry.bitmap[bitIndex]
                    if type(bit) == "table" then
                        bitName = bit.field
                        if bit.help == nil and type(bitName) == "string" then
                            composite = type(fieldName) == "string" and (fieldName .. "->" .. bitName) or nil
                            bit.help = (composite and helpFields[composite]) or helpFields[bitName]
                        end
                    end
                end
            end
        end
    end
end

function api.load(name)
    local ok
    local moduleOrErr
    local pathModule
    local pathErr

    if not name or name == "" then
        return nil, "api_name_required"
    end

    if not api.loaded[name] then
        ok, moduleOrErr = pcall(require, "mspapi.definitions." .. name)
        if not ok then
            pathModule, pathErr = loadDefinitionFromPath(name)
            if not pathModule then
                return nil, tostring(moduleOrErr) .. " | fallback: " .. tostring(pathErr)
            end
            moduleOrErr = pathModule
        end
        api.loaded[name] = moduleOrErr
        if type(moduleOrErr) == "table" then
            injectHelpIntoStructure(name, moduleOrErr.__rfReadStructure)
            if moduleOrErr.__rfWriteStructure ~= moduleOrErr.__rfReadStructure then
                injectHelpIntoStructure(name, moduleOrErr.__rfWriteStructure)
            end
        end
    end

    return api.loaded[name]
end

function api.get(name)
    return api.load(name)
end

function api.unload(name)
    if not name or name == "" then
        return false
    end

    api.loaded[name] = nil
    api.helpLoaded[name] = nil
    api.apidata.positionmap[name] = nil
    api.apidata.receivedBytes[name] = nil
    api.apidata.receivedBytesCount[name] = nil
    api.apidata.lastRead[name] = nil
    api.apidata.lastWrite[name] = nil
    api.apidata._lastReadMode[name] = nil
    api.apidata._lastWriteMode[name] = nil
    package.loaded["mspapi.definitions." .. tostring(name)] = nil
    package.loaded["mspapi.apihelp." .. tostring(name)] = nil

    return true
end

function api.clear()
    api.loaded = {}
    api.helpLoaded = {}
    api.apidata = {
        positionmap = {},
        receivedBytes = {},
        receivedBytesCount = {},
        lastRead = {},
        lastWrite = {},
        _lastReadMode = {},
        _lastWriteMode = {}
    }
end

function api.resetData()
    api.apidata = {
        positionmap = {},
        receivedBytes = {},
        receivedBytesCount = {},
        lastRead = {},
        lastWrite = {},
        _lastReadMode = {},
        _lastWriteMode = {}
    }
end

function api.reset()
    for name in pairs(api.loaded) do
        package.loaded["mspapi.definitions." .. name] = nil
    end
    for name in pairs(api.helpLoaded) do
        package.loaded["mspapi.apihelp." .. name] = nil
    end

    api.loaded = {}
    api.helpLoaded = {}
    api:resetData()
end

function api.setDeltaCacheEnabled(enabled)
    api.deltaCacheEnabled = enabled == true
end

function api.isDeltaCacheEnabled()
    return api.deltaCacheEnabled == true
end

return api
