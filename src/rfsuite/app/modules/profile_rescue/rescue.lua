--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_rescue.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_rescue.help_p1)@",
        "@i18n(app.modules.profile_rescue.help_p2)@",
        "@i18n(app.modules.profile_rescue.help_p3)@",
        "@i18n(app.modules.profile_rescue.help_p4)@",
        "@i18n(app.modules.profile_rescue.help_p5)@",
        "@i18n(app.modules.profile_rescue.help_p6)@",
        "@i18n(app.modules.profile_rescue.help_p7)@"
    },
    api = {
        {name = "RESCUE_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "@i18n(app.modules.profile_rescue.pull_up)@", label = 1, inline_size = 13.6},
            {t = "@i18n(app.modules.profile_rescue.climb)@", label = 2, inline_size = 13.6},
            {t = "@i18n(app.modules.profile_rescue.hover)@", label = 3, inline_size = 13.6},
            {t = "@i18n(app.modules.profile_rescue.flip)@", label = 4, inline_size = 13.6},
            {t = "@i18n(app.modules.profile_rescue.gains)@", label = 5, inline_size = 13.6},
            {t = "", label = 6, inline_size = 40.15},
            {t = "", label = 7, inline_size = 40.15}
        },
        fields = {
            {t = "@i18n(app.modules.profile_rescue.mode_enable)@", inline = 1, type = 1, apikey = "rescue_mode"},
            {t = "@i18n(app.modules.profile_rescue.flip_upright)@", inline = 1, type = 1, apikey = "rescue_flip_mode"},
            {t = "@i18n(app.modules.profile_rescue.collective)@", inline = 2, label = 1, apikey = "rescue_pull_up_collective"},
            {t = "@i18n(app.modules.profile_rescue.time)@", inline = 1, label = 1, apikey = "rescue_pull_up_time"},
            {t = "@i18n(app.modules.profile_rescue.collective)@", inline = 2, label = 2, apikey = "rescue_climb_collective"},
            {t = "@i18n(app.modules.profile_rescue.time)@", inline = 1, label = 2, apikey = "rescue_climb_time"},
            {t = "@i18n(app.modules.profile_rescue.collective)@", inline = 2, label = 3, apikey = "rescue_hover_collective"},
            {t = "@i18n(app.modules.profile_rescue.fail_time)@", inline = 2, label = 4, apikey = "rescue_flip_time"},
            {t = "@i18n(app.modules.profile_rescue.exit_time)@", inline = 1, label = 4, apikey = "rescue_exit_time"},
            {t = "@i18n(app.modules.profile_rescue.level_gain)@", inline = 2, label = 5, apikey = "rescue_level_gain"},
            {t = "@i18n(app.modules.profile_rescue.flip)@", inline = 1, label = 5, apikey = "rescue_flip_gain"},
            {t = "@i18n(app.modules.profile_rescue.rate)@", inline = 1, label = 6, apikey = "rescue_max_setpoint_rate"},
            {t = "@i18n(app.modules.profile_rescue.accel)@", inline = 1, label = 7, apikey = "rescue_max_setpoint_accel"}
        }
    }
})
