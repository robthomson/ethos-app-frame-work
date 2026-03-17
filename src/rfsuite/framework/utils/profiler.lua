--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Lightweight development profiler for background task timing and Lua memory.
]] --

local profiler = {}

local function memoryCountKB()
    if type(collectgarbage) ~= "function" then
        return 0
    end

    local ok, value = pcall(collectgarbage, "count")
    if ok then
        return value or 0
    end

    return 0
end

local function getMemoryUsage()
    if not system or type(system.getMemoryUsage) ~= "function" then
        return nil
    end

    local ok, value = pcall(system.getMemoryUsage)
    if ok and type(value) == "table" then
        return value
    end

    return nil
end

function profiler.new(options)
    options = options or {}

    local memstats = options.memstats == true
    local taskprofiler = options.taskprofiler == true

    return {
        enabled = memstats or taskprofiler,
        memstats = memstats,
        taskprofiler = taskprofiler,
        dumpInterval = options.dumpInterval or 10,
        minDuration = options.minDuration or 0,
        lastDumpAt = 0,
        tasks = {},
        loop = {
            lastMs = 0,
            avgMs = 0,
            maxMs = 0,
            totalMs = 0,
            runs = 0
        },
        memory = {
            startKB = memoryCountKB(),
            currentKB = 0,
            peakKB = 0,
            deltaKB = 0,
            systemFreeKB = 0,
            luaFreeKB = 0
        }
    }
end

function profiler:beginLoop(state)
    if not state or not state.enabled then
        return nil
    end

    return {startedAt = os.clock()}
end

function profiler:recordTask(state, name, interval, durationSeconds)
    if not state or not state.taskprofiler then
        return
    end

    if durationSeconds < (state.minDuration or 0) then
        return
    end

    local entry = state.tasks[name]
    if not entry then
        entry = {
            name = name,
            interval = interval or 0,
            lastMs = 0,
            maxMs = 0,
            totalMs = 0,
            runs = 0
        }
        state.tasks[name] = entry
    end

    local durationMs = durationSeconds * 1000.0
    entry.interval = interval or entry.interval or 0
    entry.lastMs = durationMs
    entry.totalMs = entry.totalMs + durationMs
    entry.runs = entry.runs + 1
    entry.maxMs = math.max(entry.maxMs or 0, durationMs)
end

function profiler:_updateMemory(state)
    if not state or not state.memstats then
        return
    end

    local currentKB = memoryCountKB()
    local memUsage = getMemoryUsage()
    state.memory.currentKB = currentKB
    state.memory.peakKB = math.max(state.memory.peakKB or 0, currentKB)
    state.memory.deltaKB = currentKB - (state.memory.startKB or 0)
    state.memory.systemFreeKB = memUsage and ((memUsage.ramAvailable or 0) / 1024) or 0
    state.memory.luaFreeKB = memUsage and ((memUsage.luaRamAvailable or 0) / 1024) or 0
end

function profiler:_updateLoop(state, startedAt)
    if not state or not startedAt then
        return
    end

    local durationMs = (os.clock() - startedAt) * 1000.0
    local loop = state.loop
    loop.lastMs = durationMs
    loop.totalMs = loop.totalMs + durationMs
    loop.runs = loop.runs + 1
    loop.maxMs = math.max(loop.maxMs or 0, durationMs)
    loop.avgMs = loop.totalMs / math.max(loop.runs, 1)
end

function profiler:getTaskSnapshot(state)
    local snapshot = {}

    if not state or not state.taskprofiler then
        return snapshot
    end

    for name, entry in pairs(state.tasks) do
        snapshot[#snapshot + 1] = {
            name = name,
            interval = entry.interval or 0,
            lastMs = entry.lastMs or 0,
            maxMs = entry.maxMs or 0,
            totalMs = entry.totalMs or 0,
            runs = entry.runs or 0,
            avgMs = (entry.runs or 0) > 0 and ((entry.totalMs or 0) / entry.runs) or 0
        }
    end

    table.sort(snapshot, function(a, b)
        return a.avgMs > b.avgMs
    end)

    return snapshot
end

function profiler:getTopTask(state)
    local bestName = nil
    local bestEntry = nil
    local bestAvg = nil

    if not state or not state.taskprofiler then
        return nil
    end

    for name, entry in pairs(state.tasks) do
        local runs = entry.runs or 0
        local avg = runs > 0 and ((entry.totalMs or 0) / runs) or 0

        if bestAvg == nil or avg > bestAvg then
            bestAvg = avg
            bestName = name
            bestEntry = entry
        end
    end

    if not bestEntry then
        return nil
    end

    return {
        name = bestName,
        interval = bestEntry.interval or 0,
        lastMs = bestEntry.lastMs or 0,
        maxMs = bestEntry.maxMs or 0,
        totalMs = bestEntry.totalMs or 0,
        runs = bestEntry.runs or 0,
        avgMs = bestAvg or 0
    }
end

function profiler:getSummary(state)
    if not state then
        return nil
    end

    local snapshot = self:getTaskSnapshot(state)
    local topTask = self:getTopTask(state)

    return {
        enabled = state.enabled,
        memstats = state.memstats,
        taskprofiler = state.taskprofiler,
        loop = {
            lastMs = state.loop.lastMs or 0,
            avgMs = state.loop.avgMs or 0,
            maxMs = state.loop.maxMs or 0,
            runs = state.loop.runs or 0
        },
        memory = {
            currentKB = state.memory.currentKB or 0,
            peakKB = state.memory.peakKB or 0,
            deltaKB = state.memory.deltaKB or 0,
            systemFreeKB = state.memory.systemFreeKB or 0,
            luaFreeKB = state.memory.luaFreeKB or 0
        },
        topTask = topTask,
        taskCount = #snapshot
    }
end

function profiler:dump(state, logger)
    if not state or not state.enabled then
        return
    end

    local summary = self:getSummary(state)
    local snapshot = self:getTaskSnapshot(state)
    local emit = logger or print

    emit("====== Dev Profile ======")
    emit(string.format(
        "Loop: last=%.3fms avg=%.3fms max=%.3fms runs=%d",
        summary.loop.lastMs,
        summary.loop.avgMs,
        summary.loop.maxMs,
        summary.loop.runs
    ))

    if state.memstats then
        emit(string.format(
            "Lua: current=%.1fKB peak=%.1fKB delta=%.1fKB",
            summary.memory.currentKB,
            summary.memory.peakKB,
            summary.memory.deltaKB
        ))
        emit(string.format(
            "Free RAM: system=%.1fKB lua=%.1fKB",
            summary.memory.systemFreeKB,
            summary.memory.luaFreeKB
        ))
    end

    if state.taskprofiler then
        for _, entry in ipairs(snapshot) do
            emit(string.format(
                "%-12s avg=%8.3fms last=%8.3fms max=%8.3fms runs=%5d int=%5.3fs",
                entry.name,
                entry.avgMs,
                entry.lastMs,
                entry.maxMs,
                entry.runs,
                entry.interval
            ))
        end
    end

    emit("=========================")
end

function profiler:endLoop(state, token, logger)
    if not state or not state.enabled then
        return nil
    end

    self:_updateMemory(state)
    self:_updateLoop(state, token and token.startedAt)

    local now = os.clock()
    if state.dumpInterval > 0 and (now - (state.lastDumpAt or 0)) >= state.dumpInterval then
        self:dump(state, logger)
        state.lastDumpAt = now
    end

    return self:getSummary(state)
end

return profiler
