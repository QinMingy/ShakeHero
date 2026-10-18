local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Art = require("Bottle.Art")
local SoftView = require("Bottle.SoftView")
local PopIn = require("Bottle.PopIn")
local Storage = require("Bottle.Storage")
local Description = require("Bottle.Description")
local DeckBoard = require("Bottle.DeckBoard")
local ItemText = require("Bottle.ItemText")
local MachineSkin = require("Machine.LayeredSkin")
local Atmosphere=require("Machine.Atmosphere")
local GameAudio = require("Bottle.Audio")

---@type any
local View = {}
View.__index = View
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

-- 品质铭牌文字色，与三选一候选、详情共用同一组。
local QUALITY_INK = {
    {224, 224, 211, 255}, {80, 200, 120, 255}, {69, 170, 242, 255},
    {167, 122, 245, 255}, {255, 205, 74, 255},
}

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
---@field particles {uid:number,value:number,age:number,x:number,y:number}[]
---@field scoreQueue {uid:number,value:number,x:number,y:number}[] 待逐个弹出的结算浮字
---@field scorePopTimer number
---@field displayScore number? 结算展示期间逐件递增的顶部滚轮暂显值；nil 时显示真实余额
---@field pulses table<number,number>
---@field residue table<number,{id:string,x:number,y:number,angle:number,radius:number,soft:BottleSoftPose[]?}> 结算残留：物品回牌库后保留的最后姿态
---@field pops BottlePopPose[] 出现弹跳动效；按 uid 查表的 popByUid 与其同步维护
---@field popByUid table<number,BottlePopPose?>
---@field bursts BottlePopParticle[] 出现动效的重力像素粒子（瓶内米制坐标）
---@field presentUids table<number,boolean> 上一帧瓶内成员，用于差量触发出现动效
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
    self:ResetEffects()
    self:ResetPopState()
end

function Board:ResetEffects()
    -- residue：结算后物品已回牌库、刚体被移除，但仍按最后姿态保留绘制；
    -- 新回合重摆布局（prepare/running/settle 相位切换或换回合）时才清空。
    self.particles, self.pulses, self.residue = {}, {}, {}
    self.scoreQueue, self.scorePopTimer = {}, 0
    self.displayScore = nil
    self.bursts = {}
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
        or (self.physicsMenu and self.physicsMenu:IsVisible())
        or (self.physicsButton and self.physicsButton:HitTest(event.x, event.y)) then return false end
    self.state.dragging = true
    self.pointerId = event.pointerId
    self.lastPanX = event.totalDeltaX - event.deltaX
    self.lastPanY = event.totalDeltaY - event.deltaY
    self.physics:BeginShake()
    return true
end

function Board:OnPanEnd(event)
    if event.pointerId ~= self.pointerId then return end
    self.state.dragging = false
    self.pointerId, self.shakePressId = -1, -1
    self.physics:EndShake()
end

function Board:OnPointerCancel(event)
    self.inspectPress = false
    if event.pointerId == self.shakePressId then self.shakePressId = -1 end
    if event.pointerId ~= self.pointerId then return end
    self.state.dragging = false
    self.pointerId, self.shakePressId = -1, -1
    self.physics:EndShake()
end

function Board:OnPanMove(event)
    if not self.state.dragging or event.pointerId ~= self.pointerId or self.game.phase ~= "running" then return end
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

function Board:Update(dt)
    if self.physics.mode == 2 then
        -- 视觉摆幅与惯性来自同一个瓶子运动，不再独立回弹造成拖拽错觉。
        self.visualX = self.physics.motion.x * self.ppu
        self.visualY = -self.physics.motion.y * self.ppu
    else
        self.visualX = self.visualX * math.exp(-dt * 12)
        self.visualY = self.visualY * math.exp(-dt * 12)
    end
    local l = self:GetAbsoluteLayout()
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
    -- 结算浮字逐个弹出：分数事件已入队，reveal 阶段按间隔逐件释放。
    -- 节拍与 Game 的 reveal 时长共用同一组常量；离开展示阶段后丢弃未放完的队列。
    if #self.scoreQueue > 0 then
        if self.game.phase == "reveal" then
            self.scorePopTimer = self.scorePopTimer - dt
            local interval = math.min(self.game.REVEAL_SCORE_INTERVAL,
                math.max(self.game.REVEAL_SCORE_MIN_INTERVAL,
                    self.game.REVEAL_SCORE_BUDGET / #self.scoreQueue))
            while #self.scoreQueue > 0 and self.scorePopTimer <= 0 do
                local pending = table.remove(self.scoreQueue, 1)
                self.particles[#self.particles + 1] = {
                    uid = pending.uid, value = pending.value, age = 0, x = pending.x, y = pending.y,
                }
                -- 顶部滚轮随每件浮字逐步增加（用户要求）：暂显值先停在结算前，
                -- 每弹出一件加上该件收益，滚轮因此分多次滚动而不是一次跳到最终值。
                if self.displayScore ~= nil then
                    self.displayScore = self.displayScore + pending.value
                end
                -- 每弹出一件结算浮字播放一次出现音效；音调阶梯由队列起点重置后逐件升高。
                GameAudio.Pop()
                self.scorePopTimer = self.scorePopTimer + interval
            end
            -- 队列播完：显示值锁定为真实余额（最后一件弹出时已结算完成）。
            if #self.scoreQueue == 0 and self.displayScore ~= nil then
                self.displayScore = self.game.score
            end
        elseif self.game.phase ~= "settle" then
            self.scoreQueue, self.scorePopTimer = {}, 0
            self.displayScore = nil
        end
    end
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

---@param events GameEvent[]
function Board:Effects(events)
    -- 本批结算浮字插入队列前的长度：批结束时据此设置滚轮暂显起点与音调阶梯。
    local queueStart = #self.scoreQueue
    for _, event in ipairs(events) do
        -- Effects 在物理同步删除实体之前读取事件位置；同一步生成后又消耗的物品
        -- 可能没有刚体，必须用事件 x/y，绝不让 GetPose 的缺失默认值变成瓶中浮字。
        local x, y = event.x, event.y
        if (x == nil or y == nil) and event.uid and self.physics.bodies[event.uid] then
            x, y = self.physics:GetPose(event.uid)
        end
        if event.kind == "score" and event.uid then
            self.pulses[event.uid] = 0
            if (event.value or 0) > 0 and x ~= nil and y ~= nil then
                -- 结算浮字先入队，由 Board:Update 在 reveal 阶段逐个释放（用户要求）。
                self.scoreQueue[#self.scoreQueue + 1] = {
                    uid = event.uid, value = event.value or 0, x = x, y = y,
                }
            end
            -- 结算残留：score 事件发出时物品已回牌库（_CleanupRound 已执行），
            -- 刚体要到本步末尾的 physics:Sync 才被移除；此刻捕获最终姿态，
            -- 三选一/结束阶段按原位保留绘制，物体不再随结算完成瞬间消失。
            local item = self.game:Get(event.uid)
            if item and item.location ~= "bottle" and self.physics.bodies[event.uid] then
                local poseX, poseY, poseAngle, poseRadius = self.physics:GetPose(event.uid)
                local def = Items.byId[item.id]
                self.residue[event.uid] = {
                    -- 事件批一次性送达时香蕉满3回合转化已在 _Settle 内完成，
                    -- item 是实时实例，取到的 id 即腐烂的香蕉而非转化前图案。
                    id = item.id,
                    x = x ~= nil and x or poseX,
                    y = y ~= nil and y or poseY,
                    angle = poseAngle,
                    radius = (def and def.radius) or poseRadius,
                    soft = self.physics:GetSoftPose(event.uid),
                }
            end
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
    local extent = Art.ItemExtent(item and item.id or "apple", radius * ppu, -angle) + 4
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
            x - originX - px * ppu, y - originY + py * ppu, radius * ppu, -angle)) then
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
    if self.inspectPress then
        local dx, dy = event.x - self.pressX, event.y - self.pressY
        if dx * dx + dy * dy > 64 then self.clickMoved = true end
    end
