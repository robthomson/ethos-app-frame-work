--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local omp = {}

local MODEL_NAMES = {
    [0] = "RESERVED",
    [1] = "35A",
    [2] = "65A",
    [3] = "85A",
    [4] = "125A",
    [5] = "155A",
    [6] = "130A",
    [7] = "195A",
    [8] = "300A"
}

function omp.details(parsed)
    local modelId = tonumber(parsed and parsed.esc_model)
    local version = tonumber(parsed and parsed.esc_version)
    local modelName = MODEL_NAMES[modelId]
    local major
    local minor

    if version == nil then
        version = 0
    end

    major = math.floor(version / 16)
    minor = version % 16

    return {
        model = modelName and ("OMP " .. modelName) or ("OMP #" .. tostring(modelId or "?")),
        version = " ",
        firmware = string.format("SW%d.%d", major, minor)
    }
end

function omp.activeFields(parsed)
    local value = tonumber(parsed and parsed.activefields) or 0
    local fields = {}
    local index
    local bitValue

    for index = 1, 32 do
        bitValue = math.floor(value / (2 ^ (index - 1))) % 2
        fields[index] = bitValue
    end

    return fields
end

return omp
