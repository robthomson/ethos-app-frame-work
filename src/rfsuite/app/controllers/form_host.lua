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
        onSyncState = opts.onSyncState,
        clearForm = opts.clearForm,
        nodeHasMenuItems = opts.nodeHasMenuItems,
        collectNodeIconPaths = opts.collectNodeIconPaths,
        loadMask = opts.loadMask,
        loadRootNode = opts.loadRootNode,
        addHeader = opts.addHeader,
        runNodeHook = opts.runNodeHook,
        addStaticLine = opts.addStaticLine,
        buildGridButtons = opts.buildGridButtons,
        currentMenuEnableSignature = opts.currentMenuEnableSignature,
        setMenuEnableSignature = opts.setMenuEnableSignature,
        clearMenuFocusRestore = opts.clearMenuFocusRestore,
        syncSaveButtonState = opts.syncSaveButtonState,
        restoreAppFocus = opts.restoreAppFocus,
        resolveItemValue = opts.resolveItemValue,
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

function controller:_sync()
    if type(self.onSyncState) == "function" then
        self.onSyncState(self.state)
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
    local built
    local hasCustomBuilder
    local iconPaths
    local index

    if type(self.nodeHasMenuItems) == "function" and self.nodeHasMenuItems(node) == true then
        iconPaths = type(self.collectNodeIconPaths) == "function" and self.collectNodeIconPaths(node) or {}
        for index = 1, #iconPaths do
            if type(self.loadMask) == "function" then
                self.loadMask(iconPaths[index])
            end
        end
    end

    if type(self.clearForm) == "function" then
        self.clearForm()
    end
    self:clearFormRefs()
    self.state.formBuildCount = (self.state.formBuildCount or 0) + 1
    self:_sync()

    if type(self.addHeader) == "function" then
        self.addHeader(node)
    end
    if type(self.runNodeHook) == "function" then
        built, hasCustomBuilder = self.runNodeHook(node, "buildForm")
    end
    if hasCustomBuilder then
        if built == false and type(self.addStaticLine) == "function" then
            self.addStaticLine("Error", "Page builder failed")
        end
        if type(self.syncSaveButtonState) == "function" then
            self.syncSaveButtonState()
        end
        if type(self.restoreAppFocus) == "function" then
            self.restoreAppFocus()
        end
        return
    end

    if type(self.buildGridButtons) == "function" then
        self.buildGridButtons(node and node.items or {})
    end
    if type(self.nodeHasMenuItems) == "function" and self.nodeHasMenuItems(node) == true then
        if type(self.setMenuEnableSignature) == "function" and type(self.currentMenuEnableSignature) == "function" then
            self.setMenuEnableSignature(self.currentMenuEnableSignature())
        end
        if type(self.clearMenuFocusRestore) == "function" then
            self.clearMenuFocusRestore()
        end
    end
    if type(self.syncSaveButtonState) == "function" then
        self.syncSaveButtonState()
    end
    if type(self.restoreAppFocus) == "function" then
        self.restoreAppFocus()
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
    local entry

    for _, entry in ipairs(self.state.valueFields or {}) do
        if entry.field and entry.field.value and type(self.resolveItemValue) == "function" then
            entry.field:value(self.resolveItemValue(entry.item))
        end
    end
end

return controller
