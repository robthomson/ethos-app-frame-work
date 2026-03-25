--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local lib = {}

lib.CONFIG_FIELDS = {
    {bit = 0, label = "@i18n(app.modules.beepers.field_gyro_calibrated)@"},
    {bit = 1, label = "@i18n(app.modules.beepers.field_rx_lost)@"},
    {bit = 2, label = "@i18n(app.modules.beepers.field_rx_lost_landing)@"},
    {bit = 3, label = "@i18n(app.modules.beepers.field_disarming)@"},
    {bit = 4, label = "@i18n(app.modules.beepers.field_arming)@"},
    {bit = 5, label = "@i18n(app.modules.beepers.field_arming_gps_fix)@"},
    {bit = 6, label = "@i18n(app.modules.beepers.field_bat_crit_low)@"},
    {bit = 7, label = "@i18n(app.modules.beepers.field_bat_low)@"},
    {bit = 8, label = "@i18n(app.modules.beepers.field_gps_status)@"},
    {bit = 9, label = "@i18n(app.modules.beepers.field_rx_set)@"},
    {bit = 10, label = "@i18n(app.modules.beepers.field_acc_calibration)@"},
    {bit = 11, label = "@i18n(app.modules.beepers.field_acc_calibration_fail)@"},
    {bit = 12, label = "@i18n(app.modules.beepers.field_ready_beep)@"},
    {bit = 14, label = "@i18n(app.modules.beepers.field_disarm_repeat)@"},
    {bit = 15, label = "@i18n(app.modules.beepers.field_armed)@"},
    {bit = 16, label = "@i18n(app.modules.beepers.field_system_init)@"},
    {bit = 17, label = "@i18n(app.modules.beepers.field_usb)@"},
    {bit = 18, label = "@i18n(app.modules.beepers.field_blackbox_erase)@"},
    {bit = 21, label = "@i18n(app.modules.beepers.field_arming_gps_no_fix)@"}
}

lib.DSHOT_FIELDS = {
    {bit = 1, label = "@i18n(app.modules.beepers.field_rx_lost)@"},
    {bit = 9, label = "@i18n(app.modules.beepers.field_rx_set)@"}
}

lib.DSHOT_TONES = {
    {"1", 1},
    {"2", 2},
    {"3", 3},
    {"4", 4},
    {"5", 5}
}

lib.HELP = {
    "@i18n(app.modules.beepers.help_p1)@",
    "@i18n(app.modules.beepers.help_p2)@"
}

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
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

local function bitFlag(bit)
    return 2 ^ (tonumber(bit or 0) or 0)
end

function lib.bitIsSet(mask, bit)
    local value = tonumber(mask or 0) or 0
    local flag = bitFlag(bit)

    return math.floor(value / flag) % 2 == 1
end

function lib.setBit(mask, bit, enabled)
    local value = tonumber(mask or 0) or 0
    local flag = bitFlag(bit)
    local alreadySet = math.floor(value / flag) % 2 == 1

    if enabled == true then
        if alreadySet ~= true then
            value = value + flag
        end
    elseif alreadySet == true then
        value = value - flag
    end

    return value
end

function lib.snapshotSession(state, app)
    local session = app and app.framework and app.framework.session or nil

    if type(session) ~= "table" then
        return
    end

    session.beepers = {
        config = copyTable(state.cfg),
        ready = true
    }
end

function lib.loadSessionSnapshot(state, app)
    local session = app and app.framework and app.framework.session or nil
    local snapshot = session and session.beepers or nil
    local config = snapshot and snapshot.config or nil

    if type(config) ~= "table" then
        return false
    end

    state.cfg.beeper_off_flags = tonumber(config.beeper_off_flags or 0) or 0
    state.cfg.dshotBeaconTone = tonumber(config.dshotBeaconTone or 1) or 1
    state.cfg.dshotBeaconOffFlags = tonumber(config.dshotBeaconOffFlags or 0) or 0
    return true
end

function lib.cleanupActiveApi(state, app)
    local api = state and state.activeApi or nil
    local apiName = state and state.activeApiName or nil
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    if type(state) ~= "table" then
        return
    end

    state.activeApi = nil
    state.activeApiName = nil

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
    if api.releaseTransientState then
        api.releaseTransientState()
    elseif api.clearReadData then
        api.clearReadData()
    end
    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(apiName)
    end
end

