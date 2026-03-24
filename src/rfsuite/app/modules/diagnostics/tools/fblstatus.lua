--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()
local utils = require("lib.utils")

local POLL_INTERVAL = 2.0

local function u8(value)
    return math.floor(tonumber(value) or 0) % 256
end

local function highByte(value)
    return math.floor((tonumber(value) or 0) / 256) % 256
end

local function bitSet(value, bit)
    local n = tonumber(value) or 0
    local mask = 2 ^ bit

    return math.floor(n / mask) % 2 == 1
end

local function canPoll(node)
    local session = node.app.framework.session

    return diagnostics.isSimulation() == true or session:get("isConnected", false) == true
end

local function queueDirect(node, command, simulatorResponse, onReply)
    local mspTask = node.app.framework:getTask("msp")

    if not mspTask or not mspTask.queueCommand then
        return false
    end

    return mspTask:queueCommand(command, {}, {
        timeout = 1.5,
        simulatorResponse = simulatorResponse,
        onReply = function(_, buffer)
            if type(onReply) == "function" then
                onReply(buffer)
            end
        end
    })
end

local function updateFields(node)
    local state = node and node.state or nil
    local load

    if type(state) ~= "table" or state.closed == true then
        return
    end

    if state.status.fblYear and state.status.fblMonth and state.status.fblDay then
        diagnostics.setFieldText(state.fields.date, string.format("%04d-%02d-%02d", state.status.fblYear, state.status.fblMonth, state.status.fblDay))
    else
        diagnostics.setFieldText(state.fields.date, "-")
    end

    if state.status.fblHour and state.status.fblMinute and state.status.fblSecond then
        diagnostics.setFieldText(state.fields.time, string.format("%02d:%02d:%02d", state.status.fblHour, state.status.fblMinute, state.status.fblSecond))
    else
        diagnostics.setFieldText(state.fields.time, "-")
    end

    diagnostics.setFieldText(state.fields.arming, diagnostics.armingDisableFlagsToString(state.status.armingDisableFlags))

    if state.summary.supported == true then
        diagnostics.setFieldText(
            state.fields.dataflash,
            string.format("%.1f @i18n(app.modules.fblstatus.megabyte)@", math.max(0, (tonumber(state.summary.totalSize) or 0) - (tonumber(state.summary.usedSize) or 0)) / (1024 * 1024))
        )
    elseif state.summary.supported == false then
        diagnostics.setFieldText(state.fields.dataflash, "@i18n(app.modules.fblstatus.unsupported)@")
    else
        diagnostics.setFieldText(state.fields.dataflash, "-")
    end

    if state.status.realTimeLoad ~= nil then
        load = math.floor((tonumber(state.status.realTimeLoad) or 0) / 10)
        diagnostics.setFieldText(state.fields.realtime, tostring(load) .. "%", load >= 60 and RED or GREEN)
    else
        diagnostics.setFieldText(state.fields.realtime, "-")
    end

    if state.status.cpuLoad ~= nil then
        load = (tonumber(state.status.cpuLoad) or 0) / 10
        diagnostics.setFieldText(state.fields.cpu, string.format("%.1f%%", load), load >= 60 and RED or GREEN)
    else
        diagnostics.setFieldText(state.fields.cpu, "-")
    end
end

