--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local Provider = {}
Provider.__index = Provider

local FORCE_REFRESH_INTERVAL = 1.0
local INITIAL_FORCE_REFRESH_INTERVAL = 0.25
local INITIAL_FORCE_REFRESH_WINDOW = 3.0

local API_ORDER = {
    "DATAFLASH_SUMMARY",
    "GOVERNOR_CONFIG",
    "NAME"
}

local API_DEFS = {
    DATAFLASH_SUMMARY = {
        intervalArmed = -1,
        intervalDisarmed = 10,
        onConnect = true,
        onDisarm = true,
        fields = {
            flags = {
                sessionKey = "bblFlags",
                startupValue = 0,
                sensor = {
                    appId = 0x5FFF,
                    name = "@i18n(sensors.blackbox.flags)@",
                    unit = UNIT_RAW,
                    min = 0,
                    max = 255
                }
            },
            total = {
                sessionKey = "bblSize",
                startupValue = 0,
                sensor = {
                    appId = 0x5FFE,
                    name = "@i18n(sensors.blackbox.size)@",
                    unit = UNIT_RAW,
                    min = 0,
                    max = 2147483647
                }
            },
            used = {
                sessionKey = "bblUsed",
                startupValue = 0,
                sensor = {
                    appId = 0x5FFD,
                    name = "@i18n(sensors.blackbox.used)@",
                    unit = UNIT_RAW,
                    min = 0,
                    max = 2147483647
                }
            }
        }
    },
    GOVERNOR_CONFIG = {
        intervalArmed = -1,
        intervalDisarmed = 10,
        onConnect = false,
        onDisarm = false,
        fields = {
            gov_mode = {
                sessionKey = "governorMode",
                sensor = {
                    appId = 0x5FFC,
                    name = "@i18n(sensors.system.governor_mode)@",
                    unit = UNIT_RAW,
                    min = 0,
                    max = 255
                }
            }
        }
    },
    NAME = {
        intervalArmed = -1,
        intervalDisarmed = 30,
        onConnect = true,
        onDisarm = false,
        fields = {
            name = {
                sessionKey = "craftName"
            }
        }
    }
}

local function moduleNumberForSession(session)
    local moduleNumber = session:get("telemetryModuleNumber", nil)
    local source = session:get("telemetrySensor", nil)

    if type(moduleNumber) == "number" then
        return moduleNumber
    end

    if source and type(source.module) == "function" then
        moduleNumber = source:module()
        if type(moduleNumber) == "number" then
            return moduleNumber
        end
    end

    return nil
end

local function syncSensorMetadata(sensor, definition, moduleNumber)
    if not sensor or not definition then
        return
    end

    if definition.name ~= nil then
        pcall(sensor.name, sensor, definition.name)
    end
    if moduleNumber ~= nil then
        pcall(sensor.module, sensor, moduleNumber)
    end
    if definition.min ~= nil then
        pcall(sensor.minimum, sensor, definition.min)
    end
    if definition.max ~= nil then
        pcall(sensor.maximum, sensor, definition.max)
    end
    if definition.unit ~= nil then
        pcall(sensor.unit, sensor, definition.unit)
        pcall(sensor.protocolUnit, sensor, definition.unit)
    end
end

function Provider.new(framework)
    return setmetatable({
        framework = framework,
        sensors = {},
        activeSensors = {},
        lastValues = {},
        lastPush = {},
        nextDue = {},
        inFlightApiName = nil,
        lastConnected = false,
        lastArmed = false,
        lastModuleNumber = nil,
        connectedAt = 0,
        apiSucceeded = {}
    }, Provider)
end

function Provider:_resetSensorCaches()
    self.sensors = {}
    self.activeSensors = {}
    self.lastValues = {}
    self.lastPush = {}
    self.lastModuleNumber = nil
end

function Provider:_ensureModuleCache()
    local moduleNumber = moduleNumberForSession(self.framework.session)

    if type(moduleNumber) == "number" and self.lastModuleNumber ~= moduleNumber then
        self:_resetSensorCaches()
        self.lastModuleNumber = moduleNumber
    end

    return moduleNumber or self.lastModuleNumber
end

