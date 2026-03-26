--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.governor.menu_filters)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    reboot = true,
    help = {
        "@i18n(app.modules.governor.help_p1)@"
    },
    api = {
        {name = "GOVERNOR_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.governor.gov_rpm_filter)@", apikey = "gov_rpm_filter"},
            {t = "@i18n(app.modules.governor.gov_pwr_filter)@", apikey = "gov_pwr_filter"},
            {t = "@i18n(app.modules.governor.gov_tta_filter)@", apikey = "gov_tta_filter"},
            {t = "@i18n(app.modules.governor.gov_ff_filter)@", apikey = "gov_ff_filter"},
            {t = "@i18n(app.modules.governor.gov_d_filter)@", apikey = "gov_d_filter"}
        }
    }
})
