--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local power = {}

function power.controlsReady(node)
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

function power.findField(node, apikey)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.apikey == apikey then
            return field
        end
    end

    return nil
end

function power.setFieldEnabled(node, apikey, enabled)
    local field = power.findField(node, apikey)
    local control = field and field.control or nil

    if control and control.enable then
        pcall(control.enable, control, enabled == true)
    end
end

function power.applyWhenChanged(node, key, signature, fn)
    local state = node and node.state or nil

    if type(state) ~= "table" then
        return false
    end

    if power.controlsReady(node) ~= true then
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

return power
