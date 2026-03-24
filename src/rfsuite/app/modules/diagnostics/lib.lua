--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local runtime = require("runtime")
local utils = require("lib.utils")

local diagnostics = {}

local ARMING_DISABLE_FLAG_TAG = {
    [0] = "@i18n(app.modules.fblstatus.arming_disable_flag_0):upper()@",
    [1] = "@i18n(app.modules.fblstatus.arming_disable_flag_1):upper()@",
    [2] = "@i18n(app.modules.fblstatus.arming_disable_flag_2):upper()@",
    [3] = "@i18n(app.modules.fblstatus.arming_disable_flag_3):upper()@",
    [4] = "@i18n(app.modules.fblstatus.arming_disable_flag_4):upper()@",
    [5] = "@i18n(app.modules.fblstatus.arming_disable_flag_5):upper()@",
    [6] = "@i18n(app.modules.fblstatus.arming_disable_flag_6):upper()@",
    [7] = "@i18n(app.modules.fblstatus.arming_disable_flag_7):upper()@",
    [8] = "@i18n(app.modules.fblstatus.arming_disable_flag_8):upper()@",
    [9] = "@i18n(app.modules.fblstatus.arming_disable_flag_9):upper()@",
    [10] = "@i18n(app.modules.fblstatus.arming_disable_flag_10):upper()@",
    [11] = "@i18n(app.modules.fblstatus.arming_disable_flag_11):upper()@",
    [12] = "@i18n(app.modules.fblstatus.arming_disable_flag_12):upper()@",
    [13] = "@i18n(app.modules.fblstatus.arming_disable_flag_13):upper()@",
    [14] = "@i18n(app.modules.fblstatus.arming_disable_flag_14):upper()@",
    [15] = "@i18n(app.modules.fblstatus.arming_disable_flag_15):upper()@",
    [16] = "@i18n(app.modules.fblstatus.arming_disable_flag_16):upper()@",
    [17] = "@i18n(app.modules.fblstatus.arming_disable_flag_17):upper()@",
    [18] = "@i18n(app.modules.fblstatus.arming_disable_flag_18):upper()@",
    [19] = "@i18n(app.modules.fblstatus.arming_disable_flag_19):upper()@",
    [20] = "@i18n(app.modules.fblstatus.arming_disable_flag_20):upper()@",
    [21] = "@i18n(app.modules.fblstatus.arming_disable_flag_21):upper()@",
    [22] = "@i18n(app.modules.fblstatus.arming_disable_flag_22):upper()@",
    [23] = "@i18n(app.modules.fblstatus.arming_disable_flag_23):upper()@",
    [24] = "@i18n(app.modules.fblstatus.arming_disable_flag_24):upper()@",
    [25] = "@i18n(app.modules.fblstatus.arming_disable_flag_25):upper()@"
}

local function bitSet(value, bit)
    local n = tonumber(value) or 0
    local mask = 2 ^ bit

    return math.floor(n / mask) % 2 == 1
end

function diagnostics.valuePos(app, width)
    local totalWidth = app and app._windowSize and app:_windowSize() or select(1, lcd.getWindowSize())
    local valueWidth = math.max(110, tonumber(width) or math.floor(totalWidth * 0.34))

    return {
        x = totalWidth - valueWidth - 8,
        y = app and app.radio and app.radio.linePaddingTop or 0,
        w = valueWidth,
        h = app and app.radio and app.radio.navbuttonHeight or 30
    }
end

function diagnostics.setFieldText(field, value, color)
    if not field then
        return
    end

    if field.value then
        field:value(tostring(value or "-"))
    end
    if color and field.color then
        field:color(color)
    end
end

function diagnostics.setStatusField(field, ok, dashIfNil)
    if dashIfNil == true and ok == nil then
        diagnostics.setFieldText(field, "-")
        return
    end

    if ok == true then
        diagnostics.setFieldText(field, "@i18n(app.modules.rfstatus.ok)@", GREEN)
    elseif ok == false then
        diagnostics.setFieldText(field, "@i18n(app.modules.rfstatus.error)@", RED)
    else
        diagnostics.setFieldText(field, "-")
    end
end

function diagnostics.sortSensorListByName(sensorList)
    table.sort(sensorList, function(a, b)
        return tostring(a and a.name or ""):lower() < tostring(b and b.name or ""):lower()
    end)
    return sensorList
end

