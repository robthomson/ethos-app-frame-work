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
    local opts = options or {}

    return setmetatable({
        shared = shared,
        clearFocusRestore = opts.clearFocusRestore,
        getModalDialogDepth = opts.getModalDialogDepth,
        isLoaderModalActive = opts.isLoaderModalActive,
        getReturnMenuArmed = opts.getReturnMenuArmed,
        setReturnMenuArmed = opts.setReturnMenuArmed,
        requestExit = opts.requestExit,
        focusNavigationButton = opts.focusNavigationButton,
        handleMenuAction = opts.handleMenuAction,
        handleSaveAction = opts.handleSaveAction,
        navButtonsForNode = opts.navButtonsForNode,
        getCurrentNode = opts.getCurrentNode,
        runNodeHook = opts.runNodeHook
    }, controller_mt)
end

function controller:route(category, value, x, y)
    local currentNode = type(self.getCurrentNode) == "function" and self.getCurrentNode() or nil
    local returnMenuArmed = type(self.getReturnMenuArmed) == "function" and self.getReturnMenuArmed() == true or false

    if isRotaryNavigationEvent(value) == true and type(self.clearFocusRestore) == "function" then
        self.clearFocusRestore()
    end

    if type(self.getModalDialogDepth) == "function" and (self.getModalDialogDepth() or 0) > 0 then
        return false
    end

    if isMenuKeyEvent(value) ~= true and type(self.setReturnMenuArmed) == "function" then
        self.setReturnMenuArmed(false)
        returnMenuArmed = false
    end

    if isExitLongEvent(value) then
        suppressFollowupKeyEvent(value)
        return type(self.requestExit) == "function" and self.requestExit() or false
    end

    if isMenuKeyEvent(value) then
        if returnMenuArmed == true then
            if type(self.setReturnMenuArmed) == "function" then
                self.setReturnMenuArmed(false)
            end
            return type(self.handleMenuAction) == "function" and self.handleMenuAction() or false
        end
        if type(self.focusNavigationButton) == "function" and self.focusNavigationButton("menu") == true then
            if type(self.setReturnMenuArmed) == "function" then
                self.setReturnMenuArmed(true)
            end
            suppressFollowupKeyEvent(value)
            return true
        end
        return type(self.handleMenuAction) == "function" and self.handleMenuAction() or false
    end

    if isCloseEvent(category, value) then
        return type(self.handleMenuAction) == "function" and self.handleMenuAction() or false
    end

    if isSaveKeyEvent(value) then
        if type(self.isLoaderModalActive) == "function" and self.isLoaderModalActive() == true then
            suppressFollowupKeyEvent(value)
            return true
        end
        if type(self.navButtonsForNode) == "function" and self.navButtonsForNode(currentNode).save.enabled == true then
            if type(self.handleSaveAction) == "function" then
                self.handleSaveAction()
            end
        end
        suppressFollowupKeyEvent(value)
        return true
    end

    if type(self.isLoaderModalActive) == "function" and self.isLoaderModalActive() == true then
        return true
    end

    if type(self.runNodeHook) == "function" and self.runNodeHook(currentNode, "event", category, value, x, y) == true then
        return true
    end

    return false
end

return controller
