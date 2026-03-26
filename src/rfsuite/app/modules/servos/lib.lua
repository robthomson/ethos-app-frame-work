--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local helpData = assert(loadfile("app/modules/servos/help.lua"))()
local utils = require("lib.utils")

local servos = {}

local BUS_OUTPUT_COUNT = 18
local BUS_DISPLAY_COUNT = 16
local BUS_READ_BASE_INDEX = 8
local OVERRIDE_ON = 0
local OVERRIDE_OFF = 2001
local PWM_LIVE_SETTLE_LEGACY = 0.85
local PWM_LIVE_SETTLE_MODERN = 0.05
local BUS_LIVE_SETTLE = 0.05
local API_TIMEOUT = 6.0

local PWM_FIELDS = {
    {key = "mid", label = "@i18n(app.modules.servos.center)@", min = 50, max = 2250, default = 1500, helpKey = "servoMid"},
    {key = "min", label = "@i18n(app.modules.servos.minimum)@", min = -1000, max = 1000, default = -700, helpKey = "servoMin"},
    {key = "max", label = "@i18n(app.modules.servos.maximum)@", min = -1000, max = 1000, default = 700, helpKey = "servoMax"},
    {key = "scaleNeg", label = "@i18n(app.modules.servos.scale_negative)@", min = 100, max = 1000, default = 500, helpKey = "servoScaleNeg"},
    {key = "scalePos", label = "@i18n(app.modules.servos.scale_positive)@", min = 100, max = 1000, default = 500, helpKey = "servoScalePos"},
    {key = "rate", label = "@i18n(app.modules.servos.rate)@", min = 50, max = 5000, default = 333, suffix = "@i18n(app.unit_hertz)@", helpKey = "servoRate"},
    {key = "speed", label = "@i18n(app.modules.servos.speed)@", min = 0, max = 60000, default = 0, suffix = "ms", helpKey = "servoSpeed"},
    {key = "reverse", label = "@i18n(app.modules.servos.reverse)@", type = "choice"},
    {key = "geometry", label = "@i18n(app.modules.servos.geometry)@", type = "choice"}
}

local BUS_FIELDS = {
    {key = "mid", label = "@i18n(app.modules.servos.center)@", min = 1000, max = 2000, default = 1500, helpKey = "servoMid"},
    {key = "min", label = "@i18n(app.modules.servos.minimum)@", min = -500, max = -1, default = -500, helpKey = "servoMin"},
    {key = "max", label = "@i18n(app.modules.servos.maximum)@", min = 1, max = 500, default = 500, helpKey = "servoMax"},
    {key = "scaleNeg", label = "@i18n(app.modules.servos.scale_negative)@", min = 100, max = 1000, default = 500, helpKey = "servoScaleNeg"},
    {key = "scalePos", label = "@i18n(app.modules.servos.scale_positive)@", min = 100, max = 1000, default = 500, helpKey = "servoScalePos"},
    {key = "speed", label = "@i18n(app.modules.servos.speed)@", min = 0, max = 60000, default = 0, suffix = "ms", helpKey = "servoSpeed"},
    {key = "reverse", label = "@i18n(app.modules.servos.reverse)@", type = "choice"},
    {key = "geometry", label = "@i18n(app.modules.servos.geometry)@", type = "choice", busOnlySwash = true}
}

local YES_NO_CHOICES = {
    {"@i18n(app.modules.servos.tbl_no)@", 0},
    {"@i18n(app.modules.servos.tbl_yes)@", 1}
}

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function session(app)
    local framework = app and app.framework or nil
    return framework and framework.session or nil
end

local function showLoader(app, options)
    if app and app.isLoaderActive and app:isLoaderActive() == true and app.updateLoader then
        app:updateLoader(options)
        return true
    end
    if app and app.ui and app.ui.showLoader then
        app.ui.showLoader(options)
        return true
    end
    return false
end

local function clearLoader(app)
    if app and app.requestLoaderClose then
        app:requestLoaderClose()
    elseif app and app.ui and app.ui.clearProgressDialog then
        app.ui.clearProgressDialog(true)
    end
end

local function syncSaveButton(node)
    if node and node.app and node.app._syncSaveButtonState then
        node.app:_syncSaveButtonState()
    end
end

local function copyTable(source)
    local target = {}
    local key

    for key, value in pairs(source or {}) do
        target[key] = value
    end

    return target
end

local function readParsed(api)
    local data = api and api.data and api.data() or nil
    return data and data.parsed or nil
end

local function queueCommand(node, cmd, payload, options)
    local mspTask = node and node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    if not mspTask or not mspTask.queueCommand then
        return false, "msp unavailable"
    end
    return mspTask:queueCommand(cmd, payload or {}, options or {})
end

