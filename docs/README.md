# Rotorflight Ethos Lua Framework

A ground-up rethink of the Rotorflight Ethos Lua architecture focused on **decentralization**, **resource efficiency**, and **callback-driven design**.

## Licensing

The framework source under `src/rfsuite` is part of the Rotorflight project and is intended to carry a Rotorflight GPLv3 file header consistently across the Lua source tree.

Header convention:

```lua
--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --
```

When adding new Lua modules, keep that header in place at the top of the file so source provenance and licensing stay explicit.

## Foundations

The current base is organized around three central shared services:

- `framework.session`
  The single runtime state store for live values.
- `framework.preferences`
  The central store for global persistent preferences.
- `runtime.lua`
  The composition root that seeds defaults and wires tasks/apps/widgets together.

Model-specific preferences are still intentionally separate from global preferences. They are loaded after `mcu_id` is known during `onconnect`, then exposed through session as `modelPreferences`.

## Quick Start

### 1. Basic Framework Setup

```lua
local framework = require("framework.core.init")

-- Initialize with configuration
framework:init({
    toolName = "Rotorflight",
    version = "2.4.0"
})

-- Register background tasks
framework:registerTask("telemetry", TelemetryTask, {
    priority = 20,
    interval = 0.1
})

-- Register app
framework:registerApp(App)
framework:activateApp()
```

### 2. Implement a Background Task

```lua
local MyTask = {}

function MyTask:init(framework)
    self.framework = framework
    -- One-time setup
end

function MyTask:wakeup()
    -- Called periodically based on interval
    -- Keep this fast and bounded
end

function MyTask:close()
    -- Cleanup resources
end

return MyTask
```

### 3. Implement an App

```lua
local App = {}

function App:init(framework)
    self.framework = framework
    
    -- Subscribe to events
    framework:on("event:name", function(data)
        -- Handle event
    end)
end

function App:wakeup()
    -- Update state, check inputs
end

function App:paint()
    -- Render UI
end

function App:close()
    -- Cleanup
end

return App
```

### 4. Use Ethos Loop

```lua
function wakeup()
    framework:wakeup()
    lcd.invalidate()
end

function paint()
    framework:paint()
end

function close()
    framework:close()
end
```

## Architecture Overview

### Core Principles

1. **Locals First**: Each module is LOCAL, only expose through framework
2. **Globals for Shared State Only**: `config`, `session`, `preferences`
3. **Event-Driven**: Decoupled communication via events, not direct calls
4. **Callback-Based**: Asynchronous operations with CPU budgeting
5. **Lazy Loading**: Load modules only when needed

### Component Breakdown

#### Framework Core (`framework/core/`)

- **`init.lua`** - Main framework, coordinates everything
- **`callback.lua`** - CPU-aware callback queue
- **`session.lua`** - Runtime state with watchers
- **`registry.lua`** - Module/task registration with lazy loading

#### Events (`framework/events/`)

- **`events.lua`** - Pub/Sub event system for decoupling

#### Utilities (`framework/utils/`)

- **`log.lua`** - Structured logging
- Additional utilities for memory, performance profiling

#### Application (`app/`)

- **`app.lua`** - Main app module

#### Tasks (`tasks/`)

- **`telemetry.lua`** - Telemetry polling task
- **`msp.lua`** - MSP protocol task
- Additional background tasks

### Execution Flow

```
┌─────────────────────────────────────────────┐
│Ethos wakeup()                              │
└────────────┬────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────┐
│framework:wakeup()                          │
├─────────────────────────────────────────────┤
│ 1. Update task timings                      │
│ 2. Wakeup tasks (with interval checks)      │
│ 3. Process callbacks (timers, events)       │
│ 4. Wakeup app (if active)                   │
└──────────────┬────────────────────────────┬─┘
               │                            │
               ▼                            ▼
       ┌──────────────┐         ┌─────────────────┐
       │Background    │         │App Module       │
       │Tasks         │         │- Pages          │
       │- Telemetry   │         │- Forms          │
       │- MSP         │         │- Dialogs        │
       │- Events      │         └─────────────────┘
       └──────┬───────┘
              │
              ▼
    ┌────────────────────┐
    │Emit Events         │
    │(Task completion)   │
    └────────┬───────────┘
             │
             ▼
    ┌─────────────────────────┐
    │App Receives Event       │
    │Updates UI State         │
    └─────────────────────────┘
```

## Event System

Use events for decoupled communication between modules:

```lua
-- Task emits event
framework:_emit("connection:state", true)

-- App listens
framework:on("connection:state", function(connected)
    print("Connected:", connected)
end)

-- One-time listener
framework:once("startup:complete", function()
    print("Startup done")
end)

-- Unsubscribe
local handler = function(data) print(data) end
framework:on("event", handler)
framework:off("event", handler)
```

## Callback System

Queue functions with CPU budgeting:

```lua
-- Immediate execution (next callback cycle)
framework:callbackNow(function()
    print("Run immediately")
end)

-- Delayed execution
framework:callbackInSeconds(5, function()
    print("Run after 5 seconds")
end)

-- Repeating callback
framework:callbackEvery(1.0, function()
    print("Run every 1 second")
end)

-- Configure budgets per category
framework.callback:setBudget("render", 20, 8)   -- 20 calls, 8ms max
framework.callback:setBudget("immediate", 32, 10)
```

## Session Management

Runtime state with change tracking:

