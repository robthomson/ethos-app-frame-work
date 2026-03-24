--[[
  Copyright (C) 2026 Rotorflight Project
  GPLv3 — https://www.gnu.org/licenses/gpl-3.0.en.html
]] --

local controller = {}
local controller_mt = {__index = controller}

function controller.new(shared, options)
    local opts = options or {}

    return setmetatable({
        shared = shared,
        menuRootPath = opts.menuRootPath or "app/menu/root.lua",
        state = {
            currentNode = nil,
            currentNodeSource = opts.menuRootPath or "app/menu/root.lua",
            pathStack = {}
        }
    }, controller_mt)
end

function controller:_app()
    return self.shared and self.shared.app or nil
end

function controller:_sync()
    local app = self:_app()

    if app and app._syncPageHostState then
        app:_syncPageHostState(self.state)
    end
end

function controller:reset()
    self.state.currentNode = nil
    self.state.currentNodeSource = self.menuRootPath
    self.state.pathStack = {}
    self:_sync()
end

function controller:ensureCurrentNode()
    local app = self:_app()

    if self.state.currentNode == nil and app and app._loadRootNode then
        self.state.currentNodeSource = self.menuRootPath
        self.state.currentNode = app:_loadRootNode()
        if app._afterNodeChanged then
            app:_afterNodeChanged()
        end
        if app._invalidateForm then
            app:_invalidateForm()
        end
        self:_sync()
    end

    return self.state.currentNode
end

function controller:openRoot()
    local app = self:_app()

    if app and app._closeNode then
        app:_closeNode(self.state.currentNode)
    end
    if app and app.setPageDirty then
        app:setPageDirty(false)
    end
    self.state.pathStack = {}
    self.state.currentNodeSource = self.menuRootPath
    self.state.currentNode = app and app._loadRootNode and app:_loadRootNode() or nil
    if app and app._afterNodeChanged then
        app:_afterNodeChanged()
    end
    if app and app._invalidateForm then
        app:_invalidateForm()
    end
    self:_sync()
    return self.state.currentNode
end

function controller:enterItem(index, item, breadcrumb)
    local app = self:_app()
    local key
    local opts
    local previousNode

    if type(item) ~= "table" then
        return nil
    end

    if app and app._setSelectedIndex then
        app:_setSelectedIndex(self.state.currentNodeSource, index)
    end
    self.state.pathStack[#self.state.pathStack + 1] = {
        source = self.state.currentNodeSource,
        breadcrumb = self.state.currentNode and self.state.currentNode.breadcrumb or nil,
        item = self.state.currentNode and self.state.currentNode.__item or nil
    }
    previousNode = self.state.currentNode

    if item.kind == "page" and app and app.showLoader then
        app:showLoader({
            kind = "progress",
            title = item.title or item.id or "Loading",
            message = "Loading values.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if app and app._closeNode then
        app:_closeNode(previousNode)
    end
    self.state.currentNode = nil

    if item.kind == "menu" and type(item.source) == "string" then
        self.state.currentNodeSource = item.source
        self.state.currentNode = app and app._loadNodeFromSource and app:_loadNodeFromSource(item.source) or nil
        if type(self.state.currentNode) == "table" then
            self.state.currentNode.breadcrumb = breadcrumb
        end
    elseif item.kind == "page" then
        self.state.currentNodeSource = "page:" .. tostring(item.path or item.id or index)
        self.state.currentNode = app and app._loadPageNode and app:_loadPageNode(item, breadcrumb) or nil
        if type(self.state.currentNode) == "table" and self.state.currentNode.showLoaderOnEnter == true and app and app.updateLoader then
            opts = {}
            for key, value in pairs(self.state.currentNode.loaderOnEnter or {}) do
                opts[key] = value
            end
            opts.title = opts.title or self.state.currentNode.baseTitle or self.state.currentNode.title or item.title or item.id or "Loading"
            app:updateLoader(opts)
        elseif app and app.clearLoader then
            app:clearLoader(true)
        end
    else
        self.state.currentNodeSource = "leaf:" .. tostring(item.id or index)
        self.state.currentNode = app and app._makeLeafNode and app:_makeLeafNode(item, breadcrumb) or nil
    end

    if app and app.setPageDirty then
        app:setPageDirty(false)
    end
    if item.kind ~= "menu" and app and app._requestAppFocusRestore then
        app:_requestAppFocusRestore()
    end
    if app and app._afterNodeChanged then
        app:_afterNodeChanged()
    end
    if app and app._invalidateForm then
        app:_invalidateForm()
    end
    self:_sync()
    return self.state.currentNode
end

function controller:goBack()
    local app = self:_app()
    local previous = self.state.pathStack[#self.state.pathStack]

    if not previous then
        return false
    end

    if app and app._closeNode then
        app:_closeNode(self.state.currentNode)
    end
    self.state.pathStack[#self.state.pathStack] = nil
    self.state.currentNodeSource = previous.source
    if previous.source == self.menuRootPath then
        self.state.currentNode = app and app._loadRootNode and app:_loadRootNode() or nil
    elseif type(previous.item) == "table" and type(previous.source) == "string" and previous.source:sub(1, 5) == "page:" then
        self.state.currentNode = app and app._loadPageNode and app:_loadPageNode(previous.item, previous.breadcrumb) or nil
    else
        self.state.currentNode = app and app._loadNodeFromSource and app:_loadNodeFromSource(previous.source) or nil
        if type(self.state.currentNode) == "table" then
            self.state.currentNode.breadcrumb = previous.breadcrumb
        end
    end
    if app and app.setPageDirty then
        app:setPageDirty(false)
    end
    if app and app._afterNodeChanged then
        app:_afterNodeChanged()
    end
    if app and app._invalidateForm then
        app:_invalidateForm()
    end
    self:_sync()
    return true
end

return controller
