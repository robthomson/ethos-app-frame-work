--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local framework = require("framework.core.init")
local utils = require("lib.utils")

local context = {}

local function lazyModule(name)
    return setmetatable({}, {
        __index = function(_, key)
            return require(name)[key]
        end,
        __newindex = function(_, key, value)
            require(name)[key] = value
        end
    })
end

local function resolveTask(name)
    if framework and framework.getTask and framework._taskMetadata and framework._taskMetadata[name] then
        return framework:getTask(name)
    end
    return nil
end

local sessionProxy = setmetatable({}, {
    __index = function(_, key)
        if framework and framework.session then
            return framework.session:get(key)
        end
        return nil
    end,
    __newindex = function(_, key, value)
        if framework and framework.session then
            framework.session:set(key, value)
        end
    end
})

local configProxy = setmetatable({}, {
    __index = function(_, key)
        return framework and framework.config and framework.config[key] or nil
    end,
    __newindex = function(_, key, value)
        if framework and framework.config then
            framework.config[key] = value
        end
    end
})

local preferencesProxy = setmetatable({}, {
    __index = function(_, key)
        return framework and framework.preferences and framework.preferences[key] or nil
    end,
    __newindex = function(_, key, value)
        if framework and framework.preferences then
            framework.preferences[key] = value
        end
    end
})

local tasksProxy = setmetatable({}, {
    __index = function(_, key)
        if key == "callback" then
            return framework and framework.callback or nil
        end
        return resolveTask(key)
    end
})

local uiStub = {
    progressDisplaySave = function()
    end
}

local appProxy = setmetatable({
    ui = uiStub,
    Page = nil,
    formFields = nil
}, {
    __index = function(_, key)
        local app = framework and framework.getApp and framework:getApp() or nil
        if app and app[key] ~= nil then
            return app[key]
        end
        return rawget(_, key)
    end,
    __newindex = function(_, key, value)
        local app = framework and framework.getApp and framework:getApp() or nil
        if app then
            app[key] = value
        else
            rawset(_, key, value)
        end
    end
})

local iniProxy = lazyModule("lib.ini")
local mspProxy = setmetatable({}, {
    __index = function(_, key)
        local task = resolveTask("msp")
        return task and task[key] or nil
    end,
    __newindex = function(_, key, value)
        local task = resolveTask("msp")
        if task then
            task[key] = value
        end
    end
})

context.core = lazyModule("mspapi.core")
context.factory = lazyModule("mspapi.factory")
context.msp = mspProxy

context.rfsuite = {
    config = configProxy,
    preferences = preferencesProxy,
    session = sessionProxy,
    tasks = tasksProxy,
    utils = utils,
    ini = iniProxy,
    app = appProxy
}

return context
