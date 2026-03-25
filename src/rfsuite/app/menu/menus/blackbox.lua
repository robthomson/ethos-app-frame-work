return {
    title = "@i18n(app.modules.blackbox.name)@",
    subtitle = "Configuration / Setup / Controls / Blackbox",
    items = {
        {id = "blackbox_status", title = "@i18n(app.modules.blackbox.menu_status)@", subtitle = "@i18n(app.modules.blackbox.name)@", loaderSpeed = 0.08, kind = "page", path = "blackbox/tools/status.lua", image = "app/modules/blackbox/gfx/status.png"},
        {id = "blackbox_logging", title = "@i18n(app.modules.blackbox.menu_logging)@", subtitle = "@i18n(app.modules.blackbox.name)@", loaderSpeed = 0.08, kind = "page", path = "blackbox/tools/logging.lua", image = "app/modules/blackbox/gfx/logging.png"},
        {id = "blackbox_configuration", title = "@i18n(app.modules.blackbox.menu_configuration)@", subtitle = "@i18n(app.modules.blackbox.name)@", loaderSpeed = 0.08, kind = "page", path = "blackbox/tools/configuration.lua", image = "app/modules/blackbox/gfx/configuration.png"}
    }
}
