--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local PrefsPage = {}

local function copyTable(source)
    local out = {}

    for key, value in pairs(source or {}) do
        if type(value) == "table" then
            out[key] = copyTable(value)
        else
            out[key] = value
        end
    end

    return out
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

local function toNumber(value, default)
    local n = tonumber(value)
    if n == nil then
        return default
    end
    return n
end

local function containerWithLines(title)
    if form and form.addExpansionPanel then
        return form.addExpansionPanel(title)
    end

    return {
        addLine = function(_, label)
            return form.addLine(label)
        end
    }
end

local function addLine(container, label)
    if container and container.addLine then
        return container:addLine(label)
    end
    return form.addLine(label)
end

local function addField(container, field, state)
    local line = addLine(container, field.label)
    local key = field.key

    if field.kind == "choice" then
        return form.addChoiceField(line, nil, field.choices or {},
            function()
                if type(field.get) == "function" then
                    return field.get(state)
                end
                return state[key]
            end,
            function(newValue)
                if type(field.set) == "function" then
                    field.set(state, newValue)
                else
                    state[key] = newValue
                end
            end)
    end

    if field.kind == "boolean" then
        return form.addBooleanField(line, nil,
            function()
                if type(field.get) == "function" then
                    return field.get(state)
                end
                return prefBool(state[key], field.default == true)
            end,
            function(newValue)
                if type(field.set) == "function" then
                    field.set(state, newValue)
                else
                    state[key] = newValue
                end
            end)
    end

    if field.kind == "number" then
        local control = form.addNumberField(line, nil, field.min or 0, field.max or 100,
            function()
                if type(field.get) == "function" then
                    return field.get(state)
                end
                return toNumber(state[key], field.default)
            end,
            function(newValue)
                if type(field.set) == "function" then
                    field.set(state, newValue)
                else
                    state[key] = newValue
                end
            end)

        if control and control.suffix and field.suffix then
            control:suffix(field.suffix)
        end
        if control and control.minimum and field.min ~= nil then
            control:minimum(field.min)
        end
        if control and control.maximum and field.max ~= nil then
            control:maximum(field.max)
        end

        return control
    end

    return nil
end

function PrefsPage.create(spec)
    local pageSpec = type(spec) == "table" and spec or {}

    return {
        open = function(_, ctx)
            local state = type(pageSpec.readState) == "function" and pageSpec.readState(ctx.framework) or {}
            local node = {
                title = ctx.item.title or pageSpec.title or "Preferences",
                subtitle = ctx.item.subtitle or pageSpec.subtitle or "Preferences",
                breadcrumb = ctx.breadcrumb,
                navButtons = pageSpec.navButtons or {menu = true, save = true, reload = true, tool = false, help = false},
                state = state
            }

            local function resetState()
                local fresh = type(pageSpec.readState) == "function" and pageSpec.readState(ctx.framework) or {}

                for key in pairs(state) do
                    state[key] = nil
                end
                for key, value in pairs(fresh) do
                    state[key] = value
                end
            end

            function node:buildForm(app)
                local section
                local field

                for _, section in ipairs(pageSpec.sections or {}) do
                    local container = containerWithLines(section.title)

                    for _, field in ipairs(section.fields or {}) do
                        addField(container, field, state)
                    end
                end

                if type(pageSpec.buildForm) == "function" then
                    pageSpec.buildForm(self, app, state)
                end
            end

            function node:save(app)
                local result

                if pageSpec.showSaveLoader ~= false and app and app.ui and app.ui.showLoader then
                    app.ui.showLoader({
                        kind = "save",
                        title = self.title or pageSpec.title or "Saving",
                        message = "Saving settings.",
                        closeWhenIdle = false,
                        modal = true
                    })
                end

                if type(pageSpec.save) == "function" then
                    result = pageSpec.save(self, app, state)
                else
                    result = true
                end

                if pageSpec.showSaveLoader ~= false and app and app.ui and app.ui.clearProgressDialog then
                    app.ui.clearProgressDialog(true)
                end

                return result ~= false
            end

            function node:reload(app)
                if pageSpec.showReloadLoader ~= false and app and app.ui and app.ui.showLoader then
                    app.ui.showLoader({
                        kind = "progress",
                        title = self.title or pageSpec.title or "Reloading",
                        message = "Reloading settings.",
                        closeWhenIdle = false,
                        modal = true
                    })
                end

                resetState()
                if type(pageSpec.afterReload) == "function" then
                    pageSpec.afterReload(self, app, state)
                end
                app:_invalidateForm()

                if pageSpec.showReloadLoader ~= false and app and app.ui and app.ui.clearProgressDialog then
                    app.ui.clearProgressDialog(true)
                end

                return true
            end

            if type(pageSpec.getGeneralPreferences) == "function" then
                function node:getGeneralPreferences()
                    return pageSpec.getGeneralPreferences(self, state)
                end
            end

            return node
        end
    }
end

return PrefsPage
