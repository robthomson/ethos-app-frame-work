--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local utils = require("lib.utils")

local TAIL_MODE_CHOICES = {
    {"@i18n(api.MIXER_CONFIG.tbl_tail_variable_pitch)@", 0},
    {"@i18n(api.MIXER_CONFIG.tbl_tail_motororized_tail)@", 1},
    {"@i18n(api.MIXER_CONFIG.tbl_tail_bidirectional)@", 2}
}

local DIRECTION_CHOICES = {
    {"@i18n(api.MIXER_INPUT.tbl_reversed)@", 0},
    {"@i18n(api.MIXER_INPUT.tbl_normal)@", 1}
}

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function applyControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
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
    local api

    if type(state.activeApis) ~= "table" then
        return nil
    end

    api = state.activeApis[apiName]
    state.activeApis[apiName] = nil
    return api
end

local function cleanupActiveApis(state, app)
    local apiName
    local api
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    if type(state) ~= "table" or type(state.activeApis) ~= "table" then
        return
    end

    for apiName, api in pairs(state.activeApis) do
        if api and api.setCompleteHandler then
            api.setCompleteHandler(function() end)
        end
        if api and api.setErrorHandler then
            api.setErrorHandler(function() end)
        end
        if api and api.setUUID then
            api.setUUID(nil)
        end
        unloadApi(mspTask, apiName, api)
        state.activeApis[apiName] = nil
    end
end

local function readParsed(api)
    local data = api and api.data and api.data() or nil
    return data and data.parsed or nil
end

local function u16ToS16(value)
    value = tonumber(value) or 0
    if value >= 0x8000 then
        return value - 0x10000
    end
    return value
end

local function s16ToU16(value)
    value = tonumber(value) or 0
    if value < 0 then
        return value + 0x10000
    end
    return value
end

local function round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function rateToDir(value)
    if u16ToS16(value) < 0 then
        return 0
    end
    return 1
end

local function isMotorizedMode(mode)
    return (tonumber(mode) or -1) >= 1
end

local function rawTrimFromControlValue(value, mode)
    local numeric = tonumber(value) or 0

    if isMotorizedMode(mode) then
        return numeric
    end

    return round(numeric * 100 / 24)
end

local function controlTrimFromRawValue(value, mode)
    local numeric = tonumber(value) or 0

    if isMotorizedMode(mode) then
        return numeric
    end

    return round(math.abs(numeric) * 24 / 100)
end

local function rawLimitFromControlValue(value, mode)
    local numeric = tonumber(value) or 0

    if isMotorizedMode(mode) then
        return numeric
    end

    return round(numeric * 100 / 24)
end

local function controlLimitFromRawValue(value, mode)
    local numeric = tonumber(value) or 0

    if isMotorizedMode(mode) then
        return math.abs(numeric)
    end

    return round(math.abs(numeric) * 24 / 100)
end

local function applyTailModeDefaults(state, previousMode, newMode)
    local oldMode = tonumber(previousMode) or 0
    local targetMode = tonumber(newMode) or 0
    local rawTrim
    local rawCw
    local rawCcw

    if isMotorizedMode(oldMode) == isMotorizedMode(targetMode) then
        return false
    end

    rawTrim = rawTrimFromControlValue(state.tailCenterTrim, oldMode)
    rawCw = rawLimitFromControlValue(state.yawCwLimit, oldMode)
    rawCcw = rawLimitFromControlValue(state.yawCcwLimit, oldMode)

    state.tailCenterTrim = controlTrimFromRawValue(rawTrim, targetMode)
    state.yawCwLimit = controlLimitFromRawValue(rawCw, targetMode)
    state.yawCcwLimit = controlLimitFromRawValue(rawCcw, targetMode)
    state.yawCalibration = isMotorizedMode(targetMode) and 1000 or 250

    return true
end

