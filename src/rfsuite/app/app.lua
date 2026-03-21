--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local App = {}
local callbackFactory = require("framework.core.callback")
local AudioLib = require("lib.audio")
local sharedContextFactory
local loaderControllerFactory
local pageHostControllerFactory
local menuControllerFactory
local formHostControllerFactory
local navigationControllerFactory
local actionsControllerFactory
local eventsControllerFactory
local lifecycleControllerFactory

do
    local ok, mod = pcall(require, "app.shared.context")
    if ok and type(mod) == "table" then
        sharedContextFactory = mod
    else
        local chunk = assert(loadfile("app/shared/context.lua"))
        sharedContextFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.loader")
    if ok and type(mod) == "table" then
        loaderControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/loader.lua"))
        loaderControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.page_host")
    if ok and type(mod) == "table" then
        pageHostControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/page_host.lua"))
        pageHostControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.menu")
    if ok and type(mod) == "table" then
        menuControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/menu.lua"))
        menuControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.form_host")
    if ok and type(mod) == "table" then
        formHostControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/form_host.lua"))
        formHostControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.navigation")
    if ok and type(mod) == "table" then
        navigationControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/navigation.lua"))
        navigationControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.actions")
    if ok and type(mod) == "table" then
        actionsControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/actions.lua"))
        actionsControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.events")
    if ok and type(mod) == "table" then
        eventsControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/events.lua"))
        eventsControllerFactory = chunk()
    end
end

do
    local ok, mod = pcall(require, "app.controllers.lifecycle")
    if ok and type(mod) == "table" then
        lifecycleControllerFactory = mod
    else
        local chunk = assert(loadfile("app/controllers/lifecycle.lua"))
        lifecycleControllerFactory = chunk()
    end
end

local MENU_ROOT_PATH = "app/menu/root.lua"
local MASK_CACHE_MAX = 32
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
local SHARED_MASK_CACHE = {}
local SHARED_MASK_CACHE_ORDER = {}
local LUA_TABLE_CACHE = {}

local function unloadModuleIfLoaded(name)
    if type(name) ~= "string" or name == "" then
        return
    end
    if package and type(package.loaded) == "table" then
        package.loaded[name] = nil
    end
end

local function clearAppModuleCaches()
    -- Keep helper modules warm across app open/close cycles.
    -- Repeated unload/reload churn costs more RAM over time on radio than
    -- the small stable footprint of these shared helpers.
    return
end

local function cloneTable(value, seen)
    local copy
    local key
    local nestedSeen = seen or {}

    if type(value) ~= "table" then
        return value
    end
    if nestedSeen[value] then
        return nestedSeen[value]
    end

    copy = {}
    nestedSeen[value] = copy

    for key, entry in pairs(value) do
        copy[cloneTable(key, nestedSeen)] = cloneTable(entry, nestedSeen)
    end

    return copy
end

local function shouldCloneLoadedTable(path)
    return type(path) == "string" and path:sub(1, 9) == "app/menu/"
end

