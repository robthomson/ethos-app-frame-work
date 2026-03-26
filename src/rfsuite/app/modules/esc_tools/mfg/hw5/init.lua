--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local hw5 = {}

local function trim(text)
    if type(text) ~= "string" then
        return ""
    end

    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function getText(buffer, st, en)
    local out = {}
    local index
    local value

    if type(buffer) ~= "table" then
        return ""
    end

    for index = st, en do
        value = buffer[index]
        if value == nil or value == 0 then
            break
        end
        out[#out + 1] = string.char(value)
    end

    return trim(table.concat(out))
end

function hw5.details(buffer, parsed)
    local model = getText(buffer, 35, 50)
    local version = getText(buffer, 19, 34)
    local firmware = getText(buffer, 3, 18)

    if model == "" then
        model = trim(parsed and parsed.esc_type)
    end
    if version == "" then
        version = trim(parsed and parsed.hardware_version)
    end
    if firmware == "" then
        firmware = trim(parsed and parsed.firmware_version)
    end

    return {
        model = model,
        version = version,
        firmware = firmware
    }
end

return hw5
