--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()

local SESSION_ACTIVE_FIELDS = "esc_tools_ztw_active_fields"
local SESSION_DETAILS = "esc_tools_ztw_details"

local FIELDS = {
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.gov)@", activeFieldPos = 2, type = 1, apikey = "governor"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.gov_p)@", activeFieldPos = 6, apikey = "gov_p"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.gov_i)@", activeFieldPos = 7, apikey = "gov_i"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.motor_poles)@", activeFieldPos = 17, apikey = "motor_poles"}
}

local function copyVisibleFields(activeFields)
    local out = {}
    local index
    local field
    local visible

    for index = 1, #FIELDS do
        field = FIELDS[index]
        visible = activeFields == nil or activeFields[field.activeFieldPos] ~= 0
        if visible then
            out[#out + 1] = {
                t = field.t,
                apikey = field.apikey,
                type = field.type
            }
        end
    end

    return out
end

local Page = {}

function Page:open(ctx)
    local activeFields = escTools.getSessionValue(ctx.app, SESSION_ACTIVE_FIELDS, nil)
    local details = escTools.getSessionValue(ctx.app, SESSION_DETAILS, nil)
    local page = MspPage.create({
        title = "@i18n(app.modules.esc_tools.mfg.ztw.governor)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_tools.mfg.ztw.name)@",
        eepromWrite = true,
        api = {
            {name = "ESC_PARAMETERS_ZTW", rebuildOnWrite = true}
        },
        loaderOnEnter = {
            watchdogTimeout = 10.0
        },
        loaderOnSave = {
            watchdogTimeout = 12.0
        },
        layout = {
            fields = copyVisibleFields(activeFields)
        }
    })

    return escTools.decorateHeaderLine(page:open(ctx), escTools.formatDetails(details))
end

return Page
