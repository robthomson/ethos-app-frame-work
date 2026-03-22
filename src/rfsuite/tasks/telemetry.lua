--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local catalog = require("telemetry.catalog")
local utils = require("lib.utils")
local ModuleLoader = require("framework.utils.module_loader")

local TelemetryTask = {}

local SOURCE_MODULES = {
    sim = "telemetry.sources.sim",
    sport = "telemetry.sources.sport",
    crsf = "telemetry.sources.crsf",
    crsfLegacy = "telemetry.sources.crsf_legacy"
}

local HOT_SIZE = 20
local ONCHANGE_INTERVAL = 0.25
local STATS_PER_WAKEUP = 4

local function loadModule(moduleName)
    local path

    path = string.gsub(moduleName, "%.", "/") .. ".lua"
    return ModuleLoader.requireOrLoad(moduleName, path)
end

local function getSource(descriptor)
    local ok
    local source

    if not system or not system.getSource then
        return nil
    end

    ok, source = pcall(system.getSource, descriptor)
    if ok then
        return source
    end

    return nil
end

local function getSourceValue(source)
    local ok
    local value
    local major
    local minor

    if not source or type(source.value) ~= "function" then
        return nil, nil, nil
    end

    ok, value, major, minor = pcall(source.value, source)
    if ok then
        return value, major, minor
    end

    return nil, nil, nil
end

local function getSourceState(source)
    local ok
    local state

    if not source or type(source.state) ~= "function" then
        return nil
    end

    ok, state = pcall(source.state, source)
    if ok then
        return state
    end

    return nil
end

function TelemetryTask:_buildPublicApi()
    self.getSensorSource = function(name)
        return self:_getSensorSource(name)
    end
    self.getSensor = function(sensorKey, paramMin, paramMax, paramThresholds)
        return self:_getSensor(sensorKey, paramMin, paramMax, paramThresholds)
    end
    self.listSensors = function()
        return self:_listSensors()
    end
    self.listSwitchSensors = function()
        return self:_listSwitchSensors()
    end
    self.listSensorAudioUnits = function()
        return self:_listSensorAudioUnits()
    end
    self.validateSensors = function(returnValid)
        return self:_validateSensors(returnValid)
    end
    self.getSensorStats = function(sensorKey)
        return self.sensorStats[sensorKey] or {min = nil, max = nil, last = nil}
    end
    self.active = function()
        if system and system.getVersion and system.getVersion().simulation == true then
            return true
        end
        return self.framework.session:get("telemetryState", false) == true
    end
    self.reset = function()
        self:_resetCaches()
    end
    self.simSensors = function()
        return self:_simSensors()
    end
end

function TelemetryTask:_buildMemoLists()
    local audioUnits = {}
    local sensors = {}
    local switchSensors = {}
    local key
    local entry

    for key, entry in pairs(catalog) do
        sensors[#sensors + 1] = {
            key = key,
            name = entry.name,
            mandatory = entry.mandatory,
            set_telemetry_sensors = entry.set_telemetry_sensors
        }

        if entry.switch_alerts then
            switchSensors[#switchSensors + 1] = {
                key = key,
                name = entry.name,
                mandatory = entry.mandatory,
                set_telemetry_sensors = entry.set_telemetry_sensors
            }
        end

        if entry.unit then
            audioUnits[key] = entry.unit
        end
    end

    self._memoListSensors = sensors
    self._memoListSwitchSensors = switchSensors
    self._memoListAudioUnits = audioUnits
end

function TelemetryTask:_listSensors()
    if not self._memoListSensors then
        self:_buildMemoLists()
    end

    return self._memoListSensors
end

function TelemetryTask:_listSwitchSensors()
    if not self._memoListSwitchSensors then
        self:_buildMemoLists()
    end

    return self._memoListSwitchSensors
end

function TelemetryTask:_listSensorAudioUnits()
    if not self._memoListAudioUnits then
        self:_buildMemoLists()
    end

    return self._memoListAudioUnits
end

function TelemetryTask:_checkCondition(sensorEntry)
    if type(sensorEntry) ~= "table" then
        return true
    end

    if sensorEntry.mspgt and not utils.apiVersionCompare(">=", sensorEntry.mspgt) then
        return false
    end
    if sensorEntry.msplt and not utils.apiVersionCompare("<=", sensorEntry.msplt) then
        return false
    end

    return true
end

function TelemetryTask:_loadSourceTable(mode)
    local sourceTable
    local moduleName

    if not mode then
        return nil
    end

    sourceTable = self._sourceTables[mode]
    if sourceTable ~= nil then
        return sourceTable
    end

    moduleName = SOURCE_MODULES[mode]
    if not moduleName then
        return nil
    end

    sourceTable = loadModule(moduleName)
    self._sourceTables[mode] = sourceTable or {}
    return self._sourceTables[mode]
