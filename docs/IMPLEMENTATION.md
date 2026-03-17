# Framework Implementation Guide

## Step-by-Step Build Guide for Rotorflight Ethos Lua Framework

This guide walks through building the framework incrementally, with each step adding new capabilities.

## Step 1: Core Framework & Callback System ✅

**Status**: COMPLETE

**Files Created**:
- `src/framework/core/callback.lua` - CPU-aware callback queue
- `src/framework/core/session.lua` - Runtime state management  
- `src/framework/events/events.lua` - Event pub/sub system
- `src/framework/core/registry.lua` - Module registration
- `src/framework/core/init.lua` - Framework coordinator

**What It Does**:
- Registers background tasks and app
- Manages callback queue with CPU budgeting
- Provides session state with watchers
- Event-driven decoupling

**How It Works**:
```lua
-- Tasks -> Events -> App
-- No direct dependencies
```

---

## Step 2: Background Task Infrastructure

**Files to Create**:

### `src/framework/scheduler/task_base.lua`

Base class for all background tasks with lifecycle management:

```lua
local TaskBase = {}

function TaskBase:init(framework)
    self.framework = framework
    self.enabled = true
    self.nextWakeup = 0
end

function TaskBase:wakeup()
    -- Override in subclass
end

function TaskBase:close()
    -- Override for cleanup
end

function TaskBase:setEnabled(enable)
    self.enabled = enable
end

return TaskBase
```

### `src/framework/scheduler/heartbeat.lua`

Special task that runs every wakeup (fast status checks):

```lua
local Heartbeat = {}

function Heartbeat:init(framework)
    self.framework = framework
    self.checks = {}
end

function Heartbeat:registerCheck(name, func)
    self.checks[name] = func
end

function Heartbeat:wakeup()
    for name, check in pairs(self.checks) do
        pcall(check)
    end
end

return Heartbeat
```

### Update `src/framework/core/init.lua`

Add task scheduling improvements:

```lua
function framework:wakeupTasks()
    local now = os.clock()
    
    for _, taskInfo in ipairs(self._taskOrder) do
        local meta = self._taskMetadata[taskInfo.name]
        if meta.enabled and meta.instance then
            local elapsed = now - meta.lastWakeup
            if elapsed >= meta.interval then
                pcall(meta.instance.wakeup, meta.instance)
                meta.lastWakeup = now
            end
        end
    end
end
```

**Expected Behavior**:
- Tasks wake at specified intervals
- No task starves others due to CPU budget
- Heartbeat runs every cycle (sub-millisecond operations)

---

## Step 3: MSP Protocol Handler

**Files to Create**:

### `src/framework/scheduler/msp/msp_base.lua`

Base MSP packet structure:

```lua
local MSPPacket = {}
MSPPacket.__index = MSPPacket

function MSPPacket.new(direction, cmd, payload)
    local self = setmetatable({}, MSPPacket)
    self.direction = direction  -- 1 (to device) or 2 (from device)
    self.cmd = cmd
    self.payload = payload or ""
    self.crc = 0
    return self
end

function MSPPacket:calculateCRC()
    -- CRC implementation
end

function MSPPacket:serialize()
    -- Convert to wire format
end

return MSPPacket
```

### `src/framework/scheduler/msp/msp_queue.lua`

Queue management with backpressure handling:

```lua
local MSPQueue = {}
MSPQueue.__index = MSPQueue

function MSPQueue.new(maxSize)
    local self = setmetatable({}, MSPQueue)
    self.queue = {}
    self.maxSize = maxSize or 32
    self.dedupe = {}  -- Deduplicate similar requests
    return self
end

function MSPQueue:enqueue(packet)
    if #self.queue >= self.maxSize then
        return false, "queue_full", nil, #self.queue
    end
    
    table.insert(self.queue, packet)
    return true, "queued", #self.queue, #self.queue
end

function MSPQueue:dequeue()
    return table.remove(self.queue, 1)
end

return MSPQueue
```

### `src/tasks/msp_handler.lua`

Complete MSP task:

```lua
local MSPHandler = {}

function MSPHandler:init(framework)
    self.framework = framework
    self.connected = false
    self.queue = require("framework.scheduler.msp.msp_queue").new(32)
    self.currentOp = nil
end

function MSPHandler:wakeup()
    -- Process queue
    local packet = self.queue:dequeue()
    if packet then
        -- Stub: Send MSP packet
        self.framework:_emit("msp:sent", packet)
    end
end

function MSPHandler:enqueueRead(cmd, payload)
    return self.queue:enqueue(payload)
end

return MSPHandler
```

**Expected Behavior**:
- MSP commands queued reliably
- Backpressure handling prevents buffer overflow
- Events emitted on completion

---

## Step 4: Telemetry System

**Files to Create**:

### `src/framework/scheduler/telemetry/sensor.lua`

Individual sensor/telemetry source:

