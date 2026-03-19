--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local API_NAME = "EXPERIMENTAL"
local MAX_BYTES = 16

local function uint8ToInt8(value)
    local n = tonumber(value) or 0

    n = math.max(0, math.min(255, math.floor(n)))
    if n > 127 then
        return n - 256
    end
    return n
end

local function int8ToUint8(value)
    local n = tonumber(value) or 0

    n = math.max(-128, math.min(127, math.floor(n)))
    if n < 0 then
        return n + 256
    end
    return n
end

local function readConfiguredByteCount(framework)
    local developer = framework.preferences:section("developer", {})
    local count = tonumber(developer.mspexpbytes) or 8

    if count < 0 then
        return 0
    end
    if count > MAX_BYTES then
        return MAX_BYTES
    end
    return count
end

local function persistByteCount(app, count)
    local developer = app.framework.preferences:section("developer", {})
    local safeCount = math.max(0, math.min(MAX_BYTES, tonumber(count) or 8))

    developer.mspexpbytes = safeCount
    app.framework.preferences:save()
end

local function currentApi(app)
    local mspTask = app.framework:getTask("msp")

    if not mspTask or not mspTask.api or not mspTask.api.load then
        return nil, "msp_unavailable"
    end

    return mspTask.api.load(API_NAME)
end

local function refreshMirrors(state)
    local i

    for i = 1, MAX_BYTES do
        state.intValues[i] = uint8ToInt8(state.uintValues[i] or 0)
    end
end

local function applyReadResult(node, api)
    local state = node.state
    local result = api and api.data and api.data() or nil
    local parsed = result and result.parsed or {}
    local receivedCount = tonumber(result and result.receivedBytesCount) or 0
    local i

    for i = 1, MAX_BYTES do
        state.uintValues[i] = tonumber(parsed["exp_uint" .. i]) or 0
    end
    refreshMirrors(state)

    state.byteCount = math.max(0, math.min(MAX_BYTES, receivedCount))
    persistByteCount(node.app, state.byteCount)

    state.loaded = true
    state.loading = false
    state.saving = false
    state.error = nil
    state.status = state.byteCount > 0 and "Ready" or "No Data"
    node.app.ui.clearProgressDialog(true)
    node.app:_invalidateForm()
end

local function buildByteRow(node, app, index)
    local width = app:_windowSize()
    local rowH = app.radio.navbuttonHeight or 30
    local rowY = app.radio.linePaddingTop or 0
    local labelW = 34
    local gap = 8
    local boxW = math.max(70, math.floor((width - labelW - (gap * 4)) / 2))
    local line = form.addLine(tostring(index))
    local intX = labelW + gap
    local uintX = intX + boxW + gap
    local intField
    local uintField

    intField = form.addNumberField(line, {x = intX, y = rowY, w = boxW, h = rowH}, -128, 127,
        function()
            return node.state.intValues[index] or 0
        end,
        function(newValue)
            local intValue = math.max(-128, math.min(127, math.floor(tonumber(newValue) or 0)))
            local uintValue = int8ToUint8(intValue)

            node.state.intValues[index] = intValue
            node.state.uintValues[index] = uintValue
            if node.fields.uintFields[index] and node.fields.uintFields[index].value then
                node.fields.uintFields[index]:value(uintValue)
            end
        end)

    uintField = form.addNumberField(line, {x = uintX, y = rowY, w = boxW, h = rowH}, 0, 255,
        function()
            return node.state.uintValues[index] or 0
        end,
        function(newValue)
            local uintValue = math.max(0, math.min(255, math.floor(tonumber(newValue) or 0)))
            local intValue = uint8ToInt8(uintValue)

            node.state.uintValues[index] = uintValue
            node.state.intValues[index] = intValue
            if node.fields.intFields[index] and node.fields.intFields[index].value then
                node.fields.intFields[index]:value(intValue)
            end
        end)

    node.fields.intFields[index] = intField
    node.fields.uintFields[index] = uintField
end

