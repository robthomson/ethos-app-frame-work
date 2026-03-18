--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local AudioLib = require("lib.audio")

local AudioTask = {}

local SPEAK_WAV_MS = 450
local SPEAK_NUM_MS = 600
local HAPTIC_MS = 250
local INIT_GUARD_SECONDS = 5.0

local ARM_FILES = {
    [0] = "disarmed.wav",
    [1] = "armed.wav",
    [2] = "disarmed.wav",
    [3] = "armed.wav"
}

local GOVERNOR_FILES = {
    [0] = "off.wav",
    [1] = "idle.wav",
    [2] = "spoolup.wav",
    [3] = "recovery.wav",
    [4] = "active.wav",
    [5] = "thr-off.wav",
    [6] = "lost-hs.wav",
    [7] = "autorot.wav",
    [8] = "bailout.wav",
    [100] = "disabled.wav",
    [101] = "disarmed.wav"
}

local ADJ_WAVS = {
    [5] = {"pitch", "rate"},
    [6] = {"roll", "rate"},
    [7] = {"yaw", "rate"},
    [8] = {"pitch", "rc", "rate"},
    [9] = {"roll", "rc", "rate"},
    [10] = {"yaw", "rc", "rate"},
    [11] = {"pitch", "rc", "expo"},
    [12] = {"roll", "rc", "expo"},
    [13] = {"yaw", "rc", "expo"},
    [14] = {"pitch", "p", "gain"},
    [15] = {"pitch", "i", "gain"},
    [16] = {"pitch", "d", "gain"},
    [17] = {"pitch", "f", "gain"},
    [18] = {"roll", "p", "gain"},
    [19] = {"roll", "i", "gain"},
    [20] = {"roll", "d", "gain"},
    [21] = {"roll", "f", "gain"},
    [22] = {"yaw", "p", "gain"},
    [23] = {"yaw", "i", "gain"},
    [24] = {"yaw", "d", "gain"},
    [25] = {"yaw", "f", "gain"},
    [26] = {"yaw", "cw", "gain"},
    [27] = {"yaw", "ccw", "gain"},
    [28] = {"yaw", "cyclic", "ff"},
    [29] = {"yaw", "collective", "ff"},
    [30] = {"yaw", "collective", "dyn"},
    [31] = {"yaw", "collective", "decay"},
    [32] = {"pitch", "collective", "ff"},
    [33] = {"pitch", "gyro", "cutoff"},
    [34] = {"roll", "gyro", "cutoff"},
    [35] = {"yaw", "gyro", "cutoff"},
    [36] = {"pitch", "dterm", "cutoff"},
    [37] = {"roll", "dterm", "cutoff"},
    [38] = {"yaw", "dterm", "cutoff"},
    [39] = {"rescue", "climb", "collective"},
    [40] = {"rescue", "hover", "collective"},
    [41] = {"rescue", "hover", "alt"},
    [42] = {"rescue", "alt", "p", "gain"},
    [43] = {"rescue", "alt", "i", "gain"},
    [44] = {"rescue", "alt", "d", "gain"},
    [45] = {"angle", "level", "gain"},
    [46] = {"horizon", "level", "gain"},
    [47] = {"acro", "gain"},
    [48] = {"gov", "gain"},
    [49] = {"gov", "p", "gain"},
    [50] = {"gov", "i", "gain"},
    [51] = {"gov", "d", "gain"},
    [52] = {"gov", "f", "gain"},
    [53] = {"gov", "tta", "gain"},
    [54] = {"gov", "cyclic", "ff"},
    [55] = {"gov", "collective", "ff"},
    [56] = {"pitch", "b", "gain"},
    [57] = {"roll", "b", "gain"},
    [58] = {"yaw", "b", "gain"},
    [59] = {"pitch", "o", "gain"},
    [60] = {"roll", "o", "gain"},
    [61] = {"crossc", "gain"},
    [62] = {"crossc", "ratio"},
    [63] = {"crossc", "cutoff"},
    [64] = {"acc", "pitch", "trim"},
    [65] = {"acc", "roll", "trim"},
    [66] = {"yaw", "inertia", "precomp", "gain"},
    [67] = {"yaw", "inertia", "precomp", "cutoff"},
    [68] = {"pitch", "setpoint", "boost", "gain"},
    [69] = {"roll", "setpoint", "boost", "gain"},
    [70] = {"yaw", "setpoint", "boost", "gain"},
    [71] = {"collective", "setpoint", "boost", "gain"},
    [72] = {"yaw", "dyn", "ceiling", "gain"},
    [73] = {"yaw", "dyn", "deadband", "gain"},
    [74] = {"yaw", "dyn", "deadband", "filter"},
    [75] = {"yaw", "precomp", "cutoff"},
    [76] = {"gov", "idle", "throttle"},
    [77] = {"gov", "auto", "throttle"},
    [78] = {"gov", "max", "throttle"},
    [79] = {"gov", "min", "throttle"},
    [80] = {"gov", "headspeed"},
    [81] = {"gov", "yaw", "ff"},
    [82] = {"battery", "profile"}
}

