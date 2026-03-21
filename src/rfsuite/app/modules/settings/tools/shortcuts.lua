--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local SHORTCUTS = assert(loadfile("app/lib/shortcuts.lua"))()
local GROUP_PREF_KEY = "settings_shortcuts_group"

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

local function copyMap(source)
    local out = {}

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function countSelected(configMap)
    local count = 0

    for _, value in pairs(configMap or {}) do
        if value == true then
            count = count + 1
        end
    end

    return count
end

local function showLimitDialog(maxSelected)
    if not (form and form.openDialog) then
        return
    end

    form.openDialog({
        width = nil,
        title = "@i18n(app.modules.settings.shortcuts)@",
        message = string.format("@i18n(app.modules.settings.shortcuts_limit)@", maxSelected),
        buttons = {
            {
                label = "@i18n(app.btn_ok)@",
                action = function()
                    return true
                end
            }
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
end

local function groupChoices(groups)
    local choices = {}
    local i

    for i = 1, #(groups or {}) do
        choices[#choices + 1] = {groups[i].title or ("Group " .. tostring(i)), i}
    end

    return choices
end

function Page:open(ctx)
    local registry = SHORTCUTS.buildRegistry(ctx.framework)
    local maxSelected = SHORTCUTS.getMaxSelected()
    local general = ctx.framework.preferences:section("general", {})
    local selectedPrefs = ctx.framework.preferences:section("shortcuts", {})
    local lastSelected = ctx.framework.preferences:section("menulastselected", {})
    local state = {
        registry = registry,
        config = copyMap(selectedPrefs),
        mixedIn = prefBool(general.shortcuts_mixed_in, true),
        groupIndex = tonumber(lastSelected[GROUP_PREF_KEY]) or 1
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.settings.shortcuts)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.settings.shortcuts_preferences)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        state = state
    }

    if state.groupIndex < 1 then
        state.groupIndex = 1
    end
    if state.groupIndex > #(registry.groups or {}) then
        state.groupIndex = #(registry.groups or {})
    end
    if state.groupIndex < 1 then
        state.groupIndex = 1
    end

    function node:buildForm(app)
        local line
        local groups = self.state.registry.groups or {}
        local group = groups[self.state.groupIndex]
        local item

        form.addBooleanField(form.addLine("@i18n(app.modules.settings.shortcuts_mixed_in_mode)@"), nil,
            function()
                return self.state.mixedIn == true
            end,
            function(newValue)
                self.state.mixedIn = prefBool(newValue, true)
            end)

        if #groups == 0 then
            line = form.addLine("@i18n(app.modules.settings.shortcuts_status_label)@")
            form.addStaticText(line, nil, "@i18n(app.modules.settings.shortcuts_none)@")
            return
        end

        form.addChoiceField(form.addLine("@i18n(app.modules.settings.shortcuts_group)@"), nil, groupChoices(groups),
            function()
                return self.state.groupIndex
            end,
            function(newValue)
                self.state.groupIndex = tonumber(newValue) or 1
                lastSelected[GROUP_PREF_KEY] = self.state.groupIndex
                app:_invalidateForm()
            end)

        if not group then
            line = form.addLine("@i18n(app.modules.settings.shortcuts_status_label)@")
            form.addStaticText(line, nil, "@i18n(app.modules.settings.shortcuts_group_selected_none)@")
            return
        end

        for _, item in ipairs(group.items or {}) do
            form.addBooleanField(form.addLine(item.title or item.id), nil,
                function()
                    return self.state.config[item.id] == true
                end,
                function(newValue)
                    local selected = prefBool(newValue, false)

                    if selected == true and self.state.config[item.id] ~= true and countSelected(self.state.config) >= maxSelected then
                        showLimitDialog(maxSelected)
                        app:_invalidateForm()
                        return
                    end

                    self.state.config[item.id] = selected == true
                end)
        end
    end

    function node:reload(app)
        local freshGeneral = app.framework.preferences:section("general", {})
        local freshShortcuts = app.framework.preferences:section("shortcuts", {})
        local freshLastSelected = app.framework.preferences:section("menulastselected", {})

        app.ui.showLoader({
            kind = "progress",
            title = self.title or "@i18n(app.modules.settings.shortcuts)@",
            message = "Reloading settings.",
            closeWhenIdle = false,
            modal = true
        })

        self.state.config = copyMap(freshShortcuts)
        self.state.mixedIn = prefBool(freshGeneral.shortcuts_mixed_in, true)
        self.state.groupIndex = tonumber(freshLastSelected[GROUP_PREF_KEY]) or 1
        app:_invalidateForm()
        app.ui.clearProgressDialog(true)
        return true
    end

    function node:save(app)
        local generalSection = app.framework.preferences:section("general", {})
        local shortcutsSection = app.framework.preferences:section("shortcuts", {})
        local selected = SHORTCUTS.limitSelectionMap(self.state.config, maxSelected)
        local key
        local item

        app.ui.showLoader({
            kind = "save",
            title = self.title or "@i18n(app.modules.settings.shortcuts)@",
            message = "Saving settings.",
            closeWhenIdle = false,
            modal = true
        })

        generalSection.shortcuts_mixed_in = (self.state.mixedIn == true)
        lastSelected[GROUP_PREF_KEY] = self.state.groupIndex

        for key in pairs(shortcutsSection) do
            shortcutsSection[key] = nil
        end

        for _, item in ipairs(self.state.registry.items or {}) do
            if selected[item.id] then
                shortcutsSection[item.id] = true
            end
        end

        app.framework.preferences:save()
        app.ui.clearProgressDialog(true)
        return true
    end

    return node
end

return Page
