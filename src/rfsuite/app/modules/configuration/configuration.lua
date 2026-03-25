--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local FEATURE_BIT_GPS = 7
local FEATURE_BIT_LED_STRIP = 16
local FEATURE_BIT_CMS = 19
local PID_LOOP_DENOMS = {1, 2, 3, 4}
local LOAD_HELP = {
    "@i18n(app.modules.configuration.help_p1)@",
    "@i18n(app.modules.configuration.help_p2)@"
}

local function noopHandler()
end

local function bitIsSet(value, bit)
    local mask = 1 << bit
    return ((tonumber(value) or 0) & mask) ~= 0
end

local function setBit(value, bit, enabled)
    local base = tonumber(value) or 0
    local mask = 1 << bit

    if enabled == true then
        return base | mask
    end

    return base & (~mask)
end

local function toBool(value)
    return value == true or value == 1
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

local function fieldLineY(app)
    return app and app.radio and app.radio.linePaddingTop or 0
end

local function fieldHeight(app)
    return app and app.radio and app.radio.navbuttonHeight or 30
end

local function textFieldPos(app)
    local width = app:_windowSize()
    local valueWidth = math.max(160, math.floor(width * 0.34))

    return {
        x = width - valueWidth - 8,
        y = fieldLineY(app),
        w = valueWidth,
        h = fieldHeight(app)
    }
end

local function boolFieldPos(app)
    local width = app:_windowSize()
    local valueWidth = math.max(110, math.floor(width * 0.24))

    return {
        x = width - valueWidth - 8,
        y = fieldLineY(app),
        w = valueWidth,
        h = fieldHeight(app)
    }
end

