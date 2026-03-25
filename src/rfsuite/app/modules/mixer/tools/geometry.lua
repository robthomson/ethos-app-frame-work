--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local LIVE_UPDATE_INTERVAL = 0.25
local MIXER_OVERRIDE_OFF = 2501
local MIXER_OVERRIDE_ON = 0
local MIXER_OVERRIDE_PASSTHROUGH = 2502

local LAYOUT = {
    {
        key = "cyclicCalibration",
        label = "@i18n(app.modules.mixer.cyclic_calibration)@",
        min = 200,
        max = 2000,
        decimals = 1,
        step = 1,
        unit = "%"
    },
    {
        key = "collectiveCalibration",
        label = "@i18n(app.modules.mixer.collective_calibration)@",
        min = 200,
        max = 2000,
        decimals = 1,
        step = 1,
        unit = "%"
    },
    {
        key = "geoCorrection",
        label = "@i18n(app.modules.mixer.geo_correction)@",
        min = -250,
        max = 250,
        decimals = 1,
        step = 2,
        unit = "%"
    },
    {
        key = "cyclicPitchLimit",
        label = "@i18n(app.modules.mixer.cyclic_pitch_limit)@",
        min = 0,
        max = 200,
        decimals = 1,
        step = 1,
        unit = "°"
    },
    {
        key = "collectivePitchLimit",
        label = "@i18n(app.modules.mixer.collective_pitch_limit)@",
        min = 0,
        max = 200,
        decimals = 1,
        step = 1,
        unit = "°"
    },
    {
        key = "swashPitchLimit",
        label = "@i18n(app.modules.mixer.swash_pitch_limit)@",
        min = 0,
        max = 360,
        decimals = 1,
        step = 1,
        unit = "°"
    },
    {
        key = "swashPhase",
        label = "@i18n(app.modules.mixer.swash_phase)@",
        min = -1800,
        max = 1800,
        decimals = 1,
        step = 1,
        unit = "°"
    },
    {
        key = "collectiveTiltCorrectionPos",
        label = "@i18n(app.modules.mixer.collective_tilt_correction_pos)@",
        min = -100,
        max = 100
    },
    {
        key = "collectiveTiltCorrectionNeg",
        label = "@i18n(app.modules.mixer.collective_tilt_correction_neg)@",
        min = -100,
        max = 100
    }
}

local LOAD_APIS = {
    "MIXER_CONFIG",
    "GET_MIXER_INPUT_PITCH",
    "GET_MIXER_INPUT_ROLL",
    "GET_MIXER_INPUT_COLLECTIVE"
}

local SAVE_APIS = LOAD_APIS

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
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

