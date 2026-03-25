return {
    title = "@i18n(app.modules.profile_governor.name)@",
    subtitle = "Configuration / Flight Tuning / Governor",
    items = {
        {id = "governor_general", title = "@i18n(app.modules.governor.menu_general)@", subtitle = "Governor gains and precomp", kind = "page", path = "profile_governor/tools/general.lua", image = "app/modules/profile_governor/gfx/general.png"},
        {id = "governor_flags", title = "@i18n(app.modules.governor.menu_flags)@", subtitle = "Governor behaviour options", kind = "page", path = "profile_governor/tools/flags.lua", image = "app/modules/profile_governor/gfx/flags.png", apiversiongte = {12, 0, 9}}
    }
}
