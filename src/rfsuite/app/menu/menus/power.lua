return {
    title = "@i18n(app.modules.power.name)@",
    subtitle = "Configuration / Setup / Power",
    items = {
        {id = "power_battery", title = "@i18n(app.modules.power.battery_name)@", subtitle = "@i18n(app.modules.power.name)@", loaderSpeed = 0.08, kind = "page", path = "power/tools/battery.lua", image = "app/modules/power/gfx/battery.png"},
        {id = "power_alerts", title = "@i18n(app.modules.power.alert_name)@", subtitle = "@i18n(app.modules.power.name)@", loaderSpeed = 0.08, kind = "page", path = "power/tools/alerts.lua", image = "app/modules/power/gfx/alerts.png"},
        {id = "power_source", title = "@i18n(app.modules.power.source_name)@", subtitle = "@i18n(app.modules.power.name)@", loaderSpeed = 0.08, kind = "page", path = "power/tools/source.lua", image = "app/modules/power/gfx/source.png"},
        {id = "power_preferences", title = "@i18n(app.modules.power.preferences_name)@", subtitle = "@i18n(app.modules.power.name)@", loaderSpeed = 0.08, kind = "page", path = "power/tools/preferences.lua", image = "app/modules/power/gfx/preferences.png"}
    }
}
