--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local adapter = require("app.lib.legacy_page_adapter")

local Page = {}

function Page:open(ctx)
    return adapter.open(ctx, "app/modules/modes/legacy.lua")
end

return Page
