# Rotorflight Ethos Lua - New Architecture Framework

## Overview

This framework reimagines the Rotorflight Ethos Lua architecture to address critical issues:
- **Decentralization**: Move from monolithic global state to locally-scoped modules
- **Resource Efficiency**: Strict CPU and RAM budgeting across all components  
- **Callback-Driven**: Event-driven architecture for loose coupling
- **Lazy Loading**: Only load what's needed, when it's needed
- **Explicit Cleanup**: Resource management and lifecycle control

## Core Principles

### Source File Convention

All Lua source files in `src/rfsuite` should carry the Rotorflight GPLv3 header at the top of the file. This is part of the project convention now, not a one-off migration detail.

```lua
--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --
```

### Runtime Ownership

To keep the framework predictable, the codebase now has three distinct ownership layers:

- `framework/*`
  Framework primitives only. Session store, preferences service, callback runner, task runner, events, logging, and profiling belong here.
- `runtime.lua`
  Composition root. It provides config defaults, registers tasks/apps/widgets, and seeds baseline session state.
- domain modules like `tasks/*`, `lifecycle/*`, `mspapi/*`, `app/*`, and `widgets/*`
  These own behavior and domain-specific state, but they should build on framework primitives rather than invent their own storage systems.

### Session Ownership

There is one common session mechanism:

- `framework.session` in `framework/core/session.lua`

Use it as the single runtime state store. The important distinction is not where values are stored, but who owns which keys:

- `runtime.lua`
  Seeds baseline keys and default values.
- `tasks/msp.lua`
  Owns link-scoped transport and connection state such as telemetry presence, API version, queue status, and connected/disconnected transitions.
- `tasks/lifecycle.lua` and `lifecycle/*`
  Own post-connect derived state such as `fcVersion`, `mcu_id`, `modelPreferences`, timer setup, and default rate profile.
- `app/*` and `widgets/*`
  Should mostly read session state, not own connection state.

As a rule: if a task is responsible for clearing or rebuilding a value on disconnect/reconnect, that task owns the key.

### Preferences Ownership

Global preferences are now handled centrally by:

- `framework.preferences` in `framework/core/preferences.lua`

This service is responsible for:

- loading preferences from the configured preferences file
- exposing section data such as `preferences.developer`
- supporting structured access through `get/set/save/load`

There is still an intentional split between:

- global preferences
  Managed by `framework.preferences`
- model-specific preferences
  Currently loaded during `onconnect` once `mcu_id` is known, then exposed through session as `modelPreferences`

That means the preferences story is now centralized at the framework level for global settings, while model preferences remain a domain concern tied to a connected flight controller.

### `lib` vs `framework`

Use this boundary:

- put code in `framework/*` if it is a framework primitive that any subsystem could rely on
- put code in `lib/*` if it is a shared helper, storage parser, or domain-adjacent utility that is not part of the framework contract itself

With the current layout that means:

- `framework/core/session.lua`
  correct in framework
- `framework/core/preferences.lua`
  correct in framework
- `framework/utils/log.lua`
  correct in framework
- `lib/ini.lua`
  reasonable in `lib` because it is a general file format helper, not a framework runtime primitive
- `lib/utils.lua`
  still slightly ambiguous, but acceptable as a shared helper module for now

### 1. Locals First, Globals Only for Shared State

```lua
-- ✅ GOOD: Local module with shared access via framework
local MyApp = {}
local framework = require("framework")
framework:register("myapp", MyApp)

-- ❌ AVOID: Dumping everything in global/_G
_G.myapp = {}
_G.myapp_state = {}
_G.myapp_callbacks = {}
```

Each core area (app, tasks, widgets, modules) is **LOCAL** within its file. Only expose through the framework registry.

**Shared state** stays in framework globals:
- `framework.config` - static configuration
- `framework.session` - runtime state
- `framework.preferences` - user preferences

### 2. Callback-Based Decoupling

Instead of direct inter-module calls, use the framework's callback system:

```lua
-- App registers for flight mode changes
framework.on("flightmode:changed", function(newMode)
    -- React to flight mode change
end)

-- Tasks emit the event
framework.emit("flightmode:changed", "acro")
```

This decouples modules: tasks don't need to know about app, app doesn't need to know about tasks.

### 3. CPU Budget Enforcement

All callback execution is time-boxed:

