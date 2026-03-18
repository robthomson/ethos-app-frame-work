--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = require("lib.ini")

local LoggingTask = {}

local MAX_QUEUE = 200
local FLUSH_QUEUE_SIZE = 20
local DISK_WRITE_INTERVAL = 2.5
local DISK_BUFFER_MAX_BYTES = 4096
local DISK_KEEP_OPEN = true
local LOG_INTERVAL = 1.0

local LOG_TABLE = {
    {name = "voltage"},
    {name = "current"},
    {name = "rpm"},
    {name = "temp_esc"},
    {name = "throttle_percent"}
}

local function safeMkdir(path)
    if os and os.mkdir and path then
        pcall(os.mkdir, path)
    end
end

local function safeClose(fileHandle)
    if fileHandle then
        pcall(function()
            fileHandle:close()
        end)
    end
end

function LoggingTask:_refreshSessionCaches()
    local session = self.framework.session
    local mcuId = session:get("mcu_id", nil)

    if not mcuId or mcuId == "" then
        return false
    end

    if self.cachedMcuId ~= mcuId then
        self.cachedMcuId = mcuId
        self.cachedBaseDir = "LOGS:/rfsuite/telemetry/" .. mcuId
        self.cachedIniPath = self.cachedBaseDir .. "/logs.ini"
        self.cachedFilePath = nil
        self.logDirChecked = false
        self.sourcesCached = false
        self.sensorSources = {}
    end

    return true
end

function LoggingTask:_cacheFilePath()
    if not self.cachedBaseDir or not self.logFileName then
        return nil
    end

    self.cachedFilePath = self.cachedBaseDir .. "/" .. self.logFileName
    return self.cachedFilePath
end

function LoggingTask:_checkLogdirExists()
    if not self.cachedMcuId then
        return
    end

    safeMkdir("LOGS:")
    safeMkdir("LOGS:/rfsuite")
    safeMkdir("LOGS:/rfsuite/telemetry")
    safeMkdir("LOGS:/rfsuite/telemetry/" .. self.cachedMcuId)
end

function LoggingTask:_generateLogFilename()
    local timestamp = os.date("%Y-%m-%d_%H-%M-%S")
    local uniquePart = math.floor(os.clock() * 1000)

    return timestamp .. "_" .. uniquePart .. ".csv"
end

function LoggingTask:_diskClose()
    safeClose(self.diskFH)
    self.diskFH = nil
    self.diskFHPath = nil
end

function LoggingTask:_diskEnsureOpen(path)
    local fileHandle

    if not path or path == "" then
        return nil
    end

    if self.diskFH and self.diskFHPath == path then
        return self.diskFH
    end

    self:_diskClose()
    fileHandle = io.open(path, "a")
    if not fileHandle then
        return nil
    end

    self.diskFH = fileHandle
    self.diskFHPath = path
    return fileHandle
end

function LoggingTask:_dropQueuePrefix(n)
    local total
    local bytes
    local i
    local line

    if n <= 0 then
        return
    end

    total = #self.logQueue
    if n >= total then
        for i = 1, total do
            self.logQueue[i] = nil
        end
        self.logQueueBytes = 0
        return
    end

    table.move(self.logQueue, n + 1, total, 1)
    for i = total - n + 1, total do
        self.logQueue[i] = nil
    end

    bytes = 0
    for i = 1, (total - n) do
        line = self.logQueue[i]
        if line then
            bytes = bytes + #line + 1
        end
    end
    self.logQueueBytes = bytes
end

