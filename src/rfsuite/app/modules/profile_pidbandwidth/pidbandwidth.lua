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
        kind = "rows",
        rows = {
            {
                t = "Gyro Cutoff",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "Roll", apikey = "gyro_cutoff_0", fieldWidth = "80px"},
                    {t = "Pitch", apikey = "gyro_cutoff_1", fieldWidth = "80px"},
                    {t = "Yaw", apikey = "gyro_cutoff_2", fieldWidth = "80px"}
                }
            },
            {
                t = "D-Term Cutoff",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "Roll", apikey = "dterm_cutoff_0", fieldWidth = "80px"},
                    {t = "Pitch", apikey = "dterm_cutoff_1", fieldWidth = "80px"},
                    {t = "Yaw", apikey = "dterm_cutoff_2", fieldWidth = "80px"}
                }
            },
            {
                t = "B-Term Cutoff",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "Roll", apikey = "bterm_cutoff_0", fieldWidth = "80px"},
                    {t = "Pitch", apikey = "bterm_cutoff_1", fieldWidth = "80px"},
                    {t = "Yaw", apikey = "bterm_cutoff_2", fieldWidth = "80px"}
                }
            }
        }
    }
})