```lua
local Sensor = {}
Sensor.__index = Sensor

function Sensor.new(name, dataType)
    local self = setmetatable({}, Sensor)
    self.name = name
    self.dataType = dataType
    self.value = nil
    self.lastUpdate = 0
    self.updateRate = 1.0  -- Hz
    return self
end

function Sensor:setValue(value)
    self.value = value
    self.lastUpdate = os.clock()
end

function Sensor:getValue()
    return self.value
end

return Sensor
```

### `src/tasks/telemetry_collector.lua`

Background task collecting telemetry:

```lua
local TelemetryCollector = {}

function TelemetryCollector:init(framework)
    self.framework = framework
    self.sensors = {}
    self.connected = false
end

function TelemetryCollector:registerSensor(name, sensor)
    self.sensors[name] = sensor
end

function TelemetryCollector:wakeup()
    if self.connected then
        -- Stub: Read telemetry
        for name, sensor in pairs(self.sensors) do
            -- Update sensor value
        end
        
        self.framework:_emit("telemetry:updated", self:getAll())
    end
end

function TelemetryCollector:getAll()
    local data = {}
    for name, sensor in pairs(self.sensors) do
        data[name] = sensor:getValue()
    end
    return data
end

return TelemetryCollector
```

**Expected Behavior**:
- Telemetry collected at configured rates
- Events emitted when data updates
- App receives events and updates UI

---

## Step 5: Connection Management

**Files to Create**:

### `src/framework/scheduler/connection.lua`

Connection state machine:

```lua
local Connection = {}

local States = {
    DISCONNECTED = "disconnected",
    CONNECTING = "connecting",
    CONNECTED = "connected",
    DISCONNECT_PENDING = "disconnect_pending"
}

function Connection:init(framework)
    self.framework = framework
    self.state = States.DISCONNECTED
    self.connectedAt = nil
end

function Connection:connect()
    self.state = States.CONNECTING
    self.framework:_emit("connection:state", "connecting")
end

function Connection:onConnected()
    self.state = States.CONNECTED
    self.connectedAt = os.clock()
    self.framework:_emit("connection:state", "connected")
end

function Connection:disconnect()
    self.state = States.DISCONNECTED
    self.connectedAt = nil
    self.framework:_emit("connection:state", "disconnected")
end

return Connection
```

### Update `src/tasks/telemetry.lua`

React to connection events:

```lua
function TelemetryTask:init(framework)
    -- ... existing code ...
    
    framework:on("connection:state", function(state)
        self.connected = (state == "connected")
    end)
end
```

**Expected Behavior**:
- Connection state transitions emit events
- Tasks react to connection/disconnection
- App updates UI based on connection state

---

## Step 6: App Page System

**Files to Create**:

### `src/framework/app/page_base.lua`

Base class for application pages:

```lua
local PageBase = {}
PageBase.__index = PageBase

function PageBase.new(name)
    local self = setmetatable({}, PageBase)
    self.name = name
    self.framework = nil
    self.visible = false
    return self
end

function PageBase:onEnter()
    -- Override: Page displayed
end

function PageBase:onExit()
    -- Override: Page hidden
end

function PageBase:wakeup()
    -- Override: Periodic update
end

function PageBase:paint()
    -- Override: Render to LCD
end

function PageBase:close()
    -- Override: Cleanup
end

return PageBase
```

### `src/app/pages/home_page.lua`

Example home page:

```lua
local PageBase = require("framework.app.page_base")
local HomePage = setmetatable({}, {__index = PageBase})

function HomePage:new()
    local self = PageBase.new("Home")
    self.telemetry = {}
    return self
end

function HomePage:onEnter()
    self.framework:on("telemetry:updated", function(data)
        self.telemetry = data
    end)
end

function HomePage:paint()
    if lcd then
        lcd.color(lcd.RGB(255, 255, 255))
        lcd.drawText(10, 10, "Telemetry")
        if self.telemetry.voltage then
            lcd.drawText(10, 30, "V: " .. self.telemetry.voltage)
        end
    end
end

function HomePage:close()
    self.telemetry = {}
end

return HomePage
```

### `src/app/page_manager.lua`

Navigate between pages:

```lua
local PageManager = {}

function PageManager:init(framework)
    self.framework = framework
    self.pages = {}
    self.currentPage = nil
end

function PageManager:registerPage(page)
    self.pages[page.name] = page
    page.framework = self.framework
end

function PageManager:loadPage(pageName)
    if self.currentPage then
        self.currentPage:onExit()
    end
    
    self.currentPage = self.pages[pageName]
    if self.currentPage then
        self.currentPage:onEnter()
    end
end

function PageManager:paint()
    if self.currentPage then
        self.currentPage:paint()
    end
end

return PageManager
```

**Expected Behavior**:
- Pages initialize on enter
- Pages receive telemetry updates
- Pages render to LCD
- Clean transition between pages

---

## Step 7: Menu System

**Files to Create**:

### `src/framework/app/menu.lua`

Hierarchical menu structure:

```lua
local Menu = {}

function Menu:new(title)
    self.title = title
    self.items = {}
    self.parent = nil
    return self
end

function Menu:addItem(label, action, submenu)
    table.insert(self.items, {
        label = label,
        action = action,
        submenu = submenu
    })
end

function Menu:addSubmenu(label, submenu)
    self:addItem(label, nil, submenu)
end

return Menu
```

