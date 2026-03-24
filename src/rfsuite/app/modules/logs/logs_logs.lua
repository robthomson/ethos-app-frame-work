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

local function groupedLogItems(dirname, modelName)
    local logs = utils.getLogs(utils.getLogPath(dirname))
    local items = {}
    local index
    local filename
    local datePart

    for index = 1, #logs do
        filename = logs[index]
        datePart = filename:match("(%d%d%d%d%-%d%d%-%d%d)_")
        items[#items + 1] = {
            id = "log-file-" .. tostring(index),
            kind = "page",
            path = "logs/logs_view.lua",
            title = utils.extractHourMinute(filename) or filename,
            subtitle = utils.extractShortTimestamp(filename),
            image = "app/modules/logs/gfx/logs.png",
            logfile = filename,
            dirname = dirname,
            modelName = modelName,
            offline = true,
            group = datePart or "unknown",
            groupTitle = utils.formatDate(datePart or "Unknown")
        }
    end

    return items
end

function Page:open(ctx)
    local dirname = ctx.item.dirname
    local modelName = ctx.item.modelName or utils.resolveModelName(dirname)
    local node = {
        title = modelName,
        subtitle = "Flight log list",
        breadcrumb = ctx.breadcrumb,
        navButtons = {menu = true, save = false, reload = false, tool = false, help = true},
        items = groupedLogItems(dirname, modelName)
    }

    if #node.items == 0 then
        function node:buildForm(app)
            buildEmptyForm(app)
        end
    end

    function node:help()
        return utils.openHelpDialog((self.title or "@i18n(app.modules.logs.name)@") .. " Help", helpText.default)
    end

    return node
end

return Page
