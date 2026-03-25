--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local LIVE_UPDATE_INTERVAL = 0.85
local MIXER_OVERRIDE_OFF = 2501
local MIXER_OVERRIDE_ON = 0
local TAIL_CENTER_TRIM_MULT = 0.239923224568138

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

local function cleanupActiveApi(state, app)
    local api = state and state.activeApi or nil
    local apiName = state and state.activeApiName or nil
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    if state then
        state.activeApi = nil
        state.activeApiName = nil
    end

    if not api then
        return
    end

    if api.setCompleteHandler then
        api.setCompleteHandler(function() end)
    end
    if api.setErrorHandler then
        api.setErrorHandler(function() end)
    end
    if api.setUUID then
        api.setUUID(nil)
    end

    unloadApi(mspTask, apiName, api)
end

local function readParsed(api)
    local data = api and api.data and api.data() or nil
    return data and data.parsed or nil
end

local function round(value)
    value = tonumber(value) or 0
    if value >= 0 then
        return math.floor(value + 0.5)
    end
    return math.ceil(value - 0.5)
end

local function applyControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function isMotorizedMode(mode)
    return (tonumber(mode) or -1) >= 1
end

local function tailTrimControlFromRaw(rawValue)
    return round((tonumber(rawValue) or 0) * TAIL_CENTER_TRIM_MULT)
end

local function tailTrimEngineeringFromControl(controlValue)
    return (tonumber(controlValue) or 0) / (10 * TAIL_CENTER_TRIM_MULT)
end

local function digestValues(state)
    return table.concat({
        tostring(state.rollTrim or ""),
        tostring(state.pitchTrim or ""),
        tostring(state.collectiveTrim or ""),
        tostring(state.tailValue or ""),
        tostring(state.tailMode or "")
    }, "|")
end

local function queueOverrideCommand(node, payloadValue)
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

local function applyParsedValues(state)
    local parsed = state.mixerConfigRaw or {}

    state.tailMode = tonumber(parsed.tail_rotor_mode) or 0
    state.rollTrim = tonumber(parsed.swash_trim_0) or 0
    state.pitchTrim = tonumber(parsed.swash_trim_1) or 0
    state.collectiveTrim = tonumber(parsed.swash_trim_2) or 0

    if isMotorizedMode(state.tailMode) then
        state.tailFieldKey = "tailMotorIdle"
        state.tailFieldLabel = "@i18n(app.modules.trim.tail_motor_idle)@"
        state.tailValue = tonumber(parsed.tail_motor_idle) or 0
    else
        state.tailFieldKey = "yawTrim"
        state.tailFieldLabel = "@i18n(app.modules.trim.yaw_trim)@"
        state.tailValue = tailTrimControlFromRaw(parsed.tail_center_trim)
    end
end

local function refreshControls(state)
    local controls = state.controls or {}

    applyControlValue(controls.rollTrim, state.rollTrim or 0)
    applyControlValue(controls.pitchTrim, state.pitchTrim or 0)
    applyControlValue(controls.collectiveTrim, state.collectiveTrim or 0)
    applyControlValue(controls.tailValue, state.tailValue or 0)
end

local function setControlsEnabled(state, enabled)
    local control

    if type(state) ~= "table" or type(state.controls) ~= "table" then
        return
    end

    for _, control in pairs(state.controls) do
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

    if nodeIsOpen(node) then
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("MIXER_CONFIG") or nil

    if not api then
        failLoad(node, "MIXER_CONFIG unavailable.")
        return false
    end

    cleanupActiveApi(state, node.app)
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.activeApiName = "MIXER_CONFIG"
    state.activeApi = api
    setControlsEnabled(state, false)

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.mixer.trims)@",
            message = "Loading trims.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if api.setUUID then
        api.setUUID(utils.uuid("mixer-trims-read"))
    end
    api.setCompleteHandler(function()
        local parsed = readParsed(api) or {}

        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        state.mixerConfigRaw = parsed
        applyParsedValues(state)
        state.lastAppliedDigest = digestValues(state)
        state.lastChangeAt = os.clock()
        state.loading = false
        state.loaded = true

        if nodeIsOpen(node) then
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
            refreshControls(state)
            setControlsEnabled(state, true)
            node.app:setPageDirty(false)
        end
    end)
    api.setErrorHandler(function(_, reason)
        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        failLoad(node, reason or "MIXER_CONFIG read failed.")
    end)

    if api.read() ~= true then
        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        failLoad(node, "MIXER_CONFIG read failed.")
        return false
    end

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

