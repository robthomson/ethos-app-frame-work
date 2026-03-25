--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")

local MODE_SET = 2
local CHANNEL_LABELS = {
    "@i18n(app.modules.failsafe.roll)@",
    "@i18n(app.modules.failsafe.pitch)@",
    "@i18n(app.modules.failsafe.yaw)@",
    "@i18n(app.modules.failsafe.collective)@",
    "@i18n(app.modules.failsafe.throttle)@",
    "@i18n(app.modules.failsafe.aux1)@",
    "@i18n(app.modules.failsafe.aux2)@",
    "@i18n(app.modules.failsafe.aux3)@",
    "@i18n(app.modules.failsafe.aux4)@",
    "@i18n(app.modules.failsafe.aux5)@",
    "@i18n(app.modules.failsafe.aux6)@",
    "@i18n(app.modules.failsafe.aux7)@",
    "@i18n(app.modules.failsafe.aux8)@",
    "@i18n(app.modules.failsafe.aux9)@",
    "@i18n(app.modules.failsafe.aux10)@",
    "@i18n(app.modules.failsafe.aux11)@",
    "@i18n(app.modules.failsafe.aux12)@",
    "@i18n(app.modules.failsafe.aux13)@"
}

local function findField(node, apikey)
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

local function syncValueEnablement(node)
    local index
    local modeField
    local valueField

    if not (node and node.state and node.state.loaded == true and node.state.loading ~= true) then
        return
    end

    for index = 1, #CHANNEL_LABELS do
        modeField = findField(node, "channel_" .. index .. "_mode")
        valueField = findField(node, "channel_" .. index .. "_value")
        if valueField and valueField.control and valueField.control.enable then
            valueField.control:enable(tonumber(modeField and modeField.value) == MODE_SET)
        end
    end
end

local function wakeup(node)
    local buildCount = node and node.app and node.app.formBuildCount or 0
    local parts = {tostring(buildCount)}
    local index
    local modeField
    local signature

    for index = 1, #CHANNEL_LABELS do
        modeField = findField(node, "channel_" .. index .. "_mode")
        parts[#parts + 1] = tostring(modeField and modeField.value or "")
    end

    signature = table.concat(parts, "|")
    if node.state.failsafeModeSignature == signature then
        return
    end

    node.state.failsafeModeSignature = signature
    syncValueEnablement(node)
end

local labels = {}
local fields = {}
local index

for index = 1, #CHANNEL_LABELS do
    labels[#labels + 1] = {
        t = CHANNEL_LABELS[index],
        label = index,
        inline_size = 16.0
    }

    fields[#fields + 1] = {
        t = "",
        label = index,
        inline = 1,
        api = "RXFAIL_CONFIG",
        apikey = "channel_" .. index .. "_value",
        min = 875,
        max = 2125,
        default = 1500,
        step = 5,
        unit = "us"
    }

    fields[#fields + 1] = {
        t = "",
        type = 1,
        label = index,
        inline = 2,
        api = "RXFAIL_CONFIG",
        apikey = "channel_" .. index .. "_mode"
    }
end

return MspPage.create({
    title = "@i18n(app.modules.failsafe.name)@",
    buildFormWhileLoading = true,
    eepromWrite = true,
    help = {
        "@i18n(app.modules.failsafe.help_p1)@"
    },
    api = {
        {name = "RXFAIL_CONFIG", rebuildOnWrite = true}
    },
    layout = {
        labels = labels,
        fields = fields
    },
    wakeup = wakeup
})