local function unloadApi(app, apiName, api)
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    if api and api.setCompleteHandler then
        api.setCompleteHandler(function() end)
    end
    if api and api.setErrorHandler then
        api.setErrorHandler(function() end)
    end
    if api and api.setUUID then
        api.setUUID(nil)
    end
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end
    if mspTask and mspTask.api and mspTask.api.unload and apiName then
        mspTask.api.unload(apiName)
    end
end

local function cleanupActiveApis(state, app)
    local apiName
    local api

    if type(state) ~= "table" or type(state.activeApis) ~= "table" then
        return
    end

    for apiName, api in pairs(state.activeApis) do
        unloadApi(app, apiName, api)
        state.activeApis[apiName] = nil
    end
end

local function trackApi(state, apiName, api)
    if type(state.activeApis) == "table" and type(apiName) == "string" and api ~= nil then
        state.activeApis[apiName] = api
    end
end

local function clearTrackedApi(state, apiName)
    local api = state and state.activeApis and state.activeApis[apiName] or nil
    if state and state.activeApis then
        state.activeApis[apiName] = nil
    end
    return api
end

local function flagsToBits(flags)
    local value = tonumber(flags) or 0
    local reverse = (value == 1 or value == 3) and 1 or 0
    local geometry = (value == 2 or value == 3) and 1 or 0

    return reverse, geometry
end

local function bitsToFlags(reverse, geometry)
    reverse = tonumber(reverse) or 0
    geometry = tonumber(geometry) or 0

    if reverse == 1 and geometry == 1 then
        return 3
    end
    if reverse == 1 then
        return 1
    end
    if geometry == 1 then
        return 2
    end
    return 0
end

local function apiModern()
    return utils.apiVersionCompare(">=", {12, 0, 9})
end

local function pwmServoCount(totalServoCount)
    local count = tonumber(totalServoCount) or 0
    if apiModern() and count > BUS_OUTPUT_COUNT then
        count = count - BUS_OUTPUT_COUNT
    end
    if count < 0 then
        count = 0
    end
    return count
end

local function decodeServoConfig(buf, name)
    local helper = require("mspapi.helper")
    local config = {}

    config.name = name
    config.mid = helper.readU16(buf) or 0
    config.min = helper.readS16(buf) or 0
    config.max = helper.readS16(buf) or 0
    config.scaleNeg = helper.readU16(buf) or 0
    config.scalePos = helper.readU16(buf) or 0
    config.rate = helper.readU16(buf) or 0
    config.speed = helper.readU16(buf) or 0
    config.flags = helper.readU16(buf) or 0
    config.reverse, config.geometry = flagsToBits(config.flags)

    return config
end

local function buildServoEntries(kind, totalServoCount, swashType, tailMode)
    local entries = {}
    local index
    local count

    if kind == "bus" then
        count = BUS_DISPLAY_COUNT
    else
        count = pwmServoCount(totalServoCount)
    end

    for index = 1, count do
        entries[index] = {
            title = "@i18n(app.modules.servos.servo_prefix)@" .. index,
            image = "servo" .. index .. ".png"
        }
    end

    if swashType == 2 or swashType == 3 or swashType == 4 then
        if entries[1] then
            entries[1].title = "@i18n(app.modules.servos.cyc_pitch)@"
            entries[1].image = "cpitch.png"
        end
        if entries[2] then
            entries[2].title = "@i18n(app.modules.servos.cyc_left)@"
            entries[2].image = "cleft.png"
        end
        if entries[3] then
            entries[3].title = "@i18n(app.modules.servos.cyc_right)@"
            entries[3].image = "cright.png"
        end
    end

    if tailMode == 0 and (swashType == 1 or swashType == 2 or swashType == 3 or swashType == 4 or swashType == 5 or swashType == 6) then
        if entries[4] then
            entries[4].title = "@i18n(app.modules.servos.tail)@"
            entries[4].image = "tail.png"
        end
    end

    return entries
end

local function defaultConfig(mode)
    return {
        mid = mode == "bus" and 1500 or 1500,
        min = mode == "bus" and -500 or -700,
        max = mode == "bus" and 500 or 700,
        scaleNeg = 500,
        scalePos = 500,
        rate = mode == "bus" and 0 or 333,
        speed = 0,
        flags = 0,
        reverse = 0,
        geometry = 0
    }
end

local function setSessionValue(app, key, value)
    local s = session(app)
    if s and s.set then
        s:set(key, value)
    end
end

local function getSessionValue(app, key, defaultValue)
    local s = session(app)
    if s and s.get then
        return s:get(key, defaultValue)
    end
    return defaultValue
end

local function detectOverride(parsed)
    local index
    local key

    for index = 1, 8 do
        key = "servo_" .. index
        if tonumber(parsed and parsed[key] or -1) == OVERRIDE_ON then
            return true
        end
    end

    return false
end

