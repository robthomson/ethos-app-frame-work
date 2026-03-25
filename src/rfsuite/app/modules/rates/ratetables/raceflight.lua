return {
    name = "@i18n(app.modules.rates.raceflight)@",
    rows = {
        "@i18n(app.modules.rates.roll)@",
        "@i18n(app.modules.rates.pitch)@",
        "@i18n(app.modules.rates.yaw)@",
        "@i18n(app.modules.rates.collective)@"
    },
    cols = {
        "@i18n(app.modules.rates.rc_rate)@",
        "@i18n(app.modules.rates.acroplus)@",
        "@i18n(app.modules.rates.expo)@"
    },
    help = {
        "@i18n(app.modules.rates.help_table_2_p1)@",
        "@i18n(app.modules.rates.help_table_2_p2)@",
        "@i18n(app.modules.rates.help_table_2_p3)@"
    },
    fields = {
        {row = 1, col = 1, min = 0, max = 100, default = 24, mult = 10, step = 10, apikey = "rcRates_1"},
        {row = 2, col = 1, min = 0, max = 100, default = 24, mult = 10, step = 10, apikey = "rcRates_2"},
        {row = 3, col = 1, min = 0, max = 100, default = 40, mult = 10, step = 10, apikey = "rcRates_3"},
        {row = 4, col = 1, min = 0, max = 100, default = 50, decimals = 1, scale = 4, apikey = "rcRates_4"},
        {row = 1, col = 2, min = 0, max = 255, default = 0, apikey = "rates_1"},
        {row = 2, col = 2, min = 0, max = 255, default = 0, apikey = "rates_2"},
        {row = 3, col = 2, min = 0, max = 255, default = 0, apikey = "rates_3"},
        {row = 4, col = 2, min = 0, max = 255, default = 0, apikey = "rates_4"},
        {row = 1, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_1"},
        {row = 2, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_2"},
        {row = 3, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_3"},
        {row = 4, col = 3, min = 0, max = 100, default = 0, apikey = "rcExpo_4"}
    }
}
