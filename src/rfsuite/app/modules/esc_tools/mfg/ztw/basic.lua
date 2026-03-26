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
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.lv_bec_voltage)@", activeFieldPos = 5, type = 1, apikey = "lv_bec_voltage"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.hv_bec_voltage)@", activeFieldPos = 11, type = 1, apikey = "hv_bec_voltage"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.motor_direction)@", activeFieldPos = 6, type = 1, apikey = "motor_direction"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.startup_power)@", activeFieldPos = 12, type = 1, apikey = "startup_power"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.led_color)@", activeFieldPos = 18, type = 1, apikey = "led_color"},
    {t = "@i18n(app.modules.esc_tools.mfg.ztw.smart_fan)@", activeFieldPos = 19, type = 1, apikey = "smart_fan"}
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
        title = "@i18n(app.modules.esc_tools.mfg.ztw.basic)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_tools.mfg.ztw.name)@",
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
