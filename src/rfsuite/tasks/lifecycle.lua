--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local registry = require("lifecycle.registry")
local defaults = require("lifecycle.defaults")

local LifecycleTask = {}

local EVENT_NAMES = {
    "onconnect",
    "ondisconnect",
    "ontransportchange"
}

local function queueCount(queue)
    return queue.last - queue.first + 1
end

local function queuePush(queue, item)
    queue.last = queue.last + 1
    queue.items[queue.last] = item
end

local function queuePop(queue)
    local item

    if queue.first > queue.last then
        return nil
    end

    item = queue.items[queue.first]
    queue.items[queue.first] = nil
    queue.first = queue.first + 1

    if queue.first > queue.last then
        queue.first = 1
        queue.last = 0
    end

    return item
end

function LifecycleTask:_emit(eventName, payload)
    self.framework:_emit("lifecycle:" .. eventName, payload)
end

function LifecycleTask:_updateSession(values)
    self.framework.session:setMultiple(values)
end

function LifecycleTask:_snapshotContext(run, hook, now)
    return {
        framework = self.framework,
        session = self.framework.session,
        eventName = run.eventName,
        payload = run.payload,
        hook = hook,
        task = self,
        now = now,
        msp = self.framework:getTask("msp")
    }
end

function LifecycleTask:_finishCurrentRun(now)
    local run = self.currentRun

    if not run then
        return
    end

    self:_updateSession({
        lifecycleActive = false,
        lifecycleEvent = "idle",
        lifecycleHook = "idle",
        lifecyclePendingCount = queueCount(self.pendingRuns),
        lifecycleLastCompletedEvent = run.eventName,
        lifecycleLastCompletedAt = now
    })

    self:_emit("completed", {
        eventName = run.eventName,
        runToken = run.token,
        at = now
    })

    self.currentRun = nil
end

function LifecycleTask:_failHook(run, hook, now, reason)
    self.framework.log:connect(
        "Lifecycle %s/%s failed: %s",
        tostring(run.eventName or "unknown"),
        tostring(hook.name or "unknown"),
        tostring(reason or "failed")
    )

    self:_emit("hookFailed", {
        eventName = run.eventName,
        hookName = hook.name,
        runToken = run.token,
        reason = reason or "failed",
        at = now
    })

    run.index = run.index + 1
    self:_updateSession({
        lifecycleHook = "failed:" .. hook.name,
        lifecyclePendingCount = queueCount(self.pendingRuns)
    })
end

function LifecycleTask:_runHookWakeup(run, hook, now)
    local definition = hook.definition
    local context = self:_snapshotContext(run, hook, now)
    local ok
    local result
    local complete

    if not hook.started then
        hook.started = true
        hook.startedAt = now

        if type(definition) == "table" and type(definition.reset) == "function" then
            pcall(definition.reset, context)
        end

        self:_emit("hookStarted", {
            eventName = run.eventName,
            hookName = hook.name,
            runToken = run.token,
            at = now
        })
    end

    if hook.timeout and (now - hook.startedAt) > hook.timeout then
        self:_failHook(run, hook, now, "timeout")
        return
    end

    if type(definition) == "function" then
        ok, result = pcall(definition, context)
        complete = ok and result ~= false
    elseif type(definition) == "table" and type(definition.run) == "function" then
        ok, result = pcall(definition.run, context)
        complete = ok and result ~= false
    elseif type(definition) == "table" and type(definition.wakeup) == "function" then
        ok, result = pcall(definition.wakeup, context)
        if not ok then
            complete = false
        elseif type(definition.isComplete) == "function" then
            ok, complete = pcall(definition.isComplete, context, result)
        else
            complete = true
        end
    else
        complete = true
        ok = true
    end

    if not ok then
        self:_failHook(run, hook, now, tostring(result))
        return
    end

    if complete then
        self:_emit("hookCompleted", {
            eventName = run.eventName,
            hookName = hook.name,
            runToken = run.token,
            at = now
        })
        run.index = run.index + 1
    end
end

function LifecycleTask:_startNextRun(now)
    local run = queuePop(self.pendingRuns)

    if not run then
        return
    end

    self.currentRun = run
    self:_updateSession({
        lifecycleActive = true,
        lifecycleEvent = run.eventName,
        lifecycleHook = (#run.hooks > 0 and run.hooks[1].name) or "none",
        lifecyclePendingCount = queueCount(self.pendingRuns),
        lifecycleRunToken = run.token,
        lifecycleLastStartedAt = now
    })

    self:_emit("started", {
        eventName = run.eventName,
        runToken = run.token,
        hookCount = #run.hooks,
        at = now
    })
end

function LifecycleTask:_enqueue(eventName, payload)
    local run = {
        eventName = eventName,
        payload = payload or {},
        hooks = registry.list(eventName),
        index = 1,
        token = self.nextRunToken
    }

    self.nextRunToken = self.nextRunToken + 1
    queuePush(self.pendingRuns, run)

    self:_updateSession({
        lifecyclePendingCount = queueCount(self.pendingRuns) + (self.currentRun and 1 or 0),
        lifecycleLastQueuedEvent = eventName
    })
end

function LifecycleTask:init(framework)
    local i

    self.framework = framework
    self.pendingRuns = {
        items = {},
        first = 1,
        last = 0
    }
    self.currentRun = nil
    self.nextRunToken = 1

    defaults.registerAll()

    for i = 1, #EVENT_NAMES do
        local eventName = EVENT_NAMES[i]
        framework:on(eventName, function(payload)
            self:_enqueue(eventName, payload)
        end)
    end

    self:_updateSession({
        lifecycleActive = false,
        lifecycleEvent = "idle",
        lifecycleHook = "idle",
        lifecycleRunToken = 0,
        lifecyclePendingCount = 0,
        lifecycleLastQueuedEvent = "none",
        lifecycleLastCompletedEvent = "none",
        lifecycleLastCompletedAt = 0,
        lifecycleLastStartedAt = 0,
        postConnectComplete = framework.session:get("postConnectComplete", false),
        postConnectTransport = framework.session:get("postConnectTransport", "disconnected"),
        postConnectApiVersion = framework.session:get("postConnectApiVersion", nil),
        postConnectProtocolVersion = framework.session:get("postConnectProtocolVersion", framework.config.mspProtocolVersion or 1),
        postConnectAt = framework.session:get("postConnectAt", 0),
        postConnectToken = framework.session:get("postConnectToken", 0),
        lastTransportChangeAt = framework.session:get("lastTransportChangeAt", 0),
        lastTransportOld = framework.session:get("lastTransportOld", "disconnected"),
        lastTransportNew = framework.session:get("lastTransportNew", "disconnected")
    })
end

function LifecycleTask:wakeup()
    local now = os.clock()
    local run
    local hook

    if not self.currentRun then
        self:_startNextRun(now)
    end

    run = self.currentRun
    if not run then
        self:_updateSession({
            lifecyclePendingCount = queueCount(self.pendingRuns)
        })
        return
    end

    hook = run.hooks[run.index]
    if not hook then
        self:_finishCurrentRun(now)
        return
    end

    self:_updateSession({
        lifecycleActive = true,
        lifecycleEvent = run.eventName,
        lifecycleHook = hook.name,
        lifecyclePendingCount = queueCount(self.pendingRuns)
    })

    self:_runHookWakeup(run, hook, now)
end

function LifecycleTask:close()
    self.pendingRuns = {
        items = {},
        first = 1,
        last = 0
    }
    self.currentRun = nil
end

return LifecycleTask
