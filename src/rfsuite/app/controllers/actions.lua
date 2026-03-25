--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

function controller.new(shared, options)
    return setmetatable({
        shared = shared
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_confirmAction(title, message, action)
    local app = self:_app()

    if not (form and form.openDialog) then
        return action()
    end

    app.modalDialogDepth = (app.modalDialogDepth or 0) + 1

    form.openDialog({
        width = nil,
        title = title,
        message = message,
        buttons = {
            {
                label = "@i18n(app.btn_ok)@",
                action = function()
                    app.modalDialogDepth = math.max(0, (app.modalDialogDepth or 0) - 1)
                    app.pendingDialogAction = action
                    app.pendingDialogActionReady = false
                    return true
                end
            },
            {
                label = "@i18n(app.btn_cancel)@",
                action = function()
                    app.modalDialogDepth = math.max(0, (app.modalDialogDepth or 0) - 1)
                    return true
                end
            }
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
    return true
end

function controller:handleSaveAction()
    local app = self:_app()
    local node = app and app.currentNode or nil
    local result
    local customResult
    local handled

    if app and app._canSaveNode and not app:_canSaveNode(node) then
        return false
    end

    if app and app._runNodeHook then
        customResult, handled = app:_runNodeHook(node, "onSaveMenu")
        if handled == true then
            return customResult ~= false
        end
    end

    local function runSave()
        if app and app._runNodeHook then
            result = app:_runNodeHook(node, "save")
        end
        if result == false then
            return false
        end
        if app and app.setPageDirty then
            app:setPageDirty(false)
        end
        return true
    end

    if app and app._confirmBeforeSave and app:_confirmBeforeSave() == true then
        return self:_confirmAction("Save Settings", "Save changes?", runSave)
    end

    return runSave()
end

function controller:handleReloadAction()
    local app = self:_app()
    local node = app and app.currentNode or nil
    local result
    local customResult
    local handled

    if app and app._runNodeHook then
        customResult, handled = app:_runNodeHook(node, "onReloadMenu")
        if handled == true then
            return customResult ~= false
        end
    end

    local function runReload()
        if app and app._runNodeHook then
            result = app:_runNodeHook(node, "reload")
        end
        if result == false then
            return false
        end
        if app and app.setPageDirty then
            app:setPageDirty(false)
        end
        return true
    end

    if app and app._confirmBeforeReload and app:_confirmBeforeReload() == true then
        return self:_confirmAction("Reload Settings", "Discard changes and reload?", runReload)
    end

    return runReload()
end

function controller:handleMenuAction()
    local app = self:_app()
    local node = app and app.currentNode or nil
    local pathStack = app and app.pathStack or {}
    local result
    local handled

    if app and app._runNodeHook then
        result, handled = app:_runNodeHook(node, "onNavMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = app:_runNodeHook(node, "menu")
        if handled == true then
            return result ~= false
        end
    end

    if #pathStack == 0 then
        return app and app._requestExit and app:_requestExit() or false
    end

    return app and app._goBack and app:_goBack() or false
end

function controller:handleToolAction()
    local app = self:_app()
    local node = app and app.currentNode or nil
    local result
    local handled

    if app and app._runNodeHook then
        result, handled = app:_runNodeHook(node, "onToolMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = app:_runNodeHook(node, "tool")
        if handled == true then
            return result ~= false
        end
    end

    return false
end

function controller:handleHelpAction()
    local app = self:_app()
    local node = app and app.currentNode or nil
    local result
    local handled

    if app and app._runNodeHook then
        result, handled = app:_runNodeHook(node, "onHelpMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = app:_runNodeHook(node, "help")
        if handled == true then
            return result ~= false
        end
    end

    return false
end

return controller
