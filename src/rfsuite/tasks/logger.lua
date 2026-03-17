--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local LoggerTask = {}

function LoggerTask:init(framework)
    self.framework = framework
    self._sessionValues = {}
    self.framework.log:info("[Logger] Task initialized")
end

function LoggerTask:wakeup()
    local log
    local values

    if not self.framework or not self.framework.log then
        return
    end

    if self.framework.session:get("mspBusy", false) then
        return
    end

    log = self.framework.log
    values = self._sessionValues

    log:process()
    values.logQueueDepth = log._consoleQueue and log._consoleQueue.count or 0
    values.logConnectDepth = log._connectQueue and log._connectQueue.count or 0
    values.logDroppedConsole = log._consoleQueue and log._consoleQueue.dropped or 0
    values.logDroppedConnect = log._connectQueue and log._connectQueue.dropped or 0
    values.logLevel = log._config and log._config.minLevel or "info"
    self.framework.session:setMultiple(values)
end

function LoggerTask:close()
    if self.framework and self.framework.log then
        self.framework.log:info("[Logger] Task closing")
        self.framework.log:flush()
    end
    self.framework = nil
end

return LoggerTask
