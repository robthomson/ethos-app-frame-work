--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

function controller.new(shared, options)
    local opts = options or {}

    return setmetatable({
        shared = shared,
        getCurrentNode = opts.getCurrentNode,
        getPathStack = opts.getPathStack,
        runNodeHook = opts.runNodeHook,
        canSaveNode = opts.canSaveNode,
        confirmBeforeSave = opts.confirmBeforeSave,
        confirmBeforeReload = opts.confirmBeforeReload,
        setPageDirty = opts.setPageDirty,
        requestExit = opts.requestExit,
        goBack = opts.goBack
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
                label = "OK",
                action = function()
                    app.modalDialogDepth = math.max(0, (app.modalDialogDepth or 0) - 1)
                    app.pendingDialogAction = action
                    app.pendingDialogActionReady = false
                    return true
                end
            },
            {
                label = "Cancel",
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
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local result
    local customResult
    local handled

    if type(self.canSaveNode) == "function" and not self.canSaveNode(node) then
        return false
    end

    if type(self.runNodeHook) == "function" then
        customResult, handled = self.runNodeHook(node, "onSaveMenu")
        if handled == true then
            return customResult ~= false
        end
    end

    local function runSave()
        if type(self.runNodeHook) == "function" then
            result = self.runNodeHook(node, "save")
        end
        if result == false then
            return false
        end
        if type(self.setPageDirty) == "function" then
            self.setPageDirty(false)
        end
        return true
    end

    if type(self.confirmBeforeSave) == "function" and self.confirmBeforeSave() == true then
        return self:_confirmAction("Save Settings", "Save changes?", runSave)
    end

    return runSave()
end

function controller:handleReloadAction()
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local result
    local customResult
    local handled

    if type(self.runNodeHook) == "function" then
        customResult, handled = self.runNodeHook(node, "onReloadMenu")
        if handled == true then
            return customResult ~= false
        end
    end

    local function runReload()
        if type(self.runNodeHook) == "function" then
            result = self.runNodeHook(node, "reload")
        end
        if result == false then
            return false
        end
        if type(self.setPageDirty) == "function" then
            self.setPageDirty(false)
        end
        return true
    end

    if type(self.confirmBeforeReload) == "function" and self.confirmBeforeReload() == true then
        return self:_confirmAction("Reload Settings", "Discard changes and reload?", runReload)
    end

    return runReload()
end

function controller:handleMenuAction()
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local pathStack = type(self.getPathStack) == "function" and self.getPathStack() or {}
    local result
    local handled

    if type(self.runNodeHook) == "function" then
        result, handled = self.runNodeHook(node, "onNavMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = self.runNodeHook(node, "menu")
        if handled == true then
            return result ~= false
        end
    end

    if #pathStack == 0 then
        return type(self.requestExit) == "function" and self.requestExit() or false
    end

    return type(self.goBack) == "function" and self.goBack() or false
end

function controller:handleToolAction()
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local result
    local handled

    if type(self.runNodeHook) == "function" then
        result, handled = self.runNodeHook(node, "onToolMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = self.runNodeHook(node, "tool")
        if handled == true then
            return result ~= false
        end
    end

    return false
end

function controller:handleHelpAction()
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local result
    local handled

    if type(self.runNodeHook) == "function" then
        result, handled = self.runNodeHook(node, "onHelpMenu")
        if handled == true then
            return result ~= false
        end

        result, handled = self.runNodeHook(node, "help")
        if handled == true then
            return result ~= false
        end
    end

    return false
end

return controller
