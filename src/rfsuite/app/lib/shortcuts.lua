--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local shortcuts = {}

local ROOT_MENU_PATH = "app/menu/root.lua"
local MAX_SHORTCUTS = 5
local registryCache = nil
local LEGACY_SHORTCUT_IDS_BY_PATH = {
    ["pids/pids.lua"] = {"s_flight_tuning_menu_pids_pids_lua_e97a40faab"},
    ["rates/rates.lua"] = {"s_flight_tuning_menu_rates_rates_lua_853c5751ea"},
    ["profile_governor/tools/general.lua"] = {"s_profile_governor_general_lua_3a27cf6764"},
    ["profile_governor/tools/flags.lua"] = {"s_profile_governor_flags_lua_3992e9f64d"},
    ["filters/filters.lua"] = {"s_advanced_menu_filters_filters_lua_f1de87c4bd"},
    ["profile_pidcontroller/pidcontroller.lua"] = {"s_advanced_menu_profile_pidcontroller_d88ea3ba97"},
    ["profile_pidbandwidth/pidbandwidth.lua"] = {"s_advanced_menu_profile_pidbandwidth_p_650df8805e"},
    ["profile_autolevel/autolevel.lua"] = {"s_advanced_menu_profile_autolevel_auto_d9832fb3eb"},
    ["profile_mainrotor/mainrotor.lua"] = {"s_advanced_menu_profile_mainrotor_main_99724a655d"},
    ["profile_tailrotor/tailrotor.lua"] = {"s_advanced_menu_profile_tailrotor_tail_9cd82ec0d9"},
    ["profile_rescue/rescue.lua"] = {"s_advanced_menu_profile_rescue_rescue_3bb5c29dca"},
    ["rates_advanced/tools/advanced.lua"] = {"s_rates_advanced_advanced_lua_5673f8caee"},
    ["rates_advanced/tools/cyclic_behaviour.lua"] = {"s_rates_advanced_cyclic_behaviour_lua_df5de615f1"},
    ["rates_advanced/tools/table.lua"] = {"s_rates_advanced_table_lua_7e2b9c5584"},
    ["configuration/configuration.lua"] = {"s_setup_menu_configuration_configurati_fd32dd8698"},
    ["radio_config/radio_config.lua"] = {"s_setup_menu_radio_config_radio_config_176a7167bd"},
    ["telemetry/telemetry.lua"] = {"s_setup_menu_telemetry_telemetry_lua_72f812703b"},
    ["accelerometer/accelerometer.lua"] = {"s_setup_menu_accelerometer_acceleromet_1e39c3bf97"},
    ["alignment/alignment.lua"] = {"s_setup_menu_alignment_alignment_lua_58dbca14ba"},
    ["ports/ports.lua"] = {"s_setup_menu_ports_ports_lua_0511c48eaf"},
    ["mixer/tools/swash.lua"] = {"s_mixer_swash_lua_219836e7bb", "s_mixer_swash_legacy_lua_c1fdc218f2"},
    ["mixer/tools/geometry.lua"] = {"s_mixer_swashgeometry_lua_2b19036cb9"},
    ["mixer/tools/tail.lua"] = {"s_mixer_tail_lua_4dae4bbc4e", "s_mixer_tail_legacy_lua_af252b8ccf"},
    ["mixer/tools/trims.lua"] = {"s_mixer_trims_lua_89bbcb71cc"},
    ["modes/modes.lua"] = {"s_safety_menu_modes_modes_lua_4bfa50db9c"},
    ["adjustments/adjustments.lua"] = {"s_safety_menu_adjustments_adjustments_1aa898354c"},
    ["failsafe/failsafe.lua"] = {"s_safety_menu_failsafe_failsafe_lua_5033612baf"},
    ["beepers/tools/configuration.lua"] = {"s_beepers_configuration_lua_3d60a90251"},
    ["beepers/tools/dshot.lua"] = {"s_beepers_dshot_lua_f1e47cbff2"},
    ["stats/stats.lua"] = {"s_safety_menu_stats_stats_lua_6e4a1dfd3e"},
    ["blackbox/tools/configuration.lua"] = {"s_blackbox_configuration_lua_1b07855e2c"},
    ["blackbox/tools/logging.lua"] = {"s_blackbox_logging_lua_6216852e49"},
    ["blackbox/tools/status.lua"] = {"s_blackbox_status_lua_6d398bae79"},
    ["governor/tools/general.lua"] = {"s_governor_general_lua_bb876f329d"},
    ["governor/tools/time.lua"] = {"s_governor_time_lua_3fa58c3610"},
    ["governor/tools/filters.lua"] = {"s_governor_filters_lua_258e16a592"},
    ["governor/tools/curves.lua"] = {"s_governor_curves_lua_a8f9b2b504"},
    ["power/tools/battery.lua"] = {"s_power_battery_lua_f67116c271", "s_power_battery_legacy_lua_71177b8cf6"},
    ["power/tools/alerts.lua"] = {"s_power_alerts_lua_9fd7dbdc4d"},
    ["power/tools/source.lua"] = {"s_power_source_lua_6d24f8cd57"},
    ["power/tools/preferences.lua"] = {"s_power_preferences_lua_2bae48fe41"},
    ["copyprofiles/copyprofiles.lua"] = {"s_tools_menu_copyprofiles_copyprofiles_020f84c51f"},
    ["profile_select/select_profile.lua"] = {"s_tools_menu_profile_select_select_pro_b62834ef6e"},
    ["diagnostics/tools/rfstatus.lua"] = {"s_diagnostics_rfstatus_lua_ac6fe96c58"},
    ["diagnostics/tools/sensors.lua"] = {"s_diagnostics_sensors_lua_0010694864"},
    ["diagnostics/tools/info.lua"] = {"s_diagnostics_info_lua_5025a3d5b5"},
    ["diagnostics/tools/fblstatus.lua"] = {"s_diagnostics_fblstatus_lua_d9afde0a7c"},
    ["diagnostics/tools/fblsensors.lua"] = {"s_diagnostics_fblsensors_lua_05321e9f3c"},
    ["settings/tools/general.lua"] = {"s_settings_admin_tools_general_lua_37954a091f"},
    ["settings/tools/shortcuts.lua"] = {"s_settings_admin_tools_shortcuts_lua_7ef1a52bf9"},
    ["settings/tools/dashboard.lua"] = {"s_settings_admin_tools_dashboard_lua_949703e179"},
    ["settings/tools/localizations.lua"] = {"s_settings_admin_tools_localizations_l_bfcda87566"},
    ["settings/tools/audio.lua"] = {"s_settings_admin_tools_audio_lua_54f65112f1"}
}

