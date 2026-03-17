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

for k, v in pairs(_G) do
    if type(v) == "number" then
        if (k:match("^KEY_") or k:match("^ROTARY_")) and KEY_NAMES[v] == nil then
            KEY_NAMES[v] = k
        elseif k:match("^TOUCH_") and TOUCH_NAMES[v] == nil then
            TOUCH_NAMES[v] = k
        elseif k:match("^EVT_") and EVT_NAMES[v] == nil then
            EVT_NAMES[v] = k
        end
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

function events.debug(tag, category, value, x, y, options)
    options = options or {}

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
        log:debug("%s", line)
    end

    return line
end

return events
