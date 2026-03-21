--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

local MENU_ROOT_PATH = "app/menu/root.lua"

local function normalizeNodeKey(source)
    return tostring(source or "root"):gsub("[^%w]+", "_")
end

function controller.new(shared, options)
    local opts = options or {}

    return setmetatable({
        shared = shared,
        menuRootPath = opts.menuRootPath or MENU_ROOT_PATH,
        state = {
            menuAccessSignature = nil,
            menuEnableSignature = nil,
            pendingFocusRestore = false
        }
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_sync()
    local app = self:_app()

    if app and app._syncMenuState then
        app:_syncMenuState(self.state)
    end
end

function controller:reset()
    self.state.menuAccessSignature = nil
    self.state.menuEnableSignature = nil
    self.state.pendingFocusRestore = false
    self:_sync()
end

function controller:primeSignatures(accessSignature, enableSignature)
    self.state.menuAccessSignature = accessSignature
    self.state.menuEnableSignature = enableSignature
    self:_sync()
end

function controller:setMenuEnableSignature(signature)
    self.state.menuEnableSignature = signature
    self:_sync()
end

function controller:requestFocusRestore()
    self.state.pendingFocusRestore = true
    self:_sync()
end

function controller:clearFocusRestore()
    self.state.pendingFocusRestore = false
    self:_sync()
end

function controller:_menuState()
    local framework = self.shared and self.shared.framework or nil
    local prefs = framework and framework.preferences or nil
    local state
    local legacy
    local key

    if not prefs or not prefs.section then
        return {}
    end

    state = prefs:section("menulastselected", {})
    legacy = prefs:section("menu_state", {})

    for key, value in pairs(legacy or {}) do
        if state[key] == nil then
            state[key] = value
        end
    end

    return state
end

function controller:_selectedIndexKey(source)
    if source == self.menuRootPath then
        return "mainmenu"
    end

    return "sel_" .. normalizeNodeKey(source)
end

function controller:getSelectedIndex(source)
    local state = self:_menuState()
    local key = self:_selectedIndexKey(source)
    local value = tonumber(state[key])

    if value == nil and source == self.menuRootPath then
        value = tonumber(state["sel_" .. normalizeNodeKey(source)])
    end

    if value == nil or value < 1 then
        return 1
    end

    return value
end

function controller:setSelectedIndex(source, index)
    local state = self:_menuState()
    local value = tonumber(index) or 1
    local key = self:_selectedIndexKey(source)

    state[key] = value

    if source == self.menuRootPath then
        state["sel_" .. normalizeNodeKey(source)] = value
    end
end

function controller:nodeHasMenuItems(node)
    local items = node and node.items or nil
    local index
    local item

    if type(items) ~= "table" then
        return false
    end

    for index = 1, #items do
        item = items[index]
        if item and (item.kind == "menu" or item.kind == "page") then
            return true
        end
    end

    return false
end

function controller:collectNodeIconPaths(node)
    local seen = {}
    local paths = {}
    local items = node and node.items or {}
    local i
    local path

    for i = 1, #items do
        path = items[i] and items[i].image or nil
        if type(path) == "string" and path ~= "" and seen[path] ~= true then
            seen[path] = true
            paths[#paths + 1] = path
        end
    end

    return paths
end

function controller:_itemEnabled(item)
    local app = self:_app()

    if app and app._itemEnabled then
        return app:_itemEnabled(item)
    end

    return type(item) == "table" and item.disabled ~= true
end

function controller:refreshMenuAccess()
    local app = self:_app()
    local signature = app and app._currentMenuAccessSignatureLegacy and app:_currentMenuAccessSignatureLegacy() or "default"

    if self.state.menuAccessSignature == signature then
        return false
    end

    self.state.menuAccessSignature = signature
    if app and app._reloadCurrentMenuNode then
        app:_reloadCurrentMenuNode()
    end
    if app and app._invalidateForm then
        app:_invalidateForm()
    end
    self:_sync()

    return true
end

function controller:restoreFocus(node, currentNodeSource, buttonFields)
    local app = self:_app()
    local items = node and node.items or nil
    local selectedIndex = self:getSelectedIndex(currentNodeSource)
    local buttonIndex = 0
    local firstEnabledField = nil
    local selectedField = nil
    local selectedEnabled = false
    local item
    local field
    local enabled

    if app and app._modalUiActive and app:_modalUiActive() == true then
        return false
    end

    if type(items) == "table" and next(buttonFields or {}) ~= nil then
        for _, item in ipairs(items) do
            if item.kind == "menu" or item.kind == "page" then
                buttonIndex = buttonIndex + 1
                field = buttonFields[buttonIndex]
                enabled = self:_itemEnabled(item)
                if enabled and firstEnabledField == nil and field then
                    firstEnabledField = field
                end
                if buttonIndex == selectedIndex then
                    selectedField = field
                    selectedEnabled = enabled == true
                end
            end
        end

        if selectedEnabled == true and selectedField and selectedField.focus then
            pcall(selectedField.focus, selectedField)
            self:clearFocusRestore()
            return true
        end
        if firstEnabledField and firstEnabledField.focus then
            pcall(firstEnabledField.focus, firstEnabledField)
            self:clearFocusRestore()
            return true
        end
    end

    if app and app._focusNavigationButton and app:_focusNavigationButton("menu") == true then
        self:clearFocusRestore()
        return true
    end

    return false
end

function controller:syncButtonStates(node, currentNodeSource, buttonFields)
    local app = self:_app()
    local buttonIndex = 0
    local items = node and node.items or nil
    local selectedIndex = self:getSelectedIndex(currentNodeSource)
    local firstEnabledField = nil
    local selectedField = nil
    local selectedEnabled = false
    local signature = app and app._currentMenuEnableSignatureLegacy and app:_currentMenuEnableSignatureLegacy() or "default"
    local signatureChanged = (self.state.menuEnableSignature ~= signature)
    local item
    local field
    local enabled

    if type(items) ~= "table" then
        self.state.menuEnableSignature = signature
        self:_sync()
        return
    end

    if signatureChanged ~= true and self.state.pendingFocusRestore ~= true then
        return
    end

    for _, item in ipairs(items) do
        if item.kind == "menu" or item.kind == "page" then
            buttonIndex = buttonIndex + 1
            field = buttonFields[buttonIndex]
            enabled = self:_itemEnabled(item)
            if field and field.enable then
                field:enable(enabled)
            end
            if enabled and firstEnabledField == nil and field then
                firstEnabledField = field
            end
            if buttonIndex == selectedIndex then
                selectedField = field
                selectedEnabled = enabled == true
            end
        end
    end

    self.state.menuEnableSignature = signature

    if (signatureChanged or self.state.pendingFocusRestore == true) and selectedEnabled ~= true and firstEnabledField and firstEnabledField.focus then
        firstEnabledField:focus()
        self.state.pendingFocusRestore = false
    elseif (signatureChanged or self.state.pendingFocusRestore == true) and selectedEnabled == true and selectedField and selectedField.focus then
        selectedField:focus()
        self.state.pendingFocusRestore = false
    end

    self:_sync()
end

return controller
