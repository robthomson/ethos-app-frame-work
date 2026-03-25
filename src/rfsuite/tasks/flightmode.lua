--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local FlightModeTask = {}

local THROTTLE_THRESHOLD = 35

local function isGovernorActive(value)
    return type(value) == "number" and value >= 4 and value <= 8
end

function FlightModeTask:_telemetry()
    return self.framework:getTask("telemetry")
end

function FlightModeTask:_appActive()
    if self.framework and self.framework.isAppActive then
        return self.framework:isAppActive() == true
    end

    return self.framework
        and self.framework.session
        and self.framework.session:get("appActive", false) == true
end

function FlightModeTask:_inFlight()
    local telemetry
    local governor
    local throttle

    if self.framework.session:get("isArmed", false) ~= true then
        return false
    end

    telemetry = self:_telemetry()
    if not telemetry or type(telemetry.getSensor) ~= "function" then
        return false
    end

    governor = telemetry.getSensor("governor")
    if isGovernorActive(governor) then
        return true
    end

    throttle = telemetry.getSensor("throttle_percent")
    return type(throttle) == "number" and throttle > THROTTLE_THRESHOLD
end

function FlightModeTask:_determineMode()
    local session = self.framework.session
    local armed = session:get("isArmed", false)
    local connected = session:get("isConnected", false)
    local current = session:get("currentFlightMode", "preflight")

    if current == "inflight" and not connected then
        self.hasBeenInFlight = false
        self.lastArmed = armed
        return "postflight"
    end

    if armed and not self.lastArmed then
        self.hasBeenInFlight = false
        self.lastArmed = armed
        return "preflight"
    end

    if self:_inFlight() then
        self.hasBeenInFlight = true
        self.lastArmed = armed
        return "inflight"
    end

    self.lastArmed = armed
    return self.hasBeenInFlight and "postflight" or "preflight"
end

function FlightModeTask:_resetState()
    self.lastFlightMode = nil
    self.hasBeenInFlight = false
    self.lastArmed = self.framework.session:get("isArmed", false)
end

function FlightModeTask:init(framework)
    self.framework = framework
    self:_resetState()

    framework:on("onconnect", function()
        self:_resetState()
    end)
end

function FlightModeTask:wakeup()
    if self:_appActive() then
        return
    end

    local mode = self:_determineMode()

    if mode ~= self.lastFlightMode then
        self.framework.session:setMultiple({
            flightMode = mode,
            currentFlightMode = mode
        })
        self.framework:_emit("flightmode:changed", mode)
        self.framework.log:info("Flight mode: %s", mode)
        self.lastFlightMode = mode
    end
end

return FlightModeTask
