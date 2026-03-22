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
            startupLoaderStage = 0,
            startupJob = nil,
            maintenanceScheduled = false,
            maintenancePhase = 0
        }
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_sync()
    local app = self:_app()

    if app and app._syncLifecycleState then
        app:_syncLifecycleState(self.state)
    end
end

function controller:afterNodeChanged()
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
    local app = self:_app()
    local sensorsTask

    if app and app.framework and app.framework.getTask then
        sensorsTask = app.framework:getTask("sensors")
        if sensorsTask and type(sensorsTask.armSensorLostMute) == "function" then
            sensorsTask:armSensorLostMute(6.0)
        end
    end

    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self.state.startupJob = nil

    if app and app.pageHost then
        app.pageHost:openRoot()
    end

    self:_sync()
end

function controller:activate()
    local app = self:_app()

    if app and app.loaderController then
        app.loaderController:reset()
    end
    if app and app.menuController then
        app.menuController:reset()
        app.menuController:primeSignatures(
            app:_currentMenuAccessSignatureLegacy(),
            app:_currentMenuEnableSignatureLegacy()
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
    local app = self:_app()
    local canTouchForm = app and app.framework and app.framework.isAppActive and app.framework:isAppActive() == true

    if app and app.loaderController then
        app.loaderController:reset()
    end
    if app and app.menuController then
        app.menuController:reset()
    end
    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self:cancelDeferredMaintenance()
    self.state.maintenancePhase = 0
    if app and app.callback then
        app.callback:clearAll()
    end
    if app and app._closeNode then
        app:_closeNode(app.currentNode)
    end
    if canTouchForm and form and form.clear then
        form.clear()
    end
    if app and app.formHost then
        app.formHost:reset()
    end
    if app and app.pageHost then
        app.pageHost:reset()
    elseif app then
        app.currentNode = nil
        app.pathStack = {}
    end
    if app then
        app.snapshot = nil
        app.telemetryTask = nil
        app.mspTask = nil
        app.rootLoadError = nil
    end
    if app and app._clearMaskCache then
        app:_clearMaskCache()
    end
    if app and app._clearLuaTableCache then
        app:_clearLuaTableCache()
    end
    if app and app._savePreferences then
        app:_savePreferences()
    end
    pcall(collectgarbage, "collect")
    if app and app.framework and app.framework.captureMemoryDebug then
        app.framework:captureMemoryDebug("app_deactivate")
    end
    self:_sync()
end

function controller:close()
    local app = self:_app()
    local canTouchForm = app and app.framework and app.framework.isAppActive and app.framework:isAppActive() == true

    if app and app.loaderController then
        app.loaderController:reset()
    end
    if app and app.menuController then
        app.menuController:reset()
    end
    self.state.startupLoaderStage = 0
    self:cancelStartupPreparation()
    self:cancelDeferredMaintenance()
    if app and app.callback then
        app.callback:clearAll()
    end
    if app and app._closeNode then
        app:_closeNode(app.currentNode)
    end
    if canTouchForm and form and form.clear then
        form.clear()
    end
    if app and app.formHost then
        app.formHost:reset()
    end
    if app and app.pageHost then
        app.pageHost:reset()
    elseif app then
        app.currentNode = nil
        app.pathStack = nil
    end
    if app and app._clearMaskCache then
        app:_clearMaskCache()
    end
    if app and app._clearLuaTableCache then
        app:_clearLuaTableCache()
    end
    if app then
        app.snapshot = nil
        app.telemetryTask = nil
        app.mspTask = nil
        app.rootLoadError = nil
    end
    if app and app._savePreferences then
        app:_savePreferences()
    end
    if app then
        app.framework = nil
    end
    pcall(collectgarbage, "collect")
    self:_sync()
end

return controller
