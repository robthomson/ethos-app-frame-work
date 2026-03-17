--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Event System
  
  Decoupled event emission and subscription.
  Modules don't need to know about each other - they just subscribe to events.
  
  Usage:
    framework:on("flightmode:changed", function(mode)
        print("Flight mode:", mode)
    end)
    
    framework:emit("flightmode:changed", "acro")
    framework:off("flightmode:changed", handler)
]] --

local events = {}
local log = require("framework.utils.log")

events._handlers = {}

--[[ API ]]

function events:on(eventName, handler)
    if not self._handlers[eventName] then
        self._handlers[eventName] = {}
    end
    table.insert(self._handlers[eventName], handler)
    
    -- Return a function to unsubscribe
    return function()
        self:off(eventName, handler)
    end
end

function events:once(eventName, handler)
    local function wrappedHandler(...)
        handler(...)
        self:off(eventName, wrappedHandler)
    end
    return self:on(eventName, wrappedHandler)
end

function events:off(eventName, handler)
    if not self._handlers[eventName] then
        return
    end
    for i = #self._handlers[eventName], 1, -1 do
        if self._handlers[eventName][i] == handler then
            table.remove(self._handlers[eventName], i)
        end
    end
end

function events:emit(eventName, ...)
    if not self._handlers[eventName] then
        return
    end
    
    for _, handler in ipairs(self._handlers[eventName]) do
        local ok, err = pcall(handler, ...)
        if not ok then
            log:error("Event handler error for '%s': %s", eventName, tostring(err))
        end
    end
end

function events:emitAsync(eventName, delayMs, ...)
    local args = {...}
    -- Schedule async emission (would need callback system)
    -- This is a placeholder for integration with framework.callback
end

function events:clearEvent(eventName)
    if eventName then
        self._handlers[eventName] = nil
    end
end

function events:clearAll()
    self._handlers = {}
end

function events:getHandlerCount(eventName)
    if self._handlers[eventName] then
        return #self._handlers[eventName]
    end
    return 0
end

function events:listEvents()
    local result = {}
    for eventName, handlers in pairs(self._handlers) do
        result[eventName] = #handlers
    end
    return result
end

return events
