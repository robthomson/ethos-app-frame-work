--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Session Management
  
  Manages runtime state with change tracking and watchers.
  
  Usage:
    session:set("activeProfile", 1)
    local val = session:get("activeProfile")
    session:watch("activeProfile", function(old, new)
        print("Profile changed:", old, "->", new)
    end)
]] --

local session = {}
local log = require("framework.utils.log")

session.data = {}
session._watchers = {}
session._changeCallbacks = {}

--[[ API ]]

function session:set(key, value)
    local old = self.data[key]
    
    -- Only notify if value actually changed
    if old ~= value then
        self.data[key] = value
        
        -- Notify watchers
        if self._watchers[key] then
            for _, watcher in ipairs(self._watchers[key]) do
                local ok, err = pcall(watcher, old, value)
                if not ok then
                    log:error("Watcher error for '%s': %s", key, tostring(err))
                end
            end
        end
    end
end

function session:setSilent(key, value)
    self.data[key] = value
end

function session:get(key, default)
    local value = self.data[key]
    if value == nil then
        return default
    end
    return value
end

function session:watch(key, callback)
    if not self._watchers[key] then
        self._watchers[key] = {}
    end
    table.insert(self._watchers[key], callback)
end

function session:unwatch(key, callback)
    if not self._watchers[key] then
        return
    end
    for i = #self._watchers[key], 1, -1 do
        if self._watchers[key][i] == callback then
            table.remove(self._watchers[key], i)
        end
    end
end

function session:setMultiple(updates)
    for key, value in pairs(updates) do
        self:set(key, value)
    end
end

function session:setMultipleSilent(updates)
    for key, value in pairs(updates) do
        self:setSilent(key, value)
    end
end

function session:unset(key)
    self:set(key, nil)
end

function session:clearKeys(keys)
    local i

    for i = 1, #(keys or {}) do
        self:set(keys[i], nil)
    end
end

function session:getMultiple(keys)
    local result = {}
    for _, key in ipairs(keys) do
        result[key] = self.data[key]
    end
    return result
end

function session:dump()
    local result = {}
    for key, value in pairs(self.data) do
        result[key] = value
    end
    return result
end

function session:clear()
    self.data = {}
    self._watchers = {}
end

return session