local function listLayout(app)
    local prefs = app and app.framework and app.framework.preferences and app.framework.preferences:section("general", {}) or {}
    local iconSize = tonumber(prefs.iconsize)
    local width = app and app._windowSize and app:_windowSize() or select(1, lcd.getWindowSize())
    local radio = app and app.radio or {}
    local padding
    local buttonW
    local buttonH
    local perRow

    if iconSize == nil then
        iconSize = 1
    end

    if iconSize == 0 then
        padding = radio.buttonPaddingSmall or 6
        perRow = radio.buttonsPerRow or 3
        buttonW = math.floor((width - padding) / perRow) - padding
        buttonH = radio.navbuttonHeight or 30
    elseif iconSize == 2 then
        padding = radio.buttonPadding or 8
        buttonW = radio.buttonWidth or 110
        buttonH = radio.buttonHeight or 82
        perRow = radio.buttonsPerRow or 3
    else
        padding = radio.buttonPaddingSmall or 6
        buttonW = radio.buttonWidthSmall or 92
        buttonH = radio.buttonHeightSmall or 68
        perRow = radio.buttonsPerRowSmall or 4
    end

    return padding, buttonW, buttonH, perRow, iconSize
end

local function loadMask(state, filename)
    local path = "app/modules/servos/gfx/" .. tostring(filename or "")

    state.icons = state.icons or {}
    if state.icons[path] == nil then
        state.icons[path] = lcd.loadMask(path)
    end

    return state.icons[path]
end

local function openHelp(title, key)
    return diagnostics.openHelpDialog(title, helpData.help[key] or helpData.help.default)
end

