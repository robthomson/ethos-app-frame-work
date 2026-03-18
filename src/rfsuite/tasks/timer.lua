--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = require("lib.ini")
local utils = require("lib.utils")

local TimerTask = {}

local FLIGHT_COUNT_THRESHOLD = 25
local STATS_SYNC_DELAY = 1.0

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function toNumber(value, default)
    local number = tonumber(value)

    if number == nil then
        return default
    end

    return number
end

function TimerTask:_ensureTimerState()
    local session = self.framework.session
    local timerState = session:get("timer", nil)
    local modelPreferences = session:get("modelPreferences", nil)
    local general = modelPreferences and modelPreferences.general or nil
    local created = false

    if type(timerState) ~= "table" then
        timerState = {}
        created = true
    end

    if timerState.baseLifetime == nil then
        timerState.baseLifetime = toNumber(general and general.totalflighttime, 0)
    end
    if timerState.session == nil then
        timerState.session = 0
    end
    if timerState.start == nil then
        timerState.start = nil
    end
    if timerState.lifetime == nil then
        timerState.lifetime = timerState.baseLifetime or 0
    end
    if timerState.live == nil then
        timerState.live = timerState.session or 0
    end

    if created then
        session:set("timer", timerState)
    end

    return timerState
end

function TimerTask:_saveToEeprom()
    local mspTask = self.framework:getTask("msp")
    local queued
    local reason

    if not mspTask or type(mspTask.queueCommand) ~= "function" then
        return
    end

    queued, reason = mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            self.framework.log:info("EEPROM write command sent")
        end
    })

    if queued ~= true then
        self.framework.log:info("EEPROM enqueue rejected (%s)", tostring(reason or "queue_rejected"))
    end
end

function TimerTask:_writeStats()
    local session = self.framework.session
    local prefs = session:get("modelPreferences", nil)
    local mspTask = self.framework:getTask("msp")
    local api
    local loadErr
    local totalflighttime
    local flightcount
    local key

    if utils.apiVersionCompare(">=", {12, 0, 9}) ~= true or not prefs or not mspTask or not mspTask.api then
        return
    end

    api, loadErr = mspTask.api.load("FLIGHT_STATS")
    if not api then
        self.framework.log:warn("[timer] FLIGHT_STATS load failed: %s", tostring(loadErr or "load_failed"))
        return
    end

    totalflighttime = toNumber(ini.getvalue(prefs, "general", "totalflighttime"), 0)
    flightcount = toNumber(ini.getvalue(prefs, "general", "flightcount"), 0)

    api.setRebuildOnWrite(true)

    for key, value in pairs(self.readData or {}) do
        api.setValue(key, value)
    end

    api.setValue("totalflighttime", totalflighttime)
    api.setValue("flightcount", flightcount)
    api.setCompleteHandler(function()
        self.framework.log:info("Synchronized flight stats to FBL")
        self:_saveToEeprom()
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.framework.log:warn("[timer] FLIGHT_STATS write failed: %s", tostring(errorMessage or "write_failed"))
    end)
    api.setUUID("timer-flight-stats-write")
    api.setTimeout(3.0)
    api.write()
end

function TimerTask:_syncStatsToFbl()
    local mspTask = self.framework:getTask("msp")
    local api
    local loadErr

    if utils.apiVersionCompare(">=", {12, 0, 9}) ~= true or not mspTask or not mspTask.api then
        return
    end

    api, loadErr = mspTask.api.load("FLIGHT_STATS")
    if not api then
        self.framework.log:warn("[timer] FLIGHT_STATS load failed: %s", tostring(loadErr or "load_failed"))
        return
    end

    api.setCompleteHandler(function()
        local data = api.data and api.data() or nil
        self.readData = copyTable(data and data.parsed or {})
        self:_writeStats()
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.framework.log:warn("[timer] FLIGHT_STATS read failed: %s", tostring(errorMessage or "read_failed"))
    end)
    api.setUUID("timer-flight-stats-read")
    api.setTimeout(3.0)
    api.read()
end