local function buildPayload(state)
    local values = {
        main_rotor_dir = state.mixerConfigRaw.main_rotor_dir,
        tail_rotor_mode = state.mixerConfigRaw.tail_rotor_mode,
        tail_motor_idle = state.mixerConfigRaw.tail_motor_idle,
        tail_center_trim = state.mixerConfigRaw.tail_center_trim,
        swash_type = state.mixerConfigRaw.swash_type,
        swash_ring = state.mixerConfigRaw.swash_ring,
        swash_phase = state.mixerConfigRaw.swash_phase,
        swash_pitch_limit = state.mixerConfigRaw.swash_pitch_limit,
        swash_trim_0 = (tonumber(state.rollTrim) or 0) / 10,
        swash_trim_1 = (tonumber(state.pitchTrim) or 0) / 10,
        swash_trim_2 = (tonumber(state.collectiveTrim) or 0) / 10,
        swash_tta_precomp = state.mixerConfigRaw.swash_tta_precomp,
        swash_geo_correction = state.mixerConfigRaw.swash_geo_correction,
        collective_tilt_correction_pos = state.mixerConfigRaw.collective_tilt_correction_pos,
        collective_tilt_correction_neg = state.mixerConfigRaw.collective_tilt_correction_neg
    }

    if isMotorizedMode(state.tailMode) then
        values.tail_motor_idle = (tonumber(state.tailValue) or 0) / 10
    else
        values.tail_center_trim = tailTrimEngineeringFromControl(state.tailValue)
    end

    return values
end

local function startSave(node, commitToEeprom)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("MIXER_CONFIG") or nil
    local payload

    local function fail(reason)
        state.saving = false
        if nodeIsOpen(node) then
            if commitToEeprom == true then
                node.app.ui.clearProgressDialog(true)
            end
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.trims)@", tostring(reason or "Save failed."))
        end
    end

    if not api then
        fail("MIXER_CONFIG unavailable.")
        return false
    end

    if state.loaded ~= true or state.loading == true or state.saving == true then
        return false
    end

    state.saving = true
    state.activeApiName = "MIXER_CONFIG"
    state.activeApi = api
    payload = buildPayload(state)

    if commitToEeprom == true then
        node.app.ui.showLoader({
            kind = "save",
            title = node.title or "@i18n(app.modules.mixer.trims)@",
            message = "@i18n(app.msg_saving_to_fbl)@",
            closeWhenIdle = false,
            watchdogTimeout = 12.0,
            transferInfo = true,
            modal = true
        })
    end

    if api.clearValues then
        api.clearValues()
    end
    if api.resetWriteStatus then
        api.resetWriteStatus()
    end
    if api.setRebuildOnWrite then
        api.setRebuildOnWrite(true)
    end
    for key, value in pairs(payload) do
        api.setValue(key, value)
    end
    if api.setUUID then
        api.setUUID(utils.uuid("mixer-trims-write"))
    end
    api.setCompleteHandler(function()
        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        state.mixerConfigRaw = payload
        state.lastAppliedDigest = digestValues(state)
        state.saving = false

        if not nodeIsOpen(node) then
            return
        end

        if commitToEeprom == true then
            if queueEepromWrite(node, function()
                if nodeIsOpen(node) then
                    node.app.ui.clearProgressDialog(true)
                    node.app:setPageDirty(false)
                end
            end, function(reason)
                if nodeIsOpen(node) then
                    node.app.ui.clearProgressDialog(true)
                    diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.trims)@", tostring(reason or "EEPROM write failed."))
                end
            end) ~= true then
                node.app.ui.clearProgressDialog(true)
                diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.trims)@", "EEPROM write failed.")
            end
        else
            state.lastChangeAt = os.clock()
        end
    end)
    api.setErrorHandler(function(_, reason)
        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        fail(reason or "MIXER_CONFIG write failed.")
    end)

    if api.write() ~= true then
        state.activeApi = nil
        state.activeApiName = nil
        unloadApi(mspTask, "MIXER_CONFIG", api)
        fail("MIXER_CONFIG write failed.")
        return false
    end

    return true
