--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local registry = require("lifecycle.registry")
local onconnect = require("lifecycle.onconnect")

local defaults = {
    _registered = false
}

local function markPostConnect(context)
    local payload = context.payload or {}

    context.session:setMultiple({
        postConnectComplete = true,
        postConnectTransport = payload.transport or context.session:get("connectionTransport", "disconnected"),
        postConnectApiVersion = payload.apiVersion or context.session:get("apiVersion", nil),
        postConnectProtocolVersion = payload.protocolVersion or context.session:get("mspProtocolVersion", 1),
        postConnectAt = payload.at or context.now,
        postConnectToken = payload.connectionToken or context.session:get("connectionToken", 0)
    })

    return true
end

local function clearPostConnect(context)
    local payload = context.payload or {}

    context.session:setMultiple({
        postConnectComplete = false,
        postConnectTransport = payload.newTransport or "disconnected",
        postConnectProtocolVersion = context.framework.config.mspProtocolVersion or 1,
        postConnectAt = 0
    })
    context.session:clearKeys({
        "postConnectApiVersion",
        "fcVersion",
        "rfVersion",
        "mcu_id",
        "modelPreferences",
        "modelPreferencesFile",
        "flightMode",
        "currentFlightMode",
        "sensorStats",
        "timer",
        "flightCounted",
        "defaultRateProfile",
        "defaultRateProfileName"
    })

    return true
end

local function rememberTransportChange(context)
    local payload = context.payload or {}

    context.session:setMultiple({
        lastTransportChangeAt = payload.at or context.now,
        lastTransportOld = payload.oldTransport or "disconnected",
        lastTransportNew = payload.newTransport or "disconnected"
    })

    return true
end

function defaults.registerAll()
    if defaults._registered then
        return
    end

    registry.register("onconnect", "session.postconnect", markPostConnect, {priority = 100})
    registry.register("ondisconnect", "session.disconnect", clearPostConnect, {priority = 100})
    registry.register("ontransportchange", "session.transportchange", rememberTransportChange, {priority = 100})
    onconnect.registerAll(registry)

    defaults._registered = true
end

return defaults
