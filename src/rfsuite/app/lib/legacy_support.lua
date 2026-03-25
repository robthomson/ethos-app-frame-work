--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local support = {}

local state = {
    app = nil,
    node = nil
}

local function framework()
    return state.app and state.app.framework or nil
end

local function triggerSideEffect(key, value)
    local app = state.app

    if value ~= true or app == nil then
        return
    end

    if key == "closeProgressLoader" or key == "closeSave" then
        if app.ui and app.ui.clearProgressDialog then
            app.ui.clearProgressDialog(true)
        elseif app.clearLoader then
            app:clearLoader(true)
        end
    elseif key == "showSaveArmedWarning" then
        if app.ui and app.ui.clearProgressDialog then
            app.ui.clearProgressDialog(true)
        elseif app.clearLoader then
            app:clearLoader(true)
        end
    end
end

local triggerProxy = setmetatable({}, {
    __newindex = function(tbl, key, value)
        rawset(tbl, key, value)
        triggerSideEffect(key, value)
    end
})

local pageProxy = setmetatable({}, {
    __index = function(_, key)
        local node = state.node
        return node and node[key] or nil
    end,
    __newindex = function(_, key, value)
        local app = state.app
        local node = state.node

        if node == nil then
            return
        end

        node[key] = value
        if key == "navButtons" and app and app._syncSaveButtonState then
            app:_syncSaveButtonState()
        end
    end
})

local function addLegacyHeader(title)
    local app = state.app
    local node = state.node

    if app == nil or node == nil then
        return
    end

    if type(title) == "string" and title ~= "" then
        node.title = title
    end

    if app._addHeader then
        app:_addHeader(node)
    end
end

local uiProxy = setmetatable({}, {
    __index = function(_, key)
        local app = state.app
        local ui = app and app._createUiBridge and app:_createUiBridge() or nil
        local value = ui and ui[key] or nil

        if key == "fieldHeader" then
            return addLegacyHeader
        end

        return value
    end
})

local appProxy = setmetatable({
    ui = uiProxy,
    triggers = triggerProxy,
    Page = pageProxy
}, {
    __index = function(_, key)
        local app = state.app

        if key == "radio" then
            return app and app.radio or {}
        end
        if key == "lcdWidth" then
            return app and app._windowSize and select(1, app:_windowSize()) or select(1, lcd.getWindowSize())
        end
        if key == "lcdHeight" then
            return app and app._windowSize and select(2, app:_windowSize()) or select(2, lcd.getWindowSize())
        end
        if key == "formNavigationFields" then
            return app and app.navFields or {}
        end

        return app and app[key] or nil
    end,
    __newindex = function(_, key, value)
        local app = state.app
        if app ~= nil then
            app[key] = value
        end
    end
})

local tasksProxy = setmetatable({}, {
    __index = function(_, key)
        local app = state.app
        local fw = app and app.framework or nil
        local mspTask = fw and fw.getTask and fw:getTask("msp") or nil

        if key == "msp" then
            return mspTask
        end
        if key == "callback" then
            return app and app.callback or nil
        end

        return nil
    end
})

local rfsuiteProxy = setmetatable({
    app = appProxy,
    tasks = tasksProxy,
    utils = utils
}, {
    __index = function(_, key)
        local fw = framework()

        if key == "preferences" then
            return fw and fw.preferences or nil
        end
        if key == "session" then
            return fw and fw.session or nil
        end

        return nil
    end
})

function support.setContext(app, node)
    state.app = app
    state.node = node
    return rfsuiteProxy
end

function support.get()
    return rfsuiteProxy
end

return support
