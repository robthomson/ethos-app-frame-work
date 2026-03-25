--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local governor = {}

local function session(node)
    local app = node and node.app or nil
    local framework = app and app.framework or nil

    return framework and framework.session or nil
end

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

function governor.mode(node)
    local value = session(node) and session(node):get("governorMode", nil) or nil

    return tonumber(value)
end

function governor.isDisabled(node)
    return governor.mode(node) == 0
end

function governor.syncSaveButton(node)
    if node and node.app and node.app._syncSaveButtonState then
        node.app:_syncSaveButtonState()
    end
end

function governor.setReloadEnabled(node, enabled)
    local app = node and node.app or nil
    local field = app and app.navFields and app.navFields.reload or nil
    local enableFn = field and field.enable or nil

    if type(enableFn) == "function" then
        pcall(enableFn, field, enabled == true)
    end
end

function governor.applyGeneralState(node)
    local mode = governor.mode(node)
    local buildCount = node and node.app and node.app.formBuildCount or 0

    applyWhenChanged(node, "governorGeneralUiSignature", table.concat({
        tostring(mode),
        tostring(buildCount)
    }, "|"), function(activeNode)
        local standardMode = mode == nil or mode >= 1
        local advancedMode = mode == nil or mode >= 2

        governor.setReloadEnabled(activeNode, mode ~= 0)
        governor.syncSaveButton(activeNode)

        setFieldEnabled(activeNode, {"governor_headspeed", "governor_min_throttle", "governor_gain", "governor_p_gain",
            "governor_i_gain", "governor_d_gain", "governor_f_gain", "governor_yaw_weight", "governor_cyclic_weight",
            "governor_collective_weight", "governor_yaw_ff_weight", "governor_cyclic_ff_weight",
            "governor_collective_ff_weight"}, advancedMode)
        setFieldEnabled(activeNode, {"governor_max_throttle", "governor_fallback_drop"}, standardMode)
    end)
end

function governor.applyFlagsState(node)
    local mode = governor.mode(node)
    local batteryConfig = session(node) and session(node):get("batteryConfig", nil) or nil
    local voltageSource = type(batteryConfig) == "table" and tonumber(batteryConfig.voltageMeterSource) or nil
    local buildCount = node and node.app and node.app.formBuildCount or 0

    applyWhenChanged(node, "governorFlagsUiSignature", table.concat({
        tostring(mode),
        tostring(voltageSource),
        tostring(buildCount)
    }, "|"), function(activeNode)
        local governorEnabled = mode ~= 0
        local voltageCompEnabled = governorEnabled and (voltageSource == nil or voltageSource == 1)

        governor.setReloadEnabled(activeNode, governorEnabled)
        governor.syncSaveButton(activeNode)

        setFieldEnabled(activeNode, {"governor_flags->fallback_precomp", "governor_flags->pid_spoolup",
            "governor_flags->dyn_min_throttle"}, governorEnabled)
        setFieldEnabled(activeNode, "governor_flags->voltage_comp", voltageCompEnabled)
    end)
end

function governor.wrapPage(basePage, stateUpdater)
    local Page = {}

    function Page:open(ctx)
        local node = basePage:open(ctx)
        local baseCanSave = node.canSave
        local baseWakeup = node.wakeup

        function node:canSave(app)
            if governor.isDisabled(self) then
                return false
            end

            return baseCanSave(self, app)
        end

        function node:wakeup()
            baseWakeup(self)
            stateUpdater(self)
        end

        return node
    end

    return Page
end

return governor
