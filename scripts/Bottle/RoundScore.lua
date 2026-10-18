-- 结算中央计分牌：数据只跟随 Board 已播放的分数队列，不参与规则计分。
local UI = require("urhox-libs/UI")
local Plates = require("Machine.LayeredSprites")
local Coin = require("Bottle.CoinIcon")
local Money = require("Bottle.Money")

---@class BottleRoundScore
---@field root Panel
---@field caption Label
---@field number Label
---@field total number
---@field pulseAge number
---@field phase string
---@field layoutScale number
---@field pulseCount integer
---@field plate any
---@field heading Panel
---@field headingCoin BottleCoinIcon
---@field shakeRoot Panel
---@field shakeNumber Label
---@field shakeIcon BottleCoinIcon
---@field shakeTotal number
---@field shakeIdle number
local Score = {}
Score.__index = Score

---@return BottleRoundScore
function Score.New()
    local self = setmetatable({}, Score)
    self:Init()
    return self
end

function Score:Init()
    self.caption = UI.Label {id = "roundScoreCaption", text = "本回合金币", width = 64, height = 22,
        flexShrink = 0,
        fontSize = 12, fontFamily = "pixel", textAlign = "center", fontColor = {255, 255, 255, 255},
        textStroke = {width = 1, color = {0, 0, 0, 255}}, textMotionDisabled = true}
    self.headingCoin = Coin.Widget {width = 18, height = 18, flexShrink = 0, pointerEvents = "none"}
    self.heading = UI.Panel {width = "100%", height = 22, flexDirection = "row", gap = 5,
        alignItems = "center", justifyContent = "center", children = {self.caption, self.headingCoin}}
    self.number = UI.Label {id = "roundScoreValue", text = "+0", width = "100%", height = 64,
        fontSize = 38, fontFamily = "pixel", textAlign = "center", verticalAlign = "middle",
        fontColor = {255, 255, 255, 255}, textStroke = {width = 2, color = {0, 0, 0, 255}},
        transformOrigin = "center", textMotionDisabled = true}
    self.root = UI.Panel {id = "roundScore", position = "absolute", visible = false,
        width = 236, height = 106, padding = 9, gap = 2,
        pointerEvents = "none", zIndex = 7,
        children = {self.heading, self.number}}
    self.shakeIcon = Coin.Widget {id = "shakeCoinIcon", width = 24, height = 24, pointerEvents = "none"}
    self.shakeNumber = UI.Label {id = "shakeCoinValue", text = "×0", width = 74, height = 26,
        fontSize = 16, fontFamily = "pixel", verticalAlign = "middle", fontColor = {255, 255, 255, 255},
        textStroke = {width = 1, color = {0, 0, 0, 255}}, textMotionDisabled = true}
    self.shakeRoot = UI.Panel {id = "shakeCoins", position = "absolute", visible = false,
        left = 12, top = 10, width = 116, height = 36, paddingHorizontal = 8,
        flexDirection = "row", alignItems = "center", gap = 4, pointerEvents = "none", zIndex = 7,
        children = {self.shakeIcon, self.shakeNumber}}
    -- 复用现有金属九宫格资源，在 UI 层绘制，覆盖瓶中物品而不改变机台 3D 深度。
    self.plate = Plates.New()
    ---@param widget Widget
    ---@param vg NVGContextWrapper
    local function RenderPlate(widget, vg)
        local b = widget:GetAbsoluteLayout()
        self.plate:Panel(vg, "metal", b.x, b.y, b.w, b.h, self.layoutScale)
    end
    -- 实例回调接收显式 self；LSP 的绑定方法签名会省略这个参数。
    (self.root --[[@as any]]).Render = RenderPlate;
    (self.shakeRoot --[[@as any]]).Render = RenderPlate
    local destroy = self.root.Destroy
    self.root.Destroy = function(widget)
        self.plate:Dispose()
        destroy(widget)
    end
    self.layoutScale = 0
    self:Reset()
end

function Score:Reset()
    self.total, self.pulseAge, self.phase, self.pulseCount = 0, 1, "", 0
    self.shakeTotal, self.shakeIdle = 0, 0
    self.shakeNumber:SetText("×0")
    self.number:SetText("+0")
    self.number:SetStyle({translateY = 0, scale = 1})
    self.root:Hide()
    self.shakeRoot:Hide()