function lib.load(node, options)
    local opts = options or {}
    local state = node.state
    local app = node.app
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil
    local api

    lib.cleanupActiveApi(state, app)

    state.loading = true
    state.loaded = false
    state.error = nil

    if opts.showLoader ~= false then
        showLoader(app, {
            kind = "progress",
            title = node.baseTitle or node.title or "@i18n(app.modules.beepers.name)@",
            message = opts.message or "@i18n(app.modules.beepers.loading)@",
            closeWhenIdle = false,
            watchdogTimeout = opts.watchdogTimeout or 8.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("BEEPER_CONFIG") or nil
    if not api then
        state.loading = false
        state.error = "BEEPER_CONFIG unavailable"
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
        return false
    end

    state.activeApi = api
    state.activeApiName = "BEEPER_CONFIG"

    api.setUUID(utils.uuid(opts.uuid or "beepers-load"))
    api.setCompleteHandler(function()
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}

        lib.cleanupActiveApi(state, app)
        if not nodeIsOpen(node) then
            return
        end

        state.cfg.beeper_off_flags = tonumber(parsed.beeper_off_flags or 0) or 0
        state.cfg.dshotBeaconTone = tonumber(parsed.dshotBeaconTone or 1) or 1
        state.cfg.dshotBeaconOffFlags = tonumber(parsed.dshotBeaconOffFlags or 0) or 0
        if state.cfg.dshotBeaconTone < 1 or state.cfg.dshotBeaconTone > 5 then
            state.cfg.dshotBeaconTone = 1
        end

        state.loading = false
        state.loaded = true
        state.error = nil
        lib.snapshotSession(state, app)
        app.ui.clearProgressDialog(true)
        app:setPageDirty(false)
        app:_invalidateForm()
    end)
    api.setErrorHandler(function(_, err)
        lib.cleanupActiveApi(state, app)
        if not nodeIsOpen(node) then
            return
        end

        state.loading = false
        state.loaded = false
        state.error = tostring(err or "read_failed")
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
    end)

    if api.read() ~= true then
        lib.cleanupActiveApi(state, app)
        state.loading = false
        state.loaded = false
        state.error = "read_failed"
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
        return false
    end

    return true
end

function lib.save(node, options)
    local opts = options or {}
    local state = node.state
    local app = node.app
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil
    local api

    if state.loaded ~= true or state.saving == true then
        return false
    end

    lib.cleanupActiveApi(state, app)

    state.saving = true
    state.error = nil

    showLoader(app, {
        kind = "save",
        title = node.baseTitle or node.title or "@i18n(app.modules.beepers.name)@",
        message = opts.message or "@i18n(app.modules.beepers.saving)@",
        closeWhenIdle = false,
        watchdogTimeout = opts.watchdogTimeout or 10.0,
        transferInfo = true,
        modal = true
    })

    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("BEEPER_CONFIG") or nil
    if not api then
        state.saving = false
        state.error = "BEEPER_CONFIG unavailable"
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
        return false
    end

    state.activeApi = api
    state.activeApiName = "BEEPER_CONFIG"

    api.setUUID(utils.uuid(opts.uuid or "beepers-save"))
    api.setErrorHandler(function(_, err)
        lib.cleanupActiveApi(state, app)
        if not nodeIsOpen(node) then
            return
        end

        state.saving = false
        state.error = tostring(err or "write_failed")
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
    end)
    api.setCompleteHandler(function()
        local ok
        local reason

        lib.cleanupActiveApi(state, app)
        if not nodeIsOpen(node) then
            return
        end

        ok, reason = mspTask:queueCommand(250, {}, {
            timeout = 4.0,
            simulatorResponse = {},
            onReply = function()
                if not nodeIsOpen(node) then
                    return
                end

                state.saving = false
                state.error = nil
                lib.snapshotSession(state, app)
                app.ui.clearProgressDialog(true)
                app:setPageDirty(false)
                app:_invalidateForm()
            end,
            onError = function(_, err)
                if not nodeIsOpen(node) then
                    return
                end

                state.saving = false
                state.error = tostring(err or "eeprom_failed")
                app.ui.clearProgressDialog(true)
                app:_invalidateForm()
            end
        })

        if ok ~= true then
            state.saving = false
            state.error = tostring(reason or "eeprom_queue_failed")
            app.ui.clearProgressDialog(true)
            app:_invalidateForm()
        end
    end)

    api.setValue("beeper_off_flags", state.cfg.beeper_off_flags)
    api.setValue("dshotBeaconTone", state.cfg.dshotBeaconTone)
    api.setValue("dshotBeaconOffFlags", state.cfg.dshotBeaconOffFlags)

    if api.write() ~= true then
        lib.cleanupActiveApi(state, app)
        state.saving = false
        state.error = "write_failed"
        app.ui.clearProgressDialog(true)
        app:_invalidateForm()
        return false
    end

    return true
end

function lib.openHelp(title)
    return diagnostics.openHelpDialog((title or "@i18n(app.modules.beepers.name)@") .. " Help", lib.HELP)
end

return lib
