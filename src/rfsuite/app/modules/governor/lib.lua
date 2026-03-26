--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local governor = {}

local function controlsReady(node)
    local index
    local field

    if not (node and node.state and node.state.loaded == true and node.state.loading ~= true) then
        return false
    end

    for index = 1, #(node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control then
            return true
        end
    end

    return false
end

local function applyWhenChanged(node, key, signature, fn)
    local state = node and node.state or nil

    if type(state) ~= "table" then
        return false
    end

    if controlsReady(node) ~= true then
        state[key] = nil
        return false
    end

    if state[key] == signature then
        return false
    end

    state[key] = signature
    fn(node)
    return true
end

local function setFieldEnabled(node, keys, enabled)
    local lookup = {}
    local index
    local key
    local field
    local control
    local enableFn

    if type(keys) == "string" then
        keys = {keys}
    end

    for index = 1, #(keys or {}) do
        key = keys[index]
        if type(key) == "string" and key ~= "" then
            lookup[key] = true
        end
    end

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        control = field and field.control or nil
        enableFn = control and control.enable or nil
        if field and lookup[field.apikey] == true and type(enableFn) == "function" then
            pcall(enableFn, control, enabled == true)
        end
    end
end

local function fieldValue(node, apikey)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.apikey == apikey then
            return tonumber(field.value)
        end
    end

    return nil
end

function governor.mode(node)
    return fieldValue(node, "gov_mode")
end

function governor.syncSaveButton(node)
    if node and node.app and node.app._syncSaveButtonState then
        node.app:_syncSaveButtonState()
    end
end

function governor.applyGeneralState(node)
    local mode = governor.mode(node)
    local buildCount = node and node.app and node.app.formBuildCount or 0

    applyWhenChanged(node, "governorGeneralUiSignature", table.concat({
        tostring(mode),
        tostring(buildCount)
    }, "|"), function(activeNode)
        local governorEnabled = mode ~= nil and mode >= 1
        local advancedEnabled = mode ~= nil and mode >= 2

        governor.syncSaveButton(activeNode)
        setFieldEnabled(activeNode, {
            "gov_throttle_type",
            "governor_idle_throttle",
            "governor_auto_throttle"
        }, governorEnabled)
        setFieldEnabled(activeNode, {
            "gov_handover_throttle",
            "gov_throttle_hold_timeout",
            "gov_autorotation_timeout"
        }, advancedEnabled)
    end)
end

return governor