end

function TelemetryTask:_detectSourceMode()
    local session = self.framework.session
    local mode = session:get("telemetryType", "disconnected")

    if system and system.getVersion and system.getVersion().simulation == true then
        return "sim"
    end

    if mode == "crsf" then
        if not self._crsfV3SourceChecked then
            self._crsfV3Source = getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = 0xEE01}) or false
            self._crsfV3SourceChecked = true
        end

        if self._crsfV3Source and self._crsfV3Source ~= false then
            return "crsf"
        end

        return "crsfLegacy"
    end

    if mode == "sport" then
        return "sport"
    end

    return nil
end

function TelemetryTask:_reindexHotFrom(startIndex)
    local i

    for i = startIndex or 1, #self._hotList do
        self._hotIndex[self._hotList[i]] = i
    end
end

function TelemetryTask:_markHot(key)
    local index = self._hotIndex[key]
    local oldKey

    if index and index >= 1 and index <= #self._hotList then
        table.remove(self._hotList, index)
        self:_reindexHotFrom(index)
    elseif #self._hotList >= HOT_SIZE then
        oldKey = table.remove(self._hotList, 1)
        if oldKey ~= nil then
            self._hotIndex[oldKey] = nil
            self._sources[oldKey] = nil
        end
        self:_reindexHotFrom(1)
    end

    self._hotList[#self._hotList + 1] = key
    self._hotIndex[key] = #self._hotList
end

function TelemetryTask:_makeVirtualSource(key, candidate)
    local id = key .. ":" .. tostring(candidate.uid or candidate.appId or "virtual")
    local source = self._virtualSources[id]

    if source then
        return source
    end

    source = {
        value = function()
            local value = candidate.value
            if type(value) == "function" then
                return value()
            end
            return value
        end,
        state = function()
            return true
        end
    }

    self._virtualSources[id] = source
    return source
end

function TelemetryTask:_resolveCandidate(key, candidate)
    local source

    if candidate == nil then
        return nil
    end

    if type(candidate) == "string" then
        return getSource(candidate)
    end

    if type(candidate) ~= "table" or not self:_checkCondition(candidate) then
        return nil
    end

    if candidate.uid then
        source = getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = candidate.uid})
        if source then
            return source
        end

        if type(candidate.value) == "function" then
            return self:_makeVirtualSource(key, candidate)
        end

        return nil
    end

    source = getSource(candidate)
    if source then
        return source
    end

    if type(candidate.value) == "function" then
        return self:_makeVirtualSource(key, candidate)
    end

    return nil
end

function TelemetryTask:_resetCaches()
    self._sources = {}
    self._virtualSources = {}
    self._hotList = {}
    self._hotIndex = {}
    self._lastOnchangeValues = {}
    self._mode = nil
    self._sourceTable = nil
    self._crsfV3Source = nil
    self._crsfV3SourceChecked = false
    self._statsIndex = 1
end

function TelemetryTask:_ensureMode()
    local mode = self:_detectSourceMode()

    if mode ~= self._mode then
        self:_resetCaches()
        self._mode = mode
        self._sourceTable = self:_loadSourceTable(mode)
    elseif self._sourceTable == nil and mode ~= nil then
        self._sourceTable = self:_loadSourceTable(mode)
    end

    return self._mode, self._sourceTable
end

function TelemetryTask:_getSensorSource(name)
    local source
    local candidates
    local i
    local mode

    if not catalog[name] then
        return nil
    end

    mode = self:_ensureMode()
    if not mode or not self._sourceTable then
        return nil
    end

    source = self._sources[name]
    if source then
        self:_markHot(name)
        return source
    end

    candidates = self._sourceTable[name] or {}
    for i = 1, #candidates do
        source = self:_resolveCandidate(name, candidates[i])
        if source then
            self._sources[name] = source
            self:_markHot(name)
            return source
        end
    end

    return nil
end

