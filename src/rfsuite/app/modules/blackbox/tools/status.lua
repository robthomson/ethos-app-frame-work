--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()

local FIELD = {
    DATAFLASH = 1,
    SDCARD = 2
}

local SDCARD_STATE = {
    NOT_PRESENT = 0,
    FATAL = 1,
    CARD_INIT = 2,
    FS_INIT = 3,
    READY = 4
}

local STATUS_HELP = {
    "@i18n(app.modules.blackbox.help_p1)@",
    "@i18n(app.modules.blackbox.help_p2)@",
    "@i18n(app.modules.blackbox.help_p3)@"
}

local function hasBit(mask, bit)
    local numericMask = tonumber(mask or 0) or 0
    local flag = 2 ^ (tonumber(bit or 0) or 0)
    return math.floor(numericMask / flag) % 2 == 1
end

local function formatSize(bytes)
    if not bytes or bytes <= 0 then
        return "0 B"
    end
    if bytes < 1024 then
        return string.format("%d B", bytes)
    end
    if bytes < (1024 * 1024) then
        return string.format("%.1f kB", bytes / 1024)
    end
    if bytes < (1024 * 1024 * 1024) then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    end
    return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
end

local function formatDataflashStatus(state)
    if state.dataflash.supported ~= true then
        return "@i18n(app.modules.blackbox.not_supported)@"
    end
    if state.eraseInProgress == true or state.dataflash.ready ~= true then
        return "@i18n(app.modules.blackbox.erasing_busy)@"
    end
    return string.format("@i18n(app.modules.blackbox.used_fmt)@", formatSize(state.dataflash.usedSize or 0), formatSize(state.dataflash.totalSize or 0))
end

local function formatSDCardStatus(state)
    local sdcardState = tonumber(state.sdcard.state) or SDCARD_STATE.NOT_PRESENT

    if state.sdcard.supported ~= true then
        return "@i18n(app.modules.blackbox.not_supported)@"
    end
    if sdcardState == SDCARD_STATE.NOT_PRESENT then
        return "@i18n(app.modules.blackbox.no_card)@"
    end
    if sdcardState == SDCARD_STATE.FATAL then
        return string.format("@i18n(app.modules.blackbox.error_code_fmt)@", tonumber(state.sdcard.filesystemLastError) or 0)
    end
    if sdcardState == SDCARD_STATE.CARD_INIT then
        return "@i18n(app.modules.blackbox.initializing_card)@"
    end
    if sdcardState == SDCARD_STATE.FS_INIT then
        return "@i18n(app.modules.blackbox.initializing_filesystem)@"
    end
    if sdcardState == SDCARD_STATE.READY then
        local totalKB = tonumber(state.sdcard.totalSizeKB) or 0
        local freeKB = tonumber(state.sdcard.freeSizeKB) or 0
        local usedKB = math.max(totalKB - freeKB, 0)
        return string.format("@i18n(app.modules.blackbox.used_fmt)@", formatSize(usedKB * 1024), formatSize(totalKB * 1024))
    end

    return string.format("@i18n(app.modules.blackbox.unknown_state_fmt)@", sdcardState)
end

local function updateStatusFields(node)
    local state = node.state
    local fields = state.formFields or {}

    if fields[FIELD.DATAFLASH] and fields[FIELD.DATAFLASH].value then
        fields[FIELD.DATAFLASH]:value(formatDataflashStatus(state))
    end
    if fields[FIELD.SDCARD] and fields[FIELD.SDCARD].value then
        fields[FIELD.SDCARD]:value(formatSDCardStatus(state))
    end
end

local function pollDataflash(node)
    local mspTask = node.app.framework:getTask("msp")
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("DATAFLASH_SUMMARY")

    if not api then
        return false
    end

    api.setCompleteHandler(function()
        local parsed = api.data and api.data().parsed or {}

        if node.state.closed == true then
            if mspTask.api and mspTask.api.unload then
                mspTask.api.unload("DATAFLASH_SUMMARY")
            end
            return
        end

        node.state.dataflash.ready = hasBit(parsed.flags, 0)
        node.state.dataflash.supported = hasBit(parsed.flags, 1)
        node.state.dataflash.totalSize = tonumber(parsed.total) or 0
        node.state.dataflash.usedSize = tonumber(parsed.used) or 0

        if mspTask.api and mspTask.api.unload then
            mspTask.api.unload("DATAFLASH_SUMMARY")
        end
        updateStatusFields(node)
    end)
    api.setErrorHandler(function()
        if mspTask.api and mspTask.api.unload then
            mspTask.api.unload("DATAFLASH_SUMMARY")
        end
    end)

    return api.read() == true
