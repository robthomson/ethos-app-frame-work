--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local SENSOR_HELP = {
    "@i18n(app.modules.validate_sensors.help_p1)@",
    "@i18n(app.modules.validate_sensors.help_p2)@"
}

local function noopHandler()
end

local function unloadApi(mspTask, apiName, api)
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end

    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(apiName)
    end
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
end

local function trackActiveApi(node, apiName, api)
    local state = node and node.state or nil

    if type(state) ~= "table" then
        return
    end

    state.activeApiName = apiName
    state.activeApi = api
end

local function clearActiveApi(state)
    if type(state) ~= "table" then
        return
    end

    state.activeApiName = nil
    state.activeApi = nil
end

local function cleanupActiveApi(state, app)
    local api
    local apiName
    local mspTask

    if type(state) ~= "table" then
        return
    end

    api = state.activeApi
    apiName = state.activeApiName
    clearActiveApi(state)

    if not api then
        return
    end

    if api.setCompleteHandler then
        api.setCompleteHandler(noopHandler)
    end
    if api.setErrorHandler then
        api.setErrorHandler(noopHandler)
    end
    if api.setUUID then
        api.setUUID(nil)
    end

    mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil
    unloadApi(mspTask, apiName, api)
end

local function canRepair(node)
    local session = node.app.framework.session

    if session:get("isConnected", false) ~= true and diagnostics.isSimulation() ~= true then
        return false
    end

    if session:get("apiVersion", nil) == nil then
        return false
    end

    return utils.apiVersionCompare(">=", {12, 0, 8})
end

local function desiredSensorIds(sensorList, currentConfig)
    local ids = {}
    local seen = {}
    local entry
    local sensorId
    local index

    for index = 1, #(sensorList or {}) do
        entry = sensorList[index]
        sensorId = tonumber(entry and entry.set_telemetry_sensors)
        if sensorId and sensorId > 0 and not seen[sensorId] then
            ids[#ids + 1] = sensorId
            seen[sensorId] = true
        end
    end

    for index = 1, 40 do
        sensorId = tonumber(currentConfig["telem_sensor_slot_" .. tostring(index)]) or 0
        if sensorId > 0 and not seen[sensorId] then
            ids[#ids + 1] = sensorId
            seen[sensorId] = true
        end
    end

    table.sort(ids)
    return ids
end

local function finishRepair(node, ok, message)
    local state = node.state

    if type(state) ~= "table" then
        return false
    end

    state.repairInFlight = false
    clearActiveApi(state)
    if nodeIsOpen(node) ~= true then
        return false
    end

    node.app.ui.clearProgressDialog(true)
    if ok == true then
        diagnostics.openMessageDialog("@i18n(app.modules.validate_sensors.name)@", message or "@i18n(app.modules.validate_sensors.msg_repair_fin)@")
    else
        diagnostics.openMessageDialog("@i18n(app.modules.validate_sensors.name)@", message or "@i18n(app.modules.validate_sensors.msg_repair_failed)@")
    end

    if node.app.framework:getTask("telemetry") and node.app.framework:getTask("telemetry").reset then
        node.app.framework:getTask("telemetry").reset()
    end
    node:refresh(true, true)
    return true
end

local function runReboot(node)
    local mspTask = node.app.framework:getTask("msp")
    local sensorsTask = node.app.framework:getTask("sensors")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("REBOOT")

    if not api then
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_reboot_queue_failed)@")
        return false
    end

    if sensorsTask and sensorsTask.armSensorLostMute then
        sensorsTask:armSensorLostMute(10)
    end

    if api.clearValues then
        api.clearValues()
    end
    if api.setValue then
        api.setValue("rebootMode", 0)
    end

    trackActiveApi(node, "REBOOT", api)
    api.setUUID(utils.uuid("diag-sensors-reboot"))
    api.setCompleteHandler(function()
        unloadApi(mspTask, "REBOOT", api)
        finishRepair(node, true, "@i18n(app.modules.validate_sensors.msg_repair_fin)@")
    end)
    api.setErrorHandler(function(_, reason)
        unloadApi(mspTask, "REBOOT", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_reboot_failed)@")
    end)

    if api.write() ~= true then
        unloadApi(mspTask, "REBOOT", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_reboot_failed)@")
        return false
    end

    return true
end

local function runEepromWrite(node)
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE")

    if not api then
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_eeprom_failed)@")
        return false
    end

    trackActiveApi(node, "EEPROM_WRITE", api)
    api.setUUID(utils.uuid("diag-sensors-eeprom"))
    api.setCompleteHandler(function()
        unloadApi(mspTask, "EEPROM_WRITE", api)
        runReboot(node)
    end)
    api.setErrorHandler(function(_, reason)
        unloadApi(mspTask, "EEPROM_WRITE", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_eeprom_failed)@")
    end)

    if api.write() ~= true then
        unloadApi(mspTask, "EEPROM_WRITE", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_eeprom_failed)@")
        return false
    end

    return true
end

