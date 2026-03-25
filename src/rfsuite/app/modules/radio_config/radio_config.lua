--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

local function controlsReady(node)
    local index
    local field

    if not (node and node.state and node.state.loaded == true and node.state.loading ~= true) then
        return false
    end

    for index = 1, #(node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control then
            return true
        end
    end

    return false
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

local function validateThrottleValues(node)
    local armField
    local minField
    local arm
    local minimumAllowed

    if controlsReady(node) ~= true then
        node.state.radioConfigValidationSignature = nil
        return false
    end

    armField = findField(node, "rc_arm_throttle")
    minField = findField(node, "rc_min_throttle")
    if not armField or not minField then
        node.state.radioConfigValidationSignature = nil
        return false
    end

    arm = tonumber(armField.value)
    if arm == nil then
        return false
    end

    minimumAllowed = arm + 10
    minField.min = minimumAllowed

    if minField.control and minField.control.minimum then
        pcall(minField.control.minimum, minField.control, minimumAllowed)
    end

    if tonumber(minField.value) == nil or tonumber(minField.value) < minimumAllowed then
        minField.value = minimumAllowed
        if minField.control and minField.control.value then
            pcall(minField.control.value, minField.control, minimumAllowed)
        end
    end

    return true
end

local function wakeup(node)
    local armField = findField(node, "rc_arm_throttle")
    local minField = findField(node, "rc_min_throttle")
    local buildCount = node and node.app and node.app.formBuildCount or 0
    local signature

    if not armField or not minField then
        node.state.radioConfigValidationSignature = nil
        return
    end

    signature = table.concat({
        tostring(buildCount),
        tostring(armField.value),
        tostring(minField.value)
    }, "|")

    if node.state.radioConfigValidationSignature == signature then
        return
    end

    node.state.radioConfigValidationSignature = signature
    validateThrottleValues(node)
end

return MspPage.create({
    title = "@i18n(app.modules.radio_config.name)@",
    eepromWrite = true,
    reboot = true,
    help = {
        "@i18n(app.modules.radio_config.help_p1)@"
    },
    api = {
        {name = "RC_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.radio_config.stick)@", label = 1, inline_size = 16},
            {t = "@i18n(app.modules.radio_config.throttle)@", label = 2, inline_size = 16, apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.radio_config.throttle)@", label = 2, inline_size = 16, apiversionlte = {12, 0, 6}},
            {t = "", label = 3, inline_size = 16, apiversionlte = {12, 0, 6}},
            {t = "@i18n(app.modules.radio_config.deadband)@", label = 4, inline_size = 16}
        },
        fields = {
            {t = "@i18n(app.modules.radio_config.center)@", label = 1, inline = 2, apikey = "rc_center"},
            {t = "@i18n(app.modules.radio_config.deflection)@", label = 1, inline = 1, apikey = "rc_deflection"},

            {t = "@i18n(app.modules.radio_config.min_throttle)@", label = 2, inline = 2, apikey = "rc_min_throttle", apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.radio_config.max_throttle)@", label = 2, inline = 1, apikey = "rc_max_throttle", apiversiongte = {12, 0, 9}},

            {t = "@i18n(app.modules.radio_config.arming)@", label = 2, inline = 2, apikey = "rc_arm_throttle", apiversionlte = {12, 0, 6}},
            {t = "@i18n(app.modules.radio_config.min_throttle)@", label = 2, inline = 1, apikey = "rc_min_throttle", apiversionlte = {12, 0, 6}},
            {t = "@i18n(app.modules.radio_config.max_throttle)@", label = 3, inline = 1, apikey = "rc_max_throttle", apiversionlte = {12, 0, 6}},

            {t = "@i18n(app.modules.radio_config.cyclic)@", label = 4, inline = 2, apikey = "rc_deadband"},
            {t = "@i18n(app.modules.radio_config.yaw_deadband)@", label = 4, inline = 1, apikey = "rc_yaw_deadband"}
        }
    },
    wakeup = wakeup
})