function Provider:_ensureSensor(definition)
    local sensor = self.sensors[definition.appId]
    local moduleNumber = self:_ensureModuleCache()

    if sensor then
        syncSensorMetadata(sensor, definition, moduleNumber)
        return sensor
    end

    sensor = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = definition.appId})
    if sensor then
        syncSensorMetadata(sensor, definition, moduleNumber)
        self.sensors[definition.appId] = sensor
        return sensor
    end

    if type(moduleNumber) ~= "number" then
        return nil
    end

    sensor = model.createSensor({type = SENSOR_TYPE_DIY})
    sensor:appId(definition.appId)
    syncSensorMetadata(sensor, definition, moduleNumber)
    self.sensors[definition.appId] = sensor

    return sensor
end

function Provider:_pushSensorValue(definition, value, now)
    local sensor
    local lastValue
    local useRawValue = utils.ethosVersionAtLeast({26, 1, 0})
    local refreshInterval = FORCE_REFRESH_INTERVAL

    if (self.connectedAt or 0) > 0 and (now - (self.connectedAt or 0)) < INITIAL_FORCE_REFRESH_WINDOW then
        refreshInterval = INITIAL_FORCE_REFRESH_INTERVAL
    end

    if value == nil or not definition then
        return
    end

    sensor = self:_ensureSensor(definition)
    lastValue = self.lastValues[definition.appId]

    if sensor and (value ~= lastValue or (now - (self.lastPush[definition.appId] or 0)) >= refreshInterval) then
        if useRawValue and type(sensor.rawValue) == "function" then
            sensor:rawValue(value)
        else
            sensor:value(value)
        end
        self.lastValues[definition.appId] = value
        self.lastPush[definition.appId] = now
    end
end

function Provider:_applyApiFields(apiName, api)
    local apiMeta = API_DEFS[apiName]
    local session = self.framework.session
    local now = os.clock()
    local fieldName
    local fieldMeta
    local value

    if not apiMeta or not api or not api.readValue then
        return
    end

    for fieldName, fieldMeta in pairs(apiMeta.fields or {}) do
        value = api.readValue(fieldName)
        if value ~= nil then
            if type(fieldMeta.transform) == "function" then
                value = fieldMeta.transform(value)
            end
            if fieldMeta.sessionKey then
                session:set(fieldMeta.sessionKey, value)
            end
            if fieldMeta.sensor then
                self.activeSensors[fieldMeta.sensor.appId] = fieldMeta.sensor
                self:_pushSensorValue(fieldMeta.sensor, value, now)
            end
        end
    end

    self.apiSucceeded[apiName] = true
end

function Provider:seedStartupPlaceholders(now)
    local session = self.framework.session
    local apiMeta = API_DEFS.DATAFLASH_SUMMARY
    local fieldName
    local fieldMeta

    if session:get("isConnected", false) ~= true or session:get("apiVersion", nil) == nil then
        return
    end

    if self.apiSucceeded.DATAFLASH_SUMMARY == true then
        return
    end

    for fieldName, fieldMeta in pairs(apiMeta.fields or {}) do
        if fieldMeta.sensor and fieldMeta.startupValue ~= nil then
            self.activeSensors[fieldMeta.sensor.appId] = fieldMeta.sensor
            if fieldMeta.sessionKey then
                session:set(fieldMeta.sessionKey, fieldMeta.startupValue)
            end
            self:_pushSensorValue(fieldMeta.sensor, fieldMeta.startupValue, now)
        end
    end
end

function Provider:_refreshStaleSensors(now)
    local appId
    local definition
    local value
    local refreshInterval = FORCE_REFRESH_INTERVAL

    if (self.connectedAt or 0) > 0 and (now - (self.connectedAt or 0)) < INITIAL_FORCE_REFRESH_WINDOW then
        refreshInterval = INITIAL_FORCE_REFRESH_INTERVAL
    end

    for appId, definition in pairs(self.activeSensors) do
        value = self.lastValues[appId]
        if value ~= nil and (now - (self.lastPush[appId] or 0)) >= refreshInterval then
            self:_pushSensorValue(definition, value, now)
        end
    end
end

function Provider:refresh(now)
    local session = self.framework.session
    local refreshAt = now or os.clock()

    if session:get("isConnected", false) ~= true or session:get("apiVersion", nil) == nil then
        return
    end

    if (self.connectedAt or 0) <= 0 then
        self.connectedAt = refreshAt
    end

    self:_refreshStaleSensors(refreshAt)
