--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local telemetryConfigSession = require("telemetry.config")
local utils = require("lib.utils")

local FEATURE_BIT_TELEMETRY = 10
local MAX_TELEMETRY_SENSORS = 40
local TELEMETRY_HELP = nil

local SENSOR_LIST = {
    [1] = {name = "Heartbeat", group = "system"},
    [3] = {name = "Voltage", group = "battery"},
    [4] = {name = "Current", group = "battery"},
    [5] = {name = "Consumption", group = "battery"},
    [6] = {name = "Charge Level", group = "battery"},
    [7] = {name = "Cell Count", group = "battery"},
    [8] = {name = "Cell Voltage", group = "battery"},
    [9] = {name = "Cell Voltages", group = "battery"},
    [10] = {name = "Ctrl", group = "control"},
    [11] = {name = "Pitch Control", group = "control"},
    [12] = {name = "Roll Control", group = "control"},
    [13] = {name = "Yaw Control", group = "control"},
    [14] = {name = "Coll Control", group = "control"},
    [15] = {name = "Throttle %", group = "control"},
    [17] = {name = "ESC1 Voltage", group = "esc1"},
    [18] = {name = "ESC1 Current", group = "esc1"},
    [19] = {name = "ESC1 Consump", group = "esc1"},
    [20] = {name = "ESC1 eRPM", group = "esc1"},
    [21] = {name = "ESC1 PWM", group = "esc1"},
    [22] = {name = "ESC1 Throttle", group = "esc1"},
    [23] = {name = "ESC1 Temp", group = "esc1"},
    [24] = {name = "ESC1 Temp 2", group = "esc1"},
    [25] = {name = "ESC1 BEC Volt", group = "esc1"},
    [26] = {name = "ESC1 BEC Curr", group = "esc1"},
    [27] = {name = "ESC1 Status", group = "esc1"},
    [28] = {name = "ESC1 Model ID", group = "esc1"},
    [30] = {name = "ESC2 Voltage", group = "esc2"},
    [31] = {name = "ESC2 Current", group = "esc2"},
    [32] = {name = "ESC2 Consump", group = "esc2"},
    [33] = {name = "ESC2 eRPM", group = "esc2"},
    [36] = {name = "ESC2 Temp", group = "esc2"},
    [41] = {name = "ESC2 Model ID", group = "esc2"},
    [42] = {name = "ESC Voltage", group = "voltage"},
    [43] = {name = "BEC Voltage", group = "voltage"},
    [44] = {name = "BUS Voltage", group = "voltage"},
    [45] = {name = "MCU Voltage", group = "voltage"},
    [46] = {name = "ESC Current", group = "current"},
    [47] = {name = "BEC Current", group = "current"},
    [48] = {name = "BUS Current", group = "current"},
    [49] = {name = "MCU Current", group = "current"},
    [50] = {name = "ESC Temp", group = "temps"},
    [51] = {name = "BEC Temp", group = "temps"},
    [52] = {name = "MCU Temp", group = "temps"},
    [57] = {name = "Heading", group = "gyro"},
    [58] = {name = "Altitude", group = "barometer"},
    [59] = {name = "VSpeed", group = "barometer"},
    [60] = {name = "Headspeed", group = "rpm"},
    [61] = {name = "Tailspeed", group = "rpm"},
    [64] = {name = "Attd", group = "gyro"},
    [65] = {name = "Pitch Attitude", group = "gyro"},
    [66] = {name = "Roll Attitude", group = "gyro"},
    [67] = {name = "Yaw Attitude", group = "gyro"},
    [68] = {name = "Accl", group = "gyro"},
    [69] = {name = "Accel X", group = "gyro"},
    [70] = {name = "Accel Y", group = "gyro"},
    [71] = {name = "Accel Z", group = "gyro"},
    [73] = {name = "GPS Sats", group = "gps"},
    [74] = {name = "GPS PDOP", group = "gps"},
    [75] = {name = "GPS HDOP", group = "gps"},
    [76] = {name = "GPS VDOP", group = "gps"},
    [77] = {name = "GPS Coord", group = "gps"},
    [78] = {name = "GPS Altitude", group = "gps"},
    [79] = {name = "GPS Heading", group = "gps"},
    [80] = {name = "GPS Speed", group = "gps"},
    [81] = {name = "GPS Home Dist", group = "gps"},
    [82] = {name = "GPS Home Dir", group = "gps"},
    [85] = {name = "CPU Load", group = "system"},
    [86] = {name = "SYS Load", group = "system"},
    [87] = {name = "RT Load", group = "system"},
    [88] = {name = "Model ID", group = "status"},
    [89] = {name = "Flight Mode", group = "status"},
    [90] = {name = "Arming Flags", group = "status"},
    [91] = {name = "Arming Disable", group = "status"},
    [92] = {name = "Rescue", group = "status"},
    [93] = {name = "Governor", group = "status"},
    [95] = {name = "PID Profile", group = "profiles"},
    [96] = {name = "Rate Profile", group = "profiles"},
    [97] = {name = "Battery Profile", group = "profiles"},
    [98] = {name = "LED Profile", group = "profiles"},
    [99] = {name = "ADJ", group = "status"},
    [100] = {name = "DBG0", group = "debug"},
    [101] = {name = "DBG1", group = "debug"},
    [102] = {name = "DBG2", group = "debug"},
    [103] = {name = "DBG3", group = "debug"},
    [104] = {name = "DBG4", group = "debug"},
    [105] = {name = "DBG5", group = "debug"},
    [106] = {name = "DBG6", group = "debug"},
    [107] = {name = "DBG7", group = "debug"}
}

