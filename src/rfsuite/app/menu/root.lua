--[[
  Split root menu registry.
  Keep this file small and move section contents into per-section files so the
  app only loads the root cards plus the currently open section.
]] --

return {
    title = "Rotorflight",
    headerTitle = "Configuration",
    subtitle = "Main Menu",
    items = {
        {
            id = "flight_tuning_menu",
            title = "Flight Tuning",
            subtitle = "PIDs, rates, governor and advanced",
            kind = "menu",
            source = "app/menu/menus/flight_tuning.lua",
            image = "app/gfx/flight_tuning.png",
            group = "configuration",
            groupTitle = "Configuration"
        },
        {
            id = "setup_menu",
            title = "Setup",
            subtitle = "Configuration, radio, telemetry and ports",
            kind = "menu",
            source = "app/menu/menus/setup.lua",
            image = "app/gfx/hardware.png",
            group = "configuration",
            groupTitle = "Configuration"
        },
        {
            id = "tools_menu",
            title = "Tools",
            subtitle = "Profiles and diagnostics",
            kind = "menu",
            source = "app/menu/menus/tools.lua",
            image = "app/gfx/tools.png",
            offline = true,
            group = "system",
            groupTitle = "System"
        },
        {
            id = "logs",
            title = "Logs",
            subtitle = "Flight logs and telemetry CSV",
            kind = "page",
            path = "logs/logs_dir.lua",
            image = "app/modules/logs/gfx/logs.png",
            offline = true,
            group = "system",
            groupTitle = "System",
            status = "Scaffold"
        },
        {
            id = "settings_admin",
            title = "Settings",
            subtitle = "General, shortcuts, dashboard and audio",
            kind = "menu",
            source = "app/menu/menus/settings_admin.lua",
            image = "app/modules/settings/settings.png",
            offline = true,
            group = "system",
            groupTitle = "System"
        },
        {
            id = "developer",
            title = "Developer",
            subtitle = "Developer tools",
            kind = "menu",
            source = "app/menu/menus/developer.lua",
            image = "app/modules/developer/developer.png",
            offline = true,
            developer = true,
            group = "system",
            groupTitle = "System"
        }
    }
}
