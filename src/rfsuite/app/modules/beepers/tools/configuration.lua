--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local lib = assert(loadfile("app/modules/beepers/lib.lua"))()

local Page = {}

function Page:open(ctx)
    local state = {
        cfg = {
            beeper_off_flags = 0,
            dshotBeaconTone = 1,
            dshotBeaconOffFlags = 0
        },
        controls = {},
        activeApi = nil,
        activeApiName = nil,
        loading = false,
        loaded = false,
        saving = false,
        error = nil,
        closed = false
    }
    local node = {
        baseTitle = ctx.item.title or "@i18n(app.modules.beepers.menu_configuration)@",
        title = ctx.item.title or "@i18n(app.modules.beepers.menu_configuration)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.beepers.name)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = true, tool = false, help = true},
        showLoaderOnEnter = true,
        loaderOnEnter = {
            kind = "progress",
            message = "@i18n(app.modules.beepers.loading)@",
            closeWhenIdle = false,
            watchdogTimeout = 8.0,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true
        },
        state = state
    }

    function node:buildForm(app)
        local line
        local control
        local index
        local def

        self.app = app
        state.controls = {}

        if state.error then
            line = form.addLine("@i18n(app.modules.beepers.status)@")
            form.addStaticText(line, nil, "Error")
            line = form.addLine("")
            form.addStaticText(line, {x = 8, y = app.radio.linePaddingTop or 0, w = math.max(40, app:_windowSize() - 16), h = app.radio.navbuttonHeight or 30}, tostring(state.error))
            return
        end

        for index = 1, #lib.CONFIG_FIELDS do
            def = lib.CONFIG_FIELDS[index]
            local currentDef = def
            line = form.addLine(def.label)
            control = form.addBooleanField(line, nil,
                function()
                    if state.loaded ~= true then
                        return nil
                    end
                    return lib.bitIsSet(state.cfg.beeper_off_flags, currentDef.bit) ~= true
                end,
                function(value)
                    state.cfg.beeper_off_flags = lib.setBit(state.cfg.beeper_off_flags, currentDef.bit, value ~= true)
                    app:setPageDirty(true)
                end)
            if control.enable then
                control:enable(state.loaded == true and state.saving ~= true)
            end
            state.controls[#state.controls + 1] = control
        end
    end

    function node:canSave()
        return state.loaded == true and state.loading ~= true and state.saving ~= true and state.error == nil
    end

    function node:reload()
        return lib.load(self, {
            message = "@i18n(app.modules.beepers.loading)@",
            watchdogTimeout = 8.0,
            uuid = "beepers-config-reload"
        })
    end

    function node:save()
        return lib.save(self, {
            message = "@i18n(app.modules.beepers.saving)@",
            watchdogTimeout = 10.0,
            uuid = "beepers-config-save"
        })
    end

    function node:help()
        return lib.openHelp(self.title or self.baseTitle)
    end

    function node:wakeup()
        if state.loaded ~= true and state.loading ~= true then
            if lib.loadSessionSnapshot(state, self.app) then
                state.loaded = true
                self.app.ui.clearProgressDialog(true)
                self.app:setPageDirty(false)
                self.app:_invalidateForm()
                return
            end
        end
        if state.loaded ~= true and state.loading ~= true then
            self:reload()
        end
    end

    function node:close()
        state.closed = true
        lib.cleanupActiveApi(state, self.app)
    end

    return node
end

return Page
