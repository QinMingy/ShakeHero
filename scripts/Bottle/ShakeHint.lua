-- 首次考核前的常驻操作提示；独立于教程、规则时钟与存档。
local L = require("Machine.LayeredLayout")
local Hint = {}
Hint.TEXT = "摇晃手机/按住瓶子摇晃"
local HEIGHT = 26

---@param game BottleGame
---@return number
function Hint.Reserve(game)
    return game.stage == 1 and game.phase ~= "over" and HEIGHT or 0
end

---@param view any
---@return boolean
function Hint.Visible(view)
    if Hint.Reserve(view.game) == 0 or view.inventoryOpen then return false end
    if view.startScreen and view.startScreen:IsActive() then return false end
    for _, overlay in ipairs({view.modal, view.detailOverlay, view.definitionModal}) do
        if overlay:IsVisible() then return false end
    end
    return true
end

---@param elapsed number
---@return number
function Hint.Opacity(elapsed)
    -- 2.4秒一轮柔和明暗变化，最低仍保持可读，不使用突闪或位移。
    return .78 + .18 * (.5 + .5 * math.cos(elapsed * math.pi * 2 / 2.4))
end

---@param view any
function Hint.Layout(view)
    local m = view.machineSkin
    local reserve, scale = Hint.Reserve(view.game), m.scale
    if m.shakeHintScale == scale and m.shakeHintReserve == reserve
        and view.board.props.height == (L.board[4] - reserve) * scale then return end
    m.shakeHintScale, m.shakeHintReserve = scale, reserve
    -- 仅调整显示视口，瓶图、拾取和详情仍共用Board原来的坐标变换；物理世界不变。
    view.board:SetStyle(L.Style({L.board[1], L.board[2], L.board[3], L.board[4] - reserve}, scale))
    m.shakeHint:SetStyle(L.Style({L.board[1] + 8, L.board[2] + L.board[4] - HEIGHT,
        L.board[3] - 16, HEIGHT}, scale))
    m.shakeHint:SetStyle({fontSize = 10.5 * scale,
        textShadow = {offsetX = scale, offsetY = scale, blur = 0, color = {12, 19, 16, 255}}})
end

---@param view any
function Hint.Sync(view)
    Hint.Layout(view)
    local label = view.machineSkin.shakeHint
    local visible = Hint.Visible(view)
    if label:IsVisible() ~= visible then label:SetVisible(visible) end
end

---@param view any
function Hint.Attach(view)
    local UI = require("urhox-libs/UI")
    local theme = require("Bottle.Theme")
    local label = UI.Label {id = "shakeHint", text = Hint.TEXT,
        fontFamily = "sans", fontColor = theme.colors.textSecondary,
        textMotionDisabled = true, whiteSpace = "nowrap", maxLines = 1,
        textAlign = "center", verticalAlign = "middle", padding = 0,
        pointerEvents = "none", zIndex = 22, opacity = Hint.Opacity(0)}
    local elapsed = 0.0
    local update = label.Update
    function label:Update(dt)
        if update then update(self, dt) end
        Hint.Sync(view)
        if not self:IsVisible() then return end
        elapsed = (elapsed + math.max(0, dt)) % 2.4
        local opacity = math.floor(Hint.Opacity(elapsed) * 255 + .5) / 255
        if self.props.opacity ~= opacity then self:SetStyle({opacity = opacity}) end
    end
    view.machineSkin.shakeHint = label
    view.container:AddChild(label)
    Hint.Sync(view)
    print("[操作提示] 已添加瓶下提示，首次考核后隐藏")
end

return Hint
