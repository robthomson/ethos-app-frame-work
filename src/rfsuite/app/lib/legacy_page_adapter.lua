--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local support = require("app.lib.legacy_support")

local adapter = {}

local function normalizeNavButtons(legacy)
    local buttons = type(legacy) == "table" and legacy.navButtons or {}

    return {
        menu = buttons.menu == true,
        save = buttons.save == true and type(legacy.onSaveMenu) == "function",
        reload = buttons.reload == true and type(legacy.onReloadMenu) == "function",
        tool = buttons.tool == true and type(legacy.onToolMenu) == "function",
        help = buttons.help == true and type(legacy.onHelpMenu) == "function"
    }
end

function adapter.open(ctx, legacyPath)
    local chunk
    local legacy
    local node

    support.setContext(ctx.app, nil)

    chunk = assert(loadfile(legacyPath))
    legacy = chunk()

    node = {
        title = ctx.item.title or legacy.title or "Page",
        subtitle = ctx.item.subtitle or "Page",
        breadcrumb = ctx.breadcrumb,
        navButtons = normalizeNavButtons(legacy),
        state = {
            opened = false
        }
    }

    local function withContext(app)
        support.setContext(app or ctx.app, node)
    end

    node.buildForm = function()
        withContext(ctx.app)
        if node.state.opened ~= true and type(legacy.openPage) == "function" then
            node.state.opened = true
            legacy.openPage({
                idx = 1,
                title = node.title,
                script = ctx.source
            })
        end
    end

    node.wakeup = function()
        withContext(ctx.app)
        if node.state.opened ~= true and type(legacy.openPage) == "function" then
            node.state.opened = true
            legacy.openPage({
                idx = 1,
                title = node.title,
                script = ctx.source
            })
        end
        if type(legacy.wakeup) == "function" then
            legacy.wakeup()
        end
    end

    node.save = function()
        withContext(ctx.app)
        if type(legacy.onSaveMenu) == "function" then
            return legacy.onSaveMenu()
        end
        return false
    end

    node.reload = function()
        withContext(ctx.app)
        if type(legacy.onReloadMenu) == "function" then
            return legacy.onReloadMenu()
        end
        return false
    end

    node.menu = function()
        withContext(ctx.app)
        if type(legacy.onNavMenu) == "function" then
            return legacy.onNavMenu()
        end
        return ctx.app and ctx.app._handleMenuAction and ctx.app:_handleMenuAction() or false
    end

    node.tool = function()
        withContext(ctx.app)
        if type(legacy.onToolMenu) == "function" then
            return legacy.onToolMenu()
        end
        return false
    end

    node.help = function()
        withContext(ctx.app)
        if type(legacy.onHelpMenu) == "function" then
            return legacy.onHelpMenu()
        end
        return false
    end

    node.event = function(_, _, category, value, x, y)
        withContext(ctx.app)
        if type(legacy.event) == "function" then
            return legacy.event(nil, category, value, x, y)
        end
        return false
    end

    node.close = function()
        withContext(ctx.app)
        if type(legacy.close) == "function" then
            legacy.close()
        end
    end

    return node
end

return adapter
