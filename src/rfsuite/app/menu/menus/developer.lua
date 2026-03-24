return {
    title = "@i18n(app.modules.settings.txt_developer)@",
    subtitle = "@i18n(app.modules.settings.system_developer)@",
    items = {
        {id = "msp_speed", title = "@i18n(app.modules.msp_speed.name)@", subtitle = "@i18n(app.modules.msp_speed.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "developer/tools/msp_speed.lua", image = "app/modules/developer/gfx/msp_speed.png"},
        {id = "api_tester", title = "@i18n(app.modules.api_tester.name)@", subtitle = "@i18n(app.modules.api_tester.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "developer/tools/api_tester.lua", image = "app/modules/developer/gfx/api_tester.png"},
        {id = "msp_exp", title = "@i18n(app.modules.msp_exp.name)@", subtitle = "@i18n(app.modules.msp_exp.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "developer/tools/msp_exp.lua", image = "app/modules/developer/gfx/msp_exp.png"},
        {id = "development", title = "@i18n(app.modules.settings.name)@", subtitle = "@i18n(app.modules.settings.developer_settings)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/development.lua", image = "app/modules/developer/gfx/settings.png", offline = true}
    }
}
