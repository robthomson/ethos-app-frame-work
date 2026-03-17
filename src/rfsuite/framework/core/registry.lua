--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Registry
  
  Manages registration of modules, tasks, and components.
  Supports lazy loading to minimize initial memory footprint.
  
  Usage:
    registry:register("module", "mymodule", MyModuleClass)
    registry:register("task", "telemetry", TelemetryTaskClass, {lazy=true, file="tasks/telemetry.lua"})
    
    local module = registry:get("module", "mymodule")
    local tasks = registry:list("task")
]] --

local registry = {}
local log = require("framework.utils.log")

registry._items = {}
registry._metadata = {}

--[[ API ]]

function registry:register(category, name, itemOrPath, options)
    options = options or {}
    
    if not self._items[category] then
        self._items[category] = {}
        self._metadata[category] = {}
    end
    
    local id = category .. ":" .. name
    
    if options.lazy then
        -- Lazy loading: store file path, load on first access
        self._items[category][name] = nil  -- Not loaded yet
        self._metadata[category][name] = {
            lazy = true,
            path = itemOrPath,
            options = options,
            loaded = false,
            instance = nil
        }
    else
        -- Immediate: store the actual object
        self._items[category][name] = itemOrPath
        self._metadata[category][name] = {
            lazy = false,
            options = options,
            loaded = true,
            instance = itemOrPath
        }
    end
end

function registry:get(category, name)
    if not self._items[category] or not self._items[category][name] then
        if not self._metadata[category] or not self._metadata[category][name] then
            return nil
        end
        
        -- Check if lazy-loading needed
        local meta = self._metadata[category][name]
        if meta.lazy and not meta.loaded then
            -- Load the module
            local ok, result = pcall(loadfile, meta.path)
            if ok then
                meta.instance = result
                meta.loaded = true
                self._items[category][name] = result
                return result
            else
                log:error("Failed to load %s: %s", meta.path, tostring(result))
                return nil
            end
        end
        
        return meta.instance
    end
    
    return self._items[category][name]
end

function registry:list(category)
    if not self._items[category] then
        return {}
    end
    
    local result = {}
    for name, item in pairs(self._items[category]) do
        if item then
            table.insert(result, {name = name, item = item})
        end
    end
    return result
end

function registry:listMeta(category)
    if not self._metadata[category] then
        return {}
    end
    
    local result = {}
    for name, meta in pairs(self._metadata[category]) do
        table.insert(result, {name = name, meta = meta})
    end
    return result
end

function registry:unregister(category, name)
    if not self._items[category] then
        return
    end
    
    local item = self._items[category][name]
    
    -- Call cleanup if available
    if item and type(item) == "table" and item.close then
        local ok, err = pcall(item.close, item)
        if not ok then
            log:error("Error closing %s:%s: %s", category, name, tostring(err))
        end
    end
    
    self._items[category][name] = nil
    self._metadata[category][name] = nil
end

function registry:exists(category, name)
    if not self._items[category] then
        return false
    end
    return self._items[category][name] ~= nil or 
           (self._metadata[category] and self._metadata[category][name] ~= nil)
end

function registry:getStats()
    local stats = {}
    for category, items in pairs(self._items) do
        stats[category] = {
            total = 0,
            loaded = 0,
            lazy = 0
        }
        
        for name, _ in pairs(items) do
            stats[category].total = stats[category].total + 1
            if self._metadata[category][name].lazy then
                if self._metadata[category][name].loaded then
                    stats[category].loaded = stats[category].loaded + 1
                else
                    stats[category].lazy = stats[category].lazy + 1
                end
            else
                stats[category].loaded = stats[category].loaded + 1
            end
        end
    end
    return stats
end

function registry:clear()
    -- Cleanup all items
    for category, items in pairs(self._items) do
        for name, item in pairs(items) do
            if item and type(item) == "table" and item.close then
                pcall(item.close, item)
            end
        end
    end
    self._items = {}
    self._metadata = {}
end

return registry
