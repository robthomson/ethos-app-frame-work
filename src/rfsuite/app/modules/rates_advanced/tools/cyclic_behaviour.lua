--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

return MspPage.create({
    title = "@i18n(app.modules.rates_advanced.cyclic_behaviour)@",
    titleProfileSuffix = "rate",
    refreshOnRateChange = true,
    eepromWrite = true,
    api = {
        {name = "RC_TUNING", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.rates_advanced.cyclic_polarity)@", apikey = "cyclic_polarity", type = "choice", apiversiongte = {12, 0, 9}},
            {t = "@i18n(app.modules.rates_advanced.cyclic_ring)@", apikey = "cyclic_ring", apiversiongte = {12, 0, 9}}
        }
    }
})