local function applyControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function pidLoopChoices(state)
    local rawGyroHz
    local gyroHz
    local choices = {}
    local seen = {}
    local index
    local denom
    local pidKhz
    local rounded
    local text

    rawGyroHz = (tonumber(state.pidBaseHz) or 0)
    if rawGyroHz <= 0 then
        rawGyroHz = 1000000 / math.max(1, tonumber(state.gyroDeltaUs) or 250)
    end
    gyroHz = math.floor((rawGyroHz / 1000) + 0.5) * 1000

    for index = 1, #PID_LOOP_DENOMS do
        denom = PID_LOOP_DENOMS[index]
        pidKhz = (gyroHz / denom) / 1000
        rounded = math.floor((pidKhz * 100) + 0.5) / 100
        text = string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
        if not text:find("%.") and rounded >= 2 then
            text = text .. ".0"
        end
        choices[#choices + 1] = {string.format("%s kHz", text), denom}
        seen[denom] = true
    end

    if state.currentPidLoop ~= nil and seen[state.currentPidLoop] ~= true then
        pidKhz = (gyroHz / math.max(1, tonumber(state.currentPidLoop) or 1)) / 1000
        rounded = math.floor((pidKhz * 100) + 0.5) / 100
        text = string.format("%.2f", rounded):gsub("0+$", ""):gsub("%.$", "")
        if text == "" then
            text = "@i18n(app.modules.configuration.pid_loop_custom)@"
        end
        choices[#choices + 1] = {string.format("%s (%s)", "@i18n(app.modules.configuration.pid_loop_custom)@", text), state.currentPidLoop}
    end

    return choices
end

local function readParsed(api)
    local data = api and api.data and api.data() or nil
    return data and data.parsed or nil
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local generation
    local pending

    local function settle()
        pending = pending - 1
        if pending > 0 then
            return
        end

        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        state.loading = false
        state.loaded = true
        state.loadStarted = true
        state.saveError = nil
        state.loadError = nil
        state.originalName = state.currentName
        state.originalPidLoop = state.currentPidLoop
        state.originalFeatures = state.currentFeatures
        node.app:setPageDirty(false)
        if node.app.requestLoaderClose then
            node.app:requestLoaderClose()
        else
            node.app.ui.clearProgressDialog(true)
        end
        node.app:_invalidateForm()
    end

    local function fail(message)
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        cleanupActiveApis(state, node.app)
        state.loading = false
        state.loaded = false
        state.loadStarted = true
        state.loadError = tostring(message or "read_failed")
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function beginRead(apiName, onComplete, unavailableMsg, readFailedMsg)
        local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(apiName)

        if not api then
            fail(unavailableMsg)
            return false
        end

        trackActiveApi(state, apiName, api)
        if api.setUUID then
            api.setUUID(utils.uuid("configuration-" .. string.lower(apiName)))
        end
        api.setCompleteHandler(function()
            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                clearActiveApi(state, apiName)
                unloadApi(mspTask, apiName, api)
                return
            end

            if type(onComplete) == "function" then
                onComplete(api)
            end
            clearActiveApi(state, apiName)
            unloadApi(mspTask, apiName, api)
            settle()
        end)
        api.setErrorHandler(function(_, reason)
            clearActiveApi(state, apiName)
            unloadApi(mspTask, apiName, api)
            fail(readFailedMsg or reason or "read_failed")
        end)

        if api.read() ~= true then
            clearActiveApi(state, apiName)
            unloadApi(mspTask, apiName, api)
            fail(readFailedMsg)
            return false
        end

        return true
    end

    cleanupActiveApis(state, node.app)
    state.loadGeneration = (state.loadGeneration or 0) + 1
    generation = state.loadGeneration
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.saveError = nil
    state.currentName = ""
    state.currentPidLoop = 1
    state.currentFeatures = 0
    state.gyroDeltaUs = 250
    state.pidBaseHz = 0
    pending = 4
    state.loadStarted = true
    node.app:setPageDirty(false)

    if showLoader == true then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.configuration.name)@",
            message = "@i18n(app.modules.configuration.progress_loading)@",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if beginRead("NAME", function(api)
        local parsed = readParsed(api)
        state.currentName = parsed and tostring(parsed.name or "") or ""
    end, "@i18n(app.modules.configuration.error_name_api_unavailable)@", "@i18n(app.modules.configuration.error_name_read_failed)@") ~= true then
        return false
    end

    if beginRead("ADVANCED_CONFIG", function(api)
        local parsed = readParsed(api)
        state.currentPidLoop = tonumber(parsed and parsed.pid_process_denom or 1) or 1
        state.pidBaseHz = tonumber(parsed and parsed.pid_process_denom_base_hz or 0) or 0
        state.gyroSyncCompat = tonumber(parsed and parsed.gyro_sync_denom_compat or 1) or 1
    end, "@i18n(app.modules.configuration.error_advanced_api_unavailable)@", "@i18n(app.modules.configuration.error_advanced_read_failed)@") ~= true then
        return false
    end

    if beginRead("FEATURE_CONFIG", function(api)
        local parsed = readParsed(api)
        state.currentFeatures = tonumber(parsed and parsed.enabledFeatures or 0) or 0
    end, "@i18n(app.modules.configuration.error_feature_api_unavailable)@", "@i18n(app.modules.configuration.error_feature_read_failed)@") ~= true then
        return false
    end

    if beginRead("STATUS", function(api)
        local parsed = readParsed(api)
        local delta = tonumber(parsed and parsed.task_delta_time_gyro or 0) or 0
        if delta > 0 then
            state.gyroDeltaUs = delta
        end
    end, nil, nil) ~= true then
        return false
    end

    return true
end

local function runReboot(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local sensorsTask = node.app.framework:getTask("sensors")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("REBOOT")

    local function finishSuccess()
        cleanupActiveApis(state, node.app)
        state.dirty = false
        state.saving = false
        state.saveError = nil
        state.originalName = state.currentName
        state.originalPidLoop = state.currentPidLoop
        state.originalFeatures = state.currentFeatures
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = tostring(message or "@i18n(app.modules.configuration.error_save_failed)@")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    if not api then
        fail("@i18n(app.modules.configuration.error_eeprom_write_failed)@")
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
    if api.setUUID then
        api.setUUID(utils.uuid("configuration-reboot"))
    end

    if api.write() ~= true then
        unloadApi(mspTask, "REBOOT", api)
        fail("@i18n(app.modules.configuration.error_eeprom_write_failed)@")
        return false
    end

    unloadApi(mspTask, "REBOOT", api)
    finishSuccess()
    return true
end

local function performSave(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local nameApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("NAME")
    local advApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("ADVANCED_CONFIG")
    local featureApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FEATURE_CONFIG")
    local eepromApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE")
    local featuresChanged

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = tostring(message or "@i18n(app.modules.configuration.error_save_failed)@")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    if state.loading == true or state.saving == true or state.loaded ~= true or state.dirty ~= true then
        return false
    end

    if not nameApi then
        fail("@i18n(app.modules.configuration.error_name_api_unavailable)@")
        return false
    end
    if not advApi then
        fail("@i18n(app.modules.configuration.error_advanced_api_unavailable)@")
        return false
    end
    if not featureApi then
        fail("@i18n(app.modules.configuration.error_feature_api_unavailable)@")
        return false
    end
    if not eepromApi then
        fail("@i18n(app.modules.configuration.error_eeprom_api_unavailable)@")
        return false
    end

    cleanupActiveApis(state, node.app)
    state.saving = true
    state.saveError = nil
    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.configuration.name)@",
        message = "@i18n(app.modules.configuration.progress_saving)@",
        closeWhenIdle = false,
        modal = true
    })

    trackActiveApi(state, "NAME", nameApi)
    trackActiveApi(state, "ADVANCED_CONFIG", advApi)
    trackActiveApi(state, "FEATURE_CONFIG", featureApi)
    trackActiveApi(state, "EEPROM_WRITE", eepromApi)

    if nameApi.clearValues then
        nameApi.clearValues()
    end
    if advApi.clearValues then
        advApi.clearValues()
    end
    if featureApi.clearValues then
        featureApi.clearValues()
    end

    if nameApi.setValue then
        nameApi.setValue("name", state.currentName or "")
    end

    if advApi.setValue then
        advApi.setValue("gyro_sync_denom_compat", tonumber(state.gyroSyncCompat) or 1)
        advApi.setValue("pid_process_denom", tonumber(state.currentPidLoop) or 1)
    end

    if featureApi.setValue then
        featuresChanged = (tonumber(state.currentFeatures) or 0) ~= (tonumber(state.originalFeatures) or 0)
        if featuresChanged == true then
            featureApi.setValue("enabledFeatures->gps", bitIsSet(state.currentFeatures, FEATURE_BIT_GPS) and 1 or 0)
            featureApi.setValue("enabledFeatures->led_strip", bitIsSet(state.currentFeatures, FEATURE_BIT_LED_STRIP) and 1 or 0)
            featureApi.setValue("enabledFeatures->cms", bitIsSet(state.currentFeatures, FEATURE_BIT_CMS) and 1 or 0)
        end
    end

    if nameApi.setUUID then
        nameApi.setUUID(utils.uuid("configuration-name-write"))
    end
    if advApi.setUUID then
        advApi.setUUID(utils.uuid("configuration-advanced-write"))
    end
    if featureApi.setUUID then
        featureApi.setUUID(utils.uuid("configuration-feature-write"))
    end
    if eepromApi.setUUID then
        eepromApi.setUUID(utils.uuid("configuration-eeprom-write"))
    end

    eepromApi.setCompleteHandler(function()
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        if nodeIsOpen(node) == true then
            runReboot(node)
        end
    end)
    eepromApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        if nodeIsOpen(node) == true then
            fail("@i18n(app.modules.configuration.error_eeprom_write_failed)@")
        end
    end)

    featureApi.setCompleteHandler(function()
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        if nodeIsOpen(node) == true then
            if eepromApi.write() ~= true then
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail("@i18n(app.modules.configuration.error_eeprom_write_failed)@")
            end
        end
    end)
    featureApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        if nodeIsOpen(node) == true then
            fail("@i18n(app.modules.configuration.error_feature_write_failed)@")
        end
    end)

    advApi.setCompleteHandler(function()
        clearActiveApi(state, "ADVANCED_CONFIG")
        unloadApi(mspTask, "ADVANCED_CONFIG", advApi)
        if nodeIsOpen(node) == true then
            if featuresChanged == true then
                if featureApi.write() ~= true then
                    clearActiveApi(state, "FEATURE_CONFIG")
                    unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
                    clearActiveApi(state, "EEPROM_WRITE")
                    unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                    fail("@i18n(app.modules.configuration.error_feature_write_failed)@")
                end
            else
                clearActiveApi(state, "FEATURE_CONFIG")
                unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
                if eepromApi.write() ~= true then
                    clearActiveApi(state, "EEPROM_WRITE")
                    unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                    fail("@i18n(app.modules.configuration.error_eeprom_write_failed)@")
                end
            end
        end
    end)
    advApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "ADVANCED_CONFIG")
        unloadApi(mspTask, "ADVANCED_CONFIG", advApi)
        if nodeIsOpen(node) == true then
            fail("@i18n(app.modules.configuration.error_advanced_write_failed)@")
        end
    end)

    nameApi.setCompleteHandler(function()
        clearActiveApi(state, "NAME")
        unloadApi(mspTask, "NAME", nameApi)
        if nodeIsOpen(node) == true then
            if advApi.write() ~= true then
                clearActiveApi(state, "ADVANCED_CONFIG")
                unloadApi(mspTask, "ADVANCED_CONFIG", advApi)
                clearActiveApi(state, "FEATURE_CONFIG")
                unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail("@i18n(app.modules.configuration.error_advanced_write_failed)@")
            end
        end
    end)
    nameApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "NAME")
        unloadApi(mspTask, "NAME", nameApi)
        if nodeIsOpen(node) == true then
            fail("@i18n(app.modules.configuration.error_name_write_failed)@")
        end
    end)

    if nameApi.write() ~= true then
        clearActiveApi(state, "NAME")
        unloadApi(mspTask, "NAME", nameApi)
        clearActiveApi(state, "ADVANCED_CONFIG")
        unloadApi(mspTask, "ADVANCED_CONFIG", advApi)
        clearActiveApi(state, "FEATURE_CONFIG")
        unloadApi(mspTask, "FEATURE_CONFIG", featureApi)
        clearActiveApi(state, "EEPROM_WRITE")
        unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
        fail("@i18n(app.modules.configuration.error_name_write_failed)@")
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        loadStarted = false,
        loadGeneration = 0,
        loading = false,
        loaded = false,
        saving = false,
        dirty = false,
        closed = false,
        loadError = nil,
        saveError = nil,
        currentName = "",
        currentPidLoop = 1,
        currentFeatures = 0,
        originalName = "",
        originalPidLoop = 1,
        originalFeatures = 0,
        gyroDeltaUs = 250,
        pidBaseHz = 0,
        gyroSyncCompat = 1,
        activeApis = {}
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.configuration.name)@",
        subtitle = ctx.item.subtitle or "System configuration",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "@i18n(app.modules.configuration.progress_loading)@",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:canSave()
        return state.loaded == true and state.loading ~= true and state.saving ~= true and state.dirty == true
    end

    function node:buildForm(app)
        local line
        local control

        self.app = app

        if state.loadError then
            line = form.addLine("Status")
            form.addStaticText(line, nil, "Error")
            line = form.addLine("")
            form.addStaticText(line, diagnostics.valuePos(app, math.floor(app:_windowSize() * 0.72)), tostring(state.loadError))
            return
        end

        if state.loading == true or state.loaded ~= true then
            line = form.addLine("Status")
            form.addStaticText(line, nil, state.loading == true and "@i18n(app.modules.configuration.loading)@" or "Waiting...")
            return
        end

        if state.saveError then
            line = form.addLine("Status")
            form.addStaticText(line, diagnostics.valuePos(app, math.floor(app:_windowSize() * 0.72)), tostring(state.saveError))
        end

        control = form.addTextField(form.addLine("@i18n(app.modules.configuration.craft_name)@"), textFieldPos(app),
            function()
                return state.currentName
            end,
            function(newValue)
                local value = tostring(newValue or "")
                if value ~= state.currentName then
                    state.currentName = value
                    state.dirty = true
                    app:setPageDirty(true)
                end
            end)
        applyControlValue(control, state.currentName or "")

        control = form.addChoiceField(form.addLine("@i18n(app.modules.configuration.pid_loop_speed)@"), textFieldPos(app), pidLoopChoices(state),
            function()
                return state.currentPidLoop
            end,
            function(newValue)
                local value = tonumber(newValue) or 1
                if value ~= state.currentPidLoop then
                    state.currentPidLoop = value
                    state.dirty = true
                    app:setPageDirty(true)
                end
            end)
        applyControlValue(control, state.currentPidLoop)

        control = form.addBooleanField(form.addLine("@i18n(app.modules.configuration.feature_gps)@"), boolFieldPos(app),
            function()
                return bitIsSet(state.currentFeatures, FEATURE_BIT_GPS)
            end,
            function(newValue)
                local updated = setBit(state.currentFeatures, FEATURE_BIT_GPS, toBool(newValue))
                if updated ~= state.currentFeatures then
                    state.currentFeatures = updated
                    state.dirty = true
                    app:setPageDirty(true)
                end
            end)
        applyControlValue(control, bitIsSet(state.currentFeatures, FEATURE_BIT_GPS))

        control = form.addBooleanField(form.addLine("@i18n(app.modules.configuration.feature_led_strip)@"), boolFieldPos(app),
            function()
                return bitIsSet(state.currentFeatures, FEATURE_BIT_LED_STRIP)
            end,
            function(newValue)
                local updated = setBit(state.currentFeatures, FEATURE_BIT_LED_STRIP, toBool(newValue))
                if updated ~= state.currentFeatures then
                    state.currentFeatures = updated
                    state.dirty = true
                    app:setPageDirty(true)
                end
            end)
        applyControlValue(control, bitIsSet(state.currentFeatures, FEATURE_BIT_LED_STRIP))

        control = form.addBooleanField(form.addLine("@i18n(app.modules.configuration.feature_cms)@"), boolFieldPos(app),
            function()
                return bitIsSet(state.currentFeatures, FEATURE_BIT_CMS)
            end,
            function(newValue)
                local updated = setBit(state.currentFeatures, FEATURE_BIT_CMS, toBool(newValue))
                if updated ~= state.currentFeatures then
                    state.currentFeatures = updated
                    state.dirty = true
                    app:setPageDirty(true)
                end
            end)
        applyControlValue(control, bitIsSet(state.currentFeatures, FEATURE_BIT_CMS))
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

        state.dirty = false
        self.app:setPageDirty(false)
        return startLoad(self, true)
    end

    function node:save()
        if not self:canSave() then
            return false
        end

        return performSave(self)
    end

    function node:help()
        return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.configuration.name)@") .. " Help", LOAD_HELP)
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
