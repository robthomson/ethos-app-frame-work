--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()

local UPDATE_INTERVAL = 0.5

local function transportLabel(value)
    local labels = {
        crsf = "@i18n(app.modules.info.transport_crsf)@",
        sport = "@i18n(app.modules.info.transport_sport)@",
        sim = "@i18n(app.modules.info.transport_sim)@",
        disconnected = "@i18n(app.modules.info.transport_disconnected)@"
    }

    return labels[tostring(value or "disconnected")] or string.upper(tostring(value or "disconnected"))
end

function Page:open(ctx)
    local state = {
        fields = {},
        lastUpdateAt = 0
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.info.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.info.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = false},
        state = state
    }

    function node:refresh(force)
        local now = os.clock()
        local session = self.app.framework.session

        if force ~= true and (now - (state.lastUpdateAt or 0)) < UPDATE_INTERVAL then
            return
        end
        state.lastUpdateAt = now

        diagnostics.setFieldText(state.fields.version, diagnostics.runtimeVersion())
        diagnostics.setFieldText(state.fields.ethos, diagnostics.ethosVersionString())
        diagnostics.setFieldText(state.fields.rf, diagnostics.formatVersion(session:get("rfVersion", nil)))
        diagnostics.setFieldText(state.fields.fc, diagnostics.formatVersion(session:get("fcVersion", nil)))
        diagnostics.setFieldText(state.fields.msp, diagnostics.formatVersion(session:get("apiVersion", nil)))
        diagnostics.setFieldText(state.fields.transport, transportLabel(session:get("connectionTransport", "disconnected")))
        diagnostics.setFieldText(state.fields.supported, diagnostics.supportedMspVersions(self.app))
        diagnostics.setFieldText(state.fields.simulation, diagnostics.isSimulation() and "@i18n(app.modules.info.value_on)@" or "@i18n(app.modules.info.value_off)@")
    end

    function node:buildForm(app)
        local function addLine(label, key)
            local line = form.addLine(label)
            state.fields[key] = form.addStaticText(line, diagnostics.valuePos(app, 220), "-")
        end

        self.app = app
        addLine("@i18n(app.modules.info.version)@", "version")
        addLine("@i18n(app.modules.info.ethos_version)@", "ethos")
        addLine("@i18n(app.modules.info.rf_version)@", "rf")
        addLine("@i18n(app.modules.info.fc_version)@", "fc")
        addLine("@i18n(app.modules.info.msp_version)@", "msp")
        addLine("@i18n(app.modules.info.msp_transport)@", "transport")
        addLine("@i18n(app.modules.info.supported_versions)@", "supported")
        addLine("@i18n(app.modules.info.simulation)@", "simulation")
        self:refresh(true)
    end

    function node:wakeup()
        self:refresh(false)
    end

    return node
end

return Page
