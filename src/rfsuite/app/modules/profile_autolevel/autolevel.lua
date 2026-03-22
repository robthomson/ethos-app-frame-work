--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_autolevel.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_autolevel.help_p1)@",
        "@i18n(app.modules.profile_autolevel.help_p2)@",
        "@i18n(app.modules.profile_autolevel.help_p3)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        kind = "matrix",
        rowLabelWidth = "46%",
        rowLabelAlign = "left",
        columnAlign = "right",
        slotGap = "18px",
        rightPadding = "12px",
        rows = {
            {id = "acro", t = "@i18n(app.modules.profile_autolevel.acro_trainer)@"},
            {id = "angle", t = "@i18n(app.modules.profile_autolevel.angle_mode)@"},
            {id = "horizon", t = "@i18n(app.modules.profile_autolevel.horizon_mode)@"}
        },
        columns = {
            {id = "gain", t = "@i18n(app.modules.profile_autolevel.gain)@"},
            {id = "max", t = "@i18n(app.modules.profile_autolevel.max)@"}
        },
        fields = {
            {row = "acro", column = "gain", apikey = "trainer_gain"},
            {row = "acro", column = "max", apikey = "trainer_angle_limit"},
            {row = "angle", column = "gain", apikey = "angle_level_strength"},
            {row = "angle", column = "max", apikey = "angle_level_limit"},
            {row = "horizon", column = "gain", apikey = "horizon_level_strength"}
        }
    }
})
