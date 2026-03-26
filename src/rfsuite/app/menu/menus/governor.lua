return {
    title = "@i18n(app.modules.governor.name)@",
    subtitle = "Configuration / Setup / Governor",
    items = {
        {id = "governor_general", title = "@i18n(app.modules.governor.menu_general)@", subtitle = "Governor mode and throttle behaviour", kind = "page", path = "governor/tools/general.lua", image = "app/modules/governor/gfx/general.png"},
        {id = "governor_time", title = "@i18n(app.modules.governor.menu_time)@", subtitle = "Governor ramp timing", kind = "page", path = "governor/tools/time.lua", image = "app/modules/governor/gfx/time.png"},
        {id = "governor_filters", title = "@i18n(app.modules.governor.menu_filters)@", subtitle = "Governor filter cutoffs", kind = "page", path = "governor/tools/filters.lua", image = "app/modules/governor/gfx/filters.png"},
        {id = "governor_curves", title = "@i18n(app.modules.governor.menu_curves)@", subtitle = "Bypass throttle curve", kind = "page", path = "governor/tools/curves.lua", image = "app/modules/governor/gfx/curves.png"}
    }
}
