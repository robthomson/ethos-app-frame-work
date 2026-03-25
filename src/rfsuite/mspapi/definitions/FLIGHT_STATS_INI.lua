--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = require("mspapi.context")
local rfsuite = context.rfsuite
local msp = context.msp
local core = context.core
local factory = context.factory

local API_NAME = "FLIGHT_STATS_INI"
local INI_SECTION = "general"

local ini = rfsuite.ini
local tonumber = tonumber
local ipairs = ipairs
local pairs = pairs

-- LuaFormatter off
local MSP_API_STRUCTURE_READ_DATA = {
    { field = "flightcount",     type = "U32", simResponse = {0}, min = 0, max = 1000000000},
    { field = "lastflighttime",  type = "U32", simResponse = {0}, min = 0, max = 1000000000, unit = "s"},
    { field = "totalflighttime", type = "U32", simResponse = {0}, min = 0, max = 1000000000, unit = "s"},
}
-- LuaFormatter on

local READ_STRUCT = core.prepareStructureData(MSP_API_STRUCTURE_READ_DATA)

local function resolveIniFile()
    local modelPreferencesFile = rfsuite.session.modelPreferencesFile
    local preferencesRoot
    local mcuId

    if type(modelPreferencesFile) == "string" and modelPreferencesFile ~= "" then
        return modelPreferencesFile
    end

    preferencesRoot = rfsuite.config.preferences
    mcuId = rfsuite.session.mcu_id
    if type(preferencesRoot) == "string" and preferencesRoot ~= "" and type(mcuId) == "string" and mcuId ~= "" then
        return "SCRIPTS:/" .. preferencesRoot .. "/models/" .. mcuId .. ".ini"
    end

    return nil
end

local function resolveIniTable()
    local modelPreferences = rfsuite.session.modelPreferences
    local iniFile

    if type(modelPreferences) == "table" then
        return modelPreferences
    end

    iniFile = resolveIniFile()
    if iniFile then
        return ini.load_ini_file(iniFile) or {}
    end

    return {}
end

local function loadParsedFromINI()
    local tbl = resolveIniTable()
    local parsed = {}
    for _, entry in ipairs(MSP_API_STRUCTURE_READ_DATA) do
        parsed[entry.field] = tonumber(ini.getvalue(tbl, INI_SECTION, entry.field)) or entry.simResponse[1] or 0
    end
    return parsed
end

return factory.create({
    name = API_NAME,
    readStructure = READ_STRUCT,
    customRead = function(state, emitComplete)
        local parsed = loadParsedFromINI()
        state.mspData = {
            parsed = parsed,
            structure = READ_STRUCT,
            buffer = parsed,
            positionmap = {},
            other = {},
            receivedBytesCount = #MSP_API_STRUCTURE_READ_DATA
        }
        state.mspWriteComplete = false
        emitComplete(nil, parsed)
        return true
    end,
    customWrite = function(_, state, emitComplete, emitError)
        local iniFile = resolveIniFile()
        local msg = "@i18n(app.modules.profile_select.save_prompt_local)@"
        local tbl

        rfsuite.app.ui.progressDisplaySave(msg:gsub("%?$", "."))

        if not iniFile then
            emitError(nil, "Model preferences file unavailable")
            return false, "model_preferences_file_unavailable"
        end

        tbl = resolveIniTable()
        tbl.general = tbl.general or {}

        for k, v in pairs(state.payloadData) do
            v = math.floor(v)
            ini.setvalue(tbl, INI_SECTION, k, v)
            if rfsuite.session.modelPreferences and rfsuite.session.modelPreferences[INI_SECTION] then
                rfsuite.session.modelPreferences[INI_SECTION][k] = v
            end
        end

        local ok, err = ini.save_ini_file(iniFile, tbl)
        if not ok then
            emitError(nil, err or ("Failed to save INI: " .. iniFile))
            return false, err
        end

        state.mspWriteComplete = true
        local parsed = loadParsedFromINI()
        state.mspData = {
            parsed = parsed,
            structure = READ_STRUCT,
            buffer = parsed,
            positionmap = {},
            other = {},
            receivedBytesCount = #MSP_API_STRUCTURE_READ_DATA
        }

        emitComplete(nil, parsed)
        state.payloadData = {}
        return true
    end,
    readCompleteFn = function(state)
        return state.mspData ~= nil
    end,
    methods = {
        resetWriteStatus = function(state)
            state.mspWriteComplete = false
            state.payloadData = {}
            state.mspData = nil
        end
    }
})
