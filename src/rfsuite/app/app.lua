--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local App = {}
local ethos_events = require("framework.utils.ethos_events")
local callbackFactory = require("framework.core.callback")
local AudioLib = require("lib.audio")

local MENU_ROOT_PATH = "app/menu/root.lua"
local MASK_CACHE_MAX = 96
local NOOP_PAINT = function() end
local HEADER_NAV_HEIGHT_REDUCTION = 4
local HEADER_NAV_Y_SHIFT = 6
local HEADER_BREADCRUMB_Y_OFFSET = 5
local HEADER_RIGHT_GUTTER = 12
local LOADER_MIN_VISIBLE = 0.35
local LOADER_FALLBACK_CLOSE = 0.85
local STARTUP_LOADER_MIN_VISIBLE = 0.20
local STARTUP_ICON_BATCH = 2
local STARTUP_SENSOR_LOST_MUTE = 6.0
local LOADER_PROGRESS_MULTIPLIER = 2.0
local MENU_LOADER_PROGRESS_FACTOR = 4.0
local LOADER_TIMEOUT_MESSAGE = "Error: timed out"
local LOADER_TIMEOUT_DETAIL = "Press close to continue."
local MSP_DEBUG_PLACEHOLDER = "MSP Waiting"
local DIRTY_WRAPPERS_INSTALLED = false
local DIRTY_OWNER = nil
local unpack_fn = table.unpack or unpack
local APP_CALLBACK_WAKEUP_OPTIONS = {
    maxCalls = 6,
    budgetMs = 2,
    categories = {"immediate", "timer", "events"}
}
local APP_RENDER_CALLBACK_WAKEUP_OPTIONS = {
    maxCalls = 4,
    budgetMs = 2,
    category = "render"
}
local APP_MAINTENANCE_PHASES = 3
local SHORTCUTS_MODULE_CACHE = nil
local MENU_VISIBILITY_MODULE_CACHE = nil

local function loadLuaTable(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid path"
    end

    local chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr
    end

    local ok, value = pcall(chunk)
    if not ok then
        return nil, value
    end

    if type(value) ~= "table" then
        return nil, "module did not return table"
    end

    return value
end

local function loadShortcutsModule()
    if type(SHORTCUTS_MODULE_CACHE) == "table" then
        return SHORTCUTS_MODULE_CACHE
    end

    local mod = select(1, loadLuaTable("app/lib/shortcuts.lua"))

    if type(mod) == "table" then
        SHORTCUTS_MODULE_CACHE = mod
        return mod
    end

    return nil
end

local function loadMenuVisibilityModule()
    if type(MENU_VISIBILITY_MODULE_CACHE) == "table" then
        return MENU_VISIBILITY_MODULE_CACHE
    end

    local mod = select(1, loadLuaTable("app/lib/menu_visibility.lua"))

    if type(mod) == "table" then
        MENU_VISIBILITY_MODULE_CACHE = mod
        return mod
    end

    return nil
end

local function isCloseEvent(category, value)
    return ethos_events.isCloseEvent(category, value)
end

local function isSaveKeyEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_ENTER_LONG",
        "KEY_PAGE_LONG"
    })
end

local function isMenuKeyEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_RTN",
        "KEY_RTN_FIRST",
        "KEY_RTN_BREAK"
    })
end

local function isRotaryNavigationEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_ROTARY_LEFT",
        "KEY_ROTARY_RIGHT"
    })
end

local function isExitLongEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_RTN_LONG"
    })
end

local function suppressFollowupKeyEvent(value)
    local breakName = nil
    local breakValue

    if not (system and system.killEvents) then
        return
    end

    if ethos_events.matchesConstant(value, "KEY_ENTER_LONG") then
        breakName = "KEY_ENTER_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_PAGE_LONG") then
        breakName = "KEY_PAGE_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_RTN") or ethos_events.matchesConstant(value, "KEY_RTN_FIRST") then
        breakName = "KEY_RTN_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_RTN_LONG") then
        breakName = "KEY_RTN_BREAK"
    end

    if breakName == nil then
        return
    end

    breakValue = ethos_events.getConstant(breakName)
    if breakValue ~= nil then
        pcall(system.killEvents, breakValue)
    end
end

local function formatValue(value, format)
    if value == nil then
        return "--"
    end

    if format == "ms_3" then
        return string.format("%.3fms", tonumber(value) or 0)
    end

    if format == "kb_1" then
        return string.format("%.1fKB", tonumber(value) or 0)
    end

    if format == "bool" then
        return value == true and "Yes" or "No"
    end

    return tostring(value)
end

local function safeFormClear()
    if form and form.clear then
        form.clear()
    end
end

local function normalizeNodeKey(source)
    return tostring(source or "root"):gsub("[^%w]+", "_")
end

