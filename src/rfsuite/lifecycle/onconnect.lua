--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = require("lib.ini")
local telemetryconfig = require("telemetry.config")
local utils = require("lib.utils")

local onconnect = {
    _registered = false
}

local MODEL_PREFERENCES_DEFAULTS = {
    dashboard = {
        theme_preflight = "nil",
        theme_inflight = "nil",
        theme_postflight = "nil"
    },
    general = {
        flightcount = 0,
        totalflighttime = 0,
        lastflighttime = 0,
        batterylocalcalculation = 1
    },
    battery = {
        smartfuel_model_type = 0,
        sag_multiplier = 0.5,
        calc_local = 0,
        alert_type = 0,
        becalertvalue = 6.5,
        rxalertvalue = 7.5,
        flighttime = 300
    }
}

local function safeMkdir(path)
    if os and os.mkdir and path then
        pcall(os.mkdir, path)
    end
end

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
end

local function createApiReadHook(spec)
    local state = {
        started = false,
        failed = false
    }

    return {
        timeout = spec.timeout or 3.0,
        reset = function(context)
            state.started = false
            state.failed = false
            if spec.onReset then
                spec.onReset(context)
            end
        end,
        wakeup = function(context)
            local api
            local loadErr
            local ok
            local err

            if state.failed then
                return true
            end

            if spec.isReady and spec.isReady(context) ~= true then
                return false
            end

            if spec.isComplete and spec.isComplete(context) == true then
                return true
            end

            if state.started then
                return false
            end

            if context.msp and context.msp.api and context.msp.api.load then
                api, loadErr = context.msp.api.load(spec.apiName)
            end
            if not api then
                state.failed = true
                context.framework.log:error(
                    "[lifecycle] onconnect hook '%s' failed to load API '%s': %s",
                    spec.name,
                    spec.apiName,
                    tostring(loadErr or "load_failed")
                )
                return true
            end

            api.setCompleteHandler(function()
                if spec.onComplete then
                    spec.onComplete(context, api)
                end
            end)
            api.setErrorHandler(function(_, errorMessage)
                state.failed = true
                if spec.onError then
                    spec.onError(context, errorMessage)
                else
                    context.framework.log:warn("[lifecycle] onconnect hook '%s' API '%s' error: %s", spec.name, spec.apiName, tostring(errorMessage))
                end
            end)
            if spec.uuid then
                api.setUUID(spec.uuid)
            end
            if spec.readTimeout then
                api.setTimeout(spec.readTimeout)
            end

            ok, err = api.read()
            if not ok then
                state.failed = true
                context.framework.log:warn("[lifecycle] onconnect hook '%s' API '%s' queue error: %s", spec.name, spec.apiName, tostring(err))
                return true
            end

            state.started = true
            return false
        end,
        isComplete = function(context)
            if state.failed then
                return true
            end

            if spec.isComplete then
                return spec.isComplete(context) == true
            end

            return false
        end
    }
end

local function flightmodeHook(context)
    context.session:setMultiple({
        flightMode = "preflight",
        currentFlightMode = "preflight"
    })
    context.framework:_emit("flightmode:changed", "preflight")
    context.framework.log:connect("Flight mode: preflight")
    return true
end

local fcversionHook = createApiReadHook({
    name = "fcversion",
    apiName = "FC_VERSION",
    uuid = "lifecycle-fc-version",
    isReady = function(context)
        return context.session:get("apiVersion", nil) ~= nil and context.session:get("mspBusy", false) ~= true
    end,
    isComplete = function(context)
        return context.session:get("fcVersion", nil) ~= nil
    end,
    onReset = function(context)
        context.session:clearKeys({"fcVersion", "rfVersion"})
    end,
    onComplete = function(context, api)
        local fcVersion = api.readVersion and api.readVersion() or nil
        local rfVersion = api.readRfVersion and api.readRfVersion() or nil

        context.session:setMultiple({
            fcVersion = fcVersion,
            rfVersion = rfVersion
        })

        if fcVersion then
            context.framework.log:connect("FC version: %s", tostring(fcVersion))
        end
    end
})

local uidHook = createApiReadHook({
    name = "uid",
    apiName = "UID",
    uuid = "lifecycle-uid",
    isReady = function(context)
        return context.session:get("apiVersion", nil) ~= nil and context.session:get("mspBusy", false) ~= true
    end,
    isComplete = function(context)
        return context.session:get("mcu_id", nil) ~= nil
    end,
    onReset = function(context)
        context.session:unset("mcu_id")
    end,
    onComplete = function(context, api)
        local u0 = api.readValue and api.readValue("U_ID_0") or nil
        local u1 = api.readValue and api.readValue("U_ID_1") or nil
        local u2 = api.readValue and api.readValue("U_ID_2") or nil
        local function toHexLe(u32)
            local b1 = u32 % 256
            local b2 = math.floor(u32 / 256) % 256
            local b3 = math.floor(u32 / 65536) % 256
            local b4 = math.floor(u32 / 16777216) % 256
            return string.format("%02x%02x%02x%02x", b1, b2, b3, b4)
        end

        if u0 == nil or u1 == nil or u2 == nil then
            return
        end

        local uid = toHexLe(u0) .. toHexLe(u1) .. toHexLe(u2)
        context.session:set("mcu_id", uid)
        context.framework.log:connect("MCU ID: %s", uid)
    end
})