local function loadLuaTable(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid path"
    end

    if LUA_TABLE_CACHE[path] ~= nil then
        if shouldCloneLoadedTable(path) then
            return cloneTable(LUA_TABLE_CACHE[path])
        end
        return LUA_TABLE_CACHE[path]
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

    LUA_TABLE_CACHE[path] = value

    if shouldCloneLoadedTable(path) then
        return cloneTable(value)
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
    self.shared = sharedContextFactory.new(self)
    self.telemetryTask = nil
    self.menuAccessSignature = nil
    self.menuEnableSignature = nil
    self.startupLoaderStage = 0
    self.startupJob = nil
    self.maintenanceScheduled = false
    self.maintenancePhase = 0
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
    self.maskCache = SHARED_MASK_CACHE
    self.maskCacheOrder = SHARED_MASK_CACHE_ORDER
    self.pageDirty = false
    self.dirtySuspendDepth = 0
    self.returnMenuArmed = false
    self.pendingFocusRestore = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    self.formBuildCount = 0
    self.mspTask = nil
    self.loaderSpeed = {
        VSLOW = 0.5,
        SLOW = 0.75,
        DEFAULT = 1.0,
        FAST = 2.3,
        VFAST = 2.8
    }
    self.loaderController = loaderControllerFactory.new(self.shared, {
        minVisible = LOADER_MIN_VISIBLE,
        fallbackClose = LOADER_FALLBACK_CLOSE,
        progressMultiplier = LOADER_PROGRESS_MULTIPLIER,
        menuProgressFactor = MENU_LOADER_PROGRESS_FACTOR,
        timeoutMessage = LOADER_TIMEOUT_MESSAGE,
        timeoutDetail = LOADER_TIMEOUT_DETAIL,
        transferPlaceholder = MSP_DEBUG_PLACEHOLDER,
        audio = AudioLib,
        generalBool = function(key, default)
            return self:_generalBool(key, default)
        end,
        mspTask = function()
            return self:_msp()
        end,
        modalUiActive = function()
            return self:_modalUiActive()
        end,
        focusNavigationButton = function(key)
            return self:_focusNavigationButton(key)
        end,
        restoreAppFocus = function()
            return self:_restoreAppFocus()
        end
    })
    self.loader = self.loaderController.state
    self.menuController = menuControllerFactory.new(self.shared, {
        menuRootPath = MENU_ROOT_PATH,
        onSyncState = function(state)
            self:_syncMenuState(state)
        end,
        currentMenuAccessSignature = function()
            return self:_currentMenuAccessSignatureLegacy()
        end,
        currentMenuEnableSignature = function()
            return self:_currentMenuEnableSignatureLegacy()
        end,
        itemEnabled = function(item)
            return self:_itemEnabled(item)
        end,
        reloadCurrentMenuNode = function()
            return self:_reloadCurrentMenuNode()
        end,
        invalidateForm = function()
            return self:_invalidateForm()
        end,
        modalUiActive = function()
            return self:_modalUiActive()
        end,
        focusNavigationButton = function(key)
            return self:_focusNavigationButton(key)
        end
    })
    self:_syncMenuState(self.menuController.state)
    self.navigationController = navigationControllerFactory.new(self.shared, {
        getCurrentNode = function()
            return self.currentNode
        end,
        getCurrentNodeSource = function()
            return self.currentNodeSource
        end,
        getPathStack = function()
            return self.pathStack
        end,
        headerMetrics = function()
            return self:_headerMetrics()
        end,
        headerNavY = function()
            return self:_headerNavY()
        end,
        headerTitlePos = function()
            return self:_headerTitlePos()
        end,
        collapseNavigation = function()
            return self:_collapseNavigation()
        end,
        loadMask = function(path)
            return self:_loadMask(path)
        end,
        canSaveNode = function(node)
            return self:_canSaveNode(node)
        end,
        handleMenuAction = function()
            return self:_handleMenuAction()
        end,
        handleSaveAction = function()
            return self:_handleSaveAction()
        end,
        handleReloadAction = function()
            return self:_handleReloadAction()
        end,
        handleToolAction = function()
            return self:_handleToolAction()
        end,
        handleHelpAction = function()
            return self:_handleHelpAction()
        end,
        getNavFields = function()
            return self.navFields
        end,
        setNavField = function(key, field)
            self.navFields[key] = field
            if self.formHost and self.formHost._sync then
                self.formHost:_sync()
            end
        end,
        getHeaderTitleField = function()
            return self.headerTitleField
        end,
        setHeaderTitleField = function(field)
            self.headerTitleField = field
            if self.formHost and self.formHost.state then
                self.formHost.state.headerTitleField = field
                if self.formHost._sync then
                    self.formHost:_sync()
                end
            end
        end
    })
    self.actionsController = actionsControllerFactory.new(self.shared, {
        getCurrentNode = function()
            return self.currentNode
        end,
        getPathStack = function()
            return self.pathStack
        end,
        runNodeHook = function(node, hookName, ...)
            return self:_runNodeHook(node, hookName, ...)
        end,
        canSaveNode = function(node)
            return self:_canSaveNode(node)
        end,
        confirmBeforeSave = function()
            return self:_confirmBeforeSave()
        end,
        confirmBeforeReload = function()
            return self:_confirmBeforeReload()
        end,
        setPageDirty = function(isDirty)
            return self:setPageDirty(isDirty)
        end,
        requestExit = function()
            return self:_requestExit()
        end,
        goBack = function()
            return self:_goBack()
        end
    })
    self.eventsController = eventsControllerFactory.new(self.shared, {
        clearFocusRestore = function()
            if self.menuController and self.menuController.clearFocusRestore then
                self.menuController:clearFocusRestore()
            else
                self.pendingFocusRestore = false
            end
        end,
        getModalDialogDepth = function()
            return self.modalDialogDepth or 0
        end,
        isLoaderModalActive = function()
            return self.loader and self.loader.active and self.loader.active.modal == true
        end,
        getReturnMenuArmed = function()
            return self.returnMenuArmed == true
        end,
        setReturnMenuArmed = function(value)
            self.returnMenuArmed = value == true
        end,
        requestExit = function()
            return self:_requestExit()
        end,
        focusNavigationButton = function(key)
            return self:_focusNavigationButton(key)
        end,
        handleMenuAction = function()
            return self:_handleMenuAction()
        end,
        handleSaveAction = function()
            return self:_handleSaveAction()
        end,
        navButtonsForNode = function(node)
            return self:_navButtonsForNode(node)
        end,
        getCurrentNode = function()
            return self.currentNode
        end,
        runNodeHook = function(node, hookName, ...)
            return self:_runNodeHook(node, hookName, ...)
        end
    })
    self.lifecycleController = lifecycleControllerFactory.new(self.shared, {
        onSyncState = function(state)
            self:_syncLifecycleState(state)
        end,
        armStartupSensors = function()
            local sensorsTask = self.framework and self.framework.getTask and self.framework:getTask("sensors") or nil
            if sensorsTask and type(sensorsTask.armSensorLostMute) == "function" then
                sensorsTask:armSensorLostMute(STARTUP_SENSOR_LOST_MUTE)
            end
        end,
        resetLoader = function()
            if self.loaderController then
                self.loaderController:reset()
            end
        end,
        resetMenu = function()
            if self.menuController then
                self.menuController:reset()
            end
        end,
        primeMenuSignatures = function(accessSig, enableSig)
            if self.menuController and self.menuController.primeSignatures then
                self.menuController:primeSignatures(accessSig, enableSig)
            else
                self.menuAccessSignature = accessSig
                self.menuEnableSignature = enableSig
            end
        end,
        currentMenuAccessSignature = function()
            return self:_currentMenuAccessSignatureLegacy()
        end,
        currentMenuEnableSignature = function()
            return self:_currentMenuEnableSignatureLegacy()
        end,
        clearAllCallbacks = function()
            if self.callback then
                self.callback:clearAll()
            end
        end,
        closeCurrentNode = function()
            return self:_closeNode(self.currentNode)
        end,
        clearForm = function()
            safeFormClear()
        end,
        resetFormHost = function()
            if self.formHost then
                self.formHost:reset()
            end
        end,
        resetPageHost = function()
            if self.pageHost then
                self.pageHost:reset()
            end
        end,
        resetCurrentNodeFallback = function(nilPathStack)
            self.currentNode = nil
            self.pathStack = nilPathStack and nil or {}
        end,
        clearMaskCache = function()
            -- Keep masks warm across app close/open cycles.
            return
        end,
        nilMaskCache = function()
            -- Keep masks warm across app close/open cycles.
            return
        end,
        clearAppModuleCaches = function()
            clearAppModuleCaches()
        end,
        savePreferences = function()
            return self:_savePreferences()
        end,
        collectGarbage = function(mode)
            if mode == "collect" then
                pcall(collectgarbage, "collect")
            else
                pcall(collectgarbage, "step", 64)
            end
        end,
        loadRoot = function()
            if self.pageHost then
                self.pageHost:openRoot()
            else
                self:_closeNode(self.currentNode)
                self:setPageDirty(false)
                self.pathStack = {}
                self.currentNodeSource = MENU_ROOT_PATH
                self.currentNode = self:_loadRootNode()
                self:_afterNodeChanged()
                self:_invalidateForm()
            end
        end,
        resetSnapshot = function()
            self.snapshot = nil
        end,
        resetTelemetryTask = function()
            self.telemetryTask = nil
        end,
        resetFramework = function()
            self.framework = nil
        end
    })
    self:_syncLifecycleState(self.lifecycleController.state)
    self.formHost = formHostControllerFactory.new(self.shared, {
        onSyncState = function(state)
            self:_syncFormHostState(state)
        end,
        clearForm = function()
            safeFormClear()
        end,
        nodeHasMenuItems = function(node)
            return self:_nodeHasMenuItems(node)
        end,
        collectNodeIconPaths = function(node)
            return self:_collectNodeIconPaths(node)
        end,
        loadMask = function(path)
            return self:_loadMask(path)
        end,
        loadRootNode = function()
            return self:_loadRootNode()
        end,
        addHeader = function(node)
            return self:_addHeader(node)
        end,
        runNodeHook = function(node, hookName, ...)
            return self:_runNodeHook(node, hookName, ...)
        end,
        addStaticLine = function(label, value, key)
            return self:_addStaticLine(label, value, key)
        end,
        buildGridButtons = function(items)
            return self:_buildGridButtons(items)
        end,
        currentMenuEnableSignature = function()
            return self:_currentMenuEnableSignature()
        end,
        setMenuEnableSignature = function(signature)
            if self.menuController and self.menuController.setMenuEnableSignature then
                self.menuController:setMenuEnableSignature(signature)
            else
                self.menuEnableSignature = signature
            end
        end,
        clearMenuFocusRestore = function()
            if self.menuController and self.menuController.clearFocusRestore then
                self.menuController:clearFocusRestore()
            else
                self.pendingFocusRestore = false
            end
        end,
        syncSaveButtonState = function()
            return self:_syncSaveButtonState()
        end,
        restoreAppFocus = function()
            if self.pendingFocusRestore == true then
                return self:_restoreAppFocus()
            end
            return false
        end,
        resolveItemValue = function(item)
            return self:_resolveItemValue(item)
        end
    })
    self:_syncFormHostState(self.formHost.state)
    self.pageHost = pageHostControllerFactory.new(self.shared, {
        menuRootPath = MENU_ROOT_PATH,
        onSyncState = function(state)
            self:_syncPageHostState(state)
        end,
        loadRootNode = function()
            return self:_loadRootNode()
        end,
        loadNodeFromSource = function(source)
            return self:_loadNodeFromSource(source)
        end,
        loadPageNode = function(item, breadcrumb)
            return self:_loadPageNode(item, breadcrumb)
        end,
        makeLeafNode = function(item, breadcrumb)
            return self:_makeLeafNode(item, breadcrumb)
        end,
        closeNode = function(node)
            return self:_closeNode(node)
        end,
        afterNodeChanged = function()
            return self:_afterNodeChanged()
        end,
        invalidateForm = function()
            return self:_invalidateForm()
        end,
        setPageDirty = function(value)
            return self:setPageDirty(value)
        end,
        requestAppFocusRestore = function()
            return self:_requestAppFocusRestore()
        end,
        setSelectedIndex = function(source, index)
            return self:_setSelectedIndex(source, index)
        end,
        showLoader = function(options)
            return self:showLoader(options)
        end,
        updateLoader = function(options)
            return self:updateLoader(options)
        end,
        clearLoader = function(force)
            return self:clearLoader(force)
        end
    })
    self:_syncPageHostState(self.pageHost.state)
    self.ui = self:_createUiBridge()
    self:_installDirtyCallbackWrappers()
end

function App:_clearFormRefs()
    self.formHost:clearFormRefs()
end

function App:_syncPageHostState(state)
    local hostState = state or (self.pageHost and self.pageHost.state) or {}

    self.currentNode = hostState.currentNode
    self.currentNodeSource = hostState.currentNodeSource or MENU_ROOT_PATH
    self.pathStack = hostState.pathStack or {}
end

function App:_syncMenuState(state)
    local menuState = state or (self.menuController and self.menuController.state) or {}

    self.menuAccessSignature = menuState.menuAccessSignature
    self.menuEnableSignature = menuState.menuEnableSignature
    self.pendingFocusRestore = menuState.pendingFocusRestore == true
end

function App:_syncFormHostState(state)
    local formState = state or (self.formHost and self.formHost.state) or {}

    self.formDirty = formState.formDirty == true
    self.formBuildCount = formState.formBuildCount or 0
    self.statusFields = formState.statusFields or {}
    self.valueFields = formState.valueFields or {}
    self.buttonFields = formState.buttonFields or {}
    self.navFields = formState.navFields or {}
    self.headerTitleField = formState.headerTitleField
end

function App:_syncLifecycleState(state)
    local lifecycleState = state or (self.lifecycleController and self.lifecycleController.state) or {}

    self.startupLoaderStage = lifecycleState.startupLoaderStage or 0
    self.startupJob = lifecycleState.startupJob
    self.maintenanceScheduled = lifecycleState.maintenanceScheduled == true
    self.maintenancePhase = lifecycleState.maintenancePhase or 0
end

function App:_invalidateForm()
    self.formHost:invalidate()
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
    return self.menuController:getSelectedIndex(source)
end

function App:_setSelectedIndex(source, index)
    self.menuController:setSelectedIndex(source, index)
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
    return self.lifecycleController:afterNodeChanged()
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
    return self.navigationController:syncSaveButtonState()
end

function App:_focusNavigationButton(key)
    return self.navigationController:focusNavigationButton(key)
end

function App:_modalUiActive()
    return (self.loader and self.loader.active and self.loader.active.modal == true)
        or ((self.modalDialogDepth or 0) > 0)
end

function App:_requestAppFocusRestore()
    self.menuController:requestFocusRestore()
end

function App:_restoreAppFocus()
    return self.menuController:restoreFocus(self.currentNode, self.currentNodeSource, self.buttonFields or {})
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

function App:_handleSaveAction()
    return self.actionsController:handleSaveAction()
end

function App:_handleReloadAction()
    return self.actionsController:handleReloadAction()
end

function App:_handleMenuAction()
    return self.actionsController:handleMenuAction()
end

function App:_handleToolAction()
    return self.actionsController:handleToolAction()
end

function App:_handleHelpAction()
    return self.actionsController:handleHelpAction()
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
    if self.loaderController then
        return self.loaderController:refresh()
    end
    return nil
end

function App:showLoader(options)
    if self.loaderController then
        return self.loaderController:show(options)
    end
    return nil
end

function App:updateLoader(options)
    if self.loaderController then
        return self.loaderController:update(options)
    end
    return nil
end

function App:clearLoader(force)
    if self.loaderController then
        return self.loaderController:clear(force)
    end
    return true
end

function App:requestLoaderClose()
    if self.loaderController then
        self.loaderController:requestClose()
    end
    return true
end

function App:isLoaderActive()
    if self.loaderController then
        return self.loaderController:isActive()
    end
    return false
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
    return self.menuController:nodeHasMenuItems(node)
end

function App:_currentMenuAccessSignatureLegacy()
    local visibility = loadMenuVisibilityModule()

    if visibility and type(visibility.accessSignature) == "function" then
        return visibility.accessSignature(self.framework)
    end

    return "default"
end

function App:_currentMenuAccessSignature()
    return self.menuController.currentMenuAccessSignature()
end

function App:_currentMenuEnableSignatureLegacy()
    local visibility = loadMenuVisibilityModule()

    if visibility and type(visibility.connectionMode) == "function" then
        return visibility.connectionMode(self.framework)
    end

    return "default"
end

function App:_currentMenuEnableSignature()
    return self.menuController.currentMenuEnableSignature()
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
    self.menuController:refreshMenuAccess()
end

function App:_syncMenuButtonStates()
    self.menuController:syncButtonStates(self.currentNode, self.currentNodeSource, self.buttonFields or {})
end

function App:_collectNodeIconPaths(node)
    return self.menuController:collectNodeIconPaths(node)
end

function App:_cancelStartupPreparation()
    return self.lifecycleController:cancelStartupPreparation()
end

function App:_cancelDeferredMaintenance()
    return self.lifecycleController:cancelDeferredMaintenance()
end

function App:_startInitialToolLoad()
    return self.lifecycleController:startInitialToolLoad()
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

function App:_releaseNodeMemory(node)
    if type(node) ~= "table" then
        return
    end

    node.app = nil
    node.framework = nil
    node.items = nil
    node.state = nil
    node.loaderOnEnter = nil
    node.navButtons = nil
    node.buildForm = nil
    node.wakeup = nil
    node.paint = nil
    node.event = nil
    node.save = nil
    node.reload = nil
    node.menu = nil
    node.tool = nil
    node.help = nil
    node.canSave = nil
    node.close = nil
end

function App:_closeNode(node)
    self:_runNodeHook(node, "close")
    self:_releaseNodeMemory(node)
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

    self.pageHost:enterItem(index, item, breadcrumb)
end

function App:_goBack()
    return self.pageHost:goBack()
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

function App:_navButtonsForNode(node)
    return self.navigationController:buttonsForNode(node)
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
    return self.navigationController:addNavigationButtons()
end

function App:_addHeader(node)
    return self.navigationController:addHeader(node, MENU_ROOT_PATH)
end

function App:setHeaderTitle(title)
    return self.navigationController:setHeaderTitle(title, MENU_ROOT_PATH)
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
    return self.formHost:build(self.currentNode or self:_loadRootNode())
end

function App:_rebuildFormIfNeeded()
    return self.formHost:rebuildIfNeeded(self.currentNode or self:_loadRootNode())
end

function App:_updateValueFields()
    return self.formHost:updateValueFields()
end

function App:wakeup()
    if self.callback then
        self.callback:wakeup(APP_CALLBACK_WAKEUP_OPTIONS)
    end

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
        self.pageHost:ensureCurrentNode()
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
    return self.eventsController:route(category, value, x, y)
end

function App:onActivate()
    DIRTY_OWNER = self
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    self.lifecycleController:activate()
end

function App:onDeactivate()
    if DIRTY_OWNER == self then
        DIRTY_OWNER = nil
    end
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    self.lifecycleController:deactivate()
end

function App:close()
    if DIRTY_OWNER == self then
        DIRTY_OWNER = nil
    end
    self.returnMenuArmed = false
    self.pendingDialogAction = nil
    self.pendingDialogActionReady = false
    self.modalDialogDepth = 0
    self.lifecycleController:close()
    self.callback = nil
    self.formHost = nil
    self.navigationController = nil
    self.actionsController = nil
    self.eventsController = nil
    self.lifecycleController = nil
    self.loaderController = nil
    self.menuController = nil
    self.pageHost = nil
    self.shared = nil
end

return App
