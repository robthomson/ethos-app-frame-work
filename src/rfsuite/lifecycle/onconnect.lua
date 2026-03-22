--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")

local onconnect = {
    _registered = false
}

local MODULE_NAME = "lifecycle.onconnect_runtime"
local MODULE_PATH = "lifecycle/onconnect_runtime.lua"

local function loadRuntime()
    return ModuleLoader.requireOrLoad(MODULE_NAME, MODULE_PATH)
end

local function releaseRuntime()
    ModuleLoader.clear(MODULE_NAME, MODULE_PATH)
    if package and type(package.loaded) == "table" then
        package.loaded[MODULE_NAME] = nil
    end
end

local function resolveHook(handlerName)
    local runtime = loadRuntime()
    if runtime and type(runtime.getHook) == "function" then
        return runtime.getHook(handlerName)
    end
    return nil
end

local function createDeferredHook(handlerName)
    return {
        reset = function(context)
            local definition = resolveHook(handlerName)
            if type(definition) == "table" and type(definition.reset) == "function" then
                return definition.reset(context)
            end
            context.hook._runtimeResult = nil
            context.hook._runtimeLoaded = nil
            return nil
        end,
        wakeup = function(context)
            local definition = resolveHook(handlerName)
            local result

            if not definition then
                return true
            end

            context.hook._runtimeLoaded = true
            if type(definition) == "function" then
                result = definition(context)
            elseif type(definition) == "table" and type(definition.run) == "function" then
                result = definition.run(context)
            elseif type(definition) == "table" and type(definition.wakeup) == "function" then
                result = definition.wakeup(context)
            else
                result = true
            end

            context.hook._runtimeResult = result
            return result
        end,
        isComplete = function(context)
            local definition = resolveHook(handlerName)

            if not definition then
                return true
            end

            if type(definition) == "table" and type(definition.isComplete) == "function" then
                return definition.isComplete(context, context.hook._runtimeResult)
            end

            return context.hook._runtimeResult ~= false
        end
    }
end

function onconnect.releaseLoaded()
    releaseRuntime()
end

function onconnect.registerAll(registry)
    if onconnect._registered then
        return
    end

    registry.register("onconnect", "onconnect.flightmode", createDeferredHook("flightmode"), {priority = 95})
    registry.register("onconnect", "onconnect.fcversion", createDeferredHook("fcversion"), {priority = 90, timeout = 3.0})
    registry.register("onconnect", "onconnect.uid", createDeferredHook("uid"), {priority = 85, timeout = 3.0})
    registry.register("onconnect", "onconnect.telemetryconfig", createDeferredHook("telemetryconfig"), {priority = 82, timeout = 3.0})
    registry.register("onconnect", "onconnect.modelpreferences", createDeferredHook("modelpreferences"), {priority = 80})
    registry.register("onconnect", "onconnect.sensorstats", createDeferredHook("sensorstats"), {priority = 75})
    registry.register("onconnect", "onconnect.timer", createDeferredHook("timer"), {priority = 70})
    registry.register("onconnect", "onconnect.rateprofile", createDeferredHook("rateprofile"), {priority = 65})

    onconnect._registered = true
end

return onconnect
