--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()

local SESSION_ACTIVE_FIELDS = "esc_tools_xdfly_active_fields"
local SESSION_DETAILS = "esc_tools_xdfly_details"

local FIELDS = {
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.timing)@", activeFieldPos = 4, type = 1, apikey = "timing"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.acceleration)@", activeFieldPos = 9, type = 1, apikey = "acceleration"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.brake_force)@", activeFieldPos = 14, apikey = "brake_force"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.sr_function)@", activeFieldPos = 15, type = 1, apikey = "sr_function"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.capacity_correction)@", activeFieldPos = 16, apikey = "capacity_correction"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.auto_restart_time)@", activeFieldPos = 10, type = 1, apikey = "auto_restart_time"},
    {t = "@i18n(app.modules.esc_tools.mfg.xdfly.cell_cutoff)@", activeFieldPos = 11, type = 1, apikey = "cell_cutoff"}
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
        title = "@i18n(app.modules.esc_tools.mfg.xdfly.advanced)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_tools.mfg.xdfly.name)@",
        eepromWrite = true,
        api = {
            {name = "ESC_PARAMETERS_XDFLY", rebuildOnWrite = true}
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