end

---@param event PointerEvent
function Board:OnPointerUp(event)
    self:OnPointerMove(event)
end

---@param event PointerEvent?
function Board:OnClick(event)
    if self.physicsMenu and self.physicsMenu:IsVisible() then self.physicsMenu:Hide(); return end
    if not event or not event:IsPrimaryButton() or Busy(self.game)
        or not self.inspectPress or self.clickMoved then return end
    self.inspectPress = false
    self.inspect(self:PickItem(event.x, event.y))
end

function Board:Render(vg)
    local l = self:GetAbsoluteLayout()
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
        local cooling = self.game.phase == "running" and item.remaining > 0
        local pop = self.popByUid and self.popByUid[item.uid] or nil
        -- 错峰等待中的物品保持不可见（含选中框与冷却环），轮到它时才弹跳出现。
        local visible = not pop or pop.delay <= 0
        if visible then
            if pop then
                -- 出现弹跳：绕物品中心缩放＋轻微角回摆，与三选一选中 icon 同一响应形式。
                nvgSave(vg)
                nvgTranslate(vg, sx, sy)
                nvgScale(vg, math.max(.001, pop.scale), math.max(.001, pop.scale))
                nvgRotate(vg, pop.angle)
                nvgTranslate(vg, -sx, -sy)
                SoftView.Item(vg, self.physics, item, x, y, self.ppu, cooling)
                nvgRestore(vg)
                -- 出现瞬间的白色像素环快速扩张淡出，强化“炸出”的第一帧。
                if pop.age < .22 then
                    local t = pop.age / .22
                    PixelFrame(vg, sx, sy, sr + 6 + math.floor(t * 12), { 255, 255, 255, 255 },
                        math.floor(170 * (1 - t)))
                end
            else
                SoftView.Item(vg, self.physics, item, x, y, self.ppu, cooling)
            end
        end
        if visible and item.uid == self.selectedUid and not Busy(self.game) then
            local extent = Art.ItemExtent(item.id, sr, -angle) + 4
            PixelFrame(vg, sx, sy, extent + 2, C.primary, 100)
            PixelFrame(vg, sx, sy, extent, C.warning)
        end
        if visible and self.game.phase == "running" and self.game:CooldownOf(item.id) > 0 then
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
        local sx, sy, sr = x + res.x * self.ppu, y - res.y * self.ppu, res.radius * self.ppu
        if self.pulses[resUid] then
            local age = self.pulses[resUid]
            PixelFrame(vg, sx, sy, sr + 5 + math.floor(age * 28), C.warning,
                math.floor(180 * (1 - age / .45)))
        end
        if res.soft then SoftView.Draw(vg, res.soft, x, y, self.ppu)
        else Art.Item(vg, res.id, sx, sy, sr, -res.angle) end
    end
    -- 出现动效的像素粒子：物品色板取色的硬边方粒，已受重力步进，寿命末段淡出。
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
    nvgFontFace(vg, UI.Theme.FontFace("pixel", "normal"))
    nvgTextAlign(vg, NVG_ALIGN_CENTER + NVG_ALIGN_MIDDLE)
    for _, p in ipairs(self.particles) do
        local text = "+" .. string.format("%g", p.value)
        -- 不淡出：保持完全不透明，生命周期结束时直接消失（用户要求）。
        local alpha = 255
        local tx = x + p.x * self.ppu
        -- 上升动画（用户要求恢复）。
        local ty = y - p.y * self.ppu - 20 - p.age * 42
        -- 字号随字数增大；"+N"是最少字数，使用最小字号22。
        local size = math.min(SCORE_FONT_MAX,
            SCORE_FONT_BASE + SCORE_FONT_PER_CHAR * math.max(0, #text - 2))
        nvgFontSize(vg, UI.Theme.FontSize(size))
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        -- 弹性摇晃：弹出的同时左右大幅摇摆（约±14度）后衰减停稳，方向按 uid 错开。
        local wobble = (p.uid % 2 == 0 and 1 or -1) * math.rad(14)
            * math.exp(-2.5 * p.age) * math.sin(12 * p.age)
        local s = popScale(p.age)
        nvgRotate(vg, wobble)
        nvgScale(vg, s, s)
        -- 先铺8方向黑色描边，再盖白色填充，保证跳字在任意底色上都清晰可读。
        nvgFillColor(vg, nvgRGBA(0, 0, 0, alpha))
        for _, o in ipairs(SCORE_OUTLINE) do
            nvgText(vg, o.x, o.y, text, nil)
        end
        nvgFillColor(vg, nvgRGBA(255, 255, 255, alpha))
        nvgText(vg, 0, 0, text, nil)
        nvgRestore(vg)
    end
    nvgRestore(vg)
end

---@class BottleItemIcon : Widget
---@field itemId string
---@field isRelic boolean
---@overload fun(props:WidgetProps): BottleItemIcon
local Icon = UI.Widget:Extend("BottleItemIcon") --[[@as BottleItemIcon]]
function Icon:Init(props)
    UI.Widget.Init(self, props)
    self.itemId = props.itemId or "apple"
    self.isRelic = props.isRelic == true
end
function Icon:Render(vg)
    local l = self:GetAbsoluteLayout()
    local x, y, radius = l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) * .38
    if self.isRelic then Art.Relic(vg, self.itemId, x, y, radius)
    else Art.Item(vg, self.itemId, x, y, radius) end
end

---@class BottleStatIcon : Widget
---@field kind string
---@overload fun(props:WidgetProps): BottleStatIcon
local StatIcon = UI.Widget:Extend("BottleStatIcon") --[[@as BottleStatIcon]]
function StatIcon:Init(props)
    UI.Widget.Init(self, props)
    self.kind = props.kind or "gain"
end
function StatIcon:Render(vg)
    local l = self:GetAbsoluteLayout()
    Art.StatIcon(vg, self.kind, l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) / 2)
end

-- 三选一、牌库和详情共用第二行：金币、冷却数值及其右侧 tag。
---@param gold number
---@param cooldown number
---@param tags? string
---@return Panel
---@return Label
---@return Label
---@return Label
local function ItemStats(gold, cooldown, tags)
    local goldLabel = UI.Label {id = "goldValue", text = string.format("%g", gold),
        textMotionDisabled = true, fontSize = 11.25, fontFamily = "mono", fontColor = C.warning}
    local cooldownLabel = UI.Label {id = "cooldownValue", text = string.format("%g", cooldown),
        textMotionDisabled = true, fontSize = 11.25, fontFamily = "mono", fontColor = C.textSecondary}
    local tagText = tags or ""
    local tagLabel = UI.Label {id = "itemTag", text = tagText, visible = tagText ~= "",
        fontSize = 11.25, fontColor = C.textSecondary, marginLeft = 8,
        whiteSpace = "normal", flexShrink = 1}
    local row = UI.Panel {id = "itemStats", width = "100%", flexDirection = "row",
        flexWrap = "wrap", alignItems = "center", gap = 12, pointerEvents = "none", children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 4, minHeight = 24, children = {
                StatIcon {kind = "gain", width = 24, height = 24}, goldLabel,
            }},
            UI.Panel {flexDirection = "row", flexWrap = "wrap", alignItems = "center",
                gap = 4, minHeight = 24, flexShrink = 1, children = {
                StatIcon {kind = "cooldown", width = 24, height = 24}, cooldownLabel, tagLabel,
            }},
        }}
    return row, goldLabel, cooldownLabel, tagLabel