local function writeApiValues(node, apiName, values, uuidSuffix, done, failed)
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(apiName) or nil
    local key

    if not api then
        if type(failed) == "function" then
            failed(apiName .. " unavailable.")
        end
        return false
    end

    trackActiveApi(node.state, apiName, api)
    if api.clearValues then
        api.clearValues()
    end
    for key, value in pairs(values or {}) do
        api.setValue(key, value)
    end
    if api.setUUID then
        api.setUUID(utils.uuid(uuidSuffix))
    end
    api.setCompleteHandler(function()
        clearActiveApi(node.state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(done) == "function" then
            done()
        end
    end)
    api.setErrorHandler(function(_, reason)
        clearActiveApi(node.state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(reason or (apiName .. " write failed."))
        end
    end)

    if api.write() ~= true then
        clearActiveApi(node.state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(apiName .. " write failed.")
        end
        return false
    end

    return true
end

local function runReboot(node, onSuccess, onError)
    local mspTask = node.app.framework:getTask("msp")
    local sensorsTask = node.app.framework:getTask("sensors")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("REBOOT")

    if not api then
        if type(onError) == "function" then
            onError("Reboot unavailable.")
        end
        return false
    end

    if sensorsTask and sensorsTask.armSensorLostMute then
        sensorsTask:armSensorLostMute(10)
    end

    if api.clearValues then
        api.clearValues()
    end
    if api.setUUID then
        api.setUUID(utils.uuid("mixer-tail-reboot"))
    end

    if api.write() ~= true then
        unloadApi(mspTask, "REBOOT", api)
        if type(onError) == "function" then
            onError("Reboot failed.")
        end
        return false
    end

    unloadApi(mspTask, "REBOOT", api)
    if type(onSuccess) == "function" then
        onSuccess()
    end
    return true
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local generation = (state.loadGeneration or 0) + 1
    local mixerApi
    local yawApi

    state.loadGeneration = generation
    cleanupActiveApis(state, node.app)
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.saveError = nil
    node.app:setPageDirty(false)

    if showLoader == true then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "Tail",
            message = "Loading tail settings.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    local function fail(message)
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        cleanupActiveApis(state, node.app)
        state.loading = false
        state.loaded = false
        state.loadError = tostring(message or "Load failed.")
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function complete()
        local mode
        local trim
        local rate
        local minValue
        local maxValue

        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        mode = tonumber(state.mixerConfigRaw.tail_rotor_mode or 0) or 0
        trim = tonumber(state.mixerConfigRaw.tail_center_trim or 0) or 0
        rate = tonumber(state.yawRaw.rate_stabilized_yaw or 0) or 0
        minValue = tonumber(state.yawRaw.min_stabilized_yaw or 0) or 0
        maxValue = tonumber(state.yawRaw.max_stabilized_yaw or 0) or 0

        state.tailMode = mode
        state.renderTailMode = mode
        state.originalTailMode = mode
        state.tailMotorIdle = tonumber(state.mixerConfigRaw.tail_motor_idle or 0) or 0
        state.yawDirection = rateToDir(rate)
        state.yawCalibration = math.abs(u16ToS16(rate))

        state.tailCenterTrim = controlTrimFromRawValue(trim, mode)
        state.yawCwLimit = controlLimitFromRawValue(u16ToS16(minValue), mode)
        state.yawCcwLimit = controlLimitFromRawValue(u16ToS16(maxValue), mode)

        state.loading = false
        state.loaded = true
        node.app:setPageDirty(false)
        node.app:requestLoaderClose()
        node.app:_invalidateForm()
    end

    yawApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("GET_MIXER_INPUT_YAW") or nil
    mixerApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("MIXER_CONFIG") or nil

    if not mixerApi then
        fail("MIXER_CONFIG unavailable.")
        return false
    end
    if not yawApi then
        fail("GET_MIXER_INPUT_YAW unavailable.")
        return false
    end

    trackActiveApi(state, "MIXER_CONFIG", mixerApi)
    if mixerApi.setUUID then
        mixerApi.setUUID(utils.uuid("mixer-tail-config"))
    end
    mixerApi.setCompleteHandler(function()
        clearActiveApi(state, "MIXER_CONFIG")
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            unloadApi(mspTask, "MIXER_CONFIG", mixerApi)
            return
        end

        state.mixerConfigRaw = copyTable(readParsed(mixerApi))
        unloadApi(mspTask, "MIXER_CONFIG", mixerApi)
        trackActiveApi(state, "GET_MIXER_INPUT_YAW", yawApi)
        if yawApi.setUUID then
            yawApi.setUUID(utils.uuid("mixer-tail-yaw"))
        end
        yawApi.setCompleteHandler(function()
            clearActiveApi(state, "GET_MIXER_INPUT_YAW")
            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                unloadApi(mspTask, "GET_MIXER_INPUT_YAW", yawApi)
                return
            end

            state.yawRaw = copyTable(readParsed(yawApi))
            unloadApi(mspTask, "GET_MIXER_INPUT_YAW", yawApi)
            complete()
        end)
        yawApi.setErrorHandler(function(_, reason)
            clearActiveApi(state, "GET_MIXER_INPUT_YAW")
            unloadApi(mspTask, "GET_MIXER_INPUT_YAW", yawApi)
            fail(reason or "Failed to read yaw mixer input.")
        end)
        if yawApi.read() ~= true then
            clearActiveApi(state, "GET_MIXER_INPUT_YAW")
            unloadApi(mspTask, "GET_MIXER_INPUT_YAW", yawApi)
            fail("Failed to read yaw mixer input.")
        end
    end)
    mixerApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "MIXER_CONFIG")
        unloadApi(mspTask, "MIXER_CONFIG", mixerApi)
        fail(reason or "Failed to read mixer config.")
    end)

    if mixerApi.read() ~= true then
        clearActiveApi(state, "MIXER_CONFIG")
        unloadApi(mspTask, "MIXER_CONFIG", mixerApi)
        fail("Failed to read mixer config.")
        return false
    end

    return true
end

local function performSave(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local eepromApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE")
    local mixerValues = copyTable(state.mixerConfigRaw)
    local yawValues = copyTable(state.yawRaw)
    local modeChanged = tonumber(state.tailMode or 0) ~= tonumber(state.originalTailMode or 0)
    local motorized = isMotorizedMode(state.tailMode)

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = tostring(message or "Save failed.")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function finishSuccess()
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = nil
        state.originalTailMode = state.tailMode
        state.renderTailMode = state.tailMode
        state.mixerConfigRaw = mixerValues
        state.yawRaw = yawValues
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    if state.loading == true or state.saving == true or state.loaded ~= true or node.app.pageDirty ~= true then
        return false
    end
    if not eepromApi then
        fail("EEPROM write unavailable.")
        return false
    end

    mixerValues.tail_rotor_mode = tonumber(state.tailMode or 0) or 0
    if motorized then
        mixerValues.tail_motor_idle = (tonumber(state.tailMotorIdle or 0) or 0) / 10
        mixerValues.tail_center_trim = (tonumber(state.tailCenterTrim or 0) or 0) / 10
    else
        mixerValues.tail_center_trim = (rawTrimFromControlValue(state.tailCenterTrim, state.tailMode) or 0) / 10
    end

    yawValues.rate_stabilized_yaw = s16ToU16((math.abs(tonumber(state.yawCalibration or 0) or 0)) * ((tonumber(state.yawDirection) == 0) and -1 or 1))
    if motorized then
        yawValues.min_stabilized_yaw = s16ToU16(-math.abs(tonumber(state.yawCwLimit or 0) or 0))
        yawValues.max_stabilized_yaw = s16ToU16(math.abs(tonumber(state.yawCcwLimit or 0) or 0))
    else
        yawValues.min_stabilized_yaw = s16ToU16(-round((tonumber(state.yawCwLimit or 0) or 0) * 100 / 24))
        yawValues.max_stabilized_yaw = s16ToU16(round((tonumber(state.yawCcwLimit or 0) or 0) * 100 / 24))
    end

    state.saving = true
    state.saveError = nil
    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "Tail",
        message = "Saving tail settings.",
        closeWhenIdle = false,
        modal = true
    })

    return writeApiValues(node, "MIXER_CONFIG", mixerValues, "mixer-tail-write-config", function()
        writeApiValues(node, "GET_MIXER_INPUT_YAW", yawValues, "mixer-tail-write-yaw", function()
            trackActiveApi(state, "EEPROM_WRITE", eepromApi)
            if eepromApi.clearValues then
                eepromApi.clearValues()
            end
            if eepromApi.setUUID then
                eepromApi.setUUID(utils.uuid("mixer-tail-eeprom"))
            end
            eepromApi.setCompleteHandler(function()
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                if modeChanged then
                    runReboot(node, finishSuccess, fail)
                else
                    finishSuccess()
                end
            end)
            eepromApi.setErrorHandler(function(_, reason)
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail(reason or "EEPROM write failed.")
            end)
            if eepromApi.write() ~= true then
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail("EEPROM write failed.")
            end
        end, fail)
    end, fail)