local function startServoContextLoad(node, showLoader)
    local state = node.state
    local app = node.app
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    local function fail(reason)
        cleanupActiveApis(state, app)
        state.loading = false
        state.loaded = false
        state.error = tostring(reason or "load_failed")
        if nodeIsOpen(node) then
            clearLoader(app)
            app:_invalidateForm()
        end
    end

    local function loadOverrideState()
        local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("SERVO_OVERRIDE") or nil

        if not api then
            state.overrideEnabled = getSessionValue(app, "servoOverrideEnabled", false) == true
            state.entries = buildServoEntries(state.mode, state.totalServoCount, state.swashType, state.tailMode)
            state.loading = false
            state.loaded = true
            state.error = nil
            clearLoader(app)
            app:_invalidateForm()
            return true
        end

        trackApi(state, "SERVO_OVERRIDE", api)
        if api.setTimeout then
            api.setTimeout(API_TIMEOUT)
        end
        if api.setUUID then
            api.setUUID(utils.uuid("servos-override-read-" .. state.mode))
        end
        api.setCompleteHandler(function()
            local parsed

            clearTrackedApi(state, "SERVO_OVERRIDE")
            parsed = readParsed(api) or {}
            unloadApi(app, "SERVO_OVERRIDE", api)

            state.overrideEnabled = detectOverride(parsed)
            state.entries = buildServoEntries(state.mode, state.totalServoCount, state.swashType, state.tailMode)
            setSessionValue(app, "servoOverrideEnabled", state.overrideEnabled)
            state.loading = false
            state.loaded = true
            state.error = nil

            if nodeIsOpen(node) then
                clearLoader(app)
                app:_invalidateForm()
            end
        end)
        api.setErrorHandler(function(_, reason)
            clearTrackedApi(state, "SERVO_OVERRIDE")
            unloadApi(app, "SERVO_OVERRIDE", api)
            fail(reason or "SERVO_OVERRIDE read failed.")
        end)

        if api.read() ~= true then
            clearTrackedApi(state, "SERVO_OVERRIDE")
            unloadApi(app, "SERVO_OVERRIDE", api)
            fail("SERVO_OVERRIDE read failed.")
            return false
        end

        return true
    end

    local function loadMixer()
        local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("MIXER_CONFIG") or nil

        if not api then
            fail("MIXER_CONFIG unavailable.")
            return false
        end

        trackApi(state, "MIXER_CONFIG", api)
        if api.setTimeout then
            api.setTimeout(API_TIMEOUT)
        end
        if api.setUUID then
            api.setUUID(utils.uuid("servos-mixer-read-" .. state.mode))
        end
        api.setCompleteHandler(function()
            local parsed = readParsed(api) or {}

            clearTrackedApi(state, "MIXER_CONFIG")
            unloadApi(app, "MIXER_CONFIG", api)
            state.swashType = tonumber(parsed.swash_type) or 0
            state.tailMode = tonumber(parsed.tail_rotor_mode) or 0
            setSessionValue(app, "servoSwashType", state.swashType)
            setSessionValue(app, "servoTailMode", state.tailMode)
            loadOverrideState()
        end)
        api.setErrorHandler(function(_, reason)
            clearTrackedApi(state, "MIXER_CONFIG")
            unloadApi(app, "MIXER_CONFIG", api)
            fail(reason or "MIXER_CONFIG read failed.")
        end)

        if api.read() ~= true then
            clearTrackedApi(state, "MIXER_CONFIG")
            unloadApi(app, "MIXER_CONFIG", api)
            fail("MIXER_CONFIG read failed.")
            return false
        end

        return true
    end

    cleanupActiveApis(state, app)
    state.loading = true
    state.loaded = false
    state.error = nil
    state.entries = {}

    if showLoader ~= false then
        showLoader(app, {
            kind = "progress",
            title = node.baseTitle or node.title or "@i18n(app.modules.servos.name)@",
            message = "@i18n(app.modules.servos.loading_list)@",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("STATUS") or nil
    if not api then
        fail("STATUS unavailable.")
        return false
    end

    trackApi(state, "STATUS", api)
    if api.setTimeout then
        api.setTimeout(API_TIMEOUT)
    end
    if api.setUUID then
        api.setUUID(utils.uuid("servos-status-read-" .. state.mode))
    end
    api.setCompleteHandler(function()
        local parsed = readParsed(api) or {}

        clearTrackedApi(state, "STATUS")
        unloadApi(app, "STATUS", api)
        state.totalServoCount = tonumber(parsed.servo_count) or 0
        setSessionValue(app, "servoTotalCount", state.totalServoCount)
        loadMixer()
    end)
    api.setErrorHandler(function(_, reason)
        clearTrackedApi(state, "STATUS")
        unloadApi(app, "STATUS", api)
        fail(reason or "STATUS read failed.")
    end)

    if api.read() ~= true then
        clearTrackedApi(state, "STATUS")
        unloadApi(app, "STATUS", api)
        fail("STATUS read failed.")
        return false
    end

    return true
end

local function uiIndexToBusReadIndex(uiIndex)
    return (tonumber(uiIndex) or 0) + BUS_READ_BASE_INDEX
end

local function uiIndexToBusConfigWriteIndex(uiIndex, totalServoCount)
    return (tonumber(uiIndex) or 0) + ((tonumber(totalServoCount) or BUS_OUTPUT_COUNT) - BUS_OUTPUT_COUNT)
end

local function queueOverrideAll(node, enabled)
    local state = node.state
    local app = node.app
    local totalCount = tonumber(state.totalServoCount) or 0
    local payloadValue = enabled == true and OVERRIDE_ON or OVERRIDE_OFF
    local index
    local ok
    local payload
    local helper = require("mspapi.helper")

    if apiModern() then
        payload = {}
        helper.writeU16(payload, payloadValue)
        ok = queueCommand(node, 196, payload, {
            timeout = 1.5,
            simulatorResponse = {},
            onError = function() end
        })
        ok = ok == true
    else
        ok = true
        for index = 0, math.max(0, totalCount - 1) do
            payload = {index}
            helper.writeU16(payload, payloadValue)
            if queueCommand(node, 193, payload, {
                timeout = 1.5,
                simulatorResponse = {},
                onError = function() end
            }) ~= true then
                ok = false
                break
            end
        end
    end

    if ok == true then
        state.overrideEnabled = enabled == true
        setSessionValue(app, "servoOverrideEnabled", state.overrideEnabled)
        syncSaveButton(node)
    end

    return ok
end

local function queueOverrideDisableOnClose(node)
    if node and node.state and node.state.overrideEnabled == true then
        queueOverrideAll(node, false)
    end
end

local function queueCenterWrite(node)
    local state = node.state
    local helper = require("mspapi.helper")
    local payload = {}
    local writeIndex

    if state.mode == "bus" then
        writeIndex = uiIndexToBusReadIndex(state.servoUiIndex)
    else
        writeIndex = state.servoUiIndex
    end

    helper.writeU8(payload, writeIndex)
    helper.writeU16(payload, tonumber(state.config.mid) or 0)

    return queueCommand(node, 213, payload, {
        timeout = 1.5,
        simulatorResponse = {},
        onError = function() end
    }) == true
end

local function setDetailControlState(node)
    local state = node.state
    local key
    local control
    local enabled

    for key, control in pairs(state.controls or {}) do
        enabled = state.loaded == true and state.saving ~= true
        if key ~= "mid" and state.overrideEnabled == true then
            enabled = false
        end
        if control and control.enable then
            pcall(control.enable, control, enabled)
        end
    end

    syncSaveButton(node)
end

local function liveSettleSeconds(state)
    if state.mode == "bus" then
        return BUS_LIVE_SETTLE
    end
    if apiModern() then
        return PWM_LIVE_SETTLE_MODERN
    end
    return PWM_LIVE_SETTLE_LEGACY
end

local function startDetailLoad(node, showLoader)
    local state = node.state
    local app = node.app
    local helper = require("mspapi.helper")

    local function fail(reason)
        state.loading = false
        state.loaded = false
        state.error = tostring(reason or "load_failed")
        if nodeIsOpen(node) then
            clearLoader(app)
            setDetailControlState(node)
            app:_invalidateForm()
        end
    end

    local function finish()
        state.loading = false
        state.loaded = true
        state.error = nil
        state.lastLiveSentMid = tonumber(state.config.mid) or 0
        state.lastChangeAt = os.clock()
        setSessionValue(app, "servoOverrideEnabled", state.overrideEnabled)

        if nodeIsOpen(node) then
            clearLoader(app)
            setDetailControlState(node)
            app:setPageDirty(false)
            app:_invalidateForm()
        end
    end

    local function loadOverrideState()
        local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil
        local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("SERVO_OVERRIDE") or nil

        if not api then
            state.overrideEnabled = getSessionValue(app, "servoOverrideEnabled", false) == true
            finish()
            return true
        end

        trackApi(state, "SERVO_OVERRIDE", api)
        if api.setTimeout then
            api.setTimeout(API_TIMEOUT)
        end
        if api.setUUID then
            api.setUUID(utils.uuid("servo-detail-override-" .. state.mode))
        end
        api.setCompleteHandler(function()
            local parsed = readParsed(api) or {}

            clearTrackedApi(state, "SERVO_OVERRIDE")
            unloadApi(app, "SERVO_OVERRIDE", api)
            state.overrideEnabled = detectOverride(parsed)
            finish()
        end)
        api.setErrorHandler(function()
            clearTrackedApi(state, "SERVO_OVERRIDE")
            unloadApi(app, "SERVO_OVERRIDE", api)
            state.overrideEnabled = getSessionValue(app, "servoOverrideEnabled", false) == true
            finish()
        end)

        if api.read() ~= true then
            clearTrackedApi(state, "SERVO_OVERRIDE")
            unloadApi(app, "SERVO_OVERRIDE", api)
            state.overrideEnabled = getSessionValue(app, "servoOverrideEnabled", false) == true
            finish()
            return true
        end

        return true
    end

    cleanupActiveApis(state, app)
    state.loading = true
    state.loaded = false
    state.error = nil
    state.config = defaultConfig(state.mode)

    if showLoader ~= false then
        showLoader(app, {
            kind = "progress",
            title = node.baseTitle or node.title or "@i18n(app.modules.servos.name)@",
            message = state.mode == "bus" and "@i18n(app.modules.servos.loading_bus)@" or "@i18n(app.modules.servos.loading_pwm)@",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if state.mode == "pwm" then
        if queueCommand(node, 120, {}, {
            timeout = 3.0,
            simulatorResponse = {4, 180, 5, 12, 254, 244, 1, 244, 1, 244, 1, 144, 0, 0, 0, 1, 0, 160, 5, 12, 254, 244, 1, 244, 1, 244, 1, 144, 0, 0, 0, 1, 0, 14, 6, 12, 254, 244, 1, 244, 1, 244, 1, 144, 0, 0, 0, 0, 0, 120, 5, 212, 254, 44, 1, 244, 1, 244, 1, 77, 1, 0, 0, 0, 0},
            onReply = function(_, buffer)
                local buf = copyTable(buffer or {})
                local count
                local index
                local selected

                buf.offset = 1
                count = helper.readU8(buf) or 0
                if count <= state.servoUiIndex then
                    fail("Servo index out of range.")
                    return
                end

                for index = 0, count - 1 do
                    local config = decodeServoConfig(buf, state.servoName)
                    if index == state.servoUiIndex then
                        selected = config
                    end
                end

                if not selected then
                    fail("Servo configuration missing.")
                    return
                end

                state.totalServoCount = count
                state.config = selected
                loadOverrideState()
            end,
            onError = function(_, reason)
                fail(reason or "Servo configuration read failed.")
            end
        }) ~= true then
            fail("Servo configuration read failed.")
            return false
        end
    else
        if queueCommand(node, 125, {uiIndexToBusReadIndex(state.servoUiIndex)}, {
            timeout = 3.0,
            simulatorResponse = {220, 5, 232, 3, 208, 7, 232, 3, 232, 3, 100, 0, 0, 0, 0, 0},
            onReply = function(_, buffer)
                local buf = copyTable(buffer or {})
                buf.offset = 1
                state.config = decodeServoConfig(buf, state.servoName)
                loadOverrideState()
            end,
            onError = function(_, reason)
                fail(reason or "BUS servo configuration read failed.")
            end
        }) ~= true then
            fail("BUS servo configuration read failed.")
            return false
        end
    end

    return true
end

local function queueEepromWrite(node, done, failed)
    return queueCommand(node, 250, {}, {
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
    }) == true
end

local function startDetailSave(node)
    local state = node.state
    local helper = require("mspapi.helper")
    local payload = {}
    local writeIndex

    local function fail(reason)
        state.saving = false
        if nodeIsOpen(node) then
            clearLoader(node.app)
            setDetailControlState(node)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.servos.name)@", tostring(reason or "Save failed."))
        end
    end

    if state.loaded ~= true or state.loading == true or state.saving == true or state.overrideEnabled == true then
        return false
    end

    state.saving = true
    setDetailControlState(node)
    showLoader(node.app, {
        kind = "save",
        title = node.baseTitle or node.title or "@i18n(app.modules.servos.name)@",
        message = state.mode == "bus" and "@i18n(app.modules.servos.saving_bus)@" or "@i18n(app.modules.servos.saving_pwm)@",
        closeWhenIdle = false,
        watchdogTimeout = 12.0,
        transferInfo = true,
        modal = true
    })

    if state.mode == "bus" then
        writeIndex = uiIndexToBusConfigWriteIndex(state.servoUiIndex, state.totalServoCount)
    else
        writeIndex = state.servoUiIndex
    end

    helper.writeU8(payload, writeIndex)
    helper.writeU16(payload, tonumber(state.config.mid) or 0)
    helper.writeS16(payload, tonumber(state.config.min) or 0)
    helper.writeS16(payload, tonumber(state.config.max) or 0)
    helper.writeU16(payload, tonumber(state.config.scaleNeg) or 0)
    helper.writeU16(payload, tonumber(state.config.scalePos) or 0)
    helper.writeU16(payload, tonumber(state.config.rate) or 0)
    helper.writeU16(payload, tonumber(state.config.speed) or 0)
    helper.writeU16(payload, bitsToFlags(state.config.reverse, state.config.geometry))

    if queueCommand(node, 212, payload, {
        timeout = 3.0,
        simulatorResponse = {},
        onReply = function()
            if queueEepromWrite(node, function()
                state.saving = false
                state.lastLiveSentMid = tonumber(state.config.mid) or 0
                if nodeIsOpen(node) then
                    clearLoader(node.app)
                    node.app:setPageDirty(false)
                    setDetailControlState(node)
                end
            end, fail) ~= true then
                fail("EEPROM write failed.")
            end
        end,
        onError = function(_, reason)
            fail(reason or "Servo configuration write failed.")
        end
    }) ~= true then
        fail("Servo configuration write failed.")
        return false
    end

    return true
end

function servos.createListPage(mode)
    local Page = {}

    function Page:open(ctx)
        local state = {
            mode = mode,
            entries = {},
            icons = {},
            activeApis = {},
            totalServoCount = tonumber(getSessionValue(ctx.app, "servoTotalCount", 0)) or 0,
            swashType = tonumber(getSessionValue(ctx.app, "servoSwashType", 0)) or 0,
            tailMode = tonumber(getSessionValue(ctx.app, "servoTailMode", 0)) or 0,
            overrideEnabled = getSessionValue(ctx.app, "servoOverrideEnabled", false) == true,
            loading = false,
            loaded = false,
            error = nil,
            closed = false
        }
        local node = {
            baseTitle = ctx.item.title or (mode == "bus" and "@i18n(app.modules.servos.bus)@" or "@i18n(app.modules.servos.pwm)@"),
            title = ctx.item.title or (mode == "bus" and "@i18n(app.modules.servos.bus)@" or "@i18n(app.modules.servos.pwm)@"),
            subtitle = ctx.item.subtitle or "@i18n(app.modules.servos.name)@",
            breadcrumb = ctx.breadcrumb,
            navButtons = {menu = true, save = false, reload = false, tool = {enabled = true, text = "*"}, help = true},
            showLoaderOnEnter = true,
            loaderOnEnter = {
                kind = "progress",
                message = "@i18n(app.modules.servos.loading_list)@",
                closeWhenIdle = false,
                watchdogTimeout = 10.0,
                transferInfo = true,
                focusMenuOnClose = true,
                modal = true
            },
            state = state
        }

        function node:buildForm(app)
            local padding
            local buttonW
            local buttonH
            local perRow
            local iconSize
            local index
            local entry
            local row = 0
            local col = 0
            local y = 0
            local x = 0
            local currentItem
            local currentIndex
            local baseY

            self.app = app

            if state.error then
                local line = form.addLine("Status")
                form.addStaticText(line, nil, tostring(state.error))
                return
            end

            if state.loaded ~= true then
                return
            end

            if #state.entries == 0 then
                local line = form.addLine("")
                form.addStaticText(line, {x = 8, y = app.radio.linePaddingTop or 0, w = math.max(40, app:_windowSize() - 16), h = app.radio.navbuttonHeight or 30}, "@i18n(app.modules.servos.no_servos)@")
                return
            end

            padding, buttonW, buttonH, perRow, iconSize = listLayout(app)
            baseY = form.height() + padding

            for index = 1, #state.entries do
                entry = state.entries[index]
                col = (index - 1) % perRow
                row = math.floor((index - 1) / perRow)
                x = col * (buttonW + padding)
                y = baseY + row * (buttonH + padding)

                currentItem = {
                    id = string.format("servo-%s-%d", state.mode, index),
                    kind = "page",
                    path = string.format("servos/tools/%s_tool.lua", state.mode),
                    title = entry.title,
                    subtitle = self.baseTitle,
                    image = "app/modules/servos/gfx/" .. entry.image,
                    servoIndex = index - 1,
                    servoName = entry.title,
                    totalServoCount = state.totalServoCount
                }
                currentIndex = index

                form.addButton(nil, {x = x, y = y, w = buttonW, h = buttonH}, {
                    text = entry.title,
                    icon = iconSize ~= 0 and loadMask(state, entry.image) or nil,
                    options = FONT_S,
                    paint = function() end,
                    press = function()
                        app:_enterItem(currentIndex, currentItem)
                    end
                })
            end
        end

        function node:wakeup()
            if state.loaded ~= true and state.loading ~= true then
                startServoContextLoad(self, false)
            end
        end

        function node:tool()
            local title
            local message

            if state.overrideEnabled == true then
                title = "@i18n(app.modules.servos.disable_servo_override)@"
                message = "@i18n(app.modules.servos.disable_servo_override_msg)@"
            else
                title = "@i18n(app.modules.servos.enable_servo_override)@"
                message = "@i18n(app.modules.servos.enable_servo_override_msg)@"
            end

            return diagnostics.openConfirmDialog(title, message, function()
                showLoader(self.app, {
                    kind = "progress",
                    title = "@i18n(app.modules.servos.servo_override)@",
                    message = state.overrideEnabled == true and "@i18n(app.modules.servos.disabling_servo_override)@" or "@i18n(app.modules.servos.enabling_servo_override)@",
                    closeWhenIdle = false,
                    watchdogTimeout = 4.0,
                    transferInfo = true,
                    modal = true
                })
                if queueOverrideAll(self, state.overrideEnabled ~= true) ~= true then
                    clearLoader(self.app)
                    diagnostics.openMessageDialog(self.title or self.baseTitle, "Failed to toggle servo override.")
                    return
                end
                clearLoader(self.app)
            end)
        end

        function node:help()
            return openHelp(self.title or self.baseTitle, "default")
        end

        function node:menu()
            if state.overrideEnabled == true then
                queueOverrideDisableOnClose(self)
            end
            return self.app and self.app._goBack and self.app:_goBack() or false
        end

        function node:close()
            state.closed = true
            cleanupActiveApis(state, self.app)
        end

        return node
    end

    return Page
end

function servos.createDetailPage(mode)
    local Page = {}

    function Page:open(ctx)
        local state = {
            mode = mode,
            servoUiIndex = tonumber(ctx.item.servoIndex) or 0,
            servoName = ctx.item.servoName or ctx.item.title or ("@i18n(app.modules.servos.servo_prefix)@" .. tostring((tonumber(ctx.item.servoIndex) or 0) + 1)),
            totalServoCount = tonumber(ctx.item.totalServoCount) or tonumber(getSessionValue(ctx.app, "servoTotalCount", 0)) or 0,
            config = defaultConfig(mode),
            controls = {},
            activeApis = {},
            loading = false,
            loaded = false,
            saving = false,
            error = nil,
            overrideEnabled = getSessionValue(ctx.app, "servoOverrideEnabled", false) == true,
            lastLiveSentMid = nil,
            lastChangeAt = 0,
            closed = false
        }
        local node = {
            baseTitle = (mode == "bus" and "@i18n(app.modules.servos.bus)@" or "@i18n(app.modules.servos.pwm)@") .. " / " .. tostring(state.servoName),
            title = ctx.item.title or tostring(state.servoName),
            subtitle = ctx.item.subtitle or "@i18n(app.modules.servos.name)@",
            breadcrumb = ctx.breadcrumb,
            navButtons = {menu = true, save = true, reload = true, tool = {enabled = true, text = "*"}, help = true},
            showLoaderOnEnter = true,
            loaderOnEnter = {
                kind = "progress",
                message = mode == "bus" and "@i18n(app.modules.servos.loading_bus)@" or "@i18n(app.modules.servos.loading_pwm)@",
                closeWhenIdle = false,
                watchdogTimeout = 10.0,
                transferInfo = true,
                focusMenuOnClose = true,
                modal = true
            },
            state = state
        }

        function node:buildForm(app)
            local fields = state.mode == "bus" and BUS_FIELDS or PWM_FIELDS
            local index
            local spec
            local line
            local control
            local helpField
            local includeGeometry

            self.app = app
            state.controls = {}

            if state.error then
                line = form.addLine("Status")
                form.addStaticText(line, nil, tostring(state.error))
                return
            end

            for index = 1, #fields do
                spec = fields[index]
                includeGeometry = (spec.key ~= "geometry") or state.mode ~= "bus" or state.servoUiIndex <= 7
                if includeGeometry then
                    local currentSpec = spec
                    line = form.addLine(spec.label)
                    helpField = currentSpec.helpKey and helpData.fields[currentSpec.helpKey] or nil

                    if currentSpec.type == "choice" then
                        control = form.addChoiceField(line, nil, YES_NO_CHOICES,
                            function()
                                if state.loaded ~= true then
                                    return nil
                                end
                                return tonumber(state.config[currentSpec.key] or 0) or 0
                            end,
                            function(value)
                                if tonumber(value) ~= tonumber(state.config[currentSpec.key]) then
                                    state.config[currentSpec.key] = tonumber(value) or 0
                                    state.config.flags = bitsToFlags(state.config.reverse, state.config.geometry)
                                    app:setPageDirty(true)
                                end
                            end)
                    else
                        control = form.addNumberField(line, nil, currentSpec.min, currentSpec.max,
                            function()
                                if state.loaded ~= true then
                                    return nil
                                end
                                return tonumber(state.config[currentSpec.key] or 0) or 0
                            end,
                            function(value)
                                if tonumber(value) ~= tonumber(state.config[currentSpec.key]) then
                                    state.config[currentSpec.key] = tonumber(value) or 0
                                    state.lastChangeAt = os.clock()
                                    app:setPageDirty(true)
                                end
                            end)

                        if currentSpec.default ~= nil and control.default then
                            control:default(currentSpec.default)
                        end
                        if currentSpec.suffix and control.suffix then
                            control:suffix(currentSpec.suffix)
                        end
                        if control.enableInstantChange then
                            control:enableInstantChange(true)
                        end
                    end

                    if helpField and control and control.help then
                        control:help(helpField.t)
                    end

                    state.controls[currentSpec.key] = control
                end
            end

            setDetailControlState(self)
        end

        function node:canSave()
            return state.loaded == true and state.loading ~= true and state.saving ~= true and state.overrideEnabled ~= true and state.error == nil
        end

        function node:wakeup()
            local mspTask = self.app and self.app.framework and self.app.framework.getTask and self.app.framework:getTask("msp") or nil
            local queue = mspTask and mspTask.mspQueue or nil
            local currentMid
            local settle

            if state.loaded ~= true and state.loading ~= true then
                startDetailLoad(self, false)
                return
            end

            if state.overrideEnabled == true and state.loaded == true and state.saving ~= true and queue and queue.isProcessed and queue:isProcessed() == true then
                currentMid = tonumber(state.config.mid) or 0
                settle = liveSettleSeconds(state)
                if currentMid ~= tonumber(state.lastLiveSentMid) and (os.clock() - (state.lastChangeAt or 0)) >= settle then
                    if queueCenterWrite(self) == true then
                        state.lastLiveSentMid = currentMid
                        state.lastChangeAt = os.clock()
                    end
                end
            end
        end

        function node:reload()
            if state.overrideEnabled == true then
                queueOverrideAll(self, false)
            end
            return startDetailLoad(self, true)
        end

        function node:save()
            return startDetailSave(self)
        end

        function node:tool()
            local title
            local message

            if state.overrideEnabled == true then
                title = "@i18n(app.modules.servos.disable_servo_override)@"
                message = "@i18n(app.modules.servos.disable_servo_override_msg)@"
            else
                title = "@i18n(app.modules.servos.enable_servo_override)@"
                message = "@i18n(app.modules.servos.enable_servo_override_msg)@"
            end

            return diagnostics.openConfirmDialog(title, message, function()
                showLoader(self.app, {
                    kind = "progress",
                    title = "@i18n(app.modules.servos.servo_override)@",
                    message = state.overrideEnabled == true and "@i18n(app.modules.servos.disabling_servo_override)@" or "@i18n(app.modules.servos.enabling_servo_override)@",
                    closeWhenIdle = false,
                    watchdogTimeout = 4.0,
                    transferInfo = true,
                    modal = true
                })
                if queueOverrideAll(self, state.overrideEnabled ~= true) ~= true then
                    clearLoader(self.app)
                    diagnostics.openMessageDialog(self.title or self.baseTitle, "Failed to toggle servo override.")
                    return
                end
                clearLoader(self.app)
                setDetailControlState(self)
            end)
        end

        function node:help()
            return openHelp(self.baseTitle or self.title, "servos_tool")
        end

        function node:menu()
            if state.overrideEnabled == true then
                queueOverrideDisableOnClose(self)
            end
            return self.app and self.app._goBack and self.app:_goBack() or false
        end

        function node:close()
            state.closed = true
            cleanupActiveApis(state, self.app)
        end

        return node
    end

    return Page
end

return servos
