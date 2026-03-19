--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Callback System
  
  CPU-aware callback queue with budget management.
  Supports immediate, delayed, and repeating callbacks.
  
  Usage:
    callback:now(func)
    callback:inSeconds(5, func)
    callback:every(1.5, func)
    callback:wakeup({maxCalls=16, budgetMs=4, category="render"})
]] --

local callback = {}
local log = require("framework.utils.log")

-- Local globals for performance
local os_clock = os.clock
local table_insert = table.insert
local table_remove = table.remove

local function copyTable(source)
    local out = {}
    local key
    local value

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
end

callback._queues = {
    immediate = {},
    timer = {},
}

callback._budgets = {
    immediate = {maxCalls = 32, budgetMs = 10},
    timer = {maxCalls = 16, budgetMs = 5},
    render = {maxCalls = 20, budgetMs = 8},
    events = {maxCalls = 24, budgetMs = 6},
    default = {maxCalls = 16, budgetMs = 4},
}

local callback_mt = {__index = callback}

-- Entry structure: {time=nil, func=func, interval=nil, category=category}

--[[ API ]]

function callback:now(func, category)
    category = category or "immediate"
    if not self._queues[category] then
        self._queues[category] = {}
    end
    table_insert(self._queues[category], {
        time = nil,
        func = func,
        interval = nil
    })
end

function callback:inSeconds(seconds, func, category)
    category = category or "timer"
    if not self._queues[category] then
        self._queues[category] = {}
    end
    table_insert(self._queues[category], {
        time = os_clock() + seconds,
        func = func,
        interval = nil
    })
end

function callback:every(seconds, func, category)
    category = category or "timer"
    if not self._queues[category] then
        self._queues[category] = {}
    end
    table_insert(self._queues[category], {
        time = os_clock() + seconds,
        func = func,
        interval = seconds
    })
end

function callback:wakeup(options)
    options = options or {}
    local category = options.category or "default"
    local maxCalls = options.maxCalls
    local budgetMs = options.budgetMs
    
    local budget = self._budgets[category] or self._budgets.default
    maxCalls = maxCalls or budget.maxCalls
    budgetMs = budgetMs or budget.budgetMs
    
    local queues = options.categories or {category}
    
    for _, cat in ipairs(queues) do
        self:_processQueue(cat, maxCalls, budgetMs)
    end
end

function callback:wakeupAll(options)
    options = options or {}
    options.categories = {}
    for cat, _ in pairs(self._queues) do
        table_insert(options.categories, cat)
    end
    self:wakeup(options)
end

function callback:_processQueue(category, maxCalls, budgetMs)
    if not self._queues[category] then
        return
    end
    
    local queue = self._queues[category]
    local now = os_clock()
    local deadline = (budgetMs and budgetMs > 0) and (now + budgetMs / 1000) or nil
    local processed = 0
    local i = 1
    
    while i <= #queue and processed < maxCalls do
        if deadline and os_clock() >= deadline then
            break
        end
        
        local entry = queue[i]
        
        -- Check if it's time to execute
        if not entry.time or entry.time <= now then
            local ok, err = pcall(entry.func)
            if not ok then
                log:error("Callback error: %s", tostring(err))
            end
            
            -- Handle repeating callbacks
            if entry.interval then
                entry.time = now + entry.interval
                i = i + 1
                processed = processed + 1
            else
                table_remove(queue, i)
                processed = processed + 1
            end
        else
            i = i + 1
        end
    end
end

function callback:clear(func)
    for _, queue in pairs(self._queues) do
        for i = #queue, 1, -1 do
            if queue[i].func == func then
                table_remove(queue, i)
            end
        end
    end
end

function callback:clearAll()
    for _, queue in pairs(self._queues) do
        for i = #queue, 1, -1 do
            queue[i] = nil
        end
    end
end

function callback:reset()
    self:clearAll()
end

function callback:setBudget(category, maxCalls, budgetMs)
    self._budgets[category] = {
        maxCalls = maxCalls,
        budgetMs = budgetMs
    }
end

function callback:getStats()
    local total = 0
    for _, queue in pairs(self._queues) do
        total = total + #queue
    end
    return {
        totalQueued = total,
        queues = self._queues
    }
end

function callback.new(options)
    local opts = options or {}
    local instance = setmetatable({
        _queues = copyTable(opts.queues or callback._queues),
        _budgets = copyTable(opts.budgets or callback._budgets)
    }, callback_mt)

    return instance
end

return callback
