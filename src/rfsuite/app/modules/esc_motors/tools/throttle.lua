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

local function readValue(node, apikey)
    local field = findField(node, apikey)

    if field and field.value ~= nil then
        return tonumber(field.value)
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
    local protocol = tonumber(readValue(node, "motor_pwm_protocol")) or 0
    local unsynced = findField(node, "use_unsynced_pwm")
    local dshot = protocol >= 5 and protocol <= 8
    local editable = not dshot and protocol ~= 10
    local unsyncedEnabled = protocol >= 1 and protocol <= 4

    if unsynced and unsynced.value == nil then
        unsynced.value = 0
        if unsynced.control and unsynced.control.value then
            pcall(unsynced.control.value, unsynced.control, 0)
        end
    end

    setEnabled(node, "motor_pwm_rate", editable)
    setEnabled(node, "mincommand", editable)
    setEnabled(node, "minthrottle", editable)
    setEnabled(node, "maxthrottle", editable)
    setEnabled(node, "use_unsynced_pwm", unsyncedEnabled)
end

return MspPage.create({
    title = "@i18n(app.modules.esc_motors.throttle)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    api = {
        {name = "MOTOR_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.esc_motors.throttle_protocol)@", apikey = "motor_pwm_protocol", type = 1},
            {t = "@i18n(app.modules.esc_motors.motor_pwm_rate)@", apikey = "motor_pwm_rate"},
            {t = "@i18n(app.modules.esc_motors.mincommand)@", apikey = "mincommand"},
            {t = "@i18n(app.modules.esc_motors.min_throttle)@", apikey = "minthrottle"},
            {t = "@i18n(app.modules.esc_motors.max_throttle)@", apikey = "maxthrottle"},
            {t = "@i18n(app.modules.esc_motors.unsynced)@", apikey = "use_unsynced_pwm", type = 1}
        }
    },
    wakeup = wakeup
})
