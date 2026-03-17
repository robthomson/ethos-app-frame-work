--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local registry = {
    _hooks = {},
    _order = 0
}

local function ensureEvent(eventName)
    if not registry._hooks[eventName] then
        registry._hooks[eventName] = {}
    end

    return registry._hooks[eventName]
end

local function sortHooks(items)
    table.sort(items, function(a, b)
        if a.priority == b.priority then
            return a.order < b.order
        end

        return a.priority > b.priority
    end)
end

function registry.register(eventName, name, definition, options)
    local hooks
    local entry

    if type(eventName) ~= "string" or eventName == "" then
        error("lifecycle.register requires eventName")
    end

    if type(name) ~= "string" or name == "" then
        error("lifecycle.register requires hook name")
    end

    if type(definition) ~= "table" and type(definition) ~= "function" then
        error("lifecycle.register requires hook table or function")
    end

    registry._order = registry._order + 1
    hooks = ensureEvent(eventName)
    entry = {
        name = name,
        definition = definition,
        priority = (options and options.priority) or (type(definition) == "table" and definition.priority) or 50,
        timeout = (options and options.timeout) or (type(definition) == "table" and definition.timeout) or nil,
        order = registry._order
    }

    hooks[#hooks + 1] = entry
    sortHooks(hooks)

    return entry
end

function registry.list(eventName)
    local source = ensureEvent(eventName)
    local copy = {}
    local i

    for i = 1, #source do
        local hook = source[i]
        copy[i] = {
            name = hook.name,
            definition = hook.definition,
            priority = hook.priority,
            timeout = hook.timeout,
            order = hook.order
        }
    end

    return copy
end

function registry.clear(eventName)
    if eventName then
        registry._hooks[eventName] = {}
        return
    end

    registry._hooks = {}
    registry._order = 0
end

function registry.count(eventName)
    return #ensureEvent(eventName)
end

function registry.events()
    local result = {}
    local eventName

    for eventName in pairs(registry._hooks) do
        result[#result + 1] = eventName
    end

    table.sort(result)
    return result
end

return registry
