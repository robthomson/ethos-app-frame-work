--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

return {
    rssi = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}},
    link = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}, "RSSI 1", "RSSI 2"},
    vfr = {{crsfId = 0x14, subIdStart = 0, subIdEnd = 1}},
    armflags = {},
    voltage = {"Rx Batt"},
    rpm = {"GPS Alt"},
    current = {"Rx Curr"},
    temp_esc = {"GPS Speed"},
    temp_mcu = {"GPS Sats"},
    fuel = {"Rx Batt%"},
    smartfuel = {},
    smartconsumption = {},
    consumption = {"Rx Cons"},
    governor = {"Flight mode"},
    adj_f = {},
    adj_v = {},
    pid_profile = {},
    rate_profile = {},
    battery_profile = {},
    led_profile = {},
    throttle_percent = {},
    armdisableflags = {},
    altitude = {},
    bec_voltage = {},
    cell_count = {},
    accx = {},
    accy = {},
    accz = {},
    attyaw = {},
    attroll = {},
    attpitch = {},
    groundspeed = {}
}
