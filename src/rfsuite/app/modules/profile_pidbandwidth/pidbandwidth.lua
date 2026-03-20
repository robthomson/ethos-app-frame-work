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
    title = "@i18n(app.modules.profile_pidbandwidth.name)@",
    titleProfileSuffix = "pid",
    refreshOnProfileChange = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.profile_pidbandwidth.help_p1)@",
        "@i18n(app.modules.profile_pidbandwidth.help_p2)@",
        "@i18n(app.modules.profile_pidbandwidth.help_p3)@"
    },
    api = {
        {name = "PID_PROFILE", rebuildOnWrite = true}
    },
    layout = {
        kind = "rows",
        rows = {
            {
                t = "@i18n(app.modules.profile_pidbandwidth.name)@",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "@i18n(app.modules.profile_pidbandwidth.roll)@", apikey = "gyro_cutoff_0", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.pitch)@", apikey = "gyro_cutoff_1", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.yaw)@", apikey = "gyro_cutoff_2", fieldWidth = "80px"}
                }
            },
            {
                t = "@i18n(app.modules.profile_pidbandwidth.dterm_cutoff)@",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "@i18n(app.modules.profile_pidbandwidth.roll)@", apikey = "dterm_cutoff_0", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.pitch)@", apikey = "dterm_cutoff_1", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.yaw)@", apikey = "dterm_cutoff_2", fieldWidth = "80px"}
                }
            },
            {
                t = "@i18n(app.modules.profile_pidbandwidth.bterm_cutoff)@",
                labelWidth = "28%",
                slotGap = 14,
                cells = {
                    {t = "@i18n(app.modules.profile_pidbandwidth.roll)@", apikey = "bterm_cutoff_0", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.pitch)@", apikey = "bterm_cutoff_1", fieldWidth = "80px"},
                    {t = "@i18n(app.modules.profile_pidbandwidth.yaw)@", apikey = "bterm_cutoff_2", fieldWidth = "80px"}
                }
            }
        }
    }
})
