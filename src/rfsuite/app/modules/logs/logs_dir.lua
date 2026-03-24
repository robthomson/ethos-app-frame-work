--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local Page = {}

local utils = assert(loadfile("app/modules/logs/lib/utils.lua"))()
local helpText = assert(loadfile("app/modules/logs/help.lua"))()

local function buildEmptyForm(app)
    local message = "@i18n(app.modules.logs.msg_no_logs_found)@"
    local width, height = app:_windowSize()
    local textWidth, textHeight = lcd.getTextSize(message)

    form.addStaticText(nil, {
        x = math.floor((width - textWidth) / 2),
        y = math.floor((height - textHeight) / 2),
        w = textWidth,
        h = app.radio.navbuttonHeight or 30
    }, message)
end

function Page:open(ctx)
    local folders = utils.getLogsDir(utils.getLogPath())
    local node = {
        title = ctx.item.title or "@i18n(app.modules.logs.name)@",
        subtitle = ctx.item.subtitle or "Flight logs and telemetry CSV",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = true},
        items = {}
    }
    local index
    local folder
    local modelName

    for index = 1, #folders do
        folder = folders[index]
        modelName = folder.modelName or utils.resolveModelName(folder.foldername)
        node.items[#node.items + 1] = {
            id = "logs-folder-" .. tostring(index),
            kind = "page",
            path = "logs/logs_logs.lua",
            title = modelName,
            subtitle = folder.foldername,
            image = "app/modules/logs/gfx/folder.png",
            dirname = folder.foldername,
            modelName = modelName,
            offline = true
        }
    end

    if #node.items == 0 then
        function node:buildForm(app)
            buildEmptyForm(app)
        end
    end

    function node:help()
        return utils.openHelpDialog(self.title .. " Help", helpText.default)
    end

    return node
end

return Page
