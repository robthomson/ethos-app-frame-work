--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")

local MspPage = {}

local FIELD_TYPE_CHOICE = 1
local DEFAULT_INLINE_SIZE = 13.6
local DEFAULT_NAV = {menu = true, save = true, reload = true, tool = false, help = false}

local function copyTable(source)
    local out = {}
    local key

    for key, value in pairs(source or {}) do
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

    return value
end

local function setterValue(field, controlValue)
    local value = tonumber(controlValue)

    if value == nil then
        return nil
    end

    if field.offset then
        value = value - field.offset
    end

    if field.mult then
        value = value / field.mult
    end

    return value
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

    if lcd and lcd.font and FONT_STD then
        lcd.font(FONT_STD)
    end

    if lcd and lcd.getTextSize then
        textWidth = select(1, lcd.getTextSize(fieldText)) or 0
    end

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
        value = telemetry:getSensor("pid_profile")
    end

    if value == nil then
        value = node.app.framework.session:get("activeProfile", nil)
    end

    value = tonumber(value)
    if value == nil then
        return nil
    end

    return math.floor(value)
end

local function updateDynamicTitle(node)
    local newTitle = node.baseTitle

    if node.spec.titleProfileSuffix == "pid" then
        local profile = currentPidProfile(node)
        if profile ~= nil then
            newTitle = string.format("%s #%d", node.baseTitle, profile)
        end
    end

    if node.title ~= newTitle then
        node.title = newTitle
        node.app:_invalidateForm()
    end
end

local function ensureApis(node)
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

local function mergedField(node, fieldSpec)
    local apiName = fieldSpec.api or fieldSpec.apiName or node.state.defaultApiName
    local apiEntry = apiName and node.state.apis[apiName] or nil
    local api = apiEntry and apiEntry.api or nil
    local meta = api and api.describeField and api.describeField(fieldSpec.apikey) or nil
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

    if not control then
        return
    end

    if field.decimals and control.decimals and field.type ~= FIELD_TYPE_CHOICE then
        control:decimals(field.decimals)
    end

    if field.step and control.step and field.type ~= FIELD_TYPE_CHOICE then
        control:step(field.step)
    end

    if field.unit and control.suffix and field.type ~= FIELD_TYPE_CHOICE then
        control:suffix(field.unit)
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
    local values = convertChoiceTable(field.table, field.tableIdxInc)

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
            field.value = setterValue(field, newValue)
        end)
end

local function applyControlValue(control, value)
    local ok

    if control and control.value then
        ok = pcall(control.value, control, value)
        return ok == true
    end

    return false
end

local function refreshBuiltControls(node)
    local index
    local field
    local updated = false

    for index = 1, #(node.state.fields or {}) do
        field = node.state.fields[index]
        if field and field.control then
            updated = applyControlValue(field.control, field.value) or updated
        end
    end

    if updated ~= true then
        node.app:_invalidateForm()
    end
end

local function buildField(line, node, app, field)
    local positions = inlinePositions(node, app, field)
    local control

    if tostring(field.t or "") ~= "" then
        form.addStaticText(line, positions.text, tostring(field.t))
    end

    if field.type == FIELD_TYPE_CHOICE or type(field.table) == "table" then
        control = buildChoiceField(line, positions.field, field)
    else
        control = buildNumberField(line, positions.field, field)
    end

    applyFieldDecoration(control, field)
    field.control = control
    return control
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
    node.state.labels = visibleLabels(node)
    node.state.fields = mergeFieldsInPlace(node.state.fields or {}, visibleFields(node))
    return true
end

local function finishRead(node)
    prepareLayout(node)
    node.state.loaded = true
    node.state.loading = false
    node.state.error = nil
    updateDynamicTitle(node)
    refreshBuiltControls(node)
    node.app.ui.clearProgressDialog(true)
end

