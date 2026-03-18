--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

return {
    create = {
        [0x5100] = {name = "@i18n(sensors.system.heartbeat)@", unit = UNIT_RAW}, -- Heartbeat
        [0x5250] = {name = "@i18n(sensors.power.consumption)@", unit = UNIT_MILLIAMPERE_HOUR}, -- Consumption
        [0x5260] = {name = "@i18n(sensors.power.cell_count)@", unit = UNIT_RAW}, -- Cell Count
        [0x51A0] = {name = "@i18n(sensors.control.pitch)@", unit = UNIT_DEGREE, decimals = 2}, -- Pitch Control
        [0x51A1] = {name = "@i18n(sensors.control.roll)@", unit = UNIT_DEGREE, decimals = 2}, -- Roll Control
        [0x51A2] = {name = "@i18n(sensors.control.yaw)@", unit = UNIT_DEGREE, decimals = 2}, -- Yaw Control
        [0x51A3] = {name = "@i18n(sensors.control.collective)@", unit = UNIT_DEGREE, decimals = 2}, -- Collective Ctrl
        [0x51A4] = {name = "@i18n(sensors.control.throttle)@", unit = UNIT_PERCENT, decimals = 1}, -- Throttle %
        [0x5258] = {name = "@i18n(sensors.esc1.capacity)@", unit = UNIT_MILLIAMPERE_HOUR}, -- ESC1 Capacity
        [0x5268] = {name = "@i18n(sensors.esc1.power)@", unit = UNIT_PERCENT}, -- ESC1 Power
        [0x5269] = {name = "@i18n(sensors.esc1.throttle)@", unit = UNIT_PERCENT, decimals = 1}, -- ESC1 Throttle
        [0x5128] = {name = "@i18n(sensors.esc1.status)@", unit = UNIT_RAW}, -- ESC1 Status
        [0x5129] = {name = "@i18n(sensors.esc1.model_id)@", unit = UNIT_RAW}, -- ESC1 Model ID
        [0x525A] = {name = "@i18n(sensors.esc2.capacity)@", unit = UNIT_MILLIAMPERE_HOUR}, -- ESC2 Capacity
        [0x512B] = {name = "@i18n(sensors.esc2.model_id)@", unit = UNIT_RAW}, -- ESC2 Model ID
        [0x51D0] = {name = "@i18n(sensors.system.cpu_load)@", unit = UNIT_PERCENT}, -- CPU Load
        [0x51D1] = {name = "@i18n(sensors.system.system_load)@", unit = UNIT_PERCENT}, -- System Load
        [0x51D2] = {name = "@i18n(sensors.system.rt_load)@", unit = UNIT_PERCENT}, -- RT Load
        [0x5120] = {name = "@i18n(sensors.system.model_id)@", unit = UNIT_RAW}, -- Model ID
        [0x5121] = {name = "@i18n(sensors.system.flight_mode)@", unit = UNIT_RAW}, -- Flight Mode
        [0x5122] = {name = "@i18n(sensors.system.arming_flags)@", unit = UNIT_RAW}, -- Arm Flags
        [0x5123] = {name = "@i18n(sensors.system.arming_disable)@", unit = UNIT_RAW}, -- Arm Dis Flags
        [0x5124] = {name = "@i18n(sensors.system.rescue_state)@", unit = UNIT_RAW}, -- Rescue State
        [0x5125] = {name = "@i18n(sensors.system.governor)@", unit = UNIT_RAW}, -- Gov State
        [0x5130] = {name = "@i18n(sensors.system.pid_profile)@", unit = UNIT_RAW}, -- PID Profile
        [0x5131] = {name = "@i18n(sensors.system.rate_profile)@", unit = UNIT_RAW}, -- Rates Profile
        [0x5132] = {name = "@i18n(sensors.system.led_profile)@", unit = UNIT_RAW}, -- LED Profile
        [0x5133] = {name = "@i18n(sensors.system.battery_profile)@", unit = UNIT_RAW}, -- Battery Profile
        [0x5110] = {name = "@i18n(sensors.control.adjustment_function)@", unit = UNIT_RAW}, -- Adj Function
        [0x5111] = {name = "@i18n(sensors.control.adjustment_value)@", unit = UNIT_RAW}, -- Adj Value
        [0x5210] = {name = "@i18n(sensors.attitude.heading)@", unit = UNIT_DEGREE, decimals = 1}, -- Heading
        [0x52F0] = {name = "@i18n(sensors.debug.value_0)@", unit = UNIT_RAW}, -- Debug 0
        [0x52F1] = {name = "@i18n(sensors.debug.value_1)@", unit = UNIT_RAW}, -- Debug 1
        [0x52F2] = {name = "@i18n(sensors.debug.value_2)@", unit = UNIT_RAW}, -- Debug 2
        [0x52F3] = {name = "@i18n(sensors.debug.value_3)@", unit = UNIT_RAW}, -- Debug 3
        [0x52F4] = {name = "@i18n(sensors.debug.value_4)@", unit = UNIT_RAW}, -- Debug 4
        [0x52F5] = {name = "@i18n(sensors.debug.value_5)@", unit = UNIT_RAW}, -- Debug 5
        [0x52F6] = {name = "@i18n(sensors.debug.value_6)@", unit = UNIT_RAW}, -- Debug 6
        [0x52F8] = {name = "@i18n(sensors.debug.value_7)@", unit = UNIT_RAW} -- Debug 7
    },
    rename = {
        [0x0500] = {name = "@i18n(sensors.rotor.headspeed)@", onlyifname = "RPM"}, -- Headspeed
        [0x0501] = {name = "@i18n(sensors.rotor.tailspeed)@", onlyifname = "RPM"}, -- Tailspeed
        [0x0210] = {name = "@i18n(sensors.power.voltage)@", onlyifname = "VFAS"}, -- Voltage
        [0x0600] = {name = "@i18n(sensors.power.charge_level)@", onlyifname = "Fuel"}, -- Charge Level
        [0x0910] = {name = "@i18n(sensors.power.cell_voltage)@", onlyifname = "ADC4"}, -- Cell Voltage
        [0x0211] = {name = "@i18n(sensors.power.esc_voltage)@", onlyifname = "VFAS"}, -- ESC Voltage
        [0x0B70] = {name = "@i18n(sensors.power.esc_temp)@", onlyifname = "ESC temp"}, -- ESC Temp
        [0x0218] = {name = "@i18n(sensors.esc1.voltage)@", onlyifname = "VFAS"}, -- ESC1 Voltage
        [0x0208] = {name = "@i18n(sensors.esc1.current)@", onlyifname = "Current"}, -- ESC1 Current
        [0x0508] = {name = "@i18n(sensors.esc1.rpm)@", onlyifname = "RPM"}, -- ESC1 RPM
        [0x0418] = {name = "@i18n(sensors.esc1.temp)@", onlyifname = "Temp2"}, -- ESC1 Temp
        [0x0219] = {name = "@i18n(sensors.esc1.bec_voltage)@", onlyifname = "VFAS"}, -- ESC1 BEC Voltage
        [0x0229] = {name = "@i18n(sensors.esc1.bec_current)@", onlyifname = "Current"}, -- ESC1 BEC Current
        [0x0419] = {name = "@i18n(sensors.esc1.bec_temp)@", onlyifname = "Temp2"}, -- ESC1 BEC Temp
        [0x021A] = {name = "@i18n(sensors.esc2.voltage)@", onlyifname = "VFAS"}, -- ESC2 Voltage
        [0x020A] = {name = "@i18n(sensors.esc2.current)@", onlyifname = "Current"}, -- ESC2 Current
        [0x050A] = {name = "@i18n(sensors.esc2.rpm)@", onlyifname = "RPM"}, -- ESC2 RPM
        [0x041A] = {name = "@i18n(sensors.esc2.temp)@", onlyifname = "Temp2"}, -- ESC2 Temp
        [0x0840] = {name = "@i18n(sensors.gps.heading)@", onlyifname = "GPS course"}, -- GPS Heading
        [0x0900] = {name = "@i18n(sensors.power.mcu_voltage)@", onlyifname = "ADC3"}, -- MCU Voltage
        [0x0901] = {name = "@i18n(sensors.power.bec_voltage)@", onlyifname = "ADC3"}, -- BEC Voltage
        [0x0902] = {name = "@i18n(sensors.power.bus_voltage)@", onlyifname = "ADC3"}, -- Bus Voltage
        [0x0201] = {name = "@i18n(sensors.power.esc_current)@", onlyifname = "Current"}, -- ESC Current
        [0x0222] = {name = "@i18n(sensors.power.bec_current)@", onlyifname = "Current"}, -- BEC Current
        [0x0400] = {name = "@i18n(sensors.system.mcu_temp)@", onlyifname = "Temp1"}, -- MCU Temp
        [0x0401] = {name = "@i18n(sensors.power.esc_temp)@", onlyifname = "Temp1"}, -- ESC Temp
        [0x0402] = {name = "@i18n(sensors.power.bec_temp)@", onlyifname = "Temp1"}, -- BEC Temp
        [0x5210] = {name = "@i18n(sensors.attitude.yaw)@", onlyifname = "Heading"} -- Yaw Attitude
    },
    drop = {}
}