end

-- 当前三选一是尚未创建实例的 id；若候选是已有实例，必须显示它自己的动态现值。
-- 不借用牌库中同名物品的永久增长，避免把新卡的基础值误写成另一个实例的值。
---@param game BottleGame
---@param option string|ItemInstance
---@return string id
---@return number? gold 遗物不具有物品价值
---@return ItemDef|RelicDef def
local function DraftValue(game, option)
    local id = option --[[@as string]]
    if type(option) == "table" then id = option.id end
    if game.relicDraft then
        local relic = Relics.byId[id]
        assert(relic, "未知遗物候选：" .. tostring(id))
        return id, nil, relic
    end
    local def = Items.byId[id]
    assert(def, "未知物品候选：" .. tostring(id))
    return id, type(option) == "table" and game:_Value(option) or ItemText.InitialValue(game, id), def
end

---@class BottleEye : Widget
---@overload fun(props:WidgetProps): BottleEye
local Eye = UI.Widget:Extend("BottleEye") --[[@as BottleEye]]
function Eye:Render(vg)
    local l = self:GetAbsoluteLayout()
    Art.Eye(vg, l.x + l.w / 2, l.y + l.h / 2, 9)
end

---@param text string
---@param size? number
---@param color? RGBAColor
---@return Label
local function Label(text, size, color)
    local fontSize = math.max(size or 12, 11.25)
    return UI.Label {text = text, fontSize = fontSize, fontColor = color or C.text,
        fontWeight = fontSize >= 13 and "bold" or "normal", flexShrink = 1}
end

---@param text string
---@param callback function
---@param primary? boolean
---@return Button
local function Button(text, callback, primary)
    return GameAudio.Button {
        text = text, onClick = callback, fontSize = 12, height = 48,
        variant = primary and "primary" or "secondary",
        borderColor = C.border,
        flexShrink = 1,
    }
end

---@class BottleView
---@field game BottleGame
---@field physics BottlePhysics
---@field actions table<string,function>
---@field targetBursts table[]? 目标进度条前沿的重力像素粒子
---@field root Panel
---@field container Panel
---@field board BottleBoard
---@field detail Card
---@field detailIcon BottleItemIcon
---@field detailTitle Label
---@field detailStats Panel
---@field detailGold Label
---@field detailCooldown Label
---@field detailTag Label
---@field detailEffect BottleDescription
---@field detailScroll ScrollView
---@field definitionModal Panel
---@field definitionId string
---@field definitionIcon BottleItemIcon
---@field definitionTitle Label
---@field definitionGold Label
---@field definitionCooldown Label
---@field definitionTag Label
---@field definitionEffect BottleDescription
---@field definitionScroll ScrollView
---@field selectedUid integer
---@field detailRound integer
---@field detailRevision number
---@field physicsButton Button
---@field physicsMenu Panel
---@field physicsOne Button
---@field physicsTwo Button
---@field scoreLabel Label
---@field roundLabel Label
---@field goalLabel Label
---@field progress ProgressBar
---@field timer ProgressBar
---@field statusLabel Label
---@field footer Panel
---@field draft Panel
---@field modal Panel
---@field deckButton Button
---@field badgeLabel Label
---@field currentPhase string
---@field inventoryOpen boolean
---@field inventoryPanel Card?
---@field inventoryTitle Label?
---@field deckBody Panel?
---@field deckBoard any
---@field deckSim any
---@field deckBackButton Button?
---@field deckDetailUid integer
---@field deckDraftWasOpen boolean
---@field choiceHidden boolean
---@field lastRevision number
---@field lastDisplayedScore number
---@field lastRound number

---@param game BottleGame
---@param physics BottlePhysics
---@param actions table<string,function>
---@return BottleView
function View.New(game, physics, actions)
    local self = setmetatable({}, View)
    self:Init(game, physics, actions)
    return self
end

