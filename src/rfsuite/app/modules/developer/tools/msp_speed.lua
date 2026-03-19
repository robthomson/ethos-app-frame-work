--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local TEST_DURATIONS = {
    {label = "30S", seconds = 30},
    {label = "60S", seconds = 60},
    {label = "120S", seconds = 120},
    {label = "300S", seconds = 300}
}

local API_SEQUENCE = {
    "BATTERY_CONFIG",
    "GOVERNOR_CONFIG",
    "MIXER_CONFIG"
}

local function round(value, decimals)
    local scale = 10 ^ (decimals or 0)
    return math.floor((tonumber(value) or 0) * scale + 0.5) / scale
end

local function valuePos(app)
    return app:_valuePos()
end

local function formatSeconds(value)
    local number = tonumber(value)

    if number == nil then
        return "-"
    end

    return string.format("%.2fs", number)
end

local function resetStats(state)
    state.stats = {
        total = 0,
        success = 0,
        retries = 0,
        timeouts = 0,
        errors = 0,
        avgTime = 0,
        minTime = nil,
        maxTime = 0
    }
    state.active = false
    state.duration = 0
    state.startedAt = nil
    state.endsAt = nil
    state.pending = false
    state.pendingApi = nil
    state.currentStartedAt = nil
    state.nextApiIndex = 1
    state.lastError = "-"
    state.status = "Idle"
    state.lastTransport = "-"
end

local function updateField(field, value)
    if field and field.value then
        field:value(value)
    end
end

local function refreshFields(node)
    local fields = node.fields
    local state = node.state
    local stats = state.stats
    local avg = "-"

    if not fields then
        return
    end

    if stats.total > 0 then
        avg = formatSeconds(stats.avgTime / stats.total)
    end

    updateField(fields.transport, state.lastTransport or "-")
    updateField(fields.total, tostring(stats.total or 0))
    updateField(fields.success, tostring(stats.success or 0))
    updateField(fields.retries, tostring(stats.retries or 0))
    updateField(fields.timeouts, tostring(stats.timeouts or 0))
    updateField(fields.errors, tostring(stats.errors or 0))
    updateField(fields.minTime, stats.minTime and formatSeconds(stats.minTime) or "-")
    updateField(fields.maxTime, stats.maxTime and formatSeconds(stats.maxTime) or "-")
    updateField(fields.avgTime, avg)
end

local function queueIsIdle(mspTask)
    local queue = mspTask and mspTask.queue

    if not queue then
        return true
    end

    return queue:isProcessed() == true
end

local function updateLoaderDetail(node)
    local state = node.state
    local elapsed
    local progressValue = 0

    if state.active ~= true then
        return
    end

    elapsed = math.max(0, os.clock() - (state.startedAt or os.clock()))
    if tonumber(state.duration) and tonumber(state.duration) > 0 then
        progressValue = math.max(0, math.min(100, (elapsed * 100) / tonumber(state.duration)))
    end

    node.app.ui.updateLoader({
        detail = string.format(
            "Test %.0fs  Elapsed %.1fs  Queries %d",
            tonumber(state.duration) or 0,
            elapsed,
            tonumber(state.stats.total) or 0
        ),
        progressValue = progressValue
    })
end

local function finishTest(node, statusText)
    local state = node.state

    if state.active ~= true then
        return
    end

    state.active = false
    state.pending = false
    state.pendingApi = nil
    state.currentStartedAt = nil
    state.status = statusText or "Complete"
    node.app.ui.clearProgressDialog(true)
    refreshFields(node)
    node.app:_invalidateForm()
end

