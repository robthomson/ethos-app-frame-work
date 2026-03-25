--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.rates_advanced.advanced)@",
    titleProfileSuffix = "rate",
    refreshOnRateChange = true,
    eepromWrite = true,
    api = {
        {name = "RC_TUNING", rebuildOnWrite = true}
    },
    layout = {
        kind = "matrix",
        rowLabelWidth = "31%",
        rowLabelAlign = "left",
        columnAlign = "right",
        columnPack = "right",
        columnWidth = "86px",
        fieldWidth = "80px",
        slotGap = "8px",
        rightPadding = "8px",
        rows = {
            {id = "response_time", t = "@i18n(app.modules.rates_advanced.response_time)@"},
            {id = "acc_limit", t = "@i18n(app.modules.rates_advanced.acc_limit)@"},
            {id = "setpoint_boost_gain", t = "@i18n(app.modules.rates_advanced.setpoint_boost_gain)@", apiversiongte = {12, 0, 8}},
            {id = "setpoint_boost_cutoff", t = "@i18n(app.modules.rates_advanced.setpoint_boost_cutoff)@", apiversiongte = {12, 0, 8}},
            {id = "dyn_ceiling_gain", t = "@i18n(app.modules.rates_advanced.dyn_ceiling_gain)@", apiversiongte = {12, 0, 8}},
            {id = "dyn_deadband_gain", t = "@i18n(app.modules.rates_advanced.dyn_deadband_gain)@", apiversiongte = {12, 0, 8}},
            {id = "dyn_deadband_filter", t = "@i18n(app.modules.rates_advanced.dyn_deadband_filter)@", apiversiongte = {12, 0, 8}}
        },
        columns = {
            {id = "roll", t = "@i18n(app.modules.rates_advanced.roll)@"},
            {id = "pitch", t = "@i18n(app.modules.rates_advanced.pitch)@"},
            {id = "yaw", t = "@i18n(app.modules.rates_advanced.yaw)@"},
            {id = "collective", t = "@i18n(app.modules.rates_advanced.col)@"}
        },
        fields = {
            {row = "response_time", column = "roll", apikey = "response_time_1"},
            {row = "response_time", column = "pitch", apikey = "response_time_2"},
            {row = "response_time", column = "yaw", apikey = "response_time_3"},
            {row = "response_time", column = "collective", apikey = "response_time_4"},

            {row = "acc_limit", column = "roll", apikey = "accel_limit_1"},
            {row = "acc_limit", column = "pitch", apikey = "accel_limit_2"},
            {row = "acc_limit", column = "yaw", apikey = "accel_limit_3"},
            {row = "acc_limit", column = "collective", apikey = "accel_limit_4"},

            {row = "setpoint_boost_gain", column = "roll", apikey = "setpoint_boost_gain_1", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_gain", column = "pitch", apikey = "setpoint_boost_gain_2", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_gain", column = "yaw", apikey = "setpoint_boost_gain_3", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_gain", column = "collective", apikey = "setpoint_boost_gain_4", apiversiongte = {12, 0, 8}},

            {row = "setpoint_boost_cutoff", column = "roll", apikey = "setpoint_boost_cutoff_1", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_cutoff", column = "pitch", apikey = "setpoint_boost_cutoff_2", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_cutoff", column = "yaw", apikey = "setpoint_boost_cutoff_3", apiversiongte = {12, 0, 8}},
            {row = "setpoint_boost_cutoff", column = "collective", apikey = "setpoint_boost_cutoff_4", apiversiongte = {12, 0, 8}},

            {row = "dyn_ceiling_gain", column = "yaw", apikey = "yaw_dynamic_ceiling_gain", apiversiongte = {12, 0, 8}},
            {row = "dyn_deadband_gain", column = "yaw", apikey = "yaw_dynamic_deadband_gain", apiversiongte = {12, 0, 8}},
            {row = "dyn_deadband_filter", column = "yaw", apikey = "yaw_dynamic_deadband_filter", apiversiongte = {12, 0, 8}}
        }
    }
})
