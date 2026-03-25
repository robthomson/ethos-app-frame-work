return {
    title = "@i18n(app.modules.beepers.name)@",
    subtitle = "Configuration / Setup / Controls / Beepers",
    items = {
        {id = "beepers_configuration", title = "@i18n(app.modules.beepers.menu_configuration)@", subtitle = "General beeper conditions", loaderSpeed = 0.08, kind = "page", path = "beepers/tools/configuration.lua", image = "app/modules/beepers/gfx/configuration.png"},
        {id = "beepers_dshot", title = "@i18n(app.modules.beepers.menu_dshot)@", subtitle = "DShot beeper settings", loaderSpeed = 0.08, kind = "page", path = "beepers/tools/dshot.lua", image = "app/modules/beepers/gfx/dshot.png"}
    }
}
