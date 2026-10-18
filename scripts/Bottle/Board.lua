-- 瓶内画布：真实姿态绘制、输入与纯表现动效。由 View 构建，UI 统一管理缩放/DPR。
local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Art = require("Bottle.Art")
local SoftView = require("Bottle.SoftView")
local PopIn = require("Bottle.PopIn")
local GameAudio = require("Bottle.Audio")
local RoundScore = require("Bottle.RoundScore")
local CoinPickup = require("Bottle.CoinPickup")
local TriggerFeedback = require("Bottle.TriggerFeedback")
local ConsumeFlash = require("Bottle.ConsumeFlash")
---@type table<string, RGBAColor>
local C = (require("Bottle.Theme") --[[@as any]]).colors

---摇晃与结算阶段统称“进行中”：禁止拾取、弹层与牌库操作。
---@param game BottleGame
---@return boolean
local function Busy(game)
    return game.phase == "running" or game.phase == "settle" or game.phase == "reveal"
end

-- 从顶部开始顺时针排列，初始化一次，避免每个物品每帧重复计算三角函数。
local COOLDOWN_SEGMENTS = 24
---@type {x:number,y:number}[]
local cooldownDirections = {}
for segment = 1, COOLDOWN_SEGMENTS do
    local angle = -math.pi / 2 + (segment - 1) * math.pi * 2 / COOLDOWN_SEGMENTS
    cooldownDirections[segment] = {x = math.cos(angle), y = math.sin(angle)}
end

-- 收益浮字：白色填充 + 8方向黑色描边（描边厚约2设计单位，随弹出缩放一起变化）。
---@type {x:number,y:number}[]
local SCORE_OUTLINE = {
    {x = -2, y = -2}, {x = 0, y = -2}, {x = 2, y = -2},
    {x = -2, y = 0}, {x = 2, y = 0},
    {x = -2, y = 2}, {x = 0, y = 2}, {x = 2, y = 2},
}

-- 收益浮字存活时长（秒），与结算展示阶段 reveal 的停顿一致，保证玩家看清分数。
local PARTICLE_LIFETIME = 2.0

-- 结算浮字逐个弹出（用户要求：结算页面逐个结算，看得更清楚）：
-- 分数事件先入队，reveal 阶段按间隔逐一释放。节拍常量放在 Game 中，
-- 与 reveal 阶段时长（队列 + 2秒停顿）共用，避免两边漂移。

-- 字号与字数挂钩（用户要求）："+N"为最少字数并使用最小字号；再大两号。
local SCORE_FONT_BASE = 26
local SCORE_FONT_PER_CHAR = 6
local SCORE_FONT_MAX = 68

-- 收益浮字弹出用的欠阻尼回弹：0 → 放大过冲（约1.25）→ 缩小回摆 → 稳定到1。
-- 不截断时间，衰减在约1.4秒内收敛；比旧参数（0.32秒内结束）更明显、更慢。
---@param age number
---@return number
local function popScale(age)
    return 1 - math.exp(-4 * age) * math.cos(9 * age)
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param radius number
---@param color RGBAColor
---@param alpha? number
local function PixelFrame(vg, x, y, radius, color, alpha)
    nvgBeginPath(vg)
    nvgRect(vg, x - radius, y - radius, radius * 2, 2)
    nvgRect(vg, x - radius, y + radius - 2, radius * 2, 2)
    nvgRect(vg, x - radius, y - radius, 2, radius * 2)
    nvgRect(vg, x + radius - 2, y - radius, 2, radius * 2)
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], alpha or color[4]))
    nvgFill(vg)
end

-- 气球破裂专属：两道离散像素圆环＋径向短刺，不复用普通价值方框。
local function BurstRing(vg, x, y, radius, progress)
    local fade = math.max(0, 1 - progress)
    local pixel = math.max(2, math.floor(radius * .10))
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    for layer = 1, 2 do
        local ringRadius = radius * (1 + progress * (layer == 1 and 1.2 or .7))
        nvgBeginPath(vg)
        for segment, direction in ipairs(cooldownDirections) do
            local px = math.floor(x + direction.x * ringRadius - pixel / 2)
            local py = math.floor(y + direction.y * ringRadius - pixel / 2)
            nvgRect(vg, px, py, pixel, pixel)
            if layer == 1 and segment % 3 == 1 and progress < .55 then
                nvgRect(vg, math.floor(px + direction.x * pixel * 2),
                    math.floor(py + direction.y * pixel * 2), pixel, pixel)
            end
        end
        nvgFillColor(vg, layer == 1 and nvgRGBA(255, 242, 205, math.floor(255 * fade))
            or nvgRGBA(250, 128, 153, math.floor(220 * fade)))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

-- 保镖护盾纯表现：沿用当前UI传入的NanoVG context，不参与碰撞/目标判断。
-- 透明底泡泡配像素轮廓，跟随实例真实姿态；清盾后即消失，不保存到结算残影。
local function ShieldBubble(vg, x, y, radius)
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgCircle(vg, x, y, radius)
    nvgFillColor(vg, nvgRGBA(126, 212, 235, 24))
    nvgFill(vg)
    nvgShapeAntiAlias(vg, 0)
    local pixel = math.max(1, math.min(3, radius * .09))
    nvgBeginPath(vg)
    for _, direction in ipairs(cooldownDirections) do
        nvgRect(vg, math.floor(x + direction.x * radius - pixel / 2),
            math.floor(y + direction.y * radius - pixel / 2), pixel, pixel)
    end
    nvgFillColor(vg, nvgRGBA(167, 233, 247, 164))
    nvgFill(vg)
    nvgBeginPath(vg)
    nvgRect(vg, x - radius * .55, y - radius * .6, pixel * 2, pixel)
    nvgRect(vg, x - radius * .65, y - radius * .5, pixel, pixel * 2)
    nvgFillColor(vg, nvgRGBA(236, 255, 255, 180))
    nvgFill(vg)
    nvgRestore(vg)
