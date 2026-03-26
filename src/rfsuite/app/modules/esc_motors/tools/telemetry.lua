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
    local protocol = tonumber(readValue(node, "protocol")) or 0
    local enabled = protocol ~= 0

    setEnabled(node, "half_duplex", enabled)
    setEnabled(node, "pin_swap", enabled)
    setEnabled(node, "voltage_correction", enabled)
    setEnabled(node, "current_correction", enabled)
    setEnabled(node, "consumption_correction", enabled)
end

return MspPage.create({
    title = "@i18n(app.modules.esc_motors.telemetry)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    api = {
        {name = "ESC_SENSOR_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.esc_motors.telemetry_protocol)@", apikey = "protocol", type = 1},
            {t = "@i18n(app.modules.esc_motors.half_duplex)@", apikey = "half_duplex", type = 1},
            {t = "@i18n(app.modules.esc_motors.pin_swap)@", apikey = "pin_swap", type = 1, apiversiongte = {12, 0, 7}},
            {t = "@i18n(app.modules.esc_motors.voltage_correction)@", apikey = "voltage_correction", apiversiongte = {12, 0, 8}},
            {t = "@i18n(app.modules.esc_motors.current_correction)@", apikey = "current_correction", apiversiongte = {12, 0, 8}},
            {t = "@i18n(app.modules.esc_motors.consumption_correction)@", apikey = "consumption_correction", apiversiongte = {12, 0, 8}}
        }
    },
    wakeup = wakeup
})
