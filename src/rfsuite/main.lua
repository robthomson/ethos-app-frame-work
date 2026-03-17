--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

--[[
  Rotorflight Ethos Lua Framework - Main Entry Point
  
  This file is the Ethos bootstrap script that lives at:
    SCRIPTS:/rfsuite/main.lua

  Ethos expects bootstrap scripts to return a table with an init()
  function. That init() function then registers the actual system tool
  callbacks (create/wakeup/paint/close).
]] --

-- Sandbox the script to prevent global pollution
local log = require("framework.utils.log")

local _ENV = setmetatable({}, {
    __index = _G,
    __newindex = function(_, k)
        log:warn("Attempted to create global '%s'", tostring(k))
    end
})

local runtime = require("runtime")
local appTool = require("app.tool")
local backgroundTask = require("tasks.tasks")

local function registerMainTool()
    system.registerSystemTool({
        name = appTool.name or runtime.config.toolName,
        icon = appTool.icon or runtime.icon,
        create = appTool.create,
        wakeup = appTool.wakeup,
        paint = appTool.paint,
        event = appTool.event,
        close = appTool.close
    })
end

local function registerBackgroundTask()
    if not system.registerTask then
        log:warn("system.registerTask is unavailable")
        return
    end

    system.registerTask({
        name = runtime.config.bgTaskName,
        key = runtime.config.bgTaskKey,
        init = backgroundTask.init,
        wakeup = backgroundTask.wakeup,
        event = backgroundTask.event,
        read = backgroundTask.read,
        write = backgroundTask.write
    })
end

local function registerWidgets()
    if not system.registerWidget then
        return
    end

    local manifest = require("widgets.manifest")
    for _, meta in ipairs(manifest) do
        local moduleName = "widgets." .. meta.folder .. "." .. meta.script:gsub("%.lua$", "")
        local widget = require(moduleName)

        system.registerWidget({
            name = meta.name,
            key = meta.key,
            create = widget.create,
            wakeup = widget.wakeup,
            paint = widget.paint,
            event = widget.event,
            close = widget.close,
            persistent = widget.persistent or false,
            configure = widget.configure,
            read = widget.read,
            write = widget.write,
            menu = widget.menu,
            title = widget.title
        })
    end
end

local function init()
    if not system or not system.registerSystemTool then
        log:warn("system.registerSystemTool is unavailable")
        return
    end

    registerMainTool()
    registerBackgroundTask()
    registerWidgets()
end

return {init = init}