end

function Provider:_intervalFor(apiName, isArmed)
    local apiMeta = API_DEFS[apiName]

    if not apiMeta then
        return nil
    end

    if isArmed then
        return apiMeta.intervalArmed
    end

    return apiMeta.intervalDisarmed
end

function Provider:_ensureSchedule(now, isArmed)
    local apiName
    local interval

    for _, apiName in ipairs(API_ORDER) do
        interval = self:_intervalFor(apiName, isArmed)
        if interval and interval > 0 then
            self.nextDue[apiName] = self.nextDue[apiName] or now
        else
            self.nextDue[apiName] = nil
        end
    end
end

function Provider:_queueApiRead(apiName, now, isArmed)
    local mspTask = self.framework:getTask("msp")
    local api
    local loadErr
    local queued
    local queueErr
    local apiMeta = API_DEFS[apiName]
    local interval = self:_intervalFor(apiName, isArmed)

    if not mspTask or not mspTask.api or not mspTask.api.load then
        return false
    end

    api, loadErr = mspTask.api.load(apiName)
    if not api then
        self.framework.log:warn("[msp-sensors] failed to load API '%s': %s", apiName, tostring(loadErr or "load_failed"))
        self.nextDue[apiName] = now + 1.0
        return false
    end

    self.inFlightApiName = apiName
    api.setUUID("sensors-msp-" .. apiName)
    api.setTimeout(3.0)
    api.setCompleteHandler(function()
        self.inFlightApiName = nil
        self:_applyApiFields(apiName, api)
        if interval and interval > 0 then
            self.nextDue[apiName] = os.clock() + interval
        else
            self.nextDue[apiName] = nil
        end
    end)
    api.setErrorHandler(function(_, errorMessage)
        self.inFlightApiName = nil
        self.nextDue[apiName] = os.clock() + 1.0
        self.framework.log:warn("[msp-sensors] %s read failed: %s", apiName, tostring(errorMessage or "read_failed"))
    end)

    queued, queueErr = api.read()
    if queued ~= true then
        self.inFlightApiName = nil
        self.nextDue[apiName] = now + 1.0
        self.framework.log:warn("[msp-sensors] %s queue failed: %s", apiName, tostring(queueErr or "queue_failed"))
        return false
    end

    return true
end

function Provider:wakeup()
    local session = self.framework.session
    local connected = session:get("isConnected", false) == true
    local isArmed = session:get("isArmed", false) == true
    local mspTask = self.framework:getTask("msp")
    local now = os.clock()
    local connectedEdge = connected and not self.lastConnected
    local disarmEdge = self.lastArmed and not isArmed
    local apiName
    local apiMeta

    if not connected or session:get("apiVersion", nil) == nil then
        self.connectedAt = 0
        self.lastConnected = connected
        self.lastArmed = isArmed
        return
    end

    if connectedEdge then
        self.connectedAt = now
    end

    if not mspTask or not mspTask.mspQueue or session:get("mspBusy", false) == true or mspTask.mspQueue:isProcessed() ~= true then
        self.lastConnected = connected
        self.lastArmed = isArmed
        return
    end

    if self.inFlightApiName ~= nil then
        self.lastConnected = connected
        self.lastArmed = isArmed
        return
    end

    self:_ensureSchedule(now, isArmed)
    self:_refreshStaleSensors(now)

    for _, apiName in ipairs(API_ORDER) do
        apiMeta = API_DEFS[apiName]

        if connectedEdge and apiMeta.onConnect then
            if self:_queueApiRead(apiName, now, isArmed) then
                break
            end
        elseif disarmEdge and apiMeta.onDisarm then
            if self:_queueApiRead(apiName, now, isArmed) then
                break
            end
        elseif self.nextDue[apiName] and now >= self.nextDue[apiName] then
            if self:_queueApiRead(apiName, now, isArmed) then
                break
            end
        end
    end

    self.lastConnected = connected
    self.lastArmed = isArmed
end

function Provider:reset()
    self:_resetSensorCaches()
    self.nextDue = {}
    self.inFlightApiName = nil
    self.lastConnected = false
    self.lastArmed = false
    self.connectedAt = 0
    self.apiSucceeded = {}
end

return Provider
