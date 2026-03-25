--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

local FEATURE_BITS = {
    gps = 7,
    governor = 26,
    esc_sensor = 27
}

local function bitFlag(bit)
    return 2 ^ (tonumber(bit or 0) or 0)
end

local function hasBit(mask, bit)
    local numericMask = tonumber(mask or 0) or 0
    local flag = bitFlag(bit)
    return math.floor(numericMask / flag) % 2 == 1
end

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

local function readApiValue(node, apiName, apikey)
    local apiEntry = node and node.state and node.state.apis and node.state.apis[apiName] or nil
    local api = apiEntry and apiEntry.api or nil

    if api and api.readValue then
        return api.readValue(apikey)
    end

    return nil
end

local function setFieldEnabled(node, apikey, enabled)
    local field = findField(node, apikey)
    local control = field and field.control or nil

    if control and control.enable then
        pcall(control.enable, control, enabled == true)
    end
end

local function syncControlState(node)
    if not (node and node.state and node.state.loaded == true and node.state.loading ~= true) then
        return
    end

    local enabledFeatures = tonumber(readApiValue(node, "FEATURE_CONFIG", "enabledFeatures")) or 0
    local supported = tonumber(readApiValue(node, "BLACKBOX_CONFIG", "blackbox_supported")) or 0
    local device = tonumber(readApiValue(node, "BLACKBOX_CONFIG", "device")) or 0
    local mode = tonumber(readApiValue(node, "BLACKBOX_CONFIG", "mode")) or 0
    local editable = supported == 1 and device ~= 0 and mode ~= 0
    local buildCount = node and node.app and node.app.formBuildCount or 0
    local signature = table.concat({
        tostring(buildCount),
        tostring(enabledFeatures),
        tostring(editable)
    }, "|")

    if node.state.blackboxLoggingSignature == signature then
        return
    end

    node.state.blackboxLoggingSignature = signature

    setFieldEnabled(node, "command", editable)
    setFieldEnabled(node, "setpoint", editable)
    setFieldEnabled(node, "mixer", editable)
    setFieldEnabled(node, "pid", editable)
    setFieldEnabled(node, "attitude", editable)
    setFieldEnabled(node, "gyroraw", editable)
    setFieldEnabled(node, "gyro", editable)
    setFieldEnabled(node, "acc", editable)
    setFieldEnabled(node, "mag", editable)
    setFieldEnabled(node, "alt", editable)
    setFieldEnabled(node, "battery", editable)
    setFieldEnabled(node, "rssi", editable)
    setFieldEnabled(node, "gps", editable and hasBit(enabledFeatures, FEATURE_BITS.gps))
    setFieldEnabled(node, "rpm", editable)
    setFieldEnabled(node, "motors", editable)
    setFieldEnabled(node, "servos", editable)
    setFieldEnabled(node, "vbec", editable)
    setFieldEnabled(node, "vbus", editable)
    setFieldEnabled(node, "temps", editable)
    setFieldEnabled(node, "esc", editable and hasBit(enabledFeatures, FEATURE_BITS.esc_sensor))
    setFieldEnabled(node, "bec", editable and hasBit(enabledFeatures, FEATURE_BITS.esc_sensor))
    setFieldEnabled(node, "esc2", editable and hasBit(enabledFeatures, FEATURE_BITS.esc_sensor))
    setFieldEnabled(node, "governor", editable and hasBit(enabledFeatures, FEATURE_BITS.governor))
end

return MspPage.create({
    title = "@i18n(app.modules.blackbox.menu_logging)@",
    loaderOnEnter = {
        watchdogTimeout = 12.0
    },
    loaderOnSave = {
        watchdogTimeout = 16.0
    },
    eepromWrite = true,
    keepApisLoaded = true,
    help = {
        "@i18n(app.modules.blackbox.help_p1)@",
        "@i18n(app.modules.blackbox.help_p2)@",
        "@i18n(app.modules.blackbox.help_p3)@"
    },
    api = {
        {name = "BLACKBOX_CONFIG", rebuildOnWrite = true},
        {name = "FEATURE_CONFIG"}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.blackbox.log_command)@", api = "BLACKBOX_CONFIG", apikey = "command", type = 1},
            {t = "@i18n(app.modules.blackbox.log_setpoint)@", api = "BLACKBOX_CONFIG", apikey = "setpoint", type = 1},
            {t = "@i18n(app.modules.blackbox.log_mixer)@", api = "BLACKBOX_CONFIG", apikey = "mixer", type = 1},
            {t = "@i18n(app.modules.blackbox.log_pid)@", api = "BLACKBOX_CONFIG", apikey = "pid", type = 1},
            {t = "@i18n(app.modules.blackbox.log_attitude)@", api = "BLACKBOX_CONFIG", apikey = "attitude", type = 1},
            {t = "@i18n(app.modules.blackbox.log_gyro_raw)@", api = "BLACKBOX_CONFIG", apikey = "gyroraw", type = 1},
            {t = "@i18n(app.modules.blackbox.log_gyro)@", api = "BLACKBOX_CONFIG", apikey = "gyro", type = 1},
            {t = "@i18n(app.modules.blackbox.log_acc)@", api = "BLACKBOX_CONFIG", apikey = "acc", type = 1},
            {t = "@i18n(app.modules.blackbox.log_mag)@", api = "BLACKBOX_CONFIG", apikey = "mag", type = 1},
            {t = "@i18n(app.modules.blackbox.log_alt)@", api = "BLACKBOX_CONFIG", apikey = "alt", type = 1},
            {t = "@i18n(app.modules.blackbox.log_battery)@", api = "BLACKBOX_CONFIG", apikey = "battery", type = 1},
            {t = "@i18n(app.modules.blackbox.log_rssi)@", api = "BLACKBOX_CONFIG", apikey = "rssi", type = 1},
            {t = "@i18n(app.modules.blackbox.log_gps)@", api = "BLACKBOX_CONFIG", apikey = "gps", type = 1},
            {t = "@i18n(app.modules.blackbox.log_rpm)@", api = "BLACKBOX_CONFIG", apikey = "rpm", type = 1},
            {t = "@i18n(app.modules.blackbox.log_motors)@", api = "BLACKBOX_CONFIG", apikey = "motors", type = 1},
            {t = "@i18n(app.modules.blackbox.log_servos)@", api = "BLACKBOX_CONFIG", apikey = "servos", type = 1},
            {t = "@i18n(app.modules.blackbox.log_vbec)@", api = "BLACKBOX_CONFIG", apikey = "vbec", type = 1},
            {t = "@i18n(app.modules.blackbox.log_vbus)@", api = "BLACKBOX_CONFIG", apikey = "vbus", type = 1},
            {t = "@i18n(app.modules.blackbox.log_temps)@", api = "BLACKBOX_CONFIG", apikey = "temps", type = 1},
            {t = "@i18n(app.modules.blackbox.log_esc)@", api = "BLACKBOX_CONFIG", apikey = "esc", type = 1, apiversiongte = {12, 0, 7}},
            {t = "@i18n(app.modules.blackbox.log_bec)@", api = "BLACKBOX_CONFIG", apikey = "bec", type = 1, apiversiongte = {12, 0, 7}},
            {t = "@i18n(app.modules.blackbox.log_esc2)@", api = "BLACKBOX_CONFIG", apikey = "esc2", type = 1, apiversiongte = {12, 0, 7}},
            {t = "@i18n(app.modules.blackbox.log_governor)@", api = "BLACKBOX_CONFIG", apikey = "governor", type = 1, apiversiongte = {12, 0, 9}}
        }
    },
    controlStateSync = syncControlState
})
