return {
    title = "Flight Tuning",
    subtitle = "Configuration / Flight Tuning",
    items = {
        {id = "pids", title = "PIDs", subtitle = "Primary PID tuning", kind = "page", path = "pids/pids.lua", image = "app/modules/pids/pids.png"},
        {id = "rates", title = "Rates", subtitle = "Rates and expo", kind = "page", path = "rates/rates.lua", image = "app/modules/rates/rates.png"},
        {id = "governor", title = "Governor", subtitle = "Governor profile tuning", kind = "page", path = "profile_governor/governor.lua", image = "app/modules/profile_governor/governor.png"},
        {id = "advanced_menu", title = "Advanced", subtitle = "Advanced tuning pages", kind = "menu", source = "app/menu/menus/advanced.lua", image = "app/gfx/advanced.png"}
    }
}
