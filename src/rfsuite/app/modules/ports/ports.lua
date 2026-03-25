--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local utils = require("lib.utils")

local MSP_SET_SERIAL_CONFIG = 55

local PORT_TYPE_DISABLED = 0
local PORT_TYPE_MSP = 1
local PORT_TYPE_GPS = 2
local PORT_TYPE_TELEM = 3
local PORT_TYPE_MAVLINK = 4
local PORT_TYPE_BLACKBOX = 5
local PORT_TYPE_CUSTOM = 6
local PORT_TYPE_AUTO = 7

local FUNCTION_MASK_RX_SERIAL = 64

local BAUD_RATES = {
    "AUTO", "9600", "19200", "38400", "57600", "115200", "230400", "250000",
    "400000", "460800", "500000", "921600", "1000000", "1500000", "2000000", "2470000"
}

local PORT_FUNCTIONS = {
    {id = 0, excl = 0, name = "@i18n(app.modules.ports.function_disabled)@", type = PORT_TYPE_DISABLED},
    {id = 1, excl = 1, name = "MSP", type = PORT_TYPE_MSP},
    {id = 2, excl = 2, name = "GPS", type = PORT_TYPE_GPS},
    {id = 64, excl = 64, name = "@i18n(app.modules.ports.function_rx_serial)@", type = PORT_TYPE_AUTO},
    {id = 1024, excl = 1024, name = "@i18n(app.modules.ports.function_esc_sensor)@", type = PORT_TYPE_AUTO},
    {id = 128, excl = 128, name = "@i18n(app.modules.ports.function_blackbox)@", type = PORT_TYPE_BLACKBOX},
    {id = 262144, excl = 262144, name = "@i18n(app.modules.ports.function_sbus_out)@", type = PORT_TYPE_AUTO, minApi = {12, 0, 7}},
    {id = 524288, excl = 524288, name = "@i18n(app.modules.ports.function_fbus)@", type = PORT_TYPE_AUTO, minApi = {12, 0, 9}},
    {id = 4, excl = 4668, name = "@i18n(app.modules.ports.function_telem_frsky)@", type = PORT_TYPE_TELEM},
    {id = 32, excl = 4668, name = "@i18n(app.modules.ports.function_telem_smartport)@", type = PORT_TYPE_TELEM},
    {id = 4096, excl = 4668, name = "@i18n(app.modules.ports.function_telem_ibus)@", type = PORT_TYPE_TELEM},
    {id = 8, excl = 4668, name = "@i18n(app.modules.ports.function_telem_hott)@", type = PORT_TYPE_TELEM},
    {id = 512, excl = 4668, name = "@i18n(app.modules.ports.function_telem_mavlink)@", type = PORT_TYPE_MAVLINK},
    {id = 16, excl = 4668, name = "@i18n(app.modules.ports.function_telem_ltm)@", type = PORT_TYPE_TELEM}
}

local BAUD_OPTIONS = {
    [PORT_TYPE_DISABLED] = {0},
    [PORT_TYPE_MSP] = {1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12},
    [PORT_TYPE_GPS] = {0, 1, 2, 3, 4, 5, 6, 9},
    [PORT_TYPE_TELEM] = {0},
    [PORT_TYPE_MAVLINK] = {0, 1, 2, 3, 4, 5, 6, 9},
    [PORT_TYPE_BLACKBOX] = {0, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15},
    [PORT_TYPE_CUSTOM] = {0},
    [PORT_TYPE_AUTO] = {0}
}

local UART_NAMES = {
    [0] = "UART1",
    [1] = "UART2",
    [2] = "UART3",
    [3] = "UART4",
    [4] = "UART5",
    [5] = "UART6",
    [6] = "UART7",
    [7] = "UART8",
    [8] = "UART9",
    [9] = "UART10",
    [20] = "USB VCP",
    [30] = "SOFTSERIAL1",
    [31] = "SOFTSERIAL2"
}

local function noopHandler()
end

local function shallowCopy(tbl)
    local out = {}
    local key

    for key, value in pairs(tbl or {}) do
        out[key] = value
    end

    return out
end

local function clonePorts(ports)
    local out = {}
    local index

    for index = 1, #(ports or {}) do
        out[index] = shallowCopy(ports[index])
    end

    return out
end

local function applyControlValue(control, value)
    if control and control.value then
        pcall(control.value, control, value)
    end
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
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
    if type(state.activeApis) ~= "table" then
        return nil
    end

    local api = state.activeApis[apiName]
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
            api.setCompleteHandler(noopHandler)
        end
        if api and api.setErrorHandler then
            api.setErrorHandler(noopHandler)
        end
        if api and api.setUUID then
            api.setUUID(nil)
        end
        unloadApi(mspTask, apiName, api)
        state.activeApis[apiName] = nil
    end
