-- 真柔软培根：5 个独立 Box2D 刚体 + 4 个限角旋转关节，不用视觉摆动冒充软体。
-- 由 Bottle.Physics / DeckBoard 在世界解锁时创建/释放，并在固定物理步前调用 Step。
--
-- 碰撞设计（长度单位米；下图为原图横向，初始姿态再统一旋转）：
--       x=-2r            主 uid               x=+2r
--        [ 1 ]--o--[ 2 ]--o--[ 3 ]--o--[ 4 ]--o--[ 5 ]
--                每段长 .8r、厚 .75r，端部搭接 .025r
--       名义总长4r（旧2r的两倍），厚度不变；所有尺寸来自下方共享常量。
--       相邻段通过真实转轴连接，限角 ±0.55rad，柔弱弯曲回正与阻尼。
--       外部所有 fixture 都是实体；仅关节相邻段不自撞（Box2D 标准约定）。
--       非相邻段可自撞，同 uid 的接触不输出为玩法相邻。
-- 检测目的：任意段真实接触 -> 同一个物品 uid；分片缝中心不能漏过小物品。
-- 极限：关节限制弯曲、CCD防高速穿墙，短时新生限速由 Physics 对每段施加。
-- 生成净空用初始全包络；存活时净空逐段算，不能只查中心段或静态旧包络。

---@class BottleSoftSegment
---@field node Node
---@field body RigidBody2D
---@field halfLength number
---@field halfWidth number
---@field u0 number
---@field u1 number

---@class BottleSoftPose
---@field x number 瓶局部米
---@field y number
---@field angle number 逆时针弧度（屏幕绘制取负）
---@field halfLength number 包含微小接缝搭接的碰撞半长
---@field halfWidth number
---@field u0 number 原图横向归一化区间
---@field u1 number

---@class BottleSoftBacon
---@field segments BottleSoftSegment[] 左到右，中心为第3段
---@field joints ConstraintRevolute2D[]
---@field disposed boolean
local SoftBacon = {}
SoftBacon.__index = SoftBacon
local COUNT = 5
local CENTER = 3
local LIMIT = 0.55 -- ConstraintRevolute2D lower/upperAngle 是 Box2D 弧度，不是 Node 的度。
-- radius 仍为 Items 定义的基础尺寸；只改变横向长度，不放大厚度。
-- 瓶内、牌库沙盒、静态图标共用，真实段绘制不得再次乘 LENGTH_SCALE。
SoftBacon.LENGTH_SCALE = 2
SoftBacon.HALF_WIDTH_RATIO = 0.375
SoftBacon.OVERLAP_RATIO = 0.0125 * SoftBacon.LENGTH_SCALE
SoftBacon.SEGMENT_COUNT = COUNT
SoftBacon.CENTER_SEGMENT = CENTER

---@param radius number
---@return number
function SoftBacon.Envelope(radius)
    local halfLength = SoftBacon.LENGTH_SCALE + SoftBacon.OVERLAP_RATIO
    return radius * math.sqrt(halfLength ^ 2 + SoftBacon.HALF_WIDTH_RATIO ^ 2)
end

---@param scene Scene
---@param uid number
---@param radius number
---@param x number
---@param y number
---@param angle number 度（与 Node.rotation2D 一致）
---@param setSurface fun(shape:CollisionShape2D)
---@return BottleSoftBacon
function SoftBacon.New(scene, uid, radius, x, y, angle, setSurface)
    local self = setmetatable({}, SoftBacon)
    self:_Init(scene, uid, radius, x, y, angle, setSurface)
    return self
end

