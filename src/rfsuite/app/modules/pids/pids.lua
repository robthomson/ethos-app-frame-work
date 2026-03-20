--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local API_NAME = "PID_TUNING"

local ROWS = {
    "@i18n(app.modules.pids.roll)@",
    "@i18n(app.modules.pids.pitch)@",
    "@i18n(app.modules.pids.yaw)@"
}

local COLS = {
    "@i18n(app.modules.pids.p)@",
    "@i18n(app.modules.pids.i)@",
    "@i18n(app.modules.pids.d)@",
    "@i18n(app.modules.pids.f)@",
    "@i18n(app.modules.pids.o)@",
    "@i18n(app.modules.pids.b)@"
}

local FIELDS = {
    {row = 1, col = 1, key = "pid_0_P", min = 0, max = 1000},
    {row = 2, col = 1, key = "pid_1_P", min = 0, max = 1000},
    {row = 3, col = 1, key = "pid_2_P", min = 0, max = 1000},
    {row = 1, col = 2, key = "pid_0_I", min = 0, max = 1000},
    {row = 2, col = 2, key = "pid_1_I", min = 0, max = 1000},
    {row = 3, col = 2, key = "pid_2_I", min = 0, max = 1000},
    {row = 1, col = 3, key = "pid_0_D", min = 0, max = 1000},
    {row = 2, col = 3, key = "pid_1_D", min = 0, max = 1000},
    {row = 3, col = 3, key = "pid_2_D", min = 0, max = 1000},
    {row = 1, col = 4, key = "pid_0_F", min = 0, max = 1000},
    {row = 2, col = 4, key = "pid_1_F", min = 0, max = 1000},
    {row = 3, col = 4, key = "pid_2_F", min = 0, max = 1000},
    {row = 1, col = 5, key = "pid_0_O", min = 0, max = 1000},
    {row = 2, col = 5, key = "pid_1_O", min = 0, max = 1000},
    {row = 1, col = 6, key = "pid_0_B", min = 0, max = 1000},
    {row = 2, col = 6, key = "pid_1_B", min = 0, max = 1000},
    {row = 3, col = 6, key = "pid_2_B", min = 0, max = 1000}
}

local HELP_TEXT = table.concat({
    "@i18n(app.modules.pids.help_p1)@",
    "@i18n(app.modules.pids.help_p2)@",
    "@i18n(app.modules.pids.help_p3)@",
    "@i18n(app.modules.pids.help_p4)@"
}, "\n\n")

local function currentApi(app)
    local mspTask = app.framework:getTask("msp")

    if not mspTask or not mspTask.api or not mspTask.api.load then
        return nil, "msp_unavailable"
    end

    return mspTask.api.load(API_NAME)
end

local function updateTitle(node)
    local profile = node.app.framework.session:get("activeProfile")
    local nextTitle = node.baseTitle

    if profile ~= nil then
        nextTitle = nextTitle .. " #" .. tostring(profile)
    end

    if node.title ~= nextTitle then
        node.title = nextTitle
        node.app:_invalidateForm()
    end
end

local function applyParsedValues(node, parsed)
    local index
    local field

    for index = 1, #FIELDS do
        field = FIELDS[index]
        node.state.values[field.key] = tonumber(parsed[field.key]) or 0
    end

    node.state.api = nil
    node.state.loaded = true
    node.state.loading = false
    node.state.saving = false
    node.state.error = nil
    updateTitle(node)
    node.app:_invalidateForm()
end

local function applyReadResult(node, api)
    local result = api and api.data and api.data() or nil
    local parsed = result and result.parsed or {}

    applyParsedValues(node, parsed)
    node.app.ui.clearProgressDialog(true)
end