function View:Init(game, physics, actions)
    self.game, self.physics, self.actions = game, physics, actions
    self.currentPhase = ""
    self.inventoryOpen, self.choiceHidden = false, false
    self.deckDetailUid, self.deckDraftWasOpen = 0, false
    self.lastRevision, self.lastDisplayedScore, self.lastRound = -1, -1, -1
    self.lastRerollUsed = false
    self.selectedUid, self.detailRound, self.detailRevision = 0, -1, -1
    self.detailIcon = Icon {itemId = "apple", width = 42, height = 42, pointerEvents = "none"}
    self.detailTitle = UI.Label {text = "", fontSize = 14.25, fontWeight = "bold",
        whiteSpace = "normal", width = "100%", fontColor = C.text}
    self.detailStats, self.detailGold, self.detailCooldown, self.detailTag = ItemStats(0, 0)
    self.detailEffect = Description {id = "detailDescription", text = "", fontSize = 12, fontColor = C.text,
        onInspect = function(id) self:InspectDefinition(id) end}
    self.detailScroll = UI.ScrollView {id = "detailScroll", width = "100%", height = 32,
        bounces = false, children = {self.detailEffect}}
    self.detail = UI.Card {id = "itemDetail", position = "absolute", visible = false,
        width = 280, padding = 12, gap = 8, backgroundColor = C.surface,
        borderColor = C.border, zIndex = 15, pointerEvents = "auto",
        onClick = function() end, children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 10, children = {
                self.detailIcon,
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {self.detailTitle, self.detailStats}},
            }},
            self.detailScroll,
        }}
    self.definitionId = ""
    self.definitionIcon = Icon {id = "definitionIcon", itemId = "apple", width = 52, height = 52,
        pointerEvents = "none", flexShrink = 0}
    ---@type Panel
    local definitionStats
    definitionStats, self.definitionGold, self.definitionCooldown, self.definitionTag = ItemStats(0, 0)
    local definitionClose = Button("关闭", function(widget, event)
        if event then event:StopPropagation() end
        self:CloseDefinition()
    end)
    definitionClose:SetStyle({width = 70, height = 40, flexShrink = 0})
    definitionClose.id = "definitionClose"
    local popup = Description.CreatePopup(self.definitionIcon, definitionStats, definitionClose,
        function(id) self:InspectDefinition(id) end, function() self:CloseDefinition() end)
    self.definitionModal, self.definitionTitle = popup.overlay, popup.title
    self.definitionEffect, self.definitionScroll = popup.effect, popup.scroll
    self.scoreLabel = Label("0", 27, C.warning)
    self.scoreLabel:SetStyle({fontFamily = "mono"})
    self.roundLabel = Label("回合 1/5", 12, C.textSecondary)
    self.goalLabel = Label("40", 27, C.warning)
    self.badgeLabel = Label("考核阶段 1", 10, C.textSecondary)
    -- 统计区整体固定，不让回合／分数的文字基线随装饰时钟漂移。
    for _, value in ipairs({self.scoreLabel, self.roundLabel, self.goalLabel, self.badgeLabel}) do
        value:SetStyle({textMotionDisabled = true})
    end
    self.statusLabel = Label("准备好，摇出你的组合", 11, C.textSecondary)
    self.progress = UI.ProgressBar {value = 0, height = 12, showLabel = false, fillColor = C.primary}
    self.timer = UI.ProgressBar {value = 1, height = 8, showLabel = false, fillColor = C.warning}
    self.board = Board {game = game, physics = physics, shake = actions.shake,
        inspect = function(uid) self:InspectItem(uid) end,
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 120, pointerEvents = "auto"}
    self.physicsButton = Button("切换物理 · 二", function()
        self.board:ResetShake()
        self.physicsMenu:SetVisible(not self.physicsMenu:IsVisible())
    end)
    self.physicsButton:SetStyle({position = "absolute", left = 8, top = 8,
        width = 144, height = 40, fontSize = 11.25, zIndex = 5})
    self.physicsButton:SetWidth(144)
    self.physicsOne = Button("物理一 · 原版", function() self.actions.physics(1) end)
    self.physicsTwo = Button("物理二 · 摇晃", function() self.actions.physics(2) end, true)
    self.physicsOne:SetWidth(162)
    self.physicsTwo:SetWidth(162)
    self.physicsOne:SetStyle({fontSize = 11.25})
    self.physicsTwo:SetStyle({fontSize = 11.25})
    self.sensorStatus = "off"
    self.sensorLabel = UI.Label {id = "sensorStatus", text = "体感：未启用", fontSize = 10,
        whiteSpace = "normal", width = "100%", fontColor = C.textSecondary}
    self.sensorButton = Button("启用／校准体感", function()
        self.actions.sensor()
        self.physicsMenu:Hide()
    end)
    self.sensorButton.id = "sensorCalibrate"
    self.sensorButton:SetStyle({width = 162, fontSize = 11.25})
    self.physicsMenu = UI.Panel {position = "absolute", left = 8, top = 54,
        width = 178, padding = 8, gap = 8, backgroundColor = C.surface,
        visible = false, zIndex = 6, pointerEvents = "auto",
        children = {self.physicsOne, self.physicsTwo, self.sensorLabel, self.sensorButton}}
    self.board.physicsButton, self.board.physicsMenu = self.physicsButton, self.physicsMenu
    self.board:AddChild(self.physicsButton)
    self.board:AddChild(self.physicsMenu)
    self.footer = UI.Panel {width = "100%", gap = 10, paddingTop = 6, paddingBottom = 12}
    self.draft = UI.Panel {position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        visible = false, backgroundColor = C.overlay, justifyContent = "center", alignItems = "center",
        padding = 12, zIndex = 20, pointerEvents = "auto"}
    self.modal = UI.Panel {position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        visible = false, backgroundColor = C.overlay, padding = 16,
        justifyContent = "center", zIndex = 30, pointerEvents = "auto"}
    -- 牌库入口以袋子为底图，文字写在袋身上。
    self.deckButton = Button("牌库 3", function() self:OpenInventory() end)
    self.deckButton:SetStyle({height = 40, fontSize = 11.25, width = 86})
    local help = Button("规则", function() self:OpenHelp() end)
    help:SetStyle({height = 40, fontSize = 11.25, width = 64})
    local save = Button("存档", function() self:OpenSave() end)
    save:SetStyle({height = 40, fontSize = 11.25, width = 64})
    local gm = Button("GM", function() self:OpenGm() end)
    gm:SetStyle({textMotionDisabled = true})
    gm:SetStyle({height = 40, fontSize = 11.25, width = 52})
    local title = Label("摇摇牌库", 22.5, C.primary)
    title:SetStyle({textShadow = {offsetX = 2, offsetY = 2, blur = 0, color = C.secondary}})
    self.container = UI.Panel {width = "100%", maxWidth = 560, height = "100%",
        alignSelf = "center", paddingHorizontal = 20, paddingTop = 16, gap = 10,
        children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                    title, Label("瓶子里，藏着无限可能", 9, C.textSecondary),
                }}, gm, help, save,
            }},
            UI.Card {id = "scoreSummary", backgroundColor = C.surface, padding = 14, gap = 6,
                pointerEvents = "none", children = {
                    UI.Panel {flexDirection = "row", alignItems = "center", children = {
                        UI.Panel {flexGrow = 1, children = {Label("可用分数", 10, C.textSecondary), self.scoreLabel}},
                        UI.Panel {alignItems = "flex-end", gap = 4, children = {self.roundLabel, self.goalLabel}},
                    }}, self.progress,
                    self.badgeLabel,
                }},
            UI.Panel {flexDirection = "row", alignItems = "center", children = {
                UI.Panel {flexGrow = 1, children = {self.statusLabel}}, self.deckButton,
            }},
            self.timer, self.board, self.footer,
            self.detail, self.draft, self.modal,
        }}
    self.root = UI.Panel {width = "100%", height = "100%", backgroundColor = C.background,
        pointerEvents = "auto", onClick = function() self:CloseItemDetail() end,
        children = {UI.SafeAreaView {width = "100%", height = "100%", nativeMenuInset = true,
            children = {self.container}}, self.definitionModal}}
    MachineSkin.Apply(self,title,help,save,gm)
    UI.SetRoot(self.root)
    self:UpdatePhysicsMode()
    self:Update(true)
end

function View:UpdatePhysicsMode()
    local original = self.physics.mode == 1
    self.physicsButton:SetText("切换物理 · " .. (original and "一" or "二"))
    self.physicsOne:SetText(original and "物理一 [当前]" or "物理一 · 原版")
    self.physicsTwo:SetText(original and "物理二 · 摇晃" or "物理二 [当前]")
    self.physicsMenu:Hide()
end

function View:SetSensorStatus(status)
    if self.sensorStatus == status then return end
    self.sensorStatus = status
    local labels = {
        waiting = "体感：等待设备",
        available = "体感：已接通",
        unavailable = "体感：暂无数据",
        unsupported = "体感：当前端不支持",
    }
    self.sensorLabel:SetText(labels[status] or "体感：未启用")
    self.sensorButton:SetText(status == "available" and "重新校准体感"
        or status == "unsupported" and "查看体感说明" or "启用／校准体感")
    if Busy(self.game) then self:BuildFooter() end
end

function View:CloseItemDetail()
    self.selectedUid, self.board.selectedUid = 0, 0
    self.detail:Hide()
end

-- 查看定义，不查询/创建实例，不改变牌库、三选一或瓶中选择。
---@param id string
---@return boolean
function View:InspectDefinition(id)
    local def = Items.byId[id]
    if not def or Busy(self.game) then return false end
    if self.definitionModal:IsVisible() and self.definitionId == id then return true end
    self.board:ResetShake()
    self.definitionId = id
    self.definitionIcon.itemId = id
    self.definitionTitle:SetText(def.name .. " · " .. Items.rarityNames[def.rarity])
    self.definitionGold:SetText(string.format("%g", ItemText.InitialValue(self.game, id)))
    self.definitionCooldown:SetText(string.format("%g", self.game:CooldownOf(id)))
    self.definitionTag:SetText(Items.TagsText(def))
    self.definitionTag:SetVisible(Items.TagsText(def) ~= "")
    self.definitionEffect:SetText(ItemText.Effect(self.game, id))
    self.definitionEffect:RestartReveal()
    self.definitionModal:Show()
    UI.Layout()
    self.definitionEffect:Measure(self.definitionEffect:GetLayout().w)
    UI.Layout()
    self.definitionScroll:ScrollToTop()
    return true
end