```lua
-- Callbacks wakeup with CPU budget
local function wakeup()
    framework:wakeupCallbacks({
        maxCalls = 16,           -- Process max 16 callbacks per cycle
        budgetMs = 4,            -- Total budget: 4ms
        category = "render"      -- Separate budgets per category
    })
end
```

### 4. Task Registration Pattern

Background tasks and apps register themselves:

```lua
-- tasks/telemetry.lua
local TelemetryTask = {}

function TelemetryTask:init()
    -- One-time initialization
    self.connected = false
end

function TelemetryTask:wakeup()
    -- Called periodically based on subscription
    -- Should be fast, callback-driven
end

function TelemetryTask:close()
    -- Cleanup resources
end

return TelemetryTask
```

Register at startup:
```lua
framework:registerTask("telemetry", TelemetryTask, {
    interval = 0.1,      -- Wakeup every 100ms
    priority = 10        -- Higher = earlier execution
})
```

## Framework Architecture

### Directory Structure

```
framework/
├── core/
│   ├── init.lua              -- Main entry point
│   ├── registry.lua          -- Module/task registration
│   ├── callback.lua          -- Callback queue and dispatch
│   ├── session.lua           -- Runtime state management
│   └── config.lua            -- Configuration loading
├── scheduler/
│   ├── scheduler.lua         -- Task scheduling engine
│   ├── wakeup.lua            -- Wakeup coordination
│   └── budget.lua            -- CPU/time budget management
├── events/
│   ├── events.lua            -- Event registration and emission
│   ├── hooks.lua             -- Hook-based callbacks
│   └── lifecycle.lua         -- App/task lifecycle hooks
├── utils/
│   ├── log.lua               -- Logging with levels
│   ├── memory.lua            -- Memory profiling
│   ├── performance.lua       -- Performance monitoring
│   └── ini.lua               -- INI file handling
└── lib/
    └── queue.lua             -- Efficient queue implementation

app/
├── init.lua                  -- App registration and lifecycle
├── pages/
│   ├── page_base.lua         -- Base page class
│   └── pages/                -- Individual page modules
├── modules/
│   ├── module_base.lua       -- Base module class
│   └── modules/              -- Module implementations
└── dialogs/
    └── dialog_base.lua       -- Dialog management

tasks/
├── init.lua                  -- Task manager init
├── background/
│   ├── scheduler.lua         -- Main scheduler task
│   ├── telemetry.lua         -- Telemetry polling
│   ├── msp.lua               -- MSP protocol handler
│   └── gc.lua                -- Garbage collection tuning
└── events/
    ├── connect.lua           -- Connection lifecycle
    ├── disconnect.lua        -- Disconnection lifecycle
    └── transitions.lua       -- State transitions
```

### Core Objects

#### 1. Framework (`framework/core/init.lua`)

```lua
local framework = {
    config = {},
    session = {},
    preferences = {},
    _modules = {},
    _tasks = {},
    _callbacks = {},
}

function framework:init(config)
    -- Initialize framework with config
end

function framework:register(name, module)
    -- Register a module by name
end

function framework:registerTask(name, taskClass, options)
    -- Register a background task
end

function framework:on(event, callback)
    -- Subscribe to event
end

function framework:emit(event, ...)
    -- Emit event to all subscribers
end

function framework:wakeupCallbacks(options)
    -- Process callback queue with CPU budget
end

return framework
```

#### 2. Registry (`framework/core/registry.lua`)

Manages all registered modules and tasks with lazy loading:

```lua
local registry = {}

function registry:register(type, name, moduleOrClass, options)
    -- Register module/task
    -- Support lazy loading
end

function registry:get(type, name)
    -- Get module/task (load if lazy)
end

function registry:list(type)
    -- List all registered items of type
end

function registry:unregister(type, name)
    -- Unregister and cleanup
end

return registry
```

#### 3. Callback Queue (`framework/core/callback.lua`)

CPU-aware callback execution:

```lua
local callback = {
    _queues = {
        immediate = {},
        timer = {},
        events = {}
    }
}

function callback:now(func, category)
    -- Queue for immediate execution
end

function callback:inSeconds(seconds, func, category)
    -- Queue for delayed execution
end

function callback:every(seconds, func, category)
    -- Queue for repeating execution
end

function callback:wakeup(options)
    -- Process queue with CPU budget
    -- options.maxCalls, options.budgetMs, options.category
end

return callback
```

