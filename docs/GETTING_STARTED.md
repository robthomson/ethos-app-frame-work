# Getting Started: Run the Example

## Quick Start (5 minutes)

### Prerequisites
- Rotorflight firmware on radio
- Ethos radio with Lua support
- Text editor or VS Code

### Step 1: Copy Framework to Your Radio

The framework is ready in `src/rfsuite/`:

```
src/
└── rfsuite/
    ├── main.lua                ← Ethos bootstrap entry point
    ├── framework/              ← Framework code
    ├── app/                    ← Application
    └── tasks/                  ← Background tasks
```

### Step 2: Deploy to Radio

Copy the `src/rfsuite/` directory to your Ethos radio:

**Via SD Card:**
```
/SCRIPTS/
 └── rfsuite/            ← Copy entire src/rfsuite/ here
     ├── main.lua
     ├── framework/
     ├── app/
     └── tasks/
```

Ethos will load `SCRIPTS:/rfsuite/main.lua`, call its `init()` function,
and that bootstrap will register the Rotorflight system tool.

### Step 3: Run on Radio

1. Reboot or rescan Lua scripts on the radio
2. Open Ethos System Tools
3. Select "Rotorflight"
4. You should see:
   - "Rotorflight Framework Initialized"
   - Basic console output
   - Simple UI (if LCD available)

### Step 4: Check It's Working

Monitor the console output:
```
[Telemetry] Task initialized
[MSP] Task initialized
[App] Initialized
=== Rotorflight Framework Initialized ===
```

If you see this, the framework is running! ✅

---

## Modify the Example

### Change 1: Add a Debug Message

Edit `src/rfsuite/main.lua`, find the `initialize()` function:

```lua
function initialize()
    -- ... existing code ...
    
    -- Add this:
    print("DEBUG: Framework initialized at " .. os.date())
```

Run again, you should see the timestamp in console.

### Change 2: Create Your First Task

Create `src/rfsuite/tasks/my_demo.lua`:

```lua
local DemoTask = {}

function DemoTask:init(framework)
    self.framework = framework
    self.counter = 0
    print("[Demo] Task initialized")
end

function DemoTask:wakeup()
    self.counter = self.counter + 1
    if self.counter % 20 == 0 then
        print("[Demo] Counter: " .. self.counter)
    end
end

function DemoTask:close()
    print("[Demo] Task closed")
end

return DemoTask
```

Register it in `src/rfsuite/main.lua`:

```lua
function initialize()
    -- ... existing code ...
    
    local DemoTask = require("tasks.my_demo")
    framework:registerTask("demo", DemoTask, {
        priority = 15,
        interval = 0.1
    })
    
    -- ... rest of code ...
end
```

Run it - you should see:
```
[Demo] Task initialized
[Demo] Counter: 20
[Demo] Counter: 40
...
```

### Change 3: Listen to Task Events

Edit your task to emit events:

```lua
function DemoTask:wakeup()
    self.counter = self.counter + 1
    
    if self.counter % 20 == 0 then
        self.framework:_emit("demo:milestone", self.counter)
    end
end
```

Listen in the app (`src/rfsuite/app/app.lua`):

```lua
function App:init(framework)
    self.framework = framework
    self.demoMilestone = 0
    
    framework:on("demo:milestone", function(count)
        self.demoMilestone = count
        print("App received milestone: " .. count)
    end)
end
```

Run it - the app reacts to the task event!

---

## Debug the Running Framework

### Using Console Output

Add debug prints:

```lua
print("DEBUG: Value = " .. tostring(myValue))
print("DEBUG: State = " .. framework.session:dump())
```

Check the Ethos console (usually accessible via radio menu).

### Check Framework Stats

Add to your code:

```lua
if someDebugFlag then
    framework:printStats()
end
```

Output shows:
```
=== Framework Stats ===
Initialized: true
App Active: true
Tasks: 3
Callbacks Queued: 5
Events: 2
```

### Monitor Specific State

```lua
-- Watch for changes
framework.session:watch("voltage", function(old, new)
    print("Voltage changed: " .. old .. " -> " .. new)
end)

-- Check all state
local state = framework.session:dump()
for key, value in pairs(state) do
    print(key .. " = " .. tostring(value))
end
```

### View Event Subscriptions

```lua
local events = framework.events:listEvents()
for eventName, count in pairs(events) do
    print("Event: " .. eventName .. " (" .. count .. " listeners)")
end
```

---

## Common Issues & Solutions

### "Module not found" error

**Problem**: `require("framework.core.init")` fails

**Solution**: 
- Check path: file should be at `framework/core/init.lua`
- Check naming: case-sensitive
- Check package path: update in main.lua if needed

### Task not waking up

**Problem**: Task functions not being called

