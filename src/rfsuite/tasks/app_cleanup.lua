--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local AppCleanupTask = {}

local function setCleanupState(session, values)
    local setter = session and (session.setMultipleSilent or session.setMultiple)

    if type(setter) ~= "function" then
        return false
    end

    return pcall(setter, session, values)
end

function AppCleanupTask:init(framework)
    self.framework = framework
end

function AppCleanupTask:wakeup()
    local session = self.framework and self.framework.session or nil
    local now
    local dueAt

    if not session then
        return
    end

    if session:get("appCleanupPending", false) ~= true then
        return
    end

    if self.framework:isAppActive() == true then
        setCleanupState(session, {
            appCleanupPending = false,
            appCleanupDueAt = 0,
            appCleanupReason = "cancelled"
        })
        return
    end

    if session:get("appResident", false) ~= true or self.framework:getApp() == nil then
        setCleanupState(session, {
            appCleanupPending = false,
            appCleanupDueAt = 0,
            appCleanupReason = "not_resident"
        })
        return
    end

    now = os.clock()
    dueAt = tonumber(session:get("appCleanupDueAt", 0)) or 0
    if dueAt > now then
        return
    end

    if pcall(self.framework.releaseInactiveApp, self.framework, "idle_cleanup") and self.framework:getApp() == nil then
        setCleanupState(session, {
            appCleanupPending = false,
            appCleanupDueAt = 0,
            appCleanupLastAt = now,
            appCleanupReason = "idle_cleanup",
            appCleanupRuns = (tonumber(session:get("appCleanupRuns", 0)) or 0) + 1
        })
    else
        setCleanupState(session, {
            appCleanupPending = false,
            appCleanupDueAt = 0,
            appCleanupReason = "failed"
        })
    end
end

function AppCleanupTask:close()
    self.framework = nil
end

return AppCleanupTask
