--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local profile = {}

local PAGE_LAYOUTS = {
    basic = {
        labels = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.esc)@", label = "esc1", inline_size = 40.6},
            {t = "", label = "esc2", inline_size = 40.6},
            {t = "", label = "esc3", inline_size = 40.6},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.limits)@", label = "limits1", inline_size = 40.6},
            {t = "", label = "limits2", inline_size = 40.6},
            {t = "", label = "limits3", inline_size = 40.6}
        },
        fields = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.flight_mode)@", inline = 1, label = "esc1", type = 1, apikey = "flight_mode"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.rotation)@", inline = 1, label = "esc2", type = 1, apikey = "rotation"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.bec_voltage)@", inline = 1, label = "esc3", type = 1, apikey = "bec_voltage"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.lipo_cell_count)@", inline = 1, label = "limits1", type = 1, apikey = "lipo_cell_count"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.volt_cutoff_type)@", inline = 1, label = "limits2", type = 1, apikey = "volt_cutoff_type"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.cutoff_voltage)@", inline = 1, label = "limits3", type = 1, apikey = "cutoff_voltage"}
        }
    },
    advanced = {
        labels = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.governor)@", label = "gov", inline_size = 13.4},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.soft_start)@", label = "start", inline_size = 40.6},
            {t = "", label = "start2", inline_size = 40.6},
            {t = "", label = "start3", inline_size = 40.6}
        },
        fields = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.gov_p_gain)@", inline = 2, label = "gov", apikey = "gov_p_gain"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.gov_i_gain)@", inline = 1, label = "gov", apikey = "gov_i_gain"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.startup_time)@", inline = 1, label = "start", apikey = "startup_time"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.restart_time)@", inline = 1, label = "start2", apikey = "restart_time", type = 1},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.auto_restart)@", inline = 1, label = "start3", apikey = "auto_restart"}
        }
    },
    other = {
        labels = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.motor)@", label = "motor1", inline_size = 40.6},
            {t = "", label = "motor2", inline_size = 40.6},
            {t = "", label = "motor3", inline_size = 40.6},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.brake)@", label = "brake1", inline_size = 40.6},
            {t = "", label = "brake2", inline_size = 40.6}
        },
        fields = {
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.timing)@", inline = 1, label = "motor1", apikey = "timing"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.startup_power)@", inline = 1, label = "motor2", type = 1, apikey = "startup_power"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.active_freewheel)@", inline = 1, label = "motor3", type = 1, apikey = "active_freewheel"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.brake_type)@", inline = 1, label = "brake1", type = 1, apikey = "brake_type"},
            {t = "@i18n(app.modules.esc_tools.mfg.hw5.brake_force)@", inline = 1, label = "brake2", apikey = "brake_force"}
        }
    }
}

local TABLES = {
    rotation = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_cw)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_ccw)@"},
    rotation_hw1128 = {"Forward", "@i18n(api.ESC_PARAMETERS_HW5.tbl_reverse)@", "4D", "4D Reverse"},
    lipo_3_to_14 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_autocalculate)@", "3S", "4S", "5S", "6S", "7S", "8S", "9S", "10S", "11S", "12S", "13S", "14S"},
    lipo_3_to_8 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_autocalculate)@", "3S", "4S", "5S", "6S", "7S", "8S"},
    lipo_even_6_to_14 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_autocalculate)@", "6S", "8S", "10S", "12S", "14S"},
    lipo_2_to_4 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_autocalculate)@", "2S", "3S", "4S"},
    cutoff_28_to_38 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_disabled)@", "2.8V", "2.9V", "3.0V", "3.1V", "3.2V", "3.3V", "3.4V", "3.5V", "3.6V", "3.7V", "3.8V"},
    cutoff_25_to_38 = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_disabled)@", "2.5V", "2.6V", "2.7V", "2.8V", "2.9V", "3.0V", "3.1V", "3.2V", "3.3V", "3.4V", "3.5V", "3.6V", "3.7V", "3.8V"},
    bec_50_to_84 = {"5.0V", "5.1V", "5.2V", "5.3V", "5.4V", "5.5V", "5.6V", "5.7V", "5.8V", "5.9V", "6.0V", "6.1V", "6.2V", "6.3V", "6.4V", "6.5V", "6.6V", "6.7V", "6.8V", "6.9V", "7.0V", "7.1V", "7.2V", "7.3V", "7.4V", "7.5V", "7.6V", "7.7V", "7.8V", "7.9V", "8.0V", "8.1V", "8.2V", "8.3V", "8.4V"},
    bec_54_to_84 = {"5.4V", "5.5V", "5.6V", "5.7V", "5.8V", "5.9V", "6.0V", "6.1V", "6.2V", "6.3V", "6.4V", "6.5V", "6.6V", "6.7V", "6.8V", "6.9V", "7.0V", "7.1V", "7.2V", "7.3V", "7.4V", "7.5V", "7.6V", "7.7V", "7.8V", "7.9V", "8.0V", "8.1V", "8.2V", "8.3V", "8.4V"},
    bec_50_to_120 = {"5.0V", "5.1V", "5.2V", "5.3V", "5.4V", "5.5V", "5.6V", "5.7V", "5.8V", "5.9V", "6.0V", "6.1V", "6.2V", "6.3V", "6.4V", "6.5V", "6.6V", "6.7V", "6.8V", "6.9V", "7.0V", "7.1V", "7.2V", "7.3V", "7.4V", "7.5V", "7.6V", "7.7V", "7.8V", "7.9V", "8.0V", "8.1V", "8.2V", "8.3V", "8.4V", "8.5V", "8.6V", "8.7V", "8.8V", "8.9V", "9.0V", "9.1V", "9.2V", "9.3V", "9.4V", "9.5V", "9.6V", "9.7V", "9.8V", "9.9V", "10.0V", "10.1V", "10.2V", "10.3V", "10.4V", "10.5V", "10.6V", "10.7V", "10.8V", "10.9V", "11.0V", "11.1V", "11.2V", "11.3V", "11.4V", "11.5V", "11.6V", "11.7V", "11.8V", "11.9V", "12.0V"},
    brake_full = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_disabled)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_normal)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_proportional)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_reverse)@"},
    brake_no_prop = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_disabled)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_normal)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_reverse)@"},
    brake_basic = {"@i18n(api.ESC_PARAMETERS_HW5.tbl_disabled)@", "@i18n(api.ESC_PARAMETERS_HW5.tbl_normal)@"}
}