end

local function pollSDCard(node)
    local mspTask = node.app.framework:getTask("msp")
    local helper = mspTask and mspTask.mspHelper or nil

    if not (mspTask and mspTask.queueCommand and helper) then
        return false
    end

    return mspTask:queueCommand(79, {}, {
        timeout = 1.0,
        simulatorResponse = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0},
        onReply = function(_, buf)
            if node.state.closed == true then
                return
            end

            buf.offset = 1
            node.state.sdcard.supported = hasBit(helper.readU8(buf), 0)
            node.state.sdcard.state = helper.readU8(buf)
            node.state.sdcard.filesystemLastError = helper.readU8(buf)
            node.state.sdcard.freeSizeKB = helper.readU32(buf)
            node.state.sdcard.totalSizeKB = helper.readU32(buf)

            updateStatusFields(node)
        end
    }) == true
end

local function beginPoll(node, showLoader)
    node.state.pollAt = os.clock() + 2.0

    if showLoader == true then
        node.app.ui.showLoader({
            kind = "progress",
            title = node.title or "@i18n(app.modules.blackbox.menu_status)@",
            message = "Loading values.",
            closeWhenIdle = false,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        })
    end

    pollDataflash(node)
    pollSDCard(node)

    if showLoader == true then
        node.app.ui.clearProgressDialog(true)
    end
end

local function eraseDataflash(node)
    local mspTask = node.app.framework:getTask("msp")
    local ok

    node.state.eraseInProgress = true
    node.app.ui.showLoader({
        kind = "progress",
        title = node.title or "@i18n(app.modules.blackbox.menu_status)@",
        message = "@i18n(app.modules.blackbox.erasing_dataflash)@",
        closeWhenIdle = false,
        transferInfo = true,
        modal = true
    })

    ok = mspTask and mspTask.queueCommand and mspTask:queueCommand(72, {}, {
        timeout = 1.0,
        simulatorResponse = {},
        onReply = function()
            if node.state.closed == true then
                return
            end
            node.state.eraseInProgress = true
            node.app.ui.clearProgressDialog(true)
            beginPoll(node, false)
        end,
        onError = function(_, err)
            if node.state.closed == true then
                return
            end
            node.state.eraseInProgress = false
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.blackbox.name)@", tostring(err or "@i18n(app.modules.blackbox.erasing_busy)@"))
        end
    })

    if ok ~= true then
        node.state.eraseInProgress = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.blackbox.name)@", "@i18n(app.modules.blackbox.erasing_busy)@")
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        dataflash = {
            ready = false,
            supported = false,
            totalSize = 0,
            usedSize = 0
        },
        sdcard = {
            supported = false,
            state = 0,
            filesystemLastError = 0,
            freeSizeKB = 0,
            totalSizeKB = 0
        },
        eraseInProgress = false,
        pollAt = 0,
        formFields = {},
        closed = false,
        needsInitialLoad = true
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.blackbox.menu_status)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.blackbox.name)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = true, tool = true, help = true},
        state = state
    }

    function node:buildForm(app)
        local line

        self.app = app
        state.formFields = {}

        line = form.addLine("@i18n(app.modules.blackbox.dataflash)@")
        state.formFields[FIELD.DATAFLASH] = form.addStaticText(line, nil, formatDataflashStatus(state))

        line = form.addLine("@i18n(app.modules.blackbox.sdcard)@")
        state.formFields[FIELD.SDCARD] = form.addStaticText(line, nil, formatSDCardStatus(state))
    end

    function node:wakeup()
        if state.needsInitialLoad == true then
            state.needsInitialLoad = false
            beginPoll(self, true)
            return
        end

        if os.clock() >= (state.pollAt or 0) then
            beginPoll(self, false)
        end

        if state.eraseInProgress == true and state.dataflash.ready == true then
            state.eraseInProgress = false
        end
    end

    function node:reload()
        beginPoll(self, true)
        return true
    end

    function node:tool()
        return diagnostics.openConfirmDialog("@i18n(app.modules.blackbox.name)@", "@i18n(app.modules.blackbox.erase_prompt)@", function()
            eraseDataflash(self)
        end)
    end

    function node:help()
        return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.blackbox.menu_status)@") .. " Help", STATUS_HELP)
    end

    function node:close()
        state.closed = true
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