**Solution**:
- Check interval: is it > 0?
- Check enabled: is task enabled?
- Add debug print in wakeup() to verify it's called
- Check task registration syntax

### Events not firing

**Problem**: Listener never called

**Solution**:
- Check event name: must match exactly
- Check registration: did you call `framework:on()`?
- Add debug print before `_emit()`
- Check listener exists: `listEvents()`

### App not painting

**Problem**: Screen shows nothing

**Solution**:
- Make sure app's `paint()` function exists
- Check `isActive()`: is app active?
- Add debug text: `lcd.drawText(10, 10, "test")`
- Check LCD availability: guard with `if lcd then`

### Memory growing / Crashes

**Problem**: App runs for a while then crashes

**Solution**:
- Implement `close()` functions in all tasks
- Clear tables in close: `self.data = {}`
- Don't create new tables in hot paths
- Profile memory: check available before crash

### CPU too high / UI sluggish

**Problem**: UI feels slow or unresponsive

**Solution**:
- Check CPU: run `framework:printStats()`
- Move heavy work to callbacks: `callbackInSeconds()`
- Reduce task frequencies: increase intervals
- Check paint(): might be too heavy

---

## Next: Build Your First Feature

### Option 1: Add More Tasks

Create a new task file, register it, listen to events.

**Difficulty**: Easy
**Time**: 30 mins
**Result**: Understand task pattern

### Option 2: Add a Menu

Create a basic page, implement paint() to show menu.

**Difficulty**: Medium
**Time**: 1-2 hours
**Result**: Understand page pattern

### Option 3: Implement MSP Protocol

Follow IMPLEMENTATION.md Step 3.

**Difficulty**: Hard
**Time**: 3-4 hours
**Result**: Understand MSP communication

### Option 4: Add a Configuration System

Implement INI file loading/saving for preferences.

**Difficulty**: Medium
**Time**: 2-3 hours
**Result**: Understand persistence

---

## Deployment Checklist

Before deploying to production:

- [ ] All modules have `close()` implemented
- [ ] No memory leaks - `framework:printStats()` stable
- [ ] CPU usage acceptable - < 50% during normal ops
- [ ] All tasks initialize without error
- [ ] App renders correctly on target radio
- [ ] Connection/disconnection handled gracefully
- [ ] Error recovery works (task fails, app continues)
- [ ] Can exit/close app cleanly
- [ ] No globals created (should see no warnings)

---

## Testing on Hardware

### First Power-On

1. Connect to radio via SD card or telemetry
2. Power on radio
3. Monitor console output
4. Check for errors
5. Verify the Rotorflight entry appears in System Tools

### Testing Steps

1. **Connection Test**
   - Connect to quad/aircraft
   - Check connection event fires
   - Verify telemetry displays

2. **UI Test**
   - Navigate menus/pages
   - Send simple commands
   - Check responses

3. **Load Test**
   - Let it run for 10+ minutes
   - Monitor memory usage
   - Check for freezes or crashes

4. **Error Test**
   - Disconnect radio mid-operation
   - Reconnect
   - Verify recovery

---

## Getting Help

### "Where's the documentation?"

1. **Quick lookup**: `QUICK_REFERENCE.md`
2. **How-to**: `README.md`
3. **Deep dive**: `ARCHITECTURE.md`
4. **Step-by-step**: `IMPLEMENTATION.md`
5. **Before/after**: `BEFORE_AFTER.md`

### "How do I...?"

Use find-in-doc or INDEX.md to locate.

Examples:
- "Use events" → README.md Event System
- "Create task" → QUICK_REFERENCE.md Task Template
- "Debug issue" → QUICK_REFERENCE.md Debugging

### "Show me code"

- App example: `src/rfsuite/app/app.lua`
- Task example: `src/rfsuite/tasks/telemetry.lua`
- Integration: `src/rfsuite/main.lua`

---

## Quick Reference for This Section

```lua
-- Add debug output
print("Value: " .. tostring(x))

-- Check framework state
framework:printStats()

-- Create a task
local MyTask = {}
function MyTask:init(f) ... end
function MyTask:wakeup() ... end
function MyTask:close() ... end

-- Register task
framework:registerTask("name", MyTask, {interval=0.1})

-- Emit event
framework:_emit("event", data)

-- Listen to event
framework:on("event", function(data) ... end)

-- Get state
local val = framework.session:get("key")

-- Set state
framework.session:set("key", val)
```

---

## Next Steps

1. ✅ Run the framework example
2. ✅ Modify it (add a task, listen to events)
3. ✅ Debug it (use prints, stats, watches)
4. 🔄 Build your first feature (follow IMPLEMENTATION.md)
5. 🔄 Deploy to hardware
6. 🔄 Test and optimize

**You're ready to start building!** 🚀
