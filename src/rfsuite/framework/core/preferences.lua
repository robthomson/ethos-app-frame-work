--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = require("lib.ini")

local methods = {}

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
end

local function mergeTables(defaults, loaded)
    return ini.merge_ini_tables(loaded or {}, copyTable(defaults or {}))
end

local function normalizePath(path)
    if not path or path == "" then
        return nil
    end

    if path:match("^SCRIPTS:/") or path:match("^SD:/") or path:match("^/[A-Za-z]/") or path:match("^/") then
        return path
    end

    return "SCRIPTS:/" .. path
end

function methods:reset(defaults)
    self._defaults = copyTable(defaults or self._defaults or {})
    self._data = copyTable(self._defaults)
end

function methods:load(path, defaults)
    local loaded

    if defaults then
        self._defaults = copyTable(defaults)
    end

    self._path = normalizePath(path or self._path)
    loaded = self._path and ini.load_ini_file(self._path) or nil
    self._data = mergeTables(self._defaults, loaded)

    return self._data
end

function methods:save(path)
    local target = normalizePath(path or self._path)

    if not target then
        return false, "preferences_path_missing"
    end

    self._path = target
    return ini.save_ini_file(target, self._data)
end

function methods:get(section, key, default)
    local sectionData

    if key == nil then
        sectionData = self._data[section]
        if sectionData == nil then
            return default
        end
        return sectionData
    end

    sectionData = self._data[section]
    if type(sectionData) ~= "table" then
        return default
    end

    if sectionData[key] == nil then
        return default
    end

    return sectionData[key]
end

function methods:set(section, key, value)
    if value == nil then
        self._data[section] = key
        return
    end

    self._data[section] = self._data[section] or {}
    self._data[section][key] = value
end

function methods:setMultiple(updates)
    local section

    for section, value in pairs(updates or {}) do
        self._data[section] = value
    end
end

function methods:section(name, defaults)
    if self._data[name] == nil then
        self._data[name] = copyTable(defaults or {})
    end
    return self._data[name]
end

function methods:dump()
    return copyTable(self._data)
end

function methods:path()
    return self._path
end

local preferences_mt = {
    __index = function(self, key)
        local method = methods[key]
        if method ~= nil then
            return method
        end
        return self._data[key]
    end,
    __newindex = function(self, key, value)
        self._data[key] = value
    end
}

local preferences = {}

function preferences.new(options)
    local opts = options or {}
    local instance = setmetatable({
        _data = {},
        _defaults = copyTable(opts.defaults or {}),
        _path = normalizePath(opts.path)
    }, preferences_mt)

    instance:reset(instance._defaults)
    if instance._path then
        instance:load(instance._path)
    end

    return instance
end

return preferences
