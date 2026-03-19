--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local shortcuts = {}

local ROOT_MENU_PATH = "app/menu/root.lua"
local MAX_SHORTCUTS = 5
local registryCache = nil

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

local function copyShallow(source)
    local out = {}

    for key, value in pairs(source or {}) do
        out[key] = value
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
        groupTitle = groupTitle or "Shortcuts"
    }
end

local function collectMenu(registry, source, menuTitle, ancestry)
    local menu, err = loadLuaTable(source)
    local nextAncestry = copyShallow(ancestry or {})
    local item

    if type(menu) ~= "table" then
        return false, err
    end

    nextAncestry[#nextAncestry + 1] = menu.id or menuTitle or source

    for _, item in ipairs(menu.items or {}) do
        if item.kind == "page" and type(item.path) == "string" and item.path ~= "" then
            local entry = buildEntry(item, menu.title or menuTitle, nextAncestry)

            if entry.id then
                registry.byId[entry.id] = entry
                registry.items[#registry.items + 1] = entry
            end
        elseif item.kind == "menu" and type(item.source) == "string" and item.source ~= "" then
            collectMenu(registry, item.source, item.title or menuTitle, nextAncestry)
        end
    end

    return true
end

function shortcuts.buildRegistry()
    local root
    local registry
    local grouped = {}
    local groupOrder = {}
    local entry

    if type(registryCache) == "table" then
        return registryCache
    end

    root = select(1, loadLuaTable(ROOT_MENU_PATH)) or {}
    registry = {groups = {}, items = {}, byId = {}}

    for _, entry in ipairs(root.items or {}) do
        if entry.kind == "page" and type(entry.path) == "string" and entry.path ~= "" then
            local rootEntry = buildEntry(entry, entry.groupTitle or root.headerTitle or root.title, {"root"})

            if rootEntry.id then
                registry.byId[rootEntry.id] = rootEntry
                registry.items[#registry.items + 1] = rootEntry
            end
        elseif entry.kind == "menu" and type(entry.source) == "string" and entry.source ~= "" then
            collectMenu(registry, entry.source, entry.title, {"root", entry.id or entry.title or entry.source})
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

    registryCache = registry
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

function shortcuts.limitSelectionMap(prefs, maxSelected)
    local registry = shortcuts.buildRegistry()
    local selected = {}
    local selectedCount = 0
    local limit = tonumber(maxSelected) or MAX_SHORTCUTS
    local item

    if limit < 1 then
        limit = 1
    end

    for _, item in ipairs(registry.items or {}) do
        if shortcuts.isSelected(prefs, item.id) then
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
    local selected = shortcuts.limitSelectionMap(selectedPrefs, MAX_SHORTCUTS)
    local registry = shortcuts.buildRegistry()
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
                _mixedShortcut = (mixed == true),
                shortcutId = entry.id,
                shortcutOriginalGroupTitle = entry.groupTitle
            }
        end
    end

    return items
end

return shortcuts