end

---@class BottleRewardPopup
---@field uid number
---@field value number
---@field x number
---@field y number
---@field age number
---@field trigger string?
---@field rewardKind string?
---@field lift number?

---@class BottleBoard : Widget
---@field layered boolean?
---@field game BottleGame
---@field physics BottlePhysics
---@field shake fun(dx:number,dy:number)
---@field shakePressId number
---@field inspect fun(uid:integer)
---@field selectedUid integer
---@field inspectPress boolean
---@field clickMoved boolean
---@field pressX number
---@field pressY number
---@field physicsButton Button
---@field physicsMenu Panel
---@field pointerId number
---@field lastPanX number
---@field lastPanY number
---@field ppu number
---@field visualX number
---@field visualY number
---@field particles BottleRewardPopup[]
---@field scoreQueue BottleRewardPopup[] 待逐个弹出的结算浮字
---@field scorePopTimer number
---@field scorePopInterval number? 本次reveal固定节拍，按Game统计初始总收益事件计算
---@field scorePopRevealing boolean
---@field displayScore number? 结算展示期间逐件递增的顶部滚轮暂显值；nil 时显示真实余额
---@field roundScore BottleRoundScore 当前回合逐件累计，与顶部总余额分开显示
---@field coinPickups BottleCoinPickup
---@field coinsInFlight number 已发射、尚未抵达的金币收益
---@field shakeCoinsInFlight number 即时收益中尚未抵达左上角的部分
---@field isPaused (fun():boolean)? 主菜单覆盖时与玩法一起暂停表现
---@field pulses table<number,number>
---@field residue table<number,{id:string,x:number,y:number,angle:number,radius:number,rollValue:number?,woolCount:number?,soft:BottleSoftPose[]?}> 结算残留：物品回牌库后保留的最后姿态
---@field pops BottlePopPose[] 出现弹跳动效；按 uid 查表的 popByUid 与其同步维护
---@field popByUid table<number,BottlePopPose?>
---@field bursts BottlePopParticle[] 入场/爆炸的重力像素粒子（瓶内米制坐标）
---@field burstRings {uid:number,x:number,y:number,radius:number,age:number,life:number}[] 气球专属爆炸环
---@field explodedUids table<number,boolean> 已爆气球不得由同批score重建残留
---@field inflations table<number,BottleInflation> 气球平滑膨胀，终点保持实例永久尺寸
---@field presentUids table<number,boolean> 上一帧瓶内成员，用于差量触发出现动效
---@field consumeFlash BottleConsumeFlash
---@overload fun(props:WidgetProps): BottleBoard
local Board = UI.Widget:Extend("BottleBoard") --[[@as BottleBoard]]

function Board:Init(props)
    UI.Widget.Init(self, props)
    self.game = props.game
    self.physics = props.physics
    self.shake = props.shake
    self.inspect = props.inspect
    self.ppu = 50
    self.pointerId, self.lastPanX, self.lastPanY = -1, 0, 0
    self.shakePressId = -1
    self.selectedUid, self.inspectPress, self.clickMoved = 0, false, false
    self.pressX, self.pressY = 0, 0
    self.visualX, self.visualY = 0, 0
    self.roundScore = RoundScore.New()
    self:AddChild(self.roundScore.root)
    self:AddChild(self.roundScore.shakeRoot)
    self.coinPickups = CoinPickup {id = "coinPickups", position = "absolute",
        left = 0, top = 0, width = "100%", height = "100%", pointerEvents = "none", zIndex = 8}
    self:AddChild(self.coinPickups)
    self.consumeFlash = ConsumeFlash.New()
    self:ResetEffects()
    self:ResetPopState()
end

function Board:ResetEffects()
    if self.consumeFlash then self.consumeFlash:Reset() end
    -- residue：结算后物品已回牌库、刚体被移除，但仍按最后姿态保留绘制；
    -- 新回合重摆布局（prepare/running/settle 相位切换或换回合）时才清空。
    self.particles, self.pulses, self.residue = {}, {}, {}
    self.scoreQueue, self.scorePopTimer = {}, 0
    self.scorePopInterval, self.scorePopRevealing = nil, false
    self.displayScore = nil
    self.coinPickups:Reset()
    self.coinsInFlight = 0
    self.shakeCoinsInFlight = 0
    self.roundScore:Reset()
    self.bursts, self.burstRings, self.explodedUids, self.inflations = {}, {}, {}, {}
end

-- 物理刚体在 Sync 后已是新尺寸，残留也只保存最终尺寸；动画仅覆盖绘制半径。
---@param uid number
---@param fallback number
---@return number
function Board:VisualRadius(uid, fallback)
    local inflation = self.inflations[uid]
    return inflation and inflation.radius or fallback
end

function Board:ResetPopState()
    -- 换局/读档后成员差量从零开始：瓶内物品按新局重新错峰出现。
    -- 不并入 ResetEffects——阶段切换（如 prepare→running）只是清表现残留，
    -- 同一批瓶内物品不能因此被误判为新出现而重复弹跳/响音。
    self.pops, self.popByUid, self.presentUids = {}, {}, {}
end

function Board:ResetShake()
    self.state.dragging = false
    self.pointerId, self.shakePressId = -1, -1
    self.visualX, self.visualY = 0, 0
    self.physics:ResetMotion()
end

