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
        "PID bandwidth settings from the active PID profile.",
        "This page exercises the wrapper with a compact inline grid layout."
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        labels = {
            {t = "Gyro Cutoff", inline_size = 8.15, label = 1},
            {t = "D-Term Cutoff", inline_size = 8.15, label = 2},
            {t = "B-Term Cutoff", inline_size = 8.15, label = 3}
        },
        fields = {
            {t = "Roll", inline = 3, label = 1, apikey = "gyro_cutoff_0"},
            {t = "Pitch", inline = 2, label = 1, apikey = "gyro_cutoff_1"},
            {t = "Yaw", inline = 1, label = 1, apikey = "gyro_cutoff_2"},
            {t = "Roll", inline = 3, label = 2, apikey = "dterm_cutoff_0"},
            {t = "Pitch", inline = 2, label = 2, apikey = "dterm_cutoff_1"},
            {t = "Yaw", inline = 1, label = 2, apikey = "dterm_cutoff_2"},
            {t = "Roll", inline = 3, label = 3, apikey = "bterm_cutoff_0"},
            {t = "Pitch", inline = 2, label = 3, apikey = "bterm_cutoff_1"},
            {t = "Yaw", inline = 1, label = 3, apikey = "bterm_cutoff_2"}
        }
    }
})
