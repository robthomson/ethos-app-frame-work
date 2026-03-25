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

local function readBlackboxValue(node, apikey)
    local apiEntry = node and node.state and node.state.apis and node.state.apis.BLACKBOX_CONFIG or nil
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

local function wakeup(node)
    local buildCount = node and node.app and node.app.formBuildCount or 0
    local supported = tonumber(readBlackboxValue(node, "blackbox_supported")) or 0
    local device = tonumber(findField(node, "device") and findField(node, "device").value) or tonumber(readBlackboxValue(node, "device")) or 0
    local mode = tonumber(findField(node, "mode") and findField(node, "mode").value) or tonumber(readBlackboxValue(node, "mode")) or 0
    local signature = table.concat({
        tostring(buildCount),
        tostring(supported),
        tostring(device),
        tostring(mode)
    }, "|")

    if node.state.blackboxConfigSignature == signature then
        return
    end

    node.state.blackboxConfigSignature = signature

    setFieldEnabled(node, "device", supported == 1)
    setFieldEnabled(node, "mode", supported == 1)
    setFieldEnabled(node, "denom", supported == 1)
    setFieldEnabled(node, "initialEraseFreeSpaceKiB", supported == 1 and device == 1)
    setFieldEnabled(node, "rollingErase", supported == 1 and device == 1)
    setFieldEnabled(node, "gracePeriod", supported == 1 and device ~= 0 and (mode == 1 or mode == 2))
end

return MspPage.create({
    title = "@i18n(app.modules.blackbox.menu_configuration)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    keepApisLoaded = true,
    help = {
        "@i18n(app.modules.blackbox.help_p1)@",
        "@i18n(app.modules.blackbox.help_p2)@",
        "@i18n(app.modules.blackbox.help_p3)@"
    },
    api = {
        {name = "BLACKBOX_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {
                t = "@i18n(app.modules.blackbox.device)@",
                apikey = "device",
                type = 1,
                tableEthos = {
                    {"@i18n(app.modules.blackbox.device_disabled)@", 0},
                    {"@i18n(app.modules.blackbox.device_onboard_flash)@", 1},
                    {"@i18n(app.modules.blackbox.device_sdcard)@", 2},
                    {"@i18n(app.modules.blackbox.device_serial_port)@", 3}
                }
            },
            {
                t = "@i18n(app.modules.blackbox.logging_mode)@",
                apikey = "mode",
                type = 1,
                tableEthos = {
                    {"@i18n(app.modules.blackbox.mode_off)@", 0},
                    {"@i18n(app.modules.blackbox.mode_normal)@", 1},
                    {"@i18n(app.modules.blackbox.mode_armed)@", 2},
                    {"@i18n(app.modules.blackbox.mode_switch)@", 3}
                }
            },
            {t = "@i18n(app.modules.blackbox.logging_rate)@", apikey = "denom", min = 1, max = 1000},
            {t = "@i18n(app.modules.blackbox.disarm_grace_period)@", apikey = "gracePeriod", min = 0, max = 255, unit = "s"},
            {t = "@i18n(app.modules.blackbox.initial_erase)@", apikey = "initialEraseFreeSpaceKiB", min = 0, max = 65535, unit = "KiB"},
            {
                t = "@i18n(app.modules.blackbox.rolling_erase)@",
                apikey = "rollingErase",
                type = 1,
                tableEthos = {
                    {"@i18n(app.modules.blackbox.off)@", 0},
                    {"@i18n(app.modules.blackbox.on)@", 1}
                }
            }
        }
    },
    wakeup = wakeup
})
