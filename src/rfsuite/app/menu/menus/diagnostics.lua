return {
    title = "@i18n(app.modules.diagnostics.name)@",
    subtitle = "@i18n(app.modules.diagnostics.subtitle)@",
    items = {
        {id = "rfstatus", title = "@i18n(app.modules.rfstatus.menu_name)@", subtitle = "@i18n(app.modules.rfstatus.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/rfstatus.lua", image = "app/modules/diagnostics/gfx/rfstatus.png"},
        {id = "sensors", title = "@i18n(app.modules.validate_sensors.name)@", subtitle = "@i18n(app.modules.validate_sensors.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/sensors.lua", image = "app/modules/diagnostics/gfx/sensors.png", offline = true},
        {id = "info", title = "@i18n(app.modules.info.name)@", subtitle = "@i18n(app.modules.info.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/info.lua", image = "app/modules/diagnostics/gfx/info.png", offline = true},
        {id = "fblstatus", title = "@i18n(app.modules.fblstatus.name)@", subtitle = "@i18n(app.modules.fblstatus.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/fblstatus.lua", image = "app/modules/diagnostics/gfx/fblstatus.png"},
        {id = "fblsensors", title = "@i18n(app.modules.fblsensors.name)@", subtitle = "@i18n(app.modules.fblsensors.subtitle)@", loaderSpeed = 0.08, kind = "page", path = "diagnostics/tools/fblsensors.lua", image = "app/modules/diagnostics/gfx/fblsensors.png"}
    }
}
