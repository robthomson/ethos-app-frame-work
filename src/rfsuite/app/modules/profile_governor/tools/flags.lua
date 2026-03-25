--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local governor = ModuleLoader.requireOrLoad("app.modules.profile_governor.lib", "app/modules/profile_governor/lib.lua")

local BasePage = MspPage.create({
    title = "@i18n(app.modules.governor.menu_flags)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    api = {
        {name = "GOVERNOR_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.profile_governor.fallback_precomp)@", apikey = "governor_flags->fallback_precomp", type = 1, apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.pid_spoolup)@", apikey = "governor_flags->pid_spoolup", type = 1, apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.voltage_comp)@", apikey = "governor_flags->voltage_comp", type = 1, apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.dyn_min_throttle)@", apikey = "governor_flags->dyn_min_throttle", type = 1, apiversiongte = {12, 0, 9}}
        }
    }
})

return governor.wrapPage(BasePage, governor.applyFlagsState)
