return {
    title = "@i18n(app.modules.settings.name)@",
    subtitle = "@i18n(app.modules.settings.system_settings)@",
    items = {
        {id = "general", title = "@i18n(app.modules.settings.txt_general)@", subtitle = "@i18n(app.modules.settings.general_settings)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/general.lua", image = "app/modules/settings/gfx/general.png", offline = true},
        {id = "shortcuts", title = "@i18n(app.modules.settings.shortcuts)@", subtitle = "@i18n(app.modules.settings.shortcuts_preferences)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/shortcuts.lua", image = "app/modules/settings/gfx/shortcuts.png", offline = true},
        {id = "dashboard", title = "@i18n(app.modules.settings.dashboard)@", subtitle = "@i18n(app.modules.settings.dashboard_configuration)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/dashboard.lua", image = "app/modules/settings/gfx/dashboard.png", offline = true},
        {id = "localizations", title = "@i18n(app.modules.settings.localizations_title)@", subtitle = "@i18n(app.modules.settings.language_localization)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/localizations.lua", image = "app/modules/settings/gfx/localizations.png", offline = true},
        {id = "audio", title = "@i18n(app.modules.settings.audio)@", subtitle = "@i18n(app.modules.settings.audio_preferences)@", loaderSpeed = 0.08, kind = "page", path = "settings/tools/audio.lua", image = "app/modules/settings/gfx/audio.png", offline = true}
    }
}