end

---@param total number
function Score:SetShake(total)
    if total == self.shakeTotal then return end
    self.shakeTotal = total
    self.shakeNumber:SetText("×" .. Money.Format(total))
end

---@param amount number
function Score:Depart(amount)
    self:SetShake(math.max(0, self.shakeTotal - amount))
end

---@param total number
function Score:SetTotal(total)
    if total == self.total then return end
    self.total = total
    self.number:SetText((total >= 0 and "+" or "") .. Money.Format(total))
end

---@param value number
function Score:Add(value)
    if value == 0 then return end
    self:SetTotal(self.total + value)
    self.pulseAge = 0
    self.pulseCount = self.pulseCount + 1
end

---@param phase string
---@param total number 当前回合真实总分，包含提前获得的分数与负收益
---@param pending number 尚未逐件展示的收益之和
---@param uncollected number? 尚未飞入左上角的摇晃收益
---@return number? transfer 初次进入结算时，需要从摇晃计数转入的收益
function Score:Sync(phase, total, pending, uncollected)
    uncollected = uncollected or 0
    ---@type number?
    local transfer
    if phase == "running" then
        if self.phase ~= "running" then self:Reset() end
        self:SetShake(total - uncollected)
        self.shakeRoot:Show()
        self.root:Hide()
    elseif phase == "settle" or phase == "reveal" then
        if self.phase ~= "settle" and self.phase ~= "reveal" then
            transfer = total - (phase == "reveal" and pending or 0) - uncollected
            self:SetTotal(0)
            self:SetShake(transfer)
            self.shakeIdle = 0
            self.shakeRoot:Show()
            if transfer <= 0 then self:SetTotal(transfer); self:SetShake(0); transfer = nil end
        end
        if uncollected > 0 then self.shakeRoot:Show(); self.shakeIdle = 0 end
        self.root:Show()
    else
        if self.phase ~= phase then self:Reset() end
        self.root:Hide()
        self.shakeRoot:Hide()
    end
    self.phase = phase
    return transfer
end

---@param dt number
---@param width number 画布宽度，由 UI 统一处理 DPR
function Score:Update(dt, width)
    local s = math.max(.01, width / 370)
    if self.layoutScale ~= s then
        self.layoutScale = s
        self.root:SetStyle({left = (width - 236 * s) / 2, top = 54 * s,
            width = 236 * s, height = 106 * s, padding = 9 * s, gap = 2 * s})
        self.heading:SetStyle({height = 22 * s, gap = 5 * s})
        self.headingCoin:SetStyle({width = 18 * s, height = 18 * s})
        -- 标题和图标共用固定高度；显式文本宽度避免字体初测/缩放把图标挤到右边。
        self.caption:SetStyle({width = 64 * s, height = 22 * s, fontSize = 12 * s,
            textStroke = {width = s, color = {0, 0, 0, 255}}})
        self.number:SetStyle({fontSize = 38 * s, height = 64 * s,
            textStroke = {width = 2 * s, color = {0, 0, 0, 255}}})
        self.shakeRoot:SetStyle({left = 12 * s, top = 10 * s, width = 116 * s, height = 36 * s,
            paddingHorizontal = 8 * s, gap = 4 * s})
        self.shakeIcon:SetStyle({width = 24 * s, height = 24 * s})
        self.shakeNumber:SetStyle({fontSize = 16 * s, width = 74 * s, height = 26 * s,
            textStroke = {width = s, color = {0, 0, 0, 255}}})
    end
    if self.phase ~= "running" and self.shakeTotal == 0 then
        self.shakeIdle = self.shakeIdle + math.max(0, dt)
        if self.shakeIdle > .4 then self.shakeRoot:Hide() end
    end
    if self.pulseAge >= 1 then return end
    self.pulseAge = math.min(1, self.pulseAge + math.max(0, dt))
    local kick = self.pulseAge < 1 and math.exp(-8 * self.pulseAge) * math.sin(22 * self.pulseAge) or 0
    self.number:SetStyle({translateY = -14 * s * kick, scale = 1 + .38 * kick})
end

return Score
