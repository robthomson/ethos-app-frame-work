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
        state = {
            formDirty = true,
            formBuildCount = 0,
            statusFields = {},
            valueFields = {},
            buttonFields = {},
            navFields = {},
            headerTitleField = nil
        }
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_sync()
    local app = self:_app()

    if app and app._syncFormHostState then
        app:_syncFormHostState(self.state)
    end
end

function controller:reset()
    self.state.formDirty = true
    self.state.formBuildCount = 0
    self.state.statusFields = {}
    self.state.valueFields = {}
    self.state.buttonFields = {}
    self.state.navFields = {}
    self.state.headerTitleField = nil
    self:_sync()
end

function controller:clearFormRefs()
    self.state.statusFields = {}
    self.state.valueFields = {}
    self.state.buttonFields = {}
    self.state.navFields = {}
    self.state.headerTitleField = nil
    self:_sync()
end

function controller:invalidate()
    self.state.formDirty = true
    self:_sync()
    if form and form.invalidate then
        form.invalidate()
    end
end

function controller:build(node)
    local app = self:_app()
    local built
    local hasCustomBuilder
    local iconPaths
    local index

    if app and app._nodeHasMenuItems and app:_nodeHasMenuItems(node) == true then
        iconPaths = app._collectNodeIconPaths and app:_collectNodeIconPaths(node) or {}
        for index = 1, #iconPaths do
            if app._loadMask then
                app:_loadMask(iconPaths[index])
            end
        end
    end

    if form and form.clear then
        form.clear()
    end
    self:clearFormRefs()
    self.state.formBuildCount = (self.state.formBuildCount or 0) + 1
    self:_sync()

    if app and app._addHeader then
        app:_addHeader(node)
    end
    if app and app._runNodeHook then
        built, hasCustomBuilder = app:_runNodeHook(node, "buildForm")
    end
    if hasCustomBuilder then
        if built == false and app and app._addStaticLine then
            app:_addStaticLine("Error", "Page builder failed")
        end
        if app and app._syncSaveButtonState then
            app:_syncSaveButtonState()
        end
        if app and app.pendingFocusRestore == true and app._restoreAppFocus then
            app:_restoreAppFocus()
        end
        return
    end

    if app and app._buildGridButtons then
        app:_buildGridButtons(node and node.items or {})
    end
    if app and app._nodeHasMenuItems and app:_nodeHasMenuItems(node) == true then
        if app.menuController and app._currentMenuEnableSignature then
            app.menuController:setMenuEnableSignature(app:_currentMenuEnableSignature())
        end
        if app.menuController and app.menuController.clearFocusRestore then
            app.menuController:clearFocusRestore()
        end
    end
    if app and app._syncSaveButtonState then
        app:_syncSaveButtonState()
    end
    if app and app.pendingFocusRestore == true and app._restoreAppFocus then
        app:_restoreAppFocus()
    end
end

function controller:rebuildIfNeeded(node)
    if self.state.formDirty ~= true then
        return
    end
    self.state.formDirty = false
    self:_sync()
    self:build(node)
end

function controller:updateValueFields()
    local app = self:_app()
    local entry

    for _, entry in ipairs(self.state.valueFields or {}) do
        if entry.field and entry.field.value and app and app._resolveItemValue then
            entry.field:value(app:_resolveItemValue(entry.item))
        end
    end
end

return controller
