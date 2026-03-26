--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local governor = ModuleLoader.requireOrLoad("app.modules.governor.lib", "app/modules/governor/lib.lua")

return MspPage.create({
    title = "@i18n(app.modules.governor.menu_general)@",
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
            {t = "@i18n(app.modules.governor.mode)@", apikey = "gov_mode", type = 1},
            {t = "@i18n(app.modules.governor.throttle_type)@", apikey = "gov_throttle_type", type = 1},
            {t = "@i18n(app.modules.profile_governor.idle_throttle)@", apikey = "governor_idle_throttle"},
            {t = "@i18n(app.modules.profile_governor.auto_throttle)@", apikey = "governor_auto_throttle"},
            {t = "@i18n(app.modules.governor.handover_throttle)@", apikey = "gov_handover_throttle"},
            {t = "@i18n(app.modules.governor.throttle_hold_timeout)@", apikey = "gov_throttle_hold_timeout"},
            {t = "@i18n(app.modules.governor.auto_timeout)@", apikey = "gov_autorotation_timeout"}
        }
    },
    wakeup = governor.applyGeneralState
})
