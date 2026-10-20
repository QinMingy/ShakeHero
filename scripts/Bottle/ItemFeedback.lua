-- 物品动作的纯表现状态；坐标为米、Y向上，Board负责裁剪和DPR。
-- 只读取语义事件与真实姿态；不写玩法/物理、不调用玩法随机数，渲染不推进计时。
local Items = require("Bottle.Items")
local FrameBudget = require("Bottle.FrameBudget")
local Draw = require("Bottle.ItemFeedbackDraw")
local Pool = require("Bottle.RecordPool")
local particlePool, effectPool, starPool = Pool.New(768), Pool.New(192), Pool.New(128)

---@class BottleItemFeedbackParticle
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field age number
---@field life number
---@field size number
---@field color number[]
---@field shape string
---@field ownerUid number?
---@field behind boolean

---@class BottleItemFeedbackPose
---@field action string
---@field uid number
---@field id string
---@field targetUid number?
---@field targetId string?
---@field x number
---@field y number
---@field tx number
---@field ty number
---@field age number
---@field life number
---@field value number
---@field count number
---@field radius number

---@class BottleItemFeedback
---@field effects BottleItemFeedbackPose[]
---@field particles BottleItemFeedbackParticle[]
---@field stars table<number,{x:number,y:number,carry:number}>
---@field seen table<table,boolean>
---@field serial number
---@field starCursor number 下帧从上一批已发射星星之后继续，避免低UID独占预算
---@field _present table<number,boolean>
---@field _ids number[]
local Feedback = {}
Feedback.__index = Feedback
Feedback.MAX_PARTICLES, Feedback.MAX_EFFECTS = 384, 96
Feedback.STAR_SPACING, Feedback.STAR_STEP_LIMIT = .085, 32
local LIFE = {cut=.24, jelly=.34, grow=.48, produce=.55, steal=.58}
local GOLD, GREEN, BLUE = {255,211,83}, {133,224,128}, {127,211,255}
local CHICK = {255,244,204}

---@param value number?
---@return boolean
local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

-- 不对缺失刚体调用GetPose：该接口的默认原点不是物品真实位置。
---@param physics BottlePhysics?
---@param uid number?
---@param x number?
---@param y number?
---@return number? x, number? y
local function Position(physics, uid, x, y)
    if Finite(x) and Finite(y) then return x, y end
    if physics and uid and physics.bodies[uid] then
        local px, py = physics:GetPose(uid)
        if Finite(px) and Finite(py) then return px, py end
    end
    return nil, nil
end

---@return BottleItemFeedback
function Feedback.New()
    local self = setmetatable({}, Feedback)
    self:Reset()
    return self
end

function Feedback:Reset()
    if self.effects then effectPool:ClearActive(self.effects) else self.effects = {} end
    if self.particles then particlePool:ClearActive(self.particles) else self.particles = {} end
    if self.stars then
        for uid, sample in pairs(self.stars) do starPool:Release(sample);self.stars[uid] = nil end
    else self.stars = {} end
    if self.seen then for event in pairs(self.seen) do self.seen[event] = nil end
    else self.seen = setmetatable({}, {__mode="k"}) end
    self._present, self._ids = self._present or {}, self._ids or {}
    self.serial = 0
    self.starCursor = 0
end

-- 独立确定性外观序列；不影响任何游戏抽签。
---@return number
function Feedback:Noise()
    self.serial = (self.serial + 1) % 65521
    return ((self.serial * 173 + 97) % 1021) / 1021
end

