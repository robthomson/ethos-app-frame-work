--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.power.preferences_name)@",
    buildFormWhileLoading = true,
    eepromWrite = false,
    help = {
        "@i18n(app.modules.power.help_p1)@"
    },
    api = {
        {name = "BATTERY_INI", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.power.model_type)@", apikey = "smartfuel_model_type", type = 1},
            {t = "@i18n(app.modules.power.calcfuel_local)@", apikey = "calc_local", type = 1}
        }
    }
})