---@param event GestureEvent
---@return boolean
function Board:OnPanStart(event)
    self.clickMoved = true
    -- 手势只能归属于画布，菜单/按钮起拖不冒泡成摇瓶；第二指不抢占。
    if event.target ~= self or self.shakePressId ~= event.pointerId or self.state.dragging
        or self.game.phase ~= "running"
        or not self:HitTest(event.x, event.y)
        or (self.physicsMenu and self.physicsMenu:IsVisible())
        or (self.physicsButton and self.physicsButton:HitTest(event.x, event.y)) then return false end
    self.state.dragging = true
    self.pointerId = event.pointerId
    self.lastPanX = event.totalDeltaX - event.deltaX
    self.lastPanY = event.totalDeltaY - event.deltaY
    self.physics:BeginShake()
    return true
end

---@param pointerId number
function Board:ReleaseShake(pointerId)
    if pointerId ~= self.pointerId and pointerId ~= self.shakePressId then return end
    self.inspectPress, self.clickMoved = false, true
    if pointerId == self.shakePressId then self.shakePressId = -1 end
    if pointerId ~= self.pointerId then return end
    self.state.dragging = false
    self.pointerId, self.shakePressId = -1, -1
    self.lastPanX, self.lastPanY = 0, 0
    -- 保留当前位置和速度，由已有临界阻尼跟随平滑回中。
    self.physics:EndShake()
end

---@param event GestureEvent
function Board:OnPanEnd(event)
    self:ReleaseShake(event.pointerId)
end

---@param event PointerEvent
function Board:OnPointerLeave(event)
    UI.Widget.OnPointerLeave(self, event)
    self:ReleaseShake(event.pointerId)
end

---@param event PointerEvent
function Board:OnPointerCancel(event)
    self:ReleaseShake(event.pointerId)
end

function Board:OnPanMove(event)
    if not self.state.dragging or event.pointerId ~= self.pointerId or self.game.phase ~= "running" then return end
    -- 触摸没有 hover leave；越界手势同样结束，且不把越界的最后一段位移加进目标。
    if not self:HitTest(event.x, event.y) then self:ReleaseShake(event.pointerId); return end
    if self.physics.mode == 2 then
        -- 使用累计位移差，合并/高频事件不会增加冲量；超大位移由瓶子摆幅限幅。
        local dx, dy = event.totalDeltaX - self.lastPanX, event.totalDeltaY - self.lastPanY
        self.lastPanX, self.lastPanY = event.totalDeltaX, event.totalDeltaY
        self.shake(dx / self.ppu, -dy / self.ppu)
    else
        -- 物理一的分量限幅、增益和视觉反馈均保留原版。
        local dx = math.max(-.6, math.min(.6, event.deltaX / self.ppu))
        local dy = math.max(-.6, math.min(.6, -event.deltaY / self.ppu))
        self.shake(dx, dy)
        self.visualX = math.max(-12, math.min(12, self.visualX + event.deltaX * .14))
        self.visualY = math.max(-8, math.min(8, self.visualY + event.deltaY * .1))
    end
end

--- 队列和限流中的批次均须播完，主循环才可结束结算展示。
---@return boolean
function Board:CoinPickupsBusy()
    return #self.scoreQueue > 0 or self.coinPickups:Busy()
end

---@param amount number
---@param x number 370宽设计坐标
---@param y number
---@param source string
function Board:LaunchCoins(amount, x, y, source)
    if amount <= 0 then return end
    local l = self:GetAbsoluteLayout()
    local scale = math.max(.01, l.w / 370)
    if source == "running" then
        self.shakeCoinsInFlight = self.shakeCoinsInFlight + amount
    else
        self.coinsInFlight = self.coinsInFlight + amount
    end
    self.coinPickups:Burst(amount, x, y, source, l.h / scale)
end

---@param popup BottleRewardPopup
---@param source string
function Board:LaunchRewardCoins(popup, source)
    local l = self:GetAbsoluteLayout()
    local x, y, ppu = self:GetBottleTransform()
    local scale = math.max(.01, l.w / 370)
    self:LaunchCoins(popup.value, (x - l.x + popup.x * ppu) / scale,
        (y - l.y - popup.y * ppu) / scale, source)
end

