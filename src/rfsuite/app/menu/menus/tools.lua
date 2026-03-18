return {
    title = "Tools",
    subtitle = "System / Tools",
    items = {
        {id = "copyprofiles", title = "Copy Profiles", subtitle = "Disabled in original manifest", kind = "page", path = "copyprofiles/copyprofiles.lua", status = "Disabled", disabled = true, image = "app/modules/copyprofiles/copy.png"},
        {id = "profile_select", title = "Profile Select", subtitle = "Switch active profiles", kind = "page", path = "profile_select/select_profile.lua", image = "app/modules/profile_select/select_profile.png"},
        {id = "diagnostics", title = "Diagnostics", subtitle = "Transport and sensor diagnostics", kind = "menu", source = "app/menu/menus/diagnostics.lua", image = "app/modules/diagnostics/diagnostics.png"}
    }
}
