--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

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

local function prefBool(value, default)
    if value == nil then
        return default
    end
    if value == true or value == "true" or value == 1 or value == "1" then
        return true
    end
    if value == false or value == "false" or value == 0 or value == "0" then
        return false
    end
    return default
end

local function containerWithLines(title)
    if form and form.addExpansionPanel then
        return form.addExpansionPanel(title)
    end

    return {
        addLine = function(_, label)
            return form.addLine(label)
        end
    }
end

local function addLine(container, label)
    if container and container.addLine then
        return container:addLine(label)
    end
    return form.addLine(label)
end

local function addChoice(container, label, choices, getter, setter)
    return form.addChoiceField(addLine(container, label), nil, choices, getter, setter)
end

local function addBoolean(container, label, getter, setter)
    return form.addBooleanField(addLine(container, label), nil, getter, setter)
end

local function addNumber(container, label, minValue, maxValue, getter, setter, suffix)
    local field = form.addNumberField(addLine(container, label), nil, minValue, maxValue, getter, setter)

    if field and field.suffix and suffix then
        field:suffix(suffix)
    end
    if field and field.minimum then
        field:minimum(minValue)
    end
    if field and field.maximum then
        field:maximum(maxValue)
    end

    return field
end

local function readState(framework)
    return copyTable(framework.preferences:section("general", {}))
end

function Page:open(ctx)
    local state = readState(ctx.framework)
    local node = {
        title = ctx.item.title or "General",
        subtitle = ctx.item.subtitle or "General settings",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = false, tool = false, help = false}
    }

    local function resetState()
        local fresh = readState(ctx.framework)

        for key in pairs(state) do
            state[key] = nil
        end
        for key, value in pairs(fresh) do
            state[key] = value
        end
    end

    function node:buildForm(app)
        local displayPanel = containerWithLines("Display")
        local safetyPanel = containerWithLines("Safety")
        local integrationPanel = containerWithLines("Integration")
        local developerPanel = containerWithLines("Developer")

        addChoice(displayPanel, "Icon Size", ICON_SIZE_CHOICES,
            function()
                return state.iconsize ~= nil and state.iconsize or 1
            end,
            function(newValue)
                state.iconsize = newValue
            end)

        addChoice(displayPanel, "TX Battery Style", TX_BATT_CHOICES,
            function()
                return state.txbatt_type ~= nil and state.txbatt_type or 0
            end,
            function(newValue)
                state.txbatt_type = newValue
            end)

        addChoice(displayPanel, "Loader Style", LOADER_STYLE_CHOICES,
            function()
                return state.theme_loader ~= nil and state.theme_loader or 1
            end,
            function(newValue)
                state.theme_loader = newValue
            end)

        addChoice(displayPanel, "Loader Close Mode", LOADER_CLOSE_CHOICES,
            function()
                return state.hs_loader ~= nil and state.hs_loader or 1
            end,
            function(newValue)
                state.hs_loader = newValue
            end)

        addNumber(displayPanel, "Toolbar Timeout", 5, 30,
            function()
                return state.toolbar_timeout ~= nil and state.toolbar_timeout or 10
            end,
            function(newValue)
                state.toolbar_timeout = newValue
            end,
            "s")

        addBoolean(displayPanel, "Collapse Unused Menu Entries",
            function()
                return prefBool(state.collapse_unused_menu_entries, false)
            end,
            function(newValue)
                state.collapse_unused_menu_entries = newValue
            end)

        addBoolean(safetyPanel, "Confirm Before Save",
            function()
                return prefBool(state.save_confirm, true)
            end,
            function(newValue)
                state.save_confirm = newValue
            end)

        addBoolean(safetyPanel, "Save Only When Dirty",
            function()
                return prefBool(state.save_dirty_only, true)
            end,
            function(newValue)
                state.save_dirty_only = newValue
            end)

        addBoolean(safetyPanel, "Warn If Saving While Armed",
            function()
                return prefBool(state.save_armed_warning, true)
            end,
            function(newValue)
                state.save_armed_warning = newValue
            end)

        addBoolean(safetyPanel, "Confirm Before Reload",
            function()
                return prefBool(state.reload_confirm, false)
            end,
            function(newValue)
                state.reload_confirm = newValue
            end)

        addBoolean(safetyPanel, "Show Battery Profile On Connect",
            function()
                return prefBool(state.show_battery_profile_startup, true)
            end,
            function(newValue)
                state.show_battery_profile_startup = newValue
            end)

        addBoolean(safetyPanel, "Show Confirmation Dialogs",
            function()
                return prefBool(state.show_confirmation_dialog, true)
            end,
            function(newValue)
                state.show_confirmation_dialog = newValue
            end)

        addBoolean(integrationPanel, "Sync Model Name",
            function()
                return prefBool(state.syncname, false)
            end,
            function(newValue)
                state.syncname = newValue
            end)

        addBoolean(integrationPanel, "Show MSP Status Dialog",
            function()
                return prefBool(state.mspstatusdialog, true)
            end,
            function(newValue)
                state.mspstatusdialog = newValue
            end)

        addBoolean(developerPanel, "Enable Developer Tools",
            function()
                return prefBool(state.developer_tools, false)
            end,
            function(newValue)
                state.developer_tools = newValue
            end)
    end

    function node:getGeneralPreferences()
        return state
    end

    function node:save(app)
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

        app:_invalidateForm()
        return true
    end

    function node:reload(app)
        resetState()
        app:_invalidateForm()
        return true
    end

    return node
end

return Page
