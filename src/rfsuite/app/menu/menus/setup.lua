return {
    title = "Setup",
    subtitle = "Configuration / Setup",
    items = {
        {id = "configuration", title = "Configuration", subtitle = "Core flight configuration", loaderSpeed = 0.08, kind = "page", path = "configuration/configuration.lua", image = "app/modules/configuration/configuration.png"},
        {id = "radio_config", title = "Radio Config", subtitle = "Radio channel mapping", kind = "page", path = "radio_config/radio_config.lua", image = "app/modules/radio_config/radio_config.png"},
        {id = "telemetry", title = "Telemetry", subtitle = "Telemetry sensor setup", kind = "page", path = "telemetry/telemetry.lua", image = "app/modules/telemetry/telemetry.png"},
        {id = "accelerometer", title = "Accelerometer", subtitle = "Accelerometer calibration", loaderSpeed = 0.08, kind = "page", path = "accelerometer/accelerometer.lua", image = "app/modules/accelerometer/acc.png"},
        {id = "alignment", title = "Alignment", subtitle = "Sensor alignment", loaderSpeed = 0.08, kind = "page", path = "alignment/alignment.lua", image = "app/modules/alignment/alignment.png"},
        {id = "ports", title = "Ports", subtitle = "UART and feature ports", loaderSpeed = 0.08, kind = "page", path = "ports/ports.lua", image = "app/modules/ports/ports.png"},
        {id = "mixer", title = "Mixer", subtitle = "Mixer and layout", loaderSpeed = 0.08, kind = "menu", source = "app/menu/menus/mixer.lua", image = "app/modules/mixer/mixer.png"},
        {id = "controls", title = "@i18n(app.menu_section_controls)@", subtitle = "Modes, failsafe and logging", loaderSpeed = 0.08, kind = "menu", source = "app/menu/menus/safety_menu.lua", image = "app/modules/failsafe/failsafe.png"},
        {id = "power", title = "@i18n(app.modules.power.name)@", subtitle = "Battery and power setup", loaderSpeed = 0.08, kind = "menu", source = "app/menu/menus/power.lua", image = "app/modules/power/power.png"}
    }
}
