--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local queue = {}

local function isSimulation()
    return system and system.getVersion and system.getVersion().simulation == true
end

local function resolveSimulatorResponse(message)
    if not message then
        return nil
    end

    if message.simulatorResponse == nil then
        return nil
    end

    if type(message.simulatorResponse) == "function" then
        return message.simulatorResponse(message)
    end

    return message.simulatorResponse
end

function queue.new(options)
    local opts = options or {}

    return setmetatable({
        items = {},
        first = 1,
        last = 0,
        current = nil,
        retryCount = 0,
        firstSentAt = nil,
        lastSentAt = nil,
        nextMessageAt = 0,
        maxRetries = opts.maxRetries or 5,
        timeout = opts.timeout or 2.0,
        retryBackoff = opts.retryBackoff or 0.5,
        interMessageDelay = opts.interMessageDelay or 0.05,
        mspInterval = opts.mspInterval or 0.15,
        maxDepth = opts.maxDepth or 20,
        requeueExpired = opts.requeueExpired ~= false,
        maxExpireCount = opts.maxExpireCount or 2,
        activityHandler = opts.activityHandler,
        logHandler = opts.logHandler
    }, {__index = queue})
end

function queue:setActivityHandler(fn)
    self.activityHandler = fn
end

function queue:setLogHandler(fn)
    self.logHandler = fn
end

function queue:_notifyActivity(now)
    local handler = self.activityHandler

    if type(handler) ~= "function" then
        return
    end

    pcall(handler, self, now, self.current, self:queueCount() + (self.current and 1 or 0))
end

function queue:_notifyLog(kind, message, payload, extra)
    local handler = self.logHandler

    if type(handler) ~= "function" then
        return
    end

    pcall(handler, self, kind, message, payload, extra)
end

function queue:configure(protocol)
    if not protocol then
        return
    end

    self.maxRetries = protocol.maxRetries or self.maxRetries
    self.timeout = protocol.timeout or self.timeout
    self.retryBackoff = protocol.retryBackoff or self.retryBackoff
    self.interMessageDelay = protocol.interMessageDelay or self.interMessageDelay
    self.mspInterval = protocol.mspInterval or self.mspInterval
    self.maxDepth = protocol.maxQueueDepth or self.maxDepth
    if protocol.requeueExpired ~= nil then
        self.requeueExpired = protocol.requeueExpired == true
    end
    if protocol.maxExpireCount ~= nil then
        self.maxExpireCount = protocol.maxExpireCount
    end
end

function queue:queueCount()
    return self.last - self.first + 1
end

function queue:isProcessed()
    return self.current == nil and self:queueCount() <= 0
end

function queue:clear()
    self.items = {}
    self.first = 1
    self.last = 0
    self.current = nil
    self.retryCount = 0
    self.firstSentAt = nil
    self.lastSentAt = nil
    self.nextMessageAt = 0
end

function queue:add(message)
    local pending = self:queueCount() + (self.current and 1 or 0)
    if pending >= self.maxDepth then
        return false, "busy", nil, pending
    end

    self.last = self.last + 1
    self.items[self.last] = message

    return true, "queued", self.last, pending + 1
end

function queue:_pop()
    local item

    if self.first > self.last then
        return nil
    end

    item = self.items[self.first]
    self.items[self.first] = nil
    self.first = self.first + 1

    if self.first > self.last then
        self.first = 1
        self.last = 0
    end

    return item
end

function queue:_finish(now)
    self.current = nil
    self.retryCount = 0
    self.firstSentAt = nil
    self.lastSentAt = nil
    self.nextMessageAt = now + self.interMessageDelay
end

function queue:_requeueExpiredMessage(now, reason, transport, codec)
    local message = self.current

    if not message then
        self:_finish(now)
        return false
    end

    if codec and codec.clear then
        codec:clear()
    end
    if transport and transport.reset then
        transport:reset()
    end

    message._expireCount = (message._expireCount or 0) + 1
    message._lastExpireReason = reason

    if message.expireHandler then
        pcall(message.expireHandler, message, reason, message._expireCount, self.maxExpireCount or 0)
    end

    if self.requeueExpired and message._expireCount <= (self.maxExpireCount or 0) then
        self.last = self.last + 1
        self.items[self.last] = message
        self:_finish(now)
        return true
    end

    if message.errorHandler then
        pcall(message.errorHandler, message, reason)
    end
    self:_finish(now)
    return false
end

function queue:process(transport, protocol, codec, now)
    local message
    local command
    local buffer
    local errorFlag
    local simulatorResponse
    local timeout
    local intervalOk
    local backoffOk
    local sendOk

    if not transport or not protocol or not codec then
        return false
    end

    if self.current or self:queueCount() > 0 then
        self:_notifyActivity(now)
    end

    if not self.current then
        if now < self.nextMessageAt then
            return false
        end

        self.current = self:_pop()
        self.retryCount = 0
        self.firstSentAt = nil
        self.lastSentAt = nil
        if not self.current then
            return false
        end
    end

    message = self.current
    timeout = message.timeout or self.timeout

    if isSimulation() then
        simulatorResponse = resolveSimulatorResponse(message)

        if simulatorResponse ~= nil then
            if message.processReply then
                pcall(message.processReply, message, simulatorResponse, nil)
            end
            self:_finish(now)
            return true
        end
    end

    intervalOk = (not self.lastSentAt) or ((now - self.lastSentAt) >= self.mspInterval)
    backoffOk = (self.retryCount == 0) or ((now - self.lastSentAt) >= self.retryBackoff)

    if self.retryCount <= self.maxRetries and intervalOk and backoffOk then
        sendOk = codec:sendRequest(message.command, message.payload or {})
        if sendOk then
            self.retryCount = self.retryCount + 1
            self.lastSentAt = now
            self.firstSentAt = self.firstSentAt or now
            if self.retryCount == 1 then
                self:_notifyLog("tx", message, message.payload or {}, nil)
            end
        end
    end

    codec:processTx(transport, protocol)
    command, buffer, errorFlag = codec:pollReply(transport, protocol)

    if command and command == message.command then
        if message.processReply then
            pcall(message.processReply, message, buffer, errorFlag)
        end
        self:_notifyLog("rx", message, buffer, errorFlag)
        self:_finish(now)
        return true
    end

    if self.firstSentAt and (now - self.firstSentAt) > timeout then
        self:_notifyLog("timeout", message, nil, "timeout")
        self:_requeueExpiredMessage(now, "timeout", transport, codec)
        return true
    end

    if self.retryCount > self.maxRetries then
        self:_notifyLog("timeout", message, nil, "max_retries")
        self:_requeueExpiredMessage(now, "max_retries", transport, codec)
        return true
    end

    return true
end

return queue