function LoggingTask:_queueLog(line)
    if not line then
        return
    end

    self.logQueue[#self.logQueue + 1] = line
    self.logQueueBytes = self.logQueueBytes + #line + 1

    if #self.logQueue >= MAX_QUEUE then
        self:_writeLogs(true)
    end
end

function LoggingTask:_writeLogs(forceWrite)
    local filePath
    local maxLines
    local count
    local fileHandle
    local chunk
    local ok

    if #self.logQueue == 0 or not self.logFileName then
        return
    end

    filePath = self.cachedFilePath or self:_cacheFilePath()
    if not filePath then
        return
    end

    maxLines = forceWrite and #self.logQueue or 50
    count = math.min(#self.logQueue, maxLines)
    if count <= 0 then
        return
    end

    if DISK_KEEP_OPEN then
        fileHandle = self:_diskEnsureOpen(filePath)
    else
        fileHandle = io.open(filePath, "a")
    end

    if not fileHandle then
        self:_dropQueuePrefix(count)
        return
    end

    chunk = table.concat(self.logQueue, "\n", 1, count) .. "\n"
    ok = pcall(function()
        fileHandle:write(chunk)
        if fileHandle.flush then
            fileHandle:flush()
        end
    end)

    if not DISK_KEEP_OPEN then
        safeClose(fileHandle)
    end

    if not ok then
        self:_diskClose()
        self:_dropQueuePrefix(count)
        return
    end

    self:_dropQueuePrefix(count)
end

function LoggingTask:_getLogHeader()
    local names = {}
    local index

    for index = 1, #LOG_TABLE do
        names[index] = LOG_TABLE[index].name
    end

    return "time, " .. table.concat(names, ", ")
end

function LoggingTask:_cacheTelemetrySources(telemetry)
    local index

    if self.sourcesCached == true or not telemetry or not telemetry.getSensorSource then
        return
    end

    for index = 1, #LOG_TABLE do
        self.sensorSources[index] = telemetry.getSensorSource(LOG_TABLE[index].name)
    end

    self.sourcesCached = true
end

function LoggingTask:_getLogLine(telemetry)
    local values = self.logLineValues
    local index
    local source
    local value

    for index = 1, #LOG_TABLE do
        source = self.sensorSources[index]
        if not source and telemetry and telemetry.getSensorSource then
            source = telemetry.getSensorSource(LOG_TABLE[index].name)
            self.sensorSources[index] = source
        end

        value = (source and source.value and source:value()) or 0
        values[index] = tostring(value or 0)
    end

    return os.time() .. ", " .. table.concat(values, ", ", 1, #LOG_TABLE)
end

function LoggingTask:_writeModelLogIni()
    local session = self.framework.session
    local iniData

    if not self.cachedIniPath then
        return
    end

    iniData = ini.load_ini_file(self.cachedIniPath) or {}
    iniData.model = iniData.model or {}
    iniData.model.name = session:get("craftName", nil) or (model and model.name and model.name()) or "Unknown"
    ini.save_ini_file(self.cachedIniPath, iniData)
end

function LoggingTask:_startLog()
    local filePath
    local fileHandle

    if self.logFileName then
        return
    end

    self.logFileName = self:_generateLogFilename()
    self:_cacheFilePath()
    self.lastDiskFlush = os.clock()
    self.lastLogAt = 0
    self.sourcesCached = false
    self.sensorSources = {}
    self:_writeModelLogIni()

    filePath = self.cachedFilePath or self:_cacheFilePath()
    if not filePath then
        return
    end

    fileHandle = io.open(filePath, "w")
    if not fileHandle then
        self.logFileName = nil
        self.cachedFilePath = nil
        return
    end

    fileHandle:write(self:_getLogHeader(), "\n")
    safeClose(fileHandle)
    self.logHeaderWritten = true
    self.framework.log:info("Flight log started: %s", tostring(self.logFileName))
end

function LoggingTask:_flushLogs()
    if self.logFileName or self.logHeaderWritten then
        self:_writeLogs(true)
        self.framework.log:info("Flight log stopped: %s", tostring(self.logFileName or "unknown"))
    end

    self.logFileName = nil
    self.logHeaderWritten = false
    self.cachedFilePath = nil
    self.sourcesCached = false
    self.sensorSources = {}
    self.logQueue = {}
    self.logQueueBytes = 0
    self:_diskClose()
end

function LoggingTask:init(framework)
    self.framework = framework
    self.logFileName = nil
    self.logHeaderWritten = false
    self.logQueue = {}
    self.logQueueBytes = 0
    self.logLineValues = {}
    self.sensorSources = {}
    self.sourcesCached = false
    self.logDirChecked = false
    self.lastDiskFlush = os.clock()
    self.lastLogAt = 0
    self.cachedMcuId = nil
    self.cachedBaseDir = nil
    self.cachedIniPath = nil
    self.cachedFilePath = nil
    self.diskFH = nil
    self.diskFHPath = nil

    framework:on("ondisconnect", function()
        self:reset()
    end)
end

function LoggingTask:wakeup()
    local session = self.framework.session
    local telemetry = self.framework:getTask("telemetry")
    local now = os.clock()
    local dueBySize
    local dueByTime

    if not self:_refreshSessionCaches() then
        return
    end

    if not telemetry or not telemetry.active or telemetry.active() ~= true then
        self:_flushLogs()
        return
    end

    if self.logDirChecked ~= true then
        self:_checkLogdirExists()
        self.logDirChecked = true
    end

    if session:get("currentFlightMode", "preflight") ~= "inflight" then
        self:_flushLogs()
        return
    end

    self:_startLog()
    if not self.logFileName then
        return
    end

    self:_cacheTelemetrySources(telemetry)

    if (now - (self.lastLogAt or 0)) >= LOG_INTERVAL then
        self.lastLogAt = now
        self:_queueLog(self:_getLogLine(telemetry))
    end

    dueBySize = (#self.logQueue >= FLUSH_QUEUE_SIZE) or (self.logQueueBytes >= DISK_BUFFER_MAX_BYTES)
    dueByTime = (now - (self.lastDiskFlush or 0)) >= DISK_WRITE_INTERVAL
    if dueBySize or dueByTime then
        self.lastDiskFlush = now
        self:_writeLogs(false)
    end
end

function LoggingTask:reset()
    self:_flushLogs()
    self.lastLogAt = 0
    self.logDirChecked = false
end

function LoggingTask:close()
    self:reset()
    self.framework = nil
end

return LoggingTask
