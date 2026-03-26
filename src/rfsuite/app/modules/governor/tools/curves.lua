--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local ModuleLoader = require("framework.utils.module_loader")
local diagnostics = ModuleLoader.requireOrLoad("app.modules.diagnostics.lib", "app/modules/diagnostics/lib.lua")
local utils = require("lib.utils")

local FIELD_COUNT = 9
local API_TIMEOUT = 6.0

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function ensureApi(node)
    local state = node.state
    local mspTask

    if state.api then
        return state.api
    end

    mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    state.api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("GOVERNOR_CONFIG") or nil
    return state.api
end

local function setControlsEnabled(node, enabled)
    local index
    local control

    for index = 1, #(node.state.controls or {}) do
        control = node.state.controls[index]
        if control and control.enable then
            pcall(control.enable, control, enabled == true)
        end
    end
end

local function syncSaveButton(node)
    if node and node.app and node.app._syncSaveButtonState then
        node.app:_syncSaveButtonState()
    end
end

local function markDirty(node)
    node.state.dirty = true
    syncSaveButton(node)
end

local function applyValuesToControls(node)
    local index
    local control
    local value

    for index = 1, FIELD_COUNT do
        control = node.state.controls[index]
        value = node.state.values[index]
        if control and control.value then
            pcall(control.value, control, value)
        end
    end
end

local function requestLoaderClose(node)
    if node and node.app and node.app.requestLoaderClose then
        node.app:requestLoaderClose()
    elseif node and node.app and node.app.ui and node.app.ui.clearProgressDialog then
        node.app.ui.clearProgressDialog(true)
    end
end

local function failLoad(node, err)
    local state = node.state

    state.loading = false
    state.loaded = false
    state.error = tostring(err or "read_failed")
    requestLoaderClose(node)
    setControlsEnabled(node, false)
    syncSaveButton(node)
end

local function beginLoad(node, showLoader)
    local state = node.state
    local api = ensureApi(node)
    local index
    local raw

    if not api then
        failLoad(node, "api_missing_GOVERNOR_CONFIG")
        return false
    end

    state.loading = true
    state.loaded = false
    state.error = nil
    state.dirty = false
    syncSaveButton(node)
    setControlsEnabled(node, false)

    if showLoader ~= false and node.app and node.app.ui and node.app.ui.showLoader then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.baseTitle or "@i18n(app.modules.governor.menu_curves_long)@",
            message = "Loading governor curve.",
            watchdogTimeout = 10.0,
            transferInfo = true,
            closeWhenIdle = false,
            modal = true
        })
    end

    if api.setTimeout then
        api.setTimeout(API_TIMEOUT)
    end

    api.setUUID(utils.uuid("governor-curves-read"))
    api.setCompleteHandler(function()
        if not nodeIsOpen(node) then
            return
        end

        for index = 1, FIELD_COUNT do
            raw = tonumber(api.readValue("gov_bypass_throttle_curve_" .. index) or 0) or 0
            state.values[index] = math.floor(raw / 2)
        end

        state.loading = false
        state.loaded = true
        state.error = nil
        state.dirty = false
        applyValuesToControls(node)
        setControlsEnabled(node, true)
        requestLoaderClose(node)
        syncSaveButton(node)
    end)
    api.setErrorHandler(function(_, err)
        if not nodeIsOpen(node) then
            return
        end
        failLoad(node, err)
    end)

    if api.read() ~= true then
        failLoad(node, "read_failed")
        return false
    end

    return true
end

