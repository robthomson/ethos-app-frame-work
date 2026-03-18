--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

return {
    rssi = {{crsfId = 0x14, subId = 2}},
    link = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}, "Rx RSSI1"},
    vfr = {{crsfId = 0x14, subId = 2}},
    armflags = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1202}},
    armdisableflags = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1203}},
    voltage = {
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1011},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1041},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1051},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1080},
        {crsfId = 8}
    },
    current = {
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1012},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1042},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x104A}
    },
    bec_voltage = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1081}, {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1049}},
    fuel = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1014}},
    smartfuel = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE1}},
    smartconsumption = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5FE0}},
    consumption = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1013}},
    temp_esc = {
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10A0},
        {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1047}
    },
    temp_mcu = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10A3}},
    rpm = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10C0}},
    governor = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1205}},
    adj_f = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1221}},
    adj_v = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1222}},
    pid_profile = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1211}},
    rate_profile = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1212}},
    battery_profile = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1214}},
    throttle_percent = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1035}},
    altitude = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10B2}},
    groundspeed = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1128}},
    attroll = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1102}},
    attpitch = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1101}},
    attyaw = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1103}},
    accx = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1111}},
    accy = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1112}},
    accz = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1113}},
    cell_count = {{category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1020}},
    led_profile = {}
}
