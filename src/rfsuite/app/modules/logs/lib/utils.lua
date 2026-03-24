--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ini = require("lib.ini")

local utils = {}

local BASE_DIR = "LOGS:/rfsuite/telemetry"
local MAX_LOG_ENTRIES = 50

local function safeMkdir(path)
    if os and os.mkdir and path then
        pcall(os.mkdir, path)
    end
end

local function trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function sortByText(a, b)
    return tostring(a):lower() < tostring(b):lower()
end

local function darkColor(light, dark)
    if lcd and lcd.darkMode and lcd.darkMode() then
        return dark
    end
    return light
end

function utils.ensureBaseDir()
    safeMkdir("LOGS:")
    safeMkdir("LOGS:/rfsuite")
    safeMkdir(BASE_DIR)
    return BASE_DIR
end

function utils.getLogPath(dirname)
    utils.ensureBaseDir()

    if type(dirname) == "string" and dirname ~= "" then
        return string.format("%s/%s/", BASE_DIR, dirname)
    end

    return BASE_DIR .. "/"
end

function utils.getLogDir(dirname)
    local path = utils.getLogPath(dirname)

    if type(dirname) == "string" and dirname ~= "" then
        safeMkdir(path)
    end

    return path
end

function utils.resolveModelName(foldername)
    local iniName
    local iniData
    local modelName

    if foldername == nil or foldername == "" then
        return "Unknown"
    end

    iniName = string.format("%s/%s/logs.ini", BASE_DIR, foldername)
    iniData = ini.load_ini_file(iniName) or {}
    modelName = iniData.model and iniData.model.name or nil
    modelName = trim(tostring(modelName or ""))

    if modelName ~= "" then
        return modelName
    end

    return "Unknown"
end

function utils.hasModelName(foldername)
    return utils.resolveModelName(foldername) ~= "Unknown"
end

function utils.folderHasLogs(foldername)
    local files
    local index
    local name

    if type(foldername) ~= "string" or foldername == "" then
        return false
    end

    files = system and system.listFiles and system.listFiles(string.format("%s/%s", BASE_DIR, foldername)) or {}
    for index = 1, #files do
        name = files[index]
        if type(name) == "string" and name:match("%.csv$") then
            return true
        end
    end

    return false
end

function utils.getLogs(logDir)
    local files = system and system.listFiles and system.listFiles(logDir) or {}
    local entries = {}
    local index
    local fname
    local datePart
    local timePart
    local result = {}

    for index = 1, #files do
        fname = files[index]
        if type(fname) == "string" and fname:match("%.csv$") then
            datePart, timePart = fname:match("(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)_")
            if datePart and timePart then
                entries[#entries + 1] = {name = fname, ts = datePart .. "T" .. timePart}
            end
        end
    end

    table.sort(entries, function(a, b)
        return tostring(a.ts) > tostring(b.ts)
    end)

    for index = MAX_LOG_ENTRIES + 1, #entries do
        pcall(os.remove, logDir .. "/" .. entries[index].name)
    end

    for index = 1, math.min(#entries, MAX_LOG_ENTRIES) do
        result[#result + 1] = entries[index].name
    end

    return result
end

function utils.getLogsDir(logDir)
    local files = system and system.listFiles and system.listFiles(logDir) or {}
    local dirs = {}
    local index
    local name
    local modelName

    for index = 1, #files do
        name = files[index]
        if type(name) == "string"
            and name ~= "."
            and name ~= ".."
            and not name:match("^%.%w%w%w$")
            and not name:match("%.%w%w%w$")
            and utils.folderHasLogs(name)
        then
            modelName = utils.resolveModelName(name)
            if modelName == "Unknown" then
                modelName = name
            end
            dirs[#dirs + 1] = {foldername = name, modelName = modelName}
        end
    end

    table.sort(dirs, function(a, b)
        local aName = trim(a.modelName or "")
        local bName = trim(b.modelName or "")

        if aName == bName then
            return sortByText(a.foldername, b.foldername)
        end

        return sortByText(aName, bName)
    end)

    return dirs
end

function utils.extractHourMinute(filename)
    local hour
    local minute

    if type(filename) ~= "string" then
        return nil
    end

    hour, minute = filename:match(".-%d%d%d%d%-%d%d%-%d%d_(%d%d)%-(%d%d)%-%d%d")
    if hour and minute then
        return hour .. ":" .. minute
    end

    return nil
end

function utils.extractShortTimestamp(filename)
    local datePart
    local timePart

    if type(filename) ~= "string" then
        return nil
    end

    datePart, timePart = filename:match(".-(%d%d%d%d%-%d%d%-%d%d)_(%d%d%-%d%d%-%d%d)")
    if datePart and timePart then
        return datePart:gsub("%-", "/") .. " " .. timePart:gsub("%-", ":")
    end

    return filename
end

function utils.formatDate(isoDate)
    local year
    local month
    local day

    if type(isoDate) ~= "string" then
        return tostring(isoDate or "")
    end

    year, month, day = isoDate:match("^(%d+)%-(%d+)%-(%d+)$")
    if not (year and month and day) then
        return isoDate
    end

    return os.date("%d %B %Y", os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day)
    }))
end

function utils.openHelpDialog(title, lines)
    local message

    if not (form and form.openDialog) then
        return false
    end

    message = table.concat(lines or {}, "\n\n")
    form.openDialog({
        width = nil,
        title = title or "@i18n(app.modules.logs.name)@",
        message = message,
        buttons = {{
            label = "Close",
            action = function()
                return true
            end
        }},
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })

    return true
end

function utils.getLogColumns()
    return {
        {
            name = "voltage",
            keyindex = 1,
            keyname = "Voltage",
            keyunit = "v",
            keyminmax = 1,
            color = darkColor(lcd and lcd.RGB and lcd.RGB(200, 0, 0) or COLOR_RED, COLOR_RED),
            pen = SOLID,
            graph = true
        },
        {
            name = "current",
            keyindex = 2,
            keyname = "Current",
            keyunit = "A",
            keyminmax = 1,
            color = darkColor(lcd and lcd.RGB and lcd.RGB(220, 100, 0) or COLOR_ORANGE, COLOR_ORANGE),
            pen = SOLID,
            graph = true
        },
        {
            name = "rpm",
            keyindex = 3,
            keyname = "Headspeed",
            keyunit = "rpm",
            keyminmax = 1,
            keyfloor = true,
            color = darkColor(lcd and lcd.RGB and lcd.RGB(0, 140, 0) or COLOR_GREEN, COLOR_GREEN),
            pen = SOLID,
            graph = true
        },
        {
            name = "temp_esc",
            keyindex = 4,
            keyname = "Esc. Temperature",
            keyunit = "°",
            keyminmax = 1,
            color = darkColor(lcd and lcd.RGB and lcd.RGB(0, 80, 200) or COLOR_CYAN, COLOR_CYAN),
            pen = SOLID,
            graph = true
        },
        {
            name = "throttle_percent",
            keyindex = 5,
            keyname = "Throttle %",
            keyunit = "%",
            keyminmax = 1,
            color = darkColor(lcd and lcd.RGB and lcd.RGB(180, 160, 0) or COLOR_YELLOW, COLOR_YELLOW),
            pen = SOLID,
            graph = true
        }
    }
end

return utils
