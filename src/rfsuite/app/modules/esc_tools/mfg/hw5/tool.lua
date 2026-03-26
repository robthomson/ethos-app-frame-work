--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local utils = require("lib.utils")
local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()
local hw5 = assert(loadfile("app/modules/esc_tools/mfg/hw5/init.lua"))()
local pages = assert(loadfile("app/modules/esc_tools/mfg/hw5/pages.lua"))()

local API_NAME = "ESC_PARAMETERS_HW5"
local SESSION_DETAILS = "esc_tools_hw5_details"

local function unloadApi(node)
    local api = node.state.api
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil

    node.state.api = nil

    if api and api.setCompleteHandler then
        api.setCompleteHandler(function() end)
    end
    if api and api.setErrorHandler then
        api.setErrorHandler(function() end)
    end
    if api and api.setUUID then
        api.setUUID(nil)
    end
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end
    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(API_NAME)
    end
end

local function beginLoad(node, showLoader)
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load(API_NAME) or nil

    if node.state.loading == true then
        return false
    end

    if showLoader ~= false then
        escTools.showLoader(node.app, {
            kind = "progress",
            title = node.baseTitle,
            message = "@i18n(app.modules.esc_tools.waitingforesc)@",
            closeWhenIdle = false,
            watchdogTimeout = 12.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if not api then
        node.state.error = "ESC_PARAMETERS_HW5 unavailable."
        escTools.clearLoader(node.app)
        return false
    end

    node.state.loading = true
    node.state.loaded = false
    node.state.error = nil
    node.state.api = api

    if api.setTimeout then
        api.setTimeout(8.0)
    end
    if api.setUUID then
        api.setUUID(utils.uuid("esc-hw5-tool"))
    end

    api.setCompleteHandler(function(_, buf)
        local data = api.data and api.data() or {}
        local parsed = data.parsed or {}

        unloadApi(node)
        node.state.loading = false

        if escTools.nodeIsOpen(node) ~= true then
            return
        end

        node.state.loaded = true
        node.state.details = hw5.details(buf, parsed)
        escTools.setSessionValue(node.app, SESSION_DETAILS, node.state.details)
        escTools.clearLoader(node.app)
        node.app:_invalidateForm()
    end)

    api.setErrorHandler(function(_, reason)
        unloadApi(node)
        node.state.loading = false

        if escTools.nodeIsOpen(node) ~= true then
            return
        end

        node.state.error = tostring(reason or "ESC_PARAMETERS_HW5 read failed.")
        escTools.clearLoader(node.app)
        node.app:_invalidateForm()
    end)

    if api.read() ~= true then
        unloadApi(node)
        node.state.loading = false
        node.state.error = "ESC_PARAMETERS_HW5 read failed."
        escTools.clearLoader(node.app)
        return false
    end

    return true
end

local Page = {}

function Page:open(ctx)
    local state = {
        closed = false,
        loading = false,
        loaded = false,
        error = nil,
        api = nil,
        icons = {},
        details = escTools.getSessionValue(ctx.app, SESSION_DETAILS, nil)
    }

    if state.details ~= nil then
        state.loaded = true
    end

    local node = {
        app = ctx.app,
        baseTitle = ctx.item.title or "@i18n(app.modules.esc_tools.mfg.hw5.name)@",
        title = ctx.item.title or "@i18n(app.modules.esc_tools.mfg.hw5.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_tools.name)@",
        breadcrumb = ctx.breadcrumb,
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            title = ctx.item.title or "@i18n(app.modules.esc_tools.mfg.hw5.name)@",
            message = "@i18n(app.modules.esc_tools.waitingforesc)@",
            closeWhenIdle = false,
            watchdogTimeout = 12.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        },
        navButtons = {
            menu = true,
            save = false,
            reload = true,
            tool = false,
            help = false
        },
        state = state
    }

    function node:buildForm(app)
        local line
        local detail
        local index
        local page
        local items = {}

        if state.error ~= nil then
            line = form.addLine("Status")
            form.addStaticText(line, nil, "Error")
            line = form.addLine("")
            form.addStaticText(line, escTools.statusPos(app), tostring(state.error))
            return
        end

        detail = state.details
        if detail ~= nil then
            line = form.addLine("")
            form.addStaticText(line, escTools.statusPos(app), escTools.formatDetails(detail))
        end

        if state.loaded ~= true then
            return
        end

        for index = 1, #pages do
            page = pages[index]
            local currentIndex = index
            local currentPage = page
            items[#items + 1] = {
                title = currentPage.title,
                image = currentPage.image,
                press = function()
                    app:_enterItem(currentIndex, {
                        id = "esc-hw5-" .. tostring(currentPage.id),
                        kind = "page",
                        path = currentPage.path,
                        title = currentPage.title,
                        subtitle = self.baseTitle
                    })
                end
            }
        end

        escTools.renderGrid(self, app, items)
    end

    function node:wakeup()
        if state.loaded ~= true and state.loading ~= true then
            beginLoad(self, false)
        end
    end

    function node:reload()
        escTools.setSessionValue(self.app, SESSION_DETAILS, nil)
        state.details = nil
        state.loaded = false
        state.error = nil
        self.app:_invalidateForm()
        return beginLoad(self, true)
    end

    function node:close()
        state.closed = true
        unloadApi(self)
    end

    return node
end

return Page
