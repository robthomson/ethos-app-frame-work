--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local utils = require("lib.utils")

local SWASH_TYPE_CHOICES = {
    {"None", 0},
    {"Direct", 1},
    {"CPPM 120", 2},
    {"CPPM 135", 3},
    {"CPPM 140", 4},
    {"FPM 90 L", 5},
    {"FPM 90 V", 6}
}

local ROTOR_DIRECTION_CHOICES = {
    {"@i18n(api.MIXER_CONFIG.tbl_cw)@", 0},
    {"@i18n(api.MIXER_CONFIG.tbl_ccw)@", 1}
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

local function rateToDir(value)
    if u16ToS16(value) < 0 then
        return 0
    end
    return 1
end

local function applyDirectionToRate(rawRate, dirValue)
    local magnitude = math.abs(u16ToS16(rawRate))
    local sign = (tonumber(dirValue) == 0) and -1 or 1
    return s16ToU16(magnitude * sign)
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
        api.setUUID(utils.uuid("mixer-swash-reboot"))
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
    local pitchApi
    local rollApi
    local collectiveApi

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
            title = node.title or "Swash",
            message = "Loading mixer settings.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
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
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        state.originalSwashType = state.swashType
        state.loading = false
        state.loaded = true
        node.app:setPageDirty(false)
        node.app:requestLoaderClose()
        node.app:_invalidateForm()
    end

    local function beginCollectiveRead()
        collectiveApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("GET_MIXER_INPUT_COLLECTIVE") or nil
        if not collectiveApi then
            fail("GET_MIXER_INPUT_COLLECTIVE unavailable.")
            return false
        end

        trackActiveApi(state, "GET_MIXER_INPUT_COLLECTIVE", collectiveApi)
        if collectiveApi.setUUID then
            collectiveApi.setUUID(utils.uuid("mixer-swash-collective"))
        end
        collectiveApi.setCompleteHandler(function()
            local parsed = copyTable(readParsed(collectiveApi))

            clearActiveApi(state, "GET_MIXER_INPUT_COLLECTIVE")
            unloadApi(mspTask, "GET_MIXER_INPUT_COLLECTIVE", collectiveApi)
            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                return
            end

            state.collectiveRaw = parsed
            state.collectiveDirection = rateToDir(parsed.rate_stabilized_collective)
            complete()
        end)
        collectiveApi.setErrorHandler(function(_, reason)
            clearActiveApi(state, "GET_MIXER_INPUT_COLLECTIVE")
            unloadApi(mspTask, "GET_MIXER_INPUT_COLLECTIVE", collectiveApi)
            fail(reason or "Failed to read collective mixer input.")
        end)

        if collectiveApi.read() ~= true then
            clearActiveApi(state, "GET_MIXER_INPUT_COLLECTIVE")
            unloadApi(mspTask, "GET_MIXER_INPUT_COLLECTIVE", collectiveApi)
            fail("Failed to read collective mixer input.")
            return false
        end

        return true
    end

    local function beginRollRead()
        rollApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("GET_MIXER_INPUT_ROLL") or nil
        if not rollApi then
            fail("GET_MIXER_INPUT_ROLL unavailable.")
            return false
        end

        trackActiveApi(state, "GET_MIXER_INPUT_ROLL", rollApi)
        if rollApi.setUUID then
            rollApi.setUUID(utils.uuid("mixer-swash-roll"))
        end
        rollApi.setCompleteHandler(function()
            local parsed = copyTable(readParsed(rollApi))

            clearActiveApi(state, "GET_MIXER_INPUT_ROLL")
            unloadApi(mspTask, "GET_MIXER_INPUT_ROLL", rollApi)
            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                return
            end

            state.rollRaw = parsed
            state.ailDirection = rateToDir(parsed.rate_stabilized_roll)
            beginCollectiveRead()
        end)
        rollApi.setErrorHandler(function(_, reason)
            clearActiveApi(state, "GET_MIXER_INPUT_ROLL")
            unloadApi(mspTask, "GET_MIXER_INPUT_ROLL", rollApi)
            fail(reason or "Failed to read roll mixer input.")
        end)

        if rollApi.read() ~= true then
            clearActiveApi(state, "GET_MIXER_INPUT_ROLL")
            unloadApi(mspTask, "GET_MIXER_INPUT_ROLL", rollApi)
            fail("Failed to read roll mixer input.")
            return false
        end

        return true
    end

    local function beginPitchRead()
        pitchApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("GET_MIXER_INPUT_PITCH") or nil
        if not pitchApi then
            fail("GET_MIXER_INPUT_PITCH unavailable.")
            return false
        end

        trackActiveApi(state, "GET_MIXER_INPUT_PITCH", pitchApi)
        if pitchApi.setUUID then
            pitchApi.setUUID(utils.uuid("mixer-swash-pitch"))
        end
        pitchApi.setCompleteHandler(function()
            local parsed = copyTable(readParsed(pitchApi))

            clearActiveApi(state, "GET_MIXER_INPUT_PITCH")
            unloadApi(mspTask, "GET_MIXER_INPUT_PITCH", pitchApi)
            if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
                return
            end

            state.pitchRaw = parsed
            state.eleDirection = rateToDir(parsed.rate_stabilized_pitch)
            beginRollRead()
        end)
        pitchApi.setErrorHandler(function(_, reason)
            clearActiveApi(state, "GET_MIXER_INPUT_PITCH")
            unloadApi(mspTask, "GET_MIXER_INPUT_PITCH", pitchApi)
            fail(reason or "Failed to read pitch mixer input.")
        end)

        if pitchApi.read() ~= true then
            clearActiveApi(state, "GET_MIXER_INPUT_PITCH")
            unloadApi(mspTask, "GET_MIXER_INPUT_PITCH", pitchApi)
            fail("Failed to read pitch mixer input.")
            return false
        end

        return true
    end

    mixerApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("MIXER_CONFIG") or nil
    if not mixerApi then
        fail("MIXER_CONFIG unavailable.")
        return false
    end

    trackActiveApi(state, "MIXER_CONFIG", mixerApi)
    if mixerApi.setUUID then
        mixerApi.setUUID(utils.uuid("mixer-swash-config"))
    end
    mixerApi.setCompleteHandler(function()
        local parsed = copyTable(readParsed(mixerApi))

        clearActiveApi(state, "MIXER_CONFIG")
        unloadApi(mspTask, "MIXER_CONFIG", mixerApi)
        if generation ~= state.loadGeneration or nodeIsOpen(node) ~= true then
            return
        end

        state.mixerConfigRaw = parsed
        state.swashType = tonumber(parsed.swash_type or 0) or 0
        state.rotorDirection = tonumber(parsed.main_rotor_dir or 0) or 0
        beginPitchRead()
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
    local pitchValues = copyTable(state.pitchRaw)
    local rollValues = copyTable(state.rollRaw)
    local collectiveValues = copyTable(state.collectiveRaw)
    local needsReboot = tonumber(state.swashType or 0) ~= tonumber(state.originalSwashType or 0)

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
        state.originalSwashType = state.swashType
        state.mixerConfigRaw = mixerValues
        state.pitchRaw = pitchValues
        state.rollRaw = rollValues
        state.collectiveRaw = collectiveValues
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function afterEeprom()
        if needsReboot then
            runReboot(node, finishSuccess, fail)
        else
            finishSuccess()
        end
    end

    local function writeCollective()
        return writeApiValues(node, "GET_MIXER_INPUT_COLLECTIVE", collectiveValues, "mixer-swash-write-collective", function()
            trackActiveApi(state, "EEPROM_WRITE", eepromApi)
            if eepromApi.clearValues then
                eepromApi.clearValues()
            end
            if eepromApi.setUUID then
                eepromApi.setUUID(utils.uuid("mixer-swash-eeprom"))
            end
            eepromApi.setCompleteHandler(function()
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                afterEeprom()
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
    end

    local function writeRoll()
        return writeApiValues(node, "GET_MIXER_INPUT_ROLL", rollValues, "mixer-swash-write-roll", writeCollective, fail)
    end

    local function writePitch()
        return writeApiValues(node, "GET_MIXER_INPUT_PITCH", pitchValues, "mixer-swash-write-pitch", writeRoll, fail)
    end

    if state.loading == true or state.saving == true or state.loaded ~= true or node.app.pageDirty ~= true then
        return false
    end
    if not eepromApi then
        fail("EEPROM write unavailable.")
        return false
    end

    mixerValues.swash_type = tonumber(state.swashType or 0) or 0
    mixerValues.main_rotor_dir = tonumber(state.rotorDirection or 0) or 0
    pitchValues.rate_stabilized_pitch = applyDirectionToRate(pitchValues.rate_stabilized_pitch, state.eleDirection)
    rollValues.rate_stabilized_roll = applyDirectionToRate(rollValues.rate_stabilized_roll, state.ailDirection)
    collectiveValues.rate_stabilized_collective = applyDirectionToRate(collectiveValues.rate_stabilized_collective, state.collectiveDirection)

    state.saving = true
    state.saveError = nil
    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "Swash",
        message = "Saving swash settings.",
        closeWhenIdle = false,
        watchdogTimeout = 12.0,
        transferInfo = true,
        modal = true
    })

    return writeApiValues(node, "MIXER_CONFIG", mixerValues, "mixer-swash-write-config", writePitch, fail)
end

function Page:open(ctx)
    local node = {
        title = ctx.item.title or "Swash",
        subtitle = ctx.item.subtitle or "Swash type and directions",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        state = {
            loading = false,
            loaded = false,
            saving = false,
            loadError = nil,
            saveError = nil,
            swashType = 0,
            rotorDirection = 0,
            ailDirection = 1,
            eleDirection = 1,
            collectiveDirection = 1,
            originalSwashType = 0,
            mixerConfigRaw = {},
            pitchRaw = {},
            rollRaw = {},
            collectiveRaw = {},
            activeApis = {}
        }
    }

    local function markDirty()
        node.app:setPageDirty(true)
    end

    function node:buildForm(app)
        local control

        self.app = app

        if self.state.loading == true then
            form.addLine("Loading mixer settings.")
            return
        end

        if self.state.loadError then
            form.addLine("Error: " .. tostring(self.state.loadError))
            return
        end

        if self.state.saveError then
            form.addLine("Save error: " .. tostring(self.state.saveError))
        end

        control = form.addChoiceField(form.addLine("Swash Type"), nil, SWASH_TYPE_CHOICES,
            function()
                return self.state.swashType
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.swashType then
                    self.state.swashType = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.swashType)

        control = form.addChoiceField(form.addLine("Rotor Direction"), nil, ROTOR_DIRECTION_CHOICES,
            function()
                return self.state.rotorDirection
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.rotorDirection then
                    self.state.rotorDirection = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.rotorDirection)

        control = form.addChoiceField(form.addLine("Aileron Direction"), nil, DIRECTION_CHOICES,
            function()
                return self.state.ailDirection
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.ailDirection then
                    self.state.ailDirection = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.ailDirection)

        control = form.addChoiceField(form.addLine("Elevator Direction"), nil, DIRECTION_CHOICES,
            function()
                return self.state.eleDirection
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.eleDirection then
                    self.state.eleDirection = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.eleDirection)

        control = form.addChoiceField(form.addLine("Collective Direction"), nil, DIRECTION_CHOICES,
            function()
                return self.state.collectiveDirection
            end,
            function(newValue)
                newValue = tonumber(newValue) or 0
                if newValue ~= self.state.collectiveDirection then
                    self.state.collectiveDirection = newValue
                    markDirty()
                end
            end)
        applyControlValue(control, self.state.collectiveDirection)
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