local function beginSave(node)
    local state = node.state
    local api = ensureApi(node)
    local eepromApi
    local index
    local value

    if not api or state.loaded ~= true or state.loading == true or state.saving == true or state.dirty ~= true then
        return false
    end

    state.saving = true
    state.error = nil
    syncSaveButton(node)

    if node.app and node.app.ui and node.app.ui.showLoader then
        node.app.ui.showLoader({
            kind = "save",
            title = node.baseTitle or "@i18n(app.modules.governor.menu_curves_long)@",
            message = "Saving governor curve.",
            watchdogTimeout = 14.0,
            transferInfo = true,
            closeWhenIdle = false,
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

    for index = 1, FIELD_COUNT do
        value = clamp(tonumber(state.values[index] or 0) or 0, 0, 100)
        api.setValue("gov_bypass_throttle_curve_" .. index, math.floor(value * 2 + 0.5))
    end

    api.setUUID(utils.uuid("governor-curves-write"))
    api.setCompleteHandler(function()
        local mspTask

        if not nodeIsOpen(node) then
            return
        end

        mspTask = node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
        eepromApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE") or nil
        if not eepromApi then
            state.saving = false
            state.error = "api_missing_EEPROM_WRITE"
            requestLoaderClose(node)
            syncSaveButton(node)
            return
        end

        eepromApi.setUUID(utils.uuid("governor-curves-eeprom"))
        eepromApi.setCompleteHandler(function()
            if not nodeIsOpen(node) then
                return
            end

            state.saving = false
            state.dirty = false
            requestLoaderClose(node)
            syncSaveButton(node)
        end)
        eepromApi.setErrorHandler(function(_, err)
            if not nodeIsOpen(node) then
                return
            end

            state.saving = false
            state.error = tostring(err or "eeprom_failed")
            requestLoaderClose(node)
            syncSaveButton(node)
        end)

        if eepromApi.write() ~= true then
            state.saving = false
            state.error = "eeprom_failed"
            requestLoaderClose(node)
            syncSaveButton(node)
        end
    end)
    api.setErrorHandler(function(_, err)
        if not nodeIsOpen(node) then
            return
        end

        state.saving = false
        state.error = tostring(err or "write_failed")
        requestLoaderClose(node)
        syncSaveButton(node)
    end)

    if api.write() ~= true then
        state.saving = false
        state.error = "write_failed"
        requestLoaderClose(node)
        syncSaveButton(node)
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        values = {},
        controls = {},
        dirty = false,
        loading = false,
        loaded = false,
        saving = false,
        error = nil,
        activeIndex = 1,
        api = nil,
        closed = false
    }
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.governor.menu_curves_long)@",
        title = ctx.item.title or "@i18n(app.modules.governor.menu_curves_long)@",
        subtitle = ctx.item.subtitle or "Governor bypass curve",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        disableSaveUntilDirty = false,
        state = state
    }

    function node:canSave()
        return state.loaded == true and state.loading ~= true and state.saving ~= true and state.dirty == true
    end

    function node:buildForm(app)
        local radio
        local width
        local height
        local margin
        local gap
        local rowHeight
        local usableWidth
        local fieldWidth
        local xOffset
        local yPos
        local index
        local xPos
        local maxRight
        local controlWidth
        local control

        self.app = app
        radio = app.radio or {}
        width, height = lcd.getWindowSize()
        margin = radio.buttonPadding or 8
        gap = 5
        rowHeight = radio.navbuttonHeight or 30
        usableWidth = width - (margin * 2)
        fieldWidth = math.floor((usableWidth - (gap * (FIELD_COUNT - 1))) / FIELD_COUNT)
        xOffset = -math.floor((radio.buttonPadding or 8) / 2)
        yPos = height - rowHeight - 10

        state.controls = {}

        for index = 1, FIELD_COUNT do
            xPos = margin + ((index - 1) * (fieldWidth + gap)) + xOffset
            maxRight = width - margin
            controlWidth = fieldWidth
            if xPos + controlWidth > maxRight then
                controlWidth = maxRight - xPos
            end
            if controlWidth < 1 then
                controlWidth = 1
            end

            control = form.addNumberField(nil, {x = xPos, y = yPos, w = controlWidth, h = rowHeight}, 0, 100,
                function()
                    return state.values[index]
                end,
                function(value)
                    state.values[index] = clamp(tonumber(value or 0) or 0, 0, 100)
                    state.activeIndex = index
                    markDirty(self)
                end)

            if control and control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end
            if control and control.onFocus then
                control:onFocus(function(focused)
                    if focused == true then
                        state.activeIndex = index
                    end
                end)
            end

            state.controls[index] = control
        end

        if state.loaded == true then
            applyValuesToControls(self)
        end
    end

    function node:wakeup()
        if state.loaded ~= true and state.loading ~= true then
            beginLoad(self, true)
        end
        syncSaveButton(self)
    end

    function node:paint()
        local radio = self.app and self.app.radio or {}
        local width
        local height
        local offsetY
        local margin
        local gap
        local xOffset
        local usableWidth
        local fieldWidth
        local curveX
        local curveW
        local curveY
        local curveH
        local pad
        local gx
        local gy
        local gw
        local gh
        local index
        local xPos
        local yPos
        local points = {}
        local point
        local nextPoint
        local isDark = lcd.darkMode and lcd.darkMode() or false

        if state.loaded ~= true or not self.app then
            return
        end

        width, height = lcd.getWindowSize()
        margin = radio.buttonPadding or 8
        gap = 5
        xOffset = -math.floor((radio.buttonPadding or 8) / 2)
        usableWidth = width - (margin * 2)
        fieldWidth = math.floor((usableWidth - (gap * (FIELD_COUNT - 1))) / FIELD_COUNT)
        offsetY = height - (radio.navbuttonHeight or 30) - 10

        curveX = margin + xOffset
        curveW = (fieldWidth * FIELD_COUNT) + (gap * (FIELD_COUNT - 1))
        if curveX + curveW > (width - margin) then
            curveW = (width - margin) - curveX
        end
        curveY = radio.logGraphMenuOffset or 90
        curveH = offsetY - curveY - 10

        pad = 4
        gx = curveX + pad
        gy = curveY + pad
        gw = curveW - (pad * 2)
        gh = curveH - (pad * 2)

        if gw < 2 or gh < 2 then
            return
        end

        lcd.color(isDark and lcd.GREY(80) or lcd.GREY(180))
        for index = 0, 4 do
            yPos = gy + math.floor((gh * index) / 4 + 0.5)
            lcd.drawLine(gx, yPos, gx + gw, yPos)
        end
        for index = 0, FIELD_COUNT - 1 do
            xPos = gx + math.floor((gw * index) / (FIELD_COUNT - 1) + 0.5)
            lcd.drawLine(xPos, gy, xPos, gy + gh)
        end

        for index = 1, FIELD_COUNT do
            local value = clamp(tonumber(state.values[index] or 0) or 0, 0, 100)
            xPos = gx + math.floor(((index - 1) / (FIELD_COUNT - 1)) * gw + 0.5)
            yPos = gy + math.floor((1.0 - (value / 100.0)) * gh + 0.5)
            points[index] = {x = xPos, y = yPos}
        end

        lcd.color(isDark and lcd.RGB(255, 255, 255) or lcd.RGB(0, 0, 0))
        for index = 1, FIELD_COUNT - 1 do
            point = points[index]
            nextPoint = points[index + 1]
            lcd.drawLine(point.x, point.y, nextPoint.x, nextPoint.y)
        end

        for index = 1, FIELD_COUNT do
            point = points[index]
            if index == state.activeIndex then
                lcd.color(lcd.RGB(255, 180, 0))
                lcd.drawFilledRectangle(point.x - 4, point.y - 4, 8, 8)
            else
                lcd.color(isDark and lcd.RGB(255, 255, 255) or lcd.RGB(0, 0, 0))
                lcd.drawFilledRectangle(point.x - 2, point.y - 2, 4, 4)
            end
        end
    end

    function node:save()
        return beginSave(self)
    end

    function node:reload()
        if state.saving == true then
            return false
        end

        return beginLoad(self, true)
    end

    function node:help()
        return diagnostics.openHelpDialog(
            (self.title or "@i18n(app.modules.governor.menu_curves_long)@") .. " Help",
            {
                "@i18n(app.modules.governor.help_p1)@",
                "@i18n(app.modules.governor.help_p2)@"
            }
        )
    end

    function node:close()
        state.closed = true
        state.loading = false
        state.saving = false
        if state.api and state.api.setCompleteHandler then
            state.api.setCompleteHandler(function() end)
        end
        if state.api and state.api.setErrorHandler then
            state.api.setErrorHandler(function() end)
        end
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