local function digestFormData(state)
    local parts = {}
    local index
    local spec

    for index = 1, #LAYOUT do
        spec = LAYOUT[index]
        parts[#parts + 1] = tostring(state.formData[spec.key] or "")
    end

    return table.concat(parts, "|")
end

local function snapshotFormData(state)
    local out = {}
    local index
    local spec

    for index = 1, #LAYOUT do
        spec = LAYOUT[index]
        out[spec.key] = state.formData[spec.key]
    end

    return out
end

local function mixerOverrideOnValue()
    if utils and utils.apiVersionCompare and utils.apiVersionCompare(">=", {12, 0, 8}) then
        return MIXER_OVERRIDE_PASSTHROUGH
    end
    return MIXER_OVERRIDE_ON
end

local function queueOverrideCommand(node, payloadValue, uuidPrefix)
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local helper = mspTask and mspTask.mspHelper or nil
    local index
    local payload
    local queued

    if not mspTask or not mspTask.queueCommand or not helper or not helper.writeU16 then
        return false
    end

    for index = 1, 4 do
        payload = {index}
        helper.writeU16(payload, payloadValue)
        queued = mspTask:queueCommand(191, payload, {
            timeout = 1.0,
            simulatorResponse = {},
            onError = function() end
        })
        if queued ~= true then
            return false
        end
    end

    return true
end

local function applyApiDataToForm(node)
    local state = node.state
    local mixerValues = state.apiData.MIXER_CONFIG or {}
    local pitchValues = state.apiData.GET_MIXER_INPUT_PITCH or {}
    local rollValues = state.apiData.GET_MIXER_INPUT_ROLL or {}
    local collectiveValues = state.apiData.GET_MIXER_INPUT_COLLECTIVE or {}

    state.directions.aileron = rateToDir(rollValues.rate_stabilized_roll)
    state.directions.elevator = rateToDir(pitchValues.rate_stabilized_pitch)
    state.directions.collective = rateToDir(collectiveValues.rate_stabilized_collective)

    state.formData.cyclicCalibration = math.abs(u16ToS16(pitchValues.rate_stabilized_pitch or 0))
    state.formData.collectiveCalibration = math.abs(u16ToS16(collectiveValues.rate_stabilized_collective or 0))
    state.formData.geoCorrection = (tonumber(mixerValues.swash_geo_correction) or 0) * 2
    state.formData.cyclicPitchLimit = round(math.abs(u16ToS16(pitchValues.max_stabilized_pitch or 0)) * 12 / 100)
    state.formData.collectivePitchLimit = round(math.abs(u16ToS16(collectiveValues.max_stabilized_collective or 0)) * 12 / 100)
    state.formData.swashPitchLimit = round((tonumber(mixerValues.swash_pitch_limit) or 0) * 12 / 100)
    state.formData.swashPhase = tonumber(mixerValues.swash_phase) or 0
    state.formData.collectiveTiltCorrectionPos = tonumber(mixerValues.collective_tilt_correction_pos) or 0
    state.formData.collectiveTiltCorrectionNeg = tonumber(mixerValues.collective_tilt_correction_neg) or 0
end

local function copyFormToApi(state)
    local mixerValues = copyTable(state.apiData.MIXER_CONFIG or {})
    local pitchValues = copyTable(state.apiData.GET_MIXER_INPUT_PITCH or {})
    local rollValues = copyTable(state.apiData.GET_MIXER_INPUT_ROLL or {})
    local collectiveValues = copyTable(state.apiData.GET_MIXER_INPUT_COLLECTIVE or {})
    local cyclicRate = round(state.formData.cyclicCalibration or 0)
    local collectiveRate = round(state.formData.collectiveCalibration or 0)
    local cyclicLimit = round((state.formData.cyclicPitchLimit or 0) * 100 / 12)
    local collectiveLimit = round((state.formData.collectivePitchLimit or 0) * 100 / 12)
    local aileronSign = (tonumber(state.directions.aileron) == 0) and -1 or 1
    local elevatorSign = (tonumber(state.directions.elevator) == 0) and -1 or 1
    local collectiveSign = (tonumber(state.directions.collective) == 0) and -1 or 1

    mixerValues.swash_geo_correction = round((state.formData.geoCorrection or 0) / 2)
    mixerValues.swash_pitch_limit = round((state.formData.swashPitchLimit or 0) * 100 / 12)
    mixerValues.swash_phase = tonumber(state.formData.swashPhase) or 0
    mixerValues.collective_tilt_correction_pos = tonumber(state.formData.collectiveTiltCorrectionPos) or 0
    mixerValues.collective_tilt_correction_neg = tonumber(state.formData.collectiveTiltCorrectionNeg) or 0

    pitchValues.rate_stabilized_pitch = s16ToU16(cyclicRate * elevatorSign)
    pitchValues.max_stabilized_pitch = s16ToU16(math.abs(cyclicLimit))
    pitchValues.min_stabilized_pitch = s16ToU16(-math.abs(cyclicLimit))

    rollValues.rate_stabilized_roll = s16ToU16(cyclicRate * aileronSign)
    rollValues.max_stabilized_roll = s16ToU16(math.abs(cyclicLimit))
    rollValues.min_stabilized_roll = s16ToU16(-math.abs(cyclicLimit))

    collectiveValues.rate_stabilized_collective = s16ToU16(collectiveRate * collectiveSign)
    collectiveValues.max_stabilized_collective = s16ToU16(math.abs(collectiveLimit))
    collectiveValues.min_stabilized_collective = s16ToU16(-math.abs(collectiveLimit))

    return {
        MIXER_CONFIG = mixerValues,
        GET_MIXER_INPUT_PITCH = pitchValues,
        GET_MIXER_INPUT_ROLL = rollValues,
        GET_MIXER_INPUT_COLLECTIVE = collectiveValues
    }
end

local function refreshControls(node)
    local state = node.state
    local index
    local spec
    local control

    for index = 1, #LAYOUT do
        spec = LAYOUT[index]
        control = state.controls[spec.key]
        if control and control.value then
            pcall(control.value, control, state.formData[spec.key] or 0)
        end
    end
end

local function setControlsEnabled(node, enabled)
    local state = node and node.state or nil
    local index
    local spec
    local control

    if type(state) ~= "table" then
        return
    end

    for index = 1, #LAYOUT do
        spec = LAYOUT[index]
        control = state.controls[spec.key]
        if control and control.enable then
            pcall(control.enable, control, enabled == true)
        end
    end
end

local function failLoad(node, reason)
    local state = node.state

    state.loading = false
    state.loaded = false
    state.loadError = tostring(reason or "load_failed")

    if not nodeIsOpen(node) then
        return
    end

    setControlsEnabled(node, false)
    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local generation = (state.loadGeneration or 0) + 1

    local function loadAt(index)
        local apiName = LOAD_APIS[index]
        local api

        if not apiName then
            state.loading = false
            state.loaded = true
            state.loadError = nil
            applyApiDataToForm(node)
            state.lastAppliedDigest = digestFormData(state)
            state.lastAppliedSnapshot = snapshotFormData(state)
            state.lastChangeAt = os.clock()

            if nodeIsOpen(node) then
                node.app.ui.clearProgressDialog(true)
                refreshControls(node)
                setControlsEnabled(node, true)
                if not next(state.controls) then
                    node.app:_invalidateForm()
                end
            end
            return
        end

        api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(apiName) or nil
        if not api then
            failLoad(node, apiName .. " unavailable.")
            return
        end

        trackActiveApi(state, apiName, api)
        if api.setUUID then
            api.setUUID(utils.uuid("mixer-geometry-read-" .. string.lower(apiName)))
        end
        api.setCompleteHandler(function()
            local parsed

            clearActiveApi(state, apiName)
            if generation ~= state.loadGeneration then
                unloadApi(mspTask, apiName, api)
                return
            end

            parsed = copyTable(readParsed(api))
            unloadApi(mspTask, apiName, api)
            state.apiData[apiName] = parsed
            loadAt(index + 1)
        end)
        api.setErrorHandler(function(_, reason)
            clearActiveApi(state, apiName)
            unloadApi(mspTask, apiName, api)
            failLoad(node, reason or (apiName .. " read failed."))
        end)

        if api.read() ~= true then
            clearActiveApi(state, apiName)
            unloadApi(mspTask, apiName, api)
            failLoad(node, apiName .. " read failed.")
        end
    end

    state.loadGeneration = generation
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.apiData = {}
    cleanupActiveApis(state, node.app)
    setControlsEnabled(node, false)

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.mixer.geometry)@",
            message = "Loading mixer geometry.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    loadAt(1)
    return true