local function beginRepair(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api

    if state.repairInFlight == true then
        return true
    end

    if not canRepair(node) then
        diagnostics.openMessageDialog("@i18n(app.modules.validate_sensors.name)@", "@i18n(app.modules.validate_sensors.msg_repair_unavailable)@")
        return false
    end

    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("TELEMETRY_CONFIG")
    if not api then
        diagnostics.openMessageDialog("@i18n(app.modules.validate_sensors.name)@", "@i18n(app.modules.validate_sensors.msg_repair_loading_config)@")
        return false
    end

    state.repairInFlight = true
    node.app.ui.showLoader({
        kind = "save",
        title = "@i18n(app.modules.validate_sensors.name)@",
        message = "@i18n(app.modules.validate_sensors.msg_repair_updating)@",
        closeWhenIdle = false,
        modal = true
    })

    trackActiveApi(node, "TELEMETRY_CONFIG", api)
    api.setUUID(utils.uuid("diag-sensors-read"))
    api.setCompleteHandler(function()
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}
        local ids = desiredSensorIds(state.sensors, parsed)
        local index
        local key
        local value

        if api.clearValues then
            api.clearValues()
        end

        for key, value in pairs(parsed) do
            if api.setValue then
                api.setValue(key, value)
            end
        end

        for index = 1, 40 do
            api.setValue("telem_sensor_slot_" .. tostring(index), ids[index] or 0)
        end

        trackActiveApi(node, "TELEMETRY_CONFIG", api)
        api.setUUID(utils.uuid("diag-sensors-write"))
        api.setCompleteHandler(function()
            unloadApi(mspTask, "TELEMETRY_CONFIG", api)
            runEepromWrite(node)
        end)
        api.setErrorHandler(function(_, reason)
            unloadApi(mspTask, "TELEMETRY_CONFIG", api)
            finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_write_failed)@")
        end)

        if api.write() ~= true then
            unloadApi(mspTask, "TELEMETRY_CONFIG", api)
            finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_write_failed)@")
        end
    end)
    api.setErrorHandler(function(_, reason)
        unloadApi(mspTask, "TELEMETRY_CONFIG", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_read_failed)@")
    end)

    if api.read() ~= true then
        unloadApi(mspTask, "TELEMETRY_CONFIG", api)
        finishRepair(node, false, "@i18n(app.modules.validate_sensors.msg_repair_read_failed)@")
        return false
    end

    return true
end

function Page:open(ctx)
    local telemetry = ctx.app.framework:getTask("telemetry")
    local state = {
        sensors = diagnostics.sortSensorListByName(telemetry and telemetry.listSensors and telemetry.listSensors() or {}),
        fields = {},
        repairInFlight = false,
        lastMissingCount = nil,
        lastToolEnabled = nil,
        activeApiName = nil,
        activeApi = nil,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.validate_sensors.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.validate_sensors.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = {enabled = false, text = "*"}, help = true},
        state = state
    }

    function node:refresh(force, invalidateHeader)
        local telemetryTask = self.app.framework:getTask("telemetry")
        local invalidSensors = telemetryTask and telemetryTask.validateSensors and telemetryTask.validateSensors(false) or {}
        local invalidLookup = {}
        local missingCount = 0
        local index
        local sensor
        local field
        local enabled

        for index = 1, #(invalidSensors or {}) do
            invalidLookup[invalidSensors[index].key] = true
        end

        for index = 1, #(state.sensors or {}) do
            sensor = state.sensors[index]
            field = state.fields[sensor.key]
            if field then
                if invalidLookup[sensor.key] == true then
                    diagnostics.setFieldText(field, "@i18n(app.modules.validate_sensors.invalid)@", sensor.mandatory == true and ORANGE or RED)
                    missingCount = missingCount + 1
                else
                    diagnostics.setFieldText(field, "@i18n(app.modules.validate_sensors.ok)@", GREEN)
                end
            end
        end

        enabled = canRepair(self) and missingCount > 0 and state.repairInFlight ~= true
        if force == true or state.lastToolEnabled ~= enabled then
            self.navButtons.tool = {enabled = enabled, text = "*"}
            state.lastToolEnabled = enabled
            if invalidateHeader == true then
                self.app:_invalidateForm()
            end
        end

        state.lastMissingCount = missingCount
    end

    function node:buildForm(app)
        local index
        local sensor
        local line

        self.app = app

        for index = 1, #(state.sensors or {}) do
            sensor = state.sensors[index]
            line = form.addLine(sensor.name)
            state.fields[sensor.key] = form.addStaticText(line, diagnostics.valuePos(app, 110), "-")
        end

        self:refresh(true, false)
    end

    function node:wakeup()
        self:refresh(false, false)
    end

    function node:onToolMenu()
        return diagnostics.openConfirmDialog("@i18n(app.modules.validate_sensors.name)@", "@i18n(app.modules.validate_sensors.msg_repair)@", function()
            beginRepair(node)
        end)
    end

    function node:help()
        return diagnostics.openHelpDialog("@i18n(app.modules.validate_sensors.name)@", SENSOR_HELP)
    end

    function node:close()
        state.closed = true
        state.repairInFlight = false
        cleanupActiveApi(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
        state.fields = {}
    end

    return node
end

return Page
