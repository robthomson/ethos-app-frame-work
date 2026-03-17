# Quick Reference Card

## Framework Basics

### Initialize
```lua
local framework = require("framework.core.init")
framework:init({toolName = "MyApp"})
```

### Register App
```lua
framework:registerApp(App, options)
framework:activateApp()
```

### Register Task
```lua
framework:registerTask(name, TaskClass, {
    priority = 20,
    interval = 0.1,
    enabled = true
})
```

---

## Session (Persistent State)

```lua
-- Set value
framework.session:set("key", value)

-- Get value
local val = framework.session:get("key", default)

-- Watch for changes
framework.session:watch("key", function(old, new)
    print("Changed: " .. old .. " -> " .. new)
end)

-- Get all values
local all = framework.session:dump()
```

---

## Events (Decoupled Communication)

```lua
-- Subscribe
framework:on("event:name", handler)

-- One-time subscribe
framework:once("event:name", handler)

-- Emit
framework:_emit("event:name", arg1, arg2)

-- Unsubscribe
framework:off("event:name", handler)
```

---

## Callbacks (CPU-Budgeted Scheduling)

```lua
-- Immediate
framework:callbackNow(function() end)

-- Delayed
framework:callbackInSeconds(5, function() end)

-- Repeating
framework:callbackEvery(1.0, function() end)

-- Configure budgets
framework.callback:setBudget("render", maxCalls, budgetMs)
```

---

## Task Template

```lua
local MyTask = {}

function MyTask:init(framework)
    self.framework = framework
    -- One-time setup
end

function MyTask:wakeup()
    -- Called periodically
    -- Keep fast and bounded
end

function MyTask:close()
    -- Cleanup resources
    self.framework = nil
end

return MyTask
```

---

## App Template

```lua
local App = {}

function App:init(framework)
    self.framework = framework
    
    -- Subscribe to events
    framework:on("event", function(data)
        self:handleEvent(data)
    end)
end

function App:wakeup()
    -- Periodic updates
end

function App:paint()
    -- Render UI
end

function App:close()
    -- Cleanup
end

return App
```

---

## Main Loop (Ethos)

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

---

## Common Patterns

### Task Emits Event to App
```lua
-- Task
self.framework:_emit("state:changed", newValue)

-- App
framework:on("state:changed", function(value)
    self:handleStateChange(value)
end)
```

### App Requests Action from Task
```lua
-- App
framework:_emit("action:requested", actionName)

-- Task
framework:on("action:requested", function(name)
    self:handleAction(name)
end)
```

### Track Connected State
```lua
-- Tasks
framework:on("connection:state", function(connected)
    self.connected = connected
end)

-- Other
framework.session:set("connected", true)
framework:_emit("connection:state", true)
```

### Telemetry -> UI
```lua
-- Telemetry task
framework:_emit("telemetry:updated", {voltage=12.5, current=5.2})

-- App listens
framework:on("telemetry:updated", function(data)
    self.voltage = data.voltage
end)

-- App renders
function paint()
    lcd.drawText(10, 10, self.voltage)
end
```

---

## Error Handling

```lua
-- Wrapped in PCalls (already done by framework)
-- But in your code:

local ok, err = pcall(function()
    -- Your code
end)

if not ok then
    print("Error: " .. tostring(err))
end
```

---

## Performance Tips

### ✅ DO
- Keep wakeup() < 5ms
- Use callbacks for heavy operations
- Batch related updates
- Reuse tables, don't create new ones
- Unsubscribe from events when done

### ❌ DON'T
- Do heavy loops in wakeup
- Create new tables every wakeup
- Forget cleanup in close()
- Subscribe without unsubscribing
- Block on I/O in wakeup

---

## Debugging

### Check Stats
```lua
framework:printStats()

local stats = framework:getStats()
print("Callbacks: " .. stats.callbackStats.totalQueued)
print("Events: " .. #stats.eventStats)
```

### Trace Events
```lua
framework:on("*", function(...)
    print("Event fired:", ...)
end)
```

### Watch Session Changes
```lua
framework.session:watch("key", function(old, new)
    print("Changed: " .. tostring(old) .. "→" .. tostring(new))
end)
```

---

## File Locations

```
src/
├── main.lua                    -- Entry point
├── framework/core/
│   ├── init.lua               -- Framework
│   ├── callback.lua           -- Callbacks
│   ├── session.lua            -- State
│   └── registry.lua           -- Registry
├── framework/events/
│   └── events.lua             -- Events
├── framework/utils/
│   └── log.lua                -- Logging
├── app/
│   └── app.lua                -- App module
└── tasks/
    ├── telemetry.lua          -- Example task
    └── msp.lua                -- Example task
```

---

## Next Steps

1. **Read ARCHITECTURE.md** - Detailed design
2. **Read IMPLEMENTATION.md** - Step-by-step build guide
3. **Read BEFORE_AFTER.md** - Understand the improvements
4. **Try the Examples** - Start with main.lua
5. **Build Your Modules** - Add your own tasks/pages

---

## Key Concepts

| Concept | Purpose | Example |
|---------|---------|---------|
| Framework | Coordinator | `framework:init()` |
| Session | Persistent state | `framework.session:set()` |
| Events | Decoupled comms | `framework:_emit()` |
| Callbacks | CPU-budgeted scheduling | `framework:callbackEvery()` |
| Tasks | Background work | `registerTask()` |
| App | UI/interaction | `registerApp()` |

---

## Links

- [ARCHITECTURE.md](./ARCHITECTURE.md) - Full design
- [IMPLEMENTATION.md](./IMPLEMENTATION.md) - Build steps
- [BEFORE_AFTER.md](./BEFORE_AFTER.md) - Old vs new
- [README.md](./README.md) - Full guide