function View:CloseDefinition()
    self.definitionModal:Hide()
    self.definitionId = ""
end

---@param uid integer
function View:InspectItem(uid)
    if self.definitionModal:IsVisible() then return end
    local item = self.game:Get(uid)
    if Busy(self.game) or self.modal:IsVisible() or self.draft:IsVisible()
        or not item or item.location ~= "bottle" then
        self:CloseItemDetail()
        return
    end
    local def = Items.byId[item.id]
    self.selectedUid, self.board.selectedUid = uid, uid
    self.detailRound, self.detailRevision = self.game.round, self.game.revision
    self.detailIcon.itemId = item.id
    self.detailTitle:SetText(def.name .. "  #" .. uid .. " · " .. Items.rarityNames[def.rarity])
    self.detailGold:SetText(string.format("%g", self.game:_Value(item)))
    self.detailCooldown:SetText(string.format("%g", self.game:CooldownOf(item.id)))
    self.detailTag:SetText(Items.TagsText(def))
    self.detailTag:SetVisible(Items.TagsText(def) ~= "")
    self.detailEffect:SetText(ItemText.Effect(self.game, item.id, item))
    self.detailEffect:RestartReveal()
    self.detailTitle:SetStyle({textReveal = true})
    self.detailScroll:ScrollToTop()
    self.detail:SetStyle({borderColor = C.border})
    self.detail:Show()
    self:PositionItemDetail()
end

function View:PositionItemDetail()
    if self.selectedUid == 0 then return end
    local rootBounds = self.container:GetAbsoluteLayout()
    local container = self.board.layered and self.board:GetAbsoluteLayout() or rootBounds
    local width = math.min(300, math.max(1, container.w - 24))
    if self.detail.props.width ~= width then self.detail:SetWidth(width) end
    UI.Layout()
    local effectHeight = self.detailEffect:Measure(self.detailEffect:GetLayout().w)
    -- 常规内容自然展开；极小屏或长说明仅滚动效果区，保留标题、属性和关闭提示。
    local chromeHeight = self.detail:GetAbsoluteLayout().h - self.detailScroll:GetAbsoluteLayout().h
    local effectBudget = math.max(32, container.h - math.max(124, chromeHeight) - 32)
    local effectViewport = math.min(effectHeight, effectBudget)
    if self.detailScroll.props.height ~= effectViewport then self.detailScroll:SetHeight(effectViewport) end
    UI.Layout()
    local bounds = self.board:GetItemBounds(self.selectedUid)
    local detail = self.detail:GetAbsoluteLayout()
    local centerX = bounds.x + bounds.w / 2
    local x = math.max(container.x + 12,
        math.min(centerX - width / 2, container.x + container.w - width - 12))
    local gap = 10
    local y = bounds.y - detail.h - gap
    local minY = container.y + 8
    local maxY = container.y + container.h - detail.h - 8
    if y < minY then y = bounds.y + bounds.h + gap end
    y = math.max(minY, math.min(y, maxY))
    local left, top = x - rootBounds.x, y - rootBounds.y
    if self.detail.props.left ~= left or self.detail.props.top ~= top then
        self.detail:SetStyle({left = left, top = top})
    end
end

function View:Rebind(game)
    if self.machineSkin then
        self.machineSkin.pageMotion:Reset()
        self.machineSkin.draftMotionKey=nil
    end
    self:CloseDefinition()
    self:CloseItemDetail()
    self.board:ResetShake()
    self:UpdatePhysicsMode()
    self.game = game
    self.board.game = game
    self.board:ResetEffects()
    self.board:ResetPopState()
    -- 读档/换局后的 rerollUsed 属于基线状态：重新入场只弹跳一次，不当作即时重抽。
    self.lastRerollUsed = game.rerollUsed
    self.choiceHidden, self.inventoryOpen = false, false
    self.deckDetailUid, self.deckDraftWasOpen = 0, false
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    self.modal:Hide()
    self:Update(true)
end

