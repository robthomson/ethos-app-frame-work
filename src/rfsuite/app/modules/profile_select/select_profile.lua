--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local PROFILE_HELP = {
    "@i18n(app.modules.profile_select.help_p1)@",
    "@i18n(app.modules.profile_select.help_p2)@"
}

local PROFILE_CHOICES = {
    {"1", 1},
    {"2", 2},
    {"3", 3},
    {"4", 4},
    {"5", 5},
    {"6", 6}
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

local function clearActiveApi(state)
    if type(state) ~= "table" then
        return
    end

    state.activeApiName = nil
    state.activeApi = nil
end

local function trackActiveApi(state, apiName, api)
    if type(state) ~= "table" then
        return
    end

    state.activeApiName = apiName
    state.activeApi = api
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

local function beginLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("STATUS")

    if not api then
        if showLoader ~= false then
            node.app.ui.clearProgressDialog(true)
        end
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.profile_select.name)@", "@i18n(app.modules.profile_select.load_failed)@")
        return false
    end

    state.loading = true
    trackActiveApi(state, "STATUS", api)
    api.setUUID(utils.uuid("profile-select-status"))
    api.setCompleteHandler(function()
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}

        unloadApi(mspTask, "STATUS", api)
        clearActiveApi(state)
        state.loading = false

        if not nodeIsOpen(node) then
            return
        end

        state.currentPidProfile = math.max(1, (tonumber(parsed.current_pid_profile_index) or 0) + 1)
        state.currentRateProfile = math.max(1, (tonumber(parsed.current_control_rate_profile_index) or 0) + 1)
        state.pidProfile = state.currentPidProfile
        state.rateProfile = state.currentRateProfile
        state.loaded = true

        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)
    api.setErrorHandler(function()
        unloadApi(mspTask, "STATUS", api)
        clearActiveApi(state)
        state.loading = false

        if not nodeIsOpen(node) then
            return
        end

        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.profile_select.name)@", "@i18n(app.modules.profile_select.load_failed)@")
    end)

    if api.read() ~= true then
        unloadApi(mspTask, "STATUS", api)
        clearActiveApi(state)
        state.loading = false
        if showLoader ~= false then
            node.app.ui.clearProgressDialog(true)
        end
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.profile_select.name)@", "@i18n(app.modules.profile_select.load_failed)@")
        return false
    end

    return true
end

local function finishSave(node)
    local state = node.state

    if state.closed == true then
        return
    end

    if state.pendingWrites > 0 then
        return
    end

    state.saveInFlight = false
    node.app.ui.clearProgressDialog(true)

    if state.saveFailed == true then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.profile_select.name)@", "@i18n(app.modules.profile_select.save_failed)@")
        return
    end

    state.currentPidProfile = state.pidProfile
    state.currentRateProfile = state.rateProfile
end

local function queueSelect(node, payloadValue)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local ok

    ok = mspTask and mspTask.queueCommand and mspTask:queueCommand(210, {payloadValue}, {
        timeout = 1.0,
        simulatorResponse = {},
        onReply = function()
            if state.closed == true then
                return
            end
            state.pendingWrites = math.max(0, (state.pendingWrites or 1) - 1)
            finishSave(node)
        end,
        onError = function()
            if state.closed == true then
                return
            end
            state.saveFailed = true
            state.pendingWrites = math.max(0, (state.pendingWrites or 1) - 1)
            finishSave(node)
        end
    })

    if ok == true then
        state.pendingWrites = state.pendingWrites + 1
        return true
    end

    state.saveFailed = true
    return false
end

local function performSave(node)
    local state = node.state

    if state.saveInFlight == true then
        return true
    end

    if state.pidProfile == state.currentPidProfile and state.rateProfile == state.currentRateProfile then
        return true
    end

    state.pendingWrites = 0
    state.saveFailed = false
    state.saveInFlight = true

    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.profile_select.name)@",
        message = "@i18n(app.modules.profile_select.save_prompt)@",
        closeWhenIdle = false,
        modal = true
    })

    if state.rateProfile ~= state.currentRateProfile then
        queueSelect(node, math.max(0, (tonumber(state.rateProfile) or 1) - 1) + 128)
    end

    if state.pidProfile ~= state.currentPidProfile then
        queueSelect(node, math.max(0, (tonumber(state.pidProfile) or 1) - 1))
    end

    if state.pendingWrites == 0 then
        finishSave(node)
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        pidProfile = 1,
        rateProfile = 1,
        currentPidProfile = 1,
        currentRateProfile = 1,
        loaded = false,
        loading = false,
        pendingWrites = 0,
        saveInFlight = false,
        saveFailed = false,
        activeApiName = nil,
        activeApi = nil,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.profile_select.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.profile_select.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = false, tool = false, help = true},
        state = state,
        showLoaderOnEnter = true
    }

    function node:buildForm(app)
        self.app = app

        form.addChoiceField(form.addLine("@i18n(app.modules.profile_select.pid_profile)@"), nil, PROFILE_CHOICES,
            function()
                return state.pidProfile
            end,
            function(newValue)
                state.pidProfile = tonumber(newValue) or 1
            end)

        form.addChoiceField(form.addLine("@i18n(app.modules.profile_select.rate_profile)@"), nil, PROFILE_CHOICES,
            function()
                return state.rateProfile
            end,
            function(newValue)
                state.rateProfile = tonumber(newValue) or 1
            end)
    end

    function node:wakeup()
        if state.loaded ~= true and state.loading ~= true then
            beginLoad(self, false)
        end
    end

    function node:save()
        return diagnostics.openConfirmDialog(
            node.title or "@i18n(app.modules.profile_select.name)@",
            "@i18n(app.modules.profile_select.save_prompt)@",
            function()
                performSave(node)
            end
        )
    end

    function node:help()
        return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.profile_select.name)@") .. " Help", PROFILE_HELP)
    end

    function node:close()
        state.closed = true
        state.saveInFlight = false
        state.pendingWrites = 0
        cleanupActiveApi(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