end

local function portLabel(identifier)
    local name = UART_NAMES[identifier]

    if name then
        return name
    end

    return "@i18n(app.modules.ports.port_prefix)@ " .. tostring(identifier)
end

local function getPortFunctionById(functionMask)
    local index
    local entry

    for index = 1, #PORT_FUNCTIONS do
        entry = PORT_FUNCTIONS[index]
        if entry.id == functionMask then
            return entry
        end
    end

    return nil
end

local function getPortType(functionMask)
    local entry = getPortFunctionById(functionMask)
    return entry and entry.type or PORT_TYPE_CUSTOM
end

local function getPortExcl(functionMask)
    local entry = getPortFunctionById(functionMask)
    return entry and entry.excl or functionMask
end

local function functionAvailable(def)
    if def.minApi and not utils.apiVersionCompare(">=", def.minApi) then
        return false
    end
    if def.maxApi and not utils.apiVersionCompare("<=", def.maxApi) then
        return false
    end
    return true
end

local function getActiveBaudIndex(port)
    local ptype = getPortType(port.function_mask)

    if ptype == PORT_TYPE_MSP then
        return port.msp_baud_index
    end
    if ptype == PORT_TYPE_GPS then
        return port.gps_baud_index
    end
    if ptype == PORT_TYPE_BLACKBOX then
        return port.blackbox_baud_index
    end
    if ptype == PORT_TYPE_MAVLINK then
        return port.telem_baud_index
    end
    if ptype == PORT_TYPE_CUSTOM then
        return port.msp_baud_index
    end

    return 0
end

local function setActiveBaudIndex(port, baudIndex)
    local ptype = getPortType(port.function_mask)

    if ptype == PORT_TYPE_MSP then
        port.msp_baud_index = baudIndex
    elseif ptype == PORT_TYPE_GPS then
        port.gps_baud_index = baudIndex
    elseif ptype == PORT_TYPE_BLACKBOX then
        port.blackbox_baud_index = baudIndex
    elseif ptype == PORT_TYPE_MAVLINK then
        port.telem_baud_index = baudIndex
    elseif ptype == PORT_TYPE_CUSTOM then
        port.msp_baud_index = baudIndex
    end
end

