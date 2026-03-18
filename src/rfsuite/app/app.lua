--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local App = {}

local MENU_ROOT_PATH = "app/menu/root.lua"
local MASK_CACHE_MAX = 16
local NOOP_PAINT = function() end

local function loadLuaTable(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid path"
    end

    local chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr
    end

    local ok, value = pcall(chunk)
    if not ok then
        return nil, value
    end

    if type(value) ~= "table" then
        return nil, "module did not return table"
    end

    return value
end

local function isKey(value, name)
    return _G[name] ~= nil and value == _G[name]
end

local function isAnyKey(value, names)
    for i = 1, #names do
        if isKey(value, names[i]) then
            return true
        end
    end
    return false
end

local function isCloseEvent(category, value)
    if category == EVT_CLOSE then
        return true
    end

    return isAnyKey(value, {
        "KEY_RTN_BREAK",
        "KEY_EXIT_BREAK",
        "KEY_MODEL_BREAK"
    })
end

local function formatValue(value, format)
    if value == nil then
        return "--"
    end

    if format == "ms_3" then
        return string.format("%.3fms", tonumber(value) or 0)
    end

    if format == "kb_1" then
        return string.format("%.1fKB", tonumber(value) or 0)
    end

    if format == "bool" then
        return value == true and "Yes" or "No"
    end

    return tostring(value)
end

local function safeFormClear()
    if form and form.clear then
        form.clear()
    end
end

local function normalizeNodeKey(source)
    return tostring(source or "root"):gsub("[^%w]+", "_")
end

function App:init(framework)
    local radioConfig, radioErr

    self.framework = framework
    self.telemetryTask = nil
    radioConfig, radioErr = loadLuaTable("app/radios.lua")
    if type(radioConfig) ~= "table" then
        error("failed to load app/radios.lua: " .. tostring(radioErr))
    end
    self.radio = radioConfig
    self.snapshot = {}
    self.pathStack = {}
    self.currentNode = nil
    self.currentNodeSource = MENU_ROOT_PATH
    self.formDirty = true
    self.rootLoadError = nil
    self.statusFields = {}
    self.valueFields = {}
    self.buttonFields = {}
    self.navFields = {}
    self.maskCache = {}
    self.maskCacheOrder = {}
end

function App:_clearFormRefs()
    self.statusFields = {}
    self.valueFields = {}
    self.buttonFields = {}
    self.navFields = {}
end

function App:_invalidateForm()
    self.formDirty = true
    if form and form.invalidate then
        form.invalidate()
    end
end

function App:_menuState()
    return self.framework.preferences:section("menu_state", {})
end

function App:_getSelectedIndex(source)
    local state = self:_menuState()
    local value = tonumber(state["sel_" .. normalizeNodeKey(source)])
    if value == nil or value < 1 then
        return 1
    end
    return value
end

function App:_setSelectedIndex(source, index)
    local state = self:_menuState()
    state["sel_" .. normalizeNodeKey(source)] = tonumber(index) or 1
end

function App:_windowSize()
    if lcd and lcd.getWindowSize then
        return lcd.getWindowSize()
    end
    return 800, 480
end

function App:_iconsize()
    local general = self.framework.preferences:section("general", {})
    local iconsize = tonumber(general.iconsize)
    if iconsize == nil then
        iconsize = 1
        general.iconsize = iconsize
    end
    if iconsize < 0 then iconsize = 0 end
    if iconsize > 2 then iconsize = 2 end
    return iconsize
end

function App:_menuButtonMetrics()
    local radio = self.radio
    local iconsize = self:_iconsize()
    local width = self:_windowSize()
    local buttonW
    local buttonH
    local padding
    local numPerRow

    if iconsize == 0 then
        padding = radio.buttonPaddingSmall
        buttonW = (width - padding) / radio.buttonsPerRow - padding
        buttonH = radio.navbuttonHeight
        numPerRow = radio.buttonsPerRow
    elseif iconsize == 2 then
        padding = radio.buttonPadding
        buttonW = radio.buttonWidth
        buttonH = radio.buttonHeight
        numPerRow = radio.buttonsPerRow
    else
        padding = radio.buttonPaddingSmall
        buttonW = radio.buttonWidthSmall
        buttonH = radio.buttonHeightSmall
        numPerRow = radio.buttonsPerRowSmall
    end

    return {
        buttonW = math.floor(buttonW),
        buttonH = math.floor(buttonH),
        padding = padding,
        numPerRow = numPerRow
    }
end

function App:_headerMetrics()
    local radio = self.radio
    local width = self:_windowSize()
    local buttonW = radio.menuButtonWidth or 100
    local buttonH = radio.navbuttonHeight or 30
    local padding = 5
    local navButtons = (#self.pathStack > 0) and 2 or 1
    local reserved = (buttonW + padding) * navButtons
    return {
        width = width,
        buttonW = buttonW,
        buttonH = buttonH,
        titleWidth = math.max(40, (width - 5) - reserved - 8)
    }
end

function App:_loadMask(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local cached = self.maskCache[path]
    if cached ~= nil then
        if cached == false then
            return nil
        end
        return cached
    end

    local mask = lcd and lcd.loadMask and lcd.loadMask(path) or nil
    self.maskCache[path] = mask or false
    self.maskCacheOrder[#self.maskCacheOrder + 1] = path

    while #self.maskCacheOrder > MASK_CACHE_MAX do
        local evict = table.remove(self.maskCacheOrder, 1)
        self.maskCache[evict] = nil
    end

    return mask
end

function App:_telemetry()
    if self.telemetryTask == nil and self.framework and self.framework.getTask then
        self.telemetryTask = self.framework:getTask("telemetry")
    end
    return self.telemetryTask
end

function App:_readTelemetry(sensorKey)
    local telemetry = self:_telemetry()
    if not (telemetry and telemetry.getSensor) then
        return nil
    end

    local ok, value = pcall(telemetry.getSensor, telemetry, sensorKey)
    if not ok then
        return nil
    end
    return value
end

function App:_resolveItemValue(item)
    if type(item) ~= "table" then
        return "--"
    end

    if item.kind == "session" then
        return formatValue(self.framework.session:get(item.key, item.default), item.format)
    end

    if item.kind == "telemetry" then
        return formatValue(self:_readTelemetry(item.sensor), item.format)
    end

    if item.kind == "static" then
        return tostring(item.value or "")
    end

    return item.valueHint or ""
end

function App:_refreshSnapshot()
    return
end

function App:_loadNodeFromSource(source)
    local node, err = loadLuaTable(source)
    if not node then
        return {
            title = "Load Error",
            subtitle = tostring(err),
            items = {
                {id = "error", title = "Error", kind = "static", value = tostring(err)}
            }
        }
    end
    return node
end

function App:_loadRootNode()
    local node, err = loadLuaTable(MENU_ROOT_PATH)
    if not node then
        self.rootLoadError = tostring(err)
        return {
            title = "Rotorflight",
            subtitle = tostring(err),
            items = {
                {id = "error", title = "Menu Error", kind = "static", value = tostring(err)}
            }
        }
    end

    self.rootLoadError = nil
    return node
end

function App:_openRoot()
    self.pathStack = {}
    self.currentNodeSource = MENU_ROOT_PATH
    self.currentNode = self:_loadRootNode()
    self:_invalidateForm()
end

function App:_makeLeafNode(item)
    return {
        title = item.title or item.id or "Page",
        subtitle = item.subtitle or "Page scaffold",
        items = {
            {id = "status", title = "Status", kind = "static", value = item.status or "Scaffold"},
            {id = "path", title = "Path", kind = "static", value = item.path or item.id or "n/a"},
            {id = "note", title = "Note", kind = "static", value = item.notes or "This page path is preserved while the page implementation is migrated."}
        }
    }
end

function App:_enterItem(index, item)
    if type(item) ~= "table" then
        return
    end

    self:_setSelectedIndex(self.currentNodeSource, index)
    self.pathStack[#self.pathStack + 1] = {
        source = self.currentNodeSource,
        node = self.currentNode
    }

    if item.kind == "menu" and type(item.source) == "string" then
        self.currentNodeSource = item.source
        self.currentNode = self:_loadNodeFromSource(item.source)
    else
        self.currentNodeSource = "leaf:" .. tostring(item.id or index)
        self.currentNode = self:_makeLeafNode(item)
    end

    self:_invalidateForm()
end

function App:_goBack()
    local previous = self.pathStack[#self.pathStack]
    if not previous then
        return false
    end

    self.pathStack[#self.pathStack] = nil
    self.currentNodeSource = previous.source
    self.currentNode = previous.node
    self:_invalidateForm()
    return true
end

function App:_headerTitlePos()
    local radio = self.radio
    local metrics = self:_headerMetrics()
    return {
        x = 0,
        y = radio.linePaddingTop or 6,
        w = metrics.titleWidth,
        h = radio.navbuttonHeight or 30
    }
end

function App:_addNavigationButtons()
    local metrics = self:_headerMetrics()
    local y = self.radio.linePaddingTop or 6
    local xRight = metrics.width - 5
    local defs = {
        {
            key = "menu",
            text = "Menu",
            enabled = (#self.pathStack > 0),
            press = function()
                if #self.pathStack > 0 then
                    self:_openRoot()
                end
            end
        }
    }

    if #self.pathStack > 0 then
        defs[#defs + 1] = {
            key = "back",
            text = "Back",
            enabled = true,
            press = function()
                self:_goBack()
            end
        }
    end

    for i = #defs, 1, -1 do
        local def = defs[i]
        local bx = xRight - metrics.buttonW
        local field = form.addButton(nil, {x = bx, y = y, w = metrics.buttonW, h = metrics.buttonH}, {
            text = def.text,
            options = FONT_S,
            paint = NOOP_PAINT,
            press = def.press
        })
        if field and field.enable then
            field:enable(def.enabled == true)
        end
        self.navFields[def.key] = field
        xRight = bx - 5
    end
end

function App:_addHeader(node)
    local line = form.addLine("")
    local headerTitle = node.title or "Rotorflight"
    if self.currentNodeSource == MENU_ROOT_PATH then
        headerTitle = node.headerTitle or headerTitle
    end
    if type(headerTitle) == "string" and headerTitle ~= "" then
        form.addStaticText(line, self:_headerTitlePos(), headerTitle)
    end
    self:_addNavigationButtons()
end

function App:_valuePos()
    local width = self:_windowSize()
    local radio = self.radio
    return {
        x = math.floor(width * 0.56),
        y = radio.linePaddingTop or 0,
        w = math.floor(width * 0.34),
        h = radio.navbuttonHeight or 30
    }
end

function App:_addStaticLine(label, value, key)
    local line = form.addLine(label)
    local field = form.addStaticText(line, self:_valuePos(), value)
    if key then
        self.statusFields[key] = field
    end
    return field
end

function App:_buildGridButtons(items)
    local prefsIndex = self:_getSelectedIndex(self.currentNodeSource)
    local metrics = self:_menuButtonMetrics()
    local iconsize = self:_iconsize()
    local lc = 0
    local y = 0
    local activeGroup = nil
    local buttonIndex = 0

    for _, item in ipairs(items) do
        if item.kind == "menu" or item.kind == "page" then
            buttonIndex = buttonIndex + 1

            if type(item.group) == "string" and item.group ~= "" and item.group ~= activeGroup then
                activeGroup = item.group
                lc = 0
                if type(item.groupTitle) == "string" and item.groupTitle ~= "" and not (self.currentNodeSource == MENU_ROOT_PATH and buttonIndex == 1) then
                    form.addLine(item.groupTitle)
                end
            end

            if lc == 0 then
                y = form.height() + ((iconsize == 2) and self.radio.buttonPadding or self.radio.buttonPaddingSmall)
            end

            local bx = (metrics.buttonW + metrics.padding) * lc
            local icon = nil
            if iconsize ~= 0 and item.image then
                icon = self:_loadMask(item.image)
            end

            local field = form.addButton(nil, {x = bx, y = y, w = metrics.buttonW, h = metrics.buttonH}, {
                text = item.title or item.id or ("Item " .. tostring(buttonIndex)),
                icon = icon,
                options = FONT_S,
                paint = NOOP_PAINT,
                press = function()
                    self:_enterItem(buttonIndex, item)
                end
            })

            self.buttonFields[buttonIndex] = field
            if field and field.enable then
                field:enable(item.disabled ~= true)
            end
            if buttonIndex == prefsIndex and field and field.focus then
                field:focus()
            end

            lc = lc + 1
            if lc == metrics.numPerRow then
                lc = 0
            end
        else
            local line = form.addLine(item.title or item.id or "Value")
            local field = form.addStaticText(line, self:_statusPos(), self:_resolveItemValue(item))
            self.valueFields[#self.valueFields + 1] = {item = item, field = field}
        end
    end
end

function App:_buildNodeForm()
    local node = self.currentNode or self:_loadRootNode()

    safeFormClear()
    self:_clearFormRefs()

    self:_addHeader(node)
    self:_buildGridButtons(node.items or {})
end

function App:_rebuildFormIfNeeded()
    if self.formDirty ~= true then
        return
    end
    self.formDirty = false
    self:_buildNodeForm()
end

function App:_updateValueFields()
    for _, entry in ipairs(self.valueFields) do
        if entry.field and entry.field.value then
            entry.field:value(self:_resolveItemValue(entry.item))
        end
    end
end

function App:wakeup()
    self:_refreshSnapshot()
    if self.currentNode == nil then
        self.currentNode = self:_loadRootNode()
    end
    self:_rebuildFormIfNeeded()
    self:_updateValueFields()
end

function App:paint()
end

function App:event(category, value, x, y)
    local _ = x
    _ = y
    if isCloseEvent(category, value) then
        if self:_goBack() then
            return true
        end
        return false
    end
    return false
end

function App:onActivate()
    self:_openRoot()
end

function App:onDeactivate()
    safeFormClear()
    self:_clearFormRefs()
    self.currentNode = nil
    self.pathStack = {}
end

function App:close()
    safeFormClear()
    self:_clearFormRefs()
    self.currentNode = nil
    self.pathStack = nil
    self.snapshot = nil
    self.telemetryTask = nil
    self.maskCache = nil
    self.maskCacheOrder = nil
    pcall(function()
        self.framework.preferences:save()
    end)
    self.framework = nil
    collectgarbage("collect")
end

return App