local function loadLuaTable(path)
    if type(path) ~= "string" or path == "" then
        return nil, "invalid path"
    end

    local chunk, loadErr = loadfile(path)
    if not chunk then
        return nil, loadErr
    end

    local ok, value = pcall(chunk)
    if not ok then
        return nil, value
    end

    if type(value) ~= "table" then
        return nil, "module did not return table"
    end

    return value
end

local function loadVisibilityModule()
    local mod = select(1, loadLuaTable("app/lib/menu_visibility.lua"))

    if type(mod) == "table" then
        return mod
    end

    return nil
end

local function copyShallow(source)
    local out = {}

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function buildShortcutVisibilityFramework(framework)
    local sessionProxy

    if type(framework) ~= "table" then
        return framework
    end

    sessionProxy = {
        get = function(_, key, default)
            if key == "apiVersion" then
                return nil
            end

            if framework.session and type(framework.session.get) == "function" then
                return framework.session:get(key, default)
            end

            return default
        end
    }

    return {
        preferences = framework.preferences,
        config = framework.config,
        session = sessionProxy
    }
end

local function copyArray(source)
    local out = {}
    local i

    for i = 1, #(source or {}) do
        out[i] = source[i]
    end

    return out
end

local function normalizeShortcutId(parts)
    local joined = table.concat(parts or {}, "_")

    joined = tostring(joined):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if joined == "" then
        return nil
    end

    return joined
end

local function isTruthy(value)
    return value == true or value == "true" or value == 1 or value == "1"
end

local function boolPref(value, default)
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

