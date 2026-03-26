--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.governor.menu_time)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    reboot = true,
    help = {
        "@i18n(app.modules.governor.help_p2)@"
    },
    api = {
        {name = "GOVERNOR_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.governor.spoolup_time)@", apikey = "gov_spoolup_time"},
            {t = "@i18n(app.modules.governor.spooldown_time)@", apikey = "gov_spooldown_time"},
            {t = "@i18n(app.modules.governor.tracking_time)@", apikey = "gov_tracking_time"},
            {t = "@i18n(app.modules.governor.recovery_time)@", apikey = "gov_recovery_time"}
        }
    }
})
