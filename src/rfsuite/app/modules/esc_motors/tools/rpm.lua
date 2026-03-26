--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

local function findField(node, apikey)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.apikey == apikey then
            return field
        end
    end

    return nil
end

local function readValue(node, apiName, apikey)
    local field = findField(node, apikey)
    if field and field.value ~= nil then
        return tonumber(field.value)
    end

    local apiEntry = node and node.state and node.state.apis and node.state.apis[apiName] or nil
    local api = apiEntry and apiEntry.api or nil
    if api and api.readValue then
        return tonumber(api.readValue(apikey))
    end

    return nil
end

local function setEnabled(node, apikey, enabled)
    local field = findField(node, apikey)
    local control = field and field.control or nil

    if control and control.enable then
        pcall(control.enable, control, enabled == true)
    end
end

local function wakeup(node)
    local protocol = tonumber(readValue(node, "MOTOR_CONFIG", "motor_pwm_protocol")) or 0
    local dshot = protocol >= 5 and protocol <= 8

    setEnabled(node, "use_dshot_telemetry", dshot)
end

return MspPage.create({
    title = "@i18n(app.modules.esc_motors.rpm)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    reboot = true,
    api = {
        {name = "MOTOR_CONFIG", rebuildOnWrite = true},
        {name = "FEATURE_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.esc_motors.main_motor_ratio)@", label = 1, inline_size = 15.5},
            {t = "@i18n(app.modules.esc_motors.tail_motor_ratio)@", label = 2, inline_size = 15.5}
        },
        fields = {
            {t = "@i18n(app.modules.esc_motors.rpm_sensor_source)@", api = "FEATURE_CONFIG", apikey = "freq_sensor", type = 1},
            {t = "@i18n(app.modules.esc_motors.use_dshot_telemetry)@", api = "MOTOR_CONFIG", apikey = "use_dshot_telemetry", type = 1},
            {t = "@i18n(app.modules.esc_motors.pinion)@", api = "MOTOR_CONFIG", apikey = "main_rotor_gear_ratio_0", label = 1, inline = 2},
            {t = "@i18n(app.modules.esc_motors.main)@", api = "MOTOR_CONFIG", apikey = "main_rotor_gear_ratio_1", label = 1, inline = 1},
            {t = "@i18n(app.modules.esc_motors.rear)@", api = "MOTOR_CONFIG", apikey = "tail_rotor_gear_ratio_0", label = 2, inline = 2},
            {t = "@i18n(app.modules.esc_motors.front)@", api = "MOTOR_CONFIG", apikey = "tail_rotor_gear_ratio_1", label = 2, inline = 1},
            {t = "@i18n(app.modules.esc_motors.motor_pole_count)@", api = "MOTOR_CONFIG", apikey = "motor_pole_count_0"}
        }
    },
    wakeup = wakeup
})
