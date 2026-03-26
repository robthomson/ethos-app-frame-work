--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local EscPage = assert(loadfile("app/modules/esc_tools/esc_page.lua"))()
local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()
local hw5Profile = assert(loadfile("app/modules/esc_tools/mfg/hw5/profile.lua"))()

local Page = {}

function Page:open(ctx)
    local details = escTools.getSessionValue(ctx.app, "esc_tools_hw5_details", nil)
    local layout = hw5Profile.pageLayout("basic", details)
    return EscPage.open(ctx, {
        title = "@i18n(app.modules.esc_tools.mfg.hw5.basic)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_tools.mfg.hw5.name)@",
        details = details,
        api = {
            {name = "ESC_PARAMETERS_HW5"}
        },
        loaderOnEnter = {
            watchdogTimeout = 10.0
        },
        loaderOnSave = {
            watchdogTimeout = 12.0
        },
        layout = {
            labels = layout.labels,
            fields = layout.fields
        }
    })
end

return Page
