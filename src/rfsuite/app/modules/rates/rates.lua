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

local function applyLoadedConfig(node, api)
    local state = node.state
    local tableId = api and api.readValue and api.readValue("rates_type") or nil
    local config = rates.getRateTable(tableId, node.app.framework)

    state.tableId = config.id
    state.tableName = config.name
    state.helpLines = config.help
    state.rows = config.rows
    state.cols = config.cols
    state.fields = config.fields
    rates.populateFieldsFromApi(state.fields, api)
    node.app.framework.session:set("activeRateTable", state.tableId)
end

local function finishRead(node)
    local state = node.state

    state.loading = false

    if not rates.nodeIsOpen(node) then
        return
    end

    node.app:requestLoaderClose()
    node.app:_invalidateForm()
end

local function failRead(node, message)
    local state = node.state

    state.loading = false
    state.loaded = false
    state.error = tostring(message or "read_failed")

    if not rates.nodeIsOpen(node) then
        return
    end

    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function beginRead(node, showLoader)
    local state = node.state
    local api = ensureApi(node)

    if not api then
        failRead(node, "api_missing_RC_TUNING")
        return false
    end

    state.loading = true
    state.error = nil

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.baseTitle or "@i18n(app.modules.rates.name)@",
            message = "Loading values.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    api.setUUID(utils.uuid("rates-read"))
    api.setCompleteHandler(function()
        if not rates.nodeIsOpen(node) then
            return
        end
        applyLoadedConfig(node, api)
        state.loaded = true
        finishRead(node)
    end)
    api.setErrorHandler(function(_, err)
        failRead(node, err)
    end)

    if api.read() ~= true then
        failRead(node, "read_failed")
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

    api.setValue("rates_type", state.tableId)
    for index = 1, #(state.fields or {}) do
        field = state.fields[index]
        if type(field.apikey) == "string" and field.apikey ~= "" then
            api.setValue(field.apikey, field.value)
        end
    end

    node.app.ui.showLoader({
        kind = "save",
        title = node.baseTitle or "@i18n(app.modules.rates.name)@",
        message = "Saving values.",
        closeWhenIdle = false,
        modal = true
    })

    api.setUUID(utils.uuid("rates-write"))
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
        rows = {},
        cols = {},
        fields = {},
        tableId = rates.resolveTableId(ctx.framework.session:get("activeRateTable", nil), ctx.framework),
        tableName = "",
        helpLines = {},
        loading = false,
        loaded = false,
        saving = false,
        error = nil,
        watchedRateProfile = nil,
        activeApiName = nil,
        activeApi = nil,
        closed = false
    }
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.rates.name)@",
        title = ctx.item.title or "@i18n(app.modules.rates.name)@",
        subtitle = ctx.item.subtitle or "Rates and expo",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        showLoaderOnEnter = true,
        state = state
    }

    function node:buildForm(app)
        local line
        local numCols
        local screenWidth
        local padding
        local paddingTop
        local rowHeight
        local columnWidth
        local paddingRight
        local positions
        local posX
        local pos
        local loc
        local rowLines
        local index
        local field
        local minValue
        local maxValue
        local defaultValue

        self.app = app
        rates.updateNodeTitle(self)

        if state.error then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(state.error))
            return
        end

        if state.loaded ~= true then
            line = form.addLine("Status")
            form.addStaticText(line, nil, state.loading == true and "Loading..." or "Waiting...")
            return
        end

        numCols = #(state.cols or {})
        screenWidth = select(1, lcd.getWindowSize())
        padding = 10
        paddingTop = app.radio.linePaddingTop or 0
        rowHeight = app.radio.navbuttonHeight or 30
        columnWidth = ((screenWidth * 70 / 100) / math.max(1, numCols))
        paddingRight = 10
        positions = {}

        line = form.addLine("")
        pos = {x = 0, y = paddingTop, w = 220, h = rowHeight}
        form.addStaticText(line, pos, state.tableName or "")

        loc = numCols
        posX = screenWidth - paddingRight
        while loc > 0 do
            positions[loc] = posX - columnWidth
            pos = {x = positions[loc] + paddingRight, y = paddingTop, w = columnWidth, h = rowHeight}
            form.addStaticText(line, pos, tostring(state.cols[loc] or ""))
            posX = math.floor(posX - columnWidth)
            loc = loc - 1
        end

        rowLines = {}
        for index = 1, #(state.rows or {}) do
            rowLines[index] = form.addLine(state.rows[index])
        end

        for index = 1, #(state.fields or {}) do
            field = state.fields[index]
            local currentField = field
            minValue = tonumber(field.min) or 0
            maxValue = tonumber(field.max) or 0

            if currentField.decimals then
                minValue = minValue * rates.decimalInc(currentField.decimals)
                maxValue = maxValue * rates.decimalInc(currentField.decimals)
            end
            if currentField.mult then
                minValue = minValue * currentField.mult
                maxValue = maxValue * currentField.mult
            end
            if currentField.scale then
                minValue = minValue / currentField.scale
                maxValue = maxValue / currentField.scale
            end

            pos = {x = positions[currentField.col] + padding, y = paddingTop, w = columnWidth - padding, h = rowHeight}
            currentField.control = form.addNumberField(rowLines[currentField.row], pos, minValue, maxValue,
                function()
                    return rates.getFieldDisplayValue(currentField)
                end,
                function(value)
                    rates.saveFieldDisplayValue(currentField, value)
                    app:setPageDirty(true)
                end)

            defaultValue = rates.defaultDisplayValue(currentField)
            if currentField.control.default then
                currentField.control:default(defaultValue)
            end
            if currentField.decimals and currentField.control.decimals then
                currentField.control:decimals(currentField.decimals)
            end
            if currentField.unit and currentField.control.suffix then
                currentField.control:suffix(currentField.unit)
            end
            if currentField.step and currentField.control.step then
                currentField.control:step(currentField.step)
            end
            if currentField.disable == true and currentField.control.enable then
                currentField.control:enable(false)
            end
        end
    end

    function node:wakeup()
        local currentRateProfile = rates.currentRateProfile(self.app)

        rates.updateNodeTitle(self)

        if state.watchedRateProfile == nil then
            state.watchedRateProfile = currentRateProfile
        elseif currentRateProfile ~= nil and currentRateProfile ~= state.watchedRateProfile and state.loading ~= true and state.saving ~= true then
            state.watchedRateProfile = currentRateProfile
            beginRead(self, true)
            return
        end

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

    function node:help()
        local title = (self.title or "@i18n(app.modules.rates.name)@") .. " Help"
        return diagnostics.openHelpDialog(title, state.helpLines or {})
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
