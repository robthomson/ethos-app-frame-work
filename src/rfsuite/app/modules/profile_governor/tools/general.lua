--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local governor = ModuleLoader.requireOrLoad("app.modules.profile_governor.lib", "app/modules/profile_governor/lib.lua")

local BasePage = MspPage.create({
    title = "@i18n(app.modules.governor.menu_general)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_governor.help_p1)@",
        "@i18n(app.modules.profile_governor.help_p2)@",
        "@i18n(app.modules.profile_governor.help_p3)@",
        "@i18n(app.modules.profile_governor.help_p4)@",
        "@i18n(app.modules.profile_governor.help_p5)@",
        "@i18n(app.modules.profile_governor.help_p6)@"
    },
    api = {
        {name = "GOVERNOR_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.profile_governor.gains)@", label = 1, inline_size = 8.15},
            {t = "@i18n(app.modules.profile_governor.precomp)@", label = 2, inline_size = 8.15}
        },
        fields = {
            {t = "@i18n(app.modules.profile_governor.full_headspeed)@", apikey = "governor_headspeed"},
            {t = "@i18n(app.modules.profile_governor.min_throttle)@", apikey = "governor_min_throttle"},
            {t = "@i18n(app.modules.profile_governor.max_throttle)@", apikey = "governor_max_throttle"},
            {t = "@i18n(app.modules.profile_governor.fallback_drop)@", apikey = "governor_fallback_drop"},
            {t = "@i18n(app.modules.profile_governor.gain)@", apikey = "governor_gain"},
            {t = "@i18n(app.modules.profile_governor.p)@", inline = 4, label = 1, apikey = "governor_p_gain"},
            {t = "@i18n(app.modules.profile_governor.i)@", inline = 3, label = 1, apikey = "governor_i_gain"},
            {t = "@i18n(app.modules.profile_governor.d)@", inline = 2, label = 1, apikey = "governor_d_gain"},
            {t = "@i18n(app.modules.profile_governor.f)@", inline = 1, label = 1, apikey = "governor_f_gain"},
            {t = "@i18n(app.modules.profile_governor.yaw)@", inline = 3, label = 2, apikey = "governor_yaw_weight", apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.cyc)@", inline = 2, label = 2, apikey = "governor_cyclic_weight", apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.col)@", inline = 1, label = 2, apikey = "governor_collective_weight", apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.profile_governor.yaw)@", inline = 3, label = 2, apikey = "governor_yaw_ff_weight", apiversionlte = {12, 0, 6}},
            {t = "@i18n(app.modules.profile_governor.cyc)@", inline = 2, label = 2, apikey = "governor_cyclic_ff_weight", apiversionlte = {12, 0, 6}},
            {t = "@i18n(app.modules.profile_governor.col)@", inline = 1, label = 2, apikey = "governor_collective_ff_weight", apiversionlte = {12, 0, 6}}
        }
    }
})

return governor.wrapPage(BasePage, governor.applyGeneralState)
