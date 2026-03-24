return {
    title = "Tools",
    subtitle = "System / Tools",
    items = {
        {id = "copyprofiles", title = "@i18n(app.modules.copyprofiles.name)@", subtitle = "@i18n(app.modules.copyprofiles.subtitle)@", kind = "page", path = "copyprofiles/copyprofiles.lua", image = "app/modules/copyprofiles/copy.png"},
        {id = "profile_select", title = "@i18n(app.modules.profile_select.name)@", subtitle = "@i18n(app.modules.profile_select.subtitle)@", kind = "page", path = "profile_select/select_profile.lua", image = "app/modules/profile_select/select_profile.png"},
        {id = "diagnostics", title = "@i18n(app.modules.diagnostics.name)@", subtitle = "@i18n(app.modules.diagnostics.subtitle)@", kind = "menu", source = "app/menu/menus/diagnostics.lua", image = "app/modules/diagnostics/diagnostics.png", offline = true}
    }
}
