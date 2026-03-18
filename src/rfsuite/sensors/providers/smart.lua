--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local Provider = {}
Provider.__index = Provider

local SENSOR_DEFS = {
    smartfuel = {
        appId = 0x5FE1,
        name = "Smart Fuel",
        unit = UNIT_PERCENT,
        min = 0,
        max = 100
    },
    smartconsumption = {
        appId = 0x5FE0,
        name = "Smart Consumption",
        unit = UNIT_MILLIAMPERE_HOUR,
        min = 0,
        max = 1000000000
    }
}

local FORCE_REFRESH_INTERVAL = 2.0

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

local function moduleNumberForSession(session)
    local source = session:get("telemetrySensor", nil)

    if source and type(source.module) == "function" then
        return source:module()
    end

    return 0
end

function Provider.new(framework)
    return setmetatable({
        framework = framework,
        sensors = {},
        lastValues = {},
        lastPush = {}
    }, Provider)
end

function Provider:_ensureSensor(definition)
    local sensor = self.sensors[definition.appId]
    local moduleNumber

    moduleNumber = moduleNumberForSession(self.framework.session)

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

    sensor = model.createSensor({type = SENSOR_TYPE_DIY})
    sensor:appId(definition.appId)
    syncSensorMetadata(sensor, definition, moduleNumber)

    self.sensors[definition.appId] = sensor
    return sensor
end

function Provider:wakeup()
    local telemetry = self.framework:getTask("telemetry")
    local key
    local definition
    local sensor
    local value
    local now = os.clock()
    local useRawValue = utils.ethosVersionAtLeast({26, 1, 0})

    if not telemetry or not telemetry.getSensor then
        return
    end

    if not (self.framework.session:get("telemetryState", false) or (system and system.getVersion and system.getVersion().simulation == true)) then
        return
    end

    for key, definition in pairs(SENSOR_DEFS) do
        value = telemetry.getSensor(key)
        if value ~= nil then
            sensor = self:_ensureSensor(definition)
            if sensor and (value ~= self.lastValues[definition.appId]
                or (now - (self.lastPush[definition.appId] or 0)) >= FORCE_REFRESH_INTERVAL) then
                if useRawValue and type(sensor.rawValue) == "function" then
                    sensor:rawValue(value)
                else
                    sensor:value(value)
                end
                self.lastValues[definition.appId] = value
                self.lastPush[definition.appId] = now
            end
        end
    end
end

function Provider:reset()
    self.sensors = {}
    self.lastValues = {}
    self.lastPush = {}
end

return Provider
