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
        getCallback = opts.getCallback,
        armStartupSensors = opts.armStartupSensors,
        resetLoader = opts.resetLoader,
        resetMenu = opts.resetMenu,
        primeMenuSignatures = opts.primeMenuSignatures,
        currentMenuAccessSignature = opts.currentMenuAccessSignature,
        currentMenuEnableSignature = opts.currentMenuEnableSignature,
        clearAllCallbacks = opts.clearAllCallbacks,
        closeCurrentNode = opts.closeCurrentNode,
        clearForm = opts.clearForm,
        resetFormHost = opts.resetFormHost,
        resetPageHost = opts.resetPageHost,
        resetCurrentNodeFallback = opts.resetCurrentNodeFallback,
        clearMaskCache = opts.clearMaskCache,
        nilMaskCache = opts.nilMaskCache,
        clearAppModuleCaches = opts.clearAppModuleCaches,
        savePreferences = opts.savePreferences,
        collectGarbage = opts.collectGarbage,
        loadRoot = opts.loadRoot,
        setPageDirty = opts.setPageDirty,
        onAfterNodeChanged = opts.afterNodeChanged,
        invalidateForm = opts.invalidateForm,
        resetSnapshot = opts.resetSnapshot,
        resetTelemetryTask = opts.resetTelemetryTask,
        resetFramework = opts.resetFramework,
        state = {
            startupLoaderStage = 0,
            startupJob = nil,
            maintenanceScheduled = false,
            maintenancePhase = 0
        }
    }, controller_mt)
end

function controller:_sync()
    if type(self.onSyncState) == "function" then
        self.onSyncState(self.state)
    end
end

function controller:afterNodeChanged()
    if type(self.onAfterNodeChanged) == "function" then
        return self.onAfterNodeChanged()
    end
    return nil
end

function controller:cancelStartupPreparation()
    self.state.startupJob = nil
    self:_sync()
end

function controller:cancelDeferredMaintenance()
    self.state.maintenanceScheduled = false
    self:_sync()
end

function controller:startInitialToolLoad()
    if type(self.armStartupSensors) == "function" then
        self.armStartupSensors()
    end

    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self.state.startupJob = nil

    if type(self.loadRoot) == "function" then
        self.loadRoot()
    end

    self:_sync()
end

function controller:activate()
    if type(self.resetLoader) == "function" then
        self.resetLoader()
    end
    if type(self.resetMenu) == "function" then
        self.resetMenu()
    end
    if type(self.primeMenuSignatures) == "function" then
        self.primeMenuSignatures(
            type(self.currentMenuAccessSignature) == "function" and self.currentMenuAccessSignature() or "default",
            type(self.currentMenuEnableSignature) == "function" and self.currentMenuEnableSignature() or "default"
        )
    end
    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self:cancelDeferredMaintenance()
    self.state.maintenancePhase = 0
    self:startInitialToolLoad()
    self:_sync()
end

function controller:deactivate()
    if type(self.resetLoader) == "function" then
        self.resetLoader()
    end
    if type(self.resetMenu) == "function" then
        self.resetMenu()
    end
    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self:cancelDeferredMaintenance()
    self.state.maintenancePhase = 0
    if type(self.clearAllCallbacks) == "function" then
        self.clearAllCallbacks()
    end
    if type(self.closeCurrentNode) == "function" then
        self.closeCurrentNode()
    end
    if type(self.clearForm) == "function" then
        self.clearForm()
    end
    if type(self.resetFormHost) == "function" then
        self.resetFormHost()
    end
    if type(self.resetPageHost) == "function" then
        self.resetPageHost()
    else
        if type(self.resetCurrentNodeFallback) == "function" then
            self.resetCurrentNodeFallback(false)
        end
    end
    if type(self.clearMaskCache) == "function" then
        self.clearMaskCache()
    end
    if type(self.clearAppModuleCaches) == "function" then
        self.clearAppModuleCaches()
    end
    if type(self.savePreferences) == "function" then
        self.savePreferences()
    end
    if type(self.collectGarbage) == "function" then
        self.collectGarbage("collect")
    end
    self:_sync()
end

function controller:close()
    if type(self.resetLoader) == "function" then
        self.resetLoader()
    end
    if type(self.resetMenu) == "function" then
        self.resetMenu()
    end
    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self:cancelDeferredMaintenance()
    if type(self.clearAllCallbacks) == "function" then
        self.clearAllCallbacks()
    end
    if type(self.closeCurrentNode) == "function" then
        self.closeCurrentNode()
    end
    if type(self.clearForm) == "function" then
        self.clearForm()
    end
    if type(self.resetFormHost) == "function" then
        self.resetFormHost()
    end
    if type(self.resetPageHost) == "function" then
        self.resetPageHost()
    else
        if type(self.resetCurrentNodeFallback) == "function" then
            self.resetCurrentNodeFallback(true)
        end
    end
    if type(self.resetSnapshot) == "function" then
        self.resetSnapshot()
    end
    if type(self.resetTelemetryTask) == "function" then
        self.resetTelemetryTask()
    end
    if type(self.nilMaskCache) == "function" then
        self.nilMaskCache()
    end
    if type(self.clearAppModuleCaches) == "function" then
        self.clearAppModuleCaches()
    end
    if type(self.savePreferences) == "function" then
        self.savePreferences()
    end
    if type(self.resetFramework) == "function" then
        self.resetFramework()
    end
    if type(self.collectGarbage) == "function" then
        self.collectGarbage("collect")
    end
    self:_sync()
end

return controller
