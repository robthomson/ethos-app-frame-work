--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

local function trimText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

function controller.new(shared, options)
    local opts = options or {}

    return setmetatable({
        shared = shared,
        state = {
            active = nil,
            status = nil,
            signature = nil
        },
        minVisible = tonumber(opts.minVisible) or 0.35,
        fallbackClose = tonumber(opts.fallbackClose) or 0.85,
        progressMultiplier = tonumber(opts.progressMultiplier) or 2.0,
        menuProgressFactor = tonumber(opts.menuProgressFactor) or 4.0,
        timeoutMessage = tostring(opts.timeoutMessage or "Error: timed out"),
        timeoutDetail = tostring(opts.timeoutDetail or "Press close to continue."),
        transferPlaceholder = tostring(opts.transferPlaceholder or "MSP Waiting"),
        audio = opts.audio
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_session()
    local framework = self.shared and self.shared.framework or nil
    return framework and framework.session or nil
end

function controller:_loaderText(value, fallback)
    local text = trimText(value)

    if text == "" then
        return fallback or ""
    end
    if text:find("@i18n%(", 1, false) ~= nil then
        return fallback or ""
    end

    return text
end

function controller:_openDialog(title, message)
    local opts = {
        title = title,
        message = message,
        wakeup = function()
            self:refresh()
        end,
        paint = function() end,
        options = TEXT_LEFT
    }

    if form and form.openWaitDialog then
        opts.progress = true
        return form.openWaitDialog(opts)
    end
    if form and form.openProgressDialog then
        opts.progress = true
        return form.openProgressDialog(opts)
    end
    if form and form.openDialog then
        opts.width = nil
        return form.openDialog(opts)
    end

    return nil
end

function controller:_closeDialog(handle)
    if handle and handle.close then
        pcall(handle.close, handle)
    end
end

function controller:_generalBool(key, default)
    local app = self:_app()

    if not (app and app._generalBool) then
        return default
    end
    return app:_generalBool(key, default)
end

function controller:_msp()
    local app = self:_app()

    if app and app._msp then
        return app:_msp()
    end

    return nil
end

function controller:_transferExtras()
    local session = self:_session()
    local mspTask = self:_msp()
    local queue = mspTask and mspTask.queue or nil
    local parts = {}
    local tx
    local rx
    local retries
    local crc
    local timeoutCount

    if not session then
        return nil
    end

    tx = tonumber(session:get("mspLastTxCommand", 0)) or 0
    rx = tonumber(session:get("mspLastRxCommand", 0)) or 0
    retries = queue and tonumber(queue.retryCount) or 0
    crc = tonumber(session:get("mspCrcErrors", 0)) or 0
    timeoutCount = tonumber(session:get("mspTimeouts", 0)) or 0

    if tx > 0 then
        parts[#parts + 1] = "Transmit " .. tostring(tx)
    end
    if rx > 0 then
        parts[#parts + 1] = "Receive " .. tostring(rx)
    end
    if retries > 1 then
        parts[#parts + 1] = "Retry " .. tostring(retries - 1)
    end
    if crc > 0 then
        parts[#parts + 1] = "CRC " .. tostring(crc)
    end
    if timeoutCount > 0 then
        parts[#parts + 1] = "Timeout " .. tostring(timeoutCount)
    end

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, " ")
end

function controller:_transferStatus()
    local session = self:_session()
    local now = os.clock()
    local clearAt
    local updatedAt
    local status
    local last
    local extras

    if not session then
        return self.transferPlaceholder
    end

    clearAt = tonumber(session:get("mspStatusClearAt", 0)) or 0
    if clearAt > 0 and now >= clearAt then
        session:unset("mspStatusMessage")
        session:unset("mspStatusClearAt")
    end

    status = session:get("mspStatusMessage", nil)
    last = session:get("mspStatusLast", nil)
    updatedAt = tonumber(session:get("mspStatusUpdatedAt", 0)) or 0

    if not status and last and updatedAt > 0 and (now - updatedAt) < 0.75 then
        status = last
    end

    if type(status) == "string" and status ~= "" then
        extras = self:_transferExtras()
        if extras then
            return status .. " " .. extras
        end
        return status
    end

    extras = self:_transferExtras()
    if extras then
        return extras
    end

    return self.transferPlaceholder
end

function controller:_debugLines()
    local session = self:_session()
    local mspTask = self:_msp()
    local queue = mspTask and mspTask.queue or nil
    local queueDepth
    local retryCount
    local apiProbeState
    local transport
    local command
    local connectionState
    local reason
    local lines = {}

    if not session then
        return lines
    end

    queueDepth = tonumber(session:get("mspQueueDepth", 0)) or 0
    retryCount = queue and tonumber(queue.retryCount) or 0
    apiProbeState = tostring(session:get("apiProbeState", "idle") or "idle")
    transport = tostring(session:get("connectionTransport", "disconnected") or "disconnected")
    command = tostring(session:get("mspLastCommand", "idle") or "idle")
    connectionState = tostring(session:get("connectionState", "disconnected") or "disconnected")
    reason = tostring(session:get("connectionReason", "startup") or "startup")

    lines[#lines + 1] = string.format(
        "Queue %d  Busy %s  Retry %d",
        queueDepth,
        session:get("mspBusy", false) == true and "Yes" or "No",
        math.max(0, retryCount - 1)
    )
    lines[#lines + 1] = string.format(
        "Probe %s  Cmd %s  Link %s",
        apiProbeState,
        command,
        transport
    )
    lines[#lines + 1] = string.format(
        "Conn %s  Reason %s",
        connectionState,
        reason
    )

    return lines
end

function controller:_message(active)
    local parts = {}
    local base = self:_loaderText(active.message, "Working.")
    local detail = self:_loaderText(active.detail, "")
    local transferStatus = active.transferInfo == true
        and active.timedOut ~= true
        and active.debug ~= false
        and self:_generalBool("mspstatusdialog", true) == true
        and self:_transferStatus()
        or nil
    local lines = transferStatus == nil
        and active.debug ~= false
        and self:_generalBool("mspstatusdialog", true) == true
        and self:_debugLines()
        or nil

    if transferStatus ~= nil and transferStatus ~= "" then
        parts[#parts + 1] = transferStatus
    elseif base ~= "" then
        parts[#parts + 1] = base
    end
    if detail ~= "" then
        parts[#parts + 1] = detail
    end
    if type(lines) == "table" then
        local i
        for i = 1, math.min(#lines, 3) do
            parts[#parts + 1] = lines[i]
        end
    end

    if #parts == 0 then
        return "Working."
    end

    return table.concat(parts, "\n")
end

function controller:_signature(active)
    if type(active) ~= "table" then
        return "none"
    end

    return table.concat({
        tostring(active.title or ""),
        tostring(self:_message(active)),
        tostring(active.progressCounter or 0),
        tostring(active.pendingClose == true),
        tostring(active.timedOut == true)
    }, "#")
end

function controller:_watchdogTimeout(kind, requested)
    local value = tonumber(requested)
    local mspTask
    local protocolTimeout

    if requested == false then
        return nil
    end
    if value ~= nil and value > 0 then
        return value
    end
    if requested ~= nil and requested ~= true then
        return nil
    end
    if kind ~= "progress" and kind ~= "save" then
        return nil
    end

    mspTask = self:_msp()
    protocolTimeout = tonumber(mspTask and mspTask.protocol and mspTask.protocol.timeout)

    if kind == "save" then
        if protocolTimeout and protocolTimeout > 0 then
            return protocolTimeout + 5.0
        end
        return 8.0
    end

    if protocolTimeout and protocolTimeout > 0 then
        return protocolTimeout
    end

    return 4.0
end

function controller:_tripWatchdog(active)
    local handle

    if type(active) ~= "table" or active.timedOut == true then
        return
    end

    active.timedOut = true
    active.pendingClose = false
    active.progressValue = 100
    active.message = self.timeoutMessage
    active.detail = self.timeoutDetail
    handle = active.handle

    if handle and handle.message then
        pcall(handle.message, handle, self:_message(active))
    end
    if handle and handle.value then
        pcall(handle.value, handle, 100)
    end
    if handle and handle.closeAllowed then
        pcall(handle.closeAllowed, handle, true)
    end

    if self.audio and self.audio.playFile then
        self.audio.playFile("app", "timeout.wav")
    end
end

function controller:_busyState()
    local session = self:_session()
    local apiProbeState

    if not session then
        return false
    end

    apiProbeState = tostring(session:get("apiProbeState", "idle") or "idle")

    if session:get("lifecycleActive", false) == true then
        return true
    end
    if session:get("isConnecting", false) == true then
        return true
    end
    if session:get("mspBusy", false) == true then
        return true
    end
    if apiProbeState ~= "idle" and apiProbeState ~= "connected" then
        return true
    end

    return false
end

function controller:_speed(value)
    local app = self:_app()
    local num = tonumber(value)

    if num ~= nil and num > 0 then
        return num
    end

    return app and app.loaderSpeed and app.loaderSpeed.DEFAULT or 1.0
end

function controller:_applyFocusRestore(focusMenuOnClose, restoreFocusOnClose)
    local app = self:_app()
    local modalUiActive = app and app._modalUiActive and app:_modalUiActive() == true

    if not app then
        return
    end

    if focusMenuOnClose == true then
        if modalUiActive == true then
            app.pendingFocusRestore = true
        else
            app.pendingFocusRestore = false
            if app._focusNavigationButton then
                app:_focusNavigationButton("menu")
            end
        end
    elseif restoreFocusOnClose == true then
        if modalUiActive == true then
            app.pendingFocusRestore = true
        else
            app.pendingFocusRestore = true
            if app._restoreAppFocus then
                app:_restoreAppFocus()
            end
        end
    end
end

function controller:_syncDialog(active)
    local handle
    local message
    local progressValue

    if active == nil then
        return
    end

    handle = active.handle
    message = self:_message(active)
    progressValue = tonumber(active.progressValue)
    if progressValue == nil then
        progressValue = tonumber(active.progressCounter) or 0
    end

    if handle and handle.message then
        pcall(handle.message, handle, message)
    end
    if handle and handle.value then
        pcall(handle.value, handle, math.floor(math.max(0, math.min(100, progressValue))))
    end
    if handle and handle.closeAllowed then
        pcall(handle.closeAllowed, handle, active.timedOut == true or active.allowClose == true)
    end
end

function controller:refresh()
    local now = os.clock()
    local active = self.state.active
    local signature
    local progressValue
    local mult
    local focusMenuOnClose = false
    local restoreFocusOnClose = false

    if active then
        mult = active.speed or 1.0
        progressValue = tonumber(active.progressValue)
        if active.closeRequested == true then
            active.progressCounter = math.min(100, (active.progressCounter or 0) + (15 * mult))
        elseif progressValue == nil then
            local progressFactor = (active.kind == "menu") and self.menuProgressFactor or (active.closeWhenIdle == true and 2 or 1.2)
            active.progressCounter = math.min((active.kind == "menu") and 95 or 99, (active.progressCounter or 0) + (mult * self.progressMultiplier * progressFactor))
        else
            active.progressCounter = math.max(0, math.min(100, progressValue))
        end

        if active.pendingClose == true and now >= (active.minVisibleUntil or 0) then
            focusMenuOnClose = active.focusMenuOnClose == true
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeDialog(active.handle)
            self.state.active = nil
            active = nil
        elseif active
            and active.closeRequested == true
            and active.timedOut ~= true
            and now >= (active.minVisibleUntil or 0)
            and (active.progressCounter or 0) >= 100 then
            focusMenuOnClose = active.focusMenuOnClose == true
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeDialog(active.handle)
            self.state.active = nil
            active = nil
        elseif active and active.timedOut ~= true and active.watchdogDeadline and now >= active.watchdogDeadline then
            self:_tripWatchdog(active)
        elseif active
            and active.timedOut ~= true
            and active.closeWhenIdle == true
            and now >= (active.minVisibleUntil or 0)
            and self:_busyState() ~= true
            and now >= (active.fallbackCloseAt or 0) then
            restoreFocusOnClose = active.restoreFocusOnClose == true
            self:_closeDialog(active.handle)
            self.state.active = nil
            active = nil
        end
    end

    self.state.status = nil
    if active then
        self:_syncDialog(active)
    else
        self:_applyFocusRestore(focusMenuOnClose, restoreFocusOnClose)
    end

    signature = self:_signature(active)
    self.state.signature = signature
    return signature
end

function controller:show(options)
    local opts = type(options) == "table" and options or {}
    local now = os.clock()
    local kind = opts.kind or "progress"
    local defaultTitle = kind == "save" and "Saving" or "Loading"
    local defaultMessage = kind == "save" and "Saving settings." or "Loading from flight controller."
    local watchdogTimeout = self:_watchdogTimeout(kind, opts.watchdogTimeout or opts.watchdog)

    self.state.active = {
        kind = kind,
        title = self:_loaderText(opts.title, defaultTitle),
        message = self:_loaderText(opts.message, defaultMessage),
        detail = self:_loaderText(opts.detail, ""),
        speed = self:_speed(opts.speed),
        modal = opts.modal ~= false,
        closeWhenIdle = opts.closeWhenIdle ~= false,
        allowClose = opts.allowClose == true,
        createdAt = now,
        minVisibleUntil = now + (tonumber(opts.minVisibleFor) or self.minVisible),
        fallbackCloseAt = now + (tonumber(opts.fallbackCloseAfter) or self.fallbackClose),
        watchdogDeadline = watchdogTimeout and (now + watchdogTimeout) or nil,
        pendingClose = false,
        closeRequested = false,
        focusMenuOnClose = opts.focusMenuOnClose == true,
        restoreFocusOnClose = opts.restoreFocusOnClose == true,
        timedOut = false,
        debug = opts.debug ~= false,
        transferInfo = opts.transferInfo == true,
        progressCounter = 0,
        progressValue = tonumber(opts.progressValue)
    }

    self.state.active.handle = self:_openDialog(
        self.state.active.title,
        self:_message(self.state.active)
    )
    self:refresh()
    return self.state.active
end

function controller:update(options)
    local opts = type(options) == "table" and options or {}
    local active = self.state.active

    if active == nil then
        return self:show(opts)
    end

    if opts.title ~= nil then
        active.title = self:_loaderText(opts.title, active.title)
    end
    if opts.message ~= nil then
        active.message = self:_loaderText(opts.message, active.message)
    end
    if opts.detail ~= nil then
        active.detail = self:_loaderText(opts.detail, active.detail)
    end
    if opts.speed ~= nil then
        active.speed = self:_speed(opts.speed)
    end
    if opts.closeWhenIdle ~= nil then
        active.closeWhenIdle = opts.closeWhenIdle == true
    end
    if opts.allowClose ~= nil then
        active.allowClose = opts.allowClose == true
    end
    if opts.transferInfo ~= nil then
        active.transferInfo = opts.transferInfo == true
    end
    if opts.progressValue ~= nil then
        active.progressValue = tonumber(opts.progressValue)
    end
    if opts.watchdogTimeout ~= nil or opts.watchdog ~= nil then
        local watchdogTimeout = self:_watchdogTimeout(active.kind, opts.watchdogTimeout or opts.watchdog)
        active.watchdogDeadline = watchdogTimeout and (os.clock() + watchdogTimeout) or nil
        active.timedOut = false
    elseif opts.title ~= nil or opts.message ~= nil or opts.detail ~= nil then
        local watchdogTimeout = self:_watchdogTimeout(active.kind, true)
        if watchdogTimeout then
            active.watchdogDeadline = os.clock() + watchdogTimeout
            active.timedOut = false
        end
    end

    self:refresh()
    return active
end

function controller:clear(force)
    local active = self.state.active
    local now = os.clock()
    local focusMenuOnClose = false
    local restoreFocusOnClose = false

    if active == nil then
        self:refresh()
        return true
    end

    if force == true or now >= (active.minVisibleUntil or 0) then
        focusMenuOnClose = active.focusMenuOnClose == true
        restoreFocusOnClose = active.restoreFocusOnClose == true
        self:_closeDialog(active.handle)
        self.state.active = nil
    else
        active.pendingClose = true
    end

    self:refresh()
    if self.state.active == nil then
        self:_applyFocusRestore(focusMenuOnClose, restoreFocusOnClose)
    end
    return true
end

function controller:requestClose()
    local active = self.state.active

    if active == nil then
        return true
    end

    active.closeRequested = true
    active.pendingClose = true
    active.closeWhenIdle = false
    active.progressValue = 100
    active.watchdogDeadline = nil
    active.timedOut = false
    self:refresh()
    return true
end

function controller:isActive()
    self:refresh()
    return self.state.active ~= nil
end

function controller:reset()
    if self.state.active and self.state.active.handle then
        self:_closeDialog(self.state.active.handle)
    end
    self.state.active = nil
    self.state.status = nil
    self.state.signature = nil
end

return controller
