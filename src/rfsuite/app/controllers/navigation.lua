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
    return setmetatable({
        shared = shared
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
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
    local app = self:_app()
    local node = app and app.currentNode or nil
    local navConfig = self:buttonsForNode(node)
    local metrics = app and app._headerMetrics and app:_headerMetrics() or {}
    local y = app and app._headerNavY and app:_headerNavY() or 0
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
                if app and app._handleMenuAction then
                    app:_handleMenuAction()
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
                if app and app._handleSaveAction then
                    app:_handleSaveAction()
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
                if app and app._handleReloadAction then
                    app:_handleReloadAction()
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
                if app and app._handleToolAction then
                    app:_handleToolAction()
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
                if app and app._handleHelpAction then
                    app:_handleHelpAction()
                end
            end
        }
    }

    if app and app._collapseNavigation and app:_collapseNavigation() == true then
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
            icon = type(def.icon) == "string" and app and app._loadMask and app:_loadMask(def.icon) or nil,
            options = FONT_S,
            paint = function() end,
            press = def.press
        })

        if field and field.enable then
            if def.key == "save" then
                field:enable(app and app._canSaveNode and app:_canSaveNode(node) or false)
            elseif def.key == "menu" then
                field:enable(def.visible == true and not (app and app.pendingDialogActionLocked == true))
            else
                field:enable(def.visible == true)
            end
        end
        if app then
            app.navFields[def.key] = field
        end
        xRight = bx - 5
    end
end

function controller:addHeader(node, menuRootPath)
    local app = self:_app()
    local line = form.addLine("")
    local currentSource = app and app.currentNodeSource or nil
    local headerTitle = (node and node.title) or "Rotorflight"

    if currentSource == menuRootPath then
        headerTitle = node.headerTitle or headerTitle
    end
    if type(headerTitle) == "string" and headerTitle ~= "" then
        local field = form.addStaticText(line, app and app._headerTitlePos and app:_headerTitlePos() or {}, headerTitle)
        if app then
            app.headerTitleField = field
            if app.formHost and app.formHost.state then
                app.formHost.state.headerTitleField = field
            end
        end
    end
    self:addNavigationButtons()
end

function controller:setHeaderTitle(title, menuRootPath)
    local app = self:_app()
    local headerTitle = tostring(title or "")
    local node = app and app.currentNode or nil
    local currentSource = app and app.currentNodeSource or nil
    local field = app and app.headerTitleField or nil

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
    local app = self:_app()
    local navFields = app and app.navFields or nil
    local node = app and app.currentNode or nil
    local save = navFields and navFields.save or nil

    if save and save.enable then
        save:enable(app and app._canSaveNode and app:_canSaveNode(node) or false)
    end
end

function controller:syncActionLockState()
    local app = self:_app()
    local navFields = app and app.navFields or nil
    local node = app and app.currentNode or nil
    local menu = navFields and navFields.menu or nil
    local navConfig = self:buttonsForNode(node)

    if menu and menu.enable then
        menu:enable(navConfig.menu.enabled == true and not (app and app.pendingDialogActionLocked == true))
    end
end

function controller:focusNavigationButton(key)
    local app = self:_app()
    local navFields = app and app.navFields or nil
    local field = navFields and navFields[key] or nil

    if field and field.focus then
        pcall(field.focus, field)
        return true
    end

    return false
end

return controller
