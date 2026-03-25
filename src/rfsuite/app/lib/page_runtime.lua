--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ethos_events = require("framework.utils.ethos_events")

local runtime = {}

local function handleMenu(app, options)
    if type(options.onClose) == "function" then
        return options.onClose()
    end

    if app and app._handleMenuAction then
        return app:_handleMenuAction()
    end

    return true
end

function runtime.openMenuContext(app, opts)
    return handleMenu(app, opts or {})
end

function runtime.handleCloseEvent(app, category, value, opts)
    if ethos_events.isCloseEvent(category, value) ~= true then
        return nil
    end

    return handleMenu(app, opts or {})
end

function runtime.createMenuHandlers(app, opts)
    local options = opts or {}
    local activeApp = app

    if opts == nil and type(app) == "table" and app._handleMenuAction == nil then
        local ok, legacy = pcall(require, "rfsuite")
        options = app or {}
        activeApp = ok and legacy and legacy.app or nil
    end

    return {
        onNavMenu = function()
            return handleMenu(activeApp, options)
        end,
        event = function(_, category, value)
            return runtime.handleCloseEvent(activeApp, category, value, options)
        end
    }
end

return runtime