local PROFILES = {
    default = {
        tables = {
            rotation = TABLES.rotation,
            lipo_cell_count = TABLES.lipo_3_to_14,
            cutoff_voltage = TABLES.cutoff_28_to_38,
            bec_voltage = TABLES.bec_50_to_84,
            brake_type = TABLES.brake_full
        }
    },
    HW1104_V100456NB = {
        tables = {
            lipo_cell_count = TABLES.lipo_even_6_to_14,
            bec_voltage = TABLES.bec_50_to_120,
            brake_type = TABLES.brake_basic
        }
    },
    HW1104_V100456NB_PL_OPTO = {
        tables = {
            lipo_cell_count = TABLES.lipo_even_6_to_14,
            brake_type = TABLES.brake_basic
        },
        pages = {
            basic = {"flight_mode", "rotation", "lipo_cell_count", "volt_cutoff_type", "cutoff_voltage"}
        }
    },
    HW1106_V100456NB = {
        tables = {
            lipo_cell_count = TABLES.lipo_3_to_8,
            bec_voltage = TABLES.bec_54_to_84
        }
    },
    HW1106_V200456NB = {
        tables = {
            lipo_cell_count = TABLES.lipo_3_to_8,
            bec_voltage = TABLES.bec_50_to_120,
            brake_type = TABLES.brake_no_prop
        }
    },
    HW1106_V300456NB = {
        tables = {
            lipo_cell_count = TABLES.lipo_3_to_8,
            bec_voltage = TABLES.bec_50_to_120,
            brake_type = TABLES.brake_no_prop
        }
    },
    HW1121_V100456NB = {
        tables = {
            lipo_cell_count = TABLES.lipo_3_to_8,
            bec_voltage = TABLES.bec_50_to_120,
            brake_type = TABLES.brake_no_prop
        }
    },
    HW1128_V100456NB = {
        tables = {
            rotation = TABLES.rotation_hw1128,
            lipo_cell_count = TABLES.lipo_2_to_4,
            cutoff_voltage = TABLES.cutoff_25_to_38,
            brake_type = TABLES.brake_no_prop
        },
        pages = {
            basic = {"rotation", "lipo_cell_count", "volt_cutoff_type", "cutoff_voltage"},
            advanced = {},
            other = {"timing", "startup_power", "active_freewheel", "brake_type", "brake_force"}
        }
    },
    ["HW198_V1.00456NB"] = {
        tables = {
            lipo_cell_count = TABLES.lipo_even_6_to_14,
            bec_voltage = TABLES.bec_50_to_120,
            brake_type = TABLES.brake_basic
        }
    }
}

local function trim(text)
    if type(text) ~= "string" then
        return nil
    end

    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function buildLookup(list)
    local lookup = {}
    local index

    for index = 1, #(list or {}) do
        lookup[list[index]] = true
    end

    return lookup
end

local function pageAllowed(profileConfig, pageKey)
    local pageLayout = PAGE_LAYOUTS[pageKey]
    local override = profileConfig and profileConfig.pages and profileConfig.pages[pageKey] or nil
    local names = {}
    local index

    if pageLayout == nil then
        return {}
    end

    if override == nil then
        for index = 1, #pageLayout.fields do
            names[index] = pageLayout.fields[index].apikey
        end
        return buildLookup(names)
    end

    return buildLookup(override)
end

function profile.profileKey(details)
    local version = trim(details and details.version) or "default"
    local model = string.upper(trim(details and details.model) or "")
    local firmware = string.upper(trim(details and details.firmware) or "")

    if version ~= "default" and (model:find("OPTO", 1, true) or firmware:find("OPTO", 1, true)) then
        return version .. "_PL_OPTO"
    end

    return version
end

function profile.profileConfig(details)
    local key = profile.profileKey(details)
    return PROFILES[key] or PROFILES.default, key
end

function profile.pageLayout(pageKey, details)
    local base = PAGE_LAYOUTS[pageKey]
    local config = profile.profileConfig(details)
    local allowed = pageAllowed(config, pageKey)
    local tables = config.tables or {}
    local fields = {}
    local index
    local field
    local copy

    if base == nil then
        return {labels = {}, fields = {}}
    end

    for index = 1, #base.fields do
        field = base.fields[index]
        if allowed[field.apikey] == true then
            copy = {
                t = field.t,
                inline = field.inline,
                label = field.label,
                type = field.type,
                apikey = field.apikey
            }
            if tables[field.apikey] ~= nil then
                copy.table = tables[field.apikey]
                copy.tableIdxInc = -1
            end
            fields[#fields + 1] = copy
        end
    end

    return {
        labels = base.labels,
        fields = fields
    }
end

return profile
