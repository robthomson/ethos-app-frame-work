--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local STATS_HELP = {
    "@i18n(app.modules.stats.help_p1)@"
}

local function noopHandler()
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

    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(apiName)
    end
end

local function cleanupActiveApi(state, app)
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
        api.setCompleteHandler(noopHandler)
    end
    if api.setErrorHandler then
        api.setErrorHandler(noopHandler)
    end
    if api.setUUID then
        api.setUUID(nil)
    end

    unloadApi(mspTask, apiName, api)
end

local function finishLoad(node)
    local state = node.state

    state.loading = false
    state.loaded = true

    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function beginRemoteLoad(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api

    if utils.apiVersionCompare("<", {12, 0, 9}) then
        finishLoad(node)
        return true
    end

    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FLIGHT_STATS")
    if not api then
        finishLoad(node)
        return true
    end

    state.activeApiName = "FLIGHT_STATS"
    state.activeApi = api

    api.setUUID(utils.uuid("stats-remote-load"))
    api.setCompleteHandler(function()
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}

        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil

        if not nodeIsOpen(node) then
            return
        end

        state.remoteStats = {
            flightcount = tonumber(parsed.flightcount) or state.flightcount or 0,
            totalflighttime = tonumber(parsed.totalflighttime) or state.totalflighttime or 0,
            totaldistance = tonumber(parsed.totaldistance) or 0,
            minarmedtime = tonumber(parsed.minarmedtime) or 0
        }

        finishLoad(node)
    end)
    api.setErrorHandler(function()
        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil

        if not nodeIsOpen(node) then
            return
        end

        finishLoad(node)
    end)

    if api.read() ~= true then
        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil
        finishLoad(node)
    end

    return true
end

local function beginLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FLIGHT_STATS_INI")

    cleanupActiveApi(state, node.app)

    state.loading = true
    state.loaded = false
    state.error = nil

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.stats.name)@",
            message = "Loading values.",
            closeWhenIdle = false,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if not api then
        state.loading = false
        state.error = "FLIGHT_STATS_INI unavailable"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    state.activeApiName = "FLIGHT_STATS_INI"
    state.activeApi = api

    api.setUUID(utils.uuid("stats-local-load"))
    api.setCompleteHandler(function()
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}

        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil

        if not nodeIsOpen(node) then
            return
        end

        state.flightcount = tonumber(parsed.flightcount) or 0
        state.totalflighttime = tonumber(parsed.totalflighttime) or 0

        beginRemoteLoad(node)
    end)
    api.setErrorHandler(function(_, err)
        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil

        if not nodeIsOpen(node) then
            return
        end

        state.loading = false
        state.error = tostring(err or "read_failed")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    if api.read() ~= true then
        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil
        state.loading = false
        state.error = "read_failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function queueEepromWrite(node, onDone, onError)
    local mspTask = node.app.framework:getTask("msp")
    local ok

    ok = mspTask and mspTask.queueCommand and mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            if node.state.closed == true then
                return
            end
            if type(onDone) == "function" then
                onDone()
            end
        end,
        onError = function(_, err)
            if node.state.closed == true then
                return
            end
            if type(onError) == "function" then
                onError(err)
            end
        end
    })

    if ok ~= true and type(onError) == "function" then
        onError("eeprom_queue_failed")
    end
end

