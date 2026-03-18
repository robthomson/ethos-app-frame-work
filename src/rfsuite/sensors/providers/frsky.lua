--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local Provider = {}
Provider.__index = Provider

local TELEMETRY_PHYS_ID = 27
local SENSOR_DEFS_MODULE = "sensors.providers.frsky_sensors"
local SENSOR_DEFS_PATH = "sensors/providers/frsky_sensors.lua"
local SID_LOOKUP_MODULE = "sensors.providers.frsky_sid_lookup"
local SID_LOOKUP_PATH = "sensors/providers/frsky_sid_lookup.lua"

local function loadLuaModule(moduleName, path)
    local ok
    local result
    local chunk
    local loadErr

    ok, result = pcall(require, moduleName)
    if ok then
        return result
    end

    if not loadfile then
        return nil, result
    end

    chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr or result
    end

    ok, result = pcall(chunk)
    if ok then
        return result
    end

    return nil, result
end

local function unloadLuaModule(moduleName)
    if package and type(package.loaded) == "table" then
        package.loaded[moduleName] = nil
    end
end

local function loadTransientLuaModule(moduleName, path)
    local result
    local err

    result, err = loadLuaModule(moduleName, path)
    unloadLuaModule(moduleName)
    return result, err
end

local function moduleNumberForSession(session)
    local source = session:get("telemetrySensor", nil)

    if source and type(source.module) == "function" then
        return source:module()
    end

    return 0
end

local function syncSportMetadata(sensor, appId, meta, moduleNumber)
    if not sensor or not meta then
        return
    end

    pcall(sensor.appId, sensor, appId)
    pcall(sensor.physId, sensor, TELEMETRY_PHYS_ID)
    pcall(sensor.module, sensor, moduleNumber)
    pcall(sensor.type, sensor, SENSOR_TYPE_SPORT)

    if meta.name ~= nil then
        pcall(sensor.name, sensor, meta.name)
    end
    pcall(sensor.minimum, sensor, meta.minimum or -1000000000)
    pcall(sensor.maximum, sensor, meta.maximum or 2147483647)
    if meta.unit ~= nil then
        pcall(sensor.unit, sensor, meta.unit)
        pcall(sensor.protocolUnit, sensor, meta.unit)
    end
    if meta.decimals ~= nil then
        pcall(sensor.decimals, sensor, meta.decimals)
        pcall(sensor.protocolDecimals, sensor, meta.decimals)
    end
end

function Provider.new(framework)
    return setmetatable({
        framework = framework,
        createSensorCache = {},
        renameSensorCache = {},
        activeCreateDefs = {},
        activeRenameDefs = {},
        activeProvisionAppIds = {},
        sidLookup = nil,
        sensorDefs = nil,
        activeDefsSignature = nil,
        provisionedSignature = nil,
        unsupportedLogged = false,
        wasDiscoverActive = false
    }, Provider)
end

function Provider:_clearCaches()
    self.createSensorCache = {}
    self.renameSensorCache = {}
end

function Provider:_clearActiveDefs()
    self.activeCreateDefs = {}
    self.activeRenameDefs = {}
    self.activeProvisionAppIds = {}
    self.activeDefsSignature = nil
    self.sidLookup = nil
    self.sensorDefs = nil
end

function Provider:_loadSidLookup()
    local sidLookup
    local sidLookupErr

    if self.sidLookup ~= nil then
        return self.sidLookup
    end

    sidLookup, sidLookupErr = loadTransientLuaModule(SID_LOOKUP_MODULE, SID_LOOKUP_PATH)
    if type(sidLookup) ~= "table" then
        utils.log("[frsky] Failed to load SID lookup table: " .. tostring(sidLookupErr or "invalid_table"), "error")
        sidLookup = {}
    end

    self.sidLookup = sidLookup
    return self.sidLookup
end

function Provider:_loadSensorDefs()
    local sensorDefs
    local sensorDefsErr

    if self.sensorDefs ~= nil then
        return self.sensorDefs
    end

    sensorDefs, sensorDefsErr = loadTransientLuaModule(SENSOR_DEFS_MODULE, SENSOR_DEFS_PATH)
    if type(sensorDefs) ~= "table" then
        utils.log("[frsky] Failed to load sensor definitions: " .. tostring(sensorDefsErr or "invalid_table"), "error")
        sensorDefs = {create = {}, rename = {}, drop = {}}
    end

    self.sensorDefs = sensorDefs
    return self.sensorDefs
end

function Provider:_ensureCreatedSensor(appId, meta)
    local sensor = self.createSensorCache[appId]
    local moduleNumber = moduleNumberForSession(self.framework.session)

    if sensor then
        syncSportMetadata(sensor, appId, meta, moduleNumber)
        return sensor
    end

    sensor = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = appId})
    if sensor then
        syncSportMetadata(sensor, appId, meta, moduleNumber)
        self.createSensorCache[appId] = sensor
        return sensor
    end

    utils.log("[frsky] Creating sensor: " .. tostring(meta.name or string.format("0x%04X", appId)), "info")
    sensor = model.createSensor()
    syncSportMetadata(sensor, appId, meta, moduleNumber)
    self.createSensorCache[appId] = sensor
    return sensor
