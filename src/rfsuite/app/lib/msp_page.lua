--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local MspPage = {}

local FIELD_TYPE_CHOICE = 1
local DEFAULT_INLINE_SIZE = 13.6
local DEFAULT_NAV = {menu = true, save = true, reload = true, tool = false, help = false}
local MATRIX_FIELD_INHERIT_KEYS = {
    "type",
    "table",
    "tableEthos",
    "values",
    "tableIdxInc",
    "decimals",
    "step",
    "prefix",
    "suffix",
    "unit",
    "min",
    "max",
    "default",
    "scale",
    "offset",
    "mult",
    "help"
}
local relinkFlexRows
local resumeDirtyAfterLoad
local ensureApis
local failRead
local setBuiltControlsEnabled
local canRefreshBuiltControlsInPlace
local function noopHandler()
end

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function keepApisLoaded(node)
    return node and node.spec and node.spec.keepApisLoaded == true
end

local function buildFormWhileLoadingEnabled(nodeOrSpec)
    local spec = type(nodeOrSpec) == "table" and (nodeOrSpec.spec or nodeOrSpec) or nil

    return type(spec) == "table" and spec.buildFormWhileLoading ~= false
end

local function updateBuiltControlsInPlaceEnabled(nodeOrSpec)
    local spec = type(nodeOrSpec) == "table" and (nodeOrSpec.spec or nodeOrSpec) or nil

    return buildFormWhileLoadingEnabled(spec) and type(spec) == "table" and spec.updateBuiltControlsInPlace ~= false
end

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
        out[key] = value
    end

    return out
end

local function mergeTable(base, override)
    local out = copyTable(base)
    local key

    for key, value in pairs(override or {}) do
        out[key] = value
    end

    return out
end

local function decimalInc(decimals)
    return utils.decimalInc(decimals) or 1
end

local function convertChoiceTable(tbl, inc)
    local values = {}
    local index

    if type(tbl) ~= "table" then
        return values
    end

    if inc == nil then
        inc = 0
    end

    if tbl[0] ~= nil then
        values[0] = {tostring(tbl[0]), 0}
    end

    for index, value in ipairs(tbl) do
        values[index] = {tostring(value), index + inc}
    end

    return values
end

local function resolveChoiceValues(field)
    if type(field) ~= "table" then
        return {}
    end

    if type(field.tableEthos) == "table" then
        return field.tableEthos
    end

    if type(field.values) == "table" then
        return field.values
    end

    return convertChoiceTable(field.table, field.tableIdxInc)
end

local function allowedByApiVersion(definition)
    if type(definition) ~= "table" then
        return true
    end

    if definition.apiversiongte and utils.apiVersionCompare("<", definition.apiversiongte) then
        return false
    end

    if definition.apiversionlte and utils.apiVersionCompare(">", definition.apiversionlte) then
        return false
    end

    return true
end

local function fieldControlValue(field, rawValue)
    local value = tonumber(rawValue)
    local scale

    if value == nil then
        return nil
    end

    scale = tonumber(field.scale) or 1
    if scale == 0 then
        scale = 1
    end

    value = value * decimalInc(field.decimals) / scale

    if field.offset then
        value = value + field.offset
    end

    if field.mult then
        value = math.floor(value * field.mult + 0.5)
    end

    return value
end

local function fieldBoundaryValue(field, rawBoundary)
    return fieldControlValue(field, rawBoundary)
end

local function fieldDefaultValue(field)
    local value = tonumber(field.default)

    if value == nil then
        return nil
    end

    if field.offset then
        value = value + field.offset
    end

    value = value * decimalInc(field.decimals)

    if field.mult then
        value = value * field.mult
    end

    if value >= 0 then
        return math.floor(value + 0.5)
    end

    return math.ceil(value - 0.5)
end

local function payloadValue(field, controlValue)
    local value = tonumber(controlValue)

    if value == nil then
        return controlValue
    end

    if field.offset then
        value = value - field.offset
    end

    if field.mult then
        value = value / field.mult
    end

    return value / decimalInc(field.decimals)
end

local function lineLabelSize(node, labelId)
    local labels = node.spec.layout and node.spec.layout.labels or {}
    local index
    local label

    if labelId == nil then
        return DEFAULT_INLINE_SIZE
    end

    for index = 1, #labels do
        label = labels[index]
        if label and label.label == labelId then
            return tonumber(label.inline_size) or DEFAULT_INLINE_SIZE
        end
    end

    return DEFAULT_INLINE_SIZE
end

local function wideStatusPos(app)
    local width = app and app._windowSize and app:_windowSize() or select(1, lcd.getWindowSize())
    local radio = app and app.radio or {}

    return {
        x = 8,
        y = radio.linePaddingTop or 0,
        w = math.max(40, width - 16),
        h = radio.navbuttonHeight or 30
    }
end

local function measureTextWidth(text)
    local value = tostring(text or "")

    if lcd and lcd.font and FONT_STD then
        lcd.font(FONT_STD)
    end

    if lcd and lcd.getTextSize then
        return select(1, lcd.getTextSize(value)) or 0
    end

    return #value * 8
end

local function inlinePositions(node, app, field)
    local width = app:_windowSize()
    local padding = 5
    local fieldWidth = (width * lineLabelSize(node, field.label) * (app.radio.inlinesize_mult or 1)) / 100
    local editWidth = fieldWidth - padding
    local editHeight = app.radio.navbuttonHeight or 30
    local editY = app.radio.linePaddingTop or 0
    local fieldText = tostring(field.t or "")
    local textWidth = 0
    local multipliers = {[1] = 1, [2] = 3, [3] = 5, [4] = 7, [5] = 9}
    local m = multipliers[field.inline] or 1
    local textPadding = (field.inline == 1) and (2 * padding) or padding
    local textX = width - fieldWidth * m - textWidth - textPadding
    local editX = width - fieldWidth * m - ((field.inline == 1) and padding or 0)

    textWidth = measureTextWidth(fieldText)

    textWidth = textWidth + padding
    textX = width - fieldWidth * m - textWidth - textPadding

    return {
        text = {x = textX, y = editY, w = textWidth, h = editHeight},
        field = {x = editX, y = editY, w = editWidth, h = editHeight}
    }
end

local function pageHelpText(helpText)
    if type(helpText) == "table" then
        return table.concat(helpText, "\n\n")
    end

    return tostring(helpText or "")
end

local function currentPidProfile(node)
    local telemetry = node.app.framework:getTask("telemetry")
    local value

    if telemetry and telemetry.getSensor then
        value = telemetry.getSensor("pid_profile")
    end

    if value == nil then
        value = node.app.framework.session:get("activeProfile", nil)
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

local function currentRateProfile(node)
    local telemetry = node.app.framework:getTask("telemetry")
    local value

    if telemetry and telemetry.getSensor then
        value = telemetry.getSensor("rate_profile")
    end

    if value == nil then
        value = node.app.framework.session:get("activeRateProfile", nil)
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