local function writeRemoteStats(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api

    if utils.apiVersionCompare("<", {12, 0, 9}) then
        queueEepromWrite(node, function()
            state.saving = false
            node.app.ui.clearProgressDialog(true)
        end, function(err)
            state.saving = false
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", tostring(err or "EEPROM write failed."))
        end)
        return true
    end

    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FLIGHT_STATS")
    if not api then
        queueEepromWrite(node, function()
            state.saving = false
            node.app.ui.clearProgressDialog(true)
        end, function(err)
            state.saving = false
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", tostring(err or "EEPROM write failed."))
        end)
        return true
    end

    state.activeApiName = "FLIGHT_STATS"
    state.activeApi = api

    api.setUUID(utils.uuid("stats-remote-save"))
    api.setCompleteHandler(function()
        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil

        if state.closed == true then
            return
        end

        queueEepromWrite(node, function()
            state.saving = false
            state.remoteStats.flightcount = state.flightcount
            state.remoteStats.totalflighttime = state.totalflighttime
            node.app.ui.clearProgressDialog(true)
        end, function(err)
            state.saving = false
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", tostring(err or "EEPROM write failed."))
        end)
    end)
    api.setErrorHandler(function(_, err)
        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil

        if state.closed == true then
            return
        end

        state.saving = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", tostring(err or "Save failed."))
    end)

    api.setValue("flightcount", state.flightcount)
    api.setValue("totalflighttime", state.totalflighttime)
    api.setValue("totaldistance", tonumber(state.remoteStats.totaldistance) or 0)
    api.setValue("minarmedtime", tonumber(state.remoteStats.minarmedtime) or 0)

    if api.write() ~= true then
        unloadApi(mspTask, "FLIGHT_STATS", api)
        state.activeApiName = nil
        state.activeApi = nil
        state.saving = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", "Save failed.")
        return false
    end

    return true
end

local function performSave(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("FLIGHT_STATS_INI")

    cleanupActiveApi(state, node.app)

    if not api then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", "FLIGHT_STATS_INI unavailable.")
        return false
    end

    state.saving = true

    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.stats.name)@",
        message = "@i18n(app.msg_saving_to_fbl)@",
        closeWhenIdle = false,
        transferInfo = true,
        modal = true
    })

    state.activeApiName = "FLIGHT_STATS_INI"
    state.activeApi = api

    api.setUUID(utils.uuid("stats-local-save"))
    if api.setRebuildOnWrite then
        api.setRebuildOnWrite(true)
    end
    api.setCompleteHandler(function()
        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil

        if state.closed == true then
            return
        end

        writeRemoteStats(node)
    end)
    api.setErrorHandler(function(_, err)
        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil

        if state.closed == true then
            return
        end

        state.saving = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", tostring(err or "Save failed."))
    end)

    api.setValue("flightcount", state.flightcount)
    api.setValue("totalflighttime", state.totalflighttime)

    if api.write() ~= true then
        unloadApi(mspTask, "FLIGHT_STATS_INI", api)
        state.activeApiName = nil
        state.activeApi = nil
        state.saving = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.stats.name)@", "Save failed.")
        return false
    end

    return true
end

function Page:open(ctx)
    local node
    local state = {
        flightcount = 0,
        totalflighttime = 0,
        remoteStats = {
            flightcount = 0,
            totalflighttime = 0,
            totaldistance = 0,
            minarmedtime = 0
        },
        loading = false,
        loaded = false,
        saving = false,
        error = nil,
        activeApiName = nil,
        activeApi = nil,
        closed = false,
        needsInitialLoad = true
    }

    node = {
        title = ctx.item.title or "@i18n(app.modules.stats.name)@",
        subtitle = ctx.item.subtitle or "Flight statistics",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        state = state
    }

    function node:buildForm(app)
        local countField
        local totalField

        self.app = app

        if state.error then
            form.addStaticText(form.addLine("Status"), nil, "Error")
            form.addStaticText(form.addLine(""), nil, tostring(state.error))
            return
        end

        if state.loaded ~= true then
            form.addStaticText(form.addLine("Status"), nil, state.loading == true and "Loading..." or "Waiting...")
            return
        end

        countField = form.addNumberField(form.addLine("@i18n(app.modules.stats.flightcount)@"), nil, 0, 1000000000,
            function()
                return state.flightcount
            end,
            function(newValue)
                state.flightcount = tonumber(newValue) or 0
            end)

        totalField = form.addNumberField(form.addLine("@i18n(app.modules.stats.totalflighttime)@"), nil, 0, 1000000000,
            function()
                return state.totalflighttime
            end,
            function(newValue)
                state.totalflighttime = tonumber(newValue) or 0
            end)

        if totalField and totalField.suffix then
            totalField:suffix("s")
        end
        if countField and countField.enable then
            countField:enable(state.saving ~= true)
        end
        if totalField and totalField.enable then
            totalField:enable(state.saving ~= true)
        end
    end

    function node:wakeup()
        if state.needsInitialLoad == true and state.loading ~= true and state.loaded ~= true then
            state.needsInitialLoad = false
            beginLoad(self, true)
        end
    end

    function node:save()
        if state.loaded ~= true or state.loading == true or state.saving == true then
            return false
        end

        return performSave(self)
    end

    function node:reload()
        if state.saving == true then
            return false
        end

        return beginLoad(self, true)
    end

    function node:help()
        return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.stats.name)@") .. " Help", STATS_HELP)
    end

    function node:close()
        state.closed = true
        cleanupActiveApi(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
