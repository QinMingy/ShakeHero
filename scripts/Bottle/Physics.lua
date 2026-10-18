-- 瓶内局部坐标的 Box2D 世界，基于 templates/scaffold-2d-physics.lua。
-- 主程序负责绘制、全局事件订阅与固定步长时钟；本模块不创建相机或 UI。
-- 所有长度单位为米，+Y 向上；视觉偏移只能在主程序/Render 中处理。
-- V0.4：幽灵使用真实动态 sensor 接触，自主漂移，不接受碰撞或摇瓶冲量；
-- 保留瓶体、接触计数、随机散布、近源生成搜索、两种摇晃物理与体感接入。
--
-- 碰撞设计（实现碰撞体前先画图）：
--                        x=-1.15       x=1.15
--                 y=6.4       +-------+       封闭瓶口
--                             |       |       竖直瓶颈
--                y=6.05       +       +
--                            /         \
--                y=5.5  +--/           \--+  倾斜瓶肩
--                        |   o   \___/     |  圆形 / 简化弯月凸片
--                        |                 |  x = -2.4 .. 2.4
--                 y=0    +-----------------+  瓶底内表面恰好 y=0
--
-- 检测目的：真实 Begin/EndContact2D 事件 -> 物品接触对、触底/触顶/全部内壁状态。
-- 擦边只有 Box2D 报告才算接触；生成位置的净空计算不参与接触判定。
-- 不规则硬物由凸片/偏移圆组成，同一刚体见 Bottle.Shapes；培根用5段关节软体。
-- 复合碰撞体逐次计数：结束其中一个 fixture 接触不清除其他有效接触。
-- 幽灵：  实体A [  <ghost sensor>  ] 实体B   （穿透，不输出冲量/碰撞音）
-- sensor 保持 ITEM_CATEGORY/ITEM_MASK + BT_DYNAMIC，真实Begin/End用于灵魂联动。
-- 瓶壁不再实体挡幽灵；有限轮廓近壁转向 + 下一步安全点限速 + 解锁后几何兜底。
-- 边界包含底/封口、肩颈接缝与凹角：整个旋转包络留在瓶中，不以几何距离伪造接触。
-- 墙体内表面沿瓶子轮廓，厚度向外，相邻接缝重叠；瓶肩/瓶颈凹角不延长。
-- 全局 CCD 与各物品 bullet 均开启。
-- 新物品零初速度并有短时 CCD/速度缓冲，拥挤位置由真实物理解算排开。
-- 接触回调内绝不 Remove/Dispose：先标记待删除，scene 更新返回后再销毁。
-- 非运行期只用 dt=0 的删除屏障，不预结算重力、不消耗任何回合时间。

local Items = require "Bottle.Items"
local Shapes = require("Bottle.Shapes")
local ShakeMotion = require "Bottle.ShakeMotion"
local SoftBacon = require "Bottle.SoftBacon"
local PhysicalState = require "Bottle.PhysicalState"
local ExpansionPhysics = require "Bottle.ExpansionPhysics"

---@class BottleBodyPart
---@field node Node
---@field body RigidBody2D

---@class BottleBody
---@field uid number
---@field node Node
---@field body RigidBody2D
---@field parts BottleBodyPart[] 包含中心刚体；普通物品1段、培根5段
---@field soft BottleSoftBacon?
---@field radius number
---@field kind string 物品定义 id，不是碰撞形状名称。
---@field shape string
---@field envelope number 旋转包络半径，仅用于寻找生成位置。
---@field scale number 体积倍率；与 item.scale 不一致时重建 body 保持位置。
---@field weight number 同尺寸原质量倍率；只改重量时更新密度，不重建接触/软体关节
---@field shapes CollisionShape2D[] 普通物品全部 fixture；软体由 soft.segments 持有
---@field sensor boolean 实际穿透体态，不修改全局物品定义
---@field ghostLike boolean 幽灵/幽灵便便自主流场、直立且免摇晃
---@field newbornRemaining number
---@field lastX number 上次采样的中心 x（米），用于累计位移。
---@field lastY number 上次采样的中心 y（米），用于累计位移。

---@class BottlePhysicsSpawn
---@field x number
---@field y number

---@class BottlePhysicsPair
---@field a number
---@field b number
---@field count number

---@class BottleImpactContact
---@field a number
---@field b number?
---@field count number
---@field endedAt number?

---@class BottleImpact
---@field speed number
---@field pair boolean
---@field key string

---@class BottlePhysicsContacts : BottleContacts
---@field pairs number[][] 每项为 {uidA, uidB}，且 uidA < uidB。
---@field bottom table<number, boolean>
---@field top table<number, boolean> 只计横向 top 封口，不包括瓶肩/瓶颈
---@field wall table<number, boolean> 全部静态内壁，含 floor/top/side/shoulder/neck
---@field positions table<number, BottlePhysicsSpawn> 所有当前存活 body 的中心坐标（米）
---@field side table<number, boolean> 左右侧壁，含肩颈、不含底顶
---@field angles table<number, number> 逆时针角度（弧度）
---@field rotateOffsets table<number, number> 累计强制角差，不计指南针自然转角
---@field angularTravel table<number, number> 累计自然绝对角路程；reset归零
---@field flightArrived table<number, boolean> 飞行结束，保持到下次flight/teleport/reset
---@field flightHits table<number, number> 真实Box2D命中的目标uid
---@field shakeStrength number 单步强摇输入dv幅值，阈值4m/s，0.35秒防抖，无输入0

---@class BottlePhysicsOptions
---@field accelerator boolean?
---@field ghostPoop boolean?

---@class BottlePhysicsSyncRequest
---@field items ItemInstance[]
---@field reset boolean
---@field seed number?
---@field options BottlePhysicsOptions?

---@class BottleRebuiltPart
---@field x number 相对于旧中心的偏移（米）
---@field y number
---@field angle number 度
---@field vx number
---@field vy number
---@field angularVelocity number

---@class BottleRebuiltBody
---@field x number
---@field y number
---@field radius number
---@field newbornRemaining number
---@field parts BottleRebuiltPart[]
---@field motion BottleExpansionMotion 仅累计必继承，行为由兼容性单独决定
---@field keepPose boolean 尺寸/同类型形态重建保持姿态速度；明确重生除外
---@field keepBehavior boolean

---@class BottlePhysics
---@field speedMultiplier number 线移动速度倍率；不改变固定dt或规则计时
---@field ghostPoop boolean 四类便便是否使用幽灵sensor物理
---@field scene Scene
---@field world PhysicsWorld2D
---@field bodies table<number, BottleBody>
---@field _walls Node[]
---@field _pairs table<string, BottlePhysicsPair>
---@field _bottom table<number, number>
---@field _top table<number, number>
---@field _wall table<number, number>
---@field _impactContacts table<string, BottleImpactContact> 独立的声音接触状态，不参与玩法接触判定
---@field _impacts BottleImpact[]
---@field _side table<number, number>
---@field expansion BottleExpansionPhysics 扩展动作与真实输入采样
---@field _exactSpawns table<number, BottlePhysicsSpawn>
---@field _retired BottleBody[]
---@field _mergeSpawns table<number, BottlePhysicsSpawn>
---@field _nearSpawns table<number, BottlePhysicsSpawn>
---@field _eventRemoved table<number, boolean>
---@field _respawned table<number, boolean> 明确重生的位置/行为语义，不能与resize重建混淆
---@field _updating boolean
---@field _flushing boolean
---@field _disposed boolean
---@field _disposeRequested boolean
---@field _clearRequested boolean
---@field _pendingSync BottlePhysicsSyncRequest?
---@field _layoutSeed number 私有散布种子
---@field clock number 只由正 dt 的 Step 推进；Clear/重置布局归零，普通 Sync 保留
---@field mode number
---@field motion BottleShakeMotion
local Physics = {}
Physics.__index = Physics

