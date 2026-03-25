--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local BatterySession = require("telemetry.battery")
local utils = require("lib.utils")

local PROFILE_CHOICES = {
    {"1", 0},
    {"2", 1},
    {"3", 2},
    {"4", 3},
    {"5", 4},
    {"6", 5}
}

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

local function applyControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function clamp(value, minimum, maximum)
    value = tonumber(value) or 0
    if minimum ~= nil and value < minimum then
        return minimum
    end
    if maximum ~= nil and value > maximum then
        return maximum
    end
    return value
end

local function resolveActiveProfileDisplay(node)
    local telemetry = node.app and node.app.framework and node.app.framework:getTask("telemetry") or nil
    local value

    if telemetry and telemetry.getSensor then
        value = telemetry.getSensor("battery_profile")
    end
    if value == nil and node.app and node.app.framework and node.app.framework.session then
        value = node.app.framework.session:get("activeBatteryProfile", nil)
    end

    value = tonumber(value)
    if value == nil then
        return nil
    end

    value = math.floor(value)
    if value < 1 then
        return nil
    end

    return value
end

local function updateTitle(node)
    local title = node.baseTitle or "@i18n(app.modules.power.battery_name)@"
    local profile = node.state and node.state.modern == true and node.state.activeProfileDisplay or nil
    local newTitle = profile and string.format("%s #%d", title, profile) or title

    if node.title ~= newTitle then
        node.title = newTitle
        if node.app and node.app.setHeaderTitle then
            node.app:setHeaderTitle(newTitle)
        elseif node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
    end
end

local function profileCapacityKey(index)
    return "batteryCapacity_" .. tostring(math.max(0, math.min(5, tonumber(index) or 0)))
end

local function getProfileCapacity(state, profileIndex)
    return tonumber((state.configRaw or {})[profileCapacityKey(profileIndex)]) or 0
end

local function applyLoadedValues(state)
    local config = state.configRaw or {}

    if state.modern == true then
        state.selectedProfileIndex = clamp((state.profileRaw or {}).batteryProfile, 0, 5)
        state.capacityValue = getProfileCapacity(state, state.selectedProfileIndex)
    else
        state.selectedProfileIndex = nil
        state.capacityValue = clamp(config.batteryCapacity, 0, 40000)
    end

    state.maxCellVoltage = clamp(config.vbatmaxcellvoltage, 0, 500)
    state.fullCellVoltage = clamp(config.vbatfullcellvoltage, 0, 500)
    state.warnCellVoltage = clamp(config.vbatwarningcellvoltage, 0, 500)
    state.minCellVoltage = clamp(config.vbatmincellvoltage, 0, 500)
    state.cellCount = clamp(config.batteryCellCount, 0, 24)
    state.consumptionWarningPercentage = clamp(config.consumptionWarningPercentage, 15, 60)
end

local function refreshControls(state)
    applyControlValue(state.controls.profile, state.selectedProfileIndex)
    applyControlValue(state.controls.capacity, state.capacityValue)
    applyControlValue(state.controls.maxCellVoltage, state.maxCellVoltage)
    applyControlValue(state.controls.fullCellVoltage, state.fullCellVoltage)
    applyControlValue(state.controls.warnCellVoltage, state.warnCellVoltage)
    applyControlValue(state.controls.minCellVoltage, state.minCellVoltage)
    applyControlValue(state.controls.cellCount, state.cellCount)
    applyControlValue(state.controls.consumptionWarningPercentage, state.consumptionWarningPercentage)
end

local function setControlsEnabled(state, enabled)
    local control

    for _, control in pairs(state.controls or {}) do
        if control and control.enable then
            pcall(control.enable, control, enabled == true)
        end
    end
end

local function setSessionBatteryConfig(node, configValues)
    local session = node.app and node.app.framework and node.app.framework.session or nil
    local fakeApi = {
        readValue = function(key)
            return configValues[key]
        end
    }

    BatterySession.applyApiToSession(session, fakeApi, nil)
end

local function failLoad(node, reason)
    local state = node.state

    state.loading = false
    state.loaded = false
    state.error = tostring(reason or "load_failed")
    if nodeIsOpen(node) then
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end
end

