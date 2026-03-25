--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local rates = {}

local ModuleLoader = require("framework.utils.module_loader")
local utils = require("lib.utils")

local RATE_TABLE_MODULES = {
    [0] = "app/modules/rates/ratetables/none.lua",
    [1] = "app/modules/rates/ratetables/betaflight.lua",
    [2] = "app/modules/rates/ratetables/raceflight.lua",
    [3] = "app/modules/rates/ratetables/kiss.lua",
    [4] = "app/modules/rates/ratetables/actual.lua",
    [5] = "app/modules/rates/ratetables/quick.lua",
    [6] = "app/modules/rates/ratetables/rotorflight.lua"
}

local function copyArray(source)
    local out = {}
    local index

    for index = 1, #(source or {}) do
        out[index] = source[index]
    end

    return out
end

local function copyField(field)
    local out = {}
    local key
    local value

    for key, value in pairs(field or {}) do
        out[key] = value
    end

    return out
end

local function copyFields(fields)
    local out = {}
    local index

    for index = 1, #(fields or {}) do
        out[index] = copyField(fields[index])
    end

    return out
end

local function loadRateTableSpec(tableId)
    local path = RATE_TABLE_MODULES[tableId]

    if type(path) ~= "string" then
        return nil
    end

    return ModuleLoader.loadFileCached(path)
end

function rates.decimalInc(decimals)
    return utils.decimalInc(decimals) or 1
end

function rates.getRateTypeChoices()
    local choices = {
        {"@i18n(app.modules.rates.none)@", 0},
        {"@i18n(app.modules.rates.betaflight)@", 1},
        {"@i18n(app.modules.rates.raceflight)@", 2},
        {"@i18n(app.modules.rates.kiss)@", 3},
        {"@i18n(app.modules.rates.actual)@", 4},
        {"@i18n(app.modules.rates.quick)@", 5}
    }

    if utils.apiVersionCompare(">=", {12, 0, 9}) then
        choices[#choices + 1] = {"@i18n(app.modules.rates.rotorflight)@", 6}
    end

    return choices
end

function rates.defaultRateTableId(framework)
    local session = framework and framework.session or nil
    local value = session and session.get and session:get("defaultRateProfile", nil) or nil

    value = tonumber(value)
    if value == nil then
        value = 4
    end

    return math.max(0, math.floor(value))
end

function rates.resolveTableId(rateType, framework)
    local value = tonumber(rateType)

    if value == nil or RATE_TABLE_MODULES[value] == nil then
        value = rates.defaultRateTableId(framework)
    end

    if value == 6 and utils.apiVersionCompare("<", {12, 0, 9}) then
        value = rates.defaultRateTableId(framework)
    end

    if RATE_TABLE_MODULES[value] == nil then
        value = 4
    end

    return value
end

function rates.getRateTable(rateType, framework)
    local tableId = rates.resolveTableId(rateType, framework)
    local source = loadRateTableSpec(tableId) or loadRateTableSpec(4)

    return {
        id = tableId,
        name = source.name,
        rows = copyArray(source.rows),
        cols = copyArray(source.cols),
        help = copyArray(source.help),
        fields = copyFields(source.fields)
    }
end

function rates.getFieldDisplayValue(field)
    local value = field and field.value or 0

    if field and field.decimals then
        value = math.floor(value * rates.decimalInc(field.decimals) + 0.5)
    end

    if field and field.offset then
        value = value + field.offset
    end

    if field and field.mult then
        value = math.floor(value * field.mult + 0.5)
    end

    return value
end

function rates.saveFieldDisplayValue(field, displayValue)
    local value = tonumber(displayValue)

    if value == nil or type(field) ~= "table" then
        return field and field.value or nil
    end

    if field.offset then
        value = value - field.offset
    end

    if field.decimals then
        field.value = value / rates.decimalInc(field.decimals)
    else
        field.value = value
    end

    if field.mult then
        field.value = field.value / field.mult
    end

    return field.value
end

function rates.defaultDisplayValue(field)
    local value = tonumber(field and field.default)

    if value == nil then
        return 0
    end

    if field.decimals then
        value = value * rates.decimalInc(field.decimals)
    end
    if field.mult then
        value = math.floor(value * field.mult)
    end
    if field.scale then
        value = math.floor(value / field.scale)
    end

    return value
end

function rates.defaultStoredValue(field)
    local copy = copyField(field)

    rates.saveFieldDisplayValue(copy, rates.defaultDisplayValue(copy))
    return copy.value
end

function rates.populateFieldsFromApi(fields, api)
    local index
    local field
    local rawValue
    local scale

    for index = 1, #(fields or {}) do
        field = fields[index]
        rawValue = api and api.readValue and api.readValue(field.apikey) or nil

        if rawValue ~= nil then
            scale = tonumber(field.scale) or 1
            if scale == 0 then
                scale = 1
            end
            field.value = rawValue / scale
        else
            field.value = rates.defaultStoredValue(field)
        end
    end
end

function rates.currentRateProfile(app)
    local framework = app and app.framework or nil
    local telemetry = framework and framework.getTask and framework:getTask("telemetry") or nil
    local value

    if telemetry and telemetry.getSensor then
        value = telemetry.getSensor("rate_profile")
    end

    if value == nil and framework and framework.session then
        value = framework.session:get("activeRateProfile", nil)
    end

    value = tonumber(value)
    if value == nil then
        return nil
    end

    value = math.floor(value)
    if value < 1 then
        return nil
    end

    return value
end

function rates.updateNodeTitle(node)
    local baseTitle = node and node.baseTitle or node.title or "@i18n(app.modules.rates.name)@"
    local profile = node and node.app and rates.currentRateProfile(node.app) or nil
    local title = baseTitle

    if profile ~= nil then
        title = string.format("%s #%d", baseTitle, profile)
    end

    if node.title ~= title then
        node.title = title
        if node.app and node.app.setHeaderTitle then
            node.app:setHeaderTitle(title)
        end
    end
end

function rates.nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
end

function rates.noopHandler()
end

function rates.trackActiveApi(state, apiName, api)
    if type(state) ~= "table" then
        return
    end

    state.activeApiName = apiName
    state.activeApi = api
end

function rates.clearActiveApi(state)
    if type(state) ~= "table" then
        return
    end

    state.activeApiName = nil
    state.activeApi = nil
end

function rates.unloadApi(app, apiName, api)
    local mspTask = app and app.framework and app.framework.getTask and app.framework:getTask("msp") or nil

    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end

    if mspTask and mspTask.api and mspTask.api.unload and apiName then
        mspTask.api.unload(apiName)
    end
end

function rates.cleanupActiveApi(state, app)
    local api
    local apiName

    if type(state) ~= "table" then
        return
    end

    api = state.activeApi
    apiName = state.activeApiName
    rates.clearActiveApi(state)

    if not api then
        return
    end

    if api.setCompleteHandler then
        api.setCompleteHandler(rates.noopHandler)
    end
    if api.setErrorHandler then
        api.setErrorHandler(rates.noopHandler)
    end
    if api.setUUID then
        api.setUUID(nil)
    end

    rates.unloadApi(app, apiName, api)
end

return rates