local function queuePoll(node)
    local mspTask = node.app.framework:getTask("msp")
    local helper = mspTask and mspTask.mspHelper or nil

    if not helper or not canPoll(node) then
        return false
    end

    queueDirect(node, 247, (function()
        local t = os.date("*t")
        local millis = math.floor((os.clock() % 1) * 1000)
        return {u8(t.year), highByte(t.year), t.month, t.day, t.hour, t.min, t.sec, u8(millis), highByte(millis)}
    end)(), function(buf)
        local state = node and node.state or nil

        if type(state) ~= "table" or state.closed == true then
            return
        end

        buf.offset = 1
        state.status.fblYear = helper.readU16(buf)
        buf.offset = 3
        state.status.fblMonth = helper.readU8(buf)
        state.status.fblDay = helper.readU8(buf)
        state.status.fblHour = helper.readU8(buf)
        state.status.fblMinute = helper.readU8(buf)
        state.status.fblSecond = helper.readU8(buf)
        state.status.fblMillis = helper.readU16(buf)
        updateFields(node)
    end)

    queueDirect(node, 101, {240, 1, 124, 0, 35, 0, 0, 0, 0, 0, 0, 224, 1, 10, 1, 0, 26, 0, 0, 0, 0, 0, 2, 0, 6, 0, 6, 1, 4, 1}, function(buf)
        local state = node and node.state or nil

        if type(state) ~= "table" or state.closed == true then
            return
        end

        buf.offset = 12
        state.status.realTimeLoad = helper.readU16(buf)
        state.status.cpuLoad = helper.readU16(buf)
        buf.offset = 18
        state.status.armingDisableFlags = helper.readU32(buf)
        updateFields(node)
    end)

    queueDirect(node, 70, {3, 1, 0, 0, 0, 0, 4, 0, 0, 0, 3, 0, 0}, function(buf)
        local state = node and node.state or nil
        local flags = helper.readU8(buf)

        if type(state) ~= "table" or state.closed == true then
            return
        end

        state.summary.ready = bitSet(flags, 0)
        state.summary.supported = bitSet(flags, 1)
        state.summary.sectors = helper.readU32(buf)
        state.summary.totalSize = helper.readU32(buf)
        state.summary.usedSize = helper.readU32(buf)
        updateFields(node)
    end)

    return true
end

local function eraseDataflash(node)
    local state = node.state

    node.app.ui.showLoader({
        kind = "progress",
        title = "@i18n(app.modules.fblstatus.erasing)@",
        message = "@i18n(app.modules.fblstatus.erasing_dataflash)@",
        closeWhenIdle = false,
        modal = true
    })

    if queueDirect(node, 72, {}, function()
        if state.closed == true then
            return
        end
        state.summary = {}
        state.status = {}
        updateFields(node)
        state.nextPollAt = 0
        if node.app and node.app.ui and node.app.ui.clearProgressDialog then
            node.app.ui.clearProgressDialog(true)
        end
    end) ~= true then
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog("@i18n(app.modules.fblstatus.name)@", "@i18n(app.modules.fblstatus.erase_failed)@")
    end
end

function Page:open(ctx)
    local state = {
        fields = {},
        status = {},
        summary = {},
        nextPollAt = 0,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.fblstatus.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.fblstatus.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = {enabled = true, text = "*"}, help = false},
        state = state
    }

    function node:buildForm(app)
        local function addLine(label, key)
            local line = form.addLine(label)
            state.fields[key] = form.addStaticText(line, diagnostics.valuePos(app, 200), "-")
        end

        self.app = app
        addLine("@i18n(app.modules.fblstatus.fbl_date)@", "date")
        addLine("@i18n(app.modules.fblstatus.fbl_time)@", "time")
        addLine("@i18n(app.modules.fblstatus.arming_flags)@", "arming")
        addLine("@i18n(app.modules.fblstatus.dataflash_free_space)@", "dataflash")
        addLine("@i18n(app.modules.fblstatus.real_time_load)@", "realtime")
        addLine("@i18n(app.modules.fblstatus.cpu_load)@", "cpu")
        updateFields(self)
    end

    function node:wakeup()
        local now = os.clock()
        local mspTask = self.app.framework:getTask("msp")

        if now < (state.nextPollAt or 0) then
            return
        end

        if not canPoll(self) then
            return
        end

        if mspTask and mspTask.mspQueue and mspTask.mspQueue.isProcessed and mspTask.mspQueue:isProcessed() == true then
            state.nextPollAt = now + POLL_INTERVAL
            queuePoll(self)
        end
    end

    function node:reload()
        state.nextPollAt = 0
        return true
    end

    function node:onToolMenu()
        return diagnostics.openConfirmDialog("@i18n(app.modules.fblstatus.erase)@", "@i18n(app.modules.fblstatus.erase_prompt)@", function()
            eraseDataflash(node)
        end)
    end

    function node:close()
        state.closed = true
        state.nextPollAt = math.huge
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
        state.fields = {}
    end

    return node
end

return Page