local telemetryconfigHook = createApiReadHook({
    name = "telemetryconfig",
    apiName = "TELEMETRY_CONFIG",
    uuid = "lifecycle-telemetry-config",
    isReady = function(context)
        return context.session:get("apiVersion", nil) ~= nil and context.session:get("mspBusy", false) ~= true
    end,
    isComplete = function(context)
        return type(context.session:get("telemetryConfig", nil)) == "table"
    end,
    onReset = function(context)
        telemetryconfig.clearSession(context.session)
    end,
    onComplete = function(context, api)
        telemetryconfig.applyApiToSession(context.session, api, context.framework.log)
    end
})

local modelpreferencesHook = {
    reset = function(context)
        context.session:clearKeys({"modelPreferences", "modelPreferencesFile"})
    end,
    wakeup = function(context)
        local mcuId = context.session:get("mcu_id", nil)
        local preferencesRoot = context.framework.config.preferences
        local modelPreferences
        local modelPreferencesFile
        local loadedIni
        local mergedIni

        if context.session:get("apiVersion", nil) == nil then
            return false
        end

        if not mcuId or mcuId == "" then
            return false
        end

        modelPreferences = context.session:get("modelPreferences", nil)
        if type(modelPreferences) == "table" and next(modelPreferences) ~= nil then
            return true
        end

        if not preferencesRoot or preferencesRoot == "" then
            context.session:set("modelPreferences", copyTable(MODEL_PREFERENCES_DEFAULTS))
            return true
        end

        safeMkdir("SCRIPTS:/" .. preferencesRoot)
        safeMkdir("SCRIPTS:/" .. preferencesRoot .. "/models")

        modelPreferencesFile = "SCRIPTS:/" .. preferencesRoot .. "/models/" .. mcuId .. ".ini"
        loadedIni = ini.load_ini_file(modelPreferencesFile) or {}
        mergedIni = ini.merge_ini_tables(loadedIni, copyTable(MODEL_PREFERENCES_DEFAULTS))

        context.session:setMultiple({
            modelPreferences = mergedIni,
            modelPreferencesFile = modelPreferencesFile
        })

        if not ini.ini_tables_equal(loadedIni, MODEL_PREFERENCES_DEFAULTS) then
            ini.save_ini_file(modelPreferencesFile, mergedIni)
        end

        context.framework.log:connect("Model preferences: %s", modelPreferencesFile)
        return true
    end,
    isComplete = function(context)
        local modelPreferences = context.session:get("modelPreferences", nil)
        return type(modelPreferences) == "table" and next(modelPreferences) ~= nil
    end
}

local sensorstatsHook = {
    reset = function(context)
        context.session:clearKeys({"sensorStats"})

        local telemetryTask = context.framework:getTask("telemetry")
        if telemetryTask then
            telemetryTask.sensorStats = {}
        end
    end,
    wakeup = function(context)
        local telemetryTask

        if context.session:get("apiVersion", nil) == nil then
            return false
        end

        if context.session:get("mspBusy", false) == true then
            return false
        end

        telemetryTask = context.framework:getTask("telemetry")
        if telemetryTask then
            telemetryTask.sensorStats = {}
        end

        context.session:set("sensorStats", {})
        context.framework.log:connect("Sensor stats: reset")
        return true
    end,
    isComplete = function(context)
        return type(context.session:get("sensorStats", nil)) == "table"
    end
}

local timerHook = {
    reset = function(context)
        context.session:clearKeys({"timer", "flightCounted"})
    end,
    wakeup = function(context)
        if context.session:get("apiVersion", nil) == nil then
            return false
        end

        if context.session:get("mspBusy", false) == true then
            return false
        end

        context.session:setMultiple({
            timer = {
                start = nil,
                live = nil,
                lifetime = nil,
                session = 0
            },
            flightCounted = false
        })
        context.framework.log:connect("Timer: reset")
        return true
    end,
    isComplete = function(context)
        local timer = context.session:get("timer", nil)
        return type(timer) == "table" and timer.session == 0
    end
}

local rateprofileHook = {
    reset = function(context)
        context.session:clearKeys({"defaultRateProfile", "defaultRateProfileName"})
    end,
    wakeup = function(context)
        local defaultRateProfile
        local defaultRateProfileName

        if context.session:get("apiVersion", nil) == nil then
            return false
        end

        if utils.apiVersionCompare(">=", {12, 0, 9}) then
            defaultRateProfile = 6
            defaultRateProfileName = "ROTORFLIGHT"
        else
            defaultRateProfile = 4
            defaultRateProfileName = "ACTUAL"
        end

        context.framework.config.defaultRateProfile = defaultRateProfile
        context.session:setMultiple({
            defaultRateProfile = defaultRateProfile,
            defaultRateProfileName = defaultRateProfileName
        })
        context.framework.log:connect("Default rate profile: %s", defaultRateProfileName)
        return true
    end,
    isComplete = function(context)
        return context.session:get("defaultRateProfile", nil) ~= nil
    end
}

function onconnect.registerAll(registry)
    if onconnect._registered then
        return
    end

    registry.register("onconnect", "onconnect.flightmode", flightmodeHook, {priority = 95})
    registry.register("onconnect", "onconnect.fcversion", fcversionHook, {priority = 90, timeout = 3.0})
    registry.register("onconnect", "onconnect.uid", uidHook, {priority = 85, timeout = 3.0})
    registry.register("onconnect", "onconnect.telemetryconfig", telemetryconfigHook, {priority = 82, timeout = 3.0})
    registry.register("onconnect", "onconnect.modelpreferences", modelpreferencesHook, {priority = 80})
    registry.register("onconnect", "onconnect.sensorstats", sensorstatsHook, {priority = 75})
    registry.register("onconnect", "onconnect.timer", timerHook, {priority = 70})
    registry.register("onconnect", "onconnect.rateprofile", rateprofileHook, {priority = 65})

    onconnect._registered = true
end

return onconnect