### `src/app/menus/main_menu.lua`

Example main menu:

```lua
local Menu = require("framework.app.menu")

local MainMenu = Menu:new("Rotorflight")

MainMenu:addItem("Dashboard", function() 
    -- Load dashboard page
end)

MainMenu:addItem("Settings", nil, {
    title = "Settings",
    items = {
        {label = "PID", action = function() end},
        {label = "Rates", action = function() end}
    }
})

MainMenu:addItem("Info", function()
    -- Show device info
end)

return MainMenu
```

**Expected Behavior**:
- Hierarchical menu navigation
- Items trigger actions or open submenus
- Easy to extend

---

## Step 8: Form System

**Files to Create**:

### `src/framework/app/form.lua`

Form with dynamic fields:

```lua
local Form = {}

function Form:new(title)
    self.title = title
    self.fields = {}
    self.values = {}
    return self
end

function Form:addField(field)
    table.insert(self.fields, field)
    self.values[field.name] = field.default or ""
end

function Form:setValue(fieldName, value)
    self.values[fieldName] = value
end

function Form:getValue(fieldName)
    return self.values[fieldName]
end

function Form:getValues()
    return self.values
end

return Form
```

### `src/app/forms/settings_form.lua`

Example settings form:

```lua
local Form = require("framework.app.form")

local settingsForm = Form:new("Settings")

settingsForm:addField({
    name = "rcFilter",
    label = "RC Filter",
    type = "number",
    min = 0,
    max = 100,
    default = 50
})

settingsForm:addField({
    name = "enabled",
    label = "Enabled",
    type = "boolean",
    default = true
})

return settingsForm
```

**Expected Behavior**:
- Forms collect user input
- Validated before submission
- Values sent via MSP to device

---

## Step 9: Error Recovery & Watchdog

**Files to Create**:

### `src/framework/scheduler/watchdog.lua`

Monitor system health:

```lua
local Watchdog = {}

function Watchdog:init(framework)
    self.framework = framework
    self.lastMSPResponse = os.clock()
    self.timeout = 5.0
    self.healthy = true
end

function Watchdog:wakeup()
    -- Check if MSP responding
    if os.clock() - self.lastMSPResponse > self.timeout then
        if self.healthy then
            self.healthy = false
            self.framework:_emit("system:unhealthy", "MSP_TIMEOUT")
        end
    end
end

function Watchdog:recordMSPResponse()
    self.lastMSPResponse = os.clock()
    if not self.healthy then
        self.healthy = true
        self.framework:_emit("system:healthy")
    end
end

return Watchdog
```

---

## Step 10: Configuration & Persistence

**Files to Create**:

### `src/framework/utils/config.lua`

Configuration management:

```lua
local config = {}

function config:loadINI(filepath)
    -- Parse INI file
    local result = {}
    -- Implementation
    return result
end

function config:saveINI(filepath, data)
    -- Write INI file
end

function config:merge(defaults, user)
    local merged = {}
    for k, v in pairs(defaults) do
        merged[k] = user[k] or v
    end
    return merged
end

return config
```

---

## Implementation Timeline

### Phase 1: Basics (Step 1-2)
- **Duration**: 1-2 weeks
- **Result**: Core framework, task scheduling
- **Can Demo**: Task registration and callback system

### Phase 2: Communication (Step 3-5)
- **Duration**: 2-3 weeks
- **Result**: MSP protocol, telemetry, connection management
- **Can Demo**: Connecting and reading telemetry

### Phase 3: UI (Step 6-8)
- **Duration**: 3-4 weeks
- **Result**: Pages, menus, forms
- **Can Demo**: Basic navigation, viewing telemetry

### Phase 4: Polish (Step 9-10)
- **Duration**: 2-3 weeks
- **Result**: Error recovery, configuration
- **Can Demo**: Full working application

---

## Testing Strategy

### Unit Tests
- Callback queue timing
- Session watchers
- Event emission
- MSP serialization

### Integration Tests
- Full connection flow
- Task coordination
- Page transitions
- Data persistence

### Hardware Tests
- Memory usage profiling
- CPU load monitoring
- Ethos radio compatibility
- Long-running stability

---

## Optimization Checkpoints

### CPU Profile
- Measure callback processing time
- Monitor task wakeup overhead
- Check Ethos responsiveness

### Memory Profile
- Callback queue size
- Registered modules footprint
- Session state growth
- Telemetry buffer usage

### Recommendations
After each phase, profile and optimize:
- Use lazy loading where beneficial
- Reduce table allocations
- Cache frequently accessed values

---

## Next: Choose Your Path

1. **Implement MSP Protocol** (Step 3)
   - Start with basic packet serialization
   - Add command queueing
   - Test with real device

2. **Design Page System** (Step 6)
   - Create page base class
   - Implement page transitions
   - Build first page

3. **Build Initial UI** (Step 7-8)
   - Hierarchical menu
   - Basic forms
   - Display telemetry

Choose based on your priorities!