function diagnostics.moduleEnabled()
    local moduleIndex
    local module
    local ok
    local enabled

    if not (model and model.getModule) then
        return false
    end

    for moduleIndex = 0, 1 do
        ok, module = pcall(model.getModule, moduleIndex)
        if ok and module and module.enable then
            ok, enabled = pcall(module.enable, module)
            if ok and enabled == true then
                return true
            end
        end
    end

    return false
end

function diagnostics.haveMspSensor()
    local descriptors = {
        {appId = 0xF101},
        {crsfId = 0x14, subIdStart = 0, subIdEnd = 1}
    }
    local index
    local ok
    local source

    if not (system and system.getSource) then
        return false
    end

    for index = 1, #descriptors do
        ok, source = pcall(system.getSource, descriptors[index])
        if ok and source then
            return true
        end
    end

    return false
end

function diagnostics.systemMemoryFreeKB()
    local ok
    local info

    if not (system and system.getMemoryUsage) then
        return nil
    end

    ok, info = pcall(system.getMemoryUsage)
    if not ok or type(info) ~= "table" then
        return nil
    end

    if tonumber(info.ramAvailable) then
        return tonumber(info.ramAvailable) / 1024
    end
    if tonumber(info.luaRamAvailable) then
        return tonumber(info.luaRamAvailable) / 1024
    end

    return nil
end

function diagnostics.approxCpuLoad(app)
    local framework = app and app.framework or nil
    local session = framework and framework.session or nil
    local config = framework and framework.config or {}
    local loopMs = tonumber(session and session:get("taskLoopAvgMs", 0) or 0) or 0
    local budgetMs = tonumber(config.taskScheduler and config.taskScheduler.maxLoopMs) or 8

    if budgetMs <= 0 then
        return nil
    end

    return math.max(0, (loopMs / budgetMs) * 100)
end

function diagnostics.ethosVersionString()
    local version = system and system.getVersion and system.getVersion() or {}
    return string.format("%d.%d.%d", tonumber(version.major) or 0, tonumber(version.minor) or 0, tonumber(version.revision) or 0)
end

function diagnostics.supportedMspVersions(app)
    local versions = app and app.framework and app.framework.config and app.framework.config.supportedMspApiVersion or {}
    return table.concat(versions or {}, ", ")
end

function diagnostics.formatVersion(value)
    if value == nil or value == "" then
        return "-"
    end
    return tostring(value)
end

function diagnostics.isSimulation()
    local version = system and system.getVersion and system.getVersion() or {}
    return version.simulation == true
end

function diagnostics.openDialog(spec)
    if not (form and form.openDialog) then
        return false
    end

    form.openDialog(spec)
    return true
end

function diagnostics.openMessageDialog(title, message)
    return diagnostics.openDialog({
        width = nil,
        title = title,
        message = message,
        buttons = {
            {
                label = "@i18n(app.btn_ok)@",
                action = function()
                    return true
                end
            }
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
end

function diagnostics.openConfirmDialog(title, message, onConfirm)
    return diagnostics.openDialog({
        width = nil,
        title = title,
        message = message,
        buttons = {
            {
                label = "@i18n(app.btn_ok_long)@",
                action = function()
                    if type(onConfirm) == "function" then
                        onConfirm()
                    end
                    return true
                end
            },
            {
                label = "@i18n(app.btn_cancel)@",
                action = function()
                    return true
                end
            }
        },
        wakeup = function() end,
        paint = function() end,
        options = TEXT_LEFT
    })
end

function diagnostics.openHelpDialog(title, lines)
    local message

    if type(lines) == "table" then
        message = table.concat(lines, "\n\n")
    else
        message = tostring(lines or "")
    end

    return diagnostics.openMessageDialog(title, message)
end

function diagnostics.armingDisableFlagsToString(flags)
    local names = {}
    local bit

    flags = tonumber(flags)
    if not flags or flags == 0 then
        return "@i18n(app.modules.fblstatus.ok):upper()@"
    end

    for bit = 0, 25 do
        if bitSet(flags, bit) then
            names[#names + 1] = ARMING_DISABLE_FLAG_TAG[bit]
        end
    end

    if #names == 0 then
        return string.format("0x%X", flags)
    end

    return table.concat(names, ", ")
end

function diagnostics.runtimeVersion()
    return runtime and runtime.config and runtime.config.version or "-"
end

function diagnostics.backgroundState()
    local status = runtime.backgroundStatus() or {}
    return status
end

return diagnostics
