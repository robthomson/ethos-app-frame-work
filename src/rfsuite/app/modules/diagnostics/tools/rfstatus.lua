--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()

local UPDATE_INTERVAL = 0.5

function Page:open(ctx)
    local state = {
        fields = {},
        lastUpdateAt = 0
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.rfstatus.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.rfstatus.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = false},
        state = state
    }

    function node:refresh(force)
        local now = os.clock()
        local session = self.app.framework.session
        local telemetry = self.app.framework:getTask("telemetry")
        local bg = diagnostics.backgroundState()
        local cpuLoad = diagnostics.approxCpuLoad(self.app)
        local freeMemory = diagnostics.systemMemoryFreeKB()
        local invalidSensors = nil

        if force ~= true and (now - (state.lastUpdateAt or 0)) < UPDATE_INTERVAL then
            return
        end
        state.lastUpdateAt = now

        if cpuLoad ~= nil then
            diagnostics.setFieldText(state.fields.cpu, string.format("%.1f%%", cpuLoad))
        else
            diagnostics.setFieldText(state.fields.cpu, "-")
        end

        if freeMemory ~= nil then
            diagnostics.setFieldText(state.fields.memory, string.format("%.1f kB", freeMemory))
        else
            diagnostics.setFieldText(state.fields.memory, "-")
        end

        diagnostics.setStatusField(state.fields.background, bg.healthy == true and true or (bg.state == "waiting" and nil or false), true)
        diagnostics.setStatusField(state.fields.module, diagnostics.moduleEnabled())
        diagnostics.setStatusField(state.fields.msp, diagnostics.haveMspSensor())

        if telemetry and telemetry.active and telemetry.active() then
            invalidSensors = telemetry.validateSensors and telemetry.validateSensors(false) or nil
            diagnostics.setStatusField(state.fields.telemetry, type(invalidSensors) == "table" and #invalidSensors == 0 or nil, true)
        else
            diagnostics.setStatusField(state.fields.telemetry, nil, true)
        end

        diagnostics.setStatusField(state.fields.connected, session:get("isConnected", false), true)
        if session:get("apiVersion", nil) ~= nil then
            diagnostics.setStatusField(state.fields.api, session:get("apiVersionInvalid", false) ~= true)
        else
            diagnostics.setStatusField(state.fields.api, nil, true)
        end
    end

    function node:buildForm(app)
        local function addLine(label, key)
            local line = form.addLine(label)
            state.fields[key] = form.addStaticText(line, diagnostics.valuePos(app, 150), "-")
        end

        self.app = app
        addLine("@i18n(app.modules.fblstatus.cpu_load)@", "cpu")
        addLine("@i18n(app.modules.msp_speed.memory_free)@", "memory")
        addLine("@i18n(app.modules.rfstatus.bgtask)@", "background")
        addLine("@i18n(app.modules.rfstatus.rfmodule)@", "module")
        addLine("@i18n(app.modules.rfstatus.mspsensor)@", "msp")
        addLine("@i18n(app.modules.rfstatus.telemetrysensors)@", "telemetry")
        addLine("@i18n(app.modules.rfstatus.fblconnected)@", "connected")
        addLine("@i18n(app.modules.rfstatus.apiversion)@", "api")
        self:refresh(true)
    end

    function node:wakeup()
        self:refresh(false)
    end

    return node
end

return Page