---@param scene Scene
---@param uid number
---@param radius number
---@param x number
---@param y number
---@param angle number
---@param setSurface fun(shape:CollisionShape2D)
function SoftBacon:_Init(scene, uid, radius, x, y, angle, setSurface)
    self.segments = {}
    self.joints = {}
    self.disposed = false
    local cosine, sine = math.cos(angle * math.pi / 180), math.sin(angle * math.pi / 180)
    local length = radius * 2 * SoftBacon.LENGTH_SCALE / COUNT
    local halfWidth = radius * SoftBacon.HALF_WIDTH_RATIO
    for i = 1, COUNT do
        local offset = (i - CENTER) * length
        local name = i == CENTER and string.format("item_%d", uid)
            or string.format("item_%d_part_%d", uid, i)
        local node = scene:CreateChild(name)
        node:SetPosition2D(x + cosine * offset, y + sine * offset)
        node.rotation2D = angle
        local body = node:CreateComponent("RigidBody2D")
        body.bodyType = BT_DYNAMIC
        body.useFixtureMass = true
        body.bullet = true
        body.linearDamping = 0.25
        body.angularDamping = 0.8
        body.gravityScale = 1
        body.allowSleep = true
        local halfLength = length * 0.5 + radius * SoftBacon.OVERLAP_RATIO
        local box = node:CreateComponent("CollisionBox2D")
        box:SetSize(halfLength * 2, halfWidth * 2)
        setSurface(box)
        body.linearVelocity = Vector2(0, 0)
        body.angularVelocity = 0
        self.segments[i] = { node = node, body = body, halfLength = halfLength,
            halfWidth = halfWidth, u0 = (i - 1) / COUNT, u1 = i / COUNT }
    end
    for i = 1, COUNT - 1 do
        local a, b = self.segments[i], self.segments[i + 1]
        local offset = (i - CENTER + 0.5) * length
        local joint = a.node:CreateComponent("ConstraintRevolute2D")
        -- 先配置，再写 otherBody 生成关节；anchor 为世界米坐标。
        joint.anchor = Vector2(x + cosine * offset, y + sine * offset)
        joint.lowerAngle = -LIMIT
        joint.upperAngle = LIMIT
        joint.enableLimit = true
        joint.collideConnected = false
        joint.otherBody = b.body
        self.joints[i] = joint
    end
end

---@param node Node
---@return boolean
function SoftBacon:Owns(node)
    for _, segment in ipairs(self.segments) do
        if segment.node == node then return true end
    end
    return false
end

---隐式阻尼弹簧施加等大反向角冲量；不直接平移/旋转节点、不逐帧重建关节。
---k,c 按约化转动惯量缩放，尺寸/scale变化仍有相同柔软响应。
---@param dt number
function SoftBacon:Step(dt)
    for i = 1, #self.segments - 1 do
        local a, b = self.segments[i], self.segments[i + 1]
        local angle = ((b.node.rotation2D - a.node.rotation2D + 180) % 360 - 180) * math.pi / 180
        local relativeVelocity = b.body.angularVelocity - a.body.angularVelocity
        local ia, ib = a.body.inertia, b.body.inertia
        local reduced = ia * ib / math.max(ia + ib, 1e-9)
        local stiffness, damping = reduced * 36, reduced * 8.4
        local impulse = -(stiffness * angle + (damping + stiffness * dt) * relativeVelocity) * dt
            / (1 + (damping + stiffness * dt) * dt / math.max(reduced, 1e-9))
        if math.abs(impulse) > 1e-9 then
            a.body:ApplyAngularImpulse(-impulse, true)
            b.body:ApplyAngularImpulse(impulse, true)
        end
    end
end

---@return BottleSoftPose[]
function SoftBacon:GetPose()
    ---@type BottleSoftPose[]
    local result = {}
    for _, segment in ipairs(self.segments) do
        local position = segment.node.position2D
        result[#result + 1] = { x = position.x, y = position.y,
            angle = segment.node.rotation2D * math.pi / 180,
            halfLength = segment.halfLength, halfWidth = segment.halfWidth,
            u0 = segment.u0, u1 = segment.u1 }
    end
    return result
end

---@param x number
---@param y number
---@return boolean
function SoftBacon:ContainsPoint(x, y)
    for _, segment in ipairs(self.segments) do
        local position = segment.node.position2D
        local dx, dy = x - position.x, y - position.y
        local angle = segment.node.rotation2D * math.pi / 180
        local cosine, sine = math.cos(angle), math.sin(angle)
        if math.abs(dx * cosine + dy * sine) <= segment.halfLength
            and math.abs(-dx * sine + dy * cosine) <= segment.halfWidth then return true end
    end
    return false
end

---@param x number
---@param y number
---@param extent number
---@param gap number
---@return number
function SoftBacon:Clearance(x, y, extent, gap)
    local result = math.huge
    for _, segment in ipairs(self.segments) do
        local position = segment.node.position2D
        local dx, dy = x - position.x, y - position.y
        local angle = segment.node.rotation2D * math.pi / 180
        local cosine, sine = math.cos(angle), math.sin(angle)
        local qx = math.max(0, math.abs(dx * cosine + dy * sine) - segment.halfLength)
        local qy = math.max(0, math.abs(-dx * sine + dy * cosine) - segment.halfWidth)
        result = math.min(result, math.sqrt(qx * qx + qy * qy) - extent - gap)
    end
    return result
end

---只能在世界解锁后调用；先逐个移除关节，再删除所有段，避免悬空约束引用。
function SoftBacon:Dispose()
    if self.disposed then return end
    self.disposed = true
    for _, joint in ipairs(self.joints) do joint:Remove(); joint:Dispose() end
    self.joints = {}
    for _, segment in ipairs(self.segments) do segment.node:Remove(); segment.node:Dispose() end
    self.segments = {}
end

return SoftBacon
