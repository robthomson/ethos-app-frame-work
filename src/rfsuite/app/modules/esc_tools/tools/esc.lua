--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local escTools = assert(loadfile("app/modules/esc_tools/lib.lua"))()

local Page = {}

function Page:open(ctx)
    local state = {
        closed = false,
        icons = {}
    }

    local node = {
        app = ctx.app,
        baseTitle = ctx.item.title or "@i18n(app.modules.esc_tools.name)@",
        title = ctx.item.title or "@i18n(app.modules.esc_tools.name)@",
        subtitle = ctx.item.subtitle or "@i18n(app.modules.esc_motors.name)@",
        breadcrumb = ctx.breadcrumb,
        navButtons = {
            menu = true,
            save = false,
            reload = false,
            tool = false,
            help = false
        },
        state = state
    }

    function node:buildForm(app)
        escTools.renderGrid(self, app, {{
            title = "@i18n(app.modules.esc_tools.mfg.omp.name)@",
            image = "app/modules/esc_tools/mfg/omp/omp.png",
            press = function()
                app:_enterItem(1, {
                    id = "esc-tool-omp",
                    kind = "page",
                    path = "esc_tools/mfg/omp/tool.lua",
                    title = "@i18n(app.modules.esc_tools.mfg.omp.name)@",
                    subtitle = self.baseTitle
                })
            end
        }})
    end

    function node:wakeup()
    end

    function node:close()
        state.closed = true
    end

    return node
end

return Page
