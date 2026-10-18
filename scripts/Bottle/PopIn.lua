-- 物品入瓶/出现的弹跳动效与受重力像素粒子（纯表现：不参与规则、物理、收益与存档）。
-- 弹跳参考三选一选中 icon 的欠阻尼弹簧（LayeredSkin.spring 同一响应形式）：
--   0 → 过冲约1.25 → 回摆 → 稳定1；“突突突”节奏由同一批物品的错峰延迟给出。
-- 粒子以物品自身色板取色，径向迸发后受 (0,-9.81) 重力下落，瓶底/瓶壁反弹并淡出。
-- 随机外观用私有 Park-Miller（种子由 uid 与 game.revision 派生），不调用 math.random、
-- 不消耗玩法随机序列。
local Art = require("Bottle.Art")
local PopIn = {}

local STAGGER = .09       -- 同批物品错峰间隔（秒），形成“突突突”的连续节奏
-- 每件物品按序号独立错峰，不设延迟上限：截断会让超出上限的物品同时出现
-- （曾导致第8件起“一股脑全部出来”，用户反馈）。大抽取的出场会自然按序铺开。
local DAMPING, FREQUENCY = 8, 20 -- 与三选一弹簧同一响应形式（回摆约1.25、约0.5秒稳定）
local POP_WINDOW = .7     -- 单个弹跳动效最长保留时间（秒）
local GRAVITY = 9.81      -- 米/秒²，与瓶内物理重力一致
local BURST_COUNT = 11    -- 每件物品迸发的像素粒子数
local MIN_SPEED, MAX_SPEED = 1.4, 3.4 -- 粒子径向初速范围（米/秒）
local UP_BIAS = 1.0       -- 初速度向上的偏置（米/秒），让爆点更饱满
local WALL = 2.31         -- 瓶内壁半宽（米），粒子反弹边界
local FLOOR = .06         -- 瓶底反弹高度（米）
local RESTITUTION = .45   -- 反弹速度损耗

PopIn.STAGGER, PopIn.POP_WINDOW = STAGGER, POP_WINDOW
PopIn.INFLATION_DURATION, PopIn.EXPLOSION_LIFETIME = .55, .65

---@class BottleInflation
---@field fromRadius number
---@field targetRadius number
---@field radius number
---@field age number
---@field duration number

-- 气球膨胀是单调的尺寸过渡，不使用会回摆的出现弹簧；终点永久来自实例 scale。
---@param fromRadius number
---@param targetRadius number
---@return BottleInflation
function PopIn.NewInflation(fromRadius, targetRadius)
    return {fromRadius = fromRadius, targetRadius = targetRadius, radius = fromRadius,
        age = 0, duration = PopIn.INFLATION_DURATION}
end

---@param pose BottleInflation
---@param dt number
---@return boolean finished
function PopIn.StepInflation(pose, dt)
    pose.age = math.min(pose.duration, pose.age + math.max(0, dt))
    local t = pose.age / pose.duration
    local ease = t * t * (3 - 2 * t)
    pose.radius = pose.fromRadius + (pose.targetRadius - pose.fromRadius) * ease
    if pose.age >= pose.duration then pose.radius = pose.targetRadius; return true end
    return false
end

---@param seed number 种子可为浮点（存档恢复的 revision 不保证整数子类型）
---@param index integer
---@return number 0..1
local function seededRandom(seed, index)
    seed = math.abs(seed) % 2147483647
    local state = (seed * 48271 + index * 104729) % 2147483646 + 1
    state = (state * 48271) % 2147483647
    if state == 0 then state = 1 end
    return (state - 1) / 2147483646
end

-- 解析欠阻尼弹簧：低帧率/大 dt 不逐帧累积爆振，与三选一同一公式形式。
---@param value number
---@param velocity number
---@param target number
---@param dt number
---@return number value
---@return number velocity
local function spring(value, velocity, target, dt)
    local wave = math.sqrt(FREQUENCY * FREQUENCY - DAMPING * DAMPING)
    local delta = value - target
    local c, s, decay = math.cos(wave * dt), math.sin(wave * dt), math.exp(-DAMPING * dt)
    return target + decay * (delta * c + (velocity + DAMPING * delta) / wave * s),
        decay * (velocity * c - (DAMPING * velocity + FREQUENCY * FREQUENCY * delta) / wave * s)
end

---@class BottlePopPose
---@field uid number
---@field id string
---@field delay number 错峰延迟；>0 时物品保持不可见，越过0才弹跳出现
---@field age number
---@field started boolean 已开始弹跳（delay=0 的弹跳第一帧即激活）
---@field scale number 0 → 过冲 → 1
---@field scaleVelocity number
---@field angle number 轻微角回摆偏移（弧度），叠加在物理姿态上
---@field angleVelocity number
---@field x number? 生成事件坐标；无刚体时作为粒子迸发原点
---@field y number?