local function beginRead(node, message)
    local api, err = currentApi(node.app)
    local state = node.state
    local ok
    local reason

    if not api then
        state.loading = false
        state.error = tostring(err)
        state.status = "Read Failed"
        node.app:_invalidateForm()
        return false
    end

    state.api = api
    state.loading = true
    state.error = nil
    state.status = "Reading"

    api.setUUID("msp-exp-read")
    api.setCompleteHandler(function()
        applyReadResult(node, api)
    end)
    api.setErrorHandler(function(_, reason)
        state.loading = false
        state.error = tostring(reason or "read_error")
        state.status = "Read Failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    node.app.ui.showLoader({
        kind = "progress",
        title = "MSP Experimental",
        message = message or "Loading experimental values.",
        closeWhenIdle = true,
        modal = true
    })

    ok, reason = api.read()
    if ok == false then
        state.loading = false
        state.error = tostring(reason or "read_failed")
        state.status = "Read Failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function beginSave(node)
    local api, err = currentApi(node.app)
    local state = node.state
    local i
    local ok
    local reason

    if not api then
        state.error = tostring(err)
        state.status = "Save Failed"
        return false
    end

    state.api = api
    state.saving = true
    state.error = nil
    state.status = "Saving"

    for i = 1, state.byteCount do
        api.setValue("exp_uint" .. i, state.uintValues[i] or 0)
    end

    api.setUUID("msp-exp-write")
    api.setCompleteHandler(function()
        state.saving = false
        state.status = "Ready"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)
    api.setErrorHandler(function(_, reasonText)
        state.saving = false
        state.error = tostring(reasonText or "write_error")
        state.status = "Save Failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    node.app.ui.showLoader({
        kind = "save",
        title = "MSP Experimental",
        message = "Saving experimental values.",
        closeWhenIdle = true,
        modal = true
    })

    ok, reason = api.write()
    if ok == false then
        state.saving = false
        state.error = tostring(reason or "write_failed")
        state.status = "Save Failed"
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

function Page:open(ctx)
    local node = {
        title = ctx.item.title or "MSP Experimental",
        subtitle = ctx.item.subtitle or "MSP experimentation",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = false},
        app = ctx.app,
        fields = {
            intFields = {},
            uintFields = {}
        },
        state = {
            api = nil,
            byteCount = readConfiguredByteCount(ctx.framework),
            uintValues = {},
            intValues = {},
            loaded = false,
            loading = false,
            saving = false,
            error = nil,
            status = "Idle",
            needsInitialLoad = true
        }
    }
    local i

    for i = 1, MAX_BYTES do
        node.state.uintValues[i] = 0
        node.state.intValues[i] = 0
    end

    function node:buildForm(app)
        local line
        local i

        self.fields.intFields = {}
        self.fields.uintFields = {}

        if self.state.error then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(self.state.error))
        elseif self.state.loaded ~= true then
            line = form.addLine("Status")
            form.addStaticText(line, nil, self.state.loading == true and "Loading..." or "Waiting...")
        elseif self.state.byteCount < 1 then
            line = form.addLine("Status")
            form.addStaticText(line, nil, "No experimental bytes returned.")
        end

        for i = 1, self.state.byteCount do
            buildByteRow(self, app, i)
        end
    end

    function node:canSave(app)
        return self.state.loaded == true and self.state.loading ~= true and self.state.saving ~= true and self.state.error == nil and (self.state.byteCount or 0) > 0
    end

    function node:save(app)
        if not self:canSave(app) then
            return false
        end
        return beginSave(self)
    end

    function node:reload(app)
        self.state.loaded = false
        return beginRead(self, "Reloading experimental values.")
    end

    function node:wakeup(app)
        if self.state.needsInitialLoad == true and self.state.loading ~= true and self.state.loaded ~= true then
            self.state.needsInitialLoad = false
            beginRead(self, "Loading experimental values.")
        end
    end

    function node:close()
        self.app.ui.clearProgressDialog(true)
        self.state.loading = false
        self.state.saving = false
    end

    return node
end

return Page
