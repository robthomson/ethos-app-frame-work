--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local diagnostics = assert(loadfile("app/modules/diagnostics/lib.lua"))()

local COPY_HELP = {
    "@i18n(app.modules.copyprofiles.help_p1)@",
    "@i18n(app.modules.copyprofiles.help_p2)@"
}

local PROFILE_TYPE_CHOICES = {
    {"@i18n(app.modules.copyprofiles.profile_type_pid)@", 1},
    {"@i18n(app.modules.copyprofiles.profile_type_rate)@", 2}
}

local PROFILE_CHOICES = {
    {"1", 1},
    {"2", 2},
    {"3", 3},
    {"4", 4},
    {"5", 5},
    {"6", 6}
}

local function performCopy(node)
    local state = node.state
    local mspTask = node.app.framework:getTask("msp")
    local payload
    local ok

    if state.copyInFlight == true then
        return true
    end

    if state.sourceProfile == state.destProfile then
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.copyprofiles.name)@", "@i18n(app.modules.copyprofiles.same_profile)@")
        return false
    end

    payload = {
        math.max(0, (tonumber(state.profileType) or 1) - 1),
        math.max(0, (tonumber(state.destProfile) or 1) - 1),
        math.max(0, (tonumber(state.sourceProfile) or 1) - 1)
    }

    node.app.ui.showLoader({
        kind = "save",
        title = node.title or "@i18n(app.modules.copyprofiles.name)@",
        message = "@i18n(app.modules.copyprofiles.msgbox_msg)@",
        closeWhenIdle = false,
        modal = true
    })

    state.copyInFlight = true

    ok = mspTask and mspTask.queueCommand and mspTask:queueCommand(183, payload, {
        timeout = 1.5,
        simulatorResponse = {},
        onReply = function()
            if state.closed == true then
                return
            end
            state.copyInFlight = false
            node.app.ui.clearProgressDialog(true)
        end,
        onError = function()
            if state.closed == true then
                return
            end
            state.copyInFlight = false
            node.app.ui.clearProgressDialog(true)
            diagnostics.openMessageDialog(node.title or "@i18n(app.modules.copyprofiles.name)@", "@i18n(app.modules.copyprofiles.copy_failed)@")
        end
    })

    if ok ~= true then
        state.copyInFlight = false
        node.app.ui.clearProgressDialog(true)
        diagnostics.openMessageDialog(node.title or "@i18n(app.modules.copyprofiles.name)@", "@i18n(app.modules.copyprofiles.copy_failed)@")
        return false
    end

    return true
end

function Page:open(ctx)
    local state = {
        profileType = 1,
        sourceProfile = 1,
        destProfile = 2,
        copyInFlight = false,
        closed = false
    }
    local node = {
        title = ctx.item.title or "@i18n(app.modules.copyprofiles.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.copyprofiles.subtitle)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = true, reload = false, tool = false, help = true},
        state = state
    }

    function node:buildForm(app)
        self.app = app

        form.addChoiceField(form.addLine("@i18n(app.modules.copyprofiles.profile_type)@"), nil, PROFILE_TYPE_CHOICES,
            function()
                return state.profileType
            end,
            function(newValue)
                state.profileType = tonumber(newValue) or 1
            end)

        form.addChoiceField(form.addLine("@i18n(app.modules.copyprofiles.source_profile)@"), nil, PROFILE_CHOICES,
            function()
                return state.sourceProfile
            end,
            function(newValue)
                state.sourceProfile = tonumber(newValue) or 1
            end)

        form.addChoiceField(form.addLine("@i18n(app.modules.copyprofiles.dest_profile)@"), nil, PROFILE_CHOICES,
            function()
                return state.destProfile
            end,
            function(newValue)
                state.destProfile = tonumber(newValue) or 1
            end)
    end

    function node:save()
        return diagnostics.openConfirmDialog(
            node.title or "@i18n(app.modules.copyprofiles.name)@",
            "@i18n(app.modules.copyprofiles.msgbox_msg)@",
            function()
                performCopy(node)
            end
        )
    end

    function node:help()
        return diagnostics.openHelpDialog((self.title or "@i18n(app.modules.copyprofiles.name)@") .. " Help", COPY_HELP)
    end

    function node:close()
        state.closed = true
        state.copyInFlight = false
        if self.app and self.app.ui and self.app.ui.clearProgressDialog then
            self.app.ui.clearProgressDialog(true)
        end
    end

    return node
end

return Page