local GROUP_TITLES = {
    battery = "@i18n(telemetry.group_battery)@",
    voltage = "@i18n(telemetry.group_voltage)@",
    current = "@i18n(telemetry.group_current)@",
    temps = "@i18n(telemetry.group_temps)@",
    esc1 = "@i18n(telemetry.group_esc1)@",
    esc2 = "@i18n(telemetry.group_esc2)@",
    rpm = "@i18n(telemetry.group_rpm)@",
    barometer = "@i18n(telemetry.group_barometer)@",
    gyro = "@i18n(telemetry.group_gyro)@",
    gps = "@i18n(telemetry.group_gps)@",
    status = "@i18n(telemetry.group_status)@",
    profiles = "@i18n(telemetry.group_profiles)@",
    control = "@i18n(telemetry.group_control)@",
    system = "@i18n(telemetry.group_system)@",
    debug = "@i18n(telemetry.group_debug)@"
}

local GROUP_ORDER = {
    "battery", "voltage", "current", "temps", "esc1", "esc2", "rpm",
    "barometer", "gyro", "gps", "status", "profiles", "control", "system", "debug"
}

local NOT_AT_SAME_TIME = {
    [10] = {11, 12, 13, 14},
    [64] = {65, 66, 67},
    [68] = {69, 70, 71}
}

local SENSOR_IDS = {}
local SENSOR_GROUPS = {}

