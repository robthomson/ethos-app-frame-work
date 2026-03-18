--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local App = {}

local MENU_ROOT_PATH = "app/menu/root.lua"
local MASK_CACHE_MAX = 16
local NOOP_PAINT = function() end
local HEADER_NAV_HEIGHT_REDUCTION = 4
local HEADER_NAV_Y_SHIFT = 6
local HEADER_BREADCRUMB_Y_OFFSET = 5

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

local function trimText(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function appendBreadcrumbPart(parts, part)
    part = trimText(part)
    if part == "" then
        return
    end

    if parts[#parts] == part then
        return
    end

    parts[#parts + 1] = part
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
    local buttonH = math.max(20, (radio.navbuttonHeight or 30) - HEADER_NAV_HEIGHT_REDUCTION)
    local padding = 5
    local compactW = buttonW - math.floor((buttonW * 20) / 100)
    local reserved = (buttonW + padding) * 4 + (compactW + padding)
    return {
        width = width,
        buttonW = buttonW,
        compactW = compactW,
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

function App:_headerNavY()
    return math.max(0, (self.radio.linePaddingTop or 6) - HEADER_NAV_Y_SHIFT)
end

function App:_headerTitleY()
    return self:_headerNavY()
end

function App:_headerBreadcrumbY()
    local metrics = self:_headerMetrics()
    return self:_headerNavY() + metrics.buttonH + HEADER_BREADCRUMB_Y_OFFSET
end

function App:_fitTextToWidth(text, maxWidth)
    local value = trimText(text)
    if value == "" or type(maxWidth) ~= "number" or maxWidth <= 0 then
        return ""
    end

    if not (lcd and lcd.getTextSize) then
        return value
    end

    if lcd.getTextSize(value) <= maxWidth then
        return value
    end

    local ellipsis = "..."
    local clipped = value
    while #clipped > 0 and lcd.getTextSize(clipped .. ellipsis) > maxWidth do
        clipped = clipped:sub(1, -2)
    end

    if clipped == "" then
        return ellipsis
    end

    return clipped .. ellipsis
end

function App:_nodeTitle(node, source)
    if type(node) ~= "table" then
        return nil
    end

    if source == MENU_ROOT_PATH and type(node.headerTitle) == "string" and trimText(node.headerTitle) ~= "" then
        return node.headerTitle
    end

    if type(node.title) == "string" and trimText(node.title) ~= "" then
        return node.title
    end

    return nil
end

function App:_nodeBreadcrumb(node)
    if type(node) ~= "table" then
        return nil
    end

    local breadcrumb = trimText(node.breadcrumb)
    if breadcrumb ~= "" then
        return breadcrumb
    end

    local subtitle = trimText(node.subtitle)
    if subtitle == "" then
        return nil
    end

    local title = trimText(node.title)
    if title ~= "" then
        local suffix = " / " .. title
        if subtitle:sub(-#suffix) == suffix then
            subtitle = trimText(subtitle:sub(1, #subtitle - #suffix))
        elseif subtitle == title then
            subtitle = ""
        end
    end

    if subtitle == "" then
        return nil
    end

    return subtitle
end

function App:_joinBreadcrumb(base, leaf)
    local parts = {}
    local start = trimText(base)

    if start ~= "" then
        for part in start:gmatch("([^/]+)") do
            appendBreadcrumbPart(parts, part)
        end
    end

    appendBreadcrumbPart(parts, leaf)

    if #parts == 0 then
        return nil
    end

    return table.concat(parts, " / ")
end

function App:_breadcrumbForItem(item)
    if type(item) ~= "table" then
        return nil
    end

    if self.currentNodeSource == MENU_ROOT_PATH then
        local rootGroup = item.groupTitle
            or (self.currentNode and self.currentNode.headerTitle)
            or self:_nodeTitle(self.currentNode, self.currentNodeSource)
        rootGroup = trimText(rootGroup)
        if rootGroup ~= "" then
            return rootGroup
        end
        return nil
    end

    return self:_joinBreadcrumb(
        self:_nodeBreadcrumb(self.currentNode),
        self:_nodeTitle(self.currentNode, self.currentNodeSource)
    )
end

function App:_breadcrumbText()
    if self.currentNodeSource == MENU_ROOT_PATH then
        return nil
    end

    return self:_nodeBreadcrumb(self.currentNode)
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
            breadcrumb = self:_nodeBreadcrumb(self.currentNode),
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
            breadcrumb = nil,
            items = {
                {id = "error", title = "Menu Error", kind = "static", value = tostring(err)}
            }
        }
    end

    self.rootLoadError = nil
    node.breadcrumb = nil
    return node
end

function App:_openRoot()
    self.pathStack = {}
    self.currentNodeSource = MENU_ROOT_PATH
    self.currentNode = self:_loadRootNode()
    self:_invalidateForm()
end

function App:_makeLeafNode(item, breadcrumb)
    return {
        title = item.title or item.id or "Page",
        subtitle = item.subtitle or "Page scaffold",
        breadcrumb = breadcrumb,
        navButtons = item.navButtons or {menu = true, save = false, reload = false, tool = false, help = false},
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

    local breadcrumb = self:_breadcrumbForItem(item)

    self:_setSelectedIndex(self.currentNodeSource, index)
    self.pathStack[#self.pathStack + 1] = {
        source = self.currentNodeSource,
        node = self.currentNode
    }

    if item.kind == "menu" and type(item.source) == "string" then
        self.currentNodeSource = item.source
        self.currentNode = self:_loadNodeFromSource(item.source)
        self.currentNode.breadcrumb = breadcrumb
    else
        self.currentNodeSource = "leaf:" .. tostring(item.id or index)
        self.currentNode = self:_makeLeafNode(item, breadcrumb)
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
        y = self:_headerTitleY(),
        w = metrics.titleWidth,
        h = radio.navbuttonHeight or 30
    }
end

function App:_navButtonsForNode(node)
    local buttons = node and node.navButtons
    if type(buttons) == "table" then
        return {
            menu = buttons.menu == true,
            save = buttons.save == true,
            reload = buttons.reload == true,
            tool = buttons.tool == true,
            help = buttons.help == true
        }
    end

    return {menu = true, save = false, reload = false, tool = false, help = false}
end

function App:_requestExit()
    if self.framework and self.framework.deactivateApp then
        self.framework:deactivateApp()
    end

    if system and system.exit then
        system.exit()
    end

    return true
end

function App:_addNavigationButtons()
    local metrics = self:_headerMetrics()
    local y = self:_headerNavY()
    local xRight = metrics.width - 5
    local atRoot = (#self.pathStack == 0)
    local navConfig = self:_navButtonsForNode(self.currentNode)
    local defs = {
        {
            key = "menu",
            text = "Menu",
            compact = false,
            enabled = navConfig.menu == true,
            press = function()
                if atRoot then
                    self:_requestExit()
                else
                    self:_goBack()
                end
            end
        },
        {
            key = "save",
            text = "Save",
            compact = false,
            enabled = navConfig.save == true,
            press = function() end
        },
        {
            key = "reload",
            text = "Reload",
            compact = false,
            enabled = navConfig.reload == true,
            press = function() end
        },
        {
            key = "tool",
            text = "*",
            compact = true,
            enabled = navConfig.tool == true,
            press = function() end
        },
        {
            key = "help",
            text = "Help",
            compact = false,
            enabled = navConfig.help == true,
            press = function() end
        }
    }

    for i = #defs, 1, -1 do
        local def = defs[i]
        local bx
        local field
        local width = def.compact == true and metrics.compactW or metrics.buttonW

        bx = xRight - width
        field = form.addButton(nil, {x = bx, y = y, w = width, h = metrics.buttonH}, {
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
            local field = form.addStaticText(line, self:_valuePos(), self:_resolveItemValue(item))
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
    local breadcrumb = self:_breadcrumbText()
    local width

    if breadcrumb == nil or not (lcd and lcd.drawText and lcd.font) then
        return
    end

    width = self:_windowSize()
    breadcrumb = self:_fitTextToWidth(breadcrumb, math.max(40, width - 8))
    if breadcrumb == "" then
        return
    end

    lcd.font(FONT_XXS or FONT_XS or FONT_STD)
    if lcd.color and lcd.RGB then
        lcd.color(lcd.RGB(170, 170, 170))
    end
    lcd.drawText(0, self:_headerBreadcrumbY(), breadcrumb)
end

function App:event(category, value, x, y)
    local _ = x
    _ = y
    if isCloseEvent(category, value) then
        if self:_goBack() then
            return true
        end
        return self:_requestExit()
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
