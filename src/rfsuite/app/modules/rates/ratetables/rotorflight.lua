return {
    name = "@i18n(app.modules.rates.rotorflight)@",
    rows = {
        "@i18n(app.modules.rates.roll)@",
        "@i18n(app.modules.rates.pitch)@",
        "@i18n(app.modules.rates.yaw)@",
        "@i18n(app.modules.rates.collective)@"
    },
    cols = {
        "@i18n(app.modules.rates.rate)@",
        "@i18n(app.modules.rates.shape)@",
        "@i18n(app.modules.rates.expo)@"
    },
    help = {
        "@i18n(app.modules.rates.help_table_6_p1)@",
        "@i18n(app.modules.rates.help_table_6_p2)@",
        "@i18n(app.modules.rates.help_table_6_p3)@"
    },
    fields = {
        {row = 1, col = 1, min = 0, max = 100, default = 49, mult = 5, step = 5, apikey = "rcRates_1"},
        {row = 2, col = 1, min = 0, max = 100, default = 48, mult = 5, step = 5, apikey = "rcRates_2"},
        {row = 3, col = 1, min = 0, max = 200, default = 25, mult = 5, step = 5, apikey = "rcRates_3"},
        {row = 4, col = 1, min = 0, max = 200, default = 50, mult = 5, decimals = 2, step = 10, scale = 40, apikey = "rcRates_4"},
        {row = 1, col = 2, min = 0, max = 127, default = 12, mult = 1, step = 1, apikey = "rates_1"},
        {row = 2, col = 2, min = 0, max = 127, default = 12, mult = 1, step = 1, apikey = "rates_2"},
        {row = 3, col = 2, min = 0, max = 127, default = 12, mult = 1, step = 1, apikey = "rates_3"},
        {row = 4, col = 2, min = 0, max = 127, default = 12, mult = 1, step = 1, apikey = "rates_4"},
        {row = 1, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_1"},
        {row = 2, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_2"},
        {row = 3, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_3"},
        {row = 4, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_4"}
    }
}