local function buildBaudChoiceTable(port)
    local ptype = getPortType(port.function_mask)
    local allowed = BAUD_OPTIONS[ptype] or BAUD_OPTIONS[PORT_TYPE_AUTO]
    local current = getActiveBaudIndex(port)
    local present = {}
    local tableData = {}
    local index
    local idx

    for index = 1, #allowed do
        idx = allowed[index]
        if BAUD_RATES[idx + 1] then
            tableData[#tableData + 1] = {BAUD_RATES[idx + 1], idx}
            present[idx] = true
        end
    end

    if not present[current] then
        tableData[#tableData + 1] = {"@i18n(app.modules.ports.function_custom)@", current}
    end

    return tableData
end

local function buildFunctionChoiceTable(state, portIndex)
    local port = state.portsWorking[portIndex]
    local forbidden = 0
    local tableData = {}
    local seen = {}
    local index
    local def
    local allowed

    if not port then
        return tableData
    end

    for index = 1, #state.portsWorking do
        if index ~= portIndex then
            forbidden = forbidden | getPortExcl(state.portsWorking[index].function_mask)
        end
    end

    for index = 1, #PORT_FUNCTIONS do
        def = PORT_FUNCTIONS[index]
        if functionAvailable(def) then
            allowed = ((def.id & forbidden) == 0)
            if allowed or def.id == port.function_mask then
                tableData[#tableData + 1] = {def.name, def.id}
                seen[def.id] = true
            end
        end
    end

    if not seen[port.function_mask] then
        tableData[#tableData + 1] = {
            "@i18n(app.modules.ports.function_custom)@",
            port.function_mask
        }
    end

    return tableData
end

local function applyReceiverGuardToWorkingCopy(state)
    local index

    for index = 1, #state.portsWorking do
        if state.portsWorking[index].receiver_locked then
            state.portsWorking[index] = shallowCopy(state.portsOriginal[index])
        end
    end
end

local function u32ToBytes(value)
    local v = tonumber(value) or 0

    return v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF
end

local function queueSetSerialPort(node, port, done, failed)
    local mspTask = node.app.framework:getTask("msp")
    local b1
    local b2
    local b3
    local b4
    local payload = {
        port.identifier
    }

    if not (mspTask and mspTask.queueCommand) then
        if failed then
            failed("@i18n(app.modules.ports.error_serial_api_unavailable)@")
        end
        return false
    end

    b1, b2, b3, b4 = u32ToBytes(port.function_mask or 0)
    payload[#payload + 1] = b1
    payload[#payload + 1] = b2
    payload[#payload + 1] = b3
    payload[#payload + 1] = b4
    payload[#payload + 1] = port.msp_baud_index or 0
    payload[#payload + 1] = port.gps_baud_index or 0
    payload[#payload + 1] = port.telem_baud_index or 0
    payload[#payload + 1] = port.blackbox_baud_index or 0

    return mspTask:queueCommand(MSP_SET_SERIAL_CONFIG, payload, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            if type(done) == "function" then
                done()
            end
        end,
        onError = function(_, reason)
            if type(failed) == "function" then
                failed(reason or ("@i18n(app.modules.ports.error_serial_write_failed_for)@ " .. portLabel(port.identifier)))
            end
        end
    })
end

local function runReboot(node, onSuccess, onError)
    local mspTask = node.app.framework:getTask("msp")
    local sensorsTask = node.app.framework:getTask("sensors")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("REBOOT")

    if not api then
        if type(onError) == "function" then
            onError("@i18n(app.modules.ports.error_eeprom_write_failed)@")
        end
        return false
    end

    if sensorsTask and sensorsTask.armSensorLostMute then
        sensorsTask:armSensorLostMute(10)
    end

    if api.clearValues then
        api.clearValues()
    end
    if api.setUUID then
        api.setUUID(utils.uuid("ports-reboot"))
    end

    if api.write() ~= true then
        unloadApi(mspTask, "REBOOT", api)
        if type(onError) == "function" then
            onError("@i18n(app.modules.ports.error_eeprom_write_failed)@")
        end
        return false
    end

    unloadApi(mspTask, "REBOOT", api)
    if type(onSuccess) == "function" then
        onSuccess()
    end
    return true
end

local function startLoad(node, showLoader)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local serialApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("SERIAL_CONFIG")
    local index
    local identifier
    local functionMask
    local port
    local parsed

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.loading = false
        state.loaded = false
        state.loadError = tostring(message or "@i18n(app.modules.ports.error_failed_load)@")
        state.saveError = nil
        state.portsOriginal = {}
        state.portsWorking = {}
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    cleanupActiveApis(state, node.app)
    state.loading = true
    state.loaded = false
    state.loadError = nil
    state.saveError = nil
    state.portsOriginal = {}
    state.portsWorking = {}
    node.app:setPageDirty(false)

    if showLoader == true then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.ports.name)@",
            message = "@i18n(app.modules.ports.progress_loading)@",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if not serialApi then
        fail("@i18n(app.modules.ports.error_serial_api_unavailable)@")
        return false
    end

    trackActiveApi(state, "SERIAL_CONFIG", serialApi)
    if serialApi.setUUID then
        serialApi.setUUID(utils.uuid("ports-serial-config"))
    end
    serialApi.setCompleteHandler(function()
        parsed = serialApi.data and serialApi.data().parsed or nil
        if not nodeIsOpen(node) then
            clearActiveApi(state, "SERIAL_CONFIG")
            unloadApi(mspTask, "SERIAL_CONFIG", serialApi)
            return
        end

        for index = 1, 12 do
            identifier = parsed and parsed["port_" .. index .. "_identifier"] or nil
            if identifier == nil then
                break
            end
            if identifier ~= 20 then
                functionMask = tonumber(parsed["port_" .. index .. "_function_mask"] or 0) or 0
                port = {
                    identifier = tonumber(identifier) or 0,
                    function_mask = functionMask,
                    msp_baud_index = tonumber(parsed["port_" .. index .. "_msp_baud_index"] or 0) or 0,
                    gps_baud_index = tonumber(parsed["port_" .. index .. "_gps_baud_index"] or 0) or 0,
                    telem_baud_index = tonumber(parsed["port_" .. index .. "_telem_baud_index"] or 0) or 0,
                    blackbox_baud_index = tonumber(parsed["port_" .. index .. "_blackbox_baud_index"] or 0) or 0,
                    receiver_locked = (functionMask & FUNCTION_MASK_RX_SERIAL) ~= 0
                }
                state.portsWorking[#state.portsWorking + 1] = port
            end
        end

        state.portsOriginal = clonePorts(state.portsWorking)
        state.loading = false
        state.loaded = true
        clearActiveApi(state, "SERIAL_CONFIG")
        unloadApi(mspTask, "SERIAL_CONFIG", serialApi)
        node.app:setPageDirty(false)
        node.app:requestLoaderClose()
        node.app:_invalidateForm()
    end)
    serialApi.setErrorHandler(function(_, reason)
        clearActiveApi(state, "SERIAL_CONFIG")
        unloadApi(mspTask, "SERIAL_CONFIG", serialApi)
        fail(reason or "@i18n(app.modules.ports.error_read_serial_ports)@")
    end)

    if serialApi.read() ~= true then
        clearActiveApi(state, "SERIAL_CONFIG")
        unloadApi(mspTask, "SERIAL_CONFIG", serialApi)
        fail("@i18n(app.modules.ports.error_read_serial_ports)@")
        return false
    end

    return true
end

local function performSave(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local eepromApi = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE")
    local index = 1
    local total

    local function fail(message)
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = tostring(message or "@i18n(app.modules.ports.error_save_failed)@")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function finishSuccess()
        cleanupActiveApis(state, node.app)
        state.saving = false
        state.saveError = nil
        state.portsOriginal = clonePorts(state.portsWorking)
        node.app:setPageDirty(false)
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end

    local function writeNext()
        local current

        if index > total then
            if not eepromApi then
                fail("@i18n(app.modules.ports.error_eeprom_write_failed)@")
                return false
            end

            trackActiveApi(state, "EEPROM_WRITE", eepromApi)
            if eepromApi.clearValues then
                eepromApi.clearValues()
            end
            if eepromApi.setUUID then
                eepromApi.setUUID(utils.uuid("ports-eeprom"))
            end
            eepromApi.setCompleteHandler(function()
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                runReboot(node, finishSuccess, fail)
            end)
            eepromApi.setErrorHandler(function(_, reason)
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail(reason or "@i18n(app.modules.ports.error_eeprom_write_failed)@")
            end)

            if eepromApi.write() ~= true then
                clearActiveApi(state, "EEPROM_WRITE")
                unloadApi(mspTask, "EEPROM_WRITE", eepromApi)
                fail("@i18n(app.modules.ports.error_eeprom_write_failed)@")
                return false
            end

            return true
        end

        current = state.portsWorking[index]
        if node.app and node.app.updateLoader then
            node.app:updateLoader({
                message = "@i18n(app.modules.ports.progress_saving)@",
                detail = portLabel(current.identifier) .. " (" .. tostring(index) .. "/" .. tostring(total) .. ")"
            })
        end

        return queueSetSerialPort(node, current, function()
            index = index + 1
            writeNext()
        end, fail)
    end

    if state.loading == true or state.saving == true or state.loaded ~= true or node.app.pageDirty ~= true then
        return false
    end

    applyReceiverGuardToWorkingCopy(state)
    total = #state.portsWorking
    state.saving = true
    state.saveError = nil

    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.ports.name)@",
        message = "@i18n(app.modules.ports.progress_saving)@",
        closeWhenIdle = false,
        modal = true
    })

    return writeNext()
end

function Page:open(ctx)
    local node = {
        title = ctx.item.title or "@i18n(app.modules.ports.name)@",
        subtitle = ctx.item.subtitle or "UART and feature ports",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        state = {
            loading = false,
            loaded = false,
            saving = false,
            loadError = nil,
            saveError = nil,
            portsOriginal = {},
            portsWorking = {},
            activeApis = {}
        }
    }

    local function markDirty()
        node.app:setPageDirty(true)
    end

    function node:buildForm(app)
        local width
        local h
        local y
        local rightPadding
        local gap
        local wBaud
        local wFunc
        local xBaud
        local xFunc
        local index
        local port
        local lineTitle
        local line
        local functionChoices
        local functionField
        local baudChoices
        local baudField
        local rowControls

        self.app = app
        self.state.rowControls = {}
        rowControls = self.state.rowControls

        if self.state.loading == true then
            form.addLine("@i18n(app.modules.ports.loading)@")
            return
        end

        if self.state.loadError then
            form.addLine("@i18n(app.modules.ports.load_error_prefix)@ " .. tostring(self.state.loadError))
            return
        end

        if #self.state.portsWorking == 0 then
            form.addLine("@i18n(app.modules.ports.no_ports_reported)@")
            return
        end

        if self.state.saveError then
            form.addLine("@i18n(app.modules.ports.save_error_prefix)@ " .. tostring(self.state.saveError))
        end

        width = app:_windowSize()
        h = app.radio.navbuttonHeight or 30
        y = app.radio.linePaddingTop or 0
        rightPadding = 8
        gap = 6
        wBaud = math.floor(width * 0.28)
        wFunc = math.floor(width * 0.42)
        xBaud = width - rightPadding - wBaud
        xFunc = xBaud - gap - wFunc

        for index = 1, #self.state.portsWorking do
            local currentPort = self.state.portsWorking[index]
            local currentIndex = index

            port = currentPort
            lineTitle = portLabel(currentPort.identifier)
            if currentPort.receiver_locked then
                lineTitle = lineTitle .. " @i18n(app.modules.ports.rx_tag)@"
            end

            line = form.addLine(lineTitle)
            functionChoices = buildFunctionChoiceTable(self.state, currentIndex)
            functionField = form.addChoiceField(line, {x = xFunc, y = y, w = wFunc, h = h}, functionChoices,
                function()
                    return currentPort.function_mask
                end,
                function(value)
                    local previousFunctionMask
                    local nextBaudChoices
                    local currentBaud
                    local currentStillAllowed = false
                    local baudIndex

                    if currentPort.receiver_locked then
                        return
                    end
                    if value == currentPort.function_mask then
                        return
                    end

                    previousFunctionMask = currentPort.function_mask
                    currentPort.function_mask = value
                    nextBaudChoices = buildBaudChoiceTable(currentPort)
                    currentBaud = getActiveBaudIndex(currentPort)
                    for baudIndex = 1, #nextBaudChoices do
                        if nextBaudChoices[baudIndex][2] == currentBaud then
                            currentStillAllowed = true
                            break
                        end
                    end
                    if currentStillAllowed ~= true and #nextBaudChoices > 0 then
                        setActiveBaudIndex(currentPort, nextBaudChoices[1][2])
                    end

                    markDirty()
                    if functionField and functionField.values then
                        functionField:values(buildFunctionChoiceTable(self.state, currentIndex))
                    end
                    if baudField and baudField.values then
                        baudField:values(nextBaudChoices)
                    end
                    applyControlValue(functionField, currentPort.function_mask)
                    applyControlValue(baudField, getActiveBaudIndex(currentPort))

                    if getPortExcl(previousFunctionMask) ~= getPortExcl(value) then
                        local updateIndex
                        local updatePort
                        local controls

                        for updateIndex = 1, #self.state.portsWorking do
                            if updateIndex ~= currentIndex then
                                updatePort = self.state.portsWorking[updateIndex]
                                controls = rowControls[updateIndex]
                                if controls and controls.functionField and controls.functionField.values then
                                    controls.functionField:values(buildFunctionChoiceTable(self.state, updateIndex))
                                    applyControlValue(controls.functionField, updatePort.function_mask)
                                end
                            end
                        end
                    end
                end)

            baudChoices = buildBaudChoiceTable(currentPort)
            baudField = form.addChoiceField(line, {x = xBaud, y = y, w = wBaud, h = h}, baudChoices,
                function()
                    return getActiveBaudIndex(currentPort)
                end,
                function(value)
                    if currentPort.receiver_locked then
                        return
                    end
                    if value == getActiveBaudIndex(currentPort) then
                        return
                    end
                    setActiveBaudIndex(currentPort, value)
                    markDirty()
                end)

            if functionField and functionField.enable then
                functionField:enable(not currentPort.receiver_locked)
            end
            if baudField and baudField.enable then
                baudField:enable(not currentPort.receiver_locked)
            end

            rowControls[currentIndex] = {
                functionField = functionField,
                baudField = baudField
            }
            applyControlValue(functionField, currentPort.function_mask)
            applyControlValue(baudField, getActiveBaudIndex(currentPort))
        end
    end

    function node:canSave()
        local requireDirty = true

        if self.state.loaded ~= true or self.state.loading == true or self.state.saving == true then
            return false
        end

        if self.app and self.app._saveDirtyOnly then
            requireDirty = self.app:_saveDirtyOnly() == true
        end

        if requireDirty == true then
            return self.app.pageDirty == true
        end

        return true
    end

    function node:reload()
        if self.state.saving == true then
            return false
        end
        return startLoad(self, true)
    end

    function node:save()
        if not self:canSave() then
            return false
        end
        return performSave(self)
    end

    function node:wakeup()
        if self.state.loaded ~= true and self.state.loading ~= true and self.state.loadError == nil then
            startLoad(self, true)
        end
    end

    function node:close()
        self.state.closed = true
        cleanupActiveApis(self.state, self.app)
        self.app.ui.clearProgressDialog(true)
    end

    return node
end

return Page
