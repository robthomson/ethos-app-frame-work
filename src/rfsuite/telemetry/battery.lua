--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local battery = {}

local function buildBatteryConfig(api)
    local config = {
        voltageMeterSource = tonumber(api.readValue and api.readValue("voltageMeterSource") or nil) or 0,
        batteryCapacity = tonumber(api.readValue and api.readValue("batteryCapacity") or nil) or 0,
        batteryCellCount = tonumber(api.readValue and api.readValue("batteryCellCount") or nil) or 0,
        vbatwarningcellvoltage = (tonumber(api.readValue and api.readValue("vbatwarningcellvoltage") or nil) or 0) / 100,
        vbatmincellvoltage = (tonumber(api.readValue and api.readValue("vbatmincellvoltage") or nil) or 0) / 100,
        vbatmaxcellvoltage = (tonumber(api.readValue and api.readValue("vbatmaxcellvoltage") or nil) or 0) / 100,
        vbatfullcellvoltage = (tonumber(api.readValue and api.readValue("vbatfullcellvoltage") or nil) or 0) / 100,
        lvcPercentage = tonumber(api.readValue and api.readValue("lvcPercentage") or nil) or 0,
        consumptionWarningPercentage = tonumber(api.readValue and api.readValue("consumptionWarningPercentage") or nil) or 0,
        profiles = {}
    }
    local index
    local key
    local value

    for index = 0, 5 do
        key = "batteryCapacity_" .. tostring(index)
        value = tonumber(api.readValue and api.readValue(key) or nil)
        if value ~= nil then
            config.profiles[index] = value
        end
    end

    return config
end

function battery.clearSession(session)
    if not session or not session.clearKeys then
        return
    end

    session:clearKeys({"batteryConfig"})
end

function battery.applyApiToSession(session, api, logger)
    local config
    local profileParts = {}
    local index
    local profileValue

    if not session or not api then
        return nil
    end

    config = buildBatteryConfig(api)
    session:set("batteryConfig", config)

    if logger and logger.connect then
        logger:connect(
            "Battery config: %smAh %sS reserve=%s%%",
            tostring(config.batteryCapacity or 0),
            tostring(config.batteryCellCount or 0),
            tostring(config.consumptionWarningPercentage or 0)
        )

        for index = 0, 5 do
            profileValue = tonumber(config.profiles[index] or 0) or 0
            if profileValue > 0 then
                profileParts[#profileParts + 1] = string.format("%d=%d", index + 1, profileValue)
            end
        end

        if #profileParts > 0 then
            logger:connect("Battery profile capacities: %s", table.concat(profileParts, ","))
        end
    end

    return config
end

return battery