end

local function queueEepromWrite(node, done, failed)
    local mspTask = node.app.framework:getTask("msp")
    local queued

    queued = mspTask and mspTask.queueCommand and mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            if type(done) == "function" then
                done()
            end
        end,
        onError = function(_, reason)
            if type(failed) == "function" then
                failed(reason or "EEPROM write failed.")
            end
        end
    })

    return queued == true
end

local function writeApiValues(node, apiName, values, uuidSuffix, done, failed)
    local state = node.state
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(apiName) or nil
    local key

    if not api then
        if type(failed) == "function" then
            failed(apiName .. " unavailable.")
        end
        return false
    end

    trackActiveApi(state, apiName, api)
    if api.clearValues then
        api.clearValues()
    end
    if api.resetWriteStatus then
        api.resetWriteStatus()
    end
    if api.setRebuildOnWrite then
        api.setRebuildOnWrite(true)
    end
    for key, value in pairs(values or {}) do
        api.setValue(key, value)
    end
    if api.setUUID then
        api.setUUID(utils.uuid(uuidSuffix))
    end
    api.setCompleteHandler(function()
        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(done) == "function" then
            done()
        end
    end)
    api.setErrorHandler(function(_, reason)
        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(reason or (apiName .. " write failed."))
        end
    end)

    if api.write() ~= true then
        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(apiName .. " write failed.")
        end
        return false
    end

    return true
end

local function finishSave(node, commitToEeprom, payloads)
    local state = node.state

    state.apiData = payloads
    state.lastAppliedDigest = digestFormData(state)
    state.lastAppliedSnapshot = snapshotFormData(state)
    state.saving = false

    if not nodeIsOpen(node) then
        return
    end

    if commitToEeprom == true then
        if queueEepromWrite(node, function()
            if not nodeIsOpen(node) then
                return
            end
            node.app.ui.clearProgressDialog(true)
            node.app:setPageDirty(false)
        end, function(reason)
            if not nodeIsOpen(node) then
                return
            end
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.geometry)@", tostring(reason or "EEPROM write failed."))
        end) ~= true then
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.geometry)@", "EEPROM write failed.")
        end
    else
        state.lastChangeAt = os.clock()
    end
end