---@param particle BottleItemFeedbackParticle
function Feedback:Particle(particle)
    if #self.particles >= Feedback.MAX_PARTICLES then particlePool:Release(table.remove(self.particles, 1)) end
    self.particles[#self.particles + 1] = particle
end

---@param uid number
function Feedback:ForgetStar(uid)
    local sample = self.stars[uid]
    if sample then starPool:Release(sample);self.stars[uid] = nil end
    local count, kept = #self.particles, 0
    for index = 1, count do
        local particle = self.particles[index]
        if particle.ownerUid == uid then particlePool:Release(particle)
        else kept = kept + 1;self.particles[kept] = particle end
    end
    for index = count, kept + 1, -1 do self.particles[index] = nil end
end

---@param effect BottleItemFeedbackPose
---@param color number[]
---@param count number
---@param shape string
---@param centerX number?
---@param centerY number?
function Feedback:Scatter(effect, color, count, shape, centerX, centerY)
    for _ = 1, math.min(12, count) do
        local angle = self:Noise() * math.pi * 2
        local speed = .3 + self:Noise() * .55
        local particle = particlePool:Acquire() --[[@as BottleItemFeedbackParticle]]
        particle.x, particle.y = centerX or effect.x, centerY or effect.y
        particle.vx, particle.vy = math.cos(angle)*speed, .2 + math.sin(angle)*speed
        particle.age, particle.life, particle.size = 0, .24+self:Noise()*.2, .025+self:Noise()*.025
        particle.color, particle.shape, particle.behind = color, shape, false
        self:Particle(particle)
    end
end

---@param events GameEvent[]
---@param physics BottlePhysics?
function Feedback:Events(events, physics)
    for _, event in ipairs(events) do
        FrameBudget.Checkpoint()
        local uid = event.uid
        if uid and (event.kind == "respawn" or event.kind == "teleport") then
            -- 闪现只断开采样：原处已经留下的金点自然淡出，下一姿态重新起笔。
            local previous = self.stars[uid]
            if previous then starPool:Release(previous);self.stars[uid] = nil end
        elseif uid and (event.kind == "remove" or event.kind == "transform" or event.kind == "consume") then
            self:ForgetStar(uid)
        end
        local life = event.action and LIFE[event.action]
        if event.kind == "itemFeedback" and life and uid and not self.seen[event]
            and (event.action ~= "steal" or math.abs(event.value or 0) > 1e-9) then
            self.seen[event] = true
            local x, y = Position(physics, uid, event.x, event.y)
            local tx, ty = Position(physics, event.targetUid, event.toX, event.toY)
            if event.action == "cut" and tx == nil then tx, ty = x, y end
            if x ~= nil and y ~= nil then
                local id = event.id or ""
                local def = Items.byId[id]
                local source = physics and physics.bodies[uid]
                local sourceRadius = nil ---@type number?
                if source and source.kind == id then sourceRadius = source.radius end
                local effect = effectPool:Acquire() --[[@as BottleItemFeedbackPose]]
                effect.action, effect.uid, effect.id = event.action or "", uid, id
                effect.targetUid, effect.targetId = event.targetUid, event.targetId
                effect.x, effect.y, effect.tx, effect.ty = x, y, tx or x, ty or y
                effect.age, effect.life = 0, life
                effect.value, effect.count = event.value or 0, math.max(1, event.count or 1)
                effect.radius = Finite(sourceRadius) and sourceRadius > 0 and sourceRadius or (def and def.radius or .32)
                if #self.effects >= Feedback.MAX_EFFECTS then effectPool:Release(table.remove(self.effects, 1)) end
                self.effects[#self.effects + 1] = effect
                if effect.action == "cut" then
                    local fruit = effect.targetId and Items.byId[effect.targetId]
                    self:Scatter(effect, fruit and fruit.color or GOLD, 6, "juice", effect.tx, effect.ty)
                elseif effect.action == "produce" then
                    local color = id == "fruit_tree" and GREEN or id == "cloud" and BLUE
                        or id == "chick" and CHICK or GOLD
                    local shape = id == "fruit_tree" and "leaf" or id == "cloud" and "drop" or "square"
                    self:Scatter(effect, color, math.min(10, 6+effect.count), shape)
                elseif effect.action == "steal" and effect.value > 0 then
                    -- 幸运类增益：只在受益者附近亮起，不把正收益画成失窃。
                    self:Scatter(effect, GREEN, 4, "square", effect.tx, effect.ty)
                end
            end
        end
    end
end

---@param physics BottlePhysics
---@param dt number
function Feedback:SampleStars(physics, dt)
    local present, ids = self._present, self._ids
    for uid in pairs(present) do present[uid] = nil end
    for index = #ids, 1, -1 do ids[index] = nil end
    for uid, record in pairs(physics.bodies) do
        if record.kind == "star" then ids[#ids + 1] = uid; present[uid] = true end
    end
    table.sort(ids)
    for uid in pairs(self.stars) do if not present[uid] then self:ForgetStar(uid) end end
    local count, kept = #self.particles, 0
    for index = 1, count do
        local particle = self.particles[index]
        local owner = particle.ownerUid
        if owner and not present[owner] then particlePool:Release(particle)
        else kept = kept + 1;self.particles[kept] = particle end
    end
    for index = count, kept + 1, -1 do self.particles[index] = nil end
    local budget = Feedback.STAR_STEP_LIMIT
    local start = self.starCursor % math.max(1, #ids)
    local lastEmitted = nil ---@type number?
    for offset = 1, #ids do
        local slot = (start + offset - 1) % #ids + 1
        local uid = assert(ids[slot])
        local x, y = physics:GetPose(uid)
        if Finite(x) and Finite(y) then
            local previous = self.stars[uid]
            local carry = 0.0
            if previous and dt > 0 and dt <= .12 then
                local dx, dy = x-previous.x, y-previous.y
                local distance = math.sqrt(dx*dx + dy*dy)
                -- 只采样真实下落；超长位移作断点，大dt不补发历史粒子。
                if dy < -.006 and distance > .012 and distance < 1.5 then
                    local total = distance + previous.carry
                    local needed = math.floor(total / Feedback.STAR_SPACING)
                    local count = math.min(8, budget, needed)
                    for index = 1, count do
                        local along = Feedback.STAR_SPACING*index - previous.carry
                        local t = math.max(0, math.min(1, along / distance))
                        local jitter = (self:Noise()-.5)*.04
                        local particle = particlePool:Acquire() --[[@as BottleItemFeedbackParticle]]
                        particle.x, particle.y = previous.x+dx*t-dy/distance*jitter, previous.y+dy*t+dx/distance*jitter
                        particle.vx, particle.vy = (self:Noise()-.5)*.08, .03+self:Noise()*.07
                        particle.age, particle.life, particle.size = 0, .30+self:Noise()*.22, .018+self:Noise()*.026
                        particle.color, particle.shape = GOLD, index%3 == 0 and "spark" or "square"
                        particle.ownerUid, particle.behind = uid, true
                        self:Particle(particle)
                    end
                    budget = budget-count
                    if count > 0 then lastEmitted = slot end
                    -- 达上限时丢弃积压，后续帧不会补成一团。
                    carry = needed <= count and total-needed*Feedback.STAR_SPACING or 0
                end
            end
            local sample = previous or starPool:Acquire()
            sample.x, sample.y, sample.carry = x, y, carry
            self.stars[uid] = sample
        else self:ForgetStar(uid) end
    end
    self.starCursor = lastEmitted or ((start + 1) % math.max(1, #ids))
end

---@param dt number
---@param physics BottlePhysics?
---@param game BottleGame?
function Feedback:Update(dt, physics, game)
    local elapsed = Finite(dt) and math.max(0, dt) or 0
    local effectCount, keptEffects = #self.effects, 0
    for index = 1, effectCount do
        local effect = self.effects[index]
        effect.age = effect.age + elapsed
        if effect.age >= effect.life then effectPool:Release(effect)
        else
            keptEffects = keptEffects + 1;self.effects[keptEffects] = effect
            if physics then
            local record = physics.bodies[effect.uid]
            local expected = effect.action == "grow" and effect.targetId or effect.id
            if record and record.kind == expected and effect.action ~= "cut" then
                effect.x, effect.y = physics:GetPose(effect.uid)
                if Finite(record.radius) and record.radius > 0 then effect.radius = record.radius end
            end
            local target = effect.targetUid and physics.bodies[effect.targetUid]
            if effect.action == "steal" and target and target.kind == effect.targetId and effect.targetUid then
                effect.tx, effect.ty = physics:GetPose(effect.targetUid)
            end
            end
        end
    end
    for index = effectCount, keptEffects + 1, -1 do self.effects[index] = nil end
    local particleCount, keptParticles = #self.particles, 0
    for index = 1, particleCount do
        local particle = self.particles[index]
        particle.age = particle.age + elapsed
        if particle.age >= particle.life then particlePool:Release(particle)
        else
            particle.x = particle.x + particle.vx*elapsed
            particle.y = particle.y + particle.vy*elapsed
            if not particle.behind then particle.vy = particle.vy-1.5*elapsed end
            keptParticles = keptParticles + 1;self.particles[keptParticles] = particle
        end
    end
    for index = particleCount, keptParticles + 1, -1 do self.particles[index] = nil end
    if physics then self:SampleStars(physics, elapsed)
    else
        for uid, sample in pairs(self.stars) do starPool:Release(sample);self.stars[uid] = nil end
        local count, kept = #self.particles, 0
        for index = 1, count do
            local particle = self.particles[index]
            if particle.ownerUid then particlePool:Release(particle)
            else kept = kept + 1;self.particles[kept] = particle end
        end
        for index = count, kept + 1, -1 do self.particles[index] = nil end
    end
end

function Feedback.PoolStats()
    return particlePool:GetStats(), effectPool:GetStats(), starPool:GetStats()
end

---@param uid number
---@return number scaleX, number scaleY
function Feedback:Transform(uid)
    local sx, sy = 1.0, 1.0
    for _, effect in ipairs(self.effects) do
        if effect.uid == uid then
            local t = effect.age / effect.life
            if effect.action == "jelly" then
                local squash = .23*math.sin(t*math.pi*3)*math.exp(-3*t)
                sx, sy = sx*(1+squash), sy*(1-squash)
            elseif effect.action == "produce" then
                -- 先明显压扁再向上弹出，末段小幅回摆；只缩放视觉，不加物理冲量。
                local squash = .33*math.sin(t*math.pi*3)*(1-t)
                sx, sy = sx*(1+squash), sy*(1-squash)
            end
        end
    end
    return math.max(.72, math.min(1.3, sx)), math.max(.72, math.min(1.3, sy))
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
function Feedback:RenderBehind(vg, x, y, ppu) Draw.Behind(self, vg, x, y, ppu) end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
function Feedback:RenderFront(vg, x, y, ppu) Draw.Front(self, vg, x, y, ppu) end

return Feedback