---@param uid number
---@param id string
---@param delay number?
---@return BottlePopPose
function PopIn.NewPose(uid, id, delay)
    return {
        uid = uid, id = id, delay = delay or 0, age = 0, started = false,
        scale = 0, scaleVelocity = 0,
        -- 幽灵只缩放弹出、始终直立；其他物品按 uid 奇偶交错角回摆。
        angle = 0, angleVelocity = id == "ghost" and 0 or (uid % 2 == 0 and 1 or -1) * .9,
    }
end

-- 推进弹跳动效；返回 true 仅一次（弹跳开始的那帧），调用方此时迸发粒子并播放音效。
---@param pose BottlePopPose
---@param dt number
---@return boolean activated
function PopIn.Step(pose, dt)
    dt = math.max(0, dt)
    local activated = false
    if pose.delay > 0 then
        pose.delay = pose.delay - dt
        if pose.delay > 0 then return false end
        dt = -pose.delay -- 结转越过延迟的剩余时间，激活当帧即开始弹起
        pose.delay = 0
        activated = true
    elseif not pose.started then
        activated = true -- 无错峰延迟的弹跳（生成事件/同批第一件）第一帧激活
    end
    pose.started = true
    pose.age = pose.age + dt
    pose.scale, pose.scaleVelocity = spring(pose.scale, pose.scaleVelocity, 1, dt)
    pose.angle, pose.angleVelocity = spring(pose.angle, pose.angleVelocity, 0, dt)
    if math.abs(pose.scale - 1) < .001 and math.abs(pose.scaleVelocity) < .01 then
        pose.scale, pose.scaleVelocity = 1, 0
    end
    if math.abs(pose.angle) < .001 and math.abs(pose.angleVelocity) < .01 then
        pose.angle, pose.angleVelocity = 0, 0
    end
    return activated
end

---@class BottlePopParticle
---@field x number 瓶内米制坐标
---@field y number
---@field vx number
---@field vy number
---@field age number
---@field life number
---@field size number 屏幕像素方粒边长
---@field color number[]

-- 以物品色板取色的像素粒子迸发；外观只与 (seed, 序号) 有关，可复现且不占玩法随机。
---@param x number
---@param y number
---@param id string
---@param seed number
---@param explosionRadius number? 仅气球爆炸使用；nil 保持原出现粒子参数
---@return BottlePopParticle[]
function PopIn.Burst(x, y, id, seed, explosionRadius)
    local colors = Art.ItemColors(id)
    local particles = {}
    local count = explosionRadius and 32 or BURST_COUNT
    local minSpeed, maxSpeed = explosionRadius and 2.6 or MIN_SPEED, explosionRadius and 5.5 or MAX_SPEED
    for index = 1, count do
        local angle = seededRandom(seed, index) * math.pi * 2
        local speed = minSpeed + (maxSpeed - minSpeed) * seededRandom(seed, index + 101)
        local offset = (explosionRadius or 0) * (.35 + .5 * seededRandom(seed, index + 401))
        particles[#particles + 1] = {
            x = x + math.cos(angle) * offset, y = y + math.sin(angle) * offset,
            vx = math.cos(angle) * speed,
            vy = math.sin(angle) * speed + UP_BIAS,
            age = 0,
            life = (explosionRadius and .65 or .5) + .35 * seededRandom(seed, index + 211),
            size = (explosionRadius and 3 or 2) + math.floor(seededRandom(seed, index + 311) * 3),
            color = colors[1 + index % #colors],
        }
    end
    return particles
end

-- 独立于入场粒子的气球碎片：同种子可重现，绝不调用玩法随机或施加物理冲量。
---@param x number
---@param y number
---@param id string
---@param seed number
---@param radius number
---@return BottlePopParticle[]
function PopIn.Explosion(x, y, id, seed, radius)
    return PopIn.Burst(x, y, id, seed, radius)
end

-- 重力步进：瓶底/瓶壁反弹并损耗，到期粒子就地移除。
---@param particles BottlePopParticle[]
---@param dt number
function PopIn.StepParticles(particles, dt)
    dt = math.max(0, dt)
    for i = #particles, 1, -1 do
        local p = particles[i]
        p.age = p.age + dt
        if p.age >= p.life then
            table.remove(particles, i)
        else
            p.vy = p.vy - GRAVITY * dt
            p.x = p.x + p.vx * dt
            p.y = p.y + p.vy * dt
            if p.y <= FLOOR and p.vy < 0 then
                p.y, p.vy = FLOOR, -p.vy * RESTITUTION
            end
            if math.abs(p.x) >= WALL then
                p.x = p.x < 0 and -WALL or WALL
                p.vx = -p.vx * RESTITUTION
            end
        end
    end
end

return PopIn
