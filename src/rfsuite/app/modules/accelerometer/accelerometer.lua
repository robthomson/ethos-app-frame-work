--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local ModuleLoader = require("framework.utils.module_loader")
local MspPage = ModuleLoader.requireOrLoad("app.lib.msp_page", "app/lib/msp_page.lua")
local utils = require("lib.utils")

local BasePage = MspPage.create({
    title = "@i18n(app.modules.accelerometer.name)@",
    eepromWrite = true,
    reboot = false,
    help = {
        "@i18n(app.modules.accelerometer.help_p1)@"
    },
    navButtons = {
        tool = true
    },
    api = {
        {name = "ACC_TRIM", rebuildOnWrite = true}
    },
    layout = {
        fields = {
            {t = "@i18n(app.modules.accelerometer.roll)@", apikey = "roll"},
            {t = "@i18n(app.modules.accelerometer.pitch)@", apikey = "pitch"}
        }
    }
})
local baseOpen = BasePage.open

local function openDialog(spec)
    if not (form and form.openDialog) then
        return false
    end

    form.openDialog(spec)
    return true
end

local function openConfirmDialog(title, message, onConfirm)
    return openDialog({
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

local function openMessageDialog(title, message)
    return openDialog({
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

local function nodeIsOpen(node)
    return type(node) == "table"
        and type(node.state) == "table"
        and node.state.closed ~= true
        and node.app ~= nil
        and node.app.currentNode == node
end

local function unloadApi(mspTask, apiName, api)
    if api and api.releaseTransientState then
        api.releaseTransientState()
    elseif api and api.clearReadData then
        api.clearReadData()
    end

    if mspTask and mspTask.api and mspTask.api.unload then
        mspTask.api.unload(apiName)
    end
end

local function finishCalibrationFailure(node, err)
    local state = node.state or {}

    state.calibrationBusy = false
    state.calibrationEepromApi = nil

    if node.app and node.app.requestLoaderClose then
        node.app:requestLoaderClose()
    end

    if nodeIsOpen(node) then
        openMessageDialog(node.baseTitle or node.title or "Accelerometer", tostring(err or "Calibration failed."))
    end
end

local function beginCalibrationEepromWrite(node)
    local state = node.state or {}
    local mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    local api = mspTask and mspTask.api and mspTask.api.load and mspTask.api.load("EEPROM_WRITE") or nil

    if not api then
        finishCalibrationFailure(node, "EEPROM write unavailable.")
        return false
    end

    state.calibrationEepromApi = api

    if node.app and node.app.updateLoader then
        node.app:updateLoader({
            message = "Saving calibration."
        })
    end

    api.setUUID(utils.uuid("accelerometer-calibration-eeprom"))
    api.setCompleteHandler(function()
        unloadApi(mspTask, "EEPROM_WRITE", api)
        if state.calibrationEepromApi == api then
            state.calibrationEepromApi = nil
        end
        state.calibrationBusy = false
        state.calibrationComplete = true

        if node.app and node.app.requestLoaderClose then
            node.app:requestLoaderClose()
        end
    end)
    api.setErrorHandler(function(_, err)
        unloadApi(mspTask, "EEPROM_WRITE", api)
        if state.calibrationEepromApi == api then
            state.calibrationEepromApi = nil
        end
        finishCalibrationFailure(node, err or "EEPROM write failed.")
    end)

    if api.write() ~= true then
        unloadApi(mspTask, "EEPROM_WRITE", api)
        if state.calibrationEepromApi == api then
            state.calibrationEepromApi = nil
        end
        finishCalibrationFailure(node, "EEPROM write failed.")
        return false
    end

    return true
end

local function beginCalibration(node)
    local state = node.state or {}
    local mspTask
    local ok
    local reason

    if state.calibrationBusy == true then
        return false
    end

    mspTask = node.app and node.app.framework and node.app.framework.getTask and node.app.framework:getTask("msp") or nil
    if not (mspTask and mspTask.queueCommand) then
        openMessageDialog(node.baseTitle or node.title or "Accelerometer", "MSP task unavailable.")
        return false
    end

    state.calibrationBusy = true
    state.calibrationComplete = false

    if node.app and node.app.showLoader then
        node.app:showLoader({
            kind = "progress",
            title = node.baseTitle or node.title or "Accelerometer",
            message = "@i18n(app.modules.accelerometer.msg_calibrate)@",
            closeWhenIdle = false,
            transferInfo = true,
            focusMenuOnClose = true,
            modal = true,
            minVisibleFor = 0.25
        })
    end

    ok, reason = mspTask:queueCommand(205, {}, {
        timeout = 4.0,
        simulatorResponse = {},
        onReply = function()
            beginCalibrationEepromWrite(node)
        end,
        onError = function(_, err)
            finishCalibrationFailure(node, err or "Calibration failed.")
        end
    })

    if ok ~= true then
        finishCalibrationFailure(node, reason or "Calibration queue failed.")
        return false
    end

    return true
end

function BasePage:open(ctx)
    local node = baseOpen(self, ctx)
    local baseWakeup = node.wakeup

    node.state.calibrationBusy = false
    node.state.calibrationComplete = false
    node.state.calibrationEepromApi = nil

    function node:onToolMenu()
        return openConfirmDialog(
            "@i18n(app.modules.accelerometer.name)@",
            "@i18n(app.modules.accelerometer.msg_calibrate)@",
            function()
                beginCalibration(node)
            end
        )
    end

    function node:wakeup()
        if baseWakeup then
            baseWakeup(self)
        end

        if self.state.calibrationComplete == true then
            self.state.calibrationComplete = false
            if self.app and self.app.audio and self.app.audio.playFileCommon then
                self.app.audio.playFileCommon("beep.wav")
            end
        end
    end

    return node
end

return BasePage