local HALF_WIDTH = 2.4
local HEIGHT = 6.4
local SHOULDER_Y = 5.5
local NECK_Y = 6.05
local NECK_HALF_WIDTH = 1.15
local WALL_THICKNESS = 0.24
local SPAWN_GAP = 0.025
-- 重置布局每件物品的私有随机候选抽样次数；失败时取重叠最小候选。
local SCATTER_TRIES = 32
local SHOULDER_SLOPE = (HALF_WIDTH - NECK_HALF_WIDTH) / (NECK_Y - SHOULDER_Y)
local NEWBORN_SECONDS = 0.10
local NEWBORN_MAX_SPEED = 8.0
local SHAKE_GAIN = 18.0 -- 拖动米数 -> 速度变化量（米/秒）
local MAX_SHAKE_DELTA = 0.45
local DEFAULT_RADIUS = 0.27
local RNG_MODULUS = 2147483647
local RNG_DOMAIN = RNG_MODULUS - 1
local WALL_CATEGORY = 1
local ITEM_CATEGORY = 2
local ITEM_MASK = WALL_CATEGORY | ITEM_CATEGORY
local IMPACT_SEPARATION = .025 -- 同一对必须真正分开至少25ms才重新发声；不限制其他接触

---@param name string
---@param fallback number
---@return number
local function setting(name, fallback)
    local value = (Items.Settings or {})[name]
    if type(value) == "number" and value == value and value > 0 and value < math.huge then
        return value
    end
    return fallback
end

local NEAR_SPAWN_RADIUS = setting("nearSpawnRadius", 0.4)

---@param value number?
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param seed number
---@return number
local function normalizeSeed(seed)
    return (math.floor(seed) % RNG_DOMAIN) + 1
end

---@param seed number
---@return number nextSeed
---@return number fraction
local function randomStep(seed)
    local nextSeed = (seed * 48271) % RNG_MODULUS
    return nextSeed, (nextSeed - 1) / RNG_DOMAIN
end

---@param value number
---@param low number
---@param high number
---@return number
local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

---@param shape CollisionShape2D
---@param category integer?
---@param mask integer?
local function setSurface(shape, category, mask)
    shape.density = 1.0
    shape.friction = 0.25
    shape.restitution = 0.35
    -- 默认仅用于物品；_Wall 显式传入墙组，不能被新增类别覆盖。
    shape.categoryBits = category or ITEM_CATEGORY
    shape.maskBits = mask or ITEM_MASK
end

