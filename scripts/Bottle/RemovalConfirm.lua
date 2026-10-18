-- Independent confirmation layer: preserve the inventory sandbox and its physical poses.
local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Art = require("Bottle.Art")
local Audio = require("Bottle.Audio")
local Sprites = require("Machine.LayeredSprites")
---@type any
local Confirm = {}
Confirm.__index = Confirm
local ink = {226, 214, 174, 255}
local muted = {179, 176, 145, 255}
local clear = {0, 0, 0, 0}

local function Stop(event)
    if event then event:StopPropagation() end
end

local function Owned(game, uid)
    local item = game:Get(uid)
    if not item or (item.location ~= "deck" and item.location ~= "bottle") then return nil end
    for _, entry in ipairs(game.deck) do
        if entry == item then return item end
    end
    return nil
end

function Confirm.New(view, idPrefix)
    local self = setmetatable({}, Confirm)
    self:Init(view, idPrefix)
    return self
end

function Confirm:Init(view, idPrefix)
    self.view = view
    self.idPrefix = idPrefix or "removalConfirm"
    self.sprites = Sprites.New()
    self.scale = 1
    ---@type table?
    self.session = nil
    ---@type any
    self.card = nil
    self.overlay = UI.Panel {id = self.idPrefix .. "Overlay", position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%", visible = false,
        zIndex = 36, pointerEvents = "auto", backgroundColor = {0, 0, 0, 170},
        onPointerDown = Stop, onPointerUp = Stop,
        onClick = function(widget, event)
            Stop(event)
            if not event or (event.target == widget and event:IsPrimaryButton()) then self:Close() end
        end}
    local update = self.overlay.Update
    self.overlay.Update = function(widget, dt)
        if update then update(widget, dt) end
        self:Update()
    end
    local destroy = self.overlay.Destroy
    self.overlay.Destroy = function(widget)
        self:Close()
        self.sprites:Dispose()
        destroy(widget)
    end
    view.container:AddChild(self.overlay)
end

function Confirm:IsOpen()
    return self.session ~= nil and self.overlay:IsVisible()
end

function Confirm:Valid(session)
    local view, game = self.view, session.game
    if session.kind == "message" then
        return session.active and self.session == session and view.game == game
            and game.revision == session.revision and session.isValid()
    end
    return session.active and self.session == session and view.game == game
        and view.deckSim == session.sim and session.sim ~= nil
        and view.inventoryOpen and view.inventoryTab == "items" and view.modal:IsVisible()
        and (game.phase == "prepare" or game.phase == "draft" or game.phase == "over")
        and game.revision == session.revision and (game.removals or 0) > 0
        and Owned(game, session.uid) == session.item
end

function Confirm:Close()
    if self.session then self.session.active = false end
    self.session = nil
    self.overlay:Hide()
end

-- Buttons belong to one opening. An old click callback cannot confirm a later item.
function Confirm:Button(id, text, kind, callback)
    local button = Audio.Button {id = id, text = text, flexGrow = 1, flexBasis = 0,
        minWidth = 0, textMotionDisabled = true, padding = 0, borderWidth = 0,
        boxShadow = false, hoverBoxShadow = false, pressedBoxShadow = false,
        disabledBoxShadow = false, backgroundColor = clear,
        hoverBackgroundColor = {226, 214, 174, 20}, pressedBackgroundColor = {0, 0, 0, 35},
        textColor = ink, onClick = function(_, event) Stop(event); callback() end}
    local render = button.Render
    function button:Render(vg)
        local b = self:GetAbsoluteLayout()
        local pressed = self.state and self.state.pressed and not self.props.disabled
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        if pressed then nvgTranslate(vg, 0, 2 * self.confirm.scale) end
        self.confirm.sprites:Panel(vg, kind, b.x, b.y, b.w, b.h, self.confirm.scale)
        render(self, vg)
        nvgRestore(vg)
    end
    button.confirm = self
    return button