local function currentBatteryProfile(node)
    local telemetry = node.app.framework:getTask("telemetry")
    local value

    if telemetry and telemetry.getSensor then
        value = telemetry.getSensor("battery_profile")
    end

    if value == nil then
        value = node.app.framework.session:get("activeBatteryProfile", nil)
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

local function trackedProfileValue(node, kind)
    if kind == "rate" then
        return currentRateProfile(node)
    elseif kind == "battery" then
        return currentBatteryProfile(node)
    end

    return currentPidProfile(node)
end

local function updateDynamicTitle(node)
    local newTitle = node.baseTitle

    if node.spec.titleProfileSuffix == "pid" then
        local profile = currentPidProfile(node)
        if profile ~= nil then
            newTitle = string.format("%s #%d", node.baseTitle, profile)
        end
    elseif node.spec.titleProfileSuffix == "rate" then
        local profile = currentRateProfile(node)
        if profile ~= nil then
            newTitle = string.format("%s #%d", node.baseTitle, profile)
        end
    elseif node.spec.titleProfileSuffix == "battery" then
        local profile = currentBatteryProfile(node)
        if profile ~= nil then
            newTitle = string.format("%s #%d", node.baseTitle, profile)
        end
    end

    if node.title ~= newTitle then
        node.title = newTitle
        if node.app and node.app.setHeaderTitle then
            node.app:setHeaderTitle(newTitle)
        else
            node.app:_invalidateForm()
        end
    end
end