local function startNextQuery(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local apiName = API_SEQUENCE[state.nextApiIndex]
    local api
    local loadErr
    local queued
    local queueReason

    if not mspTask or not mspTask.api or not mspTask.api.load then
        state.status = "MSP unavailable"
        state.lastError = "msp_unavailable"
        finishTest(node, state.status)
        return false
    end

    api, loadErr = mspTask.api.load(apiName)
    if not api then
        state.status = "API load failed"
        state.lastError = tostring(loadErr)
        finishTest(node, state.status)
        return false
    end

    state.pending = true
    state.pendingApi = apiName
    state.currentStartedAt = os.clock()
    state.status = "Querying " .. apiName

    api.setUUID("msp-speed-" .. string.lower(apiName) .. "-" .. tostring(state.stats.total + 1))
    api.setErrorHandler(function(_, reason)
        local elapsed = os.clock() - (state.currentStartedAt or os.clock())

        state.pending = false
        state.pendingApi = nil
        state.currentStartedAt = nil
        state.lastError = tostring(reason or "error")
        if reason == "timeout" or reason == "max_retries" then
            state.stats.timeouts = state.stats.timeouts + 1
        else
            state.stats.errors = state.stats.errors + 1
        end
        state.stats.total = state.stats.total + 1
        state.stats.avgTime = state.stats.avgTime + math.max(0, elapsed)
        state.stats.maxTime = math.max(state.stats.maxTime or 0, elapsed)
        if state.stats.minTime == nil or elapsed < state.stats.minTime then
            state.stats.minTime = elapsed
        end
        state.status = "Last error: " .. state.lastError
        refreshFields(node)
        updateLoaderDetail(node)
    end)
    api.setCompleteHandler(function()
        local elapsed = os.clock() - (state.currentStartedAt or os.clock())
        local retryCount = (mspTask.queue and tonumber(mspTask.queue.retryCount) or 1) - 1

        state.pending = false
        state.pendingApi = nil
        state.currentStartedAt = nil
        state.lastError = "-"
        state.stats.total = state.stats.total + 1
        state.stats.success = state.stats.success + 1
        state.stats.retries = state.stats.retries + math.max(0, retryCount)
        state.stats.avgTime = state.stats.avgTime + math.max(0, elapsed)
        state.stats.maxTime = math.max(state.stats.maxTime or 0, elapsed)
        if state.stats.minTime == nil or elapsed < state.stats.minTime then
            state.stats.minTime = elapsed
        end
        state.status = "Last OK: " .. apiName
        refreshFields(node)
        updateLoaderDetail(node)
    end)

    queued, queueReason = api.read()
    if queued ~= true then
        state.pending = false
        state.pendingApi = nil
        state.currentStartedAt = nil
        state.lastError = tostring(queueReason or "queue_failed")
        state.status = "Queue failed"
        refreshFields(node)
        updateLoaderDetail(node)
        return false
    end

    state.nextApiIndex = (state.nextApiIndex % #API_SEQUENCE) + 1
    refreshFields(node)
    updateLoaderDetail(node)
    return true
end

local function openDurationDialog(node)
    local buttons = {}
    local i

    if not (form and form.openDialog) then
        node:startTest(TEST_DURATIONS[1].seconds)
        return true
    end

    for i = #TEST_DURATIONS, 1, -1 do
        local duration = TEST_DURATIONS[i]
        buttons[#buttons + 1] = {
            label = duration.label,
            action = function()
                node:startTest(duration.seconds)
                return true
            end
        }
    end

    form.openDialog({
        width = nil,
        title = "MSP Speed Test",
        message = "Select test duration.",
        buttons = buttons,
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
    return true
end

function Page:open(ctx)
    local node = {
        title = ctx.item.title or "MSP Speed",
        subtitle = ctx.item.subtitle or "MSP throughput tester",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = true, tool = true, help = false},
        fields = {},
        state = {}
    }

    resetStats(node.state)
    node.app = ctx.app

    function node:buildForm(app)
        local fields = {}
        local function addStat(label, key, initial)
            local line = form.addLine(label)
            fields[key] = form.addStaticText(line, valuePos(app), initial or "-")
        end

        addStat("Transport", "transport", "-")
        addStat("Total Queries", "total", "0")
        addStat("Successful Queries", "success", "0")
        addStat("Retries", "retries", "0")
        addStat("Timeouts", "timeouts", "0")
        addStat("Other Errors", "errors", "0")
        addStat("Min Query Time", "minTime", "-")
        addStat("Max Query Time", "maxTime", "-")
        addStat("Avg Query Time", "avgTime", "-")

        self.fields = fields
        refreshFields(self)
    end

    function node:startTest(seconds)
        if self.state.active == true then
            return true
        end

        resetStats(self.state)
        self.state.active = true
        self.state.duration = tonumber(seconds) or 30
        self.state.startedAt = os.clock()
        self.state.endsAt = self.state.startedAt + self.state.duration
        self.state.status = "Starting"
        self.state.lastTransport = self.app.framework.session:get("connectionTransport", "disconnected")

        self.app.ui.showLoader({
            kind = "progress",
            title = "MSP Speed",
            message = "Testing MSP throughput.",
            detail = "Preparing request loop.",
            speed = self.app.loaderSpeed.FAST,
            closeWhenIdle = false,
            fallbackCloseAfter = math.max(self.state.duration + 2, 5),
            modal = true,
            progressValue = 0
        })

        refreshFields(self)
        self.app:_invalidateForm()
        return true
    end

    function node:tool()
        return openDurationDialog(self)
    end

    function node:reload(app)
        local wasActive = self.state.active == true

        if wasActive then
            finishTest(self, "Reset")
        end
        resetStats(self.state)
        self.state.lastTransport = app.framework.session:get("connectionTransport", "disconnected")
        refreshFields(self)
        app:_invalidateForm()
        return true
    end

    function node:wakeup(app)
        local now = os.clock()

        self.state.lastTransport = app.framework.session:get("connectionTransport", "disconnected")

        if self.state.active ~= true then
            refreshFields(self)
            return
        end

        if now >= (self.state.endsAt or now) and self.state.pending ~= true and queueIsIdle(app.framework:getTask("msp")) then
            finishTest(self, "Complete")
            return
        end

        if self.state.pending ~= true and now < (self.state.endsAt or now) and queueIsIdle(app.framework:getTask("msp")) then
            startNextQuery(self)
        end

        if now >= (self.state.endsAt or now) and self.state.pending ~= true then
            finishTest(self, "Complete")
            return
        end

        updateLoaderDetail(self)
        refreshFields(self)
    end

    function node:close()
        if self.state.active == true then
            finishTest(self, "Stopped")
        else
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