#### 4. Session (`framework/core/session.lua`)

Runtime state with change tracking:

```lua
local session = {
    data = {},
    _watchers = {}
}

function session:set(key, value)
    local old = self.data[key]
    self.data[key] = value
    if old ~= value then
        -- Notify watchers
    end
end

function session:get(key)
    return self.data[key]
end

function session:watch(key, callback)
    -- Watch for changes to key
end

return session
```

## Execution Flow

### Startup
```
1. framework:init(config)
   - Load config
   - Initialize session
   - Load preferences
   
2. Register core tasks
   - Scheduler
   - Telemetry
   - MSP handler
   
3. Register app
   - Load app pages/modules
   - Register UI components
   
4. Start main loop
```

### Main Loop (Ethos `wakeup()`)
```
function wakeup()
    -- 1. Update scheduler (check task intervals)
    framework.scheduler:wakeup()
    
    -- 2. Execute tasks (with CPU budget)
    for task in framework:tasksInOrder() do
        if task:shouldWakeup() then
            task:wakeup()
        end
    end
    
    -- 3. Process callbacks (events, timers, etc.)
    framework:wakeupCallbacks({maxCalls=16, budgetMs=4})
    
    -- 4. Handle app (if active)
    if app.isActive() then
        app:wakeup()
    end
end
```

### Rendering (Ethos `paint()`)
```
function paint()
    -- 1. App paints (highest priority)
    if app.isActive() then
        app:paint()
    end
    
    -- 2. Widgets paint
    framework:wakeupCallbacks({
        category = "render",
        budgetMs = 8
    })
end
```

## Memory & CPU Optimization

### Memory Strategy
1. **Lazy Loading**: Load modules/tasks only when registered or first accessed
2. **Cleanup on Close**: Explicitly cleanup resources when pages/modules close
3. **Object Pooling**: Reuse tables for frequently created objects
4. **String Interning**: Cache common strings

### CPU Strategy
1. **Callback Budget**: Each category (render, events, tasks) has separate budget
2. **Priority Scheduling**: Higher-priority tasks execute first
3. **Interval-Based**: Tasks only wake up at specified intervals
4. **Throttling**: Heavy operations throttled based on system load

### Profiling & Monitoring

```lua
-- Enable performance monitoring
framework.config.enablePerformanceMonitoring = true

-- Check current stats
local stats = framework:getPerformanceStats()
print("CPU Load: " .. stats.cpuPercent .. "%")
print("Free RAM: " .. stats.freeRamKB .. "KB")
print("Callback Queue Size: " .. stats.callbackQueueSize)
```

## Best Practices

### ✅ DO

```lua
-- Use locals for module state
local MyModule = {}
local state = {}

-- Register with framework
framework:register("mymodule", MyModule)

-- Use callbacks to decouple
framework:on("event", function()
    -- React to event
end)

-- Be aware of CPU budget
function MyModule:wakeup()
    -- Fast, bounded operation
    -- Use callbacks for long operations
end

-- Cleanup explicitly
function MyModule:close()
    framework:off("event", myCallback)
    state = {}
end
```

### ❌ DON'T

```lua
-- Don't dump in global
_G.myvar = value
_G.myfunction = function() end

-- Don't call other modules directly
OtherModule:doSomething()  -- Tight coupling!

-- Don't do heavy work in wakeup
function wakeup()
    for i=1,10000 do
        -- This blocks everything
    end
end

-- Don't forget cleanup
function close()
    -- Should cleanup resources
end
```

## Migration Path

For existing code using monolithic global approach:

1. **Phase 1**: Identify core modules (app, tasks, utils)
2. **Phase 2**: Wrap each in local + framework registration
3. **Phase 3**: Convert inter-module calls to events
4. **Phase 4**: Add callback-based scheduling
5. **Phase 5**: Optimize with memory/CPU budgeting

## References

- `Modern rfsuite`: `/mnt/c/GitHub/rotorflight-lua-ethos-suite/` - Reference for large-scale app patterns
- `Betaflight Suite`: `/mnt/c/GitHub/betaflight-ethos-suite/` - Alternative implementation
- Ethos Lua Docs: `lua-doc/` - Official Ethos API documentation
