--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--=============================================================================
--  ethos_events.lua
--
--  Ethos Event Debug Helper
--
--  Converts Ethos event category/value numbers into readable names by
--  scanning runtime constants (EVT_*, KEY_*, TOUCH_*, ROTARY_*), and
--  prints formatted debug output (or returns the formatted line).
--=============================================================================

local events = {}
local log = require("framework.utils.log")

local EVT_NAMES = {}
local KEY_NAMES = {}
local TOUCH_NAMES = {}
local CONSTANTS_BY_NAME = {}

local function indexConstant(name, value)
    if type(name) ~= "string" or type(value) ~= "number" then
        return
    end

    if CONSTANTS_BY_NAME[name] == nil then
        CONSTANTS_BY_NAME[name] = value
    end
    if (name:match("^KEY_") or name:match("^ROTARY_")) and KEY_NAMES[value] == nil then
        KEY_NAMES[value] = name
    elseif name:match("^TOUCH_") and TOUCH_NAMES[value] == nil then
        TOUCH_NAMES[value] = name
    elseif name:match("^EVT_") and EVT_NAMES[value] == nil then
        EVT_NAMES[value] = name
    end
end

for k, v in pairs(_G) do
    if type(v) == "number" then
        indexConstant(k, v)
    end
end

local function nameWithNumber(map, n)
    if n == nil then
        return "nil"
    end

    local name = map[n]
    if name then
        return string.format("%s (%s)", name, tostring(n))
    end

    return tostring(n)
end

local lastLine = nil

function events.getConstant(name)
    local value

    if type(name) ~= "string" or name == "" then
        return nil
    end

    value = CONSTANTS_BY_NAME[name]
    if value ~= nil then
        return value
    end

    value = rawget(_G, name)
    if type(value) == "number" then
        indexConstant(name, value)
        return value
    end

    return nil
end

function events.matchesConstant(value, name)
    local constant = events.getConstant(name)

    return constant ~= nil and value == constant
end

function events.matchesAnyConstant(value, names)
    local i

    for i = 1, #(names or {}) do
        if events.matchesConstant(value, names[i]) then
            return true
        end
    end

    return false
end

function events.isCloseEvent(category, value)
    return events.matchesConstant(category, "EVT_CLOSE")
        or events.matchesAnyConstant(value, {
            "KEY_DOWN_BREAK",
            "KEY_RTN_BREAK",
            "KEY_EXIT_BREAK",
            "KEY_MODEL_BREAK"
        })
end

function events.debug(tag, category, value, x, y, options)
    options = options or {}
    local level = options.level or "debug"

    if options.onlyKey and category ~= EVT_KEY then
        return
    end

    if options.onlyValues and not options.onlyValues[value] then
        return
    end

    local catName = nameWithNumber(EVT_NAMES, category)

    local valName
    if category == EVT_KEY then
        valName = nameWithNumber(KEY_NAMES, value)
    elseif category == EVT_TOUCH then
        valName = nameWithNumber(TOUCH_NAMES, value)
    else
        valName = tostring(value)
    end

    local line = string.format(
        "[%s] %s  %s  x=%s y=%s",
        tag or "event",
        catName,
        valName,
        tostring(x),
        tostring(y)
    )

    if options.throttleSame and line == lastLine then
        return nil
    end

    lastLine = line
    if not options.returnOnly then
        if level == "info" then
            log:info("%s", line)
        elseif level == "warn" then
            log:warn("%s", line)
        elseif level == "error" then
            log:error("%s", line)
        else
            log:debug("%s", line)
        end
    end

    return line
end

return events