---@param force? boolean
function View:Update(force)
    MachineSkin.Update(self)
    local game = self.game
    if self.selectedUid ~= 0 then
        local item = game:Get(self.selectedUid)
        if Busy(game) or game.round ~= self.detailRound or game.revision ~= self.detailRevision
            or self.modal:IsVisible() or self.draft:IsVisible() or self.physicsMenu:IsVisible()
            or not item or item.location ~= "bottle" then
            self:CloseItemDetail()
        else
            self:PositionItemDetail()
        end
    end
    if force or game.score ~= self.lastDisplayedScore or game.target ~= self.lastDisplayedTarget then
        self.scoreLabel:SetText(string.format("%g", game.score))
        self.lastDisplayedScore = game.score
        self.lastDisplayedTarget = game.target
        self.progress:SetValue(math.min(1, game.score / game.target))
    end
    self.roundLabel:SetText("回合 " .. (((game.round - 1) % 5) + 1) .. "/5")
    self.goalLabel:SetText(string.format("%g", game.target))
    MachineSkin.FitNumbers(self)
    self.badgeLabel:SetText("考核阶段 " .. game.stage)
    if game.phase == "running" then
        self.timer:SetValue(math.max(0, 1 - game.elapsed / 10))
    elseif game.phase == "settle" then
        -- 结算下落2秒复用进度条：显示剩余缓冲时间。
        self.timer:SetValue(math.max(0, 1 - game.settleElapsed / 2))
    else
        self.timer:SetValue(1)
    end
    self.deckButton:SetText("牌库 " .. #game.deck)
    self.deckButton:SetDisabled(Busy(game))
    -- 重抽：即使抽回同一批 uid，也清空出现状态重新逐件错峰弹跳（用户要求）。
    -- rerollUsed 只在 _Prepare 重置，因此同一回合的第二次重抽（已被拒绝）不会重复触发。
    if game.rerollUsed and not self.lastRerollUsed then
        self.board:ResetPopState()
    end
    self.lastRerollUsed = game.rerollUsed
    if force or game.phase ~= self.currentPhase or game.round ~= self.lastRound
        or game.revision ~= self.lastRevision or game.relicDraft ~= self.lastRelicDraft then
        local phaseChanged = game.phase ~= self.currentPhase or game.round ~= self.lastRound
            or game.relicDraft ~= self.lastRelicDraft
        if phaseChanged then
            self:CloseDefinition()
            self.choiceHidden = false
            self.board:ResetShake()
            if game.round ~= self.lastRound or game.phase == "prepare"
                or game.phase == "running" or game.phase == "settle" then
                self.board:ResetEffects()
            end
            self.physicsMenu:Hide()
        end
        self.currentPhase, self.lastRound = game.phase, game.round
        self.lastRevision, self.lastRelicDraft = game.revision, game.relicDraft
        self:BuildFooter()
        if game.phase == "draft" then
            self:BuildDraft()
            -- Finish the three red clock flashes before opening the CRT draft page.
            if self.machineSkin.cabinet.clock.flashElapsed >= 0 then self.draft:Hide() end
        else self.draft:Hide() end
    end
    MachineSkin.SyncPages(self)
    GameAudio.SetPhase(game.phase)
end

function View:BuildFooter()
    if self.machineSkin then self.machineSkin.pageMotion:Clear("footer") end
    local children = self.footer:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.footer:ClearChildren()
    local game = self.game
    if game.phase == "prepare" then
        self.statusLabel:SetText(game.lastResult ~= "" and game.lastResult
            or (self.physics.mode == 2 and "点击物品查看效果 · 开始后短距离来回摇" or "点击物品查看效果 · 开始后拖动瓶子"))
        local reroll = Button(game.rerollUsed and "重抽已用" or "重抽 · 1 次", function() self.actions.reroll() end)
        reroll:SetDisabled(game.rerollUsed)
        reroll:SetStyle({flexGrow = 1, flexBasis = 0})
        local start = Button("开始摇晃", function() self.actions.start() end, true)
        start:SetStyle({flexGrow = 2, flexBasis = 0, height = 56, fontSize = 15})
        self.footer:AddChild(UI.Panel {flexDirection = "row", height = 60, gap = 10,
            alignItems = "center", children = {reroll, start}})
    elseif game.phase == "running" then
        self.statusLabel:SetText(self.sensorStatus == "available" and "摇动手机或按住瓶子来回摇，带动物品碰撞"
            or self.physics.mode == 2 and "按住来回摇，换向时物品惯性翻滚"
            or "按住瓶子来回拖动，碰撞会改变组合")
        local label = Label("正在摇晃", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "settle" then
        self.statusLabel:SetText("禁止摇晃 · 物品自然下落，随后统一结算")
        local label = Label("结算中", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "reveal" then
        self.statusLabel:SetText("本回合 +" .. string.format("%g", game.lastRoundScore) .. " 金币")
        local label = Label("结算完成", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "draft" then
        self.statusLabel:SetText("本回合 +" .. string.format("%g", game.lastRoundScore)
            .. (game.relicDraft and " · 选一件遗物永久生效" or " · 选一件加入牌库"))
        local show = Button("查看本回合三选一", function()
            self:CloseItemDetail()
            MachineSkin.SetDraftOpen(self,true)
        end, true)
        show:SetStyle({width = "100%", height = 54})
        self.footer:AddChild(show)
    else
        self.statusLabel:SetText("未达到阶段目标，本局结束")
        local result = Label("坚持了 " .. game.bestRound .. " 回合 · 累计 " .. string.format("%g", game.totalScore) .. " 分", 12)
        self.footer:AddChild(result)
        self.footer:AddChild(Button("重新开始", function() self:ConfirmNewRun() end, true))
    end
    MachineSkin.Footer(self)
end

function View:BuildDraft()
    if self.machineSkin then
        return MachineSkin.BuildDraft(self,Icon,Description,DraftValue,ItemStats)
    end
    local relicDraft = self.game.relicDraft == true
    local children = self.draft:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.draft:ClearChildren()
    -- 面板按屏幕比例放大并居中；内容过多时只滚动候选区，底部操作始终可见。
    local panel = UI.Card {width = "100%", height = "90%", maxHeight = 820, backgroundColor = C.surface,
        padding = 14, gap = 12, overflow = "hidden"}
    local eye = Button("", function()
        self.choiceHidden = true; self.draft:Hide()
    end)
    eye:SetStyle({width = 48, height = 44, flexShrink = 0})
    eye:AddChild(Eye {width = "100%", height = "100%", pointerEvents = "none"})
    panel:AddChild(UI.Panel {flexDirection = "row", alignItems = "center", gap = 12, children = {
        UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {
            UI.Label {text = relicDraft and "挑选你的下一件遗物" or "挑选你的下一件物品",
                fontSize = 20.25, fontWeight = "bold",
                whiteSpace = "normal", width = "100%", fontColor = C.text},
            Label("本回合 +" .. string.format("%g", self.game.lastRoundScore) .. " · 三选一", 12, C.textSecondary),
        }}, eye,
    }})
    if self.game.lastResult ~= "" then
        panel:AddChild(UI.Label {text = self.game.lastResult, fontSize = 11.25,
            whiteSpace = "normal", width = "100%", fontColor = C.primary})
    end
    local choices = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 12, padding = 4}
    for i, option in ipairs(self.game.options) do
        local index = i
        local id, gold, def = DraftValue(self.game, option)
        local card = UI.Card {width = "100%", minHeight = 132, gap = 8,
            padding = 12, backgroundColor = C.background, borderColor = C.border}
        local choose = Button("选择", function() self.actions.choose(index) end, true)
        choose:SetStyle({width = 76, height = 48, fontSize = 12, flexShrink = 0})
        card:AddChild(UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10,
            children = {
                Icon {itemId = id, isRelic = relicDraft, width = 52, height = 52, pointerEvents = "none"},
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {
                    UI.Label {text = def.name .. " · " .. Items.rarityNames[def.rarity], whiteSpace = "normal",
                        fontSize = 14.25, fontWeight = "bold", width = "100%", fontColor = C.text},
                    (relicDraft and Label("遗物 · 永久生效", 12, C.textSecondary)
                        or ItemStats(gold --[[@as number]], self.game:CooldownOf(id), Items.TagsText(def --[[@as ItemDef]]))),
                }}, choose,
            }})
        -- 效果说明独占整行，避免被图标和按钮挤窄，也不截断长描述。
        card:AddChild(Description {id = "draftDescription_" .. index,
            text = relicDraft and def.effect or ItemText.Effect(self.game, id), fontSize = 12,
            onInspect = function(itemId) self:InspectDefinition(itemId) end})
        choices:AddChild(card)
    end
    panel:AddChild(choices)
    local refresh = Button(self.game.refreshUsed and "刷新已用" or "刷新 · 1 次", function() self.actions.refresh() end)
    refresh:SetDisabled(self.game.refreshUsed)
    refresh:SetStyle({flexGrow = 1, flexBasis = 0})
    local skip = Button("跳过", function() self.actions.skip() end)
    skip:SetStyle({flexGrow = 1, flexBasis = 0})
    panel:AddChild(UI.Panel {flexDirection = "row", gap = 10, children = {refresh, skip}})
    self.draft:AddChild(panel)
    self.draft:SetVisible(not self.choiceHidden)
end