local function buildEntry(item, groupTitle, ancestry)
    local idParts = copyShallow(ancestry or {})
    local itemId = item.shortcutId or item.id or item.title

    idParts[#idParts + 1] = itemId

    return {
        id = normalizeShortcutId(idParts),
        title = item.title or item.id or "Page",
        subtitle = item.subtitle or "Page",
        path = item.path,
        image = item.image,
        groupTitle = groupTitle or "Shortcuts",
        offline = item.offline == true,
        disabled = item.disabled == true,
        aliases = copyArray(LEGACY_SHORTCUT_IDS_BY_PATH[item.path])
    }
end

local function collectMenu(registry, framework, source, menuTitle, ancestry)
    local menu, err = loadLuaTable(source)
    local nextAncestry = copyShallow(ancestry or {})
    local visibility = loadVisibilityModule()
    local item

    if type(menu) ~= "table" then
        return false, err
    end

    nextAncestry[#nextAncestry + 1] = menu.id or menuTitle or source

    for _, item in ipairs(menu.items or {}) do
        if (not visibility) or visibility.itemVisible(framework, item) == true then
            if item.kind == "page" and type(item.path) == "string" and item.path ~= "" then
                local entry = buildEntry(item, menu.title or menuTitle, nextAncestry)

                if entry.id then
                    registry.byId[entry.id] = entry
                    registry.items[#registry.items + 1] = entry
                end
            elseif item.kind == "menu" and type(item.source) == "string" and item.source ~= "" then
                collectMenu(registry, framework, item.source, item.title or menuTitle, nextAncestry)
            end
        end
    end

    return true
end

function shortcuts.buildRegistry(framework)
    local root
    local registry
    local signature
    local grouped = {}
    local groupOrder = {}
    local visibility = loadVisibilityModule()
    local visibilityFramework = buildShortcutVisibilityFramework(framework)
    local entry

    signature = visibility and visibility.accessSignature and visibility.accessSignature(visibilityFramework) or "default"
    if registryCache and registryCache.signature == signature and type(registryCache.registry) == "table" then
        return registryCache.registry
    end

    root = select(1, loadLuaTable(ROOT_MENU_PATH)) or {}
    registry = {groups = {}, items = {}, byId = {}}

    for _, entry in ipairs(root.items or {}) do
        if (not visibility) or visibility.itemVisible(visibilityFramework, entry) == true then
            if entry.kind == "page" and type(entry.path) == "string" and entry.path ~= "" then
                local rootEntry = buildEntry(entry, entry.groupTitle or root.headerTitle or root.title, {"root"})

                if rootEntry.id then
                    registry.byId[rootEntry.id] = rootEntry
                    registry.items[#registry.items + 1] = rootEntry
                end
            elseif entry.kind == "menu" and type(entry.source) == "string" and entry.source ~= "" then
                collectMenu(registry, visibilityFramework, entry.source, entry.title, {"root", entry.id or entry.title or entry.source})
            end
        end
    end

    for _, entry in ipairs(registry.items) do
        local title = entry.groupTitle or "Shortcuts"

        if grouped[title] == nil then
            grouped[title] = {title = title, items = {}}
            groupOrder[#groupOrder + 1] = title
        end
        grouped[title].items[#grouped[title].items + 1] = entry
    end

    for _, title in ipairs(groupOrder) do
        local group = grouped[title]

        if group then
            registry.groups[#registry.groups + 1] = group
        end
    end

    registryCache = {
        signature = signature,
        registry = registry
    }

    return registry
end

function shortcuts.resetRegistry()
    registryCache = nil
end

function shortcuts.getMaxSelected()
    return MAX_SHORTCUTS
end

function shortcuts.isSelected(prefs, id)
    if type(prefs) ~= "table" or type(id) ~= "string" then
        return false
    end
    return isTruthy(prefs[id])
end

function shortcuts.entrySelected(prefs, entry)
    local aliases
    local i

    if type(entry) ~= "table" then
        return false
    end

    if shortcuts.isSelected(prefs, entry.id) then
        return true
    end

    aliases = entry.aliases or {}
    for i = 1, #aliases do
        if shortcuts.isSelected(prefs, aliases[i]) then
            return true
        end
    end

    return false
end

function shortcuts.limitSelectionMap(prefs, maxSelected, registry)
    registry = registry or shortcuts.buildRegistry()
    local selected = {}
    local selectedCount = 0
    local limit = tonumber(maxSelected) or MAX_SHORTCUTS
    local item

    if limit < 1 then
        limit = 1
    end

    for _, item in ipairs(registry.items or {}) do
        if shortcuts.entrySelected(prefs, item) then
            selectedCount = selectedCount + 1
            if selectedCount <= limit then
                selected[item.id] = true
            end
        end
    end

    return selected, selectedCount
end

function shortcuts.buildRootItems(framework)
    local general = framework.preferences:section("general", {})
    local selectedPrefs = framework.preferences:section("shortcuts", {})
    local registry = shortcuts.buildRegistry(framework)
    local selected = shortcuts.limitSelectionMap(selectedPrefs, MAX_SHORTCUTS, registry)
    local mixed = boolPref(general.shortcuts_mixed_in, true)
    local items = {}
    local entry

    for _, entry in ipairs(registry.items or {}) do
        if selected[entry.id] then
            items[#items + 1] = {
                id = "shortcut_" .. entry.id,
                title = entry.title,
                subtitle = entry.subtitle,
                kind = "page",
                path = entry.path,
                image = entry.image,
                group = "shortcuts",
                groupTitle = "Shortcuts",
                offline = entry.offline == true,
                disabled = entry.disabled == true,
                _mixedShortcut = (mixed == true),
                shortcutId = entry.id,
                shortcutOriginalGroupTitle = entry.groupTitle
            }
        end
    end

    return items
end

return shortcuts
