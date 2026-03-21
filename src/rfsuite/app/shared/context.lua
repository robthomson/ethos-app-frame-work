--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local context = {}

function context.new(app)
    local framework = app and app.framework or nil

    return {
        app = app,
        framework = framework,
        session = framework and framework.session or nil,
        preferences = framework and framework.preferences or nil,
        callback = app and app.callback or nil
    }
end

return context
