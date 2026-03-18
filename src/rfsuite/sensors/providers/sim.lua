--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local Provider = {}
Provider.__index = Provider

local FORCE_REFRESH_INTERVAL = 2.0

local function syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
    if not sensor then
        return
    end

    if name ~= nil then
        pcall(sensor.name, sensor, name)
    end
    if moduleNumber ~= nil then
        pcall(sensor.module, sensor, moduleNumber)
    end
    if minValue ~= nil then
        pcall(sensor.minimum, sensor, minValue)
    end
    if maxValue ~= nil then
        pcall(sensor.maximum, sensor, maxValue)
    end
    if unit ~= nil then
        pcall(sensor.unit, sensor, unit)
        pcall(sensor.protocolUnit, sensor, unit)
    end
    if decimals ~= nil then
        pcall(sensor.decimals, sensor, decimals)
        pcall(sensor.protocolDecimals, sensor, decimals)
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

function Provider:_ensureSensor(uid, name, unit, decimals, minValue, maxValue)
    local sensor = self.sensors[uid]
    local moduleNumber

    moduleNumber = moduleNumberForSession(self.framework.session)

    if sensor then
        syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
        return sensor
    end

    sensor = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = uid})
    if sensor then
        syncSensorMetadata(sensor, name, unit, decimals, minValue, maxValue, moduleNumber)
        self.sensors[uid] = sensor
        return sensor
    end

    sensor = model.createSensor({type = SENSOR_TYPE_DIY})
    sensor:appId(uid)
    syncSensorMetadata(
        sensor,
        name,
        unit,
        decimals,
        minValue or -1000000000,
        maxValue or 2147483647,
        moduleNumber
    )

    self.sensors[uid] = sensor
    return sensor
end

function Provider:wakeup()
    local telemetry = self.framework:getTask("telemetry")
    local sensorList
    local i
    local descriptor
    local sensor
    local value
    local now = os.clock()
    local useRawValue = utils.ethosVersionAtLeast({26, 1, 0})

    if not telemetry or not telemetry.simSensors then
        return
    end

    sensorList = telemetry.simSensors()
    for i = 1, #sensorList do
        descriptor = sensorList[i]
        sensor = self:_ensureSensor(
            descriptor.sensor.uid,
            descriptor.name,
            descriptor.sensor.unit,
            descriptor.sensor.dec,
            descriptor.sensor.min,
            descriptor.sensor.max
        )

        if sensor then
            if type(descriptor.sensor.value) == "function" then
                value = descriptor.sensor.value()
            else
                value = descriptor.sensor.value
            end

            if value ~= self.lastValues[descriptor.sensor.uid]
                or (now - (self.lastPush[descriptor.sensor.uid] or 0)) >= FORCE_REFRESH_INTERVAL then
                if useRawValue and type(sensor.rawValue) == "function" then
                    sensor:rawValue(value)
                else
                    sensor:value(value)
                end
                self.lastValues[descriptor.sensor.uid] = value
                self.lastPush[descriptor.sensor.uid] = now
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