end

---@param uid integer
---@param onConfirm fun(uid:integer)
---@return boolean
function Confirm:Open(uid, onConfirm)
    self:Close()
    local view, game = self.view, self.view.game
    local item = Owned(game, uid)
    if not item or not Items.byId[item.id] or type(onConfirm) ~= "function" then return false end
    local session = {game = game, sim = view.deckSim, item = item, uid = uid,
        revision = game.revision, active = true}
    self.session = session
    if not self:Valid(session) then self:Close(); return false end
    if self.card then self.card:Destroy(); self.overlay:ClearChildren() end

    self.title = UI.Label {id = "removalConfirmTitle", text = "移除这件物品？",
        width = "100%", fontColor = ink, fontWeight = "bold", textMotionDisabled = true,
        textAlign = "center", verticalAlign = "middle", pointerEvents = "none"}
    self.icon = UI.Widget {id = "removalConfirmIcon", flexShrink = 0, pointerEvents = "none"}
    function self.icon:Render(vg)
        local b = self:GetAbsoluteLayout()
        local radius = math.min(b.w, b.h) * .38
        local extent = Art.ItemExtent(item.id, radius, 0, item.woolCount)
        local fitted = extent > radius and radius * radius / extent or radius
        Art.Item(vg, item.id, b.x + b.w / 2, b.y + b.h / 2, fitted, 0, false,
            item.rollValue, item.woolCount)
    end
    self.name = UI.Label {id = "removalConfirmItemName", text = Items.byId[item.id].name,
        width = "100%", fontColor = ink, fontWeight = "bold", textMotionDisabled = true,
        whiteSpace = "normal", pointerEvents = "none"}
    self.uidLabel = UI.Label {text = "持有编号 #" .. uid, width = "100%", fontColor = muted,
        textMotionDisabled = true, pointerEvents = "none"}
    self.hero = UI.Panel {width = "100%", flexDirection = "row", alignItems = "center",
        pointerEvents = "none", children = {self.icon,
            UI.Panel {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 4,
                children = {self.name, self.uidLabel}}}}
    self.cost = UI.Label {id = "removalConfirmCost", text = "消耗1次移除机会",
        width = "100%", textAlign = "center", verticalAlign = "middle",
        fontColor = muted, textMotionDisabled = true, pointerEvents = "none"}
    self.cancel = self:Button("removalConfirmCancel", "取消", "metal", function()
        if self.session == session then self:Close() end
    end)
    self.accept = self:Button("removalConfirmAccept", "确认移除", "green", function()
        if self.session ~= session or not session.active then return end
        local valid = self:Valid(session)
        self:Close()
        if valid then onConfirm(uid) end
    end)
    self.buttons = UI.Panel {width = "100%", flexDirection = "row", children = {self.cancel, self.accept}}
    self.card = UI.Panel {id = "removalConfirmCard", position = "absolute", pointerEvents = "auto",
        justifyContent = "space-between", onClick = function(_, event) Stop(event) end,
        children = {self.title, self.hero, self.cost, self.buttons}}
    local confirm = self
    function self.card:Render(vg)
        local b = self:GetAbsoluteLayout()
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        confirm.sprites:Panel(vg, "wood", b.x, b.y, b.w, b.h, confirm.scale)
        nvgRestore(vg)
    end
    self.overlay:AddChild(self.card)
    self.lastSize = nil
    self.overlay:Show()
    self:Place()
    return true
end