end

function Provider:_renameSensorIfNeeded(appId)
    local rename = self.activeRenameDefs[appId]
    local sensor = self.renameSensorCache[appId]
    local currentName

    if not rename then
        return
    end

    if not sensor then
        sensor = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = appId})
        self.renameSensorCache[appId] = sensor or false
    end
    if not sensor or sensor == false then
        return
    end

    currentName = type(sensor.name) == "function" and sensor:name() or nil
    if currentName == rename.onlyifname then
        utils.log("[frsky] Rename sensor: " .. tostring(rename.name), "info")
        pcall(sensor.name, sensor, rename.name)
    elseif currentName == rename.name then
        pcall(sensor.name, sensor, rename.name)
    end
end

function Provider:_rebuildActiveDefs(cfg, signature)
    local sidLookup = self:_loadSidLookup()
    local sensorDefs = self:_loadSensorDefs()
    local activeCreateDefs = {}
    local activeRenameDefs = {}
    local activeProvisionAppIds = {}
    local seen = {}
    local index
    local sid
    local appIds
    local j
    local appId

    if self.activeDefsSignature == signature then
        return
    end

    for index = 1, #cfg do
        sid = cfg[index]
        appIds = sidLookup[sid]
        if appIds then
            for j = 1, #appIds do
                appId = appIds[j]
                if appId and not seen[appId] then
                    seen[appId] = true
                    activeProvisionAppIds[#activeProvisionAppIds + 1] = appId
                end
                if appId and sensorDefs.create and sensorDefs.create[appId] then
                    activeCreateDefs[appId] = sensorDefs.create[appId]
                end
                if appId and sensorDefs.rename and sensorDefs.rename[appId] then
                    activeRenameDefs[appId] = sensorDefs.rename[appId]
                end
            end
        end
    end

    self.activeCreateDefs = activeCreateDefs
    self.activeRenameDefs = activeRenameDefs
    self.activeProvisionAppIds = activeProvisionAppIds
    self.activeDefsSignature = signature
    self.sidLookup = nil
    self.sensorDefs = nil
end

function Provider:_configSignature()
    local cfg = self.framework.session:get("telemetryConfig", nil)
    local moduleNumber = moduleNumberForSession(self.framework.session)
    local parts = {tostring(moduleNumber)}
    local i

    if type(cfg) ~= "table" then
        return nil
    end

    for i = 1, #cfg do
        parts[#parts + 1] = tostring(cfg[i] or 0)
    end

    return table.concat(parts, ",")
end

function Provider:_provisionFromConfig()
    local cfg = self.framework.session:get("telemetryConfig", nil)
    local signature
    local index
    local appId
    local meta

    if type(cfg) ~= "table" then
        return
    end

    signature = self:_configSignature()
    if signature and signature == self.provisionedSignature then
        return
    end

    self:_rebuildActiveDefs(cfg, signature)

    for index = 1, #self.activeProvisionAppIds do
        appId = self.activeProvisionAppIds[index]
        meta = self.activeCreateDefs[appId]
        if meta then
            self:_ensureCreatedSensor(appId, meta)
        end
        self:_renameSensorIfNeeded(appId)
    end

    self.provisionedSignature = signature
end

function Provider:wakeup()
    local session = self.framework.session
    local discoverActive = system.isSensorDiscoverActive and system.isSensorDiscoverActive() == true

    if not session:get("isConnected", false) then
        return
    end
    if session:get("telemetryState", false) ~= true or session:get("telemetrySensor", nil) == nil then
        self:_clearCaches()
        self:_clearActiveDefs()
        self.provisionedSignature = nil
        return
    end
    if utils.apiVersionCompare("<", {12, 0, 8}) then
        if not self.unsupportedLogged then
            utils.log("[frsky] SPORT sensors require FC API 12.0.8 or newer", "warn")
            self.unsupportedLogged = true
        end
        return
    end
    self.unsupportedLogged = false

    if discoverActive then
        if not self.wasDiscoverActive then
            self:_clearCaches()
            self:_clearActiveDefs()
            self.provisionedSignature = nil
        end
        self.wasDiscoverActive = true
        return
    end

    if self.wasDiscoverActive then
        self:_clearCaches()
        self:_clearActiveDefs()
        self.provisionedSignature = nil
        self.wasDiscoverActive = false
    end

    self:_provisionFromConfig()
end

function Provider:reset()
    self:_clearCaches()
    self:_clearActiveDefs()
    self.provisionedSignature = nil
    self.unsupportedLogged = false
    self.wasDiscoverActive = false
end

return Provider
