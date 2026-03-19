--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local LABEL_INFO = "Info"
local LABEL_VALUE = "Value"
local LABEL_ERROR = "Error"
local LABEL_FIELDS = "Fields"
local LABEL_STATUS = "Status"
local LABEL_API = "API"
local BUTTON_TEST = "Test"
local PANEL_READ_RESULT = "Read Result"
local STATUS_IDLE = "Idle"
local STATUS_LOAD_FAILED = "Load Failed"
local STATUS_READING = "Reading"
local STATUS_OK = "OK"
local MSG_CHOOSE_API = "Choose an API definition."
local MSG_NO_DATA = "No data."
local MSG_NO_API_SELECTED = "No API selected."
local MSG_NO_PARSED_RESULT = "No parsed result."
local MSG_READ_COMPLETED_ZERO = "Read completed with zero parsed fields."
local MSG_UNABLE_TO_LOAD = "Unable to load"
local MSG_WAITING_RESPONSE = "Waiting for response..."
local MSG_READ_FAILED = "Read failed."
local CHOICE_NO_API_FILES = "No API Files"
local MAX_LINE_CHARS = 90

local EXCLUDED_APIS = {
    EEPROM_WRITE = true
}

local function truncateText(text)
    text = tostring(text or ""):gsub("[%c]+", " ")
    if #text > MAX_LINE_CHARS then
        return text:sub(1, MAX_LINE_CHARS - 3) .. "..."
    end
    return text
end

local function sortAsc(a, b)
    return tostring(a) < tostring(b)
end

local function fileToApiName(filename)
    local name

    if type(filename) ~= "string" or not filename:match("%.lua$") then
        return nil
    end

    name = filename:gsub("%.lua$", "")
    if name == "" or EXCLUDED_APIS[name] then
        return nil
    end

    return name
end

local function valueString(value)
    local kind = type(value)

    if kind == "nil" then
        return "nil"
    end
    if kind == "boolean" then
        return value and "true" or "false"
    end
    if kind == "table" then
        return "<table>"
    end

    return tostring(value)
end

local function selectedApiName(state)
    local index = tonumber(state.selected) or 1

    return state.apiNames[index]
end