local function watchedProfileKinds(node)
    local kinds = {}

    if node.spec.refreshOnProfileChange == true or node.spec.titleProfileSuffix == "pid" then
        kinds[#kinds + 1] = "pid"
    end

    if node.spec.refreshOnRateChange == true or node.spec.titleProfileSuffix == "rate" then
        kinds[#kinds + 1] = "rate"
    end

    if node.spec.refreshOnBatteryProfileChange == true or node.spec.titleProfileSuffix == "battery" then
        kinds[#kinds + 1] = "battery"
    end

    return kinds
end

local function primeProfileWatchState(node)
    local kinds = watchedProfileKinds(node)
    local index
    local kind

    for index = 1, #kinds do
        kind = kinds[index]
        node.state.profileWatch[kind] = trackedProfileValue(node, kind)
    end
end

local function queueReload(node, showLoader)
    local app = node and node.app or nil
    local callback = app and app.callback or nil
    local function prepareQueuedReload()
        local ok
        local err
        local keepBuiltControls

        if type(node.state) ~= "table" then
            return
        end

        if nodeIsOpen(node) ~= true or node.state.saving == true then
            node.state.reloadQueued = false
            return
        end

        ok, err = ensureApis(node)
        if not ok then
            node.state.reloadQueued = false
            node.state.loading = false
            node.state.loaded = false
            node.state.error = tostring(err or "read_failed")
            resumeDirtyAfterLoad(node, true)
            if node.app and node.app._invalidateForm then
                node.app:_invalidateForm()
            end
            return
        end

        if nodeIsOpen(node) ~= true or node.state.saving == true then
            node.state.reloadQueued = false
            return
        end

        node.state.reloadQueued = false
        node.state.reloadPrepared = true
        node.state.preparedShowLoader = showLoader ~= false
        keepBuiltControls = canRefreshBuiltControlsInPlace(node)

        if node.app and node.app._invalidateForm and keepBuiltControls ~= true then
            node.app:_invalidateForm()
        end
    end
    local keepBuiltControls

    if nodeIsOpen(node) ~= true or node.state.reloadQueued == true or node.state.loading == true or node.state.saving == true then
        return false
    end

    keepBuiltControls = canRefreshBuiltControlsInPlace(node)
    node.state.reloadQueued = true
    node.state.loading = true
    node.state.error = nil
    node.state.reloadPrepared = false
    node.state.preparedShowLoader = showLoader ~= false

    if keepBuiltControls == true then
        setBuiltControlsEnabled(node, false)
    end

    if node.app and node.app._invalidateForm and keepBuiltControls ~= true then
        node.app:_invalidateForm()
    end

    if callback and callback.inSeconds then
        callback:inSeconds(0.02, prepareQueuedReload, "timer")
        return true
    end

    if callback and callback.now then
        callback:now(prepareQueuedReload, "immediate")
        return true
    end

    return prepareQueuedReload()
end

local function handleProfileChangeReload(node)
    local kinds = watchedProfileKinds(node)
    local index
    local kind
    local previous
    local current

    if node.state.loading == true or node.state.saving == true then
        return false
    end

    for index = 1, #kinds do
        kind = kinds[index]
        current = trackedProfileValue(node, kind)
        previous = node.state.profileWatch[kind]

        if previous == nil then
            if current ~= nil then
                node.state.profileWatch[kind] = current
                if node.spec.titleProfileSuffix == kind then
                    updateDynamicTitle(node)
                end
            end
        elseif current ~= nil and current ~= previous then
            node.state.profileWatch[kind] = current
            if node.spec.titleProfileSuffix == kind then
                updateDynamicTitle(node)
            end
            if (kind == "pid" and node.spec.refreshOnProfileChange == true) or
                (kind == "rate" and node.spec.refreshOnRateChange == true) or
                (kind == "battery" and node.spec.refreshOnBatteryProfileChange == true) then
                node:reload(true)
                return true
            end
        end
    end

    return false
end

ensureApis = function(node)
    local mspTask = node.app.framework:getTask("msp")
    local apiSpecs = node.spec.api or {}
    local apiState = node.state.apis
    local apiSpec
    local api
    local loadErr
    local index

    if not mspTask or not mspTask.api or not mspTask.api.load then
        return nil, "msp_unavailable"
    end

    for index = 1, #apiSpecs do
        apiSpec = apiSpecs[index]
        if apiState[apiSpec.name] == nil then
            api, loadErr = mspTask.api.load(apiSpec.name)
            if not api then
                return nil, loadErr or ("load_failed_" .. tostring(apiSpec.name))
            end

            apiState[apiSpec.name] = {
                api = api,
                spec = apiSpec
            }
        end
    end

    return apiState
end

local function cleanupApiEntry(apiEntry)
    local api = apiEntry and apiEntry.api or nil

    if not api then
        return
    end

    if api.releaseTransientState then
        api.releaseTransientState()
    end
    if api.setCompleteHandler then
        api.setCompleteHandler(noopHandler)
    end
    if api.setErrorHandler then
        api.setErrorHandler(noopHandler)
    end
    if api.clearValues then
        api.clearValues()
    end
    if api.resetWriteStatus then
        api.resetWriteStatus()
    end
    if api.setUUID then
        api.setUUID(nil)
    end
    if api.setTimeout then
        api.setTimeout(nil)
    end
end

local function releasePageApis(node, force)
    local state = node and node.state or nil
    local mspTask
    local apiEntry

    if type(state) ~= "table" or type(state.apis) ~= "table" then
        return
    end

    if force ~= true and keepApisLoaded(node) == true then
        return
    end

    mspTask = node.app and node.app.framework and node.app.framework:getTask("msp") or nil

    for _, apiEntry in pairs(state.apis) do
        cleanupApiEntry(apiEntry)
    end

    if mspTask and mspTask.api and mspTask.api.unload then
        for _, apiEntry in pairs(state.apis) do
            if apiEntry and apiEntry.spec and apiEntry.spec.name then
                mspTask.api.unload(apiEntry.spec.name)
            end
        end
    end

    state.apis = {}
end

local function describeApiField(api, fieldName)
    local data
    local structure
    local index
    local field

    if type(fieldName) ~= "string" or fieldName == "" or type(api) ~= "table" then
        return nil
    end

    if type(api.describeField) == "function" then
        return api.describeField(fieldName)
    end

    if type(api.data) ~= "function" then
        return nil
    end

    data = api.data()
    structure = data and data.structure or nil
    if type(structure) ~= "table" then
        return nil
    end

    for index = 1, #structure do
        field = structure[index]
        if type(field) == "table" and field.field == fieldName then
            return field
        end
    end

    return nil
end

local function mergedField(node, fieldSpec)
    local apiName = fieldSpec.api or fieldSpec.apiName or node.state.defaultApiName
    local apiEntry = apiName and node.state.apis[apiName] or nil
    local api = apiEntry and apiEntry.api or nil
    local meta = describeApiField(api, fieldSpec.apikey)
    local merged = {}
    local rawValue
    local key

    if type(meta) == "table" then
        for key, value in pairs(meta) do
            merged[key] = value
        end
    end

    for key, value in pairs(fieldSpec or {}) do
        merged[key] = value
    end

    merged.api = apiName

    rawValue = api and api.readValue and api.readValue(fieldSpec.apikey) or nil
    if rawValue ~= nil then
        merged.value = fieldControlValue(merged, rawValue)
    elseif node and buildFormWhileLoadingEnabled(node) and node.state and node.state.loaded ~= true then
        merged.value = nil
    elseif merged.value == nil then
        merged.value = fieldDefaultValue(merged)
    end

    return merged
end

local function visibleFields(node)
    local fields = {}
    local sourceFields = node.spec.layout and node.spec.layout.fields or {}
    local index
    local field

    for index = 1, #sourceFields do
        field = sourceFields[index]
        if allowedByApiVersion(field) then
            fields[#fields + 1] = mergedField(node, field)
        end
    end

    return fields
end

local function visibleLabels(node)
    local labels = {}
    local sourceLabels = node.spec.layout and node.spec.layout.labels or {}
    local index
    local label

    for index = 1, #sourceLabels do
        label = sourceLabels[index]
        if allowedByApiVersion(label) then
            labels[#labels + 1] = copyTable(label)
        end
    end

    return labels
end

local function visibleRows(node)
    local rows = {}
    local sourceRows = node.spec.layout and node.spec.layout.rows or {}
    local index
    local row

    for index = 1, #sourceRows do
        row = sourceRows[index]
        if allowedByApiVersion(row) then
            rows[#rows + 1] = copyTable(row)
        end
    end

    return rows
end

local function visibleColumns(node)
    local columns = {}
    local sourceColumns = node.spec.layout and node.spec.layout.columns or {}
    local index
    local column

    for index = 1, #sourceColumns do
        column = sourceColumns[index]
        if allowedByApiVersion(column) then
            columns[#columns + 1] = copyTable(column)
        end
    end

    return columns
end

local function visibleFlexRows(node)
    local rows = {}
    local fields = {}
    local sourceRows = node.spec.layout and node.spec.layout.rows or {}
    local rowIndex
    local cellIndex
    local sourceRow
    local row
    local sourceCells
    local cell

    for rowIndex = 1, #sourceRows do
        sourceRow = sourceRows[rowIndex]
        if allowedByApiVersion(sourceRow) then
            row = copyTable(sourceRow)
            row.cells = {}
            sourceCells = sourceRow.cells or {}

            for cellIndex = 1, #sourceCells do
                cell = sourceCells[cellIndex]
                if allowedByApiVersion(cell) then
                    fields[#fields + 1] = mergedField(node, cell)
                    row.cells[#row.cells + 1] = fields[#fields]
                end
            end

            rows[#rows + 1] = row
        end
    end

    return rows, fields
end

local function mergeFieldsInPlace(targetFields, sourceFields)
    local index
    local target
    local source
    local key

    for index = 1, #sourceFields do
        source = sourceFields[index]
        target = targetFields[index]

        if type(target) ~= "table" then
            target = {}
            targetFields[index] = target
        end

        for key, value in pairs(source) do
            if key ~= "control" then
                target[key] = value
            end
        end
    end

    for index = #targetFields, #sourceFields + 1, -1 do
        targetFields[index] = nil
    end

    return targetFields
end

local function applyFieldDecoration(control, field)
    local minValue
    local maxValue
    local defaultValue
    local suffixValue
    local choiceValues

    if not control then
        return
    end

    if field.type == FIELD_TYPE_CHOICE and control.values then
        choiceValues = resolveChoiceValues(field)
        if next(choiceValues) ~= nil then
            control:values(choiceValues)
        end
    end

    if field.decimals and control.decimals and field.type ~= FIELD_TYPE_CHOICE then
        control:decimals(field.decimals)
    end

    if field.step and control.step and field.type ~= FIELD_TYPE_CHOICE then
        control:step(field.step)
    end

    if field.prefix and control.prefix and field.type ~= FIELD_TYPE_CHOICE then
        control:prefix(field.prefix)
    end

    suffixValue = field.suffix
    if suffixValue == nil then
        suffixValue = field.unit
    end
    if suffixValue ~= nil and control.suffix and field.type ~= FIELD_TYPE_CHOICE then
        control:suffix(suffixValue)
    end

    minValue = fieldBoundaryValue(field, field.min)
    if minValue ~= nil and control.minimum and field.type ~= FIELD_TYPE_CHOICE then
        control:minimum(minValue)
    end

    maxValue = fieldBoundaryValue(field, field.max)
    if maxValue ~= nil and control.maximum and field.type ~= FIELD_TYPE_CHOICE then
        control:maximum(maxValue)
    end

    defaultValue = fieldDefaultValue(field)
    if defaultValue ~= nil and control.default and field.type ~= FIELD_TYPE_CHOICE then
        control:default(defaultValue)
    end

    if field.help and control.help then
        control:help(field.help)
    end
end

local function buildChoiceField(line, pos, field)
    local values = resolveChoiceValues(field)

    return form.addChoiceField(line, pos, values,
        function()
            return field.value
        end,
        function(newValue)
            field.value = newValue
        end)
end

local function buildNumberField(line, pos, field)
    local minValue = fieldBoundaryValue(field, field.min) or 0
    local maxValue = fieldBoundaryValue(field, field.max) or 0

    return form.addNumberField(line, pos, minValue, maxValue,
        function()
            return field.value
        end,
        function(newValue)
            field.value = newValue
        end)
end

local function shouldBuildControlsEnabled(node)
    return node and node.state and node.state.loaded == true
end

local function buildControlAtPosition(line, field, pos, enabled)
    local control

    if field.type == FIELD_TYPE_CHOICE or type(field.table) == "table" then
        control = buildChoiceField(line, pos, field)
    else
        control = buildNumberField(line, pos, field)
    end

    applyFieldDecoration(control, field)
    if control and control.enable then
        pcall(control.enable, control, enabled ~= false)
    end
    field.control = control
    return control
end

local function applyControlValue(control, value)
    local ok

    if control and control.value then
        ok = pcall(control.value, control, value)
        return ok == true
    end

    return false
end

setBuiltControlsEnabled = function(node, enabled)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control and field.control.enable then
            pcall(field.control.enable, field.control, enabled == true)
        end
    end
end

local function refreshBuiltControls(node)
    local index
    local field

    if node.app and node.app.suspendDirtyTracking then
        node.app:suspendDirtyTracking()
    end

    for index = 1, #(node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control then
            applyFieldDecoration(field.control, field)
            applyControlValue(field.control, field.value)
        end
    end

    if node.app and node.app.resumeDirtyTracking then
        node.app:resumeDirtyTracking()
    end
end

local function hasBuiltControls(node)
    local index
    local field

    for index = 1, #(node and node.state and node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control then
            return true
        end
    end

    return false
end

canRefreshBuiltControlsInPlace = function(node)
    return type(node) == "table"
        and type(node.spec) == "table"
        and updateBuiltControlsInPlaceEnabled(node)
        and hasBuiltControls(node) == true
end

local function runControlStateSync(node)
    local ok
    local err

    if type(node) ~= "table" or type(node.spec) ~= "table" then
        return true
    end

    if type(node.spec.controlStateSync) ~= "function" then
        return true
    end

    ok, err = pcall(node.spec.controlStateSync, node, node.app)
    if ok ~= true then
        node.state.error = tostring(err)
        if node.app and node.app._invalidateForm then
            node.app:_invalidateForm()
        end
        return false
    end

    return true
end

local function buildField(line, node, app, field)
    local positions = inlinePositions(node, app, field)

    if tostring(field.t or "") ~= "" then
        form.addStaticText(line, positions.text, tostring(field.t))
    end

    return buildControlAtPosition(line, field, positions.field, shouldBuildControlsEnabled(node))
end

local function buildFieldAtPosition(line, node, field, positions)
    if tostring(field.t or "") ~= "" then
        form.addStaticText(line, positions.text, tostring(field.t))
    end

    return buildControlAtPosition(line, field, positions.field, shouldBuildControlsEnabled(node))
end

local function rowSlotsStartX(node, app)
    local labels = node.state.labels or {}
    local index
    local maxWidth = 0
    local rowLabelWidth = tonumber(node.spec.layout and node.spec.layout.rowLabelWidth) or 0.34

    for index = 1, #labels do
        maxWidth = math.max(maxWidth, measureTextWidth(labels[index].t or ""))
    end

    return math.max(math.floor(app:_windowSize() * rowLabelWidth), maxWidth + 18)
end

local function buildRowSlots(line, node, app, fields)
    local width = app:_windowSize()
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local slotGap = tonumber(node.spec.layout and node.spec.layout.slotGap) or 12
    local fieldGap = tonumber(node.spec.layout and node.spec.layout.fieldGap) or 8
    local rightPadding = tonumber(node.spec.layout and node.spec.layout.rightPadding) or 5
    local startX = rowSlotsStartX(node, app)
    local count = math.max(1, #fields)
    local slotW = math.floor((width - startX - rightPadding - ((count - 1) * slotGap)) / count)
    local labelW = 0
    local minFieldW = tonumber(node.spec.layout and node.spec.layout.minFieldWidth) or 70
    local index
    local field
    local textW
    local fieldW
    local slotX

    for index = 1, #fields do
        labelW = math.max(labelW, measureTextWidth(fields[index].t or ""))
    end

    labelW = labelW + 6
    fieldW = math.max(minFieldW, slotW - labelW - fieldGap)
    if fieldW > slotW then
        fieldW = slotW
    end

    for index = 1, #fields do
        field = fields[index]
        textW = math.min(labelW, math.max(0, slotW - fieldW - fieldGap))
        slotX = startX + ((index - 1) * (slotW + slotGap))
        buildFieldAtPosition(line, node, field, {
            text = {x = slotX, y = rowY, w = textW, h = rowH},
            field = {x = slotX + textW + fieldGap, y = rowY, w = fieldW, h = rowH}
        })
    end
end

local function beginLoader(node, options)
    local opts = type(options) == "table" and options or {}
    local active = node.app and node.app.loader and node.app.loader.active or nil

    if active and opts.kind and active.kind == "menu" and opts.kind ~= "menu" then
        active.kind = opts.kind
    end

    if node.app and node.app.isLoaderActive and node.app:isLoaderActive() == true then
        if node.app.updateLoader then
            node.app:updateLoader(opts)
            return true
        end
    end

    node.app.ui.showLoader(opts)
    return true
end

local function prepareLayout(node)
    if node.spec.layout and node.spec.layout.kind == "rows" then
        local rows
        local fields

        rows, fields = visibleFlexRows(node)
        node.state.fields = mergeFieldsInPlace(node.state.fields or {}, fields)
        node.state.rows = relinkFlexRows(rows, node.state.fields)
        node.state.labels = {}
        node.state.columns = {}
    elseif node.spec.layout and node.spec.layout.kind == "matrix" then
        node.state.labels = visibleRows(node)
        node.state.columns = visibleColumns(node)
        node.state.rows = {}
        node.state.fields = mergeFieldsInPlace(node.state.fields or {}, visibleFields(node))
    else
        node.state.labels = visibleLabels(node)
        node.state.columns = {}
        node.state.rows = {}
        node.state.fields = mergeFieldsInPlace(node.state.fields or {}, visibleFields(node))
    end
    return true
end

local resolveDimension

local function matrixRowKey(row, index)
    return tostring((type(row) == "table" and (row.id or row.label)) or index)
end

local function matrixColumnKey(column, index)
    return tostring((type(column) == "table" and column.id) or index)
end

local function matrixStartX(node, app, labels)
    local width = app:_windowSize()
    local rowLabelWidth = resolveDimension(node.spec.layout and node.spec.layout.rowLabelWidth, width) or math.floor(width * 0.34)
    local index
    local maxWidth = 0

    labels = labels or node.state.labels or {}

    for index = 1, #labels do
        maxWidth = math.max(maxWidth, measureTextWidth(labels[index].t or ""))
    end

    return math.max(rowLabelWidth, maxWidth + 18)
end

local function matrixRowLabelPos(node, app, row, startX)
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local labelText = tostring((type(row) == "table" and (row.t or row.title)) or "")
    local labelWidth = measureTextWidth(labelText)
    local align = tostring((node.spec.layout and node.spec.layout.rowLabelAlign) or "left")
    local inset = resolveDimension(node.spec.layout and node.spec.layout.rowLabelPadding, startX) or 0
    local x = 0

    startX = tonumber(startX) or matrixStartX(node, app)

    if align == "right" then
        x = math.max(0, startX - labelWidth - inset)
    elseif align == "center" then
        x = math.max(0, math.floor((startX - labelWidth) / 2))
    else
        x = inset
    end

    return {
        x = x,
        y = rowY,
        w = math.max(0, startX - x),
        h = rowH
    }
end

local function matrixFieldLookup(fields)
    local lookup = {}
    local index
    local field
    local rowKey
    local columnKey

    for index = 1, #fields do
        field = fields[index]
        if field and field.row ~= nil and field.column ~= nil then
            rowKey = tostring(field.row)
            columnKey = tostring(field.column)
            lookup[rowKey] = lookup[rowKey] or {}
            lookup[rowKey][columnKey] = field
        end
    end

    return lookup
end

local function inheritMissingFieldValues(target, source)
    local index
    local key

    if type(target) ~= "table" or type(source) ~= "table" then
        return target
    end

    for index = 1, #MATRIX_FIELD_INHERIT_KEYS do
        key = MATRIX_FIELD_INHERIT_KEYS[index]
        if target[key] == nil and source[key] ~= nil then
            target[key] = source[key]
        end
    end

    return target
end

local function hydrateMatrixField(node, field, row, column)
    local layout = node and node.spec and node.spec.layout or nil

    if type(field) ~= "table" then
        return field
    end

    inheritMissingFieldValues(field, layout and layout.fieldDefaults or nil)
    inheritMissingFieldValues(field, layout)
    inheritMissingFieldValues(field, row)
    inheritMissingFieldValues(field, column)

    return field
end

local function matrixMetrics(node, app, columns, startX)
    local width = app:_windowSize()
    local gap = resolveDimension(node.spec.layout and node.spec.layout.slotGap, width) or 10
    local rightPadding = resolveDimension(node.spec.layout and node.spec.layout.rightPadding, width) or 12
    local count = math.max(1, #columns)
    local availableW = math.max(0, width - startX - rightPadding)
    local configuredCellW = resolveDimension(node.spec.layout and node.spec.layout.columnWidth, availableW)
    local cellW
    local usedW
    local blockX
    local pack

    startX = tonumber(startX) or matrixStartX(node, app)

    if configuredCellW ~= nil and configuredCellW > 0 then
        cellW = math.max(0, configuredCellW)
        usedW = (cellW * count) + ((count - 1) * gap)

        if usedW > availableW then
            cellW = math.floor((availableW - ((count - 1) * gap)) / count)
            cellW = math.max(0, cellW)
            blockX = startX
        else
            pack = tostring((node.spec.layout and node.spec.layout.columnPack) or "right")
            if pack == "left" then
                blockX = startX
            elseif pack == "center" then
                blockX = startX + math.floor((availableW - usedW) / 2)
            else
                blockX = width - rightPadding - usedW
            end
        end
    else
        cellW = math.floor((availableW - ((count - 1) * gap)) / count)
        cellW = math.max(0, cellW)
        blockX = startX
    end

    return {
        width = width,
        gap = gap,
        rightPadding = rightPadding,
        startX = startX,
        count = count,
        cellW = cellW,
        blockX = blockX
    }
end

local function buildMatrixHeader(line, node, app, columns, metrics)
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local align = tostring((node.spec.layout and node.spec.layout.columnAlign) or "center")
    local index
    local column
    local cellX
    local text
    local textWidth
    local textX

    metrics = metrics or matrixMetrics(node, app, columns)

    for index = 1, #columns do
        column = columns[index]
        cellX = metrics.blockX + ((index - 1) * (metrics.cellW + metrics.gap))
        text = tostring(column.t or column.id or "")
        textWidth = measureTextWidth(text)
        if align == "right" then
            textX = math.max(cellX, cellX + metrics.cellW - textWidth)
        elseif align == "left" then
            textX = cellX
        else
            textX = math.max(cellX, cellX + math.floor((metrics.cellW - textWidth) / 2))
        end
        form.addStaticText(line, {x = textX, y = rowY, w = math.min(metrics.cellW, textWidth + 2), h = rowH}, text)
    end
end

local function buildMatrixRow(line, node, app, row, columns, rowFields, metrics, startX)
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local index
    local column
    local field
    local cellX
    local controlW
    local controlX
    local fieldAlign

    metrics = metrics or matrixMetrics(node, app, columns, startX)
    startX = tonumber(startX) or metrics.startX

    form.addStaticText(line, matrixRowLabelPos(node, app, row, startX), tostring((type(row) == "table" and (row.t or row.title)) or ""))

    for index = 1, #columns do
        column = columns[index]
        field = rowFields and rowFields[matrixColumnKey(column, index)] or nil
        if field then
            hydrateMatrixField(node, field, row, column)
            cellX = metrics.blockX + ((index - 1) * (metrics.cellW + metrics.gap))
            controlW = resolveDimension(field.fieldWidth or column.fieldWidth or (node.spec.layout and node.spec.layout.fieldWidth), metrics.cellW) or metrics.cellW
            controlW = math.max(0, math.min(metrics.cellW, controlW))
            fieldAlign = tostring(field.fieldAlign or column.fieldAlign or (node.spec.layout and node.spec.layout.fieldAlign) or "right")

            if fieldAlign == "left" then
                controlX = cellX
            elseif fieldAlign == "center" then
                controlX = cellX + math.floor((metrics.cellW - controlW) / 2)
            else
                controlX = cellX + metrics.cellW - controlW
            end

            buildControlAtPosition(line, field, {x = controlX, y = rowY, w = controlW, h = rowH}, shouldBuildControlsEnabled(node))
        end
    end
end

relinkFlexRows = function(rows, fields)
    local fieldIndex = 1
    local rowIndex
    local cellIndex

    for rowIndex = 1, #rows do
        for cellIndex = 1, #(rows[rowIndex].cells or {}) do
            rows[rowIndex].cells[cellIndex] = fields[fieldIndex]
            fieldIndex = fieldIndex + 1
        end
    end

    return rows
end

resolveDimension = function(value, percentBasis)
    local numeric
    local percent

    if type(value) ~= "string" then
        return nil
    end

    percent = string.match(value, "^%s*([%d%.]+)%%%s*$")
    if percent then
        numeric = tonumber(percent)
        if numeric ~= nil then
            return math.floor((percentBasis or 0) * numeric / 100)
        end
    end

    numeric = string.match(value, "^%s*([%d%.]+)px%s*$")
    if numeric then
        numeric = tonumber(numeric)
        if numeric ~= nil then
            return math.floor(numeric)
        end
    end

    return nil
end

local function resolveRowStartX(node, app, row)
    local width = app:_windowSize()
    local rowTitle = (type(row) == "table" and (row.t or row.title)) or ""
    local minWidth = measureTextWidth(rowTitle) + 18
    local configured = resolveDimension(row.labelWidth or row.rowLabelWidth or (node.spec.layout and node.spec.layout.rowLabelWidth), width)

    return math.max(configured or 0, minWidth)
end

local function resolveCellWidth(value, availableWidth, totalWidth)
    return resolveDimension(value, availableWidth or totalWidth)
end

local function resolveFieldWidth(value, cellWidth, totalWidth)
    return resolveDimension(value, cellWidth or totalWidth)
end

local function preferredCellWidth(cell, totalWidth, minFieldW, fieldGap)
    local labelWidth = 0
    local controlWidth

    if tostring(cell.t or "") ~= "" then
        labelWidth = resolveDimension(cell.labelWidth, totalWidth) or (measureTextWidth(cell.t or "") + 6)
    end

    controlWidth = resolveFieldWidth(cell.fieldWidth, totalWidth, totalWidth) or minFieldW
    controlWidth = math.max(minFieldW, controlWidth)

    if labelWidth > 0 then
        return labelWidth + fieldGap + controlWidth
    end

    return controlWidth
end

local function buildFlexRow(line, node, app, row)
    local width = app:_windowSize()
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local rightPadding = tonumber(row.rightPadding or (node.spec.layout and node.spec.layout.rightPadding)) or 12
    local slotGap = tonumber(row.slotGap or row.gap or (node.spec.layout and node.spec.layout.slotGap)) or 10
    local fieldGap = tonumber(row.fieldGap or (node.spec.layout and node.spec.layout.fieldGap)) or 8
    local minFieldW = tonumber(row.minFieldWidth or (node.spec.layout and node.spec.layout.minFieldWidth)) or 70
    local align = tostring(row.align or (node.spec.layout and node.spec.layout.align) or "right")
    local startX = resolveRowStartX(node, app, row)
    local cells = row.cells or {}
    local count = #cells
    local availableWidth = width - startX - rightPadding - math.max(0, count - 1) * slotGap
    local fixedWidth = 0
    local flexibleWeight = 0
    local index
    local cell
    local cellWidth
    local cellWidths = {}
    local remainingWidth
    local remainingWeight
    local cellX = startX
    local labelWidth
    local controlWidth
    local textWidth
    local configuredFieldWidth

    if count == 0 then
        return
    end

    for index = 1, count do
        cell = cells[index]
        cellWidth = resolveCellWidth(cell.width, availableWidth, width)
        if cellWidth ~= nil then
            fixedWidth = fixedWidth + cellWidth
            cellWidths[index] = cellWidth
        elseif align == "right" then
            cellWidth = preferredCellWidth(cell, width, minFieldW, fieldGap)
            fixedWidth = fixedWidth + cellWidth
            cellWidths[index] = cellWidth
        else
            flexibleWeight = flexibleWeight + math.max(0, tonumber(cell.weight) or 1)
        end
    end

    remainingWidth = math.max(0, availableWidth - fixedWidth)
    remainingWeight = flexibleWeight

    for index = 1, count do
        cell = cells[index]
        cellWidth = cellWidths[index]
        if cellWidth == nil then
            local weight = math.max(0, tonumber(cell.weight) or 1)
            if index == count or remainingWeight <= 0 then
                cellWidth = remainingWidth
            else
                cellWidth = math.floor((remainingWidth * weight) / remainingWeight)
            end
            remainingWidth = math.max(0, remainingWidth - cellWidth)
            remainingWeight = math.max(0, remainingWeight - weight)
        end
        cellWidths[index] = cellWidth
    end

    if align == "right" then
        local usedWidth = 0

        for index = 1, count do
            usedWidth = usedWidth + (cellWidths[index] or 0)
        end
        usedWidth = usedWidth + math.max(0, count - 1) * slotGap
        cellX = math.max(startX, width - rightPadding - usedWidth)
    end

    for index = 1, count do
        cell = cells[index]
        cellWidth = cellWidths[index] or 0
        labelWidth = 0
        if tostring(cell.t or "") ~= "" then
            labelWidth = resolveCellWidth(cell.labelWidth, cellWidth, width) or (measureTextWidth(cell.t or "") + 6)
        end

        controlWidth = cellWidth
        if labelWidth > 0 then
            configuredFieldWidth = resolveFieldWidth(cell.fieldWidth, cellWidth, width)
            if configuredFieldWidth ~= nil then
                controlWidth = math.max(minFieldW, math.min(configuredFieldWidth, cellWidth))
            else
                controlWidth = math.max(minFieldW, cellWidth - labelWidth - fieldGap)
            end
            controlWidth = math.min(controlWidth, cellWidth)
            textWidth = math.min(labelWidth, math.max(0, cellWidth - controlWidth - fieldGap))
        else
            configuredFieldWidth = resolveFieldWidth(cell.fieldWidth, cellWidth, width)
            if configuredFieldWidth ~= nil then
                controlWidth = math.max(minFieldW, math.min(configuredFieldWidth, cellWidth))
            end
            textWidth = 0
        end

        buildFieldAtPosition(line, node, cell, {
            text = {x = cellX, y = rowY, w = textWidth, h = rowH},
            field = {
                x = cellX + textWidth + ((textWidth > 0) and fieldGap or 0),
                y = rowY,
                w = math.max(0, controlWidth),
                h = rowH
            }
        })

        cellX = cellX + cellWidth + slotGap
    end
end

local function finishRead(node)
    local reloadFull = node.state.reloadFullPending == true

    prepareLayout(node)
    node.state.loaded = true
    node.state.loading = false
    node.state.error = nil
    node.state.resetDirtyAfterBuild = true
    node.state.reloadFullPending = false
    updateDynamicTitle(node)
    refreshBuiltControls(node)
    setBuiltControlsEnabled(node, true)
    if runControlStateSync(node) ~= true then
        return
    end
    releasePageApis(node, false)
    resumeDirtyAfterLoad(node, true)
    if node.app and node.app.requestLoaderClose then
        node.app:requestLoaderClose()
    else
        node.app.ui.clearProgressDialog(true)
    end
    if reloadFull == true and node.app and node.app._invalidateForm then
        node.app:_invalidateForm()
    end
end

local function suspendDirtyDuringLoad(node)
    if node.state.dirtySuspended == true then
        return
    end

    if node.app and node.app.suspendDirtyTracking then
        node.app:suspendDirtyTracking()
        node.state.dirtySuspended = true
    end
end

resumeDirtyAfterLoad = function(node, clearDirty)
    if node.state.dirtySuspended == true and node.app and node.app.resumeDirtyTracking then
        node.app:resumeDirtyTracking()
        node.state.dirtySuspended = false
    end

    if clearDirty == true and node.app and node.app.setPageDirty then
        node.app:setPageDirty(false)
    end
end

local function clearDirtyAfterBuildIfNeeded(node)
    if node.state.resetDirtyAfterBuild == true and node.app and node.app.setPageDirty then
        node.state.resetDirtyAfterBuild = false
        node.app:setPageDirty(false)
    end
end

failRead = function(node, reason)
    node.state.loading = false
    node.state.loaded = false
    node.state.error = tostring(reason or "read_failed")
    releasePageApis(node, false)
    resumeDirtyAfterLoad(node, true)
    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function safeFinishRead(node)
    local ok, err = pcall(finishRead, node)

    if not ok then
        failRead(node, err)
        return false
    end

    return true
end

local function runRead(node, index)
    local apiSpecs = node.spec.api or {}
    local apiSpec = apiSpecs[index]
    local apiEntry
    local ok
    local reason

    if apiSpec == nil then
        safeFinishRead(node)
        return true
    end

    apiEntry = node.state.apis[apiSpec.name]
    if not apiEntry or not apiEntry.api then
        failRead(node, "api_missing_" .. tostring(apiSpec.name))
        return false
    end

    apiEntry.api.setUUID(utils.uuid("page-read-" .. string.lower(apiSpec.name)))
    apiEntry.api.setCompleteHandler(function()
        local ok, err = pcall(runRead, node, index + 1)
        if not ok then
            failRead(node, err)
        end
    end)
    apiEntry.api.setErrorHandler(function(_, err)
        failRead(node, err)
    end)

    ok, reason = apiEntry.api.read()
    if ok ~= true then
        failRead(node, reason)
        return false
    end

    return true
end

local function triggerEepromWrite(node)
    local mspTask = node.app.framework:getTask("msp")
    local ok
    local reason

    if node.spec.eepromWrite ~= true then
        releasePageApis(node, false)
        node.state.saving = false
        node.state.error = nil
        if node.app.requestLoaderClose then
            node.app:requestLoaderClose()
        else
            node.app.ui.clearProgressDialog(true)
        end
        return true
    end

    if not mspTask or type(mspTask.queueCommand) ~= "function" then
        releasePageApis(node, false)
        node.state.saving = false
        node.state.error = "eeprom_unavailable"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    releasePageApis(node, false)

    ok, reason = mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            node.state.saving = false
            node.state.error = nil
            if node.app.requestLoaderClose then
                node.app:requestLoaderClose()
            else
                node.app.ui.clearProgressDialog(true)
            end
        end,
        onError = function(_, err)
            node.state.saving = false
            node.state.error = tostring(err or "eeprom_failed")
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
        end
    })

    if ok ~= true then
        node.state.saving = false
        node.state.error = tostring(reason or "eeprom_queue_failed")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function failWrite(node, reason)
    node.state.saving = false
    node.state.error = tostring(reason or "write_failed")
    releasePageApis(node, false)
    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function safeTriggerEepromWrite(node)
    local ok, result = pcall(triggerEepromWrite, node)

    if not ok then
        failWrite(node, result)
        return false
    end

    return result
end

local function runWrite(node, index)
    local apiSpecs = node.spec.api or {}
    local apiSpec = apiSpecs[index]
    local apiEntry
    local ok
    local reason

    if apiSpec == nil then
        return safeTriggerEepromWrite(node)
    end

    apiEntry = node.state.apis[apiSpec.name]
    if not apiEntry or not apiEntry.api then
        failWrite(node, "api_missing_" .. tostring(apiSpec.name))
        return false
    end

    apiEntry.api.setUUID(utils.uuid("page-write-" .. string.lower(apiSpec.name)))
    apiEntry.api.setCompleteHandler(function()
        local ok, err = pcall(runWrite, node, index + 1)
        if not ok then
            failWrite(node, err)
        end
    end)
    apiEntry.api.setErrorHandler(function(_, err)
        failWrite(node, err)
    end)

    ok, reason = apiEntry.api.write()
    if ok ~= true then
        failWrite(node, reason)
        return false
    end

    return true
end

function MspPage.create(spec)
    local Page = {}

    function Page:open(ctx)
        local defaultLoaderOnEnter = {
            kind = "progress",
            message = "Loading values.",
            closeWhenIdle = false,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        }
        local defaultLoaderOnSave = {
            kind = "save",
            title = ctx.item.title or spec.title or "MSP Page",
            message = "Saving values.",
            closeWhenIdle = false,
            transferInfo = true,
            modal = true
        }
        local node = {
            spec = spec or {},
            app = ctx.app,
            baseTitle = ctx.item.title or spec.title or "MSP Page",
            title = ctx.item.title or spec.title or "MSP Page",
            subtitle = ctx.item.subtitle or spec.subtitle or "MSP-backed settings",
            breadcrumb = ctx.breadcrumb,
            showLoaderOnEnter = spec.showLoaderOnEnter ~= false,
            loaderOnEnter = mergeTable(defaultLoaderOnEnter, spec.loaderOnEnter),
            loaderOnSave = mergeTable(defaultLoaderOnSave, spec.loaderOnSave),
            navButtons = {
                menu = DEFAULT_NAV.menu,
                save = DEFAULT_NAV.save,
                reload = DEFAULT_NAV.reload,
                tool = DEFAULT_NAV.tool,
                help = (type(spec.help) == "string" or type(spec.help) == "table") and true or DEFAULT_NAV.help
            },
            state = {
                apis = {},
                fields = {},
                rows = {},
                labels = {},
                columns = {},
                profileWatch = {},
                defaultApiName = spec.api and spec.api[1] and spec.api[1].name or nil,
                loading = false,
                loaded = false,
                saving = false,
                error = nil,
                needsInitialLoad = true,
                reloadQueued = false,
                reloadFullPending = true,
                resetDirtyAfterBuild = false,
                dirtySuspended = false,
                closed = false
            }
        }
        local navKey

        for navKey, enabled in pairs(spec.navButtons or {}) do
            node.navButtons[navKey] = enabled
        end

        primeProfileWatchState(node)
        updateDynamicTitle(node)

        function node:buildForm(app)
            local groupedFields = {}
            local groupedIndex = {}
            local visibleLabelIndex = {}
            local labels = self.state.labels
            local columns = self.state.columns or {}
            local rows = self.state.rows or {}
            local fields = self.state.fields
            local index
            local label
            local field
            local line
            local labelId
            local rowLookup
            local startX
            local metrics

            if self.state.error then
                line = form.addLine("Status")
                form.addStaticText(line, nil, "Error")
                line = form.addLine("")
                form.addStaticText(line, wideStatusPos(app), tostring(self.state.error))
                clearDirtyAfterBuildIfNeeded(self)
                return
            end

            if self.state.loaded ~= true then
                if buildFormWhileLoadingEnabled(self) then
                    pcall(ensureApis, self)
                    if #(self.state.fields or {}) == 0 and #(self.state.labels or {}) == 0 and #(self.state.rows or {}) == 0 and #(self.state.columns or {}) == 0 then
                        prepareLayout(self)
                    end
                else
                    line = form.addLine("Status")
                    form.addStaticText(line, nil, self.state.loading == true and "Loading..." or "Waiting...")
                    clearDirtyAfterBuildIfNeeded(self)
                    return
                end
            end

            if self.spec.layout and self.spec.layout.kind == "rows" then
                for index = 1, #rows do
                    line = form.addLine(tostring(rows[index].t or rows[index].title or ""))
                    buildFlexRow(line, self, app, rows[index])
                end
                clearDirtyAfterBuildIfNeeded(self)
                return
            end

            if self.spec.layout and self.spec.layout.kind == "matrix" then
                startX = matrixStartX(self, app, labels)
                metrics = matrixMetrics(self, app, columns, startX)
                if #columns > 0 then
                    line = form.addLine("")
                    buildMatrixHeader(line, self, app, columns, metrics)
                end

                rowLookup = matrixFieldLookup(fields)

                for index = 1, #labels do
                    label = labels[index]
                    line = form.addLine("")
                    buildMatrixRow(line, self, app, label, columns, rowLookup[matrixRowKey(label, index)], metrics, startX)
                end
                clearDirtyAfterBuildIfNeeded(self)
                return
            end

            for index = 1, #labels do
                label = labels[index]
                visibleLabelIndex[label.label] = true
            end

            for index = 1, #fields do
                field = fields[index]
                labelId = field.label
                if labelId ~= nil and field.inline ~= nil and visibleLabelIndex[labelId] == true then
                    groupedFields[labelId] = groupedFields[labelId] or {}
                    groupedFields[labelId][#groupedFields[labelId] + 1] = field
                    groupedIndex[labelId] = true
                end
            end

            for index = 1, #labels do
                label = labels[index]
                if groupedIndex[label.label] == true then
                    line = form.addLine(tostring(label.t or ""))
                    if self.spec.layout and self.spec.layout.kind == "row_slots" then
                        buildRowSlots(line, self, app, groupedFields[label.label])
                    else
                        for _, field in ipairs(groupedFields[label.label]) do
                            buildField(line, self, app, field)
                        end
                    end
                end
            end

            for index = 1, #fields do
                field = fields[index]
                if not (field.label ~= nil and field.inline ~= nil and groupedIndex[field.label] == true) then
                    line = form.addLine(tostring(field.t or field.apikey or "Field"))
                    field.control = buildControlAtPosition(line, field, nil, shouldBuildControlsEnabled(self))
                end
            end

            if self.state.loaded == true then
                runControlStateSync(self)
            end

            clearDirtyAfterBuildIfNeeded(self)
        end

        function node:canSave()
            return self.state.loaded == true and self.state.loading ~= true and self.state.saving ~= true and self.state.error == nil
        end

        function node:reload(showLoader, apisReady, deferStart)
            local ok
            local err
            local builtControls
            local refreshInPlace
            local shouldShowLoader = showLoader ~= false

            if type(showLoader) == "table" and showLoader.framework and apisReady == nil then
                shouldShowLoader = true
            end

            if deferStart == true and apisReady ~= true then
                return queueReload(self, showLoader)
            end

            if apisReady ~= true then
                ok, err = ensureApis(self)
                if not ok then
                    failRead(self, err)
                    return false
                end
            end

            self.state.reloadQueued = false
            self.state.reloadPrepared = false
            self.state.loading = true
            self.state.error = nil
            builtControls = hasBuiltControls(self)
            refreshInPlace = updateBuiltControlsInPlaceEnabled(self) and builtControls == true
            self.state.reloadFullPending = self.spec.reloadFull == true
                or builtControls ~= true
                or (self.state.loaded ~= true and refreshInPlace ~= true)
            if self.state.reloadFullPending == true then
                self.state.loaded = false
            end
            if refreshInPlace == true then
                setBuiltControlsEnabled(self, false)
            end
            suspendDirtyDuringLoad(self)

            if shouldShowLoader == true then
                beginLoader(self, mergeTable(self.loaderOnEnter, {
                    kind = "progress",
                    title = self.baseTitle,
                    message = "Loading values."
                }))
            end

            return runRead(self, 1)
        end

        function node:save()
            local fields = self.state.fields
            local index
            local field
            local apiEntry
            local apiName
            local ok
            local err

            if not self:canSave() then
                return false
            end

            ok, err = ensureApis(self)
            if not ok then
                failWrite(self, err)
                return false
            end

            for _, apiEntry in pairs(self.state.apis) do
                if apiEntry.api.clearValues then
                    apiEntry.api.clearValues()
                end
                if apiEntry.api.resetWriteStatus then
                    apiEntry.api.resetWriteStatus()
                end
                if apiEntry.spec.rebuildOnWrite ~= nil and apiEntry.api.setRebuildOnWrite then
                    apiEntry.api.setRebuildOnWrite(apiEntry.spec.rebuildOnWrite == true)
                end
            end

            for index = 1, #fields do
                field = fields[index]
                apiName = field.api or self.state.defaultApiName
                apiEntry = apiName and self.state.apis[apiName] or nil
                if apiEntry and apiEntry.api and type(field.apikey) == "string" and field.apikey ~= "" then
                    if field.type == FIELD_TYPE_CHOICE or type(field.table) == "table" then
                        apiEntry.api.setValue(field.apikey, field.value)
                    else
                        apiEntry.api.setValue(field.apikey, payloadValue(field, field.value))
                    end
                end
            end

            self.state.saving = true
            self.state.error = nil
            beginLoader(self, self.loaderOnSave)

            return runWrite(self, 1)
        end

        function node:wakeup()
            if self.state.needsInitialLoad == true and self.state.loading ~= true and self.state.loaded ~= true then
                local showInitialLoader = self.showLoaderOnEnter == true or self.spec.showProgressWhileLoading == true
                self.state.needsInitialLoad = false
                self:reload(showInitialLoader, nil, true)
                return
            end

            if self.state.reloadPrepared == true and self.state.loading == true and self.state.saving ~= true then
                self.state.reloadPrepared = false
                self:reload(self.state.preparedShowLoader ~= false, true)
                return
            end

            if handleProfileChangeReload(self) == true then
                return
            end

            updateDynamicTitle(self)

            if runControlStateSync(self) ~= true then
                return
            end

            if type(self.spec.wakeup) == "function" then
                local ok, err = pcall(self.spec.wakeup, self, self.app)
                if not ok then
                    self.state.error = tostring(err)
                    self.app:_invalidateForm()
                end
            end
        end

        function node:help()
            if not (form and form.openDialog) then
                return false
            end

            form.openDialog({
                width = nil,
                title = self.baseTitle .. " Help",
                message = pageHelpText(self.spec.help),
                buttons = {{
                    label = "Close",
                    action = function()
                        return true
                    end
                }},
                options = TEXT_LEFT
            })

            return true
        end

        function node:close()
            local index

            self.state.closed = true
            self.state.reloadQueued = false
            self.state.reloadPrepared = false
            self.state.reloadFullPending = false
            self.state.loading = false
            self.state.saving = false
            self.state.needsInitialLoad = false

            releasePageApis(self, true)

            for index = 1, #(self.state.fields or {}) do
                if self.state.fields[index] then
                    self.state.fields[index].control = nil
                end
            end

            self.state.fields = {}
            self.state.rows = {}
            self.state.labels = {}
            self.state.columns = {}
            self.app.ui.clearProgressDialog(true)
        end

        return node
    end

    return Page
end

return MspPage
