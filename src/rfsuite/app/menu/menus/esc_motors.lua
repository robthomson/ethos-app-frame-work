return {
    title = "@i18n(app.modules.esc_motors.name)@",
    subtitle = "Configuration / Setup / ESC & Motors",
    items = {
        {
            id = "esc_motors_throttle",
            title = "@i18n(app.modules.esc_motors.throttle)@",
            subtitle = "@i18n(app.modules.esc_motors.name)@",
            kind = "page",
            path = "esc_motors/tools/throttle.lua",
            image = "app/modules/esc_motors/gfx/throttle.png"
        },
        {
            id = "esc_motors_telemetry",
            title = "@i18n(app.modules.esc_motors.telemetry)@",
            subtitle = "@i18n(app.modules.esc_motors.name)@",
            kind = "page",
            path = "esc_motors/tools/telemetry.lua",
            image = "app/modules/esc_motors/gfx/telemetry.png"
        },
        {
            id = "esc_motors_rpm",
            title = "@i18n(app.modules.esc_motors.rpm)@",
            subtitle = "@i18n(app.modules.esc_motors.name)@",
            kind = "page",
            path = "esc_motors/tools/rpm.lua",
            image = "app/modules/esc_motors/gfx/rpm.png"
        },
        {
            id = "esc_programming",
            title = "@i18n(app.modules.esc_tools.name)@",
            subtitle = "@i18n(app.modules.esc_motors.name)@",
            kind = "page",
            path = "esc_tools/tools/esc.lua",
            image = "app/modules/esc_tools/esc.png"
        }
    }
}