local function readApi(node, apiName, uuidSuffix, done, failed)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(apiName) or nil

    if not api then
        if type(failed) == "function" then
            failed(apiName .. " unavailable.")
        end
        return false
    end

    trackActiveApi(state, apiName, api)
    if api.setUUID then
        api.setUUID(utils.uuid(uuidSuffix))
    end
    api.setCompleteHandler(function()
        local parsed = copyTable(readParsed(api) or {})

        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(done) == "function" then
            done(parsed)
        end
    end)
    api.setErrorHandler(function(_, reason)
        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(reason or (apiName .. " read failed."))
        end
    end)

    if api.read() ~= true then
        clearActiveApi(state, apiName)
        unloadApi(mspTask, apiName, api)
        if type(failed) == "function" then
            failed(apiName .. " read failed.")
        end
        return false
    end

    return true
end

local function queueEepromWrite(node, done, failed)
    local mspTask = node.app.framework:getTask("msp")
    local queued = mspTask and mspTask.queueCommand and mspTask:queueCommand(250, {}, {
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

local function startLoad(node, showLoader)
    local state = node.state

    cleanupActiveApis(state, node.app)
    state.loading = true
    state.loaded = false
    state.error = nil
    state.activeProfileDisplay = resolveActiveProfileDisplay(node)
    setControlsEnabled(state, false)

    if showLoader ~= false then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.baseTitle or "@i18n(app.modules.power.battery_name)@",
            message = "Loading battery settings.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    return readApi(node, "BATTERY_CONFIG", "power-battery-config-read", function(configParsed)
        state.configRaw = configParsed
        setSessionBatteryConfig(node, configParsed)

        if state.modern ~= true then
            applyLoadedValues(state)
            state.loading = false
            state.loaded = true
            updateTitle(node)
            if nodeIsOpen(node) then
                node.app.ui.clearProgressDialog(true)
                node.app:_invalidateForm()
                refreshControls(state)
                setControlsEnabled(state, true)
                node.app:setPageDirty(false)
            end
            return
        end

        readApi(node, "BATTERY_PROFILE", "power-battery-profile-read", function(profileParsed)
            state.profileRaw = profileParsed
            if state.activeProfileDisplay == nil then
                state.activeProfileDisplay = (tonumber(profileParsed.batteryProfile) or 0) + 1
            end
            applyLoadedValues(state)
            state.loading = false
            state.loaded = true
            updateTitle(node)
            if nodeIsOpen(node) then
                node.app.ui.clearProgressDialog(true)
                node.app:_invalidateForm()
                refreshControls(state)
                setControlsEnabled(state, true)
                node.app:setPageDirty(false)
            end
        end, function(reason)
            failLoad(node, reason)
        end)
    end, function(reason)
        failLoad(node, reason)
    end)
end

local function writeApiValues(node, apiName, payload, uuidSuffix, rebuildOnWrite, done, failed)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
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
        api.setRebuildOnWrite(rebuildOnWrite == true)
    end
    for key, value in pairs(payload or {}) do
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

local function buildConfigPayload(state)
    local payload = copyTable(state.configRaw)

    payload.vbatmaxcellvoltage = clamp(state.maxCellVoltage, 0, 500)
    payload.vbatfullcellvoltage = clamp(state.fullCellVoltage, 0, 500)
    payload.vbatwarningcellvoltage = clamp(state.warnCellVoltage, 0, 500)
    payload.vbatmincellvoltage = clamp(state.minCellVoltage, 0, 500)
    payload.batteryCellCount = clamp(state.cellCount, 0, 24)
    payload.consumptionWarningPercentage = clamp(state.consumptionWarningPercentage, 15, 60)

    if state.modern == true then
        payload[profileCapacityKey(state.selectedProfileIndex)] = clamp(state.capacityValue, 0, 40000)
    else
        payload.batteryCapacity = clamp(state.capacityValue, 0, 40000)
    end

    return payload
end

local function startSave(node)
    local state = node.state
    local configPayload
    local profilePayload

    local function fail(reason)
        state.saving = false
        if nodeIsOpen(node) then
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
        end
        state.error = tostring(reason or "Save failed.")
    end

    if state.loaded ~= true or state.loading == true or state.saving == true then
        return false
    end

    state.saving = true
    state.error = nil
    configPayload = buildConfigPayload(state)
    profilePayload = state.modern == true and {batteryProfile = clamp(state.selectedProfileIndex, 0, 5)} or nil

    node.app.ui.showLoader({
        kind = "save",
        title = node.baseTitle or "@i18n(app.modules.power.battery_name)@",
        message = "@i18n(app.msg_saving_to_fbl)@",
        closeWhenIdle = false,
        watchdogTimeout = 12.0,
        transferInfo = true,
        modal = true
    })

    local function finishSuccess()
        state.saving = false
        state.configRaw = copyTable(configPayload)
        if state.modern == true then
            state.profileRaw = copyTable(profilePayload)
            state.activeProfileDisplay = (tonumber(profilePayload.batteryProfile) or 0) + 1
            node.app.framework.session:set("activeBatteryProfile", state.activeProfileDisplay)
        end
        setSessionBatteryConfig(node, configPayload)
        applyLoadedValues(state)
        updateTitle(node)

        if queueEepromWrite(node, function()
            if nodeIsOpen(node) then
                node.app.ui.clearProgressDialog(true)
                node.app:setPageDirty(false)
                node.app:_invalidateForm()
            end
        end, function(reason)
            fail(reason)
        end) ~= true then
            fail("EEPROM write failed.")
        end
    end

    if state.modern == true then
        return writeApiValues(node, "BATTERY_PROFILE", profilePayload, "power-battery-profile-write", false, function()
            writeApiValues(node, "BATTERY_CONFIG", configPayload, "power-battery-config-write", true, finishSuccess, fail)
        end, fail)
    end

    return writeApiValues(node, "BATTERY_CONFIG", configPayload, "power-battery-config-write", true, finishSuccess, fail)
end

function Page:open(ctx)
    local state = {
        controls = {},
        activeApis = {},
        configRaw = {},
        profileRaw = {},
        modern = utils.apiVersionCompare(">=", "12.0.9"),
        loading = false,
        loaded = false,
        saving = false,
        error = nil,
        selectedProfileIndex = 0,
        activeProfileDisplay = nil,
        capacityValue = 0,
        maxCellVoltage = 0,
        fullCellVoltage = 0,
        warnCellVoltage = 0,
        minCellVoltage = 0,
        cellCount = 0,
        consumptionWarningPercentage = 35,
        closed = false,
        batteryUiSignature = nil
    }
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.power.battery_name)@",
        title = ctx.item.title or "@i18n(app.modules.power.battery_name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.power.name)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "Loading battery settings.",
            closeWhenIdle = false,
            watchdogTimeout = 10.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:buildForm(app)
        local line
        local control

        self.app = app
        state.controls = {}

        if state.error then
            line = form.addLine("Status")
            form.addStaticText(line, nil, "Error")
            line = form.addLine("")
            form.addStaticText(line, {x = 8, y = app.radio.linePaddingTop or 0, w = math.max(40, app:_windowSize() - 16), h = app.radio.navbuttonHeight or 30}, tostring(state.error))
            return
        end

        if state.modern == true then
            control = form.addChoiceField(form.addLine("    @i18n(app.modules.power.selected)@"), nil, PROFILE_CHOICES,
                function()
                    if state.loaded ~= true then
                        return nil
                    end
                    return state.selectedProfileIndex
                end,
                function(newValue)
                    newValue = clamp(newValue, 0, 5)
                    if newValue ~= state.selectedProfileIndex then
                        state.selectedProfileIndex = newValue
                        state.capacityValue = getProfileCapacity(state, newValue)
                        applyControlValue(state.controls.capacity, state.capacityValue)
                        app:setPageDirty(true)
                    end
                end)
            if control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end
            if state.loaded == true then
                applyControlValue(control, state.selectedProfileIndex)
            end
            state.controls.profile = control

            control = form.addNumberField(form.addLine("    @i18n(app.modules.power.capacity)@"), nil, 0, 40000,
                function()
                    if state.loaded ~= true then
                        return nil
                    end
                    return state.capacityValue
                end,
                function(newValue)
                    newValue = clamp(newValue, 0, 40000)
                    if newValue ~= state.capacityValue then
                        state.capacityValue = newValue
                        app:setPageDirty(true)
                    end
                end)
            if control.step then
                control:step(10)
            end
            if control.suffix then
                control:suffix("mAh")
            end
            if control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end
            if state.loaded == true then
                applyControlValue(control, state.capacityValue)
            end
            state.controls.capacity = control
        else
            control = form.addNumberField(form.addLine("@i18n(app.modules.power.battery_capacity)@"), nil, 0, 20000,
                function()
                    if state.loaded ~= true then
                        return nil
                    end
                    return state.capacityValue
                end,
                function(newValue)
                    newValue = clamp(newValue, 0, 20000)
                    if newValue ~= state.capacityValue then
                        state.capacityValue = newValue
                        app:setPageDirty(true)
                    end
                end)
            if control.step then
                control:step(50)
            end
            if control.suffix then
                control:suffix("mAh")
            end
            if control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end
            if state.loaded == true then
                applyControlValue(control, state.capacityValue)
            end
            state.controls.capacity = control
        end

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.max_cell_voltage)@"), nil, 0, 500,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.maxCellVoltage
            end,
            function(newValue)
                newValue = clamp(newValue, 0, 500)
                if newValue ~= state.maxCellVoltage then
                    state.maxCellVoltage = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(2)
        end
        if control.suffix then
            control:suffix("V")
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.maxCellVoltage)
        end
        state.controls.maxCellVoltage = control

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.full_cell_voltage)@"), nil, 0, 500,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.fullCellVoltage
            end,
            function(newValue)
                newValue = clamp(newValue, 0, 500)
                if newValue ~= state.fullCellVoltage then
                    state.fullCellVoltage = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(2)
        end
        if control.suffix then
            control:suffix("V")
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.fullCellVoltage)
        end
        state.controls.fullCellVoltage = control

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.warn_cell_voltage)@"), nil, 0, 500,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.warnCellVoltage
            end,
            function(newValue)
                newValue = clamp(newValue, 0, 500)
                if newValue ~= state.warnCellVoltage then
                    state.warnCellVoltage = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(2)
        end
        if control.suffix then
            control:suffix("V")
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.warnCellVoltage)
        end
        state.controls.warnCellVoltage = control

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.min_cell_voltage)@"), nil, 0, 500,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.minCellVoltage
            end,
            function(newValue)
                newValue = clamp(newValue, 0, 500)
                if newValue ~= state.minCellVoltage then
                    state.minCellVoltage = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.decimals then
            control:decimals(2)
        end
        if control.suffix then
            control:suffix("V")
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.minCellVoltage)
        end
        state.controls.minCellVoltage = control

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.cell_count)@"), nil, 0, 24,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.cellCount
            end,
            function(newValue)
                newValue = clamp(newValue, 0, 24)
                if newValue ~= state.cellCount then
                    state.cellCount = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.cellCount)
        end
        state.controls.cellCount = control

        control = form.addNumberField(form.addLine("    @i18n(app.modules.power.consumption_warning_percentage)@"), nil, 15, 60,
            function()
                if state.loaded ~= true then
                    return nil
                end
                return state.consumptionWarningPercentage
            end,
            function(newValue)
                newValue = clamp(newValue, 15, 60)
                if newValue ~= state.consumptionWarningPercentage then
                    state.consumptionWarningPercentage = newValue
                    app:setPageDirty(true)
                end
            end)
        if control.suffix then
            control:suffix("%")
        end
        if control.enable then
            control:enable(state.loaded == true and state.saving ~= true)
        end
        if state.loaded == true then
            applyControlValue(control, state.consumptionWarningPercentage)
        end
        state.controls.consumptionWarningPercentage = control
    end

    function node:wakeup()
        local activeProfileDisplay
        local signature

        if state.loaded ~= true and state.loading ~= true then
            startLoad(self, false)
            return
        end

        if state.loaded ~= true then
            return
        end

        activeProfileDisplay = resolveActiveProfileDisplay(self)
        if activeProfileDisplay ~= nil and activeProfileDisplay ~= state.activeProfileDisplay and state.saving ~= true then
            state.activeProfileDisplay = activeProfileDisplay
            if state.modern == true then
                state.selectedProfileIndex = clamp(activeProfileDisplay - 1, 0, 5)
                state.capacityValue = getProfileCapacity(state, state.selectedProfileIndex)
                refreshControls(state)
                if self.app and self.app.setPageDirty then
                    self.app:setPageDirty(false)
                end
            end
            updateTitle(self)
        end

        signature = table.concat({
            tostring(self.app and self.app.formBuildCount or 0),
            tostring(state.activeProfileDisplay),
            tostring(state.selectedProfileIndex),
            tostring(state.capacityValue)
        }, "|")

        if state.batteryUiSignature ~= signature then
            state.batteryUiSignature = signature
            updateTitle(self)
        end
    end

    function node:reload()
        if state.saving == true then
            return false
        end
        return startLoad(self, true)
    end

    function node:save()
        return startSave(self)
    end

    function node:help()
        if not (form and form.openDialog) then
            return false
        end

        form.openDialog({
            width = nil,
            title = self.baseTitle .. " Help",
            message = "@i18n(app.modules.power.help_p1)@",
            buttons = {{
                label = "Close",
                action = function()
                    return true
                end
            }},
            options = TEXT_LEFT
        })

        return true
    end

    function node:close()
        state.closed = true
        cleanupActiveApis(state, self.app)
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
