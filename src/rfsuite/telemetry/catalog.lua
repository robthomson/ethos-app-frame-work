--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")

local function clamp(value, minValue, maxValue)
    if value == nil then
        return nil
    end
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function getTelemetryTask()
    if framework and framework.getTask and framework._taskMetadata and framework._taskMetadata.telemetry then
        return framework:getTask("telemetry")
    end
    return nil
end

local function normalizeBatteryProfileIndex(value)
    local n = tonumber(value)

    if not n then
        return nil
    end

    n = math.floor(n)
    if n >= 1 and n <= 6 then
        return n - 1
    end
    if n >= 0 and n <= 5 then
        return n
    end

    return nil
end

local function resolveBatteryCapacity(batteryConfig)
    local session = framework and framework.session or nil
    local activeProfile
    local profiles

    if not batteryConfig then
        return nil
    end

    activeProfile = session and session:get("activeBatteryProfile", nil) or nil
    activeProfile = normalizeBatteryProfileIndex(activeProfile)
    profiles = batteryConfig.profiles

    if activeProfile and type(profiles) == "table" and tonumber(profiles[activeProfile]) and tonumber(profiles[activeProfile]) > 0 then
        return tonumber(profiles[activeProfile])
    end

    return tonumber(batteryConfig.batteryCapacity)
end

local function computeSmartfuel()
    local session = framework and framework.session or nil
    local telemetry = getTelemetryTask()
    local batteryConfig = session and session:get("batteryConfig", nil) or nil
    local modelPreferences = session and session:get("modelPreferences", nil) or nil
    local voltage
    local consumption
    local capacity
    local cellCount
    local reserve
    local usableCapacity
    local minCell
    local fullCell
    local voltagePerCell
    local remaining
    local percent

    if not telemetry or not batteryConfig then
        return nil, UNIT_PERCENT, "%"
    end

    capacity = resolveBatteryCapacity(batteryConfig)
    reserve = tonumber(batteryConfig.consumptionWarningPercentage) or 30
    reserve = clamp(reserve, 0, 60)
    usableCapacity = capacity and (capacity * (1 - reserve / 100)) or nil
    if usableCapacity and usableCapacity <= 0 then
        usableCapacity = capacity
    end

    if modelPreferences
        and modelPreferences.battery
        and tonumber(modelPreferences.battery.calc_local) == 1 then
        voltage = telemetry.getSensor and telemetry.getSensor("voltage") or nil
        cellCount = tonumber(batteryConfig.batteryCellCount) or 0
        minCell = tonumber(batteryConfig.vbatmincellvoltage) or 3.30
        fullCell = tonumber(batteryConfig.vbatfullcellvoltage) or 4.10

        if voltage and cellCount > 0 and fullCell > minCell then
            voltagePerCell = voltage / cellCount
            percent = ((voltagePerCell - minCell) / (fullCell - minCell)) * 100
            return clamp(math.floor(percent + 0.5), 0, 100), UNIT_PERCENT, "%"
        end
    end

    consumption = telemetry.getSensor and telemetry.getSensor("consumption") or nil
    if consumption and usableCapacity and usableCapacity > 0 then
        remaining = 100 - ((consumption / usableCapacity) * 100)
        return clamp(math.floor(remaining + 0.5), 0, 100), UNIT_PERCENT, "%"
    end

    return telemetry.getSensor and telemetry.getSensor("fuel") or nil, UNIT_PERCENT, "%"
end

local function computeSmartconsumption()
    local session = framework and framework.session or nil
    local telemetry = getTelemetryTask()
    local batteryConfig = session and session:get("batteryConfig", nil) or nil
    local capacity
    local remainingPercent

    if not telemetry then
        return nil, UNIT_MILLIAMPERE_HOUR, "mAh"
    end

    if batteryConfig then
        capacity = resolveBatteryCapacity(batteryConfig)
        remainingPercent = computeSmartfuel()
        if capacity and remainingPercent ~= nil then
            return math.floor(capacity * (1 - (remainingPercent / 100))), UNIT_MILLIAMPERE_HOUR, "mAh"
        end
    end

    return telemetry.getSensor and telemetry.getSensor("consumption") or nil, UNIT_MILLIAMPERE_HOUR, "mAh"
end

