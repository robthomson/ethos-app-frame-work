return {
    name = "@i18n(app.modules.rates.betaflight)@",
    rows = {
        "@i18n(app.modules.rates.roll)@",
        "@i18n(app.modules.rates.pitch)@",
        "@i18n(app.modules.rates.yaw)@",
        "@i18n(app.modules.rates.collective)@"
    },
    cols = {
        "@i18n(app.modules.rates.rc_rate)@",
        "@i18n(app.modules.rates.superrate)@",
        "@i18n(app.modules.rates.expo)@"
    },
    help = {
        "@i18n(app.modules.rates.help_table_1_p1)@",
        "@i18n(app.modules.rates.help_table_1_p2)@",
        "@i18n(app.modules.rates.help_table_1_p3)@"
    },
    fields = {
        {row = 1, col = 1, min = 0, max = 255, default = 120, decimals = 2, scale = 100, apikey = "rcRates_1"},
        {row = 2, col = 1, min = 0, max = 255, default = 120, decimals = 2, scale = 100, apikey = "rcRates_2"},
        {row = 3, col = 1, min = 0, max = 255, default = 200, decimals = 2, scale = 100, apikey = "rcRates_3"},
        {row = 4, col = 1, min = 0, max = 220, default = 203, decimals = 2, scale = 100, apikey = "rcRates_4"},
        {row = 1, col = 2, min = 0, max = 99, default = 0, decimals = 2, scale = 100, apikey = "rates_1"},
        {row = 2, col = 2, min = 0, max = 99, default = 0, decimals = 2, scale = 100, apikey = "rates_2"},
        {row = 3, col = 2, min = 0, max = 99, default = 0, decimals = 2, scale = 100, apikey = "rates_3"},
        {row = 4, col = 2, min = 0, max = 99, default = 1, decimals = 2, scale = 100, apikey = "rates_4"},
        {row = 1, col = 3, min = 0, max = 100, default = 0, decimals = 2, scale = 100, apikey = "rcExpo_1"},
        {row = 2, col = 3, min = 0, max = 100, default = 0, decimals = 2, scale = 100, apikey = "rcExpo_2"},
        {row = 3, col = 3, min = 0, max = 100, default = 0, decimals = 2, scale = 100, apikey = "rcExpo_3"},
        {row = 4, col = 3, min = 0, max = 100, default = 0, decimals = 2, scale = 100, apikey = "rcExpo_4"}
    }
}
