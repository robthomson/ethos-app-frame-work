--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ethos_events = require("framework.utils.ethos_events")

local controller = {}
local controller_mt = {__index = controller}

local function isCloseEvent(category, value)
    return ethos_events.isCloseEvent(category, value)
end

local function isSaveKeyEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_ENTER_LONG",
        "KEY_PAGE_LONG"
    })
end

local function isMenuKeyEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_RTN",
        "KEY_RTN_FIRST",
        "KEY_RTN_BREAK"
    })
end

local function isRotaryNavigationEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_ROTARY_LEFT",
        "KEY_ROTARY_RIGHT"
    })
end

local function isExitLongEvent(value)
    return ethos_events.matchesAnyConstant(value, {
        "KEY_RTN_LONG"
    })
end

local function suppressFollowupKeyEvent(value)
    local breakName = nil
    local breakValue

    if not (system and system.killEvents) then
        return
    end

    if ethos_events.matchesConstant(value, "KEY_ENTER_LONG") then
        breakName = "KEY_ENTER_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_PAGE_LONG") then
        breakName = "KEY_PAGE_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_RTN") or ethos_events.matchesConstant(value, "KEY_RTN_FIRST") then
        breakName = "KEY_RTN_BREAK"
    elseif ethos_events.matchesConstant(value, "KEY_RTN_LONG") then
        breakName = "KEY_RTN_BREAK"
    end

    if breakName == nil then
        return
    end

    breakValue = ethos_events.getConstant(breakName)
    if breakValue ~= nil then
        pcall(system.killEvents, breakValue)
    end
end

function controller.new(shared, options)
    return setmetatable({
        shared = shared
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:route(category, value, x, y)
    local app = self:_app()
    local currentNode = app and app.currentNode or nil
    local returnMenuArmed = app and app.returnMenuArmed == true or false

    if isRotaryNavigationEvent(value) == true and app and app.menuController and app.menuController.clearFocusRestore then
        app.menuController:clearFocusRestore()
    end

    if app and (app.modalDialogDepth or 0) > 0 then
        return false
    end

    if isMenuKeyEvent(value) ~= true and app then
        app.returnMenuArmed = false
        returnMenuArmed = false
    end

    if isExitLongEvent(value) then
        suppressFollowupKeyEvent(value)
        return app and app._requestExit and app:_requestExit() or false
    end

    if isMenuKeyEvent(value) then
        if returnMenuArmed == true then
            if app then
                app.returnMenuArmed = false
            end
            return app and app._handleMenuAction and app:_handleMenuAction() or false
        end
        if app and app._focusNavigationButton and app:_focusNavigationButton("menu") == true then
            if app then
                app.returnMenuArmed = true
            end
            suppressFollowupKeyEvent(value)
            return true
        end
        return app and app._handleMenuAction and app:_handleMenuAction() or false
    end

    if isCloseEvent(category, value) then
        return app and app._handleMenuAction and app:_handleMenuAction() or false
    end

    if isSaveKeyEvent(value) then
        if app and app.loader and app.loader.active and app.loader.active.modal == true then
            suppressFollowupKeyEvent(value)
            return true
        end
        if app and app._navButtonsForNode and app:_navButtonsForNode(currentNode).save.enabled == true and app._handleSaveAction then
            app:_handleSaveAction()
        end
        suppressFollowupKeyEvent(value)
        return true
    end

    if app and app.loader and app.loader.active and app.loader.active.modal == true then
        return true
    end

    if app and app._runNodeHook and app:_runNodeHook(currentNode, "event", category, value, x, y) == true then
        return true
    end

    return false
end

return controller
