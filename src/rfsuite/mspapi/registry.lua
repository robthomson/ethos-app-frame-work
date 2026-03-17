--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")

local api = {
    loaded = {},
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
    end

    return api.loaded[name]
end

function api.get(name)
    return api.load(name)
end

function api.clear()
    api.loaded = {}
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

    api.loaded = {}
    api:resetData()
end

function api.setDeltaCacheEnabled(enabled)
    api.deltaCacheEnabled = enabled == true
end

function api.isDeltaCacheEnabled()
    return api.deltaCacheEnabled == true
end

return api