end

function Page:open(ctx)
    local node = {
        title = ctx.item.title or "Tail",
        subtitle = ctx.item.subtitle or "Tail mode and yaw setup",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        state = {
            loading = false,
            loaded = false,
            saving = false,
            loadError = nil,
            saveError = nil,
            tailMode = 0,
            renderTailMode = 0,
            originalTailMode = 0,
            tailMotorIdle = 0,
            yawDirection = 1,
            tailCenterTrim = 0,
            yawCalibration = 0,
            yawCwLimit = 0,
            yawCcwLimit = 0,
            mixerConfigRaw = {},
            yawRaw = {},
            activeApis = {}
        }
    }

    local function markDirty()
        node.app:setPageDirty(true)
    end

    function node:buildForm(app)
        local motorized
        local control

        self.app = app

        if self.state.loading == true then
            form.addLine("Loading tail settings.")
            return
        end

        if self.state.loadError then
            form.addLine("Error: " .. tostring(self.state.loadError))
            return
        end

        if self.state.saveError then
            form.addLine("Save error: " .. tostring(self.state.saveError))
        end

        motorized = isMotorizedMode(self.state.renderTailMode)

        control = form.addChoiceField(form.addLine("Tail Mode"), nil, TAIL_MODE_CHOICES,
            function()
                return self.state.tailMode
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.tailMode then
                    if applyTailModeDefaults(self.state, self.state.renderTailMode, newValue) then
                        self.state.renderTailMode = newValue
                        self.app:_invalidateForm()
                    end
                    self.state.tailMode = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.tailMode)

        control = form.addChoiceField(form.addLine("Yaw Direction"), nil, DIRECTION_CHOICES,
            function()
                return self.state.yawDirection
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.yawDirection then
                    self.state.yawDirection = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.yawDirection)

        if motorized then
            control = form.addNumberField(form.addLine("Tail Idle Thr%"), nil, 0, 250,
                function()
                    return self.state.tailMotorIdle
                end,
                function(newValue)
                    newValue = tonumber(newValue) or 0
                    if newValue ~= self.state.tailMotorIdle then
                        self.state.tailMotorIdle = newValue
                        markDirty()
                    end
                end)
            if control and control.decimals then
                control:decimals(1)
            end
            if control and control.suffix then
                control:suffix("%")
            end
            applyControlValue(control, self.state.tailMotorIdle)
            control = form.addNumberField(form.addLine("Tail Center Offset"), nil, -500, 500,
                function()
                    return self.state.tailCenterTrim
                end,
                function(newValue)
                    newValue = tonumber(newValue) or 0
                    if newValue ~= self.state.tailCenterTrim then
                        self.state.tailCenterTrim = newValue
                        markDirty()
                    end
                end)
            if control and control.decimals then
                control:decimals(1)
            end
            if control and control.suffix then
                control:suffix("%")
            end
            applyControlValue(control, self.state.tailCenterTrim)
        else
            control = form.addNumberField(form.addLine("Yaw Center Trim"), nil, -2500, 2500,
                function()
                    return self.state.tailCenterTrim
                end,
                function(newValue)
                    newValue = tonumber(newValue) or 0
                    if newValue ~= self.state.tailCenterTrim then
                        self.state.tailCenterTrim = newValue
                        markDirty()
                    end
                end)
            if control and control.decimals then
                control:decimals(1)
            end
            if control and control.suffix then
                control:suffix("°")
            end
            applyControlValue(control, self.state.tailCenterTrim)
        end

        control = form.addNumberField(form.addLine("Yaw Calibration"), nil, 200, 2000,
            function()
                return self.state.yawCalibration
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.yawCalibration then
                    self.state.yawCalibration = newValue
                    markDirty()
                end
            end)
        if control and control.decimals then
            control:decimals(1)
        end
        if control and control.suffix then
            control:suffix("%")
        end
        applyControlValue(control, self.state.yawCalibration)

        control = form.addNumberField(form.addLine("Yaw CW Limit"), nil, 0, motorized and 2000 or 600,
            function()
                return self.state.yawCwLimit
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.yawCwLimit then
                    self.state.yawCwLimit = newValue
                    markDirty()
                end
            end)
        if control and control.decimals then
            control:decimals(1)
        end
        if control and control.suffix then
            control:suffix(motorized and "%" or "°")
        end
        applyControlValue(control, self.state.yawCwLimit)

        control = form.addNumberField(form.addLine("Yaw CCW Limit"), nil, 0, motorized and 2000 or 600,
            function()
                return self.state.yawCcwLimit
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.yawCcwLimit then
                    self.state.yawCcwLimit = newValue
                    markDirty()
                end
            end)
        if control and control.decimals then
            control:decimals(1)
        end
        if control and control.suffix then
            control:suffix(motorized and "%" or "°")
        end
        applyControlValue(control, self.state.yawCcwLimit)
    end

    function node:canSave()
        local requireDirty = true

        if self.state.loaded ~= true or self.state.loading == true or self.state.saving == true then
            return false
        end
        if self.app and self.app._saveDirtyOnly then
            requireDirty = self.app:_saveDirtyOnly() == true
        end
        if requireDirty == true then
            return self.app.pageDirty == true
        end
        return true
    end

    function node:reload()
        if self.state.saving == true then
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

    function node:wakeup()
        if self.state.loaded ~= true and self.state.loading ~= true and self.state.loadError == nil then
            startLoad(self, true)
        end
    end

    function node:close()
        self.state.closed = true
        cleanupActiveApis(self.state, self.app)
        self.app.ui.clearProgressDialog(true)
    end

    return node
end

return Page
