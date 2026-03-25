return {
    title = "Rates",
    subtitle = "Configuration / Flight Tuning / Rates",
    items = {
        {id = "rates_table", title = "@i18n(app.modules.rates_advanced.table)@", subtitle = "Select rate table", kind = "page", path = "rates_advanced/tools/table.lua", image = "app/modules/rates_advanced/gfx/table.png"},
        {id = "rates_dynamics", title = "@i18n(app.modules.rates_advanced.advanced)@", subtitle = "Response and dynamic shaping", kind = "page", path = "rates_advanced/tools/advanced.lua", image = "app/modules/rates_advanced/gfx/advanced.png"},
        {id = "cyclic_behaviour", title = "@i18n(app.modules.rates_advanced.cyclic_behaviour)@", subtitle = "Cyclic ring and polarity", kind = "page", path = "rates_advanced/tools/cyclic_behaviour.lua", image = "app/modules/rates_advanced/gfx/cyclic_behaviour.png"}
    }
}
