--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local telemetryconfig = {}

local function buildSessionValues(api)
    local slots = {}
    local parts = {}
    local i
    local key
    local value

    for i = 1, 40 do
        key = "telem_sensor_slot_" .. i
        value = tonumber(api.readValue and api.readValue(key) or nil) or 0
        slots[i] = value
        if value ~= 0 then
            parts[#parts + 1] = tostring(value)
        end
    end

    return {
        telemetryConfig = slots,
        crsfTelemetryMode = tonumber(api.readValue and api.readValue("crsf_telemetry_mode") or nil) or 0,
        crsfTelemetryLinkRate = tonumber(api.readValue and api.readValue("crsf_telemetry_link_rate") or nil) or 0,
        crsfTelemetryLinkRatio = tonumber(api.readValue and api.readValue("crsf_telemetry_link_ratio") or nil) or 0
    }, parts
end

function telemetryconfig.clearSession(session)
    if not session or not session.clearKeys then
        return
    end

    session:clearKeys({
        "telemetryConfig",
        "crsfTelemetryMode",
        "crsfTelemetryLinkRate",
        "crsfTelemetryLinkRatio"
    })
end

function telemetryconfig.applyApiToSession(session, api, logger)
    local values
    local parts
    local transport

    if not session or not api then
        return nil
    end

    values, parts = buildSessionValues(api)
    session:setMultiple(values)

    if logger and logger.connect then
        logger:connect("Telemetry config slots: %s", #parts > 0 and table.concat(parts, ",") or "none")
        transport = session:get("connectionTransport", nil) or session:get("mspTransport", nil) or session:get("telemetryType", nil)
        if transport == "crsf" then
            logger:connect(
                "CRSF telemetry mode=%s rate=%s ratio=%s",
                tostring(values.crsfTelemetryMode or 0),
                tostring(values.crsfTelemetryLinkRate or 0),
                tostring(values.crsfTelemetryLinkRatio or 0)
            )
        end
    end

    return values
end

return telemetryconfig
