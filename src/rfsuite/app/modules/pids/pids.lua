--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.pids.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.pids.help_p1)@",
        "@i18n(app.modules.pids.help_p2)@",
        "@i18n(app.modules.pids.help_p3)@",
        "@i18n(app.modules.pids.help_p4)@"
    },
    api = {
        {name = "PID_TUNING", rebuildOnWrite = true}
    },
    layout = {
        kind = "matrix",
        rowLabelWidth = "18%",
        rowLabelAlign = "left",
        columnAlign = "right",
        columnWidth = "86px",
        columnPack = "right",
        fieldWidth = "78px",
        slotGap = "8px",
        rightPadding = "12px",
        rows = {
            {id = "roll", t = "@i18n(app.modules.pids.roll)@"},
            {id = "pitch", t = "@i18n(app.modules.pids.pitch)@"},
            {id = "yaw", t = "@i18n(app.modules.pids.yaw)@"}
        },
        columns = {
            {id = "p", t = "@i18n(app.modules.pids.p)@"},
            {id = "i", t = "@i18n(app.modules.pids.i)@"},
            {id = "d", t = "@i18n(app.modules.pids.d)@"},
            {id = "f", t = "@i18n(app.modules.pids.f)@"},
            {id = "o", t = "@i18n(app.modules.pids.o)@"},
            {id = "b", t = "@i18n(app.modules.pids.b)@"}
        },
        fields = {
            {row = "roll", column = "p", apikey = "pid_0_P"},
            {row = "pitch", column = "p", apikey = "pid_1_P"},
            {row = "yaw", column = "p", apikey = "pid_2_P"},

            {row = "roll", column = "i", apikey = "pid_0_I"},
            {row = "pitch", column = "i", apikey = "pid_1_I"},
            {row = "yaw", column = "i", apikey = "pid_2_I"},

            {row = "roll", column = "d", apikey = "pid_0_D"},
            {row = "pitch", column = "d", apikey = "pid_1_D"},
            {row = "yaw", column = "d", apikey = "pid_2_D"},

            {row = "roll", column = "f", apikey = "pid_0_F"},
            {row = "pitch", column = "f", apikey = "pid_1_F"},
            {row = "yaw", column = "f", apikey = "pid_2_F"},

            {row = "roll", column = "o", apikey = "pid_0_O"},
            {row = "pitch", column = "o", apikey = "pid_1_O"},

            {row = "roll", column = "b", apikey = "pid_0_B"},
            {row = "pitch", column = "b", apikey = "pid_1_B"},
            {row = "yaw", column = "b", apikey = "pid_2_B"}
        }
    }
})
