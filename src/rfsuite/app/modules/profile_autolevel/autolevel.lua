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
    eepromWrite = true,
    help = {
        "Autolevel profile settings from PID profile data.",
        "This page is a lightweight MSP-backed port used to validate the new page wrapper."
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "Acro Trainer", inline_size = 13.6, label = 1},
            {t = "Angle Mode", inline_size = 13.6, label = 2},
            {t = "Horizon Mode", inline_size = 13.6, label = 3}
        },
        fields = {
            {t = "Gain", inline = 2, label = 1, apikey = "trainer_gain"},
            {t = "Max", inline = 1, label = 1, apikey = "trainer_angle_limit"},
            {t = "Gain", inline = 2, label = 2, apikey = "angle_level_strength"},
            {t = "Max", inline = 1, label = 2, apikey = "angle_level_limit"},
            {t = "Gain", inline = 2, label = 3, apikey = "horizon_level_strength"}
        }
    }
})