```lua
-- Set values
framework.session:set("activeProfile", 1)
framework.session:setMultiple({
    voltage = 12.5,
    current = 5.2
})

-- Get values
local profile = framework.session:get("activeProfile")
local defaults = framework.session:get("undefined", 0)

-- Watch for changes
framework.session:watch("activeProfile", function(old, new)
    print("Profile changed:", old, "->", new)
end)

-- Get all values
local allState = framework.session:dump()
```

## Task Scheduling

Register background tasks with priority and interval:

```lua
framework:registerTask("telemetry", TelemetryTask, {
    priority = 20,      -- Higher = earlier execution
    interval = 0.1,     -- Wakeup every 100ms
    enabled = true,
    lazy = false        -- Load immediately
})

-- Task wakeups are coordinated with interval checking:
-- - Task only wakes if (now - lastWakeup) >= interval
-- - All wakeups respect CPU budget
-- - Tasks processed in priority order
```

## Memory & CPU Optimization

### Memory Strategy

1. **Lazy Loading**: Don't load tasks until needed
   ```lua
   framework:registerTask("heavy", HeavyTask, {lazy = true, file = "tasks/heavy.lua"})
   local task = framework:getTask("heavy")  -- Loaded only here
   ```

2. **Explicit Cleanup**: Close modules when done
   ```lua
   function MyTask:close()
       self.data = {}
       self.framework = nil
   end
   ```

3. **Object Reuse**: Reuse tables instead of creating new ones
   ```lua
   -- ✅ GOOD: Reuse buffer
   self.dataBuffer = {}
   function update()
       table.clear(self.dataBuffer)  -- Clear in-place
       -- Refill buffer
   end
   
   -- ❌ AVOID: Create new table
   function update()
       local newData = {}  -- Allocates every time
   end
   ```

### CPU Strategy

1. **Callback Budgets**: Each category has separate budget
   ```lua
   framework.callback:setBudget("render", 20, 8)   -- 20 calls, 8ms
   framework.callback:setBudget("events", 24, 6)   -- 24 calls, 6ms
   ```

2. **Task Intervals**: Don't wake too frequently
   ```lua
   -- Good: 100ms interval
   framework:registerTask("msensor", SensorTask, {interval = 0.1})
   
   -- Avoid: 1ms interval (too much wakeup overhead)
   ```

3. **Batch Operations**: Group related work
   ```lua
   function Task:wakeup()
       -- Do related work in one wakeup
       self:updateTelemetry()
       self:checkAlarms()
       self:updateDisplay()
   end
   ```

## Best Practices

### ✅ DO

```lua
-- Use locals for module state
local MyModule = {}
local state = {}

-- Register with framework
framework:registerApp(MyModule)

-- Emit events for decoupling
framework:_emit("state:changed", newValue)

-- Use callbacks for async operations
framework:callbackInSeconds(5, function()
    -- Deferred work
end)

-- Subscribe to events
framework:on("connection:state", handler)

-- Clean up resources
function MyModule:close()
    framework:off("connection:state", handler)
    state = {}
end
```

### ❌ DON'T

```lua
-- Don't use globals
_G.myvar = value         -- WRONG!
myvar = value            -- Also wrong (creates global)

-- Don't directly call other modules (tight coupling)
OtherModule:doSomething()   -- WRONG!

-- Don't do heavy work in wakeup
function wakeup()
    for i = 1, 10000 do         -- WRONG!
        -- Blocks everything
    end
end

-- Don't forget cleanup
function close()
    -- Always cleanup!
end

-- Don't ignore CPU budget
framework.callback:setBudget("render", 1000, 100)  -- Too generous
```

## Monitoring & Stats

Get framework statistics:

```lua
local stats = framework:getStats()
print("Initialized:", stats.initialized)
print("App Active:", stats.appActive)
print("Tasks:", stats.tasksCount)
print("Callbacks Queued:", stats.callbackStats.totalQueued)

framework:printStats()
```

## Migration from Global Approach

### Before (Monolithic)
```lua
_G.rfsuite = {}
_G.rfsuite.app = {...}
_G.rfsuite.tasks = {...}
_G.rfsuite.state = {...}

-- Everything in global, hard to reason about
```

### After (Framework)
```lua
local App = require("app.app")
local Framework = require("framework")

Framework:registerApp(App)

-- Clear separation, easy to follow
```

## File Structure

```
src/
├── main.lua                          -- Entry point for Ethos
├── framework/
│   ├── core/
│   │   ├── init.lua                 -- Framework coordinator
│   │   ├── callback.lua             -- CPU budget callback queue
│   │   ├── session.lua              -- Runtime state
│   │   └── registry.lua             -- Module registration
│   ├── events/
│   │   └── events.lua               -- Event pub/sub
│   └── utils/
│       ├── log.lua                  -- Logging
│       └── ...
├── app/
│   └── app.lua                      -- App module
└── tasks/
    ├── telemetry.lua                -- Telemetry task
    ├── msp.lua                      -- MSP task
    └── ...
```

## Next Steps

1. **Implement Core MSP Handler**: Replace stub MSP task with actual protocol
2. **Add Page/Form System**: Create page base class and form rendering
3. **Implement Menu Navigation**: Build hierarchical menu system
4. **Add Telemetry Display**: Real telemetry parsing and widgets
5. **Optimize Memory**: Profile and optimize based on real hardware
6. **Add Error Recovery**: Graceful error handling and recovery

## References

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Detailed architecture guide
- [rfsuite Implementation](../rotorflight-lua-ethos-suite/) - Reference modern implementation
- [Betaflight Suite](../betaflight-ethos-suite/) - Alternative implementation