local function startSave(node, commitToEeprom)
    local state = node.state
    local payloads

    local function fail(reason)
        state.saving = false
        if nodeIsOpen(node) then
            if commitToEeprom == true then
                node.app.ui.clearProgressDialog(true)
            end
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.geometry)@", tostring(reason or "Save failed."))
        end
    end

    local function writeAt(index)
        local apiName = SAVE_APIS[index]

        if not apiName then
            finishSave(node, commitToEeprom, payloads)
            return
        end

        if writeApiValues(node, apiName, payloads[apiName], "mixer-geometry-write-" .. string.lower(apiName), function()
            writeAt(index + 1)
        end, fail) ~= true then
            return
        end
    end

    if state.loaded ~= true or state.loading == true or state.saving == true then
        return false
    end

    payloads = copyFormToApi(state)
    state.saving = true

    if commitToEeprom == true then
        node.app.ui.showLoader({
            kind = "save",
            title = node.title or "@i18n(app.modules.mixer.geometry)@",
            message = "@i18n(app.msg_saving_to_fbl)@",
            closeWhenIdle = false,
            watchdogTimeout = 12.0,
            transferInfo = true,
            modal = true
        })
    end

    writeAt(1)
    return true
end

local function setOverrideEnabled(node, enabled)
    local state = node.state
    local ok
    local payloadValue

    payloadValue = enabled and mixerOverrideOnValue() or MIXER_OVERRIDE_OFF
    ok = queueOverrideCommand(node, payloadValue)
    if ok ~= true then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.geometry)@", enabled and "Failed to enable swash setup mode." or "Failed to disable swash setup mode.")
        return false
    end

    state.overrideEnabled = enabled == true
    state.lastChangeAt = os.clock()
    if enabled == true then
        state.lastAppliedDigest = digestFormData(state)
        state.lastAppliedSnapshot = snapshotFormData(state)
    end
    return true
end

function Page:open(ctx)
    local state = {
        controls = {},
        formData = {},
        apiData = {},
        directions = {},
        activeApis = {},
        loadGeneration = 0,
        loaded = false,
        loading = false,
        saving = false,
        loadError = nil,
        overrideEnabled = false,
        lastChangeAt = 0,
        lastAppliedDigest = nil,
        lastAppliedSnapshot = nil,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.mixer.geometry)@",
        subtitle = ctx.item.subtitle or "Swash geometry and setup",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = {enabled = true, text = "*"}, help = false},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "Loading mixer geometry.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:buildForm(app)
        local index
        local spec
        local control

        self.app = app

        if state.loadError then
            local line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.loadError))
        end

        for index = 1, #LAYOUT do
            spec = LAYOUT[index]
            local currentSpec = spec
            control = form.addNumberField(form.addLine(spec.label), nil, spec.min, spec.max,
                function()
                    if state.loaded ~= true then
                        return nil
                    end
                    return state.formData[currentSpec.key]
                end,
                function(value)
                    if value ~= state.formData[currentSpec.key] then
                        state.formData[currentSpec.key] = value
                        app:setPageDirty(true)
                    end
                end)

            if currentSpec.decimals and control.decimals then
                control:decimals(currentSpec.decimals)
            end
            if currentSpec.step and control.step then
                control:step(currentSpec.step)
            end
            if currentSpec.unit and control.suffix then
                control:suffix(currentSpec.unit)
            end
            if control.enableInstantChange then
                control:enableInstantChange(true)
            end
            if control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end

            state.controls[currentSpec.key] = control
        end
    end

    function node:wakeup()
        local mspTask = self.app and self.app.framework and self.app.framework.getTask and self.app.framework:getTask("msp") or nil
        local queue = mspTask and mspTask.mspQueue or nil
        local digest

        if state.loaded ~= true and state.loading ~= true then
            startLoad(self, false)
            return
        end

        if state.overrideEnabled == true and state.loading ~= true and state.saving ~= true and queue and queue.isProcessed and queue:isProcessed() == true then
            digest = digestFormData(state)
            if digest ~= state.lastAppliedDigest and (os.clock() - (state.lastChangeAt or 0)) >= LIVE_UPDATE_INTERVAL then
                startSave(self, false)
            end
        end
    end

    function node:reload()
        if state.saving == true then
            return false
        end

        if state.overrideEnabled == true then
            setOverrideEnabled(self, false)
        end

        return startLoad(self, true)
    end

    function node:save()
        if state.overrideEnabled == true then
            setOverrideEnabled(self, false)
        end

        return startSave(self, true)
    end

    function node:tool()
        local title
        local message

        if state.overrideEnabled == true then
            title = "@i18n(app.modules.mixer.disable_swash_override)@"
            message = "@i18n(app.modules.mixer.disable_swash_override_message)@"
        else
            title = "@i18n(app.modules.mixer.enable_swash_override)@"
            message = "@i18n(app.modules.mixer.enable_swash_override_message)@"
        end

        return diagnostics.openConfirmDialog(title, message, function()
            setOverrideEnabled(self, state.overrideEnabled ~= true)
        end)
    end

    function node:close()
        state.closed = true
        if state.overrideEnabled == true then
            setOverrideEnabled(self, false)
        end
        cleanupActiveApis(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