local DEFAULT_EVENT_PREFS = {
    armflags = true,
    governor = true,
    voltage = true,
    pid_profile = true,
    rate_profile = true,
    temp_esc = false,
    escalertvalue = 90,
    adj_f = true,
    adj_v = true,
    smartfuel = true,
    smartfuelcallout = 0,
    smartfuelrepeats = 1,
    smartfuelhaptic = false,
    battery_profile = true,
    otherModelAnnounce = false
}

local DEFAULT_TIMER_PREFS = {
    timeraudioenable = false,
    elapsedalertmode = 0,
    prealerton = false,
    prealertperiod = 30,
    prealertinterval = 10,
    postalerton = false,
    postalertperiod = 60,
    postalertinterval = 10
}

local function clamp(value, minValue, maxValue)
    if value < minValue then
        return minValue
    end
    if value > maxValue then
        return maxValue
    end
    return value
end

local function buildSmartfuelThresholds(selection)
    local thresholds = {}
    local value

    if selection == 0 then
        return {100, 10}
    end
    if selection == 10 then
        for value = 100, 10, -10 do
            thresholds[#thresholds + 1] = value
        end
        return thresholds
    end
    if selection == 20 then
        for value = 100, 20, -20 do
            thresholds[#thresholds + 1] = value
        end
        thresholds[#thresholds + 1] = 10
        return thresholds
    end
    if selection == 25 then
        return {100, 75, 50, 25, 10}
    end
    if selection == 50 then
        return {100, 50, 10}
    end
    if selection == 5 then
        return {50, 5}
    end
    if type(selection) == "number" and selection > 0 then
        return {selection}
    end

    return {100, 10}
end

local function normalizeBatteryProfileIndex(value)
    local n = tonumber(value)

    if not n then
        return nil
    end

    n = math.floor(n)
    if n >= 1 and n <= 6 then
        return n - 1
    end
    if n >= 0 and n <= 5 then
        return n
    end

    return nil
end

local function resolveBatteryCapacityForProfile(session, profileValue)
    local batteryConfig = session and session:get("batteryConfig", nil) or nil
    local profiles
    local index
    local capacity

    if type(batteryConfig) ~= "table" then
        return nil
    end

    profiles = batteryConfig.profiles
    index = normalizeBatteryProfileIndex(profileValue)

    if index ~= nil and type(profiles) == "table" then
        capacity = tonumber(profiles[index])
        if capacity == nil then
            capacity = tonumber(profiles[index + 1])
        end
        if capacity and capacity > 0 then
            return capacity
        end
    end

    capacity = tonumber(batteryConfig.batteryCapacity)
    if capacity and capacity > 0 then
        return capacity
    end

    return nil
end

function AudioTask:_migrateLegacyAudioDefaults()
    local generalPrefs = self.framework.preferences:section("general", {})
    local eventsPrefs
    local saveOk
    local saveErr

    if tonumber(generalPrefs.audioDefaultsVersion) and tonumber(generalPrefs.audioDefaultsVersion) >= 2 then
        return
    end

    eventsPrefs = self:_eventsPrefs()
    eventsPrefs.armflags = true
    eventsPrefs.governor = true
    eventsPrefs.voltage = true
    eventsPrefs.pid_profile = true
    eventsPrefs.rate_profile = true
    eventsPrefs.smartfuel = true
    eventsPrefs.smartfuelcallout = 0
    eventsPrefs.battery_profile = true
    eventsPrefs.adj_f = true
    eventsPrefs.adj_v = true

    generalPrefs.audioDefaultsVersion = 2
    saveOk, saveErr = self.framework.preferences:save()
    if saveOk ~= true then
        self.framework.log:warn("[audio] preferences save failed after migration: %s", tostring(saveErr or "save_failed"))
    end
end

function AudioTask:_eventsPrefs()
    return self.framework.preferences:section("events", DEFAULT_EVENT_PREFS)
end

function AudioTask:_timerPrefs()
    return self.framework.preferences:section("timer", DEFAULT_TIMER_PREFS)
end

function AudioTask:_canSpeak(now)
    return now >= (self.speakingUntil or 0)
end

function AudioTask:_reserveSpeech(now, seconds)
    self.speakingUntil = math.max(self.speakingUntil or 0, now) + (seconds or 0)
end

function AudioTask:_playPackageFiles(pkg, files, now)
    local index
    local resolved

    if type(files) ~= "table" or #files == 0 or not self:_canSpeak(now) then
        return false
    end

    resolved = AudioLib.resolvePackageFiles(pkg, files)
    if #resolved == 0 then
        return false
    end

    for index = 1, #resolved do
        AudioLib.playResolved(resolved[index])
    end

    self:_reserveSpeech(now, (#resolved * SPEAK_WAV_MS) / 1000.0)
    return true
end

function AudioTask:_adjustmentFiles(adjFunc)
    local wavs = ADJ_WAVS[adjFunc]
    local files = {}
    local resolved
    local missing
    local i
    local message

    if type(wavs) ~= "table" then
        return nil
    end

    for i = 1, #wavs do
        files[i] = wavs[i] .. ".wav"
    end

    resolved, missing = AudioLib.resolvePackageFiles("adjfunctions", files)
    if #missing > 0 then
        self.missingAdjAudio = self.missingAdjAudio or {}
        if self.missingAdjAudio[adjFunc] ~= true then
            self.missingAdjAudio[adjFunc] = true
            message = table.concat(missing, ", ")
            self.framework.log:warn("[audio] missing adjustment audio for id=%s: %s", tostring(adjFunc), message)
        end
    end

    return files
end

function AudioTask:_playCommon(file, now)
    if not self:_canSpeak(now) then
        return false
    end

    if AudioLib.playFileCommon(file) then
        self:_reserveSpeech(now, SPEAK_WAV_MS / 1000.0)
        return true
    end

    return false
end

function AudioTask:_playNumber(value, unit, decimals, now)
    if not self:_canSpeak(now) then
        return false
    end

    if AudioLib.playNumber(value, unit, decimals) then
        self:_reserveSpeech(now, SPEAK_NUM_MS / 1000.0)
        return true
    end

    return false
end

function AudioTask:_announceModelName(now)
    local eventsPrefs = self:_eventsPrefs()
    local craftName
    local audioFile

    if eventsPrefs.otherModelAnnounce ~= true or self.modelAnnounced == true then
        return
    end

    craftName = self.framework.session:get("craftName", nil)
    if not craftName or craftName == "" then
        return
    end

    if not self:_canSpeak(now) then
        return
    end

    audioFile = AudioLib.resolveModelAnnouncementFile(craftName)
    self.modelAnnounced = true

    if audioFile then
        AudioLib.playResolved(audioFile)
        self:_reserveSpeech(now, SPEAK_WAV_MS / 1000.0)
    end
end

function AudioTask:_handleArmGovernorEvents(now)
    local telemetry = self.framework:getTask("telemetry")
    local eventsPrefs = self:_eventsPrefs()
    local armValue
    local governorValue
    local filename

    if not telemetry or not telemetry.getSensor then
        return
    end

    armValue = telemetry.getSensor("armflags")
    if eventsPrefs.armflags == true and armValue ~= nil and armValue ~= self.lastArmValue and self.lastArmValue ~= nil then
        filename = ARM_FILES[armValue]
        if filename then
            self:_playPackageFiles("events", {"alerts/" .. filename}, now)
        end
    end
    self.lastArmValue = armValue

    governorValue = telemetry.getSensor("governor")
    if eventsPrefs.governor == true and governorValue ~= nil and governorValue ~= self.lastGovernorValue and self.lastGovernorValue ~= nil then
        filename = GOVERNOR_FILES[governorValue]
        if filename then
            self:_playPackageFiles("events", {"gov/" .. filename}, now)
        end
    end
    self.lastGovernorValue = governorValue
end

function AudioTask:_handleSmartFuel(now)
    local telemetry = self.framework:getTask("telemetry")
    local eventsPrefs = self:_eventsPrefs()
    local value
    local thresholds
    local index
    local threshold
    local repeatsBelow
    local shouldRepeat

    if not telemetry or not telemetry.getSensor or eventsPrefs.smartfuel ~= true then
        self.lastSmartfuelAnnounced = nil
        self.lowFuelRepeatAt = 0
        self.lowFuelRepeatCount = 0
        return
    end

    value = telemetry.getSensor("smartfuel")
    if type(value) ~= "number" then
        return
    end

    value = clamp(math.floor(value + 0.5), 0, 100)
    thresholds = buildSmartfuelThresholds(tonumber(eventsPrefs.smartfuelcallout) or 10)

    for index = 1, #thresholds do
        threshold = thresholds[index]
        if value <= threshold and (self.lastSmartfuelAnnounced == nil or threshold < self.lastSmartfuelAnnounced) then
            if self:_playPackageFiles("status", {"alerts/fuel.wav"}, now) then
                self:_playNumber(value, UNIT_PERCENT, 0, self.speakingUntil or now)
                self.lastSmartfuelAnnounced = threshold
                self.lowFuelRepeatAt = now
                self.lowFuelRepeatCount = 1
                if eventsPrefs.smartfuelhaptic == true then
                    AudioLib.playHaptic(HAPTIC_MS, 0, 0)
                end
            end
            break
        end
    end

    repeatsBelow = self.lastSmartfuelAnnounced
    shouldRepeat = repeatsBelow ~= nil and type(eventsPrefs.smartfuelrepeats) == "number" and eventsPrefs.smartfuelrepeats > 1
    if shouldRepeat and value <= repeatsBelow and self.lowFuelRepeatCount < eventsPrefs.smartfuelrepeats then
        if now - (self.lowFuelRepeatAt or 0) >= 10 and self:_playPackageFiles("status", {"alerts/lowfuel.wav"}, now) then
            self.lowFuelRepeatAt = now
            self.lowFuelRepeatCount = self.lowFuelRepeatCount + 1
        end
    end
end

function AudioTask:_handleAdjustmentCallouts(now)
    local telemetry = self.framework:getTask("telemetry")
    local eventsPrefs = self:_eventsPrefs()
    local adjFunc
    local adjValue
    local files
    local hasBaseline

    if not telemetry or not telemetry.getSensor then
        return
    end

    adjFunc = telemetry.getSensor("adj_f")
    adjValue = telemetry.getSensor("adj_v")

    if type(adjFunc) == "number" then
        adjFunc = math.floor(adjFunc)
    end
    if type(adjValue) == "number" then
        adjValue = math.floor(adjValue)
    end

    if adjFunc == nil or adjValue == nil then
        return
    end

    hasBaseline = self.adjustmentInitialized == true
    if adjFunc ~= self.lastAdjFunc then
        self.pendingAdjFuncAnnounce = adjFunc
    end

    if hasBaseline and self.pendingAdjFuncAnnounce ~= nil and eventsPrefs.adj_f == true and adjFunc and adjFunc ~= 0 then
        files = self:_adjustmentFiles(adjFunc)
        if files and self:_playPackageFiles("adjfunctions", files, now) then
            if adjValue ~= nil then
                self:_playNumber(adjValue, nil, nil, self.speakingUntil or now)
            end
            self.pendingAdjFuncAnnounce = nil
        end
    elseif hasBaseline and eventsPrefs.adj_v == true and adjValue ~= nil and adjValue ~= self.lastAdjValue and adjFunc and adjFunc ~= 0 then
        self:_playNumber(adjValue, nil, nil, now)
    end

    self.lastAdjFunc = adjFunc
    self.lastAdjValue = adjValue
    self.adjustmentInitialized = true
end

function AudioTask:_handleProfileCallouts(now)
    local telemetry = self.framework:getTask("telemetry")
    local eventsPrefs = self:_eventsPrefs()
    local pidProfile
    local rateProfile
    local batteryProfile
    local batteryCapacity

    if not telemetry or not telemetry.getSensor then
        return
    end

    pidProfile = telemetry.getSensor("pid_profile")
    if type(pidProfile) == "number" then
        pidProfile = math.floor(pidProfile)
    end
    if eventsPrefs.pid_profile == true and pidProfile ~= nil and pidProfile ~= self.lastPidProfile and self.lastPidProfile ~= nil then
        if self:_playPackageFiles("events", {"alerts/profile.wav"}, now) then
            self:_playNumber(pidProfile, nil, nil, self.speakingUntil or now)
        end
    end
    self.lastPidProfile = pidProfile

    rateProfile = telemetry.getSensor("rate_profile")
    if type(rateProfile) == "number" then
        rateProfile = math.floor(rateProfile)
    end
    if eventsPrefs.rate_profile == true and rateProfile ~= nil and rateProfile ~= self.lastRateProfile and self.lastRateProfile ~= nil then
        if self:_playPackageFiles("events", {"alerts/rates.wav"}, now) then
            self:_playNumber(rateProfile, nil, nil, self.speakingUntil or now)
        end
    end
    self.lastRateProfile = rateProfile

    batteryProfile = telemetry.getSensor("battery_profile")
    if type(batteryProfile) == "number" then
        batteryProfile = math.floor(batteryProfile)
    end
    if eventsPrefs.battery_profile == true and batteryProfile ~= nil and batteryProfile ~= self.lastBatteryProfile and self.lastBatteryProfile ~= nil then
        batteryCapacity = resolveBatteryCapacityForProfile(self.framework.session, batteryProfile)
        if batteryCapacity ~= nil and self:_playPackageFiles("events", {"alerts/battery.wav"}, now) then
            self:_playNumber(math.floor(batteryCapacity + 0.5), UNIT_MILLIAMPERE_HOUR, 0, self.speakingUntil or now)
        end
    end
    self.lastBatteryProfile = batteryProfile
end

function AudioTask:_handleTimerCallouts(now)
    local timerPrefs = self:_timerPrefs()
    local timerState = self.framework.session:get("timer", nil)
    local modelPreferences = self.framework.session:get("modelPreferences", nil)
    local batteryPrefs
    local targetSeconds
    local elapsed
    local elapsedMode
    local preAlertStart

    if timerPrefs.timeraudioenable ~= true then
        self.preLastBeepTimer = nil
        self.lastBeepTimer = nil
        self.timerTriggered = false
        return
    end

    if type(timerState) ~= "table" or type(timerState.live) ~= "number" then
        return
    end

    batteryPrefs = modelPreferences and modelPreferences.battery or nil
    targetSeconds = batteryPrefs and tonumber(batteryPrefs.flighttime) or 0
    if targetSeconds <= 0 then
        self.preLastBeepTimer = nil
        self.lastBeepTimer = nil
        self.timerTriggered = false
        return
    end

    elapsed = timerState.live or 0
    elapsedMode = tonumber(timerPrefs.elapsedalertmode) or 0

    if timerPrefs.prealerton == true then
        preAlertStart = targetSeconds - (tonumber(timerPrefs.prealertperiod) or 30)
        if elapsed >= preAlertStart and elapsed < targetSeconds then
            if self.preLastBeepTimer == nil or (elapsed - self.preLastBeepTimer) >= (tonumber(timerPrefs.prealertinterval) or 10) then
                if self:_playCommon("beep.wav", now) then
                    self.preLastBeepTimer = elapsed
                end
            end
            self.timerTriggered = false
            self.lastBeepTimer = nil
            return
        end
    end

    if elapsed >= targetSeconds then
        if not self.timerTriggered then
            if elapsedMode == 0 then
                self:_playCommon("beep.wav", now)
            elseif elapsedMode == 1 then
                self:_playCommon("multibeep.wav", now)
            elseif elapsedMode == 2 then
                self:_playPackageFiles("events", {"alerts/elapsed.wav"}, now)
            elseif elapsedMode == 3 and self:_playPackageFiles("status", {"alerts/timer.wav"}, now) then
                self:_playNumber(targetSeconds, UNIT_SECOND, 0, self.speakingUntil or now)
            end
            self.timerTriggered = true
            self.lastBeepTimer = elapsed
        end
    else
        self.timerTriggered = false
        self.lastBeepTimer = nil
    end
end

function AudioTask:_handleConnectBeep(now)
    if self.pendingConnectBeep ~= true then
        return
    end

    if self.framework.session:get("isConnected", false) ~= true then
        return
    end

    if self:_playCommon("beep.wav", now) then
        self.pendingConnectBeep = false
    end
end

function AudioTask:init(framework)
    self.framework = framework
    self.startedAt = os.clock()
    self.speakingUntil = 0
    self.modelAnnounced = false
    self.lastArmValue = nil
    self.lastGovernorValue = nil
    self.lastPidProfile = nil
    self.lastRateProfile = nil
    self.lastBatteryProfile = nil
    self.lastAdjFunc = nil
    self.lastAdjValue = nil
    self.adjustmentInitialized = false
    self.pendingAdjFuncAnnounce = nil
    self.lastSmartfuelAnnounced = nil
    self.lowFuelRepeatAt = 0
    self.lowFuelRepeatCount = 0
    self.preLastBeepTimer = nil
    self.lastBeepTimer = nil
    self.timerTriggered = false
    self.pendingConnectBeep = false

    framework.preferences:section("events", DEFAULT_EVENT_PREFS)
    framework.preferences:section("timer", DEFAULT_TIMER_PREFS)
    self:_migrateLegacyAudioDefaults()

    framework:on("msp:apiVersion", function(payload)
        if type(payload) == "table" and payload.apiVersion ~= nil and payload.invalid ~= true and payload.unsupported ~= true then
            self.pendingConnectBeep = true
        end
    end)

    framework:on("ondisconnect", function()
        self:reset()
    end)
end

function AudioTask:wakeup()
    local now = os.clock()

    if (now - (self.startedAt or 0)) < INIT_GUARD_SECONDS then
        return
    end

    if self.framework.session:get("isConnected", false) ~= true then
        return
    end

    self:_handleConnectBeep(now)
    self:_announceModelName(now)
    self:_handleArmGovernorEvents(now)
    self:_handleProfileCallouts(now)
    self:_handleSmartFuel(now)
    self:_handleAdjustmentCallouts(now)
    self:_handleTimerCallouts(now)
end

function AudioTask:reset()
    self.speakingUntil = 0
    self.modelAnnounced = false
    self.lastArmValue = nil
    self.lastGovernorValue = nil
    self.lastPidProfile = nil
    self.lastRateProfile = nil
    self.lastBatteryProfile = nil
    self.lastAdjFunc = nil
    self.lastAdjValue = nil
    self.adjustmentInitialized = false
    self.pendingAdjFuncAnnounce = nil
    self.lastSmartfuelAnnounced = nil
    self.lowFuelRepeatAt = 0
    self.lowFuelRepeatCount = 0
    self.preLastBeepTimer = nil
    self.lastBeepTimer = nil
    self.timerTriggered = false
    self.pendingConnectBeep = false
    self.startedAt = os.clock()
end

function AudioTask:close()
    self.framework = nil
end

return AudioTask
