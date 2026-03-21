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
        onSyncState = opts.onSyncState,
        loadRootNode = opts.loadRootNode,
        loadNodeFromSource = opts.loadNodeFromSource,
        loadPageNode = opts.loadPageNode,
        makeLeafNode = opts.makeLeafNode,
        closeNode = opts.closeNode,
        afterNodeChanged = opts.afterNodeChanged,
        invalidateForm = opts.invalidateForm,
        setPageDirty = opts.setPageDirty,
        requestAppFocusRestore = opts.requestAppFocusRestore,
        setSelectedIndex = opts.setSelectedIndex,
        showLoader = opts.showLoader,
        updateLoader = opts.updateLoader,
        clearLoader = opts.clearLoader,
        state = {
            currentNode = nil,
            currentNodeSource = opts.menuRootPath or "app/menu/root.lua",
            pathStack = {}
        }
    }, controller_mt)
end

function controller:_sync()
    if type(self.onSyncState) == "function" then
        self.onSyncState(self.state)
    end
end

function controller:reset()
    self.state.currentNode = nil
    self.state.currentNodeSource = self.menuRootPath
    self.state.pathStack = {}
    self:_sync()
end

function controller:ensureCurrentNode()
    if self.state.currentNode == nil and type(self.loadRootNode) == "function" then
        self.state.currentNodeSource = self.menuRootPath
        self.state.currentNode = self.loadRootNode()
        if type(self.afterNodeChanged) == "function" then
            self.afterNodeChanged()
        end
        if type(self.invalidateForm) == "function" then
            self.invalidateForm()
        end
        self:_sync()
    end

    return self.state.currentNode
end

function controller:openRoot()
    if type(self.closeNode) == "function" then
        self.closeNode(self.state.currentNode)
    end
    if type(self.setPageDirty) == "function" then
        self.setPageDirty(false)
    end
    self.state.pathStack = {}
    self.state.currentNodeSource = self.menuRootPath
    self.state.currentNode = type(self.loadRootNode) == "function" and self.loadRootNode() or nil
    if type(self.afterNodeChanged) == "function" then
        self.afterNodeChanged()
    end
    if type(self.invalidateForm) == "function" then
        self.invalidateForm()
    end
    self:_sync()
    return self.state.currentNode
end

function controller:enterItem(index, item, breadcrumb)
    local key
    local opts

    if type(item) ~= "table" then
        return nil
    end

    if type(self.setSelectedIndex) == "function" then
        self.setSelectedIndex(self.state.currentNodeSource, index)
    end
    self.state.pathStack[#self.state.pathStack + 1] = {
        source = self.state.currentNodeSource,
        breadcrumb = self.state.currentNode and self.state.currentNode.breadcrumb or nil
    }

    if item.kind == "page" and type(self.showLoader) == "function" then
        self.showLoader({
            kind = "progress",
            title = item.title or item.id or "Loading",
            message = "Loading values.",
            closeWhenIdle = false,
            focusMenuOnClose = true,
            modal = true
        })
    end

    if item.kind == "menu" and type(item.source) == "string" then
        self.state.currentNodeSource = item.source
        self.state.currentNode = type(self.loadNodeFromSource) == "function" and self.loadNodeFromSource(item.source) or nil
        if type(self.state.currentNode) == "table" then
            self.state.currentNode.breadcrumb = breadcrumb
        end
    elseif item.kind == "page" then
        self.state.currentNodeSource = "page:" .. tostring(item.path or item.id or index)
        self.state.currentNode = type(self.loadPageNode) == "function" and self.loadPageNode(item, breadcrumb) or nil
        if type(self.state.currentNode) == "table" and self.state.currentNode.showLoaderOnEnter == true and type(self.updateLoader) == "function" then
            opts = {}
            for key, value in pairs(self.state.currentNode.loaderOnEnter or {}) do
                opts[key] = value
            end
            opts.title = opts.title or self.state.currentNode.baseTitle or self.state.currentNode.title or item.title or item.id or "Loading"
            self.updateLoader(opts)
        elseif type(self.clearLoader) == "function" then
            self.clearLoader(true)
        end
    else
        self.state.currentNodeSource = "leaf:" .. tostring(item.id or index)
        self.state.currentNode = type(self.makeLeafNode) == "function" and self.makeLeafNode(item, breadcrumb) or nil
    end

    if type(self.setPageDirty) == "function" then
        self.setPageDirty(false)
    end
    if item.kind ~= "menu" and type(self.requestAppFocusRestore) == "function" then
        self.requestAppFocusRestore()
    end
    if type(self.afterNodeChanged) == "function" then
        self.afterNodeChanged()
    end
    if type(self.invalidateForm) == "function" then
        self.invalidateForm()
    end
    self:_sync()
    return self.state.currentNode
end

function controller:goBack()
    local previous = self.state.pathStack[#self.state.pathStack]

    if not previous then
        return false
    end

    if type(self.closeNode) == "function" then
        self.closeNode(self.state.currentNode)
    end
    self.state.pathStack[#self.state.pathStack] = nil
    self.state.currentNodeSource = previous.source
    if previous.source == self.menuRootPath then
        self.state.currentNode = type(self.loadRootNode) == "function" and self.loadRootNode() or nil
    else
        self.state.currentNode = type(self.loadNodeFromSource) == "function" and self.loadNodeFromSource(previous.source) or nil
        if type(self.state.currentNode) == "table" then
            self.state.currentNode.breadcrumb = previous.breadcrumb
        end
    end
    if type(self.setPageDirty) == "function" then
        self.setPageDirty(false)
    end
    if type(self.afterNodeChanged) == "function" then
        self.afterNodeChanged()
    end
    if type(self.invalidateForm) == "function" then
        self.invalidateForm()
    end
    self:_sync()
    return true
end

return controller
