--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")

local utils = {}

local uuidCounter = 0
local simSensorChunks = {}
local simSensorDirsReady = false

local function appendVersionParts(parts, value)
    local valueType
    local i

    if value == nil then
        return
    end

    valueType = type(value)

    if valueType == "table" then
        local arrayValues = {}

        for i, token in ipairs(value) do
            arrayValues[#arrayValues + 1] = token
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

        if #arrayValues > 0 then
            for i = 1, #arrayValues do
                appendVersionParts(parts, arrayValues[i])
            end
        elseif value[0] ~= nil then
            appendVersionParts(parts, value[0])
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

function utils.log(msg, level)
    local logger = framework.log
    local method = level or "info"

    if logger and type(logger[method]) == "function" then
        logger[method](logger, "%s", tostring(msg))
    elseif logger and type(logger.add) == "function" then
        logger:add({message = tostring(msg), level = method})
    else
        print(string.format("[%s] %s", tostring(method), tostring(msg)))
    end
end

function utils.ethosVersionAtLeast(targetVersion)
    local env
    local currentVersion
    local i

    if not system or not system.getVersion then
        return false
    end

    env = system.getVersion()
    currentVersion = {env.major or 0, env.minor or 0, env.revision or 0}

    if targetVersion == nil then
        targetVersion = framework.config and framework.config.ethosVersion or nil
        if not targetVersion then
            return false
        end
    elseif type(targetVersion) == "number" then
        utils.log("utils.ethosVersionAtLeast expects a version table", "warn")
        return false
    end

    for i = 1, 3 do
        local current = currentVersion[i] or 0
        local required = targetVersion[i] or 0

        if current > required then
            return true
        elseif current < required then
            return false
        end
    end

    return true
end

function utils.decimalInc(dec)
    if dec == nil then
        return 1
    elseif dec > 0 and dec <= 10 then
        return 10 ^ dec
    end

    return nil
end

function utils.splitVersionStringToNumbers(versionString)
    local parts = {0}

    if not versionString then
        return nil
    end

    for token in tostring(versionString):gmatch("(%d+)") do
        parts[#parts + 1] = tonumber(token)
    end

    return parts
end

function utils.apiVersionCompare(op, req, currentVersion)
    local left = versionParts(currentVersion or framework.session:get("apiVersion", "12.06"))
    local right = versionParts(req)
    local len
    local cmp = 0
    local i

    if #left == 0 or #right == 0 then
        return false
    end

    len = math.max(#left, #right)

    for i = 1, len do
        local lv = left[i] or 0
        local rv = right[i] or 0

        if lv ~= rv then
            cmp = (lv > rv) and 1 or -1
            break
        end
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

function utils.uuid(prefix)
    local now
    local seconds
    local millis

    uuidCounter = uuidCounter + 1
    if uuidCounter > 2147483647 then
        uuidCounter = 1
    end

    now = os.clock()
    seconds = math.floor(now)
    millis = math.floor((now - seconds) * 1000)

    if prefix and prefix ~= "" then
        return string.format("%s-%d-%03d-%d", prefix, seconds, millis, uuidCounter)
    end

    return string.format("%d-%03d-%d", seconds, millis, uuidCounter)
end

function utils.file_exists(path)
    local handle = io.open(path, "rb")

    if handle then
        handle:close()
        return true
    end

    return false
end

function utils.simSensors(id)
    local chunk
    local err
    local ok
    local result
    local path

    if id == nil then
        return 0
    end

    if simSensorDirsReady ~= true and os and os.mkdir then
        pcall(os.mkdir, "LOGS:")
        pcall(os.mkdir, "LOGS:/rfsuite")
        pcall(os.mkdir, "LOGS:/rfsuite/sensors")
        simSensorDirsReady = true
    end

    path = "sim/sensors/" .. tostring(id) .. ".lua"
    chunk = simSensorChunks[path]

    if chunk == nil then
        chunk, err = loadfile(path)
        if not chunk then
            utils.log("Error loading telemetry file: " .. tostring(err), "warn")
            simSensorChunks[path] = false
            return 0
        end

        simSensorChunks[path] = chunk
    elseif chunk == false then
        return 0
    end

    ok, result = pcall(chunk)
    if ok ~= true then
        utils.log("Error executing telemetry file: " .. tostring(result), "warn")
        return 0
    end

    return result or 0
end

return utils
