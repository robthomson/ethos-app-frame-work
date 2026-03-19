--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local visibility = {}

local function appendVersionParts(parts, value)
    local valueType
    local arrayValues
    local i

    if value == nil then
        return
    end

    valueType = type(value)

    if valueType == "table" then
        arrayValues = {}

        for i = 1, #value do
            arrayValues[#arrayValues + 1] = value[i]
        end

        if #arrayValues == 3 then
            local major = tonumber(arrayValues[1])
            local middle = tonumber(arrayValues[2])
            local minor = tonumber(arrayValues[3])

            if major and middle == 0 and minor then
                parts[#parts + 1] = major
                parts[#parts + 1] = minor
                return
            end
        end

        for i = 1, #arrayValues do
            appendVersionParts(parts, arrayValues[i])
        end
        return
    end

    for token in tostring(value):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(token)
    end
end

local function versionParts(value)
    local parts = {}

    appendVersionParts(parts, value)
    return parts
end

local function compareVersions(leftValue, rightValue)
    local left = versionParts(leftValue)
    local right = versionParts(rightValue)
    local len
    local i

    if #left == 0 or #right == 0 then
        return nil
    end

    len = math.max(#left, #right)

    for i = 1, len do
        local lv = left[i] or 0
        local rv = right[i] or 0

        if lv > rv then
            return 1
        end
        if lv < rv then
            return -1
        end
    end

    return 0
end

local function matchCompare(leftValue, op, rightValue)
    local cmp = compareVersions(leftValue, rightValue)

    if cmp == nil then
        return false
    end

    if op == ">" then
        return cmp == 1
    elseif op == "<" then
        return cmp == -1
    elseif op == ">=" then
        return cmp >= 0
    elseif op == "<=" then
        return cmp <= 0
    elseif op == "==" then
        return cmp == 0
    elseif op == "!=" or op == "~=" then
        return cmp ~= 0
    end

    return false
end

local function prefBool(value, default)
    if value == nil then
        return default
    end
    if value == true or value == "true" or value == 1 or value == "1" then
        return true
    end
    if value == false or value == "false" or value == 0 or value == "0" then
        return false
    end
    return default
end

local function currentEthosVersion(framework)
    local env = system and system.getVersion and system.getVersion() or nil

    if env then
        return {env.major or 0, env.minor or 0, env.revision or 0}
    end

    return (framework and framework.config and framework.config.ethosVersion) or nil
end

local function preferredApiVersion(framework)
    local prefs
    local supported
    local idx

    if not framework then
        return nil
    end

    prefs = framework.preferences and framework.preferences:section("developer", {}) or {}
    supported = framework.config and framework.config.supportedMspApiVersion or {}
    idx = tonumber(prefs.apiversion) or 1

    return supported[idx]
end

local function currentApiVersion(framework)
    local sessionVersion

    if not framework then
        return nil
    end

    sessionVersion = framework.session and framework.session:get("apiVersion", nil) or nil
    if sessionVersion ~= nil then
        return sessionVersion
    end

    return preferredApiVersion(framework)
end

function visibility.developerToolsEnabled(framework)
    local general

    if not framework or not framework.preferences then
        return false
    end

    general = framework.preferences:section("general", {})
    return prefBool(general.developer_tools, false)
end

function visibility.connectionMode(framework)
    local session
    local connected
    local postConnectComplete

    if not framework or not framework.session then
        return "offline"
    end

    session = framework.session
    connected = session:get("isConnected", false) == true
    postConnectComplete = session:get("postConnectComplete", false) == true

    if not connected then
        return "offline"
    end

    if not postConnectComplete then
        return "postconnect"
    end

    return "online"
end

function visibility.itemEnabled(framework, spec)
    if type(spec) ~= "table" then
        return false
    end

    if spec.disabled == true then
        return false
    end

    if spec.offline == true then
        return true
    end

    return visibility.connectionMode(framework) == "online"
end

function visibility.accessSignature(framework)
    local apiVersion = currentApiVersion(framework)

    return table.concat({
        tostring(apiVersion or "none"),
        visibility.developerToolsEnabled(framework) == true and "developer" or "standard"
    }, "|")
end

function visibility.itemVisible(framework, spec)
    local apiVersion

    if type(spec) ~= "table" then
        return false
    end

    if spec.developer == true and visibility.developerToolsEnabled(framework) ~= true then
        return false
    end

    if spec.ethosversion ~= nil and matchCompare(currentEthosVersion(framework), ">=", spec.ethosversion) ~= true then
        return false
    end

    apiVersion = currentApiVersion(framework)

    if spec.mspversion ~= nil and matchCompare(apiVersion, ">=", spec.mspversion) ~= true then
        return false
    end
    if spec.apiversion ~= nil and matchCompare(apiVersion, ">=", spec.apiversion) ~= true then
        return false
    end
    if spec.apiversionlt ~= nil and matchCompare(apiVersion, "<", spec.apiversionlt) ~= true then
        return false
    end
    if spec.apiversiongt ~= nil and matchCompare(apiVersion, ">", spec.apiversiongt) ~= true then
        return false
    end
    if spec.apiversionlte ~= nil and matchCompare(apiVersion, "<=", spec.apiversionlte) ~= true then
        return false
    end
    if spec.apiversiongte ~= nil and matchCompare(apiVersion, ">=", spec.apiversiongte) ~= true then
        return false
    end

    return true
end

return visibility
