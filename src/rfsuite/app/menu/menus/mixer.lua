return {
    title = "Mixer",
    subtitle = "Configuration / Setup / Mixer",
    items = {
        {id = "mixer_swash", title = "Swash", subtitle = "Swash type and directions", kind = "page", path = "mixer/tools/swash.lua", image = "app/modules/mixer/gfx/swash.png", apiversiongte = {12, 0, 9}},
        {id = "mixer_geometry", title = "@i18n(app.modules.mixer.geometry)@", subtitle = "Swash geometry and setup", kind = "page", path = "mixer/tools/geometry.lua", image = "app/modules/mixer/gfx/geometry.png", apiversiongte = {12, 0, 9}},
        {id = "mixer_tail", title = "Tail", subtitle = "Tail mode and yaw setup", kind = "page", path = "mixer/tools/tail.lua", image = "app/modules/mixer/gfx/tail.png", apiversiongte = {12, 0, 9}},
        {id = "mixer_trims", title = "@i18n(app.modules.mixer.trims)@", subtitle = "Mixer trims", kind = "page", path = "mixer/tools/trims.lua", image = "app/modules/mixer/gfx/trims.png", apiversiongte = {12, 0, 9}}
    }
}
