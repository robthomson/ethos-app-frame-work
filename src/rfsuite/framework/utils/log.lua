--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local log = {}

local os_clock = os.clock
local os_date = os.date
local print_fn = print
local string_format = string.format
local string_gsub = string.gsub
local string_rep = string.rep
local string_sub = string.sub
local table_concat = table.concat

local function newRing(capacity)
    return {
        data = {},
        head = 1,
        tail = 1,
        count = 0,
        capacity = capacity or 64,
        dropped = 0
    }
end

local function ringPush(ring, value)
    ring.data[ring.tail] = value
    ring.tail = (ring.tail % ring.capacity) + 1

    if ring.count < ring.capacity then
        ring.count = ring.count + 1
    else
        ring.head = (ring.head % ring.capacity) + 1
        ring.dropped = ring.dropped + 1
    end
end

local function ringPop(ring)
    local value

    if ring.count == 0 then
        return nil
    end

    value = ring.data[ring.head]
    ring.data[ring.head] = nil
    ring.head = (ring.head % ring.capacity) + 1
    ring.count = ring.count - 1
    return value
end

local function ringItems(ring)
    local out = {}
    local index = ring.head
    local i

    for i = 1, ring.count do
        out[#out + 1] = ring.data[index]
        index = (index % ring.capacity) + 1
    end

    return out
end

local function ringReset(ring)
    ring.data = {}
    ring.head = 1
    ring.tail = 1
    ring.count = 0
    ring.dropped = 0
end

local function ringTakeDropped(ring)
    local value = ring.dropped
    ring.dropped = 0
    return value
end

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function splitLine(message, maxLength, prefix)
    local lines = {}
    local paddedPrefix = (#prefix > 0) and string_rep(" ", #prefix) or ""
    local remaining = message

    if #remaining <= maxLength then
        return {remaining}
    end

    while #remaining > maxLength do
        lines[#lines + 1] = string_sub(remaining, 1, maxLength)
        remaining = paddedPrefix .. string_sub(remaining, maxLength + 1)
    end

    if #remaining > 0 then
        lines[#lines + 1] = remaining
    end

    return lines
end

local function stripLeadingTimestamp(line)
    if type(line) ~= "string" then
        return line
    end

    return (string_gsub(line, "^%b[]%s*", ""))
end

log.LEVELS = {
    debug = 0,
    info = 1,
    warn = 2,
    error = 3,
    off = 4
}

log._initialized = false
log._config = {
    enabled = true,
    minLevel = "info",
    printInterval = 0.25,
    maxLineLength = 120,
    consoleDrainMax = 10,
    connectDrainMax = 6,
    consoleCapacity = 200,
    connectCapacity = 80,
    connectHistoryCapacity = 160,
    historyCapacity = 240,
    prefix = nil
}

log._consoleQueue = newRing(log._config.consoleCapacity)
log._connectQueue = newRing(log._config.connectCapacity)
log._connectHistory = newRing(log._config.connectHistoryCapacity)
log._history = newRing(log._config.historyCapacity)
log._lastConsoleAt = 0
log._lastConnectAt = 0

local function getLevelValue(levelName)
    return log.LEVELS[levelName or "info"] or log.LEVELS.info
end

local function getConfiguredPrefix()
    local prefix = log._config.prefix

    if type(prefix) == "function" then
        return prefix() or ""
    end

    return prefix or string_format("[%.2f] ", os_clock())
end

local function allowLevel(levelName)
    local configured = getLevelValue(log._config.minLevel)
    local current = getLevelValue(levelName)

    if configured == log.LEVELS.off then
        return false
    end

    return current >= configured
end

local function formatMessage(message, ...)
    if select("#", ...) > 0 then
        return string_format(tostring(message), ...)
    end

    return tostring(message)
end

local function normalizeEntry(entry, fallbackLevel, ...)
    local entryType = type(entry)
    local normalized

    if entryType == "table" then
        normalized = copyTable(entry)
        normalized.message = normalized.message or normalized.msg or ""
        if select("#", ...) > 0 then
            normalized.message = formatMessage(normalized.message, ...)
        else
            normalized.message = tostring(normalized.message)
        end
    else
        normalized = {
            message = formatMessage(entry, ...),
            level = fallbackLevel
        }
    end

    normalized.level = normalized.level or fallbackLevel or "info"
    normalized.destination = normalized.destination or normalized.dest or ((normalized.level == "connect") and "connect" or "console")
    normalized.prefix = normalized.prefix or getConfiguredPrefix()
    normalized.createdAt = normalized.createdAt or os_clock()

    if normalized.destination == "connect" and normalized.level == "connect" then
        normalized.level = "info"
    end

    return normalized
end

local function renderLine(entry)
    local levelName = string.upper(entry.level or "info")
    return string_format("%s[%s] %s", entry.prefix or "", levelName, entry.message or "")
end

local function emitDirect(entry)
    local maxLength = log._config.maxLineLength or 120
    local lines = splitLine(renderLine(entry), maxLength, entry.prefix or "")
    local i

    for i = 1, #lines do
        print_fn(lines[i])
    end
end

function log:init(options)
    local config = copyTable(self._config)
    local developer = options and options.developer or {}

    if options then
        if options.enabled ~= nil then
            config.enabled = options.enabled
        end
        if options.minLevel ~= nil then
            config.minLevel = options.minLevel
        elseif developer.loglevel ~= nil then
            config.minLevel = developer.loglevel
        end
        if options.printInterval ~= nil then
            config.printInterval = options.printInterval
        end
        if options.maxLineLength ~= nil then
            config.maxLineLength = options.maxLineLength
        end
        if options.consoleDrainMax ~= nil then
            config.consoleDrainMax = options.consoleDrainMax
        end
        if options.connectDrainMax ~= nil then
            config.connectDrainMax = options.connectDrainMax
        end
        if options.consoleCapacity ~= nil then
            config.consoleCapacity = options.consoleCapacity
        end
        if options.connectCapacity ~= nil then
            config.connectCapacity = options.connectCapacity
        end
        if options.connectHistoryCapacity ~= nil then
            config.connectHistoryCapacity = options.connectHistoryCapacity
        end
        if options.historyCapacity ~= nil then
            config.historyCapacity = options.historyCapacity
        end
        if options.prefix ~= nil then
            config.prefix = options.prefix
        end
    end

    self._config = config
    self._consoleQueue = newRing(config.consoleCapacity)
    self._connectQueue = newRing(config.connectCapacity)
    self._connectHistory = newRing(config.connectHistoryCapacity)
    self._history = newRing(config.historyCapacity)
    self._lastConsoleAt = 0
    self._lastConnectAt = 0
    self._initialized = true
    return self
end

function log:setLevel(level)
    if type(level) == "string" then
        self._config.minLevel = level
    else
        local name
        for key, value in pairs(self.LEVELS) do
            if value == level then
                name = key
                break
            end
        end
        self._config.minLevel = name or "info"
    end
end

function log:add(entry, fallbackLevel, ...)
    local normalized = normalizeEntry(entry, fallbackLevel, ...)
    local destination = normalized.destination

    if not self._config.enabled then
        return false
    end

    if not self._initialized then
        if destination == "connect" or allowLevel(normalized.level) then
            ringPush(self._history, normalized)
            emitDirect(normalized)
        end
        return true
    end

    if destination == "connect" then
        ringPush(self._connectQueue, normalized)
        ringPush(self._connectHistory, normalized)
        ringPush(self._history, normalized)
        return true
    end

    if not allowLevel(normalized.level) then
        return false
    end

    ringPush(self._consoleQueue, normalized)
    ringPush(self._history, normalized)
    return true
end

function log:debug(message, ...)
    return self:add(message, "debug", ...)
end

function log:info(message, ...)
    return self:add(message, "info", ...)
end

function log:warn(message, ...)
    return self:add(message, "warn", ...)
end

function log:error(message, ...)
    return self:add(message, "error", ...)
end

function log:connect(message, ...)
    return self:add({
        destination = "connect",
        level = "info",
        message = formatMessage(message, ...)
    })
end

function log:console(message, ...)
    return self:add({
        destination = "console",
        level = "info",
        message = formatMessage(message, ...)
    })
end

function log:_drainQueue(queue, maxLines)
    local lines = 0
    local maxLength = self._config.maxLineLength or 120

    while lines < maxLines do
        local entry = ringPop(queue)
        local parts
        local i

        if not entry then
            break
        end

        parts = splitLine(renderLine(entry), maxLength, entry.prefix or "")
        for i = 1, #parts do
            print_fn(parts[i])
        end
        lines = lines + 1
    end
end

function log:process(force)
    local now = os_clock()
    local interval = self._config.printInterval or 0.25

    if not self._initialized or not self._config.enabled then
        return
    end

    if force or ((now - self._lastConsoleAt) >= interval and self._consoleQueue.count > 0) then
        self._lastConsoleAt = now

        local dropped = ringTakeDropped(self._consoleQueue)
        if dropped > 0 then
            emitDirect({
                prefix = getConfiguredPrefix(),
                level = "warn",
                message = "[logger] dropped " .. tostring(dropped) .. " console lines"
            })
        end

        self:_drainQueue(self._consoleQueue, self._config.consoleDrainMax or 10)
    end

    if force or ((now - self._lastConnectAt) >= interval and self._connectQueue.count > 0) then
        self._lastConnectAt = now

        local dropped = ringTakeDropped(self._connectQueue)
        if dropped > 0 then
            emitDirect({
                prefix = getConfiguredPrefix(),
                level = "warn",
                message = "[logger] dropped " .. tostring(dropped) .. " connect lines"
            })
        end

        self:_drainQueue(self._connectQueue, self._config.connectDrainMax or 6)
    end
end

function log:getConnectLines(maxLines, options)
    local entries = ringItems(self._connectHistory)
    local lines = {}
    local opts = options or {}
    local limit = tonumber(maxLines) or 8
    local i

    for i = #entries, 1, -1 do
        local entry = entries[i]
        local line = renderLine(entry)

        if opts.noTimestamp then
            line = stripLeadingTimestamp(line)
        end

        lines[#lines + 1] = line
        if #lines >= limit then
            break
        end
    end

    local out = {}
    for i = #lines, 1, -1 do
        out[#out + 1] = lines[i]
    end

    return out
end

function log:getRecentLines(maxLines, options, out)
    local opts = options or {}
    local ring = self._history
    local limit = tonumber(maxLines) or 8
    local lines = out or {}
    local count = 0
    local index
    local i

    for i = 1, #lines do
        lines[i] = nil
    end

    if not ring or ring.count <= 0 or limit <= 0 then
        return lines
    end

    index = ring.tail - 1
    if index < 1 then
        index = ring.capacity
    end

    for i = 1, ring.count do
        local entry = ring.data[index]
        local line
        local destinationOk = true

        if entry then
            if opts.destination then
                destinationOk = entry.destination == opts.destination
            elseif opts.destinations and opts.destinations[entry.destination] ~= true then
                destinationOk = false
            end

            if destinationOk then
                line = renderLine(entry)
                if opts.noTimestamp then
                    line = stripLeadingTimestamp(line)
                end
                count = count + 1
                lines[count] = line
                if count >= limit then
                    break
                end
            end
        end

        index = index - 1
        if index < 1 then
            index = ring.capacity
        end
    end

    for i = 1, math.floor(count / 2) do
        local j = count - i + 1
        lines[i], lines[j] = lines[j], lines[i]
    end

    for i = count + 1, #lines do
        lines[i] = nil
    end

    return lines
end

function log:getStats()
    return {
        consoleDepth = self._consoleQueue.count,
        connectDepth = self._connectQueue.count,
        connectHistoryDepth = self._connectHistory.count,
        historyDepth = self._history.count,
        consoleDropped = self._consoleQueue.dropped,
        connectDropped = self._connectQueue.dropped,
        minLevel = self._config.minLevel,
        enabled = self._config.enabled
    }
end

function log:flush()
    self:process(true)
end

function log:reset()
    ringReset(self._consoleQueue)
    ringReset(self._connectQueue)
    ringReset(self._connectHistory)
    ringReset(self._history)
    self._lastConsoleAt = 0
    self._lastConnectAt = 0
end

function log:close()
    self:flush()
end

return log
