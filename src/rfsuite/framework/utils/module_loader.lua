--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local loader = {}
local cache = {}

local function cacheKey(moduleName, path)
    if type(moduleName) == "string" and moduleName ~= "" then
        return "require:" .. moduleName
    end
    return "file:" .. tostring(path or "")
end

local function candidatePaths(path)
    if type(path) ~= "string" or path == "" then
        return {}
    end

    if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") or path:sub(1, 8) == "SCRIPTS:/" then
        return {path}
    end

    return {
        path,
        "src/rfsuite/" .. path
    }
end

function loader.loadFileCached(path)
    local key
    local chunk
    local loadErr
    local ok
    local value
    local paths
    local index

    if type(path) ~= "string" or path == "" then
        error("invalid module path")
    end

    key = cacheKey(nil, path)
    if cache[key] ~= nil then
        return cache[key]
    end

    if not loadfile then
        error("loadfile unavailable")
    end

    paths = candidatePaths(path)
    for index = 1, #paths do
        chunk, loadErr = loadfile(paths[index])
        if chunk then
            break
        end
    end
    if not chunk then
        error(tostring(loadErr or ("unable_to_load_" .. path)))
    end

    ok, value = pcall(chunk)
    if not ok then
        error(tostring(value))
    end
    if type(value) ~= "table" then
        error("module did not return table: " .. tostring(path))
    end

    cache[key] = value
    return value
end

function loader.requireOrLoad(moduleName, path)
    local key
    local ok
    local value

    if type(moduleName) == "string" and moduleName ~= "" then
        key = cacheKey(moduleName, path)
        if cache[key] ~= nil then
            return cache[key]
        end

        ok, value = pcall(require, moduleName)
        if ok and type(value) == "table" then
            cache[key] = value
            return value
        end
    end

    value = loader.loadFileCached(path)
    if key ~= nil then
        cache[key] = value
    end
    return value
end

function loader.clear(moduleName, path)
    if type(moduleName) == "string" and moduleName ~= "" then
        cache[cacheKey(moduleName, path)] = nil
    end
    if type(path) == "string" and path ~= "" then
        cache[cacheKey(nil, path)] = nil
    end
end

return loader
