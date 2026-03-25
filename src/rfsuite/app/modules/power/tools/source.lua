--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.power.source_name)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.power.help_p1)@"
    },
    api = {
        {name = "BATTERY_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.power.voltage_meter_source)@", apikey = "voltageMeterSource", type = 1},
            {t = "@i18n(app.modules.power.current_meter_source)@", apikey = "currentMeterSource", type = 1}
        }
    }
})
