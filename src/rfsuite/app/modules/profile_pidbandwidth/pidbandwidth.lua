--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.profile_pidbandwidth.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_pidbandwidth.help_p1)@",
        "@i18n(app.modules.profile_pidbandwidth.help_p2)@",
        "@i18n(app.modules.profile_pidbandwidth.help_p3)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        kind = "matrix",
        rowLabelWidth = "28%",
        rowLabelAlign = "left",
        columnAlign = "right",
        columnWidth = "112px",
        columnPack = "right",
        fieldWidth = "120px",
        slotGap = "12px",
        rightPadding = "12px",
        rows = {
            {id = "gyro", t = "@i18n(app.modules.profile_pidbandwidth.name)@"},
            {id = "dterm", t = "@i18n(app.modules.profile_pidbandwidth.dterm_cutoff)@"},
            {id = "bterm", t = "@i18n(app.modules.profile_pidbandwidth.bterm_cutoff)@"}
        },
        columns = {
            {id = "roll", t = "@i18n(app.modules.profile_pidbandwidth.roll_full)@"},
            {id = "pitch", t = "@i18n(app.modules.profile_pidbandwidth.pitch_full)@"},
            {id = "yaw", t = "@i18n(app.modules.profile_pidbandwidth.yaw_full)@"}
        },
        fields = {
            {row = "gyro", column = "roll", apikey = "gyro_cutoff_0"},
            {row = "gyro", column = "pitch", apikey = "gyro_cutoff_1"},
            {row = "gyro", column = "yaw", apikey = "gyro_cutoff_2"},
            {row = "dterm", column = "roll", apikey = "dterm_cutoff_0"},
            {row = "dterm", column = "pitch", apikey = "dterm_cutoff_1"},
            {row = "dterm", column = "yaw", apikey = "dterm_cutoff_2"},
            {row = "bterm", column = "roll", apikey = "bterm_cutoff_0"},
            {row = "bterm", column = "pitch", apikey = "bterm_cutoff_1"},
            {row = "bterm", column = "yaw", apikey = "bterm_cutoff_2"}
        }
    }
})