return {
    rssi = {
        name = "@i18n(sensors.rssi)@",
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%"
    },
    link = {
        name = "@i18n(sensors.link)@",
        mandatory = true,
        stats = true,
        switch_alerts = true,
        unit = UNIT_DB,
        unit_string = "dB"
    },
    vfr = {
        name = "@i18n(sensors.vfr)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%"
    },
    armflags = {
        name = "@i18n(sensors.arming_flags)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 90,
        onchange = function(value)
            framework.session:set("isArmed", value == 1 or value == 3)
        end
    },
    voltage = {
        name = "@i18n(sensors.voltage)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 3,
        switch_alerts = true,
        unit = UNIT_VOLT,
        unit_string = "V"
    },
    rpm = {
        name = "@i18n(sensors.headspeed)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 60,
        switch_alerts = true,
        unit = UNIT_RPM,
        unit_string = "rpm"
    },
    current = {
        name = "@i18n(sensors.current)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 4,
        switch_alerts = true,
        unit = UNIT_AMPERE,
        unit_string = "A"
    },
    temp_esc = {
        name = "@i18n(sensors.esc_temp)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 23,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        unit_string = "deg"
    },
    temp_mcu = {
        name = "@i18n(sensors.mcu_temp)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 52,
        switch_alerts = true,
        unit = UNIT_DEGREE,
        unit_string = "deg"
    },
    fuel = {
        name = "@i18n(sensors.fuel)@",
        mandatory = false,
        stats = true,
        set_telemetry_sensors = 6,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%"
    },
    smartfuel = {
        name = "@i18n(sensors.smartfuel)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_PERCENT,
        unit_string = "%",
        source = computeSmartfuel
    },
    smartconsumption = {
        name = "@i18n(sensors.smartconsumption)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh",
        source = computeSmartconsumption
    },
    consumption = {
        name = "@i18n(sensors.consumption)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 5,
        switch_alerts = true,
        unit = UNIT_MILLIAMPERE_HOUR,
        unit_string = "mAh"
    },
    governor = {
        name = "@i18n(sensors.governor)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 93
    },
    adj_f = {
        name = "@i18n(sensors.adj_func)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 99
    },
    adj_v = {
        name = "@i18n(sensors.adj_val)@",
        mandatory = true,
        stats = false
    },
    pid_profile = {
        name = "@i18n(sensors.pid_profile)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 95
    },
    rate_profile = {
        name = "@i18n(sensors.rate_profile)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 96
    },
    battery_profile = {
        name = "@i18n(sensors.battery_profile)@",
        mandatory = false,
        stats = false
    },
    led_profile = {
        name = "@i18n(sensors.led_profile)@",
        mandatory = false,
        stats = false
    },
    throttle_percent = {
        name = "@i18n(sensors.throttle_pct)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 15,
        unit = UNIT_PERCENT,
        unit_string = "%"
    },
    armdisableflags = {
        name = "@i18n(sensors.armdisableflags)@",
        mandatory = true,
        stats = false,
        set_telemetry_sensors = 91
    },
    altitude = {
        name = "@i18n(sensors.altitude)@",
        mandatory = false,
        stats = true,
        switch_alerts = true,
        unit = UNIT_METER,
        unit_string = "m"
    },
    bec_voltage = {
        name = "@i18n(sensors.bec_voltage)@",
        mandatory = true,
        stats = true,
        set_telemetry_sensors = 43,
        unit = UNIT_VOLT,
        unit_string = "V"
    },
    cell_count = {
        name = "@i18n(sensors.cell_count)@",
        mandatory = false,
        stats = true
    },
    accx = {
        name = "@i18n(sensors.acc_x)@",
        mandatory = false,
        stats = true,
        unit = UNIT_G,
        unit_string = "g"
    },
    accy = {
        name = "@i18n(sensors.acc_y)@",
        mandatory = false,
        stats = true,
        unit = UNIT_G,
        unit_string = "g"
    },
    accz = {
        name = "@i18n(sensors.acc_z)@",
        mandatory = false,
        stats = true,
        unit = UNIT_G,
        unit_string = "g"
    },
    attyaw = {
        name = "@i18n(sensors.att_yaw)@",
        mandatory = false,
        stats = true,
        unit = UNIT_DEGREE,
        unit_string = "deg"
    },
    attroll = {
        name = "@i18n(sensors.att_roll)@",
        mandatory = false,
        stats = true,
        unit = UNIT_DEGREE,
        unit_string = "deg"
    },
    attpitch = {
        name = "@i18n(sensors.att_pitch)@",
        mandatory = false,
        stats = true,
        unit = UNIT_DEGREE,
        unit_string = "deg"
    },
    groundspeed = {
        name = "@i18n(sensors.groundspeed)@",
        mandatory = false,
        stats = true,
        unit = UNIT_KNOT,
        unit_string = "kt"
    }
}
