--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_tailrotor.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_tailrotor.help_p1)@",
        "@i18n(app.modules.profile_tailrotor.help_p2)@",
        "@i18n(app.modules.profile_tailrotor.help_p3)@",
        "@i18n(app.modules.profile_tailrotor.help_p4)@",
        "@i18n(app.modules.profile_tailrotor.help_p5)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.profile_tailrotor.inertia_precomp)@", label = 2, inline_size = 13.6, apiversiongte = {12, 0, 8}},
            {t = "@i18n(app.modules.profile_tailrotor.collective_impulse_ff)@", label = 3, inline_size = 13.6, apiversionlte = {12, 0, 7}}
        },
        fields = {
            {t = "@i18n(app.modules.profile_tailrotor.precomp_cutoff)@", apikey = "yaw_precomp_cutoff"},
            {t = "@i18n(app.modules.profile_tailrotor.gain)@", inline = 2, label = 2, apikey = "yaw_inertia_precomp_gain", apiversiongte = {12, 0, 8}},
            {t = "@i18n(app.modules.profile_tailrotor.cutoff)@", inline = 1, label = 2, apikey = "yaw_inertia_precomp_cutoff", apiversiongte = {12, 0, 8}},
            {t = "@i18n(app.modules.profile_tailrotor.gain)@", inline = 2, label = 3, apikey = "yaw_collective_dynamic_gain", apiversionlte = {12, 0, 7}},
            {t = "@i18n(app.modules.profile_tailrotor.decay)@", inline = 1, label = 3, apikey = "yaw_collective_dynamic_decay", apiversionlte = {12, 0, 7}}
        }
    }
})
