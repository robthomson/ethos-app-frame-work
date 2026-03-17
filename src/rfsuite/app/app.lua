--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Example Application Module
  
  Demonstrates how to implement an app:
  - Implements :init(framework) for initialization
  - Implements :wakeup() for periodic updates
  - Implements :paint() for rendering
  - Implements :close() for cleanup
  - Uses framework:on() to subscribe to events from tasks
]] --

local App = {}

function App:init(framework)
    self.framework = framework
    self.currentPage = "home"
    self.connectionState = "disconnected"
    self.backgroundState = "waiting"
    self.backgroundAge = 0
    self.telemetryType = "disconnected"
    self.apiVersion = "n/a"
    self.mspQueueDepth = 0
    self.mspBusy = false
    self.mspProtocolVersion = 1
    self.luaMemoryKB = 0
    self.luaMemoryPeakKB = 0
    self.taskLoopAvgMs = 0
    
    self.framework.log:info("[App] Initialized")
end

function App:wakeup()
    local connected
    local connecting

    if self.framework and self.framework.session then
        connected = self.framework.session:get("isConnected", false) == true
        connecting = self.framework.session:get("isConnecting", false) == true
        self.backgroundState = self.framework.session:get("backgroundState", "waiting")
        self.backgroundAge = self.framework.session:get("backgroundAge", -1)
        self.telemetryType = connected and self.framework.session:get("mspTransport", "disconnected") or "disconnected"
        self.apiVersion = connected and (self.framework.session:get("apiVersion", nil) or "n/a") or "n/a"
        self.mspQueueDepth = self.framework.session:get("mspQueueDepth", 0)
        self.mspBusy = self.framework.session:get("mspBusy", false)
        self.mspProtocolVersion = connected and self.framework.session:get("mspProtocolVersion", 1) or 1
        self.luaMemoryKB = self.framework.session:get("luaMemoryKB", 0)
        self.luaMemoryPeakKB = self.framework.session:get("luaMemoryPeakKB", 0)
        self.taskLoopAvgMs = self.framework.session:get("taskLoopAvgMs", 0)
        if connected then
            self.connectionState = "connected"
        elseif connecting then
            self.connectionState = "connecting"
        else
            self.connectionState = "disconnected"
        end
    end

    -- Update app state based on telemetry
    if self.framework and self.framework.session:get("isConnected", false) then
        -- Check for user input, page navigation, etc.
    end
end

function App:paint()
    -- Render UI - stub for now
    if lcd then
        lcd.color(lcd.RGB(255, 255, 255))
        lcd.font(FONT_STD)
        lcd.drawText(10, 10, "Rotorflight - " .. self.currentPage)
        lcd.drawText(10, 30, "State: " .. tostring(self.connectionState))
        lcd.drawText(10, 50, "Transport: " .. tostring(self.telemetryType))
        lcd.drawText(10, 70, "API: " .. tostring(self.apiVersion) .. " / MSP v" .. tostring(self.mspProtocolVersion))
        lcd.drawText(10, 90, "Queue: " .. tostring(self.mspQueueDepth) .. (self.mspBusy and " busy" or " idle"))
        lcd.drawText(10, 110, "Background: " .. tostring(self.backgroundState))
        if self.backgroundAge and self.backgroundAge >= 0 then
            lcd.drawText(10, 130, string.format("BG age: %.2fs", self.backgroundAge))
        end
        lcd.drawText(10, 150, string.format("Lua: %.1fKB (peak %.1fKB)", self.luaMemoryKB, self.luaMemoryPeakKB))
        lcd.drawText(10, 170, string.format("Loop avg: %.3fms", self.taskLoopAvgMs))
    end
end

function App:onActivate()
    self.framework.log:info("[App] Activated")
end

function App:onDeactivate()
    self.framework.log:info("[App] Deactivated")
end

function App:close()
    self.framework.log:info("[App] Closing")
    self.framework = nil
end

return App