function Board:Update(dt)
    if self.isPaused and self.isPaused() then return end
    if self.consumeFlash then self.consumeFlash:Update(dt) end
    local l = self:GetAbsoluteLayout()
    local phase = self.game.phase
    local previousPhase = self.roundScore.phase
    ---@type number
    local pendingScore = 0
    if self.game.phase == "reveal" then
        for _, pending in ipairs(self.scoreQueue) do pendingScore = pendingScore + pending.value end
    end
    local transfer = self.roundScore:Sync(self.game.phase, self.game.roundScore, pendingScore,
        self.shakeCoinsInFlight)
    if transfer then self:LaunchCoins(transfer, 32, 28, "shake") end
    if phase == "reveal" and previousPhase ~= "reveal" then
        -- 负收益没有飞币；在揭示开始时补入，避免吞掉负值或重复计算提前收益。
        self.roundScore:Add(self.game.roundScore - pendingScore
            - self.roundScore.total - self.coinsInFlight - self.shakeCoinsInFlight)
    elseif phase ~= "running" and phase ~= "settle" and phase ~= "reveal" then
        self.displayScore = nil
        self.coinPickups:Reset()
        self.coinsInFlight = 0
        self.shakeCoinsInFlight = 0
    end
    for uid, inflation in pairs(self.inflations) do
        if PopIn.StepInflation(inflation, dt) then self.inflations[uid] = nil end
    end
    for index = #self.burstRings, 1, -1 do
        local ring = self.burstRings[index]
        ring.age = ring.age + math.max(0, dt)
        if ring.age >= ring.life then table.remove(self.burstRings, index) end
    end
    if self.physics.mode == 2 then
        -- 视觉摆幅与惯性来自同一个瓶子运动，不再独立回弹造成拖拽错觉。
        self.visualX = self.physics.motion.x * self.ppu
        self.visualY = -self.physics.motion.y * self.ppu
    else
        self.visualX = self.visualX * math.exp(-dt * 12)
        self.visualY = self.visualY * math.exp(-dt * 12)
    end
    if self.physicsButton and self.physicsButton.parent==self and l.w > 0 and l.h > 0 then
        local ppu = math.max(1, math.min((l.w - 34) / 5.6, (l.h - 38) / 7.1))
        local left = math.max(0, l.w / 2 - 2.4 * ppu - 48)
        local top = math.max(0, l.h / 2 - 3.2 * ppu - 48)
        -- 选择器向左上避让瓶口，不跟随摆动，避免遮挡瓶子或逃离手指。
        if self.physicsButton.props.left ~= left or self.physicsButton.props.top ~= top then
            self.physicsButton:SetStyle({left = left, top = top})
            self.physicsMenu:SetStyle({left = left, top = top + 46})
        end
    end
    for i = #self.particles, 1, -1 do
        local p = self.particles[i]
        p.age = p.age + dt
        if p.age > PARTICLE_LIFETIME then table.remove(self.particles, i) end
    end
    for uid, age in pairs(self.pulses) do
        local nextAge = age + dt
        if nextAge > .45 then self.pulses[uid] = nil else self.pulses[uid] = nextAge end
    end
    -- 入reveal只计算一次：分母是Game记录的初始总事件数，不随剩余队列递减而放慢。
    if self.game.phase == "reveal" then
        if not self.scorePopRevealing then
            local count = math.max(1, self.game._revealPopCount or #self.scoreQueue)
            self.scorePopInterval = math.min(self.game.REVEAL_SCORE_INTERVAL,
                math.max(self.game.REVEAL_SCORE_MIN_INTERVAL, self.game.REVEAL_SCORE_BUDGET / count))
            self.scorePopRevealing = true
            self.scorePopTimer = 0
        end
    else
        self.scorePopInterval, self.scorePopRevealing = nil, false
    end
    -- 结算浮字逐个弹出：分数事件已入队，reveal 阶段按间隔逐件释放。
    -- running/settle时保留即时收益，不能在下一帧丢掉；离开展示后才清空。
    if #self.scoreQueue > 0 then
        if self.game.phase == "reveal" then
            self.scorePopTimer = self.scorePopTimer - dt
            local interval = self.scorePopInterval or self.game.REVEAL_SCORE_INTERVAL
            while #self.scoreQueue > 0 and self.scorePopTimer <= 0 do
                local pending = table.remove(self.scoreQueue, 1)
                pending.age = 0
                self.particles[#self.particles + 1] = pending
                -- 顶部滚轮随每件浮字逐步增加（用户要求）：暂显值先停在结算前，
                -- 每弹出一件加上该件收益，滚轮因此分多次滚动而不是一次跳到最终值。
                if self.displayScore ~= nil then
                    self.displayScore = self.displayScore + pending.value
                end
                self:LaunchRewardCoins(pending, "item")
                -- 每弹出一件结算浮字播放一次出现音效；音调阶梯由队列起点重置后逐件升高。
                GameAudio.Pop()
                self.scorePopTimer = self.scorePopTimer + interval
            end
        elseif self.game.phase ~= "settle" and self.game.phase ~= "running" then
            self.scoreQueue, self.scorePopTimer = {}, 0
            self.displayScore = nil
        end
    end
    local scale = math.max(.01, l.w / 370)
    local target = self.roundScore.number:GetAbsoluteLayout()
    if target.w > 0 and target.h > 0 then
        self.coinPickups.targetX = (target.x + target.w / 2 - l.x) / scale
        self.coinPickups.targetY = (target.y + target.h / 2 - l.y) / scale
    end
    local shakeTarget = self.roundScore.shakeIcon:GetAbsoluteLayout()
    if shakeTarget.w > 0 and shakeTarget.h > 0 then
        self.coinPickups.shakeTargetX = (shakeTarget.x + shakeTarget.w / 2 - l.x) / scale
        self.coinPickups.shakeTargetY = (shakeTarget.y + shakeTarget.h / 2 - l.y) / scale
    end
    ---@type number
    local collectedAfterShake = 0
    self.coinPickups:Step(dt, function(amount, source)
        if source == "shake" then self.roundScore:Depart(amount) end
    end, function(amount, source)
        if source == "running" then
            self.shakeCoinsInFlight = self.shakeCoinsInFlight - amount
            self.roundScore:SetShake(self.roundScore.shakeTotal + amount)
            if phase ~= "running" then collectedAfterShake = collectedAfterShake + amount end
        else
            self.coinsInFlight = self.coinsInFlight - amount
            self.roundScore:Add(amount)
        end
    end)
    -- 末帧的即时收益仍先入左上角，再转入结算；回调结束后发射，避免新金币在同帧被推进两次。
    if collectedAfterShake > 0 then self:LaunchCoins(collectedAfterShake, 32, 28, "shake") end
    if phase == "reveal" and not self:CoinPickupsBusy() then
        self.coinsInFlight = 0
        self.roundScore:SetTotal(self.game.roundScore)
        if self.displayScore ~= nil then self.displayScore = self.game.score end
    end
    self.roundScore:Update(dt, l.w)
    -- 出现动效：以瓶内成员差量识别新入瓶的物品，按 uid 顺序错峰弹跳出现。
    -- 纯表现层，不触碰规则、随机数或物理；刚体由主循环的 Sync 保证已就绪。
    local present = {}
    for _, item in ipairs(self.game:BottleItems()) do present[item.uid] = true end
    for i = #self.pops, 1, -1 do
        if not present[self.pops[i].uid] then table.remove(self.pops, i) end
    end
    ---@type integer[]
    local appeared = {}
    for uid in pairs(present) do
        if not self.presentUids[uid] then appeared[#appeared + 1] = uid end
    end
    table.sort(appeared)
    if #appeared > 0 then
        -- 每批出现从最低音起逐件升高（用户要求：音调从低到高）。
        GameAudio.ResetPopPitch()
    end
    for index, uid in ipairs(appeared) do
        self.presentUids[uid] = true
        local item = self.game:Get(uid)
        -- 每件按序号独立错峰，不做上限截断（截断会让超出上限的物品同一帧全部出现）。
        local delay = (index - 1) * PopIn.STAGGER
        self.pops[#self.pops + 1] = PopIn.NewPose(uid, item and item.id or "apple", delay)
    end
    self.presentUids = present
    self.popByUid = {}
    for i = #self.pops, 1, -1 do
        local pop = self.pops[i]
        self.popByUid[pop.uid] = pop
        local activated = PopIn.Step(pop, dt)
        if activated then
            -- 激活帧迸发粒子并播放占位出现音；种子由 uid 与 revision 派生，
            -- 同件物品重抽/新回合重新入瓶时粒子外观不同，且不占用玩法随机序列。
            -- 只用乘法与取模混种：revision 从存档恢复后可能是浮点，位运算会报错。
            local burstX, burstY = self.physics:GetPose(pop.uid)
            if pop.x ~= nil and pop.y ~= nil then burstX, burstY = pop.x, pop.y end
            local seed = pop.uid * 104729 + (self.game.revision % 1000003) * 999983
            for _, particle in ipairs(PopIn.Burst(burstX, burstY, pop.id, seed)) do
                self.bursts[#self.bursts + 1] = particle
            end
            GameAudio.Pop()
        end
        if pop.age > PopIn.POP_WINDOW then table.remove(self.pops, i) end
    end
    PopIn.StepParticles(self.bursts, dt)
end

-- 同一物品同一步可同时产金币和永久价值，错开文字以保留两种真实收益。
---@param popup BottleRewardPopup
function Board:AddRewardPopup(popup)
    local lane = 0
    for _, active in ipairs(self.particles) do
        if active.uid == popup.uid and (active.age or 0) < .12 then lane = lane + 1 end
    end
    popup.age, popup.lift = 0, lane * 30
    self.particles[#self.particles + 1] = popup
end

---@param events GameEvent[]
function Board:Effects(events)
    -- 本批结算浮字插入队列前的长度：批结束时据此设置滚轮暂显起点与音调阶梯。
    local queueStart = #self.scoreQueue
    ---@type table<number,{x:number,y:number}>
    local origins = {}
    for _, event in ipairs(events) do
        if (event.kind == "spawn" or event.kind == "merge") and event.x ~= nil and event.y ~= nil then
            origins[event.uid] = {x = event.x, y = event.y}
        end
        -- Effects 在物理同步删除实体之前读取事件位置；同一步生成后又消耗的物品
        -- 可能没有刚体，必须用事件 x/y，绝不让 GetPose 的缺失默认值变成瓶中浮字。
        local x, y = event.x, event.y
        if (x == nil or y == nil) and event.uid and self.physics.bodies[event.uid] then
            x, y = self.physics:GetPose(event.uid)
        end
        if event.kind == "consume" then
            if self.consumeFlash then self.consumeFlash:Capture(event, self.physics, origins[event.uid]) end
        elseif event.kind == "score" and event.uid then
            self.pulses[event.uid] = 0
            if (event.value or 0) > 0 and x ~= nil and y ~= nil then
                local popup = {
                    uid = event.uid, value = event.value or 0, x = x, y = y, age = 0,
                    trigger = event.trigger,
                }
                if self.game.phase == "reveal" then
                    self.scoreQueue[#self.scoreQueue + 1] = popup
                else
                    -- 摇晃收益当场跳字并从实际物品位置飞向左上角，抵达后增加计数。
                    self:AddRewardPopup(popup)
                    self:LaunchRewardCoins(popup, "running")
                end
            end
            -- 结算残留：score 事件发出时物品已回牌库（_CleanupRound 已执行），
            -- 刚体要到本步末尾的 physics:Sync 才被移除；此刻捕获最终姿态，
            -- 三选一/结束阶段按原位保留绘制，物体不再随结算完成瞬间消失。
            local item = self.game:Get(event.uid)
            if item and item.location == "deck" and not self.explodedUids[event.uid]
                and self.physics.bodies[event.uid] then
                local poseX, poseY, poseAngle, poseRadius = self.physics:GetPose(event.uid)
                local def = Items.byId[item.id]
                self.residue[event.uid] = {
                    -- 事件批一次性送达时香蕉满3回合转化已在 _Settle 内完成，
                    -- item 是实时实例，取到的 id 即腐烂的香蕉而非转化前图案。
                    id = item.id,
                    x = x ~= nil and x or poseX,
                    y = y ~= nil and y or poseY,
                    angle = poseAngle,
                    radius = def and def.radius * (item.scale or 1) or poseRadius,
                    rollValue = event.rollValue or item.rollValue,
                    woolCount = item.woolCount,
                    soft = self.physics:GetSoftPose(event.uid),
                }
            end
        elseif event.kind == "triggerReward" and event.uid then
            if x ~= nil and y ~= nil and math.abs(event.value or 0) > 1e-9 then
                self.pulses[event.uid] = 0
                self:AddRewardPopup({uid = event.uid, value = event.value or 0, x = x, y = y, age = 0,
                    trigger = event.trigger, rewardKind = event.rewardKind})
            end
        elseif event.kind == "resize" and event.uid and event.id == "balloon" then
            local item = self.game:Get(event.uid)
            local def = Items.byId.balloon
            if item and item.location ~= "discard" and item.location ~= "consumed"
                and not self.explodedUids[event.uid] and self.physics.bodies[event.uid] then
                local _, _, _, oldRadius = self.physics:GetPose(event.uid)
                local targetRadius = def.radius * (event.value or item.scale or 1)
                self.inflations[event.uid] = PopIn.NewInflation(
                    self:VisualRadius(event.uid, oldRadius), targetRadius)
                if self.residue[event.uid] then self.residue[event.uid].radius = targetRadius end
            end
        elseif event.kind == "burst" and event.uid and event.id == "balloon" then
            -- 规则已完成倍率与消耗；这里只取旧刚体位置，爆炸不延迟收益也不加冲量。
            self.explodedUids[event.uid] = true
            self.residue[event.uid], self.inflations[event.uid], self.pulses[event.uid] = nil, nil, nil
            if x ~= nil and y ~= nil then
                local radius = Items.byId.balloon.radius * (event.value or 2)
                self.burstRings[#self.burstRings + 1] = {
                    uid = event.uid, x = x, y = y, radius = radius,
                    age = 0, life = PopIn.EXPLOSION_LIFETIME,
                }
                local seed = event.uid * 104729 + (self.game.revision % 1000003) * 999983 + 7919
                for _, particle in ipairs(PopIn.Explosion(x, y, "balloon", seed, radius)) do
                    self.bursts[#self.bursts + 1] = particle
                end
            end
        elseif event.kind == "remove" and event.uid then
            -- 即时score可能先于remove；弃牌与被消耗实体不得被残留绘制“复活”。
            self.residue[event.uid], self.inflations[event.uid] = nil, nil
        elseif event.kind == "spawn" and event.uid then
            -- 生成/入瓶事件：立即触发出现动效（不参与准备期错峰排队）。
            -- 同一步新实体在 Sync 后才建立刚体，位置沿用事件的 x/y（与 score 同一约定）。
            local pop = PopIn.NewPose(event.uid, event.id or "apple", 0)
            pop.x, pop.y = x, y
            self.presentUids[event.uid] = true
            self.pops[#self.pops + 1] = pop
        end
    end
    -- 一批新结算浮字入队：重置音调阶梯；顶部滚轮从结算前的值起步，
    -- 之后每弹出一件才加上该件收益（用户要求：滚轮逐步增加，而不是一次跳到最终值）。
    if #self.scoreQueue > queueStart and self.displayScore == nil then
        local pending = 0
        for i = queueStart + 1, #self.scoreQueue do
            pending = pending + self.scoreQueue[i].value
        end
        self.displayScore = self.game.score - pending
        GameAudio.ResetPopPitch()
    end
end

-- 绘制、点击拾取和详情锚点共用同一变换，UI 已把物理像素转换为基准像素。
---@return number x
---@return number y
---@return number ppu
function Board:GetBottleTransform()
    local l = self:GetAbsoluteLayout()
    local ppu = math.max(1, math.min((l.w - 34) / 5.6, (l.h - 38) / 7.1))
    self.ppu = ppu
    return l.x + l.w / 2 + self.visualX, l.y + l.h / 2 + 3.2 * ppu + self.visualY, ppu
end

---@param uid integer
---@return {x:number,y:number,w:number,h:number}
function Board:GetItemBounds(uid)
    local x, y, ppu = self:GetBottleTransform()
    local soft = SoftView.Bounds(self.physics, uid, x, y, ppu)
    if soft then return soft end
    local px, py, angle, radius = self.physics:GetPose(uid)
    local item = self.game:Get(uid)
    local extent = Art.ItemExtent(item and item.id or "apple", radius * ppu, -angle,
        item and item.woolCount or nil) + 4
    return {x = x + px * ppu - extent, y = y - py * ppu - extent, w = extent * 2, h = extent * 2}
end

-- 命中示意：点击点 → 逆旋转 → 非透明像素；从最后绘制的物品向前检查。
-- 擦过透明角落视为空白，重叠时只选最上层，不扩大 Box2D 碰撞体。
---@param x number
---@param y number
---@return integer
function Board:PickItem(x, y)
    if Busy(self.game) then return 0 end
    local l = self:GetAbsoluteLayout()
    if x < l.x or x > l.x + l.w or y < l.y or y > l.y + l.h then return 0 end
    local originX, originY, ppu = self:GetBottleTransform()
    local items = self.game:BottleItems()
    for i = #items, 1, -1 do
        local item = items[i]
        local px, py, angle, radius = self.physics:GetPose(item.uid)
        local softHit = item.id == "bacon" and self.physics:ContainsPoint(item.uid,
            (x - originX) / ppu, (originY - y) / ppu)
        if softHit or (item.id ~= "bacon" and Art.HitItem(item.id,
            x - originX - px * ppu, y - originY + py * ppu, radius * ppu, -angle, item.woolCount)) then
            return item.uid
        end
    end
    return 0
end

---@param event PointerEvent
function Board:OnPointerDown(event)
    if self.state.dragging and event.pointerId ~= self.pointerId then return end
    self.shakePressId = (event.target == self and event:IsPrimaryButton()) and event.pointerId or -1
    self.inspectPress = event.isPrimary and event:IsPrimaryButton() and not Busy(self.game) and event.target == self
    self.clickMoved = false
    self.pressX, self.pressY = event.x, event.y
end

---@param event PointerEvent
function Board:OnPointerMove(event)
    if self.state.dragging and event.pointerId == self.pointerId and not self:HitTest(event.x, event.y) then
        self:ReleaseShake(event.pointerId)
    end
    if self.inspectPress then
        local dx, dy = event.x - self.pressX, event.y - self.pressY
        if dx * dx + dy * dy > 64 then self.clickMoved = true end
    end
end

---@param event PointerEvent
function Board:OnPointerUp(event)
    self:OnPointerMove(event)
    if self.state.dragging then
        self:ReleaseShake(event.pointerId)
    elseif event.pointerId == self.shakePressId then
        -- 普通物品点击还需在随后 OnClick 中消费 inspectPress。
        self.shakePressId = -1
    end
end

---@param event PointerEvent?
function Board:OnClick(event)
    if self.physicsMenu and self.physicsMenu:IsVisible() then self.physicsMenu:Hide(); return end
    if not event or not event:IsPrimaryButton() or Busy(self.game)
        or not self.inspectPress or self.clickMoved then return end
    self.inspectPress = false
    event:StopPropagation()
    self.inspect(self:PickItem(event.x, event.y))
end

-- 普通/软体沿用原绘制；只有气球resize在真实尺寸上叠加单调视觉膨胀。
function Board:DrawItem(vg, item, x, y, cooling, outlineWidth)
    local inflation = self.inflations[item.uid]
    if item.id == "balloon" and inflation then
        local px, py, angle = self.physics:GetPose(item.uid)
        if outlineWidth then
            Art.ItemOutline(vg, item.id, x + px * self.ppu, y - py * self.ppu,
                inflation.radius * self.ppu, -angle, item.rollValue, item.woolCount, outlineWidth)
        end
        Art.Item(vg, item.id, x + px * self.ppu, y - py * self.ppu,
            inflation.radius * self.ppu, -angle, cooling)
    else
        if outlineWidth then
            local poses = self.physics:GetSoftPose(item.uid)
            if poses then
                -- 全部白色段先于全部原色段绘制，关节重叠处不产生白色接缝。
                for _, pose in ipairs(poses) do
                    Art.BaconSegmentOutline(vg, x + pose.x * self.ppu, y - pose.y * self.ppu, -pose.angle,
                        pose.halfLength * self.ppu, pose.halfWidth * self.ppu, pose.u0, pose.u1, outlineWidth)
                end
            else
                local px, py, angle, radius = self.physics:GetPose(item.uid)
                Art.ItemOutline(vg, item.id, x + px * self.ppu, y - py * self.ppu,
                    radius * self.ppu, -angle, item.rollValue, item.woolCount, outlineWidth)
            end
        end
        SoftView.Item(vg, self.physics, item, x, y, self.ppu, cooling)
    end
end

function Board:Render(vg)
    local l = self:GetAbsoluteLayout() --[[@as {x:number,y:number,w:number,h:number}]]
    if l.w <= 0 or l.h <= 0 then return end
    local x, y = self:GetBottleTransform()
    nvgSave(vg)
    nvgIntersectScissor(vg, l.x, l.y, l.w, l.h)
    -- 游戏画布走 Widget 渲染，由 UI.Scale.DEFAULT 统一处理 DPR 与输入坐标。
    self:RenderFullBackground(vg)
    if not self.layered then
        local pixel = 24
        nvgBeginPath(vg)
        for gx = math.floor(l.x), math.floor(l.x + l.w), pixel do
            for gy = math.floor(l.y), math.floor(l.y + l.h), pixel do
                nvgRect(vg, gx, gy, 2, 2)
            end
        end
        nvgFillColor(vg, nvgRGBA(C.border[1], C.border[2], C.border[3], 95))
        nvgFill(vg)
        PixelFrame(vg, l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) * .43, C.border, 90)
    end
    Art.Bottle(vg, x, y, self.ppu, self.game.phase == "running")
    for _, item in ipairs(self.game:BottleItems()) do
        local px, py, angle, radius = self.physics:GetPose(item.uid)
        local sx, sy, sr = x + px * self.ppu, y - py * self.ppu, radius * self.ppu
        local def = Items.byId[item.id]
        if self.pulses[item.uid] then
            local age = self.pulses[item.uid]
            PixelFrame(vg, sx, sy, sr + 5 + math.floor(age * 28), C.warning,
                math.floor(180 * (1 - age / .45)))
        end
        -- 厨师本体源表未写冷却，只有持帽时显示遗物明确声明的1秒。
        local hasCooldown = Items.HasCooldown(item.id)
            or (item.id == "chef" and Relics.Has(self.game, "chef_hat"))
        local coolingPhase = self.game.phase == "running" or self.game.phase == "settle"
        local cooling = coolingPhase and hasCooldown and item.remaining > 0
        local pop = self.popByUid and self.popByUid[item.uid] or nil
        -- 错峰等待中的物品保持不可见（含选中框与冷却环），轮到它时才弹跳出现。
        local visible = not pop or pop.delay <= 0
        local outlineWidth = item.uid == self.selectedUid and not Busy(self.game) and 4 or nil
        if visible then
            if pop then
                -- 出现弹跳：绕物品中心缩放＋轻微角回摆，与三选一选中 icon 同一响应形式。
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgScale(vg, math.max(.001, pop.scale), math.max(.001, pop.scale))
                nvgRotate(vg, pop.angle)
                nvgTranslate(vg, -sx, -sy)
                self:DrawItem(vg, item, x, y, cooling, outlineWidth)
                nvgRestore(vg)
                -- 出现瞬间的白色像素环快速扩张淡出，强化“炸出”的第一帧。
                if pop.age < .22 then
                    local t = pop.age / .22
                    PixelFrame(vg, sx, sy, sr + 6 + math.floor(t * 12), { 255, 255, 255, 255 },
                        math.floor(170 * (1 - t)))
                end
            else
                self:DrawItem(vg, item, x, y, cooling, outlineWidth)
            end
        end
        if visible and item.shielded then
            ShieldBubble(vg, sx, sy, Art.ItemExtent(item.id, sr, -angle, item.woolCount) + 6)
        end
        if visible and self.game.phase == "running" and hasCooldown and self.game:CooldownOf(item.id) > 0 then
            local ratio = math.max(0, math.min(1, 1 - item.remaining / self.game:CooldownOf(item.id)))
            local col = Items.rarityColors[def.rarity]
            -- 冷却进度围绕物品一圈，从十二点方向顺时针填充像素方块。
            local pixelSize = math.max(2, math.min(3, math.floor(sr * .18)))
            local ringRadius = sr + 5
            local filledSegments = math.floor(ratio * COOLDOWN_SEGMENTS)
            nvgSave(vg)
            nvgShapeAntiAlias(vg, 0)
            for segment, direction in ipairs(cooldownDirections) do
                local ready = segment <= filledSegments
                nvgBeginPath(vg)
                nvgRect(vg, math.floor(sx + direction.x * ringRadius - pixelSize / 2),
                    math.floor(sy + direction.y * ringRadius - pixelSize / 2), pixelSize, pixelSize)
                nvgFillColor(vg, ready and nvgRGBA(col[1], col[2], col[3], 240)
                    or nvgRGBA(C.border[1], C.border[2], C.border[3], 180))
                nvgFill(vg)
            end
            nvgRestore(vg)
        end
    end
    -- 结算残留：物品回牌库、刚体被移除后按结算瞬间的最后姿态保留绘制，
    -- 三选一/结束阶段瓶子不再瞬间清空；新回合重摆布局时由 ResetEffects 清除。
    -- 残留只读不可点击（PickItem 仅遍历实时 BottleItems）。
    for resUid, res in pairs(self.residue) do
        local sx, sy = x + res.x * self.ppu, y - res.y * self.ppu
        local sr = self:VisualRadius(resUid, res.radius) * self.ppu
        if self.pulses[resUid] then
            local age = self.pulses[resUid]
            PixelFrame(vg, sx, sy, sr + 5 + math.floor(age * 28), C.warning,
                math.floor(180 * (1 - age / .45)))
        end
        if res.soft then SoftView.Draw(vg, res.soft, x, y, self.ppu)
        else Art.Item(vg, res.id, sx, sy, sr, -res.angle, false, res.rollValue, res.woolCount) end
    end
    if self.consumeFlash then self.consumeFlash:Render(vg, x, y, self.ppu, l) end
    for _, ring in ipairs(self.burstRings) do
        BurstRing(vg, x + ring.x * self.ppu, y - ring.y * self.ppu,
            ring.radius * self.ppu, ring.age / ring.life)
    end
    -- 入场与气球碎片共用重力方粒步进，爆炸环独立于价值脉冲。
    if #self.bursts > 0 then
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        for _, p in ipairs(self.bursts) do
            local fade = math.max(0, math.min(1, (1 - p.age / p.life) * 2.5))
            if fade > 0 then
                local half = p.size / 2
                nvgBeginPath(vg)
                nvgRect(vg, math.floor(x + p.x * self.ppu - half),
                    math.floor(y - p.y * self.ppu - half), p.size, p.size)
                nvgFillColor(vg, nvgRGBA(p.color[1], p.color[2], p.color[3], math.floor(255 * fade)))
                nvgFill(vg)
            end
        end
        nvgRestore(vg)
    end
    for _, p in ipairs(self.particles) do
        local prefix, text, valueIcon = TriggerFeedback.Content(p.value, p.trigger, p.rewardKind)
        nvgFontFace(vg, UI.Theme.FontFace(p.trigger and "sans" or "pixel", "normal"))
        nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
        -- 不淡出：保持完全不透明，生命周期结束时直接消失（用户要求）。
        local alpha = 255
        local tx = x + p.x * self.ppu
        -- 上升动画（用户要求恢复）。
        local ty = y - p.y * self.ppu - 20 - p.age * 42 - (p.lift or 0)
        -- 字号随字数增大；"+N"是最少字数，使用最小字号22。
        local numberLength = utf8.len(text) or #text
        if p.rewardKind == "permanent" then numberLength = numberLength - 2 end
        local size = math.min(SCORE_FONT_MAX,
            SCORE_FONT_BASE + SCORE_FONT_PER_CHAR * math.max(0, numberLength - 2))
        if p.trigger then size = math.min(36, size) end
        nvgFontSize(vg, UI.Theme.FontSize(size))
        local prefixWidth = prefix ~= "" and nvgTextBounds(vg, 0, 0, prefix) or 0
        local textWidth = nvgTextBounds(vg, 0, 0, text)
        local iconWidth = valueIcon and size + 4 or 0
        local width = prefixWidth + iconWidth + textWidth
        local fit = p.trigger and math.min(1, math.max(1, l.w - 20) / math.max(1, width * 1.3)) or 1
        if p.trigger then
            local half = width * fit * 1.3 / 2 + 5
            tx = math.max(l.x + half, math.min(l.x + l.w - half, tx))
            ty = math.max(l.y + size * fit, math.min(l.y + l.h - size * fit, ty))
        end
        local left = -width / 2
        local amountX = left + prefixWidth + iconWidth
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        -- 弹性摇晃：弹出的同时左右大幅摇摆（约±14度）后衰减停稳，方向按 uid 错开。
        local wobble = (p.uid % 2 == 0 and 1 or -1) * math.rad(14)
            * math.exp(-2.5 * p.age) * math.sin(12 * p.age)
        local s = popScale(p.age)
        nvgRotate(vg, wobble)
        nvgScale(vg, s * fit, s * fit)
        -- 先铺8方向黑色描边，再盖白色填充，保证跳字在任意底色上都清晰可读。
        nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
        for _, o in ipairs(SCORE_OUTLINE) do
            if prefix ~= "" then nvgText(vg, left + o.x, o.y, prefix, nil) end
            nvgText(vg, amountX + o.x, o.y, text, nil)
        end
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        if prefix ~= "" then nvgText(vg, left, 0, prefix, nil) end
        nvgText(vg, amountX, 0, text, nil)
        if valueIcon then Art.StatIcon(vg, "gain", left + prefixWidth + size / 2, 0, size / 2) end
        nvgRestore(vg)
    end
    nvgRestore(vg)
end

return Board