local function failRead(node, reason)
    node.state.loading = false
    node.state.loaded = false
    node.state.error = tostring(reason or "read_failed")
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
        node.state.saving = false
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return true
    end

    if not mspTask or type(mspTask.queueCommand) ~= "function" then
        node.state.saving = false
        node.state.error = "eeprom_unavailable"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    ok, reason = mspTask:queueCommand(250, {}, {
        timeout = 2.0,
        simulatorResponse = {},
        onReply = function()
            node.state.saving = false
            node.state.error = nil
            node.app.ui.clearProgressDialog(true)
            node.app:_invalidateForm()
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
        local node = {
            spec = spec or {},
            app = ctx.app,
            baseTitle = ctx.item.title or spec.title or "MSP Page",
            title = ctx.item.title or spec.title or "MSP Page",
            subtitle = ctx.item.subtitle or spec.subtitle or "MSP-backed settings",
            breadcrumb = ctx.breadcrumb,
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
                labels = {},
                defaultApiName = spec.api and spec.api[1] and spec.api[1].name or nil,
                loading = false,
                loaded = false,
                saving = false,
                error = nil,
                needsInitialLoad = true
            }
        }
        local navKey
        local okPrepare

        for navKey, enabled in pairs(spec.navButtons or {}) do
            node.navButtons[navKey] = enabled == true
        end

        okPrepare = ensureApis(node)
        if okPrepare then
            prepareLayout(node)
        end

        function node:buildForm(app)
            local groupedFields = {}
            local groupedIndex = {}
            local visibleLabelIndex = {}
            local labels = self.state.labels
            local fields = self.state.fields
            local index
            local label
            local field
            local line
            local labelId

            if self.state.error then
                line = form.addLine("Status")
                form.addStaticText(line, nil, tostring(self.state.error))
            end

            if #fields == 0 then
                line = form.addLine("Status")
                form.addStaticText(line, nil, self.state.loading == true and "Loading..." or "Waiting...")
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
                    for _, field in ipairs(groupedFields[label.label]) do
                        buildField(line, self, app, field)
                    end
                end
            end

            for index = 1, #fields do
                field = fields[index]
                if not (field.label ~= nil and field.inline ~= nil and groupedIndex[field.label] == true) then
                    line = form.addLine(tostring(field.t or field.apikey or "Field"))
                    if field.type == FIELD_TYPE_CHOICE or type(field.table) == "table" then
                        field.control = buildChoiceField(line, nil, field)
                    else
                        field.control = buildNumberField(line, nil, field)
                    end
                    applyFieldDecoration(field.control, field)
                end
            end
        end

        function node:canSave()
            return self.state.loaded == true and self.state.loading ~= true and self.state.saving ~= true and self.state.error == nil
        end

        function node:reload(showLoader)
            local ok
            local err
            local shouldShowLoader = showLoader ~= false

            ok, err = ensureApis(self)
            if not ok then
                failRead(self, err)
                return false
            end

            prepareLayout(self)

            self.state.loading = true
            self.state.loaded = false
            self.state.error = nil

            self.app:_invalidateForm()

            if shouldShowLoader == true then
                beginLoader(self, {
                    kind = "progress",
                    title = self.baseTitle,
                    message = "Loading values.",
                    closeWhenIdle = true,
                    modal = true
                })
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
                    apiEntry.api.setValue(field.apikey, field.value)
                end
            end

            self.state.saving = true
            self.state.error = nil
            beginLoader(self, {
                kind = "save",
                title = self.baseTitle,
                message = "Saving values.",
                closeWhenIdle = true,
                modal = true
            })

            return runWrite(self, 1)
        end

        function node:wakeup()
            if self.state.needsInitialLoad == true and self.state.loading ~= true and self.state.loaded ~= true then
                self.state.needsInitialLoad = false
                self:reload(true)
                return
            end

            updateDynamicTitle(self)
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
            self.state.loading = false
            self.state.saving = false
            self.app.ui.clearProgressDialog(true)
        end

        return node
    end

    return Page
end

return MspPage