---@param title string
---@param noClose boolean?
---@return Card
function View:Modal(title, noClose)
    self.modalDeveloperUi=title=="GM 面板"
    self:CloseDefinition()
    self:CloseItemDetail()
    if self.inventoryOpen then
        -- 打开其它面板即离开牌库页：恢复机台输入与牌库页暂时接管的三选一页面。
        self.inventoryOpen=false
        self.deckDetailUid=0
        self:DisposeDeckSim()
        if self.game.phase=="draft" and self.deckDraftWasOpen then self.draft:Show() end
        self.deckDraftWasOpen=false
        if self.physicsButton then self.physicsButton:Show() end
    end
    self.inventoryPanel,self.inventoryTitle,self.deckBody=nil,nil,nil
    local children = self.modal:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.modal:ClearChildren()
    local panel = UI.Card {width = "100%", height = "88%", backgroundColor = C.surface,
        padding = 16, gap = 12}
    local heading=Label(title,18)
    heading.id="modalTitle"
    ---@type Widget[]
    local headChildren={UI.Panel {flexGrow = 1, children = {heading}}}
    if not noClose then
        local close = Button("关闭", function() self.modal:Hide(); self.inventoryOpen = false end)
        close:SetStyle({width = 70, height = 40, fontSize = 11.25})
        headChildren[#headChildren+1]=close
    end
    local head = UI.Panel {flexDirection = "row", alignItems = "center", children = headChildren}
    if noClose then
        -- 牌库页由物理沙盒铺满整个中部区域，标题行单独留出内边距。
        local s = self.machineSkin and self.machineSkin.scale or 1
        head:SetStyle({paddingLeft = 12 * s, paddingRight = 12 * s,
            paddingTop = 6 * s, paddingBottom = 4 * s})
    end
    panel:AddChild(head)
    self.modal:AddChild(panel)
    if self.machineSkin then MachineSkin.Modal(self,panel,false) end
    self.modal:Show()
    return panel
end

-- 牌库沙盒：全部持有实例从顶部落下，碰撞停稳后可点击进入详情。
function View:BuildDeckSandbox(body, s)
    if not self.deckSim or #self.deckSim.order == 0 then
        body:AddChild(UI.Panel {flexGrow = 1, flexBasis = 0,
            justifyContent = "center", alignItems = "center",
            children = {UI.Label {text = "牌库为空", fontSize = 12 * s, fontColor = C.textSecondary}}})
        return
    end
    local board = DeckBoard.Widget {id = "deckBoard", sim = self.deckSim,
        onPick = function(uid) self:ShowDeckItem(uid) end,
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 40, pointerEvents = "auto"}
    body:AddChild(board)
    self.deckBoard = board
end

-- 牌库物品详情：与三选一详情同构（大图标、名称、品质铭牌、属性、可滚动说明）。
function View:BuildDeckDetail(body, item, s)
    local def = Items.byId[item.id]
    local content = UI.Panel {width = "100%", flexGrow = 1, flexBasis = 0,
        paddingHorizontal = 12 * s, paddingTop = 8 * s, paddingBottom = 8 * s, gap = 8 * s}
    content:AddChild(UI.Label {id = "deckDetailTitle", text = "物品详情", fontSize = 18 * s,
        fontColor = C.text, textMotionDisabled = true})
    local name = UI.Label {id = "deckDetailName", text = def.name .. "  #" .. item.uid,
        fontSize = 20 * s, fontWeight = "bold", whiteSpace = "normal", width = "100%", fontColor = C.text}
    name:SetStyle({textReveal = true})
    local quality = UI.Label {id = "deckQuality", text = Items.rarityNames[def.rarity],
        fontSize = 11 * s, fontColor = QUALITY_INK[def.rarity] or C.text,
        backgroundColor = {20, 24, 24, 245}, textMotionDisabled = true,
        textAlign = "center", verticalAlign = "middle",
        paddingHorizontal = 8 * s, paddingVertical = 2 * s, alignSelf = "flex-start"}
    local stats = ItemStats(self.game:_Value(item), self.game:CooldownOf(item.id), Items.TagsText(def))
    content:AddChild(UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10 * s,
        children = {
            Icon {itemId = item.id, width = 76 * s, height = 76 * s, pointerEvents = "none", flexShrink = 0},
            UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4 * s, children = {name, quality, stats}},
        }})
    local prose = Description {id = "deckDescription", text = ItemText.Effect(self.game, item.id, item), fontSize = 13 * s,
        onInspect = function(id) self:InspectDefinition(id) end}
    content:AddChild(UI.ScrollView {id = "deckEffectScroll", width = "100%", flexGrow = 1, flexBasis = 0,
        bounces = false, padding = 0, children = {prose}})
    body:AddChild(content)
end

---@param syncLayout boolean? 事件回调中立即排版；尺寸变化时由 UI 帧自行排版。
function View:BuildDeckPage(syncLayout)
    local body = self.deckBody
    if not body then return end
    local children = body:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    body:ClearChildren()
    self.deckBoard = nil
    local s = self.machineSkin and self.machineSkin.scale or 1
    local item = self.deckDetailUid ~= 0 and self.game:Get(self.deckDetailUid) or nil
    if item then
        self:BuildDeckDetail(body, item, s)
    else
        self:BuildDeckSandbox(body, s)
    end
    if syncLayout then UI.Layout() end
end

---@param uid integer
function View:ShowDeckItem(uid)
    if Busy(self.game) or not self.game:Get(uid) then return end
    self.deckDetailUid = uid
    self:BuildDeckPage(true)
end

-- 返回按钮分层后退：详情 → 沙盒 → 离开牌库回到原页面。
function View:DeckBack()
    if self.deckDetailUid ~= 0 then
        self.deckDetailUid = 0
        self:BuildDeckPage(true)
        return
    end
    self:CloseInventory()
end

-- 牌库沙盒只服务于牌库页；关闭、切换面板或换局时连同独立物理世界一起释放。
function View:DisposeDeckSim()
    self.deckBoard = nil
    if self.deckSim then
        self.deckSim:Dispose()
        self.deckSim = nil
    end
end

function View:CloseInventory()
    self.modal:Hide()
    self.inventoryOpen = false
    self.deckDetailUid = 0
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    if self.game.phase == "draft" and self.deckDraftWasOpen then self.draft:Show() end
    self.deckDraftWasOpen = false
    self:Update(true)
end