function TelemetryTask:_getSensor(sensorKey, paramMin, paramMax, paramThresholds)
    local entry = catalog[sensorKey]
    local source
    local value
    local major
    local minor

    if not entry then
        return nil
    end

    self._resolvingSensors = self._resolvingSensors or {}
    if self._resolvingSensors[sensorKey] == true then
        return nil
    end

    self._resolvingSensors[sensorKey] = true

    if type(entry.source) == "function" then
        value, major, minor = entry.source(paramMin, paramMax, paramThresholds)
        self._resolvingSensors[sensorKey] = nil
        return value, major, minor
    end

    source = self:_getSensorSource(sensorKey)
    if not source then
        self._resolvingSensors[sensorKey] = nil
        return nil
    end

    value, major, minor = getSourceValue(source)
    if value == nil then
        self._resolvingSensors[sensorKey] = nil
        return nil
    end

    if type(entry.transform) == "function" then
        value = entry.transform(value)
    end

    if sensorKey == "battery_profile" then
        self.framework.session:set("activeBatteryProfile", value)
    end

    if type(entry.localizations) == "function" then
        self._resolvingSensors[sensorKey] = nil
        return entry.localizations(value, paramMin, paramMax, paramThresholds)
    end

    self._resolvingSensors[sensorKey] = nil
    return value, major or entry.unit, minor, paramMin, paramMax, paramThresholds
end

function TelemetryTask:_validateSensors(returnValid)
    local result = {}
    local key
    local entry
    local source
    local isValid

    if not self:active() then
        return self:_listSensors()
    end

    for key, entry in pairs(catalog) do
        source = self:_getSensorSource(key)
        isValid = (source ~= nil and getSourceState(source) ~= false)

        if returnValid then
            if isValid then
                result[#result + 1] = {key = key, name = entry.name}
            end
        elseif not isValid and entry.mandatory ~= false then
            result[#result + 1] = {key = key, name = entry.name}
        end
    end

    return result
end

function TelemetryTask:_simSensors()
    local sourceTable = self:_loadSourceTable("sim") or {}
    local result = {}
    local key
    local entry
    local candidates
    local firstSim

    for key, entry in pairs(catalog) do
        candidates = sourceTable[key]
        firstSim = candidates and candidates[1]
        if firstSim and type(firstSim) == "table" and firstSim.uid then
            result[#result + 1] = {
                name = entry.name,
                sensor = firstSim
            }
        end
    end

    return result
end

function TelemetryTask:_updateOnchange(now)
    local key
    local entry
    local value

    if (now - self._lastOnchangeAt) < ONCHANGE_INTERVAL then
        return
    end

    self._lastOnchangeAt = now

    for key, entry in pairs(catalog) do
        if type(entry.onchange) == "function" then
            value = self:_getSensor(key)
            if value ~= self._lastOnchangeValues[key] then
                self._lastOnchangeValues[key] = value
                entry.onchange(value)
            end
        end
    end
end

function TelemetryTask:_updateStats()
    local processed = 0
    local sensorKey
    local value
    local stats

    if #self._statKeys == 0 then
        return
    end

    while processed < STATS_PER_WAKEUP do
        sensorKey = self._statKeys[self._statsIndex]
        self._statsIndex = self._statsIndex + 1
        if self._statsIndex > #self._statKeys then
            self._statsIndex = 1
        end

        processed = processed + 1
        if sensorKey then
            value = self:_getSensor(sensorKey)
            if type(value) == "number" then
                stats = self.sensorStats[sensorKey]
                if not stats then
                    stats = {min = value, max = value, last = value}
                    self.sensorStats[sensorKey] = stats
                else
                    if stats.min == nil or value < stats.min then
                        stats.min = value
                    end
                    if stats.max == nil or value > stats.max then
                        stats.max = value
                    end
                    stats.last = value
                end
            end
        end
    end
end

function TelemetryTask:init(framework)
    local key
    local entry
    local statKeys = {}

    self.framework = framework
    self.sensorStats = framework.session:get("sensorStats", {}) or {}
    self._sourceTables = {}
    self._memoListSensors = nil
    self._memoListSwitchSensors = nil
    self._memoListAudioUnits = nil
    self._lastOnchangeAt = 0
    self._resolvingSensors = {}

    for key, entry in pairs(catalog) do
        if entry.stats then
            statKeys[#statKeys + 1] = key
        end
    end

    self._statKeys = statKeys
    self:_buildPublicApi()
    self:_resetCaches()

    framework.session:set("sensorStats", self.sensorStats)

    framework:on("ontransportchange", function()
        self:_resetCaches()
    end)
    framework:on("ondisconnect", function()
        self:_resetCaches()
    end)
end

function TelemetryTask:wakeup()
    local now = os.clock()

    self:_ensureMode()
    if self.framework.session:get("sensorStats", nil) ~= self.sensorStats then
        self.framework.session:set("sensorStats", self.sensorStats)
    end

    if self.framework.session:get("mspBusy", false) == true then
        return
    end

    self:_updateOnchange(now)
    self:_updateStats()
end

function TelemetryTask:close()
    self:_resetCaches()
    self.framework = nil
end

return TelemetryTask