local function getDisplayRows(state)
    local rowsOut = {}
    local i

    for i = 1, #(state.rows or {}) do
        local row = state.rows[i] or {}
        local label = truncateText(row.label or "")
        local value = truncateText(row.value or "")

        if label:match("%S") or value:match("%S") then
            if not label:match("%S") then
                label = LABEL_VALUE
            end
            if not value:match("%S") then
                value = "-"
            end
            rowsOut[#rowsOut + 1] = {label = label, value = value}
        end
    end

    if #rowsOut == 0 then
        rowsOut[1] = {label = LABEL_INFO, value = MSG_NO_DATA}
    end

    return rowsOut
end

local function parseReadResult(state, api)
    local result = api and api.data and api.data() or nil
    local parsed = result and result.parsed or nil
    local rowsOut = {}
    local keys = {}
    local key

    if not parsed then
        state.rows = {{label = LABEL_INFO, value = MSG_NO_PARSED_RESULT}}
        state.fieldCount = 0
        return
    end

    for key in pairs(parsed) do
        keys[#keys + 1] = key
    end
    table.sort(keys, sortAsc)

    for _, key in ipairs(keys) do
        rowsOut[#rowsOut + 1] = {label = key, value = valueString(parsed[key])}
    end

    if #rowsOut == 0 then
        rowsOut[1] = {label = LABEL_INFO, value = MSG_READ_COMPLETED_ZERO}
    end

    state.rows = rowsOut
    state.fieldCount = #keys
end

local function buildApiList(state, framework)
    local names = {}
    local apiDir = "SCRIPTS:/" .. tostring((framework.config and framework.config.baseDir) or "rfsuite") .. "/mspapi/definitions"
    local files = system and system.listFiles and system.listFiles(apiDir) or {}
    local i

    state.apiNames = {}
    state.apiChoices = {}

    for i = 1, #files do
        local name = fileToApiName(files[i])
        if name then
            names[#names + 1] = name
        end
    end

    table.sort(names, sortAsc)
    state.apiNames = names

    for i = 1, #names do
        state.apiChoices[#state.apiChoices + 1] = {names[i], i}
    end

    if #state.apiChoices == 0 then
        state.apiChoices = {{CHOICE_NO_API_FILES, 1}}
        state.selected = 1
    elseif state.selected < 1 or state.selected > #state.apiChoices then
        state.selected = 1
    end
end

function Page:open(ctx)
    local state = {
        apiNames = {},
        apiChoices = {},
        selected = 1,
        status = STATUS_IDLE,
        rows = {{label = LABEL_INFO, value = MSG_CHOOSE_API}},
        fieldCount = 0,
        pendingRebuild = false,
        autoOpenResults = false
    }
    local node = {
        title = ctx.item.title or "API Tester",
        subtitle = ctx.item.subtitle or "Manual API calls",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = false},
        state = state,
        fields = {},
        app = ctx.app
    }

    buildApiList(state, ctx.framework)

    function node:setStatus(text)
        state.status = text
        if self.fields.status and self.fields.status.value then
            self.fields.status:value(text)
        end
    end

    function node:requestRebuild(openResults)
        state.pendingRebuild = true
        if openResults == true then
            state.autoOpenResults = true
        end
    end

    function node:runTest()
        local mspTask = self.app.framework:getTask("msp")
        local apiName = selectedApiName(state)
        local api
        local loadErr
        local ok
        local reason

        if not apiName then
            state.rows = {{label = LABEL_INFO, value = MSG_NO_API_SELECTED}}
            state.fieldCount = 0
            self:setStatus(MSG_NO_API_SELECTED)
            self:requestRebuild(true)
            return true
        end

        if not mspTask or not mspTask.api or not mspTask.api.load then
            state.rows = {{label = LABEL_ERROR, value = MSG_UNABLE_TO_LOAD .. ": " .. apiName}}
            state.fieldCount = 0
            self:setStatus(STATUS_LOAD_FAILED)
            self:requestRebuild(true)
            return true
        end

        api, loadErr = mspTask.api.load(apiName)
        if not api then
            state.rows = {{label = LABEL_ERROR, value = MSG_UNABLE_TO_LOAD .. ": " .. tostring(loadErr or apiName)}}
            state.fieldCount = 0
            self:setStatus(STATUS_LOAD_FAILED)
            self:requestRebuild(true)
            return true
        end

        state.rows = {{label = LABEL_STATUS, value = MSG_WAITING_RESPONSE}}
        state.fieldCount = 0
        self:setStatus(STATUS_READING .. " " .. apiName .. "...")
        self:requestRebuild(true)

        api.setCompleteHandler(function()
            parseReadResult(state, api)
            self:setStatus(STATUS_OK .. ": " .. tostring(state.fieldCount) .. " " .. LABEL_FIELDS)
            self:requestRebuild(true)
        end)

        api.setErrorHandler(function(_, err)
            state.rows = {
                {label = LABEL_STATUS, value = MSG_READ_FAILED},
                {label = LABEL_ERROR, value = tostring(err or "read_error")}
            }
            state.fieldCount = 0
            self:setStatus(LABEL_ERROR)
            self:requestRebuild(true)
        end)

        ok, reason = api.read()
        if ok == false then
            state.rows = {
                {label = LABEL_STATUS, value = MSG_READ_FAILED},
                {label = LABEL_ERROR, value = tostring(reason or "read_not_supported")}
            }
            state.fieldCount = 0
            self:setStatus(LABEL_ERROR)
            self:requestRebuild(true)
        end

        return true
    end

    function node:buildForm(app)
        local width = app:_windowSize()
        local rowY = app.radio.linePaddingTop or 0
        local testW = 80
        local gap = 6
        local choiceW = width - 20 - testW - gap
        local displayRows
        local resultsPanel
        local i
        local row
        local line

        if choiceW < 100 then
            choiceW = 100
        end

        line = form.addLine(LABEL_API)
        self.fields.api = form.addChoiceField(line, {x = 0, y = rowY, w = choiceW, h = app.radio.navbuttonHeight}, state.apiChoices,
            function()
                return state.selected
            end,
            function(newValue)
                state.selected = newValue
            end)

        self.fields.test = form.addButton(line, {x = choiceW + gap, y = rowY, w = testW, h = app.radio.navbuttonHeight}, {
            text = BUTTON_TEST,
            icon = nil,
            options = FONT_S,
            paint = nil,
            press = function()
                self:runTest()
            end
        })

        if self.fields.test and self.fields.test.enable then
            self.fields.test:enable(#state.apiNames > 0)
        end

        line = form.addLine(LABEL_STATUS)
        self.fields.status = form.addStaticText(line, nil, state.status)

        resultsPanel = form.addExpansionPanel and form.addExpansionPanel(PANEL_READ_RESULT) or nil
        if resultsPanel and resultsPanel.open then
            resultsPanel:open(true)
        end
        state.autoOpenResults = false

        displayRows = getDisplayRows(state)
        for i = 1, #displayRows do
            row = displayRows[i]
            if resultsPanel and resultsPanel.addLine then
                line = resultsPanel:addLine(row.label)
            else
                line = form.addLine(row.label)
            end
            form.addStaticText(line, nil, row.value)
        end
    end

    function node:wakeup(app)
        if state.pendingRebuild == true then
            state.pendingRebuild = false
            app:_invalidateForm()
        end
    end

    return node
end

return Page