local function beginRead(node, message)
    local api, err = currentApi(node.app)
    local ok
    local reason

    if not api then
        node.state.loading = false
        node.state.error = tostring(err)
        node.app:_invalidateForm()
        return false
    end

    node.state.api = api
    node.state.loaded = false
    node.state.loading = true
    node.state.error = nil

    if api.setTimeout then
        api.setTimeout(3.0)
    end
    if api.setUUID then
        api.setUUID("pids-read-" .. tostring(os.clock()))
    end
    api.setCompleteHandler(function()
        applyReadResult(node, api)
    end)
    api.setErrorHandler(function(_, reasonText)
        node.state.loading = false
        node.state.error = tostring(reasonText or "read_error")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    node.app.ui.showLoader({
        kind = "progress",
        title = node.baseTitle,
        message = message or "Loading PID tuning.",
        closeWhenIdle = true,
        modal = true
    })

    ok, reason = api.read()
    if ok == false then
        node.state.loading = false
        node.state.error = tostring(reason or "read_failed")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function beginSave(node)
    local api, err = currentApi(node.app)
    local index
    local field
    local ok
    local reason

    if not api then
        node.state.error = tostring(err)
        node.app:_invalidateForm()
        return false
    end

    node.state.api = api
    node.state.saving = true
    node.state.error = nil

    for index = 1, #FIELDS do
        field = FIELDS[index]
        api.setValue(field.key, tonumber(node.state.values[field.key]) or 0)
    end

    if api.setTimeout then
        api.setTimeout(4.0)
    end
    api.setUUID("pids-write-" .. tostring(os.clock()))
    api.setCompleteHandler(function()
        node.state.saving = false
        node.app.ui.clearProgressDialog(true)
        node.app:setPageDirty(false)
        node.app:_invalidateForm()
    end)
    api.setErrorHandler(function(_, reasonText)
        node.state.saving = false
        node.state.error = tostring(reasonText or "write_error")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
    end)

    node.app.ui.showLoader({
        kind = "save",
        title = node.baseTitle,
        message = "Saving PID tuning.",
        closeWhenIdle = true,
        modal = true
    })

    ok, reason = api.write()
    if ok == false then
        node.state.saving = false
        node.state.error = tostring(reason or "write_failed")
        node.app.ui.clearProgressDialog(true)
        node.app:_invalidateForm()
        return false
    end

    return true
end

local function buildPidGrid(node, app)
    local numCols = #COLS
    local screenWidth = app:_windowSize() - 10
    local padding = 10
    local paddingTop = app.radio.linePaddingTop or 0
    local rowHeight = app.radio.navbuttonHeight or 30
    local width = (screenWidth * 70 / 100) / numCols
    local paddingRight = 20
    local positions = {}
    local loc = numCols
    local posX = screenWidth - paddingRight
    local posY = paddingTop
    local headerLine = form.addLine("")
    local rowLines = {}
    local index
    local fieldDef
    local pos

    while loc > 0 do
        pos = {x = posX, y = posY, w = width, h = rowHeight}
        form.addStaticText(headerLine, pos, COLS[loc])
        positions[loc] = posX - width + paddingRight
        posX = math.floor(posX - width)
        loc = loc - 1
    end

    for index = 1, #ROWS do
        rowLines[index] = form.addLine(ROWS[index])
    end

    for index = 1, #FIELDS do
        fieldDef = FIELDS[index]
        pos = {
            x = positions[fieldDef.col] + padding,
            y = posY,
            w = width - padding,
            h = rowHeight
        }

        form.addNumberField(rowLines[fieldDef.row], pos, fieldDef.min, fieldDef.max,
            function()
                return tonumber(node.state.values[fieldDef.key]) or 0
            end,
            function(newValue)
                node.state.values[fieldDef.key] = math.max(fieldDef.min, math.min(fieldDef.max, math.floor(tonumber(newValue) or 0)))
            end)
    end
end

function Page:open(ctx)
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.pids.name)@",
        title = ctx.item.title or "@i18n(app.modules.pids.name)@",
        subtitle = ctx.item.subtitle or "Primary PID tuning",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        usesMspApi = true,
        refreshOnProfileChange = true,
        app = ctx.app,
        state = {
            api = nil,
            values = {},
            loaded = false,
            loading = false,
            saving = false,
            error = nil,
            lastTitleProfile = nil
        }
    }
    local index
    local field

    for index = 1, #FIELDS do
        field = FIELDS[index]
        node.state.values[field.key] = 0
    end

    function node:buildForm(app)
        local line

        updateTitle(self)

        if self.state.error then
            line = form.addLine("Status")
            form.addStaticText(line, nil, tostring(self.state.error))
        elseif self.state.loaded ~= true then
            line = form.addLine("Status")
            form.addStaticText(line, nil, self.state.loading == true and "Loading..." or "Waiting...")
        end

        if self.state.loaded == true then
            buildPidGrid(self, app)
        end
    end

    function node:canSave(app)
        if self.state.loaded ~= true or self.state.loading == true or self.state.saving == true or self.state.error ~= nil then
            return false
        end
        if app:_saveDirtyOnly() == true then
            return app.pageDirty == true
        end
        return true
    end

    function node:save(app)
        if not self:canSave(app) then
            return false
        end
        return beginSave(self)
    end

    function node:reload(app)
        self.state.loaded = false
        return beginRead(self, "Reloading PID tuning.")
    end

    function node:help(app)
        if not (form and form.openDialog) then
            return false
        end

        form.openDialog({
            width = nil,
            title = self.baseTitle,
            message = HELP_TEXT,
            buttons = {{
                label = "OK",
                action = function()
                    return true
                end
            }},
            wakeup = function() end,
            paint = function() end,
            options = TEXT_LEFT
        })
        return true
    end

    function node:wakeup(app)
        local profile = app.framework.session:get("activeProfile")

        if self.state.loaded ~= true and self.state.loading ~= true and self.state.saving ~= true then
            beginRead(self, "Loading PID tuning.")
            return
        end

        if self.state.loading == true and self.state.api and self.state.api.readComplete and self.state.api:readComplete() == true then
            applyReadResult(self, self.state.api)
            return
        end

        if self.state.saving == true and self.state.api and self.state.api.writeComplete and self.state.api:writeComplete() == true then
            self.state.saving = false
            app.ui.clearProgressDialog(true)
            app:setPageDirty(false)
            app:_invalidateForm()
            return
        end

        if profile ~= self.state.lastTitleProfile then
            self.state.lastTitleProfile = profile
            updateTitle(self)
        end
    end

    function node:close()
        self.app.ui.clearProgressDialog(true)
        self.state.loading = false
        self.state.saving = false
    end

    if ctx.app.callback then
        ctx.app.callback:now(function()
            if ctx.app.currentNode == node and node.state.loading ~= true and node.state.loaded ~= true then
                beginRead(node, "Loading PID tuning.")
            end
        end, "immediate")
    end

    return node
end

return Page