do
    local id
    local sensor
    local group
    local _, groupName

    for id in pairs(SENSOR_LIST) do
        SENSOR_IDS[#SENSOR_IDS + 1] = id
    end
    table.sort(SENSOR_IDS, function(a, b)
        return a < b
    end)

    for _, id in ipairs(SENSOR_IDS) do
        sensor = SENSOR_LIST[id]
        group = sensor.group or "system"
        SENSOR_GROUPS[group] = SENSOR_GROUPS[group] or {
            title = GROUP_TITLES[group] or group,
            ids = {}
        }
        SENSOR_GROUPS[group].ids[#SENSOR_GROUPS[group].ids + 1] = id
    end

    for group in pairs(SENSOR_GROUPS) do
        local known = false
        for _, groupName in ipairs(GROUP_ORDER) do
            if groupName == group then
                known = true
                break
            end
        end
        if known ~= true then
            GROUP_ORDER[#GROUP_ORDER + 1] = group
        end
    end
end

local function noopHandler()
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
end

local function unloadApi(mspTask, apiName, api)
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end

    if mspTask and mspTask.api and mspTask.api.unload and type(apiName) == "string" then
        mspTask.api.unload(apiName)
    end
end

local function trackActiveApi(state, apiName, api)
    if type(state.activeApis) ~= "table" or type(apiName) ~= "string" or api == nil then
        return
    end

    state.activeApis[apiName] = api
end

local function clearActiveApi(state, apiName)
    if type(state.activeApis) ~= "table" then
        return nil
    end

    local api = state.activeApis[apiName]
    state.activeApis[apiName] = nil
    return api
end

local function cleanupActiveApis(state, app)
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil
    local apiName
    local api

    if type(state) ~= "table" or type(state.activeApis) ~= "table" then
        return
    end

    for apiName, api in pairs(state.activeApis) do
        if api and api.setCompleteHandler then
            api.setCompleteHandler(noopHandler)
        end
        if api and api.setErrorHandler then
            api.setErrorHandler(noopHandler)
        end
        if api and api.setUUID then
            api.setUUID(nil)
        end
        unloadApi(mspTask, apiName, api)
        state.activeApis[apiName] = nil
    end
end

local function cloneMap(source)
    local copy = {}
    local key

    for key, value in pairs(source or {}) do
        copy[key] = value
    end

    return copy
end

local function readParsed(api)
    local data = api and api.data and api.data() or nil
    return data and data.parsed or nil
end

local function countEnabledSensors(config)
    local count = 0
    local _, id

    for _, id in ipairs(SENSOR_IDS) do
        if config[id] == true then
            count = count + 1
        end
    end

    return count
end

local function configsEqual(left, right)
    local _, id

    for _, id in ipairs(SENSOR_IDS) do
        if (left[id] == true) ~= (right[id] == true) then
            return false
        end
    end

    return true
end

local function refreshDirtyState(node)
    local dirty = node.state.defaultDirty == true or not configsEqual(node.state.config, node.state.savedConfig)

    node.state.dirty = dirty
    if node.app and node.app.setPageDirty then
        node.app:setPageDirty(dirty)
    end
end

local function setControlEnabled(control, enabled)
    if control and control.enable then
        pcall(control.enable, control, enabled == true)
    end
end

local function setControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function updateConflictControl(node, sensorId)
    local control = node.state.sensorControls[sensorId]

    if control then
        setControlValue(control, node.state.config[sensorId] == true)
        setControlEnabled(control, node.state.loaded == true and node.state.loading ~= true and node.state.sensorForceDisabled[sensorId] ~= true)
    end
end

local function restoreConflicts(node, sensorId)
    local conflicts = NOT_AT_SAME_TIME[sensorId]
    local _, conflictId

    if type(conflicts) ~= "table" then
        return
    end

    for _, conflictId in ipairs(conflicts) do
        node.state.sensorForceDisabled[conflictId] = nil
        if node.state.prevState[conflictId] ~= nil then
            node.state.config[conflictId] = node.state.prevState[conflictId] == true
            node.state.prevState[conflictId] = nil
        end
        updateConflictControl(node, conflictId)
    end
end

local function applyConflicts(node, sensorId)
    local conflicts = NOT_AT_SAME_TIME[sensorId]
    local _, conflictId

    if type(conflicts) ~= "table" then
        return
    end

    for _, conflictId in ipairs(conflicts) do
        node.state.prevState[conflictId] = node.state.config[conflictId] == true
        node.state.config[conflictId] = false
        node.state.sensorForceDisabled[conflictId] = true
        updateConflictControl(node, conflictId)
    end
end

local function initialiseConflictState(node)
    local sensorId

    node.state.prevState = {}
    node.state.sensorForceDisabled = {}
    for sensorId in pairs(NOT_AT_SAME_TIME) do
        if node.state.config[sensorId] == true then
            applyConflicts(node, sensorId)
        end
    end
end

local function selectedSensorIds(config)
    local selected = {}
    local _, id

    for _, id in ipairs(SENSOR_IDS) do
        if config[id] == true then
            selected[#selected + 1] = id
        end
    end

    return selected
end

local function refreshSensorControls(node)
    local _, sensorId

    for _, sensorId in ipairs(SENSOR_IDS) do
        updateConflictControl(node, sensorId)
    end
end

local function applyDefaultSensors(node)
    local telemetryTask = node.app.framework:getTask("telemetry")
    local defaultSet = {}
    local sensor
    local sensorId
    local _, id

    if node.app and node.app.ui and node.app.ui.showLoader then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.telemetry.name)@",
            message = "Applying defaults.",
            closeWhenIdle = false,
            minVisibleFor = 0.25,
            modal = true
        })
    end

    if telemetryTask and telemetryTask.listSensors then
        for _, sensor in ipairs(telemetryTask.listSensors() or {}) do
            sensorId = tonumber(sensor and sensor.set_telemetry_sensors)
            if sensor and sensor.mandatory == true and sensorId then
                defaultSet[sensorId] = true
            end
        end
    end

    for _, id in ipairs(SENSOR_IDS) do
        node.state.config[id] = defaultSet[id] == true
    end

    initialiseConflictState(node)
    node.state.defaultDirty = true
    refreshDirtyState(node)
    if next(node.state.sensorControls or {}) ~= nil then
        refreshSensorControls(node)
    elseif node.app and node.app._invalidateForm then
        node.app:_invalidateForm()
    end
    if node.app and node.app.requestLoaderClose then
        node.app:requestLoaderClose()
    elseif node.app and node.app.ui and node.app.ui.clearProgressDialog then
        node.app.ui.clearProgressDialog(true)
    end
end

local function finishLoad(node)
    local state = node.state

    state.loading = false
    state.loaded = true
    state.loadStarted = true
    state.loadError = nil
    state.saveError = nil
    state.savedConfig = cloneMap(state.config)
    state.defaultDirty = false
    refreshDirtyState(node)
    if node.app and node.app.requestLoaderClose then
        node.app:requestLoaderClose()
    else
        node.app.ui.clearProgressDialog(true)
    end
    if next(state.sensorControls or {}) ~= nil then
        refreshSensorControls(node)
    elseif node.app and node.app._invalidateForm then
        node.app:_invalidateForm()
    end
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local generation
    local existingControls = state.sensorControls

    local function fail(message)
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        cleanupActiveApis(state, node.app)
        state.loading = false
        state.loaded = false
        state.loadStarted = true
        state.loadError = tostring(message or "read_failed")
        refreshDirtyState(node)
        node.app.ui.clearProgressDialog(true)
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
    end

    local function beginTelemetryRead()
        local telemetryApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("TELEMETRY_CONFIG")

        if not telemetryApi then
            fail("@i18n(app.modules.telemetry.invalid_version)@")
            return false
        end

        trackActiveApi(state, "TELEMETRY_CONFIG", telemetryApi)
        if telemetryApi.setUUID then
            telemetryApi.setUUID(utils.uuid("telemetry-config-read"))
        end
        telemetryApi.setCompleteHandler(function()
            local parsed
            local index
            local slotValue

            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                clearActiveApi(state, "TELEMETRY_CONFIG")
                unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
                return
            end

            parsed = readParsed(telemetryApi) or {}
            state.telemetrySettings = cloneMap(parsed)
            telemetryConfigSession.applyApiToSession(node.app.framework.session, telemetryApi, node.app.framework.log)

            for _, id in ipairs(SENSOR_IDS) do
                state.config[id] = false
            end
            for index = 1, MAX_TELEMETRY_SENSORS do
                slotValue = tonumber(parsed["telem_sensor_slot_" .. tostring(index)] or 0) or 0
                if slotValue ~= 0 then
                    state.config[slotValue] = true
                end
            end

            initialiseConflictState(node)
            clearActiveApi(state, "TELEMETRY_CONFIG")
            unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
            finishLoad(node)
        end)
        telemetryApi.setErrorHandler(function(_, reason)
            clearActiveApi(state, "TELEMETRY_CONFIG")
            unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
            fail(reason or "telemetry_read_failed")
        end)

        if telemetryApi.read() ~= true then
            clearActiveApi(state, "TELEMETRY_CONFIG")
            unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
            fail("telemetry_read_failed")
            return false
        end

        return true
    end

    local function beginFeatureRead()
        local featureApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FEATURE_CONFIG")

        if not featureApi then
            state.featureBitmap = 0
            return beginTelemetryRead()
        end

        trackActiveApi(state, "FEATURE_CONFIG", featureApi)
        if featureApi.setUUID then
            featureApi.setUUID(utils.uuid("telemetry-feature-read"))
        end
        featureApi.setCompleteHandler(function()
            local parsed

            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                clearActiveApi(state, "FEATURE_CONFIG")
                unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
                return
            end

            parsed = readParsed(featureApi) or {}
            state.featureBitmap = tonumber(parsed.enabledFeatures or 0) or 0
            clearActiveApi(state, "FEATURE_CONFIG")
            unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
            beginTelemetryRead()
        end)
        featureApi.setErrorHandler(function()
            clearActiveApi(state, "FEATURE_CONFIG")
            unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
            state.featureBitmap = 0
            beginTelemetryRead()
        end)

        if featureApi.read() ~= true then
            clearActiveApi(state, "FEATURE_CONFIG")
            unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
            state.featureBitmap = 0
            return beginTelemetryRead()
        end

        return true
    end

    if utils.apiVersionCompare("<", {12, 0, 8}) then
        state.invalidVersion = true
        state.loadStarted = true
        state.loading = false
        state.loaded = false
        state.loadError = nil
        refreshDirtyState(node)
        if showLoader == true then
            node.app.ui.clearProgressDialog(true)
        end
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
        return false
    end

    cleanupActiveApis(state, node.app)
    state.loadGeneration = (state.loadGeneration or 0) + 1
    generation = state.loadGeneration
    state.invalidVersion = false
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.saveError = nil
    state.defaultDirty = false
    state.telemetrySettings = {}
    state.featureBitmap = 0
    state.config = {}
    state.savedConfig = {}
    state.sensorControls = existingControls or {}
    state.prevState = {}
    state.sensorForceDisabled = {}
    state.loadStarted = true
    refreshDirtyState(node)
    if next(state.sensorControls or {}) ~= nil then
        refreshSensorControls(node)
    end

    if showLoader == true then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.telemetry.name)@",
            message = "Loading values.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            focusMenuOnClose = true,
            modal = true
        })
    end

    return beginFeatureRead()
