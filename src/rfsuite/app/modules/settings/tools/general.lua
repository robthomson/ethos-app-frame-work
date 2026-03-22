--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local PrefsPage = ModuleLoader.requireOrLoad("app.lib.prefs_page", "app/lib/prefs_page.lua")

local ICON_SIZE_CHOICES = {
    {"Text", 0},
    {"Small", 1},
    {"Large", 2}
}

local TX_BATT_CHOICES = {
    {"Default", 0},
    {"Text", 1},
    {"Digital", 2}
}

local LOADER_STYLE_CHOICES = {
    {"Small", 0},
    {"Medium", 1},
    {"Large", 2}
}

local LOADER_CLOSE_CHOICES = {
    {"Fast Close", 0},
    {"Wait", 1}
}

local function copyTable(source)
    local out = {}

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
end

local Page = PrefsPage.create({
    title = "General",
    subtitle = "General settings",
    navButtons = {menu = true, save = true, reload = false, tool = false, help = false},
    readState = function(framework)
        return copyTable(framework.preferences:section("general", {}))
    end,
    sections = {
        {
            title = "Display",
            fields = {
                {kind = "choice", label = "Icon Size", key = "iconsize", choices = ICON_SIZE_CHOICES, get = function(state) return state.iconsize ~= nil and state.iconsize or 1 end},
                {kind = "choice", label = "TX Battery Style", key = "txbatt_type", choices = TX_BATT_CHOICES, get = function(state) return state.txbatt_type ~= nil and state.txbatt_type or 0 end},
                {kind = "choice", label = "Loader Style", key = "theme_loader", choices = LOADER_STYLE_CHOICES, get = function(state) return state.theme_loader ~= nil and state.theme_loader or 1 end},
                {kind = "choice", label = "Loader Close Mode", key = "hs_loader", choices = LOADER_CLOSE_CHOICES, get = function(state) return state.hs_loader ~= nil and state.hs_loader or 1 end},
                {kind = "number", label = "Toolbar Timeout", key = "toolbar_timeout", min = 5, max = 30, suffix = "s", get = function(state) return state.toolbar_timeout ~= nil and state.toolbar_timeout or 10 end},
                {kind = "boolean", label = "Collapse Unused Menu Entries", key = "collapse_unused_menu_entries", default = false}
            }
        },
        {
            title = "Safety",
            fields = {
                {kind = "boolean", label = "Confirm Before Save", key = "save_confirm", default = true},
                {kind = "boolean", label = "Save Only When Dirty", key = "save_dirty_only", default = true},
                {kind = "boolean", label = "Warn If Saving While Armed", key = "save_armed_warning", default = true},
                {kind = "boolean", label = "Confirm Before Reload", key = "reload_confirm", default = false},
                {kind = "boolean", label = "Show Battery Profile On Connect", key = "show_battery_profile_startup", default = true},
                {kind = "boolean", label = "Show Confirmation Dialogs", key = "show_confirmation_dialog", default = true}
            }
        },
        {
            title = "Integration",
            fields = {
                {kind = "boolean", label = "Sync Model Name", key = "syncname", default = false},
                {kind = "boolean", label = "Show MSP Status Dialog", key = "mspstatusdialog", default = true}
            }
        },
        {
            title = "Developer",
            fields = {
                {kind = "boolean", label = "Enable Developer Tools", key = "developer_tools", default = false}
            }
        }
    },
    save = function(_, app, state)
        local general = app.framework.preferences:section("general", {})
        local ok
        local err

        for key, value in pairs(state) do
            general[key] = value
        end

        ok, err = app.framework.preferences:save()
        if ok == false then
            app.framework.log:error("Failed saving general preferences: %s", tostring(err))
            return false
        end

        return true
    end,
    getGeneralPreferences = function(_, state)
        return state
    end
})

return Page
