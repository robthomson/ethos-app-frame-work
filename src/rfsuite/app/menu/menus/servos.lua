return {
    title = "@i18n(app.modules.servos.name)@",
    subtitle = "Configuration / Setup / Servos",
    items = {
        {id = "servos_pwm", title = "@i18n(app.modules.servos.pwm)@", subtitle = "@i18n(app.modules.servos.name)@", loaderSpeed = 0.08, kind = "page", path = "servos/tools/pwm.lua", image = "app/modules/servos/gfx/pwm.png"},
        {id = "servos_bus", title = "@i18n(app.modules.servos.bus)@", subtitle = "@i18n(app.modules.servos.name)@", loaderSpeed = 0.08, kind = "page", path = "servos/tools/bus.lua", image = "app/modules/servos/gfx/bus.png"}
    }
}