---@param node Node
---@param profile BottleCollisionProfile
---@param radius number
---@param mirror boolean
---@param sensor boolean?
---@return CollisionShape2D[]
local function createProfile(node, profile, radius, mirror, sensor)
    ---@type CollisionShape2D[]
    local shapes = {}
    for _, points in ipairs(profile.polygons or {}) do
        local polygon = node:CreateComponent("CollisionPolygon2D")
        polygon:SetVertexCount(#points // 2)
        -- 翻转图案 Y 后统一为逆时针绕序；镜像鞋再翻转 X。
        -- SetVertices 的原生数组绑定不接受 Lua Vector2 值表，使用逐点 API。
        local first, last, step = #points - 1, 1, -2
        if mirror then first, last, step = 1, #points - 1, 2 end
        for i = first, last, step do
            local x = (points[i] - 8) * radius / 8
            local y = (8 - points[i + 1]) * radius / 8
            -- SetVertex 是已验收的原生零基接口，不是 Lua 数组下标。
            local index = math.abs(i - first) // 2
            polygon:SetVertex(index, Vector2(mirror and -x or x, y))
        end
        setSurface(polygon)
        polygon.trigger = sensor == true
        shapes[#shapes + 1] = polygon
    end
    for _, spec in ipairs(profile.circles or {}) do
        local x = (spec.x - 8) * radius / 8
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = spec.radius * radius / 8
        circle.center = Vector2(mirror and -x or x, (8 - spec.y) * radius / 8)
        setSurface(circle)
        circle.trigger = sensor == true
        shapes[#shapes + 1] = circle
    end
    return shapes
end

---@param id string
---@return number radius
---@return string shape
---@return number envelope
---@param woolCount number?
local function dimensions(id, woolCount)
    local def = assert(Items.byId[id], "[Bottle.Physics] 未知物品 id：" .. id)
    -- Items 是尺寸唯一源，不能用旧 .32 上限截断统一放大倍率。
    local radius = def.radius
    assert(radius > 0 and radius < math.huge, "[Bottle.Physics] 物品尺寸必须为有限正数")
    ---@type string
    local shape = id == "sheep" and Shapes.Variant(id, woolCount) or def.shape
    return radius, shape, id == "bacon" and SoftBacon.Envelope(radius) or Shapes.Envelope(shape, radius)
end

-- 私有可重现洗牌，不调用 math.random，也不消耗 Game 的随机数序列。
-- seed 为任意有限数字；同一 seed 得到同一排列，供运行期候选搜索打散顺序。
---@param points BottlePhysicsSpawn[]
---@param seed number
local function shuffle(points, seed)
    seed = (math.floor(seed) % 2147483646) + 1
    for i = #points, 2, -1 do
        seed = (seed * 48271) % 2147483647
        local j = math.floor(seed % i) + 1
        points[i], points[j] = points[j], points[i]
    end
end

---@param x number
---@param y number
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@return number
local function segmentDistanceSquared(x, y, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local t = clamp(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
    local ex, ey = x - ax - t * dx, y - ay - t * dy
    return ex * ex + ey * ey
end

---@param extent number
---@param y number
---@return number
local function spawnHalfWidth(extent, y)
    local margin = extent + SPAWN_GAP
    local rawWidth = y >= NECK_Y and NECK_HALF_WIDTH
        or math.min(HALF_WIDTH, HALF_WIDTH - SHOULDER_SLOPE * (y - SHOULDER_Y))
    local low, high = 0, rawWidth
    -- 只用于生成净空：检查有限线段，而非无限延长瓶肩，避免把瓶颈凹角
    -- 错当成越来越窄的漏斗。有限次二分求当前高度能容纳旋转包络的范围。
    for _ = 1, 24 do
        local x = (low + high) * 0.5
        local distanceSquared = math.min(
            segmentDistanceSquared(x, y, HALF_WIDTH, 0, HALF_WIDTH, SHOULDER_Y),
            segmentDistanceSquared(x, y, HALF_WIDTH, SHOULDER_Y, NECK_HALF_WIDTH, NECK_Y),
            segmentDistanceSquared(x, y, NECK_HALF_WIDTH, NECK_Y, NECK_HALF_WIDTH, HEIGHT))
        if distanceSquared >= margin * margin then low = x else high = x end
    end
    return low
end

---@param x number
---@param y number
---@param extent number
---@return number x
---@return number y
local function clampSpawn(x, y, extent)
    local safeY = clamp(y, extent + SPAWN_GAP, HEIGHT - extent - SPAWN_GAP)
    local halfWidth = math.max(0, spawnHalfWidth(extent, safeY))
    return clamp(x, -halfWidth, halfWidth), safeY
end

---@param extent number
---@param spacing number
---@param shifted boolean
---@return BottlePhysicsSpawn[]
local function makeGrid(extent, spacing, shifted)
    ---@type BottlePhysicsSpawn[]
    local points = {}
    local margin = extent + SPAWN_GAP
    local offset = shifted and spacing * 0.5 or 0
    local columns = math.floor((HALF_WIDTH * 2 - margin * 2) / spacing)
    local rows = math.floor((HEIGHT - margin * 2) / spacing)
    for row = 0, rows do
        local y = margin + row * spacing + offset
        if y <= HEIGHT - margin then
            local allowedX = spawnHalfWidth(extent, y)
            for column = 0, columns do
                local x = -HALF_WIDTH + margin + column * spacing + offset
                if math.abs(x) <= allowedX then
                    points[#points + 1] = { x = x, y = y }
                end
            end
        end
    end
    return points
end

---@return BottlePhysics
function Physics.New()
    local instance = setmetatable({}, Physics)
    instance:_Init()
    return instance
end

function Physics:_Init()
    -- 沿用脚手架 Scene + Octree + PhysicsWorld2D，并明确持有 Scene 生命周期。
    self.scene = Scene()
    self.scene.updateEnabled = false -- 禁止引擎自动更新场景
    self.scene:CreateComponent("Octree")
    self.world = self.scene:CreateComponent("PhysicsWorld2D")
    -- world 仍响应该 scene 手动发出的子系统更新事件。
    self.world.updateEnabled = true
    self.world.gravity = Vector2(0, -9.81)
    self.world.autoClearForces = true
    self.world.continuousPhysics = true
    self.world.subStepping = false
    self.world.velocityIterations = 12
    self.world.positionIterations = 8
    self.world.allowSleeping = true
    self.world.warmStarting = true
    self.bodies = {}
    self._walls = {}
    self._pairs = {}
    self._bottom = {}
    self._top = {}
    self._wall = {}
    self._impactContacts = {}
    self._side = {}
    self._exactSpawns = {}
    self.expansion = ExpansionPhysics.New()
    self.speedMultiplier, self.ghostPoop = 1, false
    self._impacts = {}
    self._retired = {}
    self._mergeSpawns = {}
    self._nearSpawns = {}
    self._eventRemoved = {}
    self._respawned = {}
    self._updating = false
    self._flushing = false
    self._disposed = false
    self._disposeRequested = false
    self._clearRequested = false
    self._pendingSync = nil
    self._layoutSeed = 1
    self.clock = 0
    self.mode = 2
    self.motion = ShakeMotion.New()

    -- 沿逆时针内边界建墙，向外法线为 (dy, -dx)/length。
    self:_Wall("floor", -HALF_WIDTH, 0, HALF_WIDTH, 0)
    self:_Wall("wall_right", HALF_WIDTH, 0, HALF_WIDTH, SHOULDER_Y)
    self:_Wall("shoulder_right", HALF_WIDTH, SHOULDER_Y, NECK_HALF_WIDTH, NECK_Y, WALL_THICKNESS, 0)
    self:_Wall("neck_right", NECK_HALF_WIDTH, NECK_Y, NECK_HALF_WIDTH, HEIGHT, 0, WALL_THICKNESS)
    self:_Wall("top", NECK_HALF_WIDTH, HEIGHT, -NECK_HALF_WIDTH, HEIGHT)
    self:_Wall("neck_left", -NECK_HALF_WIDTH, HEIGHT, -NECK_HALF_WIDTH, NECK_Y, WALL_THICKNESS, 0)
    self:_Wall("shoulder_left", -NECK_HALF_WIDTH, NECK_Y, -HALF_WIDTH, SHOULDER_Y, 0, WALL_THICKNESS)
    self:_Wall("wall_left", -HALF_WIDTH, SHOULDER_Y, -HALF_WIDTH, 0)
    print("[Bottle.Physics] 手动 Box2D 世界就绪：4.8米 × 6.4米，封闭瓶肩/瓶颈，已启用 CCD")
end

---@param name string
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@param extendStart number?
---@param extendEnd number?
function Physics:_Wall(name, ax, ay, bx, by, extendStart, extendEnd)
    local dx, dy = bx - ax, by - ay
    local length = math.sqrt(dx * dx + dy * dy)
    local start = extendStart or WALL_THICKNESS
    local finish = extendEnd or WALL_THICKNESS
    local tangentShift = (finish - start) * 0.5
    local halfThickness = WALL_THICKNESS * 0.5
    local node = self.scene:CreateChild(name)
    node:SetPosition2D((ax + bx) * 0.5 + dy / length * halfThickness + dx / length * tangentShift,
        (ay + by) * 0.5 - dx / length * halfThickness + dy / length * tangentShift)
    node.rotation2D = math.atan(dy, dx) * 180 / math.pi
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    local box = node:CreateComponent("CollisionBox2D")
    box:SetSize(length + start + finish, WALL_THICKNESS)
    setSurface(box, WALL_CATEGORY, 0xFFFF)
    self._walls[#self._walls + 1] = node
end

---@param uid number
function Physics:_ForgetContacts(uid)
    self._bottom[uid] = nil
    self._top[uid] = nil
    self._wall[uid] = nil
    self._side[uid] = nil
    for key, pair in pairs(self._pairs) do
        if pair.a == uid or pair.b == uid then self._pairs[key] = nil end
    end
    for key, contact in pairs(self._impactContacts) do
        if contact.a == uid or contact.b == uid then self._impactContacts[key] = nil end
    end
end

---@param uid number
function Physics:_Retire(uid)
    local record = self.bodies[uid]
    if not record then return end
    self.bodies[uid] = nil
    self.expansion:Forget(uid)
    self:_ForgetContacts(uid)
    self._retired[#self._retired + 1] = record
end

-- 仅在 scene:Update 返回、Box2D 世界解锁后调用。
function Physics:_DrainRetired()
    local retired = self._retired
    self._retired = {}
    self._flushing = true
    for _, record in ipairs(retired) do
        if record.soft then
            record.soft:Dispose()
        else
            record.node:Remove()
            record.node:Dispose()
        end
    end
    self._flushing = false
end

---@param force boolean?
function Physics:_RemovalBarrier(force)
    if #self._retired == 0 and not force then return end
    self._updating = true
    self.scene:Update(0) -- 不结算重力、不偷跑准备期、不增加时钟
    self._updating = false
    self:_DrainRetired()
end

---@param x number
---@param y number
---@param extent number
---@return number
function Physics:_Clearance(x, y, extent)
    local clearance = math.huge
    for _, record in pairs(self.bodies) do
        if record.soft then
            clearance = math.min(clearance, record.soft:Clearance(x, y, extent, SPAWN_GAP))
        else
            local position = record.node.position2D
            local dx, dy = x - position.x, y - position.y
            local separation = math.sqrt(dx * dx + dy * dy)
                - extent - record.envelope - SPAWN_GAP
            clearance = math.min(clearance, separation)
        end
    end
    return clearance
end

-- 返还/抽取只搜索有限个候选；拥挤时选重叠最小的位置，让物理自然排开。
-- 不进行无限重试，也不直接移动瓶内已有动态物体。
---@param uid number
---@param extent number
---@return number x
---@return number y
function Physics:_FreePosition(uid, extent)
    local spacing = extent * 2 + SPAWN_GAP * 2
    local candidates = makeGrid(extent, spacing, false)
    local shifted = makeGrid(extent, spacing, true)
    for _, point in ipairs(shifted) do candidates[#candidates + 1] = point end
    shuffle(candidates, uid)
    local bestX, bestY = clampSpawn(0, HEIGHT * 0.5, extent)
    local bestClearance = -math.huge
    for _, point in ipairs(candidates) do
        local clearance = self:_Clearance(point.x, point.y, extent)
        if clearance >= 0 then return point.x, point.y end
        if clearance > bestClearance then
            bestX, bestY, bestClearance = point.x, point.y, clearance
        end
    end
    return bestX, bestY
end

---近源生成只搜索原点周围的有限候选；即使拥挤也不退回全瓶格点。
---@param uid number
---@param extent number
---@param origin BottlePhysicsSpawn
---@return number x
---@return number y
function Physics:_NearPosition(uid, extent, origin)
    local originX, originY = clampSpawn(origin.x, origin.y, extent)
    local bestX, bestY = originX, originY
    local bestClearance = self:_Clearance(originX, originY, extent)
    if bestClearance >= 0 then return bestX, bestY end
    local angleOffset = (uid * 137.507764) * math.pi / 180
    for ring = 1, 3 do
        local distance = NEAR_SPAWN_RADIUS * ring / 3
        for spoke = 1, 12 do
            local angle = angleOffset + spoke * math.pi / 6
            local x, y = clampSpawn(originX + math.cos(angle) * distance,
                originY + math.sin(angle) * distance, extent)
            local clearance = self:_Clearance(x, y, extent)
            if clearance >= 0 then return x, y end
            if clearance > bestClearance then
                bestX, bestY, bestClearance = x, y, clearance
            end
        end
    end
    return bestX, bestY
end

---重置布局专用：(seed, uid) 决定的私有随机散布，无行列对齐。
---逐件净空校验，不重叠；找不到净空时取重叠最小候选，让物理自然排开。
---不碰 math.random，也不消耗 Game 随机序列；同一种子同 uid 完全可复现。
---@param seed number
---@param uid number
---@param extent number
---@return number x
---@return number y
---@return boolean exact 是否找到净空候选
function Physics:_ScatterPosition(seed, uid, extent)
    local state = normalizeSeed(seed * 104729 + uid * 69069 + 7)
    local bestX, bestY = clampSpawn(0, HEIGHT * 0.5, extent)
    local bestClearance = -math.huge
    local margin = extent + SPAWN_GAP
    for _ = 1, SCATTER_TRIES do
        local yFraction, xFraction = 0, 0
        state, yFraction = randomStep(state)
        state, xFraction = randomStep(state)
        local y = margin + yFraction * (HEIGHT - 2 * margin)
        local halfWidth = spawnHalfWidth(extent, y)
        local x = (xFraction * 2 - 1) * halfWidth
        local clearance = self:_Clearance(x, y, extent)
        if clearance >= 0 then return x, y, true end
        if clearance > bestClearance then
            bestX, bestY, bestClearance = x, y, clearance
        end
    end
    -- 拥挤瓶中仍留在最少重叠的有限安全候选，不穿墙、不无限重试。
    return bestX, bestY, false
end

---@param item ItemInstance
---@param x number
---@param y number
function Physics:_CreateItem(item, x, y)
    local radius, shape, envelope = dimensions(item.id, item.woolCount)
    -- 体积倍率（大胃王/气球）：碰撞与包络同步缩放，显示尺寸由 View 用同一 scale。
    local scale = PhysicalState.Clamp(item.id, "scale", item.scale)
    local weight = PhysicalState.Clamp(item.id, "weight", item.weight)
    radius = radius * scale
    envelope = envelope * scale
    local angle = (item.uid * 137.507764) % 360
    if item.id == "bacon" then
        local soft = SoftBacon.New(self.scene, item.uid, radius, x, y, angle, setSurface, weight)
        local center = assert(soft.segments[SoftBacon.CENTER_SEGMENT])
        ---@type BottleBodyPart[]
        local parts = {}
        for _, segment in ipairs(soft.segments) do
            parts[#parts + 1] = {node = segment.node, body = segment.body}
        end
        self.bodies[item.uid] = {
            uid = item.uid, node = center.node, body = center.body, soft = soft,
            parts = parts, radius = radius, kind = item.id, shape = shape,
            envelope = envelope, scale = scale, weight = weight, shapes = {}, sensor = false, ghostLike = false,
            newbornRemaining = NEWBORN_SECONDS,
            lastX = x, lastY = y,
        }
        return
    end
    local node = self.scene:CreateChild(string.format("item_%d", item.uid))
    node:SetPosition2D(x, y)
    -- 幽灵便便沿用幽灵直立sensor，但不改变其图案、标签或全局物品定义。
    local ghost = ExpansionPhysics.IsGhostLike(item.id, self.ghostPoop)
    node.rotation2D = ghost and 0 or angle
    local sensor = ExpansionPhysics.IsSensor(item.id, self.ghostPoop)
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC -- sensor 仍必须是动态体，保留与静态/动态体的真实接触。
    body.useFixtureMass = true
    body.fixedRotation = ghost
    body.linearDamping = sensor and 0 or 0.25
    body.angularDamping = sensor and 0 or 0.8
    body.gravityScale = sensor and 0 or 1
    body.bullet = true
    body.allowSleep = not sensor
    local profile = Shapes.profiles[shape]
    ---@type CollisionShape2D[]
    local shapes = {}
    if profile then
        shapes = createProfile(node, profile, radius, item.id == "slipper_right", sensor)
    elseif shape == "box" then
        -- profile 优先；仅用于尚无专用轮廓的 box 定义。
        local box = node:CreateComponent("CollisionBox2D")
        local halfSize = radius / math.sqrt(2)
        box:SetSize(halfSize * 2, halfSize * 2)
        setSurface(box)
        box.trigger = sensor
        shapes[#shapes + 1] = box
    else
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = radius
        setSurface(circle)
        circle.trigger = sensor
        shapes[#shapes + 1] = circle
    end
    local density = weight * (item.id == "balloon" and .35 or 1)
    for _, fixture in ipairs(shapes) do
        if fixture.density ~= density then fixture.density = density end
    end
    body.linearVelocity = Vector2(0, 0)
    body.angularVelocity = 0
    body.awake = true
    self.bodies[item.uid] = {
        uid = item.uid, node = node, body = body, radius = radius,
        parts = {{node = node, body = body}},
        kind = item.id, shape = shape, envelope = envelope, scale = scale,
        weight = weight, shapes = shapes, sensor = sensor, ghostLike = ghost,
        newbornRemaining = NEWBORN_SECONDS,
        lastX = x, lastY = y,
    }
end

---GameEvent 处理：合成/转化产物记住来源位置，删除事件屏蔽爆炸推动。
---V0.4：respawn（西红柿炒蛋/金针菇瓶顶重生）与 resize（大胃王/气球体积变化）
---都通过标记重建 body：respawn 用事件坐标定位，resize 保持当前位置。
---@param events GameEvent[]
function Physics:RememberEvents(events)
    if self._disposed then return end
    for _, event in ipairs(events) do
        self.expansion:Remember(event)
        if event.kind == "remove" then
            self._eventRemoved[event.uid] = true
        end
    end
    for _, event in ipairs(events) do
        if event.kind == "merge" and event.a and event.b then
            local recordA, recordB = self.bodies[event.a], self.bodies[event.b]
            local rememberedA, rememberedB = self._mergeSpawns[event.a], self._mergeSpawns[event.b]
            if (recordA or rememberedA) and (recordB or rememberedB) then
                local poseA = recordA and recordA.node.position2D
                    or Vector2(rememberedA.x, rememberedA.y)
                local poseB = recordB and recordB.node.position2D
                    or Vector2(rememberedB.x, rememberedB.y)
                self._mergeSpawns[event.uid] = {
                    x = (poseA.x + poseB.x) * 0.5,
                    y = (poseA.y + poseB.y) * 0.5,
                }
            end
        elseif event.kind == "spawn" then
            if finite(event.x) and finite(event.y) then
                self._nearSpawns[event.uid] = { x = event.x, y = event.y }
            end
        elseif event.kind == "transform" then
            -- 原地转化（香蕉→香蕉皮）：body 因 kind 变化被重建，
            -- 记住旧 body 当前位置，重建时用精确位置而不是重新搜索净空。
            local record = self.bodies[event.uid]
            if record then
                local position = record.node.position2D
                self._mergeSpawns[event.uid] = { x = position.x, y = position.y }
            end
        elseif event.kind == "respawn" then
            -- 瓶顶重生（西红柿炒蛋/金针菇）：uid 保留但 body 需回到事件坐标。
            self._respawned[event.uid] = true
            local record = self.bodies[event.uid]
            if record then
                local position = record.node.position2D
                self._mergeSpawns[event.uid] = { x = position.x, y = position.y }
            end
            if finite(event.x) and finite(event.y) then
                if (event --[[@as table]]).exact then
                    self._exactSpawns[event.uid] = {x = event.x, y = event.y}
                else
                    self._nearSpawns[event.uid] = { x = event.x, y = event.y }
                end
            end
            self._eventRemoved[event.uid] = true
        elseif event.kind == "resize" then
            -- 只有体积改变才重建。重量单独变化由 Sync 原位更新全部密度，保留接触/关节。
            local record = self.bodies[event.uid]
            if record and event.value ~= record.scale then
                local position = record.node.position2D
                self._mergeSpawns[event.uid] = { x = position.x, y = position.y }
                self._eventRemoved[event.uid] = true
            end
        end
    end
end

---只保留 location='bottle' 的实例；不改动未删除的 uid/body/node 对应关系。
---reset=true 清空重建：seed 洗牌格点决定分配顺序，再对每件叠加 (seed,uid)
---可重现抖动并逐件净空校验，视觉打散行列对齐且不引入重叠。
---seed 决定格点排列与抖动：调用方每次重置布局（重抽/新回合）应传入变化的
---种子（如 game.revision）；缺省回退最小 uid。同一种子布局完全可复现。
---Sync 不消耗正时间，准备期始终静止；定义变化（转化）或显式 remove 会重建 body。
---@param items ItemInstance[]
---@param reset boolean?
---@param seed number?
---@param options BottlePhysicsOptions? 省略沿用上次设置；新世界默认无遗物
function Physics:Sync(items, reset, seed, options)
    if self._disposed then return end
    if self._updating or self._flushing then
        ---@type ItemInstance[]
        local copy = {}
        for _, item in ipairs(items) do copy[#copy + 1] = item end
        local savedOptions = options and {accelerator = options.accelerator, ghostPoop = options.ghostPoop}
        self._pendingSync = { items = copy, reset = reset == true, seed = seed, options = savedOptions }
        return
    end
    if options then
        self.speedMultiplier = options.accelerator and 1.2 or 1
        self.ghostPoop = options.ghostPoop == true
    end
    if reset then
        self:ResetMotion()
        self.clock = 0
        for uid in pairs(self.bodies) do self:_Retire(uid) end
        self._pairs = {}
        self._bottom = {}
        self._top = {}
        self._wall = {}
        self._impactContacts = {}
        self._impacts = {}
        self._side = {}
        self._exactSpawns = {}
        self.expansion:Reset()
        self._mergeSpawns = {}
        self._nearSpawns = {}
        self._eventRemoved = {}
        self._respawned = {}
    end
    ---@type ItemInstance[]
    local ordered = {}
    ---@type table<number, boolean>
    local wanted = {}
    for _, item in ipairs(items) do
        if item.location == "bottle" and not wanted[item.uid] then
            wanted[item.uid] = true
            ordered[#ordered + 1] = item
        end
    end
    table.sort(ordered, function(a, b) return a.uid < b.uid end)
    ---@type table<number, string>
    local definitions = {}
    ---@type table<number, number>
    local scales, weights = {}, {}
    ---@type table<number, string>
    local variants = {}
    for _, item in ipairs(ordered) do
        definitions[item.uid] = item.id
        local _, shape = dimensions(item.id, item.woolCount)
        variants[item.uid] = shape
        scales[item.uid] = PhysicalState.Clamp(item.id, "scale", item.scale)
        weights[item.uid] = PhysicalState.Clamp(item.id, "weight", item.weight)
    end
    ---@type table<number, BottleRebuiltBody>
    local rebuilt = {}
    for uid, record in pairs(self.bodies) do
        -- 生命周期按uid判断，不按旧kind/sensor判断：尺寸、羊形态、转化、
        -- remove后同uid仍在场都保留自然累计和已施加强制角，但不盲继承行为。
        local sensorChanged = wanted[uid] and record.sensor ~= ExpansionPhysics.IsSensor(definitions[uid], self.ghostPoop)
        if not wanted[uid] or record.kind ~= definitions[uid] or record.shape ~= variants[uid]
            or record.scale ~= scales[uid] or sensorChanged or self._eventRemoved[uid] then
            if wanted[uid] then
                local position = record.node.position2D
                local sameKind = record.kind == definitions[uid]
                local respawned = self._respawned[uid] == true
                ---@type BottleRebuiltPart[]
                local parts = {}
                for _, part in ipairs(record.parts) do
                    local p, v = part.node.position2D, part.body.linearVelocity
                    parts[#parts + 1] = {x = p.x - position.x, y = p.y - position.y,
                        angle = part.node.rotation2D, vx = v.x, vy = v.y,
                        angularVelocity = part.body.angularVelocity}
                end
                rebuilt[uid] = {x = position.x, y = position.y, radius = record.radius, parts = parts,
                    newbornRemaining = record.newbornRemaining,
                    motion = self.expansion:SampleAngle(record),
                    keepPose = sameKind and not respawned,
                    keepBehavior = sameKind and not respawned
                        and (not self._eventRemoved[uid] or record.scale ~= scales[uid]
                            or record.shape ~= variants[uid] or sensorChanged)}
            end
            if wanted[uid] and (record.scale ~= scales[uid] or record.shape ~= variants[uid] or sensorChanged)
                and not self._mergeSpawns[uid] then
                -- 兜底：scale 变化未经 resize 事件，保持当前位置重建。
                local position = record.node.position2D
                self._mergeSpawns[uid] = { x = position.x, y = position.y }
            end
            self:_Retire(uid)
        elseif record.weight ~= weights[uid] then
            local weight = assert(weights[uid])
            if record.soft then
                record.soft:SetWeight(weight)
            else
                -- 原始密度为1；绝不能用当前密度反复相乘，避免连续改重量后漂移。
                local density = weight * (record.kind == "balloon" and .35 or 1)
                for _, fixture in ipairs(record.shapes) do fixture.density = density end
                record.body.awake = true
            end
            record.weight = weight
        end
    end
    -- 先真正删除旧 fixture，再创建替代物体，避免复用 uid 的旧接触混入。
    self:_RemovalBarrier()
    -- 重置散布种子：调用方传 revision 等变化值时，同一批物品重抽/换回合
    -- 得到全新散布；缺省回退最小 uid。同一种子布局完全可复现。
    local scatterSeed = seed or (ordered[1] and ordered[1].uid or 1)
    local created, crowded = 0, 0
    for _, item in ipairs(ordered) do
        if not self.bodies[item.uid] then
            local _, _, extent = dimensions(item.id, item.woolCount)
            extent = extent * assert(scales[item.uid])
            local remembered = self._mergeSpawns[item.uid]
            local near = self._nearSpawns[item.uid]
            local exact = self._exactSpawns[item.uid]
            local previous = rebuilt[item.uid]
            local x, y = 0, HEIGHT * 0.5
            if exact then
                x, y = exact.x, exact.y
            elseif near then
                x, y = self:_NearPosition(item.uid, extent, near)
            elseif previous and previous.keepPose then
                -- 纯尺寸/同类型形态重建不重新搜索位置；明确respawn坐标优先。
                x, y = previous.x, previous.y
            elseif remembered then
                -- 瓶内安全时保持精确材料中点；近墙只修正新产物生成点，
                -- 不修改任何存活动态物体的位置。
                x, y = clampSpawn(remembered.x, remembered.y, extent)
            elseif reset and item.woolExtraEntry then
                -- 额外羊毛按规则在准备阶段已入瓶，位置取瓶顶且不消耗抽取名额。
                x, y = clampSpawn(((item.uid * 37) % 81 - 40) / 100, 6.0, extent)
            elseif reset then
                local exact = false
                x, y, exact = self:_ScatterPosition(scatterSeed, item.uid, extent)
                if not exact then crowded = crowded + 1 end
            else
                x, y = self:_FreePosition(item.uid, extent)
            end
            self:_CreateItem(item, x, y)
            local record = assert(self.bodies[item.uid])
            if previous then
                if previous.keepPose then
                    local ratio = record.radius / previous.radius
                    for index, part in ipairs(record.parts) do
                        local pose = previous.parts[index]
                        if pose then
                            -- 五段分别还原旧弯曲姿态，偏移按新尺寸缩放；不把
                            -- 软体压回直条，不因resize丢线速度/自然角速度。
                            part.node:SetPosition2D(x + pose.x * ratio, y + pose.y * ratio)
                            part.node.rotation2D = record.ghostLike and 0 or pose.angle
                            part.body.linearVelocity = Vector2(pose.vx, pose.vy)
                            part.body.angularVelocity = record.ghostLike and 0 or pose.angularVelocity
                            part.body.awake = true
                        end
                    end
                    record.newbornRemaining = previous.newbornRemaining
                end
                self.expansion:Restore(record, previous.motion, previous.keepBehavior)
            else
                self.expansion:State(record)
            end
            created = created + 1
        end
    end
    self._mergeSpawns = {}
    self._nearSpawns = {}
    self._eventRemoved = {}
    self._respawned = {}
    self._exactSpawns = {}
    self.expansion:Flush(self)
    if reset then
        print(string.format("[Bottle.Physics] 重置 %d 个瓶内物体，随机散布，等待 Step 后才运动", #ordered))
        if crowded > 0 then
            print(string.format("[Bottle.Physics] %d 个物体未找到净空候选，使用最少重叠位置由物理排开", crowded))
        end
    elseif created > 0 then
        print(string.format("[Bottle.Physics] 同步新增 %d 个物体", created))
    end
    self:_RunDeferred()
end

---@param node Node?
---@return number?
local function itemUid(node)
    if not node then return nil end
    return tonumber(node.name:match("^item_(%d+)$") or node.name:match("^item_(%d+)_part_%d+$"))
end

---@param counts table<number, number>
---@param uid number
---@param delta number
local function changeContactCount(counts, uid, delta)
    local count = math.max(0, (counts[uid] or 0) + delta)
    counts[uid] = count > 0 and count or nil
end

-- 复合fixture/软体多段属于同一物品；持续接触只响一次，极短的分离抖动仍视作同次接触。
-- 只过滤声音，原有 _pairs/_wall 等玩法计数照常逐fixture维护。
---@param key string
---@param a number
---@param b number?
---@param begin boolean
---@return boolean
function Physics:_ImpactContact(key, a, b, begin)
    local contact = self._impactContacts[key]
    if begin then
        if not contact then
            self._impactContacts[key] = {a = a, b = b, count = 1}
            return true
        end
        local fresh = contact.count == 0
            and (not contact.endedAt or self.clock - contact.endedAt >= IMPACT_SEPARATION)
        contact.count = contact.count + 1
        return fresh
    end
    if contact and contact.count > 0 then
        contact.count = contact.count - 1
        if contact.count == 0 then contact.endedAt = self.clock end
    end
    return false
end

---由主程序转发全局 PhysicsBeginContact2D / PhysicsEndContact2D 事件。
---回调只修改 fixture 接触计数，不生成、不更新场景、不删除任何物体。
---@param eventData PhysicsBeginContact2DEventData|PhysicsEndContact2DEventData
---@param begin boolean
function Physics:Contact(eventData, begin)
    if self._disposed then return end
    local eventWorld = eventData["World"]:GetPtr("PhysicsWorld2D")
    if eventWorld ~= self.world then return end
    local nodeA = eventData["NodeA"]:GetPtr("Node")
    local nodeB = eventData["NodeB"]:GetPtr("Node")
    if not nodeA or not nodeB then return end
    local uidA, uidB = itemUid(nodeA), itemUid(nodeB)
    local recordA = uidA and self.bodies[uidA] or nil
    local recordB = uidB and self.bodies[uidB] or nil
    -- 同 uid 被重建后，拒绝旧节点迟到的 End 事件。
    if uidA and (not recordA or not (recordA.node == nodeA or (recordA.soft and recordA.soft:Owns(nodeA)))) then return end
    if uidB and (not recordB or not (recordB.node == nodeB or (recordB.soft and recordB.soft:Owns(nodeB)))) then return end
    if uidA and uidA == uidB then return end -- 软体内部接触不是物品相邻
    local delta = begin and 1 or -1
    if uidA and uidB and uidA ~= uidB then
        local a, b = math.min(uidA, uidB), math.max(uidA, uidB)
        local key = tostring(a) .. ":" .. tostring(b)
        local previous = self._pairs[key]
        local count = math.max(0, (previous and previous.count or 0) + delta)
        if count == 0 then
            self._pairs[key] = nil
        else
            self._pairs[key] = { a = a, b = b, count = count }
        end
        local impactKey = "pair:" .. key
        if self:_ImpactContact(impactKey, a, b, begin) then
            self:_EmitImpact(recordA, recordB, impactKey)
        end
    else
        local uid = uidA or uidB
        local wallNode = uidA and nodeB or nodeA
        if not uid then return end
        -- 只认本世界实际持有的静态内壁，拒绝同名但不属于瓶子的节点。
        local innerWall = false
        for _, node in ipairs(self._walls) do
            if node == wallNode then innerWall = true; break end
        end
        if not innerWall then return end
        changeContactCount(self._wall, uid, delta)
        if wallNode.name == "floor" then changeContactCount(self._bottom, uid, delta) end
        if wallNode.name == "top" then changeContactCount(self._top, uid, delta) end
        if wallNode.name ~= "floor" and wallNode.name ~= "top" then
            changeContactCount(self._side, uid, delta)
        end
        -- 各段瓶壁分别计数：沿侧壁下滑再撞瓶底仍然能响，不被侧壁接触吞掉。
        local impactKey = "wall:" .. tostring(uid) .. ":" .. wallNode.name
        if self:_ImpactContact(impactKey, uid, nil, begin) then
            self:_EmitImpact(uidA and recordA or recordB, nil, impactKey)
        end
    end
end

-- 记录一次新接触（Begin）的碰撞强度，供主循环播放碰撞音。纯事实记录，
-- 不在此做阈值／节流／音量等表现决策；速度单位米/秒。
---@param recordA BottleBody?
---@param recordB BottleBody?
---@param key string
function Physics:_EmitImpact(recordA, recordB, key)
    -- sensor 穿透是玩法接触，不是实体撞击；任一方为幽灵都不得发碰撞音。
    if (recordA and recordA.sensor) or (recordB and recordB.sensor) then return end
    local va = recordA and recordA.body and recordA.body.linearVelocity or nil
    local vb = recordB and recordB.body and recordB.body.linearVelocity or nil
    if not va then return end
    local speed
    if vb then
        local dvx, dvy = va.x - vb.x, va.y - vb.y
        speed = math.sqrt(dvx * dvx + dvy * dvy)
    else
        speed = math.sqrt(va.x * va.x + va.y * va.y)
    end
    if not speed or speed ~= speed then return end
    self._impacts[#self._impacts + 1] = { speed = speed, pair = vb ~= nil, key = key }
end

-- 取出并清空本步累积的碰撞事件；由主循环每物理步调用一次。
---@return BottleImpact[]
function Physics:TakeImpacts()
    local impacts = self._impacts
    self._impacts = {}
    return impacts
end

---@return BottlePhysicsContacts
function Physics:Contacts()
    ---@type BottlePhysicsContacts
    local result = { pairs = {}, bottom = {}, top = {}, wall = {}, side = {}, positions = {},
        angles = {}, rotateOffsets = {}, angularTravel = {}, flightArrived = {}, flightHits = {}, shakeStrength = 0 }
    for uid, record in pairs(self.bodies) do
        local position = record.node.position2D
        if position then result.positions[uid] = { x = position.x, y = position.y } end
    end
    for _, pair in pairs(self._pairs) do
        if pair.count > 0 and self.bodies[pair.a] and self.bodies[pair.b] then
            result.pairs[#result.pairs + 1] = { pair.a, pair.b }
        end
    end
    table.sort(result.pairs, function(a, b)
        return a[1] < b[1] or (a[1] == b[1] and a[2] < b[2])
    end)
    for uid, count in pairs(self._bottom) do
        if count > 0 and self.bodies[uid] then result.bottom[uid] = true end
    end
    for uid, count in pairs(self._top) do
        if count > 0 and self.bodies[uid] then result.top[uid] = true end
    end
    for uid, count in pairs(self._wall) do
        if count > 0 and self.bodies[uid] then result.wall[uid] = true end
    end
    for uid, count in pairs(self._side) do
        if count > 0 and self.bodies[uid] then result.side[uid] = true end
    end
    self.expansion:Contacts(self, result)
    return result
end

---切换仅改变输入模型，不重建物品、不清接触，也不修改姿态或速度。
---@param mode number
---@return boolean
function Physics:SetMode(mode)
    if self._disposed or (mode ~= 1 and mode ~= 2) then return false end
    if self.mode ~= mode then
        self.mode = mode
        self:ResetMotion()
        print("[Bottle.Physics] 已切换物理" .. (mode == 1 and "一：原版" or "二：摇晃惯性"))
    end
    return true
end

function Physics:ResetMotion()
    self.motion:Reset()
    self.expansion:ResetShake()
end

function Physics:BeginShake()
    if not self._disposed then self.motion:Begin() end
end

function Physics:EndShake()
    if not self._disposed then self.motion:End() end
end

---@param ax number
---@param ay number
---@param dt number
function Physics:Sensor(ax, ay, dt)
    if not self._disposed and self.mode == 2 then
        self.motion:Sensor(ax, ay, dt)
        if finite(ax) and finite(ay) and finite(dt) and dt > 0 then self.expansion:Input(false,true) end
    end
end

---物理一原样保留：世界坐标拖动增量，dx 向右、dy 向上；立即同向冲量。
---物理二：记录瓶子的目标位移；在固定 Step 中计算反向惯性，不直接平移物品。
---@param dx number
---@param dy number
function Physics:Shake(dx, dy)
    if self._disposed or dx ~= dx or dy ~= dy then return end
    if self.mode == 2 then
        if self.motion.holding and (dx ~= 0 or dy ~= 0) then self.expansion:Input(true,false) end
        self.motion:Move(dx, dy)
        return
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 or length == math.huge then return end
    local scale = math.min(1, MAX_SHAKE_DELTA / length) * SHAKE_GAIN
    self.expansion:Input(false,false,dx*scale,dy*scale)
    for _, record in pairs(self.bodies) do
        if not self.expansion:Controlled(record) then
            for _, part in ipairs(record.parts) do
                local mass = part.body.mass
                part.body:ApplyLinearImpulseToCenter(Vector2(dx * scale * mass, dy * scale * mass), true)
            end
        end
    end
end

-- 幽灵是穿透 sensor：速度仅由私有确定性流场和瓶轮廓决定，不读解算速度，
-- 也不接受摇瓶/体感/碰撞冲量；仍让 Box2D 积分并产生真实 Begin/EndContact。
-- uid 只决定流场相位，clock 只在 Step 正时间推进；不读真实时间/全局随机。
-- 近壁转向用有限内壁线段最近点；不把瓶肩无限延长成漏斗。
---@type number[][]
local GHOST_EDGES = {
    {-HALF_WIDTH,0, HALF_WIDTH,0}, {HALF_WIDTH,0, HALF_WIDTH,SHOULDER_Y},
    {HALF_WIDTH,SHOULDER_Y, NECK_HALF_WIDTH,NECK_Y},
    {NECK_HALF_WIDTH,NECK_Y, NECK_HALF_WIDTH,HEIGHT},
    {NECK_HALF_WIDTH,HEIGHT, -NECK_HALF_WIDTH,HEIGHT},
    {-NECK_HALF_WIDTH,HEIGHT, -NECK_HALF_WIDTH,NECK_Y},
    {-NECK_HALF_WIDTH,NECK_Y, -HALF_WIDTH,SHOULDER_Y},
    {-HALF_WIDTH,SHOULDER_Y, -HALF_WIDTH,0},
}
local GHOST_MAX_SPEED = 1.6

---@param x number
---@param y number
---@param extent number
---@return boolean
local function ghostPointInside(x, y, extent)
    if not finite(x) or not finite(y) then return false end
    local margin = extent + SPAWN_GAP
    if y < margin or y > HEIGHT - margin then return false end
    local halfWidth = y >= NECK_Y and NECK_HALF_WIDTH
        or math.min(HALF_WIDTH, HALF_WIDTH - SHOULDER_SLOPE * (y - SHOULDER_Y))
    if math.abs(x) > halfWidth then return false end
    -- 圆包络到每条有限边均有净空才安全，包括肩/颈凹角；无须每帧二分。
    for _, edge in ipairs(GHOST_EDGES) do
        if segmentDistanceSquared(x, y, edge[1], edge[2], edge[3], edge[4]) < margin * margin - 1e-9 then
            return false
        end
    end
    return true
end

---仅在 Box2D 解锁时修正失效/越界位置；正常运动由预测限速阻止越界，
---不是每帧传送。几何只管“留在瓶内”，绝不写入玩法接触表。
---@param record BottleBody
local function containGhost(record)
    local position = record.node.position2D
    if ghostPointInside(position.x, position.y, record.envelope) then return end
    local x, y = position.x, position.y
    if not finite(x) or not finite(y) then x, y = 0, HEIGHT * 0.5 end
    local safeX, safeY = clampSpawn(x, y, record.envelope)
    if math.abs(safeX - position.x) > 1e-7 or math.abs(safeY - position.y) > 1e-7
        or not finite(position.x) or not finite(position.y) then
        record.node:SetPosition2D(safeX, safeY)
    end
end

---@param record BottleBody
---@param clock number
---@param dt number
---@param multiplier number
local function floatGhost(record, clock, dt, multiplier)
    containGhost(record)
    local phase = (record.uid % 997) * 2.399963229728653
    local targetX = 0.95 * math.cos(clock * 0.83 + phase)
        + 0.3 * math.sin(clock * 1.37 + phase * 0.7)
    local targetY = 0.8 * math.sin(clock * 0.71 + phase * 1.3)
        + 0.3 * math.cos(clock * 1.19 + phase)
    local position = record.node.position2D
    local margin = record.envelope + 0.45
    for _, edge in ipairs(GHOST_EDGES) do
        local ax, ay, bx, by = edge[1], edge[2], edge[3], edge[4]
        local dx, dy = bx - ax, by - ay
        local along = clamp(((position.x - ax) * dx + (position.y - ay) * dy) / (dx * dx + dy * dy), 0, 1)
        local nx, ny = position.x - ax - along * dx, position.y - ay - along * dy
        local distance = math.sqrt(nx * nx + ny * ny)
        if distance > 1e-6 and distance < margin then
            local strength = 2.8 * (1 - distance / margin)
            targetX = targetX + nx / distance * strength
            targetY = targetY + ny / distance * strength
        end
    end
    local speed = math.sqrt(targetX * targetX + targetY * targetY)
    local factor = speed > GHOST_MAX_SPEED and GHOST_MAX_SPEED / speed or 1
    -- 用安全终点反推本步速度；底/顶、肩颈凹角均按整个旋转包络留内，
    -- 不依赖 sensor 的 CCD（Box2D sensor 本身不产生实体阻挡）。
    local nextX, nextY = position.x + targetX * factor * dt * multiplier,
        position.y + targetY * factor * dt * multiplier
    if not ghostPointInside(nextX, nextY, record.envelope) then
        nextX, nextY = clampSpawn(nextX, nextY, record.envelope)
    end
    -- 返回基准速度；加速积分屏障统一乘倍率，不能此处与屏障重复乘。
    record.body.linearVelocity = Vector2((nextX - position.x) / (dt * multiplier),
        (nextY - position.y) / (dt * multiplier))
    record.body.angularVelocity = 0
    record.body.awake = true
end

---每次正 dt 仅手动更新一次 scene；主程序固定传 1/60。
---本模块不自动摇晃、不订阅自动更新事件，也没有额外的回合计时器。
---@param dt number
function Physics:Step(dt)
    if self._disposed or self._updating or self._flushing or dt ~= dt or math.abs(dt) == math.huge then
        return
    end
    self.expansion:Flush(self)
    if dt <= 0 then
        self:_RemovalBarrier()
        self:_RunDeferred()
        return
    end
    self:_RunDeferred()
    if self._disposed then return end
    local dvx, dvy, sensorX, sensorY = 0, 0, 0, 0
    if self.mode == 2 then
        dvx, dvy = self.motion:Step(dt)
        sensorX, sensorY = self.motion:SensorImpulse(dt)
    end
    self.expansion:SampleShake(dt,dvx,dvy,sensorX,sensorY)
    dvx,dvy=dvx+sensorX,dvy+sensorY
    for _, record in pairs(self.bodies) do
        if record.ghostLike then floatGhost(record, self.clock, dt, self.speedMultiplier) end
        if record.soft then record.soft:Step(dt) end
        self.expansion:Before(record, dt, self.bodies, clampSpawn, self.speedMultiplier)
        for _, part in ipairs(record.parts) do
            local body = part.body
            if not self.expansion:Controlled(record) and (dvx ~= 0 or dvy ~= 0) then
                body:ApplyLinearImpulseToCenter(Vector2(dvx * body.mass, dvy * body.mass), true)
            end
            if not self.expansion:Controlled(record) and record.newbornRemaining > 0 then
                -- 每个柔软分段独立缓冲，不能只限制中心而放任末段高速飞散。
                local velocity = body.linearVelocity
                local speed = math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
                if speed > NEWBORN_MAX_SPEED then
                    local factor = NEWBORN_MAX_SPEED / speed - 1
                    body:ApplyLinearImpulseToCenter(Vector2(velocity.x * factor * body.mass,
                        velocity.y * factor * body.mass), true)
                end
            end
        end
        record.newbornRemaining = math.max(0, record.newbornRemaining - dt)
    end
    -- 固定dt不变：把基准线速度/重力映射进1.2倍移动坐标，解算后恢复基准速度。
    -- 真实Box2D负责CCD/接触/关节，绝不用事后额外平移绕过薄墙；角速度不加速。
    local accelerated = self.expansion:BeginSpeed(self)
    self.clock = self.clock + dt
    self._updating = true
    self.scene:Update(dt)
    self._updating = false
    self.expansion:EndSpeed(accelerated, self.speedMultiplier)
    for _, record in pairs(self.bodies) do
        if record.sensor then containGhost(record) end
    end
    self.expansion:After(self, dt)
    self:_DrainRetired()
    self:_RunDeferred()
end

function Physics:_ClearBodies()
    self:ResetMotion()
    self.clock = 0
    for uid in pairs(self.bodies) do self:_Retire(uid) end
    self._pairs = {}
    self._bottom = {}
    self._top = {}
    self._wall = {}
    self._impactContacts = {}
    self._side = {}
    self._exactSpawns = {}
    self.expansion:Reset()
    self._impacts = {}
    self._mergeSpawns = {}
    self._nearSpawns = {}
    self._eventRemoved = {}
    self._respawned = {}
end

---清除动态物品与接触状态，保留瓶子静态墙体以便下回合复用。
function Physics:Clear()
    if self._disposed then return end
    if self._updating or self._flushing then
        self._clearRequested = true
        self._pendingSync = nil
        return
    end
    self:_ClearBodies()
    self:_RemovalBarrier()
    self:_RunDeferred()
end

-- 其他事件监听者在 Scene.Update 内调用的结构修改，延迟到世界解锁后执行。
-- 本模块 Contact 本身从不发起结构修改。
function Physics:_RunDeferred()
    if self._updating or self._flushing or self._disposed then return end
    if self._disposeRequested then
        self._disposeRequested = false
        self:Dispose()
        return
    end
    local request = self._pendingSync
    local clearRequested = self._clearRequested
    self._pendingSync = nil
    self._clearRequested = false
    if clearRequested then self:Clear() end
    if request then self:Sync(request.items, request.reset, request.seed, request.options) end
end

---四个返回值：瓶内局部 x/y（米）、逆时针 angle（弧度）、radius（米）。
---未知或已删除 uid 返回瓶子中心的默认姿态，不访问已释放节点。
---@param uid number
---@return number x
---@return number y
---@return number angle
---@return number radius
function Physics:GetPose(uid)
    local record = self.bodies[uid]
    if not record then return 0, HEIGHT * 0.5, 0, DEFAULT_RADIUS end
    local position = record.node.position2D
    return position.x, position.y, record.node.rotation2D * math.pi / 180, record.radius
end

---柔软段绝对姿态快照；不推进物理、不泄露可写节点引用。普通物品返回 nil。
---@param uid number
---@return BottleSoftPose[]?
function Physics:GetSoftPose(uid)
    local record = self.bodies[uid]
    return record and record.soft and record.soft:GetPose() or nil
end

---软体按实际矩形段拾取；普通物品维持半径粗检，像素透明命中仍由 Art 决定。
---@param uid number
---@param x number 瓶内米坐标
---@param y number
---@return boolean
function Physics:ContainsPoint(uid, x, y)
    local record = self.bodies[uid]
    if not record or not finite(x) or not finite(y) then return false end
    if record.soft then return record.soft:ContainsPoint(x, y) end
    local position = record.node.position2D
    return (x - position.x) ^ 2 + (y - position.y) ^ 2 <= record.envelope ^ 2
end

function Physics:Dispose()
    if self._disposed then return end
    if self._updating or self._flushing then
        self._disposeRequested = true
        self._pendingSync = nil
        return
    end
    self._pendingSync = nil
    self._clearRequested = false
    self:_ClearBodies()
    self:_RemovalBarrier(true)
    self._disposed = true -- 忽略删除墙体时产生的 EndContact 事件
    for _, node in ipairs(self._walls) do
        node:Remove()
        node:Dispose()
    end
    self._walls = {}
    self.world.updateEnabled = false
    self.scene:RemoveAllComponents()
    self.world:Dispose()
    self.scene:Dispose()
    print("[Bottle.Physics] 已释放物理世界")
end

return Physics
