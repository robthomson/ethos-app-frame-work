--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local power = ModuleLoader.requireOrLoad("app.modules.power.lib", "app/modules/power/lib.lua")

local function wakeup(node)
    local apiEntry = node and node.state and node.state.apis and node.state.apis.BATTERY_INI or nil
    local api = apiEntry and apiEntry.api or nil
    local alertType = tonumber(power.findField(node, "alert_type") and power.findField(node, "alert_type").value) or 0
    local calcLocal = tonumber(api and api.readValue and api.readValue("calc_local") or nil) or 0
    local buildCount = node and node.app and node.app.formBuildCount or 0

    power.applyWhenChanged(node, "powerAlertsUiSignature", table.concat({
        tostring(buildCount),
        tostring(alertType),
        tostring(calcLocal)
    }, "|"), function(activeNode)
        power.setFieldEnabled(activeNode, "sag_multiplier", calcLocal == 1)
        power.setFieldEnabled(activeNode, "becalertvalue", alertType == 1)
        power.setFieldEnabled(activeNode, "rxalertvalue", alertType == 2)
    end)
end

return MspPage.create({
    title = "@i18n(app.modules.power.alert_name)@",
    buildFormWhileLoading = true,
    eepromWrite = false,
    keepApisLoaded = true,
    help = {
        "@i18n(app.modules.power.help_p1)@"
    },
    api = {
        {name = "BATTERY_INI", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.power.timer)@", apikey = "flighttime"},
            {t = "@i18n(app.modules.power.voltage_multiplier)@", apikey = "sag_multiplier"},
            {t = "@i18n(app.modules.power.alert_type)@", apikey = "alert_type", type = 1},
            {t = "@i18n(app.modules.power.bec_voltage_alert)@", apikey = "becalertvalue"},
            {t = "@i18n(app.modules.power.rx_voltage_alert)@", apikey = "rxalertvalue"}
        }
    },
    wakeup = wakeup
})
