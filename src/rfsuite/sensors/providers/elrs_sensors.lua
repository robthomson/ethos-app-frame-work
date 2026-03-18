--[[
  Copyright (C) 2025 Rotorflight Project
  GPLv3 - https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
ELRS sensor definition table.
Why this file exists:
- Keeps the large full SID map out of `elrs.lua` so it can be loaded on demand.
- Lets `elrs.lua` keep only active/runtime-needed metadata in memory.

Runtime contract:
- This file returns a *factory function* that receives decoder functions.
- The factory must return `table<SID, sensorDef>`.
- `sensorDef` fields used by runtime: `name`, `unit`, `prec`, `min`, `max`, `dec`.
- `dec` must always advance the parse pointer; otherwise ELRS parser will break out.

Update checklist:
1. Add/update SID entries here.
2. Keep decoder variable names aligned with decoder exports in `elrs.lua`.
3. If a SID is selected by telemetry slots, update `elrs_sid_lookup.lua` too.
4. Keep aggregator SIDs (for example control/attitude/accel/latlong/adj) mapped to
   decoders that publish any child SIDs they produce.
]]

return function(decoders)
    local decNil = decoders.decNil
    local decU8 = decoders.decU8
    local decS8 = decoders.decS8
    local decU16 = decoders.decU16
    local decS16 = decoders.decS16
    local decU24 = decoders.decU24
    local decS24 = decoders.decS24
    local decU32 = decoders.decU32
    local decS32 = decoders.decS32
    local decCellV = decoders.decCellV
    local decCells = decoders.decCells
    local decControl = decoders.decControl
    local decAttitude = decoders.decAttitude
    local decAccel = decoders.decAccel
    local decLatLong = decoders.decLatLong
    local decAdjFunc = decoders.decAdjFunc

    return {

    [0x1000] = {name = "@i18n(sensors.debug.null)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decNil}, -- NULL
    [0x1001] = {name = "@i18n(sensors.system.heartbeat)@", unit = UNIT_RAW, prec = 0, min = 0, max = 60000, dec = decU16}, -- Heartbeat
    [0x1011] = {name = "@i18n(sensors.power.voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 6500, dec = decU16}, -- Voltage
    [0x1012] = {name = "@i18n(sensors.power.current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 65000, dec = decU16}, -- Current
    [0x1013] = {name = "@i18n(sensors.power.consumption)@", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, min = 0, max = 65000, dec = decU16}, -- Consumption
    [0x1014] = {name = "@i18n(sensors.power.charge_level)@", unit = UNIT_PERCENT, prec = 0, min = 0, max = 100, dec = decU8}, -- Charge Level
    [0x1020] = {name = "@i18n(sensors.power.cell_count)@", unit = UNIT_RAW, prec = 0, min = 0, max = 16, dec = decU8}, -- Cell Count
    [0x1021] = {name = "@i18n(sensors.power.cell_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 455, dec = decCellV}, -- Cell Voltage
    [0x102F] = {name = "@i18n(sensors.power.cell_voltages)@", unit = UNIT_VOLT, prec = 2, min = nil, max = nil, dec = decCells}, -- Cell Voltages
    [0x1030] = {name = "@i18n(sensors.control.summary)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decControl}, -- Ctrl
    [0x1031] = {name = "@i18n(sensors.control.pitch)@", unit = UNIT_DEGREE, prec = 1, min = -450, max = 450, dec = decS16}, -- Pitch Control
    [0x1032] = {name = "@i18n(sensors.control.roll)@", unit = UNIT_DEGREE, prec = 1, min = -450, max = 450, dec = decS16}, -- Roll Control
    [0x1033] = {name = "@i18n(sensors.control.yaw)@", unit = UNIT_DEGREE, prec = 1, min = -900, max = 900, dec = decS16}, -- Yaw Control
    [0x1034] = {name = "@i18n(sensors.control.collective)@", unit = UNIT_DEGREE, prec = 1, min = -450, max = 450, dec = decS16}, -- Coll Control
    [0x1035] = {name = "@i18n(sensors.control.throttle)@", unit = UNIT_PERCENT, prec = 0, min = -100, max = 100, dec = decS8}, -- Throttle %
    [0x1041] = {name = "@i18n(sensors.esc1.voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 6500, dec = decU16}, -- ESC1 Voltage
    [0x1042] = {name = "@i18n(sensors.esc1.current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 65000, dec = decU16}, -- ESC1 Current
    [0x1043] = {name = "@i18n(sensors.esc1.consumption)@", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, min = 0, max = 65000, dec = decU16}, -- ESC1 Consump
    [0x1044] = {name = "@i18n(sensors.esc1.erpm)@", unit = UNIT_RPM, prec = 0, min = 0, max = 65535, dec = decU24}, -- ESC1 eRPM
    [0x1045] = {name = "@i18n(sensors.esc1.pwm)@", unit = UNIT_PERCENT, prec = 1, min = 0, max = 1000, dec = decU16}, -- ESC1 PWM
    [0x1046] = {name = "@i18n(sensors.esc1.throttle)@", unit = UNIT_PERCENT, prec = 1, min = 0, max = 1000, dec = decU16}, -- ESC1 Throttle
    [0x1047] = {name = "@i18n(sensors.esc1.temp)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC1 Temp
    [0x1048] = {name = "@i18n(sensors.esc1.temp_2)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC1 Temp 2
    [0x1049] = {name = "@i18n(sensors.esc1.bec_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 1500, dec = decU16}, -- ESC1 BEC Volt
    [0x104A] = {name = "@i18n(sensors.esc1.bec_current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 10000, dec = decU16}, -- ESC1 BEC Curr
    [0x104E] = {name = "@i18n(sensors.esc1.status)@", unit = UNIT_RAW, prec = 0, min = 0, max = 2147483647, dec = decU32}, -- ESC1 Status
    [0x104F] = {name = "@i18n(sensors.esc1.model_id)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC1 Model ID
    [0x1051] = {name = "@i18n(sensors.esc2.voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 6500, dec = decU16}, -- ESC2 Voltage
    [0x1052] = {name = "@i18n(sensors.esc2.current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 65000, dec = decU16}, -- ESC2 Current
    [0x1053] = {name = "@i18n(sensors.esc2.consumption)@", unit = UNIT_MILLIAMPERE_HOUR, prec = 0, min = 0, max = 65000, dec = decU16}, -- ESC2 Consump
    [0x1054] = {name = "@i18n(sensors.esc2.erpm)@", unit = UNIT_RPM, prec = 0, min = 0, max = 65535, dec = decU24}, -- ESC2 eRPM
    [0x1057] = {name = "@i18n(sensors.esc2.temp)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC2 Temp
    [0x105F] = {name = "@i18n(sensors.esc2.model_id)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC2 Model ID
    [0x1080] = {name = "@i18n(sensors.power.esc_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 6500, dec = decU16}, -- ESC Voltage
    [0x1081] = {name = "@i18n(sensors.power.bec_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 1600, dec = decU16}, -- BEC Voltage
    [0x1082] = {name = "@i18n(sensors.power.bus_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 1200, dec = decU16}, -- BUS Voltage
    [0x1083] = {name = "@i18n(sensors.power.mcu_voltage)@", unit = UNIT_VOLT, prec = 2, min = 0, max = 500, dec = decU16}, -- MCU Voltage
    [0x1090] = {name = "@i18n(sensors.power.esc_current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 65000, dec = decU16}, -- ESC Current
    [0x1091] = {name = "@i18n(sensors.power.bec_current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 10000, dec = decU16}, -- BEC Current
    [0x1092] = {name = "@i18n(sensors.power.bus_current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 1000, dec = decU16}, -- BUS Current
    [0x1093] = {name = "@i18n(sensors.power.mcu_current)@", unit = UNIT_AMPERE, prec = 2, min = 0, max = 1000, dec = decU16}, -- MCU Current
    [0x10A0] = {name = "@i18n(sensors.power.esc_temp)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- ESC Temp
    [0x10A1] = {name = "@i18n(sensors.power.bec_temp)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- BEC Temp
    [0x10A3] = {name = "@i18n(sensors.system.mcu_temp)@", unit = UNIT_CELSIUS, prec = 0, min = 0, max = 255, dec = decU8}, -- MCU Temp
    [0x10B1] = {name = "@i18n(sensors.attitude.heading)@", unit = UNIT_DEGREE, prec = 1, min = -1800, max = 3600, dec = decS16}, -- Heading
    [0x10B2] = {name = "@i18n(sensors.attitude.altitude)@", unit = UNIT_METER, prec = 2, min = -100000, max = 100000, dec = decS24}, -- Altitude
    [0x10B3] = {name = "@i18n(sensors.attitude.vertical_speed)@", unit = UNIT_METER_PER_SECOND, prec = 2, min = -10000, max = 10000, dec = decS16}, -- VSpeed
    [0x10C0] = {name = "@i18n(sensors.rotor.headspeed)@", unit = UNIT_RPM, prec = 0, min = 0, max = 65535, dec = decU16}, -- Headspeed
    [0x10C1] = {name = "@i18n(sensors.rotor.tailspeed)@", unit = UNIT_RPM, prec = 0, min = 0, max = 65535, dec = decU16}, -- Tailspeed
    [0x1100] = {name = "@i18n(sensors.attitude.summary)@", unit = UNIT_DEGREE, prec = 1, min = nil, max = nil, dec = decAttitude}, -- Attd
    [0x1101] = {name = "@i18n(sensors.attitude.pitch)@", unit = UNIT_DEGREE, prec = 0, min = -180, max = 360, dec = decS16}, -- Pitch Attitude
    [0x1102] = {name = "@i18n(sensors.attitude.roll)@", unit = UNIT_DEGREE, prec = 0, min = -180, max = 360, dec = decS16}, -- Roll Attitude
    [0x1103] = {name = "@i18n(sensors.attitude.yaw)@", unit = UNIT_DEGREE, prec = 0, min = -180, max = 360, dec = decS16}, -- Yaw Attitude
    [0x1110] = {name = "@i18n(sensors.accel.summary)@", unit = UNIT_G, prec = 2, min = nil, max = nil, dec = decAccel}, -- Accl
    [0x1111] = {name = "@i18n(sensors.accel.x)@", unit = UNIT_G, prec = 1, min = -4000, max = 4000, dec = decS16}, -- Accel X
    [0x1112] = {name = "@i18n(sensors.accel.y)@", unit = UNIT_G, prec = 1, min = -4000, max = 4000, dec = decS16}, -- Accel Y
    [0x1113] = {name = "@i18n(sensors.accel.z)@", unit = UNIT_G, prec = 1, min = -4000, max = 4000, dec = decS16}, -- Accel Z
    [0x1121] = {name = "@i18n(sensors.gps.sats)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- GPS Sats
    [0x1122] = {name = "@i18n(sensors.gps.pdop)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- GPS PDOP
    [0x1123] = {name = "@i18n(sensors.gps.hdop)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- GPS HDOP
    [0x1124] = {name = "@i18n(sensors.gps.vdop)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- GPS VDOP
    [0x1125] = {name = "@i18n(sensors.gps.coordinates)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decLatLong}, -- GPS Coord
    [0x1126] = {name = "@i18n(sensors.gps.altitude)@", unit = UNIT_METER, prec = 2, min = -100000000, max = 100000000, dec = decS16}, -- GPS Altitude
    [0x1127] = {name = "@i18n(sensors.gps.heading)@", unit = UNIT_DEGREE, prec = 1, min = -1800, max = 3600, dec = decS16}, -- GPS Heading
    [0x1128] = {name = "@i18n(sensors.gps.speed)@", unit = UNIT_METER_PER_SECOND, prec = 2, min = 0, max = 10000, dec = decU16}, -- GPS Speed
    [0x1129] = {name = "@i18n(sensors.gps.home_distance)@", unit = UNIT_METER, prec = 1, min = 0, max = 65535, dec = decU16}, -- GPS Home Dist
    [0x112A] = {name = "@i18n(sensors.gps.home_direction)@", unit = UNIT_METER, prec = 1, min = 0, max = 3600, dec = decU16}, -- GPS Home Dir
    [0x1141] = {name = "@i18n(sensors.system.cpu_load)@", unit = UNIT_PERCENT, prec = 0, min = 0, max = 100, dec = decU8}, -- CPU Load
    [0x1142] = {name = "@i18n(sensors.system.system_load)@", unit = UNIT_PERCENT, prec = 0, min = 0, max = 10, dec = decU8}, -- SYS Load
    [0x1143] = {name = "@i18n(sensors.system.rt_load)@", unit = UNIT_PERCENT, prec = 0, min = 0, max = 200, dec = decU8}, -- RT Load
    [0x1200] = {name = "@i18n(sensors.system.model_id)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- Model ID
    [0x1201] = {name = "@i18n(sensors.system.flight_mode)@", unit = UNIT_RAW, prec = 0, min = 0, max = 65535, dec = decU16}, -- Flight Mode
    [0x1202] = {name = "@i18n(sensors.system.arming_flags)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- Arming Flags
    [0x1203] = {name = "@i18n(sensors.system.arming_disable)@", unit = UNIT_RAW, prec = 0, min = 0, max = 2147483647, dec = decU32}, -- Arming Disable
    [0x1204] = {name = "@i18n(sensors.system.rescue_state)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- Rescue
    [0x1205] = {name = "@i18n(sensors.system.governor)@", unit = UNIT_RAW, prec = 0, min = 0, max = 255, dec = decU8}, -- Governor
    [0x1211] = {name = "@i18n(sensors.system.pid_profile)@", unit = UNIT_RAW, prec = 0, min = 1, max = 6, dec = decU8}, -- PID Profile
    [0x1212] = {name = "@i18n(sensors.system.rate_profile)@", unit = UNIT_RAW, prec = 0, min = 1, max = 6, dec = decU8}, -- Rate Profile
    [0x1213] = {name = "@i18n(sensors.system.led_profile)@", unit = UNIT_RAW, prec = 0, min = 1, max = 6, dec = decU8}, -- LED Profile
    [0x1214] = {name = "@i18n(sensors.system.battery_profile)@", unit = UNIT_RAW, prec = 0, min = 1, max = 6, dec = decU8}, -- Battery Profile
    [0x1220] = {name = "@i18n(sensors.control.adjustment)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decAdjFunc}, -- ADJ
    [0xDB00] = {name = "@i18n(sensors.debug.value_0)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 0
    [0xDB01] = {name = "@i18n(sensors.debug.value_1)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 1
    [0xDB02] = {name = "@i18n(sensors.debug.value_2)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 2
    [0xDB03] = {name = "@i18n(sensors.debug.value_3)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 3
    [0xDB04] = {name = "@i18n(sensors.debug.value_4)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 4
    [0xDB05] = {name = "@i18n(sensors.debug.value_5)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 5
    [0xDB06] = {name = "@i18n(sensors.debug.value_6)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32}, -- Debug 6
    [0xDB07] = {name = "@i18n(sensors.debug.value_7)@", unit = UNIT_RAW, prec = 0, min = nil, max = nil, dec = decS32} -- Debug 7
}
end