-- 纯文案确认复用移除物品的遮罩、木底板、按钮和屏幕避让。
function Confirm:OpenMessage(title, message, onConfirm, isValid)
    self:Close()
    local session = {kind = "message", game = self.view.game,
        revision = self.view.game.revision, active = true, isValid = isValid}
    self.session = session
    if not self:Valid(session) then self:Close(); return false end
    if self.card then self.card:Destroy(); self.overlay:ClearChildren() end
    self.title = UI.Label {id = self.idPrefix .. "Title", text = title,
        width = "100%", fontColor = ink, fontWeight = "bold", textMotionDisabled = true,
        textAlign = "center", verticalAlign = "middle", pointerEvents = "none"}
    self.message = UI.Label {id = self.idPrefix .. "Message", text = message,
        width = "100%", whiteSpace = "normal", fontColor = ink,
        textMotionDisabled = true, textAlign = "center", verticalAlign = "middle", pointerEvents = "none"}
    self.cancel = self:Button(self.idPrefix .. "Cancel", "取消", "metal", function()
        if self.session == session then self:Close() end
    end)
    self.accept = self:Button(self.idPrefix .. "Accept", "确认", "green", function()
        if self.session ~= session or not session.active then return end
        local valid = self:Valid(session)
        self:Close()
        if valid then onConfirm() end
    end)
    self.buttons = UI.Panel {width = "100%", flexDirection = "row", children = {self.cancel, self.accept}}
    self.card = UI.Panel {id = self.idPrefix .. "Card", position = "absolute", pointerEvents = "auto",
        justifyContent = "space-between", onClick = function(_, event) Stop(event) end,
        children = {self.title, self.message, self.buttons}}
    local confirm = self
    function self.card:Render(vg)
        local b = self:GetAbsoluteLayout()
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        confirm.sprites:Panel(vg, "wood", b.x, b.y, b.w, b.h, confirm.scale)
        nvgRestore(vg)
    end
    self.overlay:AddChild(self.card)
    self.lastSize = nil
    self.overlay:Show()
    self:Place()
    return true
end

function Confirm:Place()
    local view = self.view
    local bounds = view:NoteBounds()
    local parent = view.container:GetAbsoluteLayout()
    local camera = view.container.props
    local x, y = bounds.x - parent.x, bounds.y - parent.y
    local tx, ty = -(camera.translateX or 0), -(camera.translateY or 0)
    local p = self.overlay.props
    if p.left ~= x or p.top ~= y or p.width ~= bounds.w or p.height ~= bounds.h
        or p.translateX ~= tx or p.translateY ~= ty then
        self.overlay:SetStyle({left = x, top = y, width = bounds.w, height = bounds.h,
            translateX = tx, translateY = ty})
    end
    local s = math.max(.01, math.min(view.machineSkin.scale, bounds.w / 370, bounds.h / 260))
    local key = string.format("%.6f:%.6f:%.6f", s, bounds.w, bounds.h)
    if self.lastSize == key then return end
    self.scale, self.lastSize = s, key
    local isMessage = self.session and self.session.kind == "message"
    local width, height = math.min(340 * s, bounds.w - 16 * s), (isMessage and 216 or 236) * s
    self.card:SetStyle({left = math.floor((bounds.w - width) / 2 + .5),
        top = math.floor((bounds.h - height) / 2 + .5), width = width, height = height,
        padding = 16 * s, gap = 10 * s})
    self.title:SetStyle({fontSize = 22 * s, height = 28 * s})
    if isMessage then
        self.message:SetStyle({fontSize = 20 * s, height = 72 * s})
    else
        self.hero:SetStyle({height = 72 * s, gap = 10 * s})
        self.icon:SetStyle({width = 64 * s, height = 64 * s})
        self.name:SetStyle({fontSize = 20 * s})
        self.uidLabel:SetStyle({fontSize = 13 * s})
        self.cost:SetStyle({fontSize = 16 * s, height = 22 * s})
    end
    self.buttons:SetStyle({height = 44 * s, gap = 10 * s})
    self.cancel:SetStyle({height = 44 * s, fontSize = 16 * s})
    self.accept:SetStyle({height = 44 * s, fontSize = 16 * s})
end

function Confirm:Update()
    if not self.session then return end
    if not self:Valid(self.session) then self:Close(); return end
    self:Place()
end

return Confirm
