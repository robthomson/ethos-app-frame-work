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
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "Autolevel profile settings from PID profile data.",
        "This page is a lightweight MSP-backed port used to validate the new page wrapper."
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        kind = "rows",
        rows = {
            {
                t = "Acro Trainer",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "Gain", apikey = "trainer_gain"},
                    {t = "Max", apikey = "trainer_angle_limit"}
                }
            },
            {
                t = "Angle Mode",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "Gain", apikey = "angle_level_strength"},
                    {t = "Max", apikey = "angle_level_limit"}
                }
            },
            {
                t = "Horizon Mode",
                labelWidth = "46%",
                slotGap = 18,
                cells = {
                    {t = "Gain", apikey = "horizon_level_strength", width = "34%"}
                }
            }
        }
    }
})
