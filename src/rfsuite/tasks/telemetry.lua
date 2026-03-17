--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Example Background Task - Telemetry
  
  This demonstrates how to write a background task:
  - Initialize with :init(framework)
  - Implements :wakeup() for periodic execution
  - Implements :close() for cleanup
  - Uses framework.callback for delayed operations
  - Emits events for app to listen to
]] --

local TelemetryTask = {}

function TelemetryTask:init(framework)
    self.framework = framework
    self.connected = true
    self.lastUpdate = 0
    self.updateInterval = 0.1  -- 100ms
    self.counter = 0
    
    -- Subscribe to connection events
    framework:on("connection:state", function(isConnected)
        self.connected = isConnected
    end)
    
    self.framework.log:info("[Telemetry] Task initialized")
end

function TelemetryTask:wakeup()
    local now = os.clock()
    
    -- Avoid updating too frequently
    if (now - self.lastUpdate) < self.updateInterval then
        return
    end
    
    self.lastUpdate = now

    self.counter = self.counter + 1

    local data = {
        voltage = 12 + ((self.counter % 8) * 0.1),
        current = 5 + ((self.counter % 5) * 0.2),
        temperature = 40 + (self.counter % 6)
    }

    self.framework.session:setMultiple({
        telemetryConnected = self.connected,
        telemetryVoltage = data.voltage,
        telemetryCurrent = data.current,
        telemetryTemperature = data.temperature,
        telemetryUpdates = self.framework.session:get("telemetryUpdates", 0) + 1,
        telemetryLastUpdate = now
    })

    self.framework:_emit("connection:state", self.connected)
    self.framework:_emit("telemetry:updated", data)
end

function TelemetryTask:close()
    self.framework.log:info("[Telemetry] Task closing")
    self.framework = nil
end

return TelemetryTask
