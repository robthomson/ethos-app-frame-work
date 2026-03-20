--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local function loadMspPage()
    local ok, mod = pcall(require, "app.lib.msp_page")
    local chunk

    if ok and type(mod) == "table" then
        return mod
    end

    chunk = assert(loadfile("app/lib/msp_page.lua"))
    return assert(chunk())
end

local MspPage = loadMspPage()

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
        kind = "rows",
        rows = {
            {
                t = "@i18n(app.modules.profile_autolevel.acro_trainer)@",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "@i18n(app.modules.profile_autolevel.gain)@", apikey = "trainer_gain"},
                    {t = "@i18n(app.modules.profile_autolevel.max)@", apikey = "trainer_angle_limit"}
                }
            },
            {
                t = "@i18n(app.modules.profile_autolevel.angle_mode)@",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "@i18n(app.modules.profile_autolevel.gain)@", apikey = "angle_level_strength"},
                    {t = "@i18n(app.modules.profile_autolevel.max)@", apikey = "angle_level_limit"}
                }
            },
            {
                t = "@i18n(app.modules.profile_autolevel.horizon_mode)@",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "@i18n(app.modules.profile_autolevel.gain)@", apikey = "horizon_level_strength", width = "34%"}
                }
            }
        }
    }
})
