--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

return {
    rssi = {{appId = 0xF010, subId = 0}},
    link = {{appId = 0xF101, subId = 0}},
    vfr = {{appId = 0xF010, subId = 0}},
    armflags = {{uid = 0x5001, value = function() return utils.simSensors("armflags") end, min = 0, max = 2}},
    voltage = {{uid = 0x5002, unit = UNIT_VOLT, dec = 2, value = function() return utils.simSensors("voltage") end, min = 0, max = 3000}},
    rpm = {{uid = 0x5003, unit = UNIT_RPM, value = function() return utils.simSensors("rpm") end, min = 0, max = 20000}},
    current = {{uid = 0x5004, unit = UNIT_AMPERE, value = function() return utils.simSensors("current") end, min = 0, max = 300}},
    temp_esc = {{uid = 0x5005, unit = UNIT_DEGREE, value = function() return utils.simSensors("temp_esc") end, min = 0, max = 100}},
    temp_mcu = {{uid = 0x5006, unit = UNIT_DEGREE, value = function() return utils.simSensors("temp_mcu") end, min = 0, max = 100}},
    fuel = {{uid = 0x5007, unit = UNIT_PERCENT, value = function() return utils.simSensors("fuel") end, min = 0, max = 100}},
    smartfuel = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1}},
    smartconsumption = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE0}},
    consumption = {{uid = 0x5008, unit = UNIT_MILLIAMPERE_HOUR, value = function() return utils.simSensors("consumption") end, min = 0, max = 5000}},
    governor = {{uid = 0x5009, value = function() return utils.simSensors("governor") end, min = 0, max = 200}},
    adj_f = {{uid = 0x5010, value = function() return utils.simSensors("adj_f") end, min = 0, max = 10}},
    adj_v = {{uid = 0x5011, value = function() return utils.simSensors("adj_v") end, min = 0, max = 2000}},
    pid_profile = {{uid = 0x5012, value = function() return utils.simSensors("pid_profile") end, min = 0, max = 6}},
    rate_profile = {{uid = 0x5013, value = function() return utils.simSensors("rate_profile") end, min = 0, max = 6}},
    battery_profile = {{uid = 0x5026, value = function() return utils.simSensors("battery_profile") end, min = 0, max = 6}},
    throttle_percent = {{uid = 0x5014, unit = UNIT_PERCENT, value = function() return utils.simSensors("throttle_percent") end, min = 0, max = 100}},
    armdisableflags = {{uid = 0x5015, value = function() return utils.simSensors("armdisableflags") end, min = 0, max = 65536}},
    altitude = {{uid = 0x5016, unit = UNIT_METER, value = function() return utils.simSensors("altitude") end, min = 0, max = 50000}},
    bec_voltage = {{uid = 0x5017, unit = UNIT_VOLT, dec = 2, value = function() return utils.simSensors("bec_voltage") end, min = 0, max = 3000}},
    cell_count = {{uid = 0x5018, value = function() return utils.simSensors("cell_count") end, min = 0, max = 50}},
    accx = {{uid = 0x5019, unit = UNIT_G, dec = 3, value = function() return utils.simSensors("accx") end, min = -4000, max = 4000}},
    accy = {{uid = 0x5020, unit = UNIT_G, dec = 3, value = function() return utils.simSensors("accy") end, min = -4000, max = 4000}},
    accz = {{uid = 0x5021, unit = UNIT_G, dec = 3, value = function() return utils.simSensors("accz") end, min = -4000, max = 4000}},
    attyaw = {{uid = 0x5022, unit = UNIT_DEGREE, dec = 1, value = function() return utils.simSensors("attyaw") end, min = -1800, max = 3600}},
    attroll = {{uid = 0x5023, unit = UNIT_DEGREE, dec = 1, value = function() return utils.simSensors("attroll") end, min = -1800, max = 3600}},
    attpitch = {{uid = 0x5024, unit = UNIT_DEGREE, dec = 1, value = function() return utils.simSensors("attpitch") end, min = -1800, max = 3600}},
    groundspeed = {{uid = 0x5025, unit = UNIT_KNOT, dec = 1, value = function() return utils.simSensors("groundspeed") end, min = 0, max = 3600}},
    led_profile = {}
}