end

local function runReboot(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local sensorsTask = node.app.framework:getTask("sensors")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("REBOOT")

    local function finishSuccess()
        state.saving = false
        state.saveError = nil
        state.savedConfig = cloneMap(state.config)
        state.defaultDirty = false
        refreshDirtyState(node)
        node.app.ui.clearProgressDialog(true)
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
    end

    local function fail(message)
        state.saving = false
        state.saveError = tostring(message or "reboot_failed")
        node.app.ui.clearProgressDialog(true)
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
    end

    if not api then
        fail("reboot_unavailable")
        return false
    end

    if sensorsTask and sensorsTask.armSensorLostMute then
        sensorsTask:armSensorLostMute(10)
    end

    if api.clearValues then
        api.clearValues()
    end
    if api.setUUID then
        api.setUUID(utils.uuid("telemetry-reboot"))
    end

    if api.write() ~= true then
        unloadApi(mspTask, "REBOOT", api)
        fail("reboot_failed")
        return false
    end

    unloadApi(mspTask, "REBOOT", api)
    finishSuccess()
    return true
end

local function performSave(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local featureApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FEATURE_CONFIG")
    local telemetryApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("TELEMETRY_CONFIG")
    local eepromApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE")
    local selected
    local featureTarget
    local sessionValues
    local values
    local index

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = tostring(message or "save_failed")
        node.app.ui.clearProgressDialog(true)
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
    end

    if state.invalidVersion == true or state.loading == true or state.saving == true or state.loaded ~= true or state.dirty ~= true then
        return false
    end

    selected = selectedSensorIds(state.config)
    if #selected > MAX_TELEMETRY_SENSORS then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.telemetry.name)@", "@i18n(app.modules.telemetry.no_more_than_40)@")
        return false
    end

    if not telemetryApi then
        fail("telemetry_api_unavailable")
        return false
    end
    if not eepromApi then
        unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
        fail("eeprom_api_unavailable")
        return false
    end
    if not featureApi then
        unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        fail("feature_api_unavailable")
        return false
    end

    cleanupActiveApis(state, node.app)
    state.saving = true
    state.saveError = nil
    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.telemetry.name)@",
        message = "Saving values.",
        closeWhenIdle = false,
        modal = true
    })

    trackActiveApi(state, "FEATURE_CONFIG", featureApi)
    trackActiveApi(state, "TELEMETRY_CONFIG", telemetryApi)
    trackActiveApi(state, "EEPROM_WRITE", eepromApi)

    if featureApi.clearValues then
        featureApi.clearValues()
    end
    if telemetryApi.clearValues then
        telemetryApi.clearValues()
    end

    featureTarget = tonumber(state.featureBitmap or 0) or 0
    featureTarget = featureTarget | (1 << FEATURE_BIT_TELEMETRY)
    featureApi.setValue("enabledFeatures", featureTarget)

    values = cloneMap(state.telemetrySettings)
    for index = 1, MAX_TELEMETRY_SENSORS do
        values["telem_sensor_slot_" .. tostring(index)] = selected[index] or 0
    end
    for index = 1, MAX_TELEMETRY_SENSORS do
        telemetryApi.setValue("telem_sensor_slot_" .. tostring(index), values["telem_sensor_slot_" .. tostring(index)])
    end
    telemetryApi.setValue("telemetry_inverted", tonumber(values.telemetry_inverted or 0) or 0)
    telemetryApi.setValue("halfDuplex", tonumber(values.halfDuplex or 0) or 0)
    telemetryApi.setValue("enableSensors", tonumber(values.enableSensors or 0) or 0)
    telemetryApi.setValue("pinSwap", tonumber(values.pinSwap or 0) or 0)
    telemetryApi.setValue("crsf_telemetry_mode", tonumber(values.crsf_telemetry_mode or 0) or 0)
    telemetryApi.setValue("crsf_telemetry_link_rate", tonumber(values.crsf_telemetry_link_rate or 0) or 0)
    telemetryApi.setValue("crsf_telemetry_link_ratio", tonumber(values.crsf_telemetry_link_ratio or 0) or 0)

    if featureApi.setUUID then
        featureApi.setUUID(utils.uuid("telemetry-feature-write"))
    end
    if telemetryApi.setUUID then
        telemetryApi.setUUID(utils.uuid("telemetry-config-write"))
    end
    if eepromApi.setUUID then
        eepromApi.setUUID(utils.uuid("telemetry-eeprom-write"))
    end

    eepromApi.setCompleteHandler(function()
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        if nodeIsOpen(node) == true then
            state.featureBitmap = featureTarget
            state.telemetrySettings = values
            sessionValues = {
                telemetryConfig = {},
                crsfTelemetryMode = tonumber(values.crsf_telemetry_mode or 0) or 0,
                crsfTelemetryLinkRate = tonumber(values.crsf_telemetry_link_rate or 0) or 0,
                crsfTelemetryLinkRatio = tonumber(values.crsf_telemetry_link_ratio or 0) or 0
            }
            for index = 1, MAX_TELEMETRY_SENSORS do
                sessionValues.telemetryConfig[index] = values["telem_sensor_slot_" .. tostring(index)] or 0
            end
            node.app.framework.session:setMultiple(sessionValues)
            runReboot(node)
        end
    end)
    eepromApi.setErrorHandler(function()
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        if nodeIsOpen(node) == true then
            fail("eeprom_write_failed")
        end
    end)

    telemetryApi.setCompleteHandler(function()
        clearActiveApi(state, "TELEMETRY_CONFIG")
        unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
        if nodeIsOpen(node) == true and eepromApi.write() ~= true then
            clearActiveApi(state, "EEPROM_WRITE")
            unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
            fail("eeprom_write_failed")
        end
    end)
    telemetryApi.setErrorHandler(function()
        clearActiveApi(state, "TELEMETRY_CONFIG")
        unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
        if nodeIsOpen(node) == true then
            fail("telemetry_write_failed")
        end
    end)

    featureApi.setCompleteHandler(function()
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        if nodeIsOpen(node) == true and telemetryApi.write() ~= true then
            clearActiveApi(state, "TELEMETRY_CONFIG")
            unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
            clearActiveApi(state, "EEPROM_WRITE")
            unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
            fail("telemetry_write_failed")
        end
    end)
    featureApi.setErrorHandler(function()
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        if nodeIsOpen(node) == true then
            fail("feature_write_failed")
        end
    end)

    if featureApi.write() ~= true then
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        clearActiveApi(state, "TELEMETRY_CONFIG")
        unloadApi(mspTask, "TELEMETRY_CONFIG", telemetryApi)
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        fail("feature_write_failed")
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        loadGeneration = 0,
        loadStarted = false,
        loading = false,
        loaded = false,
        saving = false,
        dirty = false,
        defaultDirty = false,
        invalidVersion = false,
        loadError = nil,
        saveError = nil,
        closed = false,
        config = {},
        savedConfig = {},
        telemetrySettings = {},
        featureBitmap = 0,
        activeApis = {},
        sensorControls = {},
        prevState = {},
        sensorForceDisabled = {}
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.telemetry.name)@",
        subtitle = ctx.item.subtitle or "Telemetry sensor setup",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = true, help = false},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "Loading values.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:canSave()
        return state.invalidVersion ~= true
            and state.loaded == true
            and state.loading ~= true
            and state.saving ~= true
            and state.dirty == true
    end

    function node:buildForm(app)
        local line
        local groupKey
        local group
        local panel
        local sensorId
        local sensor
        local control

        self.app = app
        state.sensorControls = {}

        if state.invalidVersion == true then
            line = form.addLine("@i18n(app.modules.telemetry.invalid_version)@")
            form.addStaticText(line, nil, "")
            return
        end

        if state.loadError then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.loadError))
            return
        end

        if state.saveError then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.saveError))
        end

        for _, groupKey in ipairs(GROUP_ORDER) do
            group = SENSOR_GROUPS[groupKey]
            if group and type(group.ids) == "table" and #group.ids > 0 then
                panel = form.addExpansionPanel(group.title)
                panel:open(false)
                for _, sensorId in ipairs(group.ids) do
                    sensor = SENSOR_LIST[sensorId]
                    if sensor then
                        line = panel:addLine(sensor.name)
                        control = form.addBooleanField(line, nil,
                            function()
                                return state.config[sensorId] == true
                            end,
                            function(newValue)
                                local value = newValue == true or newValue == 1
                                local current = state.config[sensorId] == true

                                if value == current then
                                    return
                                end

                                if value == true and countEnabledSensors(state.config) >= MAX_TELEMETRY_SENSORS then
                                    diagnostics.openMessageDialog(node.title or "@i18n(app.modules.telemetry.name)@", "@i18n(app.modules.telemetry.no_more_than_40)@")
                                    setControlValue(state.sensorControls[sensorId], false)
                                    return
                                end

                                state.config[sensorId] = value
                                if NOT_AT_SAME_TIME[sensorId] then
                                    if value == true then
                                        applyConflicts(node, sensorId)
                                    else
                                        restoreConflicts(node, sensorId)
                                    end
                                end

                                refreshDirtyState(node)
                            end)
                        state.sensorControls[sensorId] = control
                        setControlEnabled(control, state.loaded == true and state.loading ~= true and state.sensorForceDisabled[sensorId] ~= true)
                    end
                end
            end
        end
    end

    function node:wakeup()
        if state.loadStarted ~= true and state.loading ~= true and state.saving ~= true then
            startLoad(self, false)
        end
    end

    function node:reload()
        if state.saving == true then
            return false
        end

        return startLoad(self, true)
    end

    function node:save()
        if not self:canSave() then
            return false
        end

        return performSave(self)
    end

    function node:tool()
        return diagnostics.openConfirmDialog(
            node.title or "@i18n(app.modules.telemetry.name)@",
            "@i18n(app.modules.telemetry.msg_set_defaults)@",
            function()
                applyDefaultSensors(node)
            end
        )
    end

    function node:help()
        if TELEMETRY_HELP then
            return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.telemetry.name)@") .. " Help", TELEMETRY_HELP)
        end
        return false
    end

    function node:close()
        state.closed = true
        state.loading = false
        state.saving = false
        cleanupActiveApis(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
