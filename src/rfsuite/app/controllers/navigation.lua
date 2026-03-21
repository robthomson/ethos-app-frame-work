--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

local function normalizeNavButton(value)
    if type(value) == "table" then
        return {
            enabled = value.enabled ~= false,
            icon = value.icon,
            text = value.text
        }
    end

    return {
        enabled = value == true,
        icon = nil,
        text = nil
    }
end

function controller.new(shared, options)
    local opts = options or {}

    return setmetatable({
        shared = shared,
        getCurrentNode = opts.getCurrentNode,
        getCurrentNodeSource = opts.getCurrentNodeSource,
        getPathStack = opts.getPathStack,
        headerMetrics = opts.headerMetrics,
        headerNavY = opts.headerNavY,
        headerTitlePos = opts.headerTitlePos,
        collapseNavigation = opts.collapseNavigation,
        loadMask = opts.loadMask,
        canSaveNode = opts.canSaveNode,
        handleMenuAction = opts.handleMenuAction,
        handleSaveAction = opts.handleSaveAction,
        handleReloadAction = opts.handleReloadAction,
        handleToolAction = opts.handleToolAction,
        handleHelpAction = opts.handleHelpAction,
        getNavFields = opts.getNavFields,
        setNavField = opts.setNavField,
        getHeaderTitleField = opts.getHeaderTitleField,
        setHeaderTitleField = opts.setHeaderTitleField
    }, controller_mt)
end

function controller:buttonsForNode(node)
    local buttons = node and node.navButtons

    if type(buttons) == "table" then
        return {
            menu = normalizeNavButton(buttons.menu),
            save = normalizeNavButton(buttons.save),
            reload = normalizeNavButton(buttons.reload),
            tool = normalizeNavButton(buttons.tool),
            help = normalizeNavButton(buttons.help)
        }
    end

    return {
        menu = normalizeNavButton(true),
        save = normalizeNavButton(false),
        reload = normalizeNavButton(false),
        tool = normalizeNavButton(false),
        help = normalizeNavButton(false)
    }
end

function controller:addNavigationButtons()
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local navConfig = self:buttonsForNode(node)
    local metrics = type(self.headerMetrics) == "function" and self.headerMetrics() or {}
    local y = type(self.headerNavY) == "function" and self.headerNavY() or 0
    local xRight = (metrics.width or 0) - 12
    local renderDefs = {}
    local defs = {
        {
            key = "menu",
            text = "Menu",
            compact = false,
            visible = navConfig.menu.enabled == true,
            icon = navConfig.menu.icon,
            press = function()
                if type(self.handleMenuAction) == "function" then
                    self.handleMenuAction()
                end
            end
        },
        {
            key = "save",
            text = "Save",
            compact = false,
            visible = navConfig.save.enabled == true,
            icon = navConfig.save.icon,
            press = function()
                if type(self.handleSaveAction) == "function" then
                    self.handleSaveAction()
                end
            end
        },
        {
            key = "reload",
            text = "Reload",
            compact = false,
            visible = navConfig.reload.enabled == true,
            icon = navConfig.reload.icon,
            press = function()
                if type(self.handleReloadAction) == "function" then
                    self.handleReloadAction()
                end
            end
        },
        {
            key = "tool",
            text = navConfig.tool.text or "*",
            compact = true,
            visible = navConfig.tool.enabled == true,
            icon = navConfig.tool.icon,
            press = function()
                if type(self.handleToolAction) == "function" then
                    self.handleToolAction()
                end
            end
        },
        {
            key = "help",
            text = navConfig.help.text or "?",
            compact = true,
            visible = navConfig.help.enabled == true,
            icon = navConfig.help.icon,
            press = function()
                if type(self.handleHelpAction) == "function" then
                    self.handleHelpAction()
                end
            end
        }
    }

    if type(self.collapseNavigation) == "function" and self.collapseNavigation() == true then
        for i = 1, #defs do
            if defs[i].visible == true then
                renderDefs[#renderDefs + 1] = defs[i]
            end
        end
    else
        renderDefs = defs
    end

    for i = #renderDefs, 1, -1 do
        local def = renderDefs[i]
        local width = def.compact == true and (metrics.compactW or 0) or (metrics.buttonW or 0)
        local bx = xRight - width
        local field = form.addButton(nil, {x = bx, y = y, w = width, h = metrics.buttonH or 0}, {
            text = def.text,
            icon = type(def.icon) == "string" and type(self.loadMask) == "function" and self.loadMask(def.icon) or nil,
            options = FONT_S,
            paint = function() end,
            press = def.press
        })

        if field and field.enable then
            if def.key == "save" then
                field:enable(type(self.canSaveNode) == "function" and self.canSaveNode(node) or false)
            else
                field:enable(def.visible == true)
            end
        end
        if type(self.setNavField) == "function" then
            self.setNavField(def.key, field)
        end
        xRight = bx - 5
    end
end

function controller:addHeader(node, menuRootPath)
    local line = form.addLine("")
    local currentSource = type(self.getCurrentNodeSource) == "function" and self.getCurrentNodeSource() or nil
    local headerTitle = (node and node.title) or "Rotorflight"

    if currentSource == menuRootPath then
        headerTitle = node.headerTitle or headerTitle
    end
    if type(headerTitle) == "string" and headerTitle ~= "" then
        local field = form.addStaticText(line, type(self.headerTitlePos) == "function" and self.headerTitlePos() or {}, headerTitle)
        if type(self.setHeaderTitleField) == "function" then
            self.setHeaderTitleField(field)
        end
    end
    self:addNavigationButtons()
end

function controller:setHeaderTitle(title, menuRootPath)
    local headerTitle = tostring(title or "")
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local currentSource = type(self.getCurrentNodeSource) == "function" and self.getCurrentNodeSource() or nil
    local field = type(self.getHeaderTitleField) == "function" and self.getHeaderTitleField() or nil

    if type(node) == "table" then
        if currentSource == menuRootPath then
            node.headerTitle = headerTitle
        else
            node.title = headerTitle
        end
    end

    if field and field.value then
        pcall(field.value, field, headerTitle)
    end

    return true
end

function controller:syncSaveButtonState()
    local navFields = type(self.getNavFields) == "function" and self.getNavFields() or nil
    local node = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local save = navFields and navFields.save or nil

    if save and save.enable then
        save:enable(type(self.canSaveNode) == "function" and self.canSaveNode(node) or false)
    end
end

function controller:focusNavigationButton(key)
    local navFields = type(self.getNavFields) == "function" and self.getNavFields() or nil
    local field = navFields and navFields[key] or nil

    if field and field.focus then
        pcall(field.focus, field)
        return true
    end

    return false
end

return controller