function TimerTask:_saveLocalTimers()
    local session = self.framework.session
    local prefs = session:get("modelPreferences", nil)
    local prefsFile = session:get("modelPreferencesFile", nil)
    local timerState = self:_ensureTimerState()

    if not prefsFile then
        self.framework.log:info("No model preferences file set, cannot save flight timers")
        return
    end

    if prefs then
        ini.setvalue(prefs, "general", "totalflighttime", timerState.baseLifetime or 0)
        ini.setvalue(prefs, "general", "lastflighttime", timerState.session or 0)
        ini.save_ini_file(prefsFile, prefs)
    end

    self.framework.log:info("Saving flight timers to INI: %s", prefsFile)
    self.pendingStatsSync = true
    self.pendingStatsSyncAt = os.clock() + STATS_SYNC_DELAY
end

function TimerTask:_finalizeFlightSegment(now)
    local session = self.framework.session
    local timerState = self:_ensureTimerState()
    local modelPreferences = session:get("modelPreferences", nil)
    local general = modelPreferences and modelPreferences.general or nil
    local segment

    if not timerState.start then
        return
    end

    segment = math.max(0, now - timerState.start)
    timerState.session = (timerState.session or 0) + segment
    timerState.start = nil

    if timerState.baseLifetime == nil then
        timerState.baseLifetime = toNumber(general and general.totalflighttime, 0)
    end

    timerState.baseLifetime = (timerState.baseLifetime or 0) + segment
    timerState.lifetime = timerState.baseLifetime

    if modelPreferences then
        ini.setvalue(modelPreferences, "general", "totalflighttime", timerState.baseLifetime)
    end

    self:_saveLocalTimers()
end

function TimerTask:_maybeCountFlight()
    local session = self.framework.session
    local timerState = self:_ensureTimerState()
    local prefs = session:get("modelPreferences", nil)
    local prefsFile = session:get("modelPreferencesFile", nil)
    local count

    if timerState.live < FLIGHT_COUNT_THRESHOLD or session:get("flightCounted", false) == true then
        return
    end

    session:set("flightCounted", true)

    if prefs and ini.section_exists(prefs, "general") then
        count = toNumber(ini.getvalue(prefs, "general", "flightcount"), 0)
        ini.setvalue(prefs, "general", "flightcount", count + 1)
        if prefsFile then
            ini.save_ini_file(prefsFile, prefs)
        end
    end
end

function TimerTask:_handlePendingStatsSync(now)
    local session = self.framework.session

    if session:get("isArmed", false) == true then
        return
    end

    if self.pendingStatsSync ~= true or (self.pendingStatsSyncAt or 0) > now then
        return
    end

    if session:get("isConnected", false) ~= true or session:get("lifecycleActive", false) == true then
        return
    end

    self.pendingStatsSync = false
    self.pendingStatsSyncAt = 0
    self.framework.log:info("Starting delayed FLIGHT_STATS sync")
    self:_syncStatsToFbl()
end

function TimerTask:init(framework)
    self.framework = framework
    self.pendingStatsSync = false
    self.pendingStatsSyncAt = 0
    self.readData = {}

    framework:on("onconnect", function()
        self.pendingStatsSync = false
        self.pendingStatsSyncAt = 0
        self.readData = {}
    end)
end

function TimerTask:wakeup()
    local now = os.time()
    local session = self.framework.session
    local timerState
    local flightMode
    local currentSegment

    if session:get("lifecycleActive", false) == true then
        return
    end

    timerState = self:_ensureTimerState()
    flightMode = session:get("currentFlightMode", "preflight")

    self:_handlePendingStatsSync(os.clock())

    if flightMode == "inflight" then
        if not timerState.start then
            timerState.start = now
        end

        currentSegment = math.max(0, now - timerState.start)
        timerState.live = (timerState.session or 0) + currentSegment
        timerState.lifetime = (timerState.baseLifetime or 0) + currentSegment
        self:_maybeCountFlight()
        return
    end

    timerState.live = timerState.session or 0

    if flightMode == "postflight" and timerState.start then
        self:_finalizeFlightSegment(now)
    end
end

return TimerTask