end

local function setOverrideEnabled(node, enabled)
    local state = node.state
    local ok = queueOverrideCommand(node, enabled and MIXER_OVERRIDE_ON or MIXER_OVERRIDE_OFF)

    if ok ~= true then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.mixer.trims)@", enabled and "Failed to enable mixer override." or "Failed to disable mixer override.")
        return false
    end

    state.overrideEnabled = enabled == true
    state.lastChangeAt = os.clock()
    if enabled == true then
        state.lastAppliedDigest = digestValues(state)
    end
    return true
end

function Page:open(ctx)
    local state = {
        controls = {},
        mixerConfigRaw = {},
        tailMode = 0,
        tailFieldKey = "yawTrim",
        tailFieldLabel = "@i18n(app.modules.trim.yaw_trim)@",
        rollTrim = 0,
        pitchTrim = 0,
        collectiveTrim = 0,
        tailValue = 0,
        activeApiName = nil,
        activeApi = nil,
        loaded = false,
        loading = false,
        saving = false,
        loadError = nil,
        overrideEnabled = false,
        lastAppliedDigest = nil,
        lastChangeAt = 0,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.mixer.trims)@",
        subtitle = ctx.item.subtitle or "Mixer trims",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = {enabled = true, text = "*"}, help = false},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "Loading trims.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:buildForm(app)
        local control

        self.app = app
        state.controls = {}

        if state.loadError then
            local line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.loadError))
        end

        control = form.addNumberField(form.addLine("@i18n(app.modules.trim.roll_trim)@"), nil, -1000, 1000,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.rollTrim
            end,
            function(value)
                if value ~= state.rollTrim then
                    state.rollTrim = value
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(1)
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.rollTrim or 0)
        end
        state.controls.rollTrim = control

        control = form.addNumberField(form.addLine("@i18n(app.modules.trim.pitch_trim)@"), nil, -1000, 1000,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.pitchTrim
            end,
            function(value)
                if value ~= state.pitchTrim then
                    state.pitchTrim = value
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(1)
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.pitchTrim or 0)
        end
        state.controls.pitchTrim = control

        control = form.addNumberField(form.addLine("@i18n(app.modules.trim.collective_trim)@"), nil, -1000, 1000,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.collectiveTrim
            end,
            function(value)
                if value ~= state.collectiveTrim then
                    state.collectiveTrim = value
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(1)
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.collectiveTrim or 0)
        end
        state.controls.collectiveTrim = control

        control = form.addNumberField(form.addLine(state.tailFieldLabel), nil, isMotorizedMode(state.tailMode) and 0 or -2500, isMotorizedMode(state.tailMode) and 250 or 2500,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.tailValue
            end,
            function(value)
                if value ~= state.tailValue then
                    state.tailValue = value
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(1)
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.tailValue or 0)
        end
        state.controls.tailValue = control
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
            digest = digestValues(state)
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
            title = "@i18n(app.modules.trim.disable_mixer_override)@"
            message = "@i18n(app.modules.trim.disable_mixer_message)@"
        else
            title = "@i18n(app.modules.trim.enable_mixer_override)@"
            message = "@i18n(app.modules.trim.enable_mixer_message)@"
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
        cleanupActiveApi(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
