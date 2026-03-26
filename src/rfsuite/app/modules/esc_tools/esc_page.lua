--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()

local EscPage = {}

function EscPage.open(ctx, spec)
    local pageSpec = spec or {}
    local node = MspPage.create({
        title = pageSpec.title or ctx.item.title or "@i18n(app.modules.esc_tools.name)@",
        subtitle = pageSpec.subtitle or ctx.item.subtitle or "@i18n(app.modules.esc_tools.name)@",
        api = pageSpec.api or {},
        layout = pageSpec.layout or {},
        help = pageSpec.help,
        eepromWrite = pageSpec.eepromWrite ~= false,
        keepApisLoaded = pageSpec.keepApisLoaded,
        buildFormWhileLoading = pageSpec.buildFormWhileLoading,
        controlStateSync = pageSpec.controlStateSync,
        navButtons = pageSpec.navButtons,
        loaderOnEnter = pageSpec.loaderOnEnter or {
            watchdogTimeout = 10.0
        },
        loaderOnSave = pageSpec.loaderOnSave or {
            watchdogTimeout = 12.0
        }
    }):open(ctx)

    return escTools.decorateHeaderLine(node, escTools.formatDetails(pageSpec.details))
end

return EscPage
