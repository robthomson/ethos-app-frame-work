--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local escTools = {}

local function session(app)
    local framework = app and app.framework or nil
    return framework and framework.session or nil
end

function escTools.setSessionValue(app, key, value)
    local store = session(app)

    if store and store.set then
        store:set(key, value)
    end
end

function escTools.getSessionValue(app, key, defaultValue)
    local store = session(app)

    if store and store.get then
        return store:get(key, defaultValue)
    end

    return defaultValue
end

function escTools.showLoader(app, options)
    if app and app.ui and app.ui.showLoader then
        app.ui.showLoader(options)
    end
end

function escTools.clearLoader(app)
    if app and app.requestLoaderClose then
        app:requestLoaderClose()
    elseif app and app.ui and app.ui.clearProgressDialog then
        app.ui.clearProgressDialog(true)
    end
end

function escTools.nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

function escTools.statusPos(app)
    local width = app and app._windowSize and app:_windowSize() or select(1, lcd.getWindowSize())
    local radio = app and app.radio or {}

    return {
        x = 8,
        y = radio.linePaddingTop or 0,
        w = math.max(40, width - 16),
        h = radio.navbuttonHeight or 30
    }
end

function escTools.gridLayout(app)
    local prefs = app and app.framework and app.framework.preferences and app.framework.preferences:section("general", {}) or {}
    local iconSize = tonumber(prefs.iconsize)
    local width = app and app._windowSize and app:_windowSize() or select(1, lcd.getWindowSize())
    local radio = app and app.radio or {}
    local padding
    local buttonW
    local buttonH
    local perRow

    if iconSize == nil then
        iconSize = 1
    end

    if iconSize == 0 then
        padding = radio.buttonPaddingSmall or 6
        perRow = radio.buttonsPerRow or 3
        buttonW = math.floor((width - padding) / perRow) - padding
        buttonH = radio.navbuttonHeight or 30
    elseif iconSize == 2 then
        padding = radio.buttonPadding or 8
        buttonW = radio.buttonWidth or 110
        buttonH = radio.buttonHeight or 82
        perRow = radio.buttonsPerRow or 3
    else
        padding = radio.buttonPaddingSmall or 6
        buttonW = radio.buttonWidthSmall or 92
        buttonH = radio.buttonHeightSmall or 68
        perRow = radio.buttonsPerRowSmall or 4
    end

    return padding, buttonW, buttonH, perRow, iconSize
end

function escTools.loadMask(state, path)
    state.icons = state.icons or {}

    if state.icons[path] == nil then
        state.icons[path] = lcd.loadMask(path)
    end

    return state.icons[path]
end

function escTools.renderGrid(node, app, items)
    local padding
    local buttonW
    local buttonH
    local perRow
    local iconSize
    local baseY
    local index
    local item
    local col
    local row
    local x
    local y

    padding, buttonW, buttonH, perRow, iconSize = escTools.gridLayout(app)
    baseY = form.height() + padding

    for index = 1, #items do
        item = items[index]
        col = (index - 1) % perRow
        row = math.floor((index - 1) / perRow)
        x = col * (buttonW + padding)
        y = baseY + row * (buttonH + padding)

        form.addButton(nil, {x = x, y = y, w = buttonW, h = buttonH}, {
            text = item.title,
            icon = iconSize ~= 0 and item.image and escTools.loadMask(node.state, item.image) or nil,
            options = FONT_S,
            paint = function() end,
            press = item.press
        })
    end
end

return escTools
