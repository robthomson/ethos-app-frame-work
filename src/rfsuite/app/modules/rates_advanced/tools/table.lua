--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local rates = assert(loadfile("app/modules/rates/lib.lua"))()
local utils = require("lib.utils")

local function ensureApi(node)
    local state = node.state
    local mspTask
    local api

    if state.activeApi then
        return state.activeApi
    end

    mspTask = node.app.framework:getTask("msp")
    api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("RC_TUNING")
    if api then
        rates.trackActiveApi(state, "RC_TUNING", api)
    end

    return api
end

local function finishRead(node)
    local state = node.state

    state.loading = false

    if not rates.nodeIsOpen(node) then
        return
    end

    node.app:requestLoaderClose()
    if state.rateTypeControl and state.rateTypeControl.value then
        state.rateTypeControl:value(state.rateType)
        if state.rateTypeControl.enable then
            state.rateTypeControl:enable(true)
        end
    else
        node.app:_invalidateForm()
    end
end

local function beginRead(node, showLoader)
    local state = node.state
    local api = ensureApi(node)
    local current

    if not api then
        state.error = "api_missing_RC_TUNING"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    state.loading = true
    state.error = nil
    if state.rateTypeControl and state.rateTypeControl.enable then
        state.rateTypeControl:enable(false)
    end

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.baseTitle or "@i18n(app.modules.rates_advanced.table)@",
            message = "Loading values.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    api.setUUID(utils.uuid("rates-table-read"))
    api.setCompleteHandler(function()
        if not rates.nodeIsOpen(node) then
            return
        end
        current = tonumber(api.readValue and api.readValue("rates_type") or 0) or 0
        state.rateType = current
        state.currentRateType = current
        state.loaded = true
        node.app.framework.session:set("activeRateTable", current)
        finishRead(node)
    end)
    api.setErrorHandler(function(_, err)
        state.loading = false
        state.error = tostring(err or "read_failed")
        if rates.nodeIsOpen(node) then
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
        end
    end)

    if api.read() ~= true then
        state.loading = false
        state.error = "read_failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function queueEepromWrite(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local ok

    ok = mspTask and mspTask.queueCommand and mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            if not rates.nodeIsOpen(node) then
                return
            end
            state.saving = false
            state.currentRateType = state.rateType
            node.app.framework.session:set("activeRateTable", state.rateType)
            node.app:requestLoaderClose()
            node.app:setPageDirty(false)
        end,
        onError = function(_, err)
            if not rates.nodeIsOpen(node) then
                return
            end
            state.saving = false
            state.error = tostring(err or "eeprom_failed")
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
        end
    })

    if ok ~= true then
        state.saving = false
        state.error = "eeprom_queue_failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function beginSave(node)
    local state = node.state
    local api = ensureApi(node)
    local config
    local index
    local field

    if not api or state.loaded ~= true or state.loading == true or state.saving == true then
        return false
    end

    state.saving = true
    state.error = nil

    if api.clearValues then
        api.clearValues()
    end
    if api.resetWriteStatus then
        api.resetWriteStatus()
    end
    if api.setRebuildOnWrite then
        api.setRebuildOnWrite(true)
    end

    api.setValue("rates_type", state.rateType)

    if state.rateType ~= state.currentRateType then
        config = rates.getRateTable(state.rateType, node.app.framework)
        for index = 1, #(config.fields or {}) do
            field = config.fields[index]
            api.setValue(field.apikey, rates.defaultStoredValue(field))
        end
    end

    node.app.ui.showLoader({
        kind = "save",
        title = node.baseTitle or "@i18n(app.modules.rates_advanced.table)@",
        message = "Saving values.",
        closeWhenIdle = false,
        modal = true
    })

    api.setUUID(utils.uuid("rates-table-write"))
    api.setCompleteHandler(function()
        if not rates.nodeIsOpen(node) then
            return
        end
        queueEepromWrite(node)
    end)
    api.setErrorHandler(function(_, err)
        if not rates.nodeIsOpen(node) then
            return
        end
        state.saving = false
        state.error = tostring(err or "write_failed")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    if api.write() ~= true then
        state.saving = false
        state.error = "write_failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        rateType = rates.resolveTableId(ctx.framework.session:get("activeRateTable", nil), ctx.framework),
        currentRateType = rates.resolveTableId(ctx.framework.session:get("activeRateTable", nil), ctx.framework),
        loaded = false,
        loading = false,
        saving = false,
        error = nil,
        activeApiName = nil,
        activeApi = nil,
        closed = false
    }
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.rates_advanced.table)@",
        title = ctx.item.title or "@i18n(app.modules.rates_advanced.table)@",
        subtitle = ctx.item.subtitle or "Select rate table",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        showLoaderOnEnter = true,
        state = state
    }

    function node:buildForm(app)
        local line

        self.app = app

        rates.updateNodeTitle(self)

        if state.error then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.error))
            return
        end

        state.rateTypeControl = form.addChoiceField(form.addLine("@i18n(app.modules.rates_advanced.rate_table)@"), nil, rates.getRateTypeChoices(),
            function()
                return state.rateType
            end,
            function(newValue)
                state.rateType = tonumber(newValue) or state.currentRateType
                app:setPageDirty(state.rateType ~= state.currentRateType)
            end)
        if state.rateTypeControl and state.rateTypeControl.enable then
            state.rateTypeControl:enable(state.loaded == true and state.loading ~= true)
        end

        if state.rateType ~= state.currentRateType then
            line = form.addLine("Status")
            form.addStaticText(line, nil, "@i18n(app.modules.rates_advanced.msg_reset_to_defaults)@")
        end
    end

    function node:wakeup()
        rates.updateNodeTitle(self)

        if state.loaded ~= true and state.loading ~= true then
            beginRead(self, false)
        end
    end

    function node:save()
        return beginSave(self)
    end

    function node:reload()
        if state.saving == true then
            return false
        end

        state.loaded = false
        return beginRead(self, true)
    end

    function node:close()
        state.closed = true
        state.loading = false
        state.saving = false
        rates.cleanupActiveApi(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
