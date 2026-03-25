--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_mainrotor.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_mainrotor.help_p1)@",
        "@i18n(app.modules.profile_mainrotor.help_p2)@",
        "@i18n(app.modules.profile_mainrotor.help_p3)@",
        "@i18n(app.modules.profile_mainrotor.help_p4)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.profile_mainrotor.collective_pitch_comp)@", label = 1, inline_size = 40.15},
            {t = "@i18n(app.modules.profile_mainrotor.cyclic_cross_coupling)@", label = 2, inline_size = 40.15},
            {t = "", label = 3, inline_size = 40.15},
            {t = "", label = 4, inline_size = 40.15}
        },
        fields = {
            {t = "", inline = 1, label = 1, apikey = "pitch_collective_ff_gain"},
            {t = "@i18n(app.modules.profile_mainrotor.gain)@", inline = 1, label = 2, apikey = "cyclic_cross_coupling_gain"},
            {t = "@i18n(app.modules.profile_mainrotor.ratio)@", inline = 1, label = 3, apikey = "cyclic_cross_coupling_ratio"},
            {t = "@i18n(app.modules.profile_mainrotor.cutoff)@", inline = 1, label = 4, apikey = "cyclic_cross_coupling_cutoff"}
        }
    }
})
