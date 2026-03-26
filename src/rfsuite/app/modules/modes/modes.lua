--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local diagnostics = ModuleLoader.requireOrLoad("app.modules.diagnostics.lib", "app/modules/diagnostics/lib.lua")

local Page = {}

local function loadChunk(path)
    return assert(loadfile(path))()
end

local function loadHelpLines()
    local ok, data = pcall(loadChunk, "app/modules/modes/help.lua")

    if ok ~= true or type(data) ~= "table" then
        return nil
    end

    return data.help and data.help.default or nil
end

function Page:open(ctx)
    local legacy = loadChunk("app/modules/modes/legacy.lua")
    local helpLines = loadHelpLines()
    local node = {
        baseTitle = ctx.item.title or legacy.title or "@i18n(app.modules.modes.name)@",
        title = ctx.item.title or legacy.title or "@i18n(app.modules.modes.name)@",
        subtitle = ctx.item.subtitle or "Mode ranges",
        breadcrumb = ctx.breadcrumb,
        disableSaveUntilDirty = false,
        navButtons = {
            menu = true,
            save = type(legacy.onSaveMenu) == "function",
            reload = type(legacy.onReloadMenu) == "function",
            tool = type(legacy.onToolMenu) == "function",
            help = type(helpLines) == "table" or type(legacy.onHelpMenu) == "function"
        },
        state = {
            opened = false
        }
    }

    local function ensureOpen(app)
        node.app = app or node.app or ctx.app
        if type(legacy.setContext) == "function" then
            legacy.setContext({app = node.app, node = node})
        end

        if node.state.opened ~= true and type(legacy.openPage) == "function" then
            node.state.opened = true
            legacy.openPage({
                idx = 1,
                title = node.title,
                script = ctx.source
            })
        end
    end

    function node:buildForm(app)
        ensureOpen(app)
    end

    function node:wakeup()
        ensureOpen(self.app)
        if type(legacy.wakeup) == "function" then
            legacy.wakeup()
        end
    end

    function node:save()
        ensureOpen(self.app)
        if type(legacy.onSaveMenu) == "function" then
            return legacy.onSaveMenu()
        end
        return false
    end

    function node:canSave(app)
        ensureOpen(app or self.app)
        if type(legacy.canSave) == "function" then
            return legacy.canSave() == true
        end
        return true
    end

    function node:onSaveMenu()
        return self:save()
    end

    function node:reload()
        ensureOpen(self.app)
        if type(legacy.onReloadMenu) == "function" then
            return legacy.onReloadMenu()
        end
        return false
    end

    function node:onReloadMenu()
        return self:reload()
    end

    function node:menu()
        local pathStack

        ensureOpen(self.app)
        if type(legacy.onNavMenu) == "function" then
            return legacy.onNavMenu()
        end
        pathStack = self.app and self.app.pathStack or {}
        if #pathStack == 0 then
            return self.app and self.app._requestExit and self.app:_requestExit() or false
        end
        return self.app and self.app._goBack and self.app:_goBack() or false
    end

    function node:onNavMenu()
        return self:menu()
    end

    function node:tool()
        ensureOpen(self.app)
        if type(legacy.onToolMenu) == "function" then
            return legacy.onToolMenu()
        end
        return false
    end

    function node:onToolMenu()
        return self:tool()
    end

    function node:help()
        ensureOpen(self.app)
        if type(legacy.onHelpMenu) == "function" then
            return legacy.onHelpMenu()
        end
        if type(helpLines) == "table" then
            return diagnostics.openHelpDialog((self.title or self.baseTitle or "@i18n(app.modules.modes.name)@") .. " Help", helpLines)
        end
        return false
    end

    function node:onHelpMenu()
        return self:help()
    end

    function node:event(_, category, value, x, y)
        ensureOpen(self.app)
        if type(legacy.event) == "function" then
            return legacy.event(nil, category, value, x, y)
        end
        return false
    end

    function node:close()
        if type(legacy.setContext) == "function" then
            legacy.setContext({app = self.app, node = node})
        end
        if type(legacy.close) == "function" then
            legacy.close()
        end
    end

    return node
end

return Page