function View:OpenInventory()
    if Busy(self.game) then return end
    self:CloseDefinition()
    self:CloseItemDetail()
    -- 三选一页面被牌库页整体接管；返回时恢复原候选页。
    self.deckDraftWasOpen = self.draft:IsVisible()
    local panel=self.inventoryPanel
    if not panel or not panel.node or panel.parent~=self.modal then
        panel=self:Modal("我的牌库", true)
        self.inventoryPanel=panel
        self.inventoryTitle=panel:FindById("modalTitle") --[[@as Label]]
        self.deckBody=UI.Panel {id = "deckBody", width = "100%", flexGrow = 1, flexBasis = 0}
        panel:AddChild(self.deckBody)
    end
    self.inventoryOpen = true
    self.deckDetailUid = 0
    self:DisposeDeckSim()
    -- 每次打开牌库都让全部持有实例重新从顶部落下。
    self.deckSim = DeckBoard.Sim.New(self.game.deck)
    self.inventoryTitle:SetText("我的牌库 · "..#self.game.deck.." 件")
    if self.machineSkin then MachineSkin.Modal(self,panel,true) end
    self.modal:Show()
    -- 面板可见后再排版，隐藏节点的 Yoga display=none 会得到零尺寸。
    self:BuildDeckPage(true)
    -- 牌库页占据中央屏幕，隐藏会悬浮在其上的物理入口。
    self.physicsButton:Hide()
    self.physicsMenu:Hide()
    self:Update(true)
    print(string.format("[牌库] 物理沙盒打开：%d件从顶部落下",#self.game.deck))
end

function View:OpenHelp()
    if Busy(self.game) then return end
    local panel = self:Modal("摇摇牌库 · 玩法")
    local mood=Button("机台氛围 · "..Atmosphere.names[Storage.atmosphereMode],
        function() self:OpenAtmosphere() end)
    mood:SetStyle({width="100%",height=42})
    panel:AddChild(mood)
    local scroll = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 12, padding = 4}
    local rules = {
        {"01  抽取", "回合开始从牌库随机抽取最多 20 件进入瓶中。每回合可重抽一次；牌库不足时全部入瓶。"},
        {"02  摇晃", "点击开始后运行 10 秒，瓶中物品按各自说明实时执行反应（如 [[ball]] 碰撞瓶子价值+1、[[orange]] 接触瓶底价值+2）。瓶子左上可切换物理：物理一保留原版；物理二适合短距离来回摇动。Android／iOS 原生端自动启用体感；网页预览请触摸拖动；不操作照常计时。"},
        {"03  结算", "摇晃结束后禁止摇晃，物品自然下落 2 秒，期间不执行非结算效果；随后每件物品按当前价值一次性结算金币。"},
        {"04  价值规则", "价值默认临时：本回合的+价值在结算后、新回合开始时清零回基础值；描述写明“永久+N”才跨回合保留。冷却下限 1 秒，每回合重置、不跨回合。"},
        {"05  消耗", "消耗不等于移除：物品进入本回合弃牌堆，下回合开始清空。[[banana]] 被消耗时变为 [[banana_peel]]。"},
        {"06  成长", "[[banana]] 入瓶满 3 个回合（入瓶的回合开始计数）后，在结算完成时变为 [[rotten_banana]]。"},
        {"07  构筑", "结算后进入三选一，稀有度概率随考核阶段变化（第1次考核全为普通，第5次及以后65%/30%/3.75%/1%/0.25%）。选一件加入牌库；可刷新一次，也可跳过。"},
        {"08  考核", "每 5 回合进行一次考核：达成后扣除目标分数（40/80/140…，之后每阶段×1.3），余额保留；未达成则本局结束，不再进入三选一。"},
        {"09  上限", "瓶中物品上限 100 件；回合时间上限 99 秒。"},
        {"10  存档", "每个非摇晃/结算阶段自动保存。运行中退出回退到本回合开始前，包括牌库生成与永久变化。网页刷新不能保证本地存档保留，请使用存档码。"},
        {"11  开发进度", "当前版本已实装 [[apple]]、[[banana]]、[[orange]]、[[ball]] 及香蕉衍生物品；其余 60 件已录入图鉴但效果分批实装，暂不进入卡池。"},
    }
    for _, rule in ipairs(rules) do
        scroll:AddChild(UI.Card {width = "100%", gap = 5, padding = 12, backgroundColor = C.background,
            children = {Label(rule[1], 13, C.primary),
                Description {text = rule[2], fontSize = 11.25, fontColor = C.text,
                    onInspect = function(id) self:InspectDefinition(id) end}}})
    end
    panel:AddChild(scroll)
    local sensor = Button("启用／校准手机体感", function() self.actions.sensor() end)
    sensor:SetStyle({width = "100%"})
    panel:AddChild(sensor)
end

function View:OpenAtmosphere()
    if Busy(self.game) then return end
    local panel=self:Modal("机台氛围")
    panel:SetStyle({height="auto"})
    panel:AddChild(Label("调整屏幕的环境色，保留面板原有材质。",13,C.textSecondary))
    local descriptions={
        auto="默认 · 原色屏幕",
        brass="暖灯 · 原色屏幕",
        slate="冷夜 · 微冷玻璃",
        ember="余烬 · 微暖玻璃",
    }
    for _,id in ipairs(Atmosphere.order) do
        local button=Button((Storage.atmosphereMode==id and "● " or "○ ")..descriptions[id],function()
            self.actions.atmosphere(id)
            self.modal:Hide()
        end,Storage.atmosphereMode==id)
        button:SetStyle({width="100%",height=50,fontSize=15})
        panel:AddChild(button)
    end
end

--- GM 面板：接受数字编号 1–71 或字符串 id，由 Game:GmAddItem 统一匹配；未实装物品会被拒绝。
function View:OpenGm()
    if Busy(self.game) then return end
    local panel = self:Modal("GM 面板")
    panel:SetStyle({textMotionDisabled = true})
    panel:AddChild(UI.Label {text = "功能一 · 添加物品：输入数字编号 1–71 或字符串 id，全部71件可添加，加入牌库供后续抽取",
        fontSize = 11.25, fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"})
    local message = UI.Label {text = "输入数字或字符串 id；也可点击下方列表“添加”快捷加入",
        fontSize = 10.5, fontColor = C.primary, whiteSpace = "normal", width = "100%"}
    local field = UI.TextField {id = "gmItemId", placeholder = "数字 1–71 或 id，如 1 / apple",
        width = "100%", height = 48, fontSize = 12, fontFamily = "mono", flexGrow = 1, flexBasis = 0,
        onSubmit = function(self_, value)
            local id = value:match("^%s*(%S+)%s*$")
            if not id or id == "" then
                message:SetText("请先输入数字编号 1–71 或字符串 id")
                return
            end
            local ok, text = self.actions.gmadd(id)
            message:SetText(text or "")
            if ok then self_:SetValue("") end
        end}
    local submit = Button("添加", function()
        local value = field:GetValue()
        local id = value:match("^%s*(%S+)%s*$")
        if not id or id == "" then
            message:SetText("请先输入数字编号 1–71 或字符串 id")
            return
        end
        local ok, text = self.actions.gmadd(id)
        message:SetText(text or "")
        if ok then field:SetValue("") end
    end, true)
    submit:SetStyle({width = 84, height = 48, flexShrink = 0})
    panel:AddChild(UI.Panel {width = "100%", flexDirection = "row", gap = 10, alignItems = "center",
        children = {field, submit}})
    panel:AddChild(message)
    local scroll = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 6, padding = 4}
    for _, def in ipairs(Items.list) do
        local row = UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10,
            padding = 8, backgroundColor = C.background}
        row:AddChild(Icon {itemId = def.id, width = 36, height = 36, pointerEvents = "none", flexShrink = 0})
        row:AddChild(UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, pointerEvents = "none", children = {
            Label(def.name .. " · " .. Items.rarityNames[def.rarity]
                .. (def.implemented and "" or " · 未实装"), 11.25),
            UI.Label {text = string.format("%d · %s", def.numberId, def.id), fontSize = 11.25,
                fontFamily = "mono", fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"},
        }})
        local add = Button("添加", function()
            local ok, text = self.actions.gmadd(def.id)
            message:SetText(text or "")
            if ok then UI.Toast.Show(text, {duration = 2, variant = "success"}) end
        end)
        add:SetDisabled(not def.implemented)
        add:SetStyle({width = 64, height = 38, fontSize = 11.25, flexShrink = 0})
        row:AddChild(add)
        scroll:AddChild(row)
    end
    panel:AddChild(scroll)
end

function View:OpenSave()
    if Busy(self.game) then return end
    local panel = self:Modal("保存与继续")
    panel:AddChild(Label("本地状态：" .. Storage.status, 11, C.primary))
    panel:AddChild(UI.Label {text = "网页预览刷新后本地文件可能丢失。请复制下方存档码到外部保存，再粘贴导入。原生平台使用本地自动存档。",
        whiteSpace = "normal", width = "100%", fontSize = 11, fontColor = C.textSecondary})
    local code = Storage.Export(self.game)
    local field = UI.TextField {value = code, width = "100%", height = 54, fontSize = 10,
        fontFamily = "mono"}
    panel:AddChild(field)
    panel:AddChild(Label("点击输入框，全选并复制；导入时替换为已保存的完整内容。", 10, C.textSecondary))
    local message = Label("摇晃阶段的存档会回退本回合所有变化。", 10, C.textSecondary)
    panel:AddChild(message)
    local import = Button("导入此存档", function()
        local ok, errorText = self.actions.import(field:GetValue())
        if ok then self.modal:Hide() else message:SetText(errorText or "导入失败") end
    end, true)
    import:SetStyle({width = "100%"})
    panel:AddChild(import)
    panel:AddChild(Button("开始新的一局", function() self:ConfirmNewRun() end))
end

function View:ConfirmNewRun()
    local panel = self:Modal("开始新的一局？")
    panel:SetStyle({height = 260})
    panel:AddChild(UI.Label {text = "当前自动存档将被新局覆盖。如需保留，请先导出存档码。",
        whiteSpace = "normal", width = "100%", fontSize = 12, fontColor = C.textSecondary})
    panel:AddChild(Button("确认开始新局", function() self.actions.newrun(); self.modal:Hide() end, true))
end

return View
