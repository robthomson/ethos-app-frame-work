return {
    title = "@i18n(app.menu_section_controls)@",
    subtitle = "Configuration / Setup / Controls",
    items = {
        {id = "modes", title = "@i18n(app.modules.modes.name)@", subtitle = "Mode ranges", loaderSpeed = 0.05, kind = "page", path = "modes/modes.lua", image = "app/modules/modes/modes.png"},
        {id = "adjustments", title = "@i18n(app.modules.adjustments.name)@", subtitle = "Adjustment ranges", loaderSpeed = 0.10, kind = "page", path = "adjustments/adjustments.lua", image = "app/modules/adjustments/adjustments.png"},
        {id = "failsafe", title = "@i18n(app.modules.failsafe.name)@", subtitle = "Receiver loss behavior", loaderSpeed = 0.08, kind = "page", path = "failsafe/failsafe.lua", image = "app/modules/failsafe/failsafe.png"},
        {id = "beepers", title = "@i18n(app.modules.beepers.name)@", subtitle = "Beeper options", loaderSpeed = 0.08, kind = "menu", source = "app/menu/menus/beepers.lua", image = "app/modules/beepers/beepers.png"},
        {id = "stats", title = "@i18n(app.modules.stats.name)@", subtitle = "Flight statistics", loaderSpeed = 0.08, kind = "page", path = "stats/stats.lua", image = "app/modules/stats/stats.png"},
        {id = "blackbox", title = "@i18n(app.modules.blackbox.name)@", subtitle = "Logging and media", loaderSpeed = 0.08, kind = "menu", source = "app/menu/menus/blackbox.lua", image = "app/modules/blackbox/blackbox.png"}
    }
}
