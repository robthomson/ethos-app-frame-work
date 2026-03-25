--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_pidcontroller.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_pidcontroller.help_p1)@",
        "@i18n(app.modules.profile_pidcontroller.help_p2)@",
        "@i18n(app.modules.profile_pidcontroller.help_p3)@",
        "@i18n(app.modules.profile_pidcontroller.help_p4)@",
        "@i18n(app.modules.profile_pidcontroller.help_p5)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.profile_pidcontroller.inflight_error_decay)@", label = 2, inline_size = 13.6},
            {t = "@i18n(app.modules.profile_pidcontroller.error_limit)@", label = 4, inline_size = 8.15},
            {t = "@i18n(app.modules.profile_pidcontroller.hsi_offset_limit)@", label = 5, inline_size = 8.15},
            {t = "@i18n(app.modules.profile_pidcontroller.iterm_relax)@", label = 6, inline_size = 40.15},
            {t = "@i18n(app.modules.profile_pidcontroller.cutoff_point)@", label = 15, inline_size = 8.15}
        },
        fields = {
            {t = "@i18n(app.modules.profile_pidcontroller.ground_error_decay)@", apikey = "error_decay_time_ground"},
            {t = "@i18n(app.modules.profile_pidcontroller.time)@", inline = 2, label = 2, apikey = "error_decay_time_cyclic"},
            {t = "@i18n(app.modules.profile_pidcontroller.limit)@", inline = 1, label = 2, apikey = "error_decay_limit_cyclic"},

            {t = "@i18n(app.modules.profile_pidcontroller.roll)@", inline = 3, label = 4, apikey = "error_limit_0"},
            {t = "@i18n(app.modules.profile_pidcontroller.pitch)@", inline = 2, label = 4, apikey = "error_limit_1"},
            {t = "@i18n(app.modules.profile_pidcontroller.yaw)@", inline = 1, label = 4, apikey = "error_limit_2"},

            {t = "@i18n(app.modules.profile_pidcontroller.roll)@", inline = 3, label = 5, apikey = "offset_limit_0"},
            {t = "@i18n(app.modules.profile_pidcontroller.pitch)@", inline = 2, label = 5, apikey = "offset_limit_1"},

            {t = "@i18n(app.modules.profile_pidcontroller.error_rotation)@", apikey = "error_rotation", type = 1, apiversionlte = {12, 0, 8}},
            {t = "", inline = 1, label = 6, apikey = "iterm_relax_type", type = 1},

            {t = "@i18n(app.modules.profile_pidcontroller.roll)@", inline = 3, label = 15, apikey = "iterm_relax_cutoff_0"},
            {t = "@i18n(app.modules.profile_pidcontroller.pitch)@", inline = 2, label = 15, apikey = "iterm_relax_cutoff_1"},
            {t = "@i18n(app.modules.profile_pidcontroller.yaw)@", inline = 1, label = 15, apikey = "iterm_relax_cutoff_2"}
        }
    }
})