local function trimText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function appendBreadcrumbPart(parts, part)
    part = trimText(part)
    if part == "" then
        return
    end

    if parts[#parts] == part then
        return
    end

    parts[#parts + 1] = part
end

local function boolString(value)
    return value == true and "Yes" or "No"
end

function App:init(framework)
    local radioConfig, radioErr

    self.framework = framework
    self.callback = callbackFactory.new()
    self.telemetryTask = nil
    self.menuAccessSignature = nil
    self.menuEnableSignature = nil
    self.startupLoaderStage = 0
    self.startupJob = nil
    self._startupCallback = function()
        self:_runStartupPreparationStep()
    end
    self.maintenanceScheduled = false
    self.maintenancePhase = 0
    self._maintenanceCallback = function()
        self:_runDeferredMaintenanceStep()
    end
    radioConfig, radioErr = loadLuaTable("app/radios.lua")
    if type(radioConfig) ~= "table" then
        error("failed to load app/radios.lua: " .. tostring(radioErr))
    end
    self.radio = radioConfig
    self.snapshot = {}
    self.pathStack = {}
    self.currentNode = nil
    self.currentNodeSource = MENU_ROOT_PATH
    self.formDirty = true
    self.rootLoadError = nil
    self.statusFields = {}
    self.valueFields = {}
    self.buttonFields = {}
    self.navFields = {}
    self.maskCache = {}
    self.maskCacheOrder = {}
    self.pageDirty = false
    self.dirtySuspendDepth = 0
    self.returnMenuArmed = false
    self.pendingFocusRestore = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    self.formBuildCount = 0
    self.mspTask = nil
    self.loader = {
        active = nil,
        status = nil,
        signature = nil
    }
    self.loaderSpeed = {
        VSLOW = 0.5,
        SLOW = 0.75,
        DEFAULT = 1.0,
        FAST = 2.3,
        VFAST = 2.8
    }
    self.ui = self:_createUiBridge()
    self:_installDirtyCallbackWrappers()
end

function App:_clearFormRefs()
    self.statusFields = {}
    self.valueFields = {}
    self.buttonFields = {}
    self.navFields = {}
    self.headerTitleField = nil
end

function App:_invalidateForm()
    self.formDirty = true
    if form and form.invalidate then
        form.invalidate()
    end
end

function App:_menuState()
    local prefs = self.framework and self.framework.preferences
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

function App:_selectedIndexKey(source)
    if source == MENU_ROOT_PATH then
        return "mainmenu"
    end

    return "sel_" .. normalizeNodeKey(source)
end

function App:_generalPrefs()
    local general = self.framework.preferences:section("general", {})
    local preview = self.currentNode and self.currentNode.getGeneralPreferences and self.currentNode:getGeneralPreferences()
    local merged = {}
    local key

    for key, value in pairs(general) do
        merged[key] = value
    end
    if type(preview) == "table" then
        for key, value in pairs(preview) do
            merged[key] = value
        end
    end

    return merged
end

function App:_generalBool(key, default)
    local value = self:_generalPrefs()[key]

    if value == nil then
        return default
    end
    if value == true or value == "true" or value == 1 or value == "1" then
        return true
    end
    if value == false or value == "false" or value == 0 or value == "0" then
        return false
    end

    return default
end

function App:_getSelectedIndex(source)
    local state = self:_menuState()
    local key = self:_selectedIndexKey(source)
    local value = tonumber(state[key])

    if value == nil and source == MENU_ROOT_PATH then
        value = tonumber(state["sel_" .. normalizeNodeKey(source)])
    end

    if value == nil or value < 1 then
        return 1
    end
    return value
end

function App:_setSelectedIndex(source, index)
    local state = self:_menuState()
    local value = tonumber(index) or 1
    local key = self:_selectedIndexKey(source)

    state[key] = value

    if source == MENU_ROOT_PATH then
        state["sel_" .. normalizeNodeKey(source)] = value
    end
end

function App:_savePreferences()
    if not (self.framework and self.framework.preferences and self.framework.preferences.save) then
        return false
    end

    return pcall(function()
        self.framework.preferences:save()
    end)
end

function App:_windowSize()
    if lcd and lcd.getWindowSize then
        return lcd.getWindowSize()
    end
    return 800, 480
end

function App:_iconsize()
    local general = self:_generalPrefs()
    local iconsize = tonumber(general.iconsize)
    if iconsize == nil then
        iconsize = 1
        general.iconsize = iconsize
    end
    if iconsize < 0 then iconsize = 0 end
    if iconsize > 2 then iconsize = 2 end
    return iconsize
end

function App:_collapseNavigation()
    return self:_generalBool("collapse_unused_menu_entries", false)
end

function App:_confirmBeforeSave()
    return self:_generalBool("save_confirm", true)
end

function App:_confirmBeforeReload()
    return self:_generalBool("reload_confirm", false)
end

function App:_saveDirtyOnly()
    return self:_generalBool("save_dirty_only", true)
end

function App:_menuButtonMetrics()
    local radio = self.radio
    local iconsize = self:_iconsize()
    local width = self:_windowSize()
    local buttonW
    local buttonH
    local padding
    local numPerRow

    if iconsize == 0 then
        padding = radio.buttonPaddingSmall
        buttonW = (width - padding) / radio.buttonsPerRow - padding
        buttonH = radio.navbuttonHeight
        numPerRow = radio.buttonsPerRow
    elseif iconsize == 2 then
        padding = radio.buttonPadding
        buttonW = radio.buttonWidth
        buttonH = radio.buttonHeight
        numPerRow = radio.buttonsPerRow
    else
        padding = radio.buttonPaddingSmall
        buttonW = radio.buttonWidthSmall
        buttonH = radio.buttonHeightSmall
        numPerRow = radio.buttonsPerRowSmall
    end

    return {
        buttonW = math.floor(buttonW),
        buttonH = math.floor(buttonH),
        padding = padding,
        numPerRow = numPerRow
    }
end

function App:_headerMetrics()
    local radio = self.radio
    local width = self:_windowSize()
    local buttonW = radio.menuButtonWidth or 100
    local buttonH = math.max(20, (radio.navbuttonHeight or 30) - HEADER_NAV_HEIGHT_REDUCTION)
    local padding = 5
    local compactW = math.max(20, buttonW - math.floor((buttonW * 25) / 100))
    local reserved = (buttonW + padding) * 4 + (compactW + padding)
    return {
        width = width,
        buttonW = buttonW,
        compactW = compactW,
        buttonH = buttonH,
        titleWidth = math.max(40, (width - HEADER_RIGHT_GUTTER) - reserved - 8)
    }
end

function App:_loadMask(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local cached = self.maskCache[path]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local mask = lcd and lcd.loadMask and lcd.loadMask(path) or nil
    self.maskCache[path] = mask or false
    self.maskCacheOrder[#self.maskCacheOrder + 1] = path

    while #self.maskCacheOrder > MASK_CACHE_MAX do
        local evict = table.remove(self.maskCacheOrder, 1)
        self.maskCache[evict] = nil
    end

    return mask
end

function App:_pruneMaskCacheForNode(node)
    local _ = node
    return
end

function App:_afterNodeChanged()
    self:_pruneMaskCacheForNode(self.currentNode)
    pcall(collectgarbage, "step", 64)
end

function App:_reportNodeError(context, err)
    if self.framework and self.framework.log and self.framework.log.error then
        self.framework.log:error("App %s error: %s", tostring(context), tostring(err))
    end
end

function App:_installDirtyCallbackWrappers()
    local function wrapSetter(methodName)
        local original = form and form[methodName]

        if type(original) ~= "function" then
            return
        end

        form[methodName] = function(...)
            local argc = select("#", ...)
            local args = {...}
            local setterIdx
            local setter

            for setterIdx = argc, 1, -1 do
                if type(args[setterIdx]) == "function" then
                    setter = args[setterIdx]
                    args[setterIdx] = function(...)
                        if DIRTY_OWNER and (DIRTY_OWNER.dirtySuspendDepth or 0) <= 0 and DIRTY_OWNER.markPageDirty then
                            DIRTY_OWNER:markPageDirty()
                        end
                        return setter(...)
                    end
                    break
                end
            end

            return original(unpack_fn(args, 1, argc))
        end
    end

    if DIRTY_WRAPPERS_INSTALLED or not form then
        return
    end

    wrapSetter("addBooleanField")
    wrapSetter("addChoiceField")
    wrapSetter("addNumberField")
    wrapSetter("addTextField")
    wrapSetter("addSourceField")
    wrapSetter("addSensorField")
    wrapSetter("addColorField")
    wrapSetter("addSwitchField")

    DIRTY_WRAPPERS_INSTALLED = true
end

function App:_shouldManageDirtySave(node)
    if type(node) ~= "table" then
        return false
    end
    if type(node.save) ~= "function" then
        return false
    end
    if node.disableSaveUntilDirty == false then
        return false
    end
    if self:_saveDirtyOnly() ~= true then
        return false
    end
    return true
end

function App:_canSaveNode(node)
    local ok
    local value
    local canSave = true

    if type(node) ~= "table" or type(node.save) ~= "function" then
        return false
    end

    if type(node.canSave) == "function" then
        ok, value = pcall(node.canSave, node, self)
        if ok then
            canSave = value == true
        else
            self:_reportNodeError("canSave", value)
            return false
        end
    end

    if canSave ~= true then
        return false
    end

    if self:_shouldManageDirtySave(node) then
        return self.pageDirty == true
    end

    return true
end

function App:_syncSaveButtonState()
    local save = self.navFields and self.navFields.save

    if save and save.enable then
        save:enable(self:_canSaveNode(self.currentNode))
    end
end

function App:_focusNavigationButton(key)
    local field = self.navFields and self.navFields[key] or nil

    if field and field.focus then
        pcall(field.focus, field)
        return true
    end

    return false
end

function App:_modalUiActive()
    return (self.loader and self.loader.active and self.loader.active.modal == true)
        or ((self.modalDialogDepth or 0) > 0)
end

function App:_openManagedDialog(options)
    local opts = type(options) == "table" and options or {}
    local buttons = {}
    local index
    local button
    local originalAction

    if not (form and form.openDialog) then
        return nil
    end

    self.modalDialogDepth = (self.modalDialogDepth or 0) + 1

    for index = 1, #(opts.buttons or {}) do
        button = {}
        for key, value in pairs(opts.buttons[index]) do
            button[key] = value
        end
        originalAction = button.action
        button.action = function(...)
            self.modalDialogDepth = math.max(0, (self.modalDialogDepth or 0) - 1)
            if type(originalAction) == "function" then
                return originalAction(...)
            end
            return true
        end
        buttons[#buttons + 1] = button
    end

    opts.buttons = buttons
    return form.openDialog(opts)
end

function App:_requestAppFocusRestore()
    self.pendingFocusRestore = true
end

function App:_hasMenuButtons()
    return next(self.buttonFields or {}) ~= nil
end

function App:_restoreAppFocus()
    local items = self.currentNode and self.currentNode.items or nil
    local selectedIndex = self:_getSelectedIndex(self.currentNodeSource)
    local buttonIndex = 0
    local firstEnabledField = nil
    local selectedField = nil
    local selectedEnabled = false
    local item
    local field
    local enabled

    if self:_modalUiActive() == true then
        return false
    end

    if type(items) == "table" and next(self.buttonFields or {}) ~= nil then
        for _, item in ipairs(items) do
            if item.kind == "menu" or item.kind == "page" then
                buttonIndex = buttonIndex + 1
                field = self.buttonFields[buttonIndex]
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
            self.pendingFocusRestore = false
            return true
        end
        if firstEnabledField and firstEnabledField.focus then
            pcall(firstEnabledField.focus, firstEnabledField)
            self.pendingFocusRestore = false
            return true
        end
    end

    if self:_focusNavigationButton("menu") == true then
        self.pendingFocusRestore = false
        return true
    end

    return false
end

function App:setPageDirty(isDirty)
    self.pageDirty = isDirty == true
    self:_syncSaveButtonState()
end

function App:markPageDirty()
    if self.pageDirty then
        return
    end
    self:setPageDirty(true)
end

function App:suspendDirtyTracking()
    self.dirtySuspendDepth = (self.dirtySuspendDepth or 0) + 1
    return self.dirtySuspendDepth
end

function App:resumeDirtyTracking()
    self.dirtySuspendDepth = math.max(0, (self.dirtySuspendDepth or 0) - 1)
    return self.dirtySuspendDepth
end

function App:_confirmAction(title, message, action)
    if not (form and form.openDialog) then
        return action()
    end

    self.modalDialogDepth = (self.modalDialogDepth or 0) + 1

    form.openDialog({
        width = nil,
        title = title,
        message = message,
        buttons = {
            {
                label = "OK",
                action = function()
                    self.modalDialogDepth = math.max(0, (self.modalDialogDepth or 0) - 1)
                    self.pendingDialogAction = action
                    self.pendingDialogActionReady = false
                    return true
                end
            },
            {
                label = "Cancel",
                action = function()
                    self.modalDialogDepth = math.max(0, (self.modalDialogDepth or 0) - 1)
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

function App:_handleSaveAction()
    local result
    local customResult
    local handled

    if not self:_canSaveNode(self.currentNode) then
        return false
    end

    customResult, handled = self:_runNodeHook(self.currentNode, "onSaveMenu")
    if handled == true then
        return customResult ~= false
    end

    local function runSave()
        result = self:_runNodeHook(self.currentNode, "save")
        if result == false then
            return false
        end
        self:setPageDirty(false)
        return true
    end

    if self:_confirmBeforeSave() == true then
        return self:_confirmAction("Save Settings", "Save changes?", runSave)
    end

    return runSave()
end

function App:_handleReloadAction()
    local result
    local customResult
    local handled

    customResult, handled = self:_runNodeHook(self.currentNode, "onReloadMenu")
    if handled == true then
        return customResult ~= false
    end

    local function runReload()
        result = self:_runNodeHook(self.currentNode, "reload")
        if result == false then
            return false
        end
        self:setPageDirty(false)
        return true
    end

    if self:_confirmBeforeReload() == true then
        return self:_confirmAction("Reload Settings", "Discard changes and reload?", runReload)
    end

    return runReload()
end

function App:_handleMenuAction()
    local result
    local handled

    result, handled = self:_runNodeHook(self.currentNode, "onNavMenu")
    if handled == true then
        return result ~= false
    end

    result, handled = self:_runNodeHook(self.currentNode, "menu")
    if handled == true then
        return result ~= false
    end

    if #self.pathStack == 0 then
        return self:_requestExit()
    end

    return self:_goBack()
end

function App:_handleToolAction()
    local result
    local handled

    result, handled = self:_runNodeHook(self.currentNode, "onToolMenu")
    if handled == true then
        return result ~= false
    end

    result, handled = self:_runNodeHook(self.currentNode, "tool")
    if handled == true then
        return result ~= false
    end

    return false
end

function App:_handleHelpAction()
    local result
    local handled

    result, handled = self:_runNodeHook(self.currentNode, "onHelpMenu")
    if handled == true then
        return result ~= false
    end

    result, handled = self:_runNodeHook(self.currentNode, "help")
    if handled == true then
        return result ~= false
    end

    return false
end

function App:_runNodeHook(node, hookName, ...)
    local hook
    local ok
    local result

    if type(node) ~= "table" then
        return nil, false
    end

    hook = node[hookName]
    if type(hook) ~= "function" then
        return nil, false
    end

    ok, result = pcall(hook, node, self, ...)
    if not ok then
        self:_reportNodeError(hookName, result)
        return nil, true
    end

    return result, true
end

function App:_createUiBridge()
    return {
        progressDisplay = function(title, message, speed)
            return self:showLoader({
                kind = "progress",
                title = title,
                message = message,
                speed = speed,
                closeWhenIdle = true,
                fallbackCloseAfter = 1.10,
                modal = true
            })
        end,
        progressDisplaySave = function(message)
            return self:showLoader({
                kind = "save",
                title = "Saving",
                message = message,
                closeWhenIdle = true,
                fallbackCloseAfter = LOADER_FALLBACK_CLOSE,
                modal = true
            })
        end,
        updateProgressDialogMessage = function(message)
            return self:updateLoader({message = message})
        end,
        clearProgressDialog = function()
            return self:clearLoader()
        end,
        progressClose = function()
            return self:clearLoader()
        end,
        closeLoader = function()
            return self:clearLoader()
        end,
        requestLoaderClose = function()
            return self:requestLoaderClose()
        end,
        progressDisplayIsActive = function()
            return self:isLoaderActive()
        end,
        setPageDirty = function(isDirty)
            return self:setPageDirty(isDirty)
        end,
        registerProgressDialog = function(_, baseMessage)
            return self:updateLoader({message = baseMessage})
        end,
        showLoader = function(options)
            return self:showLoader(options)
        end,
        updateLoader = function(options)
            return self:updateLoader(options)
        end,
        hideLoader = function()
            return self:clearLoader()
        end
    }
end

function App:_msp()
    if self.mspTask == nil and self.framework and self.framework.getTask then
        self.mspTask = self.framework:getTask("msp")
    end
    return self.mspTask
end

function App:_loaderText(value, fallback)
    local text = trimText(value)

    if text == "" then
        return fallback or ""
    end
    if text:find("@i18n%(", 1, false) ~= nil then
        return fallback or ""
    end

    return text
end

function App:_openLoaderDialog(title, message)
    local opts = {
        title = title,
        message = message,
        wakeup = function()
            self:_refreshLoaderState()
        end,
        paint = function() end,
        options = TEXT_LEFT
    }

    if form and form.openWaitDialog then
        opts.progress = true
        return form.openWaitDialog(opts)
    end
    if form and form.openProgressDialog then
        opts.progress = true
        return form.openProgressDialog(opts)
    end
    if form and form.openDialog then
        opts.width = nil
        return form.openDialog(opts)
    end

    return nil
end

function App:_closeLoaderDialog(handle)
    if handle and handle.close then
        pcall(handle.close, handle)
    end
end

function App:_loaderMessage(state)
    local parts = {}
    local base = self:_loaderText(state.message, "Working.")
    local detail = self:_loaderText(state.detail, "")
    local transferStatus = state.transferInfo == true
        and state.timedOut ~= true
        and state.debug ~= false
        and self:_generalBool("mspstatusdialog", true) == true
        and self:_mspTransferStatus()
        or nil
    local lines = transferStatus == nil
        and state.debug ~= false
        and self:_generalBool("mspstatusdialog", true) == true
        and self:_mspDebugLines()
        or nil

    if transferStatus ~= nil and transferStatus ~= "" then
        parts[#parts + 1] = transferStatus
    elseif base ~= "" then
        parts[#parts + 1] = base
    end
    if detail ~= "" then
        parts[#parts + 1] = detail
    end
    if type(lines) == "table" then
        for i = 1, math.min(#lines, 3) do
            parts[#parts + 1] = lines[i]
        end
    end

    if #parts == 0 then
        return "Working."
    end

    return table.concat(parts, "\n")
end

function App:_mspTransferStatus()
    local session = self.framework and self.framework.session
    local now = os.clock()
    local clearAt
    local updatedAt
    local status
    local last
    local extras

    if not session then
        return MSP_DEBUG_PLACEHOLDER
    end

    clearAt = tonumber(session:get("mspStatusClearAt", 0)) or 0
    if clearAt > 0 and now >= clearAt then
        session:unset("mspStatusMessage")
        session:unset("mspStatusClearAt")
    end

    status = session:get("mspStatusMessage", nil)
    last = session:get("mspStatusLast", nil)
    updatedAt = tonumber(session:get("mspStatusUpdatedAt", 0)) or 0

    if not status and last and updatedAt > 0 and (now - updatedAt) < 0.75 then
        status = last
    end

    if type(status) == "string" and status ~= "" then
        extras = self:_mspTransferExtras()
        if extras then
            return status .. " " .. extras
        end
        return status
    end

    extras = self:_mspTransferExtras()
    if extras then
        return extras
    end

    return MSP_DEBUG_PLACEHOLDER
end

function App:_mspTransferExtras()
    local session = self.framework and self.framework.session
    local mspTask = self:_msp()
    local queue = mspTask and mspTask.queue or nil
    local parts = {}
    local tx
    local rx
    local retries
    local crc
    local timeoutCount

    if not session then
        return nil
    end

    tx = tonumber(session:get("mspLastTxCommand", 0)) or 0
    rx = tonumber(session:get("mspLastRxCommand", 0)) or 0
    retries = queue and tonumber(queue.retryCount) or 0
    crc = tonumber(session:get("mspCrcErrors", 0)) or 0
    timeoutCount = tonumber(session:get("mspTimeouts", 0)) or 0

    if tx > 0 then
        parts[#parts + 1] = "Transmit " .. tostring(tx)
    end
    if rx > 0 then
        parts[#parts + 1] = "Receive " .. tostring(rx)
    end
    if retries > 1 then
        parts[#parts + 1] = "Retry " .. tostring(retries - 1)
    end
    if crc > 0 then
        parts[#parts + 1] = "CRC " .. tostring(crc)
    end
    if timeoutCount > 0 then
        parts[#parts + 1] = "Timeout " .. tostring(timeoutCount)
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, " ")
end

function App:_syncLoaderDialog()
    local active = self.loader.active
    local handle
    local message
    local progressValue

    if active == nil then
        return
    end

    handle = active.handle
    message = self:_loaderMessage(active)
    progressValue = tonumber(active.progressValue)
    if progressValue == nil then
        progressValue = tonumber(active.progressCounter) or 0
    end

    if handle and handle.message then
        pcall(handle.message, handle, message)
    end
    if handle and handle.value then
        pcall(handle.value, handle, math.floor(math.max(0, math.min(100, progressValue))))
    end
    if handle and handle.closeAllowed then
        pcall(handle.closeAllowed, handle, active.timedOut == true or active.allowClose == true)
    end
end

function App:_loaderBusyState()
    local session = self.framework and self.framework.session
    local apiProbeState

    if not session then
        return false
    end

    apiProbeState = tostring(session:get("apiProbeState", "idle") or "idle")

    if session:get("lifecycleActive", false) == true then
        return true
    end
    if session:get("isConnecting", false) == true then
        return true
    end
    if session:get("mspBusy", false) == true then
        return true
    end
    if apiProbeState ~= "idle" and apiProbeState ~= "connected" then
        return true
    end

    return false
end

function App:_mspDebugLines()
    local session = self.framework and self.framework.session
    local mspTask = self:_msp()
    local queue = mspTask and mspTask.queue or nil
    local queueDepth
    local retryCount
    local apiProbeState
    local transport
    local command
    local connectionState
    local reason
    local lines = {}

    if not session then
        return lines
    end

    queueDepth = tonumber(session:get("mspQueueDepth", 0)) or 0
    retryCount = queue and tonumber(queue.retryCount) or 0
    apiProbeState = tostring(session:get("apiProbeState", "idle") or "idle")
    transport = tostring(session:get("connectionTransport", "disconnected") or "disconnected")
    command = tostring(session:get("mspLastCommand", "idle") or "idle")
    connectionState = tostring(session:get("connectionState", "disconnected") or "disconnected")
    reason = tostring(session:get("connectionReason", "startup") or "startup")

    lines[#lines + 1] = string.format(
        "Queue %d  Busy %s  Retry %d",
        queueDepth,
        boolString(session:get("mspBusy", false) == true),
        math.max(0, retryCount - 1)
    )
    lines[#lines + 1] = string.format(
        "Probe %s  Cmd %s  Link %s",
        apiProbeState,
        command,
        transport
    )
    lines[#lines + 1] = string.format(
        "Conn %s  Reason %s",
        connectionState,
        reason
    )

    return lines
end

function App:_loaderSignature(state)
    if type(state) ~= "table" then
        return "none"
    end

    return table.concat({
        tostring(state.title or ""),
        tostring(self:_loaderMessage(state)),
        tostring(state.progressCounter or 0),
        tostring(state.pendingClose == true),
        tostring(state.timedOut == true)
    }, "#")
end

function App:_loaderWatchdogTimeout(kind, requested)
    local value = tonumber(requested)
    local mspTask
    local protocolTimeout

    if requested == false then
        return nil
    end
    if value ~= nil and value > 0 then
        return value
    end
    if requested ~= nil and requested ~= true then
        return nil
    end
    if kind ~= "progress" and kind ~= "save" then
        return nil
    end

    mspTask = self:_msp()
    protocolTimeout = tonumber(mspTask and mspTask.protocol and mspTask.protocol.timeout)

    if kind == "save" then
        if protocolTimeout and protocolTimeout > 0 then
            return protocolTimeout + 5.0
        end
        return 8.0
    end

    if protocolTimeout and protocolTimeout > 0 then
        return protocolTimeout
    end

    return 4.0
end

function App:_tripLoaderWatchdog(active)
    local handle

    if type(active) ~= "table" or active.timedOut == true then
        return
    end

    active.timedOut = true
    active.pendingClose = false
    active.progressValue = 100
    active.message = LOADER_TIMEOUT_MESSAGE
    active.detail = LOADER_TIMEOUT_DETAIL
    handle = active.handle

    if handle and handle.message then
        pcall(handle.message, handle, self:_loaderMessage(active))
    end
    if handle and handle.value then
        pcall(handle.value, handle, 100)
    end
    if handle and handle.closeAllowed then
        pcall(handle.closeAllowed, handle, true)
    end

    AudioLib.playFile("app", "timeout.wav")
end

function App:_refreshLoaderState()
    local now = os.clock()
    local active = self.loader.active
    local signature
    local progressValue
    local mult
    local focusMenuOnClose = false
    local restoreFocusOnClose = false

    if active then
        mult = active.speed or 1.0
        progressValue = tonumber(active.progressValue)
        if active.closeRequested == true then
            active.progressCounter = math.min(100, (active.progressCounter or 0) + (15 * mult))
        elseif progressValue == nil then
            local progressFactor = (active.kind == "menu") and MENU_LOADER_PROGRESS_FACTOR or (active.closeWhenIdle == true and 2 or 1.2)
            active.progressCounter = math.min((active.kind == "menu") and 95 or 99, (active.progressCounter or 0) + (mult * LOADER_PROGRESS_MULTIPLIER * progressFactor))
        else
            active.progressCounter = math.max(0, math.min(100, progressValue))
        end
        if active.pendingClose == true and now >= (active.minVisibleUntil or 0) then
            focusMenuOnClose = active.focusMenuOnClose == true
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeLoaderDialog(active.handle)
            self.loader.active = nil
            active = nil
        elseif active
            and active.closeRequested == true
            and active.timedOut ~= true
            and now >= (active.minVisibleUntil or 0)
            and (active.progressCounter or 0) >= 100 then
            focusMenuOnClose = active.focusMenuOnClose == true
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeLoaderDialog(active.handle)
            self.loader.active = nil
            active = nil
        elseif active.timedOut ~= true and active.watchdogDeadline and now >= active.watchdogDeadline then
            self:_tripLoaderWatchdog(active)
        elseif active
            and active.timedOut ~= true
            and active.closeWhenIdle == true
            and now >= (active.minVisibleUntil or 0)
            and self:_loaderBusyState() ~= true
            and now >= (active.fallbackCloseAt or 0) then
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeLoaderDialog(active.handle)
            self.loader.active = nil
            active = nil
        end
    end

    self.loader.status = nil
    if active then
        self:_syncLoaderDialog()
    else
        if focusMenuOnClose == true then
            if self:_modalUiActive() == true then
                self.pendingFocusRestore = true
            else
                self.pendingFocusRestore = false
                self:_focusNavigationButton("menu")
            end
        elseif restoreFocusOnClose == true then
            if self:_modalUiActive() == true then
                self.pendingFocusRestore = true
            else
                self.pendingFocusRestore = true
                self:_restoreAppFocus()
            end
        end
    end
    signature = self:_loaderSignature(active)
    self.loader.signature = signature
end

function App:_loaderSpeed(speed)
    local value = tonumber(speed)

    if value ~= nil and value > 0 then
        return value
    end

    return self.loaderSpeed.DEFAULT
end

function App:_showMenuNavigationLoader(title, detail, speed)
    local _ = title
    _ = detail
    _ = speed
end

function App:_clearMenuNavigationLoader()
    return
end

function App:showLoader(options)
    local opts = type(options) == "table" and options or {}
    local now = os.clock()
    local kind = opts.kind or "progress"
    local defaultTitle = kind == "save" and "Saving" or "Loading"
    local defaultMessage = kind == "save" and "Saving settings." or "Loading from flight controller."
    local watchdogTimeout = self:_loaderWatchdogTimeout(kind, opts.watchdogTimeout or opts.watchdog)

    self.loader.active = {
        kind = kind,
        title = self:_loaderText(opts.title, defaultTitle),
        message = self:_loaderText(opts.message, defaultMessage),
        detail = self:_loaderText(opts.detail, ""),
        speed = self:_loaderSpeed(opts.speed),
        modal = opts.modal ~= false,
        closeWhenIdle = opts.closeWhenIdle ~= false,
        allowClose = opts.allowClose == true,
        createdAt = now,
        minVisibleUntil = now + (tonumber(opts.minVisibleFor) or LOADER_MIN_VISIBLE),
        fallbackCloseAt = now + (tonumber(opts.fallbackCloseAfter) or LOADER_FALLBACK_CLOSE),
        watchdogDeadline = watchdogTimeout and (now + watchdogTimeout) or nil,
        pendingClose = false,
        closeRequested = false,
        focusMenuOnClose = opts.focusMenuOnClose == true,
        restoreFocusOnClose = opts.restoreFocusOnClose == true,
        timedOut = false,
        debug = opts.debug ~= false,
        transferInfo = opts.transferInfo == true,
        progressCounter = 0,
        progressValue = tonumber(opts.progressValue)
    }
    self.loader.active.handle = self:_openLoaderDialog(
        self.loader.active.title,
        self:_loaderMessage(self.loader.active)
    )
    self:_refreshLoaderState()
    return self.loader.active
end

function App:updateLoader(options)
    local opts = type(options) == "table" and options or {}
    local active = self.loader.active

    if active == nil then
        return self:showLoader(opts)
    end

    if opts.title ~= nil then
        active.title = self:_loaderText(opts.title, active.title)
    end
    if opts.message ~= nil then
        active.message = self:_loaderText(opts.message, active.message)
    end
    if opts.detail ~= nil then
        active.detail = self:_loaderText(opts.detail, active.detail)
    end
    if opts.speed ~= nil then
        active.speed = self:_loaderSpeed(opts.speed)
    end
    if opts.closeWhenIdle ~= nil then
        active.closeWhenIdle = opts.closeWhenIdle == true
    end
    if opts.allowClose ~= nil then
        active.allowClose = opts.allowClose == true
    end
    if opts.transferInfo ~= nil then
        active.transferInfo = opts.transferInfo == true
    end
    if opts.progressValue ~= nil then
        active.progressValue = tonumber(opts.progressValue)
    end
    if opts.watchdogTimeout ~= nil or opts.watchdog ~= nil then
        local watchdogTimeout = self:_loaderWatchdogTimeout(active.kind, opts.watchdogTimeout or opts.watchdog)
        active.watchdogDeadline = watchdogTimeout and (os.clock() + watchdogTimeout) or nil
        active.timedOut = false
    elseif opts.title ~= nil or opts.message ~= nil or opts.detail ~= nil then
        local watchdogTimeout = self:_loaderWatchdogTimeout(active.kind, true)
        if watchdogTimeout then
            active.watchdogDeadline = os.clock() + watchdogTimeout
            active.timedOut = false
        end
    end

    self:_refreshLoaderState()
    return active
end

function App:clearLoader(force)
    local active = self.loader.active
    local now = os.clock()
    local focusMenuOnClose = false
    local restoreFocusOnClose = false

    if active == nil then
        self:_refreshLoaderState()
        return true
    end

    if force == true or now >= (active.minVisibleUntil or 0) then
        focusMenuOnClose = active.focusMenuOnClose == true
        restoreFocusOnClose = active.restoreFocusOnClose == true
        self:_closeLoaderDialog(active.handle)
        self.loader.active = nil
    else
        active.pendingClose = true
    end

    self:_refreshLoaderState()
    if self.loader.active == nil then
        if focusMenuOnClose == true then
            if self:_modalUiActive() == true then
                self.pendingFocusRestore = true
            else
                self.pendingFocusRestore = false
                self:_focusNavigationButton("menu")
            end
        elseif restoreFocusOnClose == true then
            if self:_modalUiActive() == true then
                self.pendingFocusRestore = true
            else
                self.pendingFocusRestore = true
                self:_restoreAppFocus()
            end
        end
    end
    return true
end

function App:requestLoaderClose()
    local active = self.loader.active

    if active == nil then
        return true
    end

    active.closeRequested = true
    active.pendingClose = true
    active.closeWhenIdle = false
    active.progressValue = 100
    active.watchdogDeadline = nil
    active.timedOut = false
    self:_refreshLoaderState()
    return true
end

function App:isLoaderActive()
    self:_refreshLoaderState()
    return self.loader.active ~= nil
end

function App:_headerNavY()
    return math.max(0, (self.radio.linePaddingTop or 6) - HEADER_NAV_Y_SHIFT)
end

function App:_headerTitleY()
    return self:_headerNavY()
end

function App:_headerBreadcrumbY()
    local metrics = self:_headerMetrics()
    return self:_headerNavY() + metrics.buttonH + HEADER_BREADCRUMB_Y_OFFSET
end

function App:_fitTextToWidth(text, maxWidth)
    local value = trimText(text)
    if value == "" or type(maxWidth) ~= "number" or maxWidth <= 0 then
        return ""
    end

    if not (lcd and lcd.getTextSize) then
        return value
    end

    if lcd.getTextSize(value) <= maxWidth then
        return value
    end

    local ellipsis = "..."
    local clipped = value
    while #clipped > 0 and lcd.getTextSize(clipped .. ellipsis) > maxWidth do
        clipped = clipped:sub(1, -2)
    end

    if clipped == "" then
        return ellipsis
    end

    return clipped .. ellipsis
end

function App:_nodeTitle(node, source)
    if type(node) ~= "table" then
        return nil
    end

    if source == MENU_ROOT_PATH and type(node.headerTitle) == "string" and trimText(node.headerTitle) ~= "" then
        return node.headerTitle
    end

    if type(node.title) == "string" and trimText(node.title) ~= "" then
        return node.title
    end

    return nil
end

function App:_nodeBreadcrumb(node)
    if type(node) ~= "table" then
        return nil
    end

    local breadcrumb = trimText(node.breadcrumb)
    if breadcrumb ~= "" then
        return breadcrumb
    end

    local subtitle = trimText(node.subtitle)
    if subtitle == "" then
        return nil
    end

    local title = trimText(node.title)
    if title ~= "" then
        local suffix = " / " .. title
        if subtitle:sub(-#suffix) == suffix then
            subtitle = trimText(subtitle:sub(1, #subtitle - #suffix))
        elseif subtitle == title then
            subtitle = ""
        end
    end

    if subtitle == "" then
        return nil
    end

    return subtitle
end

function App:_joinBreadcrumb(base, leaf)
    local parts = {}
    local start = trimText(base)

    if start ~= "" then
        for part in start:gmatch("([^/]+)") do
            appendBreadcrumbPart(parts, part)
        end
    end

    appendBreadcrumbPart(parts, leaf)

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, " / ")
end

function App:_breadcrumbForItem(item)
    if type(item) ~= "table" then
        return nil
    end

    if self.currentNodeSource == MENU_ROOT_PATH then
        local rootGroup = item.groupTitle
            or (self.currentNode and self.currentNode.headerTitle)
            or self:_nodeTitle(self.currentNode, self.currentNodeSource)
        rootGroup = trimText(rootGroup)
        if rootGroup ~= "" then
            return rootGroup
        end
        return nil
    end

    return self:_joinBreadcrumb(
        self:_nodeBreadcrumb(self.currentNode),
        self:_nodeTitle(self.currentNode, self.currentNodeSource)
    )
end

function App:_breadcrumbText()
    if self.currentNodeSource == MENU_ROOT_PATH then
        return nil
    end

    return self:_nodeBreadcrumb(self.currentNode)
end

function App:_telemetry()
    if self.telemetryTask == nil and self.framework and self.framework.getTask then
        self.telemetryTask = self.framework:getTask("telemetry")
    end
    return self.telemetryTask
end

function App:_readTelemetry(sensorKey)
    local telemetry = self:_telemetry()
    if not (telemetry and telemetry.getSensor) then
        return nil
    end

    local ok, value = pcall(telemetry.getSensor, telemetry, sensorKey)
    if not ok then
        return nil
    end
    return value
end

function App:_resolveItemValue(item)
    if type(item) ~= "table" then
        return "--"
    end

    if item.kind == "session" then
        return formatValue(self.framework.session:get(item.key, item.default), item.format)
    end

    if item.kind == "telemetry" then
        return formatValue(self:_readTelemetry(item.sensor), item.format)
    end

    if item.kind == "static" then
        return tostring(item.value or "")
    end

    return item.valueHint or ""
end

function App:_itemEnabled(item)
    local visibility = loadMenuVisibilityModule()

    if visibility and type(visibility.itemEnabled) == "function" then
        return visibility.itemEnabled(self.framework, item)
    end

    return type(item) == "table" and item.disabled ~= true
end

function App:_nodeHasMenuItems(node)
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

function App:_currentMenuAccessSignature()
    local visibility = loadMenuVisibilityModule()

    if visibility and type(visibility.accessSignature) == "function" then
        return visibility.accessSignature(self.framework)
    end

    return "default"
end

function App:_currentMenuEnableSignature()
    local visibility = loadMenuVisibilityModule()

    if visibility and type(visibility.connectionMode) == "function" then
        return visibility.connectionMode(self.framework)
    end

    return "default"
end

function App:_reloadCurrentMenuNode()
    local breadcrumb

    if self.currentNodeSource == MENU_ROOT_PATH then
        self.currentNode = self:_loadRootNode()
        self:_afterNodeChanged()
        return
    end

    if type(self.currentNodeSource) ~= "string" then
        return
    end

    if self.currentNodeSource:sub(1, 5) == "page:" or self.currentNodeSource:sub(1, 5) == "leaf:" then
        return
    end

    breadcrumb = self.currentNode and self.currentNode.breadcrumb or nil
    self.currentNode = self:_loadNodeFromSource(self.currentNodeSource)
    if type(self.currentNode) == "table" and type(breadcrumb) == "string" and breadcrumb ~= "" then
        self.currentNode.breadcrumb = breadcrumb
    end
    self:_afterNodeChanged()
end

function App:_refreshMenuAccess()
    local signature = self:_currentMenuAccessSignature()

    if self.menuAccessSignature == signature then
        return
    end

    self.menuAccessSignature = signature
    self:_reloadCurrentMenuNode()
    self:_invalidateForm()
end

function App:_syncMenuButtonStates()
    local buttonIndex = 0
    local items = self.currentNode and self.currentNode.items or nil
    local selectedIndex = self:_getSelectedIndex(self.currentNodeSource)
    local firstEnabledField = nil
    local selectedField = nil
    local selectedEnabled = false
    local signature = self:_currentMenuEnableSignature()
    local signatureChanged = (self.menuEnableSignature ~= signature)
    local item
    local field
    local enabled

    if type(items) ~= "table" then
        self.menuEnableSignature = signature
        return
    end

    if signatureChanged ~= true and self.pendingFocusRestore ~= true then
        return
    end

    for _, item in ipairs(items) do
        if item.kind == "menu" or item.kind == "page" then
            buttonIndex = buttonIndex + 1
            field = self.buttonFields[buttonIndex]
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

    self.menuEnableSignature = signature

    if (signatureChanged or self.pendingFocusRestore == true) and selectedEnabled ~= true and firstEnabledField and firstEnabledField.focus then
        firstEnabledField:focus()
        self.pendingFocusRestore = false
    elseif (signatureChanged or self.pendingFocusRestore == true) and selectedEnabled == true and selectedField and selectedField.focus then
        selectedField:focus()
        self.pendingFocusRestore = false
    end
end

function App:_refreshSnapshot()
    return
end

function App:_collectNodeIconPaths(node)
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

function App:_cancelStartupPreparation()
    if self.callback and self._startupCallback then
        self.callback:clear(self._startupCallback)
    end

    self.startupJob = nil
end

function App:_cancelDeferredMaintenance()
    if self.callback and self._maintenanceCallback then
        self.callback:clear(self._maintenanceCallback)
    end

    self.maintenanceScheduled = false
end

function App:_scheduleStartupPreparation()
    local job = self.startupJob

    if not job or job.scheduled == true or not self.callback then
        return
    end

    job.scheduled = true
    self.callback:now(self._startupCallback, "immediate")
end

function App:_scheduleDeferredMaintenance()
    return
end

function App:_runDeferredMaintenanceStep()
    return
end

function App:_runStartupPreparationStep()
    return
end

function App:_consumePreparedStartupRoot()
    return false
end

function App:_startInitialToolLoad()
    local sensorsTask = self.framework and self.framework.getTask and self.framework:getTask("sensors") or nil

    if sensorsTask and type(sensorsTask.armSensorLostMute) == "function" then
        sensorsTask:armSensorLostMute(STARTUP_SENSOR_LOST_MUTE)
    end

    self.startupLoaderStage = 0
    self:_cancelStartupPreparation()
    self.startupJob = nil
    self:_closeNode(self.currentNode)
    self:setPageDirty(false)
    self.pathStack = {}
    self.currentNodeSource = MENU_ROOT_PATH
    self.currentNode = self:_loadRootNode()
    self:_afterNodeChanged()
    self:_invalidateForm()
end

function App:_loadNodeFromSource(source)
    local node, err = loadLuaTable(source)
    local visibility
    local filtered = {}
    local item
    if not node then
        return {
            title = "Load Error",
            subtitle = tostring(err),
            breadcrumb = self:_nodeBreadcrumb(self.currentNode),
            items = {
                {id = "error", title = "Error", kind = "static", value = tostring(err)}
            }
        }
    end

    visibility = loadMenuVisibilityModule()
    if visibility and type(node.items) == "table" and type(visibility.itemVisible) == "function" then
        for _, item in ipairs(node.items) do
            if visibility.itemVisible(self.framework, item) == true then
                filtered[#filtered + 1] = item
            end
        end
        node.items = filtered
    end

    return node
end

function App:_loadRootNode()
    local node, err = loadLuaTable(MENU_ROOT_PATH)
    local shortcuts
    local visibility
    local shortcutItems
    local merged
    local filtered
    local i
    local insertAt
    local item
    if not node then
        self.rootLoadError = tostring(err)
        return {
            title = "Rotorflight",
            subtitle = tostring(err),
            breadcrumb = nil,
            items = {
                {id = "error", title = "Menu Error", kind = "static", value = tostring(err)}
            }
        }
    end

    self.rootLoadError = nil
    node.breadcrumb = nil

    shortcuts = loadShortcutsModule()
    if shortcuts and type(shortcuts.buildRootItems) == "function" then
        shortcutItems = select(2, pcall(shortcuts.buildRootItems, self.framework))
        if type(shortcutItems) == "table" and #shortcutItems > 0 then
            merged = {}
            insertAt = 0

            for i = 1, #(node.items or {}) do
                merged[#merged + 1] = node.items[i]
                if node.items[i].group == "configuration" then
                    insertAt = #merged
                end
            end

            if insertAt < 1 then
                insertAt = #merged
            end

            for i = #shortcutItems, 1, -1 do
                table.insert(merged, insertAt + 1, shortcutItems[i])
            end

            node.items = merged
        end
    end

    visibility = loadMenuVisibilityModule()
    if visibility and type(node.items) == "table" and type(visibility.itemVisible) == "function" then
        filtered = {}
        for _, item in ipairs(node.items) do
            if visibility.itemVisible(self.framework, item) == true then
                filtered[#filtered + 1] = item
            end
        end
        node.items = filtered
    end

    return node
end

function App:_closeNode(node)
    self:_runNodeHook(node, "close")
end

function App:_openRoot()
    self:_closeNode(self.currentNode)
    self:setPageDirty(false)
    self.pathStack = {}
    self.currentNodeSource = MENU_ROOT_PATH
    self.currentNode = self:_loadRootNode()
    self:_afterNodeChanged()
    self:_invalidateForm()
end

function App:_makeLeafNode(item, breadcrumb)
    return {
        title = item.title or item.id or "Page",
        subtitle = item.subtitle or "Page scaffold",
        breadcrumb = breadcrumb,
        navButtons = item.navButtons or {menu = true, save = false, reload = false, tool = false, help = false},
        items = {
            {id = "status", title = "Status", kind = "static", value = item.status or "Scaffold"},
            {id = "path", title = "Path", kind = "static", value = item.path or item.id or "n/a"},
            {id = "note", title = "Note", kind = "static", value = item.notes or "This page path is preserved while the page implementation is migrated."}
        }
    }
end

function App:_makeLoadErrorNode(item, breadcrumb, err)
    local title = (type(item) == "table" and item.title) or "Load Error"
    local details = {
        {id = "status", title = "Status", kind = "static", value = "Load Error"},
        {id = "path", title = "Path", kind = "static", value = (type(item) == "table" and item.path) or "n/a"},
        {id = "error", title = "Error", kind = "static", value = tostring(err)}
    }
    return {
        title = title,
        subtitle = tostring(err),
        breadcrumb = breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = false},
        buildForm = function(node, app)
            local width = app:_windowSize()
            local radio = app.radio or {}
            local pos = {
                x = math.floor(width * 0.13),
                y = radio.linePaddingTop or 0,
                w = math.floor(width * 0.85),
                h = radio.navbuttonHeight or 30
            }

            for _, entry in ipairs(details) do
                local line = form.addLine(entry.title)
                form.addStaticText(line, pos, tostring(entry.value or ""))
            end
        end,
        items = details
    }
end

function App:_loadPageNode(item, breadcrumb)
    local modulePath
    local pageModule
    local loadErr
    local ok
    local node

    if type(item) ~= "table" or type(item.path) ~= "string" or item.path == "" then
        return self:_makeLeafNode(item or {}, breadcrumb)
    end

    modulePath = "app/modules/" .. item.path
    pageModule, loadErr = loadLuaTable(modulePath)
    if type(pageModule) ~= "table" then
        return self:_makeLoadErrorNode(item, breadcrumb, loadErr)
    end

    if type(pageModule.open) ~= "function" then
        return self:_makeLeafNode(item, breadcrumb)
    end

    ok, node = pcall(pageModule.open, pageModule, {
        app = self,
        framework = self.framework,
        item = item,
        breadcrumb = breadcrumb,
        source = modulePath
    })
    if not ok then
        return self:_makeLoadErrorNode(item, breadcrumb, node)
    end

    if type(node) ~= "table" then
        return self:_makeLoadErrorNode(item, breadcrumb, "page open did not return table")
    end

    if type(node.title) ~= "string" or node.title == "" then
        node.title = item.title or item.id or "Page"
    end
    if type(node.subtitle) ~= "string" or node.subtitle == "" then
        node.subtitle = item.subtitle or "Page"
    end
    if type(node.breadcrumb) ~= "string" or node.breadcrumb == "" then
        node.breadcrumb = breadcrumb
    end
    if type(node.navButtons) ~= "table" then
        node.navButtons = {menu = true, save = false, reload = false, tool = false, help = false}
    end
    if self:_shouldManageDirtySave(node) and type(node.canSave) ~= "function" then
        node.canSave = function()
            return self.pageDirty == true
        end
    end

    return node
end

function App:_enterItem(index, item)
    if type(item) ~= "table" then
        return
    end

    if self:_itemEnabled(item) ~= true then
        return
    end

    local breadcrumb = self:_breadcrumbForItem(item)
    self:_setSelectedIndex(self.currentNodeSource, index)
    self.pathStack[#self.pathStack + 1] = {
        source = self.currentNodeSource,
        breadcrumb = self.currentNode and self.currentNode.breadcrumb or nil
    }

    if item.kind == "page" and self.showLoader then
        self:showLoader({
            kind = "progress",
            title = item.title or item.id or "Loading",
            message = "Loading values.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if item.kind == "menu" and type(item.source) == "string" then
        self.currentNodeSource = item.source
        self.currentNode = self:_loadNodeFromSource(item.source)
        self.currentNode.breadcrumb = breadcrumb
    elseif item.kind == "page" then
        self.currentNodeSource = "page:" .. tostring(item.path or item.id or index)
        self.currentNode = self:_loadPageNode(item, breadcrumb)
        if type(self.currentNode) == "table" and self.currentNode.showLoaderOnEnter == true and self.showLoader then
            local opts = {}
            local key

            for key, value in pairs(self.currentNode.loaderOnEnter or {}) do
                opts[key] = value
            end
            opts.title = opts.title or self.currentNode.baseTitle or self.currentNode.title or item.title or item.id or "Loading"
            self:updateLoader(opts)
        elseif self.loader and self.loader.active then
            self:clearLoader(true)
        end
    else
        self.currentNodeSource = "leaf:" .. tostring(item.id or index)
        self.currentNode = self:_makeLeafNode(item, breadcrumb)
    end

    self:setPageDirty(false)
    if item.kind ~= "menu" then
        self:_requestAppFocusRestore()
    end
    self:_afterNodeChanged()
    self:_invalidateForm()
end

function App:_goBack()
    local previous = self.pathStack[#self.pathStack]
    if not previous then
        return false
    end

    self:_closeNode(self.currentNode)
    self.pathStack[#self.pathStack] = nil
    self.currentNodeSource = previous.source
    if previous.source == MENU_ROOT_PATH then
        self.currentNode = self:_loadRootNode()
    else
        self.currentNode = self:_loadNodeFromSource(previous.source)
        if type(self.currentNode) == "table" then
            self.currentNode.breadcrumb = previous.breadcrumb
        end
    end
    self:setPageDirty(false)
    self:_afterNodeChanged()
    self:_invalidateForm()
    return true
end

function App:_headerTitlePos()
    local radio = self.radio
    local metrics = self:_headerMetrics()
    return {
        x = 0,
        y = self:_headerTitleY(),
        w = metrics.titleWidth,
        h = radio.navbuttonHeight or 30
    }
end

local function normalizeNavButton(value)
    if type(value) == "table" then
        return {
            enabled = value.enabled ~= false,
            icon = value.icon,
            text = value.text
        }
    end

    return {
        enabled = value == true,
        icon = nil,
        text = nil
    }
end

function App:_navButtonsForNode(node)
    local buttons = node and node.navButtons

    if type(buttons) == "table" then
        return {
            menu = normalizeNavButton(buttons.menu),
            save = normalizeNavButton(buttons.save),
            reload = normalizeNavButton(buttons.reload),
            tool = normalizeNavButton(buttons.tool),
            help = normalizeNavButton(buttons.help)
        }
    end

    return {
        menu = normalizeNavButton(true),
        save = normalizeNavButton(false),
        reload = normalizeNavButton(false),
        tool = normalizeNavButton(false),
        help = normalizeNavButton(false)
    }
end

function App:_requestExit()
    if self.framework and self.framework.deactivateApp then
        self.framework:deactivateApp()
    end

    if system and system.exit then
        system.exit()
    end

    return true
end

function App:_addNavigationButtons()
    local metrics = self:_headerMetrics()
    local y = self:_headerNavY()
    local xRight = metrics.width - HEADER_RIGHT_GUTTER
    local atRoot = (#self.pathStack == 0)
    local navConfig = self:_navButtonsForNode(self.currentNode)
    local renderDefs = {}
    local defs = {
        {
            key = "menu",
            text = "Menu",
            compact = false,
            visible = navConfig.menu.enabled == true,
            icon = navConfig.menu.icon,
            press = function()
                self:_handleMenuAction()
            end
        },
        {
            key = "save",
            text = "Save",
            compact = false,
            visible = navConfig.save.enabled == true,
            icon = navConfig.save.icon,
            press = function()
                self:_handleSaveAction()
            end
        },
        {
            key = "reload",
            text = "Reload",
            compact = false,
            visible = navConfig.reload.enabled == true,
            icon = navConfig.reload.icon,
            press = function()
                self:_handleReloadAction()
            end
        },
        {
            key = "tool",
            text = navConfig.tool.text or "*",
            compact = true,
            visible = navConfig.tool.enabled == true,
            icon = navConfig.tool.icon,
            press = function()
                self:_handleToolAction()
            end
        },
        {
            key = "help",
            text = navConfig.help.text or "?",
            compact = true,
            visible = navConfig.help.enabled == true,
            icon = navConfig.help.icon,
            press = function()
                self:_handleHelpAction()
            end
        }
    }

    if self:_collapseNavigation() == true then
        for i = 1, #defs do
            if defs[i].visible == true then
                renderDefs[#renderDefs + 1] = defs[i]
            end
        end
    else
        renderDefs = defs
    end

    for i = #renderDefs, 1, -1 do
        local def = renderDefs[i]
        local bx
        local field
        local width = def.compact == true and metrics.compactW or metrics.buttonW

        bx = xRight - width
        field = form.addButton(nil, {x = bx, y = y, w = width, h = metrics.buttonH}, {
            text = def.text,
            icon = type(def.icon) == "string" and self:_loadMask(def.icon) or nil,
            options = FONT_S,
            paint = NOOP_PAINT,
            press = def.press
        })
        if field and field.enable then
            if def.key == "save" then
                field:enable(self:_canSaveNode(self.currentNode))
            else
                field:enable(def.visible == true)
            end
        end
        self.navFields[def.key] = field
        xRight = bx - 5
    end
end

function App:_addHeader(node)
    local line = form.addLine("")
    local headerTitle = node.title or "Rotorflight"
    if self.currentNodeSource == MENU_ROOT_PATH then
        headerTitle = node.headerTitle or headerTitle
    end
    if type(headerTitle) == "string" and headerTitle ~= "" then
        self.headerTitleField = form.addStaticText(line, self:_headerTitlePos(), headerTitle)
    end
    self:_addNavigationButtons()
end

function App:setHeaderTitle(title)
    local headerTitle = tostring(title or "")
    local node = self.currentNode
    local ok = false

    if type(node) == "table" then
        if self.currentNodeSource == MENU_ROOT_PATH then
            node.headerTitle = headerTitle
        else
            node.title = headerTitle
        end
    end

    if self.headerTitleField and self.headerTitleField.value then
        ok = pcall(self.headerTitleField.value, self.headerTitleField, headerTitle)
    end

    return true
end

function App:_valuePos()
    local width = self:_windowSize()
    local radio = self.radio
    return {
        x = math.floor(width * 0.56),
        y = radio.linePaddingTop or 0,
        w = math.floor(width * 0.34),
        h = radio.navbuttonHeight or 30
    }
end

function App:_addStaticLine(label, value, key)
    local line = form.addLine(label)
    local field = form.addStaticText(line, self:_valuePos(), value)
    if key then
        self.statusFields[key] = field
    end
    return field
end

function App:_buildGridButtons(items)
    local metrics = self:_menuButtonMetrics()
    local iconsize = self:_iconsize()
    local lc = 0
    local y = 0
    local activeGroup = nil
    local buttonIndex = 0
    local rememberedIndex = self:_getSelectedIndex(self.currentNodeSource)
    local firstEnabledField = nil
    local selectedField = nil
    local selectedEnabled = false
    local focused = false

    for _, item in ipairs(items) do
        if item.kind == "menu" or item.kind == "page" then
            buttonIndex = buttonIndex + 1
            local treatAsMixedShortcut = (item._mixedShortcut == true)

            if (not treatAsMixedShortcut) and type(item.group) == "string" and item.group ~= "" and item.group ~= activeGroup then
                activeGroup = item.group
                lc = 0
                if type(item.groupTitle) == "string" and item.groupTitle ~= "" and not (self.currentNodeSource == MENU_ROOT_PATH and buttonIndex == 1) then
                    form.addLine(item.groupTitle)
                end
            end

            if lc == 0 then
                y = form.height() + ((iconsize == 2) and self.radio.buttonPadding or self.radio.buttonPaddingSmall)
            end

            local bx = (metrics.buttonW + metrics.padding) * lc
            local icon = nil
            local selectedIndex = buttonIndex
            local selectedItem = item
            if iconsize ~= 0 and item.image then
                icon = self:_loadMask(item.image)
            end

            local field = form.addButton(nil, {x = bx, y = y, w = metrics.buttonW, h = metrics.buttonH}, {
                text = selectedItem.title or selectedItem.id or ("Item " .. tostring(selectedIndex)),
                icon = icon,
                options = FONT_S,
                paint = NOOP_PAINT,
                press = function()
                    self:_enterItem(selectedIndex, selectedItem)
                end
            })

            self.buttonFields[selectedIndex] = field

            if field and field.enable then
                field:enable(self:_itemEnabled(selectedItem))
            end

            if self:_itemEnabled(selectedItem) == true then
                if firstEnabledField == nil then
                    firstEnabledField = field
                end
                if selectedIndex == rememberedIndex then
                    selectedField = field
                    selectedEnabled = true
                    if focused ~= true and field and field.focus then
                        pcall(field.focus, field)
                        focused = true
                    end
                end
            elseif selectedIndex == rememberedIndex then
                selectedField = field
                selectedEnabled = false
            end

            lc = lc + 1
            if lc == metrics.numPerRow then
                lc = 0
            end
        else
            local line = form.addLine(item.title or item.id or "Value")
            local field = form.addStaticText(line, self:_valuePos(), self:_resolveItemValue(item))
            self.valueFields[#self.valueFields + 1] = {item = item, field = field}
        end
    end

    if focused ~= true then
        if selectedEnabled == true and selectedField and selectedField.focus then
            pcall(selectedField.focus, selectedField)
        elseif firstEnabledField and firstEnabledField.focus then
            pcall(firstEnabledField.focus, firstEnabledField)
        end
    end
end

function App:_buildNodeForm()
    local node = self.currentNode or self:_loadRootNode()
    local built
    local hasCustomBuilder
    local iconPaths
    local index

    if self:_nodeHasMenuItems(node) == true then
        iconPaths = self:_collectNodeIconPaths(node)
        for index = 1, #iconPaths do
            self:_loadMask(iconPaths[index])
        end
    end

    safeFormClear()
    self:_clearFormRefs()
    self.formBuildCount = (self.formBuildCount or 0) + 1

    self:_addHeader(node)
    built, hasCustomBuilder = self:_runNodeHook(node, "buildForm")
    if hasCustomBuilder then
        if built == false then
            self:_addStaticLine("Error", "Page builder failed")
        end
        self:_syncSaveButtonState()
        if self.pendingFocusRestore == true then
            self:_restoreAppFocus()
        end
        return
    end

    self:_buildGridButtons(node.items or {})
    if self:_nodeHasMenuItems(node) == true then
        self.menuEnableSignature = self:_currentMenuEnableSignature()
        self.pendingFocusRestore = false
    end
    self:_syncSaveButtonState()
    if self.pendingFocusRestore == true then
        self:_restoreAppFocus()
    end
end

function App:_rebuildFormIfNeeded()
    if self.formDirty ~= true then
        return
    end
    self.formDirty = false
    self:_buildNodeForm()
end

function App:_updateValueFields()
    for _, entry in ipairs(self.valueFields) do
        if entry.field and entry.field.value then
            entry.field:value(self:_resolveItemValue(entry.item))
        end
    end
end

function App:wakeup()
    if self.callback then
        self.callback:wakeup(APP_CALLBACK_WAKEUP_OPTIONS)
    end

    self:_refreshSnapshot()

    if self.pendingDialogAction and self:_modalUiActive() ~= true and self.pendingDialogActionReady ~= true then
        self.pendingDialogActionReady = true
    elseif self.pendingDialogAction and self:_modalUiActive() ~= true then
        local pendingAction = self.pendingDialogAction
        self.pendingDialogAction = nil
        self.pendingDialogActionReady = false
        pendingAction()
    elseif self:_modalUiActive() == true then
        self.pendingDialogActionReady = false
    end

    if self.currentNode == nil then
        self.currentNodeSource = MENU_ROOT_PATH
        self.currentNode = self:_loadRootNode()
        self.pathStack = {}
        self:_afterNodeChanged()
        self:_invalidateForm()
    end

    if self:_nodeHasMenuItems(self.currentNode) == true then
        self:_refreshMenuAccess()
    end
    self:_rebuildFormIfNeeded()
    if self:_nodeHasMenuItems(self.currentNode) == true then
        self:_syncMenuButtonStates()
    end
    self:_runNodeHook(self.currentNode, "wakeup")
    self:_updateValueFields()
    self:_refreshLoaderState()
end

function App:paint()
    if self.callback then
        self.callback:wakeup(APP_RENDER_CALLBACK_WAKEUP_OPTIONS)
    end

    self:_runNodeHook(self.currentNode, "paint")

    local breadcrumb = self:_breadcrumbText()
    local width

    if breadcrumb ~= nil and lcd and lcd.drawText and lcd.font then
        width = self:_windowSize()
        breadcrumb = self:_fitTextToWidth(breadcrumb, math.max(40, width - 8))
        if breadcrumb ~= "" then
            lcd.font(FONT_XXS or FONT_XS or FONT_STD)
            if lcd.color and lcd.RGB then
                lcd.color(lcd.RGB(170, 170, 170))
            end
            lcd.drawText(0, self:_headerBreadcrumbY(), breadcrumb)
        end
    end
end

function App:event(category, value, x, y)
    local _ = x
    _ = y

    if isRotaryNavigationEvent(value) == true then
        self.pendingFocusRestore = false
    end

    if (self.modalDialogDepth or 0) > 0 then
        return false
    end

    if isMenuKeyEvent(value) ~= true then
        self.returnMenuArmed = false
    end

    if isExitLongEvent(value) then
        suppressFollowupKeyEvent(value)
        return self:_requestExit()
    end
    if isMenuKeyEvent(value) then
        if self.returnMenuArmed == true then
            self.returnMenuArmed = false
            return self:_handleMenuAction()
        end
        if self:_focusNavigationButton("menu") == true then
            self.returnMenuArmed = true
            suppressFollowupKeyEvent(value)
            return true
        end
        return self:_handleMenuAction()
    end
    if isCloseEvent(category, value) then
        return self:_handleMenuAction()
    end
    if isSaveKeyEvent(value) then
        if self.loader and self.loader.active and self.loader.active.modal == true then
            suppressFollowupKeyEvent(value)
            return true
        end
        if self:_navButtonsForNode(self.currentNode).save.enabled == true then
            self:_handleSaveAction()
        end
        suppressFollowupKeyEvent(value)
        return true
    end
    if self.loader and self.loader.active and self.loader.active.modal == true then
        return true
    end
    if self:_runNodeHook(self.currentNode, "event", category, value, x, y) == true then
        return true
    end
    return false
end

function App:onActivate()
    DIRTY_OWNER = self
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    if self.loader.active then
        self:_closeLoaderDialog(self.loader.active.handle)
    end
    self.loader.active = nil
    self.loader.status = nil
    self.loader.signature = nil
    self.menuAccessSignature = self:_currentMenuAccessSignature()
    self.menuEnableSignature = self:_currentMenuEnableSignature()
    self.startupLoaderStage = 0
    self:_cancelStartupPreparation()
    self:_cancelDeferredMaintenance()
    self.maintenancePhase = 0
    self:_startInitialToolLoad()
end

function App:onDeactivate()
    if DIRTY_OWNER == self then
        DIRTY_OWNER = nil
    end
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    if self.loader.active then
        self:_closeLoaderDialog(self.loader.active.handle)
    end
    self.loader.active = nil
    self.loader.status = nil
    self.loader.signature = nil
    self.startupLoaderStage = 0
    self:_cancelStartupPreparation()
    self:_cancelDeferredMaintenance()
    self.maintenancePhase = 0
    if self.callback then
        self.callback:clearAll()
    end
    self:_closeNode(self.currentNode)
    safeFormClear()
    self:_clearFormRefs()
    self.currentNode = nil
    self.pathStack = {}
    self.maskCache = {}
    self.maskCacheOrder = {}
    self:_savePreferences()
    pcall(collectgarbage, "collect")
end

function App:close()
    if DIRTY_OWNER == self then
        DIRTY_OWNER = nil
    end
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    if self.loader.active then
        self:_closeLoaderDialog(self.loader.active.handle)
    end
    self.loader.active = nil
    self.loader.status = nil
    self.loader.signature = nil
    self.startupLoaderStage = 0
    self:_cancelStartupPreparation()
    self:_cancelDeferredMaintenance()
    if self.callback then
        self.callback:clearAll()
    end
    self:_closeNode(self.currentNode)
    safeFormClear()
    self:_clearFormRefs()
    self.currentNode = nil
    self.pathStack = nil
    self.snapshot = nil
    self.telemetryTask = nil
    self.maskCache = nil
    self.maskCacheOrder = nil
    self.callback = nil
    self._maintenanceCallback = nil
    self:_savePreferences()
    self.framework = nil
    collectgarbage("collect")
end

return App
