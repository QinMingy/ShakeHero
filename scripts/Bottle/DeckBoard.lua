-- 牌库物理沙盒：所有持有实例从顶部落下，在矩形屏幕容器内按真实 Box2D 碰撞停稳。
-- 独立 Scene／World，只用于牌库页表现；不接入回合物理、玩法随机与存档。
local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Shapes = require("Bottle.Shapes")
local Art = require("Bottle.Art")
local SoftBacon = require("Bottle.SoftBacon")
local SoftView = require("Bottle.SoftView")
local PhysicalState = require("Bottle.PhysicalState")
-- 碰撞设计（米）：培根 [1]-o-[2]-o-[3]-o-[4]-o-[5]，与瓶中同一5段4关节。
-- 任意段均可撞墙/物品；弯曲后逐段拾取，所有段仍只返回一个实例 uid。
-- 缩窄面板时整条等量平移，不只移动中心破坏关节；释放先关节后所有段。
-- 幽灵在此仍按牌库既有规则受重力/实体碰撞：沙盒不模拟瓶内特殊效果。

local WORLD_WIDTH = 4.8
local WORLD_HEIGHT = 5.4
-- 生成布局的保守宽度：真实面板宽度首帧才确定，先按常见值排列，随后由 SetBounds 收紧。
local SPAWN_WIDTH = 4.2
local WALL_THICKNESS = .24
local FIXED_STEP = 1 / 60
local MAX_STEPS = 3
local ITEM_CATEGORY = 2
local WALL_CATEGORY = 1
local ITEM_MASK = WALL_CATEGORY | ITEM_CATEGORY

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
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
    shape.categoryBits = category or ITEM_CATEGORY
    shape.maskBits = mask or ITEM_MASK
end

-- 与瓶内物理相同的图案碰撞体；牌库沙盒只负责展示，不改动该数据。
---@param node Node
---@param profile BottleCollisionProfile
---@param radius number
---@param mirror boolean
---@return CollisionShape2D[]
local function createProfile(node, profile, radius, mirror)
    ---@type CollisionShape2D[]
    local shapes = {}
    for _, points in ipairs(profile.polygons or {}) do
        local polygon = node:CreateComponent("CollisionPolygon2D")
        polygon:SetVertexCount(#points // 2)
        local first, last, step = #points - 1, 1, -2
        if mirror then first, last, step = 1, #points - 1, 2 end
        for i = first, last, step do
            local x = (points[i] - 8) * radius / 8
            local y = (8 - points[i + 1]) * radius / 8
            local index = math.abs(i - first) // 2
            polygon:SetVertex(index, Vector2(mirror and -x or x, y))
        end
        setSurface(polygon)
        shapes[#shapes + 1] = polygon
    end
    for _, spec in ipairs(profile.circles or {}) do
        local x = (spec.x - 8) * radius / 8
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = spec.radius * radius / 8
        circle.center = Vector2(mirror and -x or x, (8 - spec.y) * radius / 8)
        setSurface(circle)
        shapes[#shapes + 1] = circle
    end
    return shapes
end

---@class BottleDeckSimRecord
---@field uid number
---@field id string
---@field scale number
---@field weight number
---@field woolCount number 小羊当前储毛量（只影响专用图案/轮廓，不改变scale/weight）
---@field woolTier number 小羊轮廓档0/1/5
---@field source ItemInstance 实例实时引用，只读；用于沙盒已打开时同步物理倍率
---@field shapes CollisionShape2D[] 普通物品的全部 fixture，基准密度保持原1
---@field rollValue number? 骰子实际点数，仅供绘制
---@field radius number?
---@field node Node?
---@field body RigidBody2D?
---@field soft BottleSoftBacon?

---@class BottleDeckSim
---@field scene Scene
---@field world PhysicsWorld2D
---@field records table<number, BottleDeckSimRecord>
---@field order BottleDeckSimRecord[]
---@field wallNodes Node[]
---@field disposed boolean
---@field width number?
---@field wallTop number?
---@field floorWall {node:Node, box:CollisionBox2D}?
---@field leftWall {node:Node, box:CollisionBox2D}?
---@field rightWall {node:Node, box:CollisionBox2D}?
local Sim = {}
Sim.__index = Sim

---@param name string
---@param x number
---@param y number
---@param halfWidth number
---@param halfHeight number
---@return {node:Node, box:CollisionBox2D}
function Sim:_Wall(name, x, y, halfWidth, halfHeight)
    local node = self.scene:CreateChild(name)
    node:SetPosition2D(x, y)
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_STATIC
    local box = node:CreateComponent("CollisionBox2D")
    box:SetSize(halfWidth * 2, halfHeight * 2)
    setSurface(box, WALL_CATEGORY, 0xFFFF)
    self.wallNodes[#self.wallNodes + 1] = node
    return {node = node, box = box}
end

-- 世界边界跟随牌库面板的真实宽高比：底墙紧贴面板下沿，左右墙紧贴两侧边框，
-- 避免固定 4.8×5.4 世界在面板内缩出空白，看起来像没有贴合边框。
---@param width number
function Sim:SetBounds(width)
    if not finite(width) or width <= 0 then return end
    width = clamp(width, 2.4, 14)
    if self.width and math.abs(width - self.width) < .001 then return end
    self.width = width
    local top = self.wallTop or 8
    local t = WALL_THICKNESS
    local floor, left, right = self.floorWall, self.leftWall, self.rightWall
    if not (floor and left and right) then return end
    floor.node:SetPosition2D(0, -t * .5)
    floor.box:SetSize(width + t * 2, t)
    left.node:SetPosition2D(-width * .5 - t * .5, top * .5)
    left.box:SetSize(t, top)
    right.node:SetPosition2D(width * .5 + t * .5, top * .5)
    right.box:SetSize(t, top)
    -- 首帧才得知宽度时，把已经生成的物品收进新的左右边界内。
    local limit = math.max(.05, width * .5)
    for _, record in ipairs(self.order) do
        if record.node then
            local position = record.node.position2D
            if record.soft then
                local minX, maxX = math.huge, -math.huge
                for _, pose in ipairs(record.soft:GetPose()) do
                    local extent = math.abs(math.cos(pose.angle)) * pose.halfLength
                        + math.abs(math.sin(pose.angle)) * pose.halfWidth
                    minX, maxX = math.min(minX, pose.x - extent), math.max(maxX, pose.x + extent)
                end
                local low, high = -limit + .01 - minX, limit - .01 - maxX
                local shift = low <= high and clamp(0, low, high) or -(minX + maxX) * .5
                if math.abs(shift) > 1e-7 then
                    -- 等量平移全部段，保留相对姿态与关节本地锚点。
                    for _, segment in ipairs(record.soft.segments) do
                        local point = segment.node.position2D
                        segment.node:SetPosition2D(point.x + shift, point.y)
                    end
                end
            else
                local half = record.radius or .27
                local x = clamp(position.x, -limit + half, limit - half)
                if x ~= position.x then record.node:SetPosition2D(x, position.y) end
            end
        end
    end
end

---@param item BottleDeckSimRecord
---@param x number
---@param y number
function Sim:_CreateBody(item, x, y)
    local def = Items.byId[item.id]
    local radius = def.radius * item.scale
    if item.id == "bacon" then
        local soft = SoftBacon.New(self.scene, item.uid, radius, x, y,
            (item.uid * 137.507764) % 360, setSurface, item.weight)
        local center = assert(soft.segments[SoftBacon.CENTER_SEGMENT])
        item.node, item.body, item.radius, item.soft = center.node, center.body, radius, soft
        return
    end
    local node = self.scene:CreateChild("deck_item_" .. item.uid)
    node:SetPosition2D(x, y)
    node.rotation2D = item.id == "ghost" and 0 or (item.uid * 137.507764) % 360
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC
    body.useFixtureMass = true
    body.fixedRotation = item.id == "ghost"
    body.linearDamping = .25
    body.angularDamping = .8
    body.gravityScale = 1
    body.bullet = true
    body.allowSleep = true
    local profile = Shapes.profiles[Shapes.Variant(def.shape, item.woolCount)]
    ---@type CollisionShape2D[]
    local shapes = {}
    if profile then
        shapes = createProfile(node, profile, radius, item.id == "slipper_right")
    elseif def.shape == "box" then
        local box = node:CreateComponent("CollisionBox2D")
        local halfSize = radius / math.sqrt(2)
        box:SetSize(halfSize * 2, halfSize * 2)
        setSurface(box)
        shapes[#shapes + 1] = box
    else
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = radius
        setSurface(circle)
        shapes[#shapes + 1] = circle
    end
    -- 气球原型密度为普通物品的35%；公开weight仍是相对原型的100%。
    local density = item.weight * (item.id == "balloon" and .35 or 1)
    for _, fixture in ipairs(shapes) do
        if fixture.density ~= density then fixture.density = density end
    end
    item.shapes = shapes
    body.linearVelocity = Vector2(0, 0)
    body.angularVelocity = 0
    body.awake = true
    item.node, item.body, item.radius = node, body, radius
end

---@param entries ItemInstance[]
---@return BottleDeckSim
function Sim.New(entries)
    local self = setmetatable({records = {}, order = {}, wallNodes = {}}, Sim)
    self.scene = Scene()
    self.scene.updateEnabled = false
    self.scene:CreateComponent("Octree")
    self.world = self.scene:CreateComponent("PhysicsWorld2D")
    self.world.updateEnabled = true
    self.world.gravity = Vector2(0, -9.81)
    self.world.autoClearForces = true
    self.world.continuousPhysics = true
    self.world.subStepping = false
    self.world.velocityIterations = 12
    self.world.positionIterations = 8
    self.world.allowSleeping = true
    self.world.warmStarting = true
    self.disposed = false

    for _, item in ipairs(entries) do
        if Items.byId[item.id] then
            local scale = PhysicalState.Clamp(item.id, "scale", item.scale)
            local weight = PhysicalState.Clamp(item.id, "weight", item.weight)
            local woolCount = item.woolCount or 0
            ---@type BottleDeckSimRecord
            local record = {uid = item.uid, id = item.id, scale = scale, weight = weight,
                woolCount = woolCount, woolTier = woolCount >= 5 and 5 or (woolCount >= 1 and 1 or 0),
                source = item, shapes = {}, rollValue = item.rollValue}
            self.records[item.uid] = record
            self.order[#self.order + 1] = record
        end
    end
    table.sort(self.order, function(a, b) return a.uid < b.uid end)

    -- 生成高度：按最大旋转包络排成若干行，整批从可见区域上方落下。
    local maxExtent = .1
    for _, record in ipairs(self.order) do
        local def = Items.byId[record.id]
        local radius = def.radius * record.scale
        local extent = record.id == "bacon" and SoftBacon.Envelope(radius)
            or Shapes.Envelope(Shapes.Variant(def.shape, record.woolCount), radius)
        maxExtent = math.max(maxExtent, extent)
    end
    local margin = math.max(.24, maxExtent * .8)
    local unit = math.max(.5, maxExtent * 2 + .12)
    local columns = math.max(1, math.min(10, math.floor((SPAWN_WIDTH - margin * 2) / unit) + 1))
    local spacing = columns > 1 and (SPAWN_WIDTH - margin * 2) / (columns - 1) or 0
    local rows = math.ceil(#self.order / columns)
    local spawnTop = WORLD_HEIGHT + .6 + math.max(0, rows - 1) * math.max(.6, unit * .8)
    local wallTop = spawnTop + 1.2

    self.wallTop = wallTop
    self.floorWall = self:_Wall("deck_floor", 0, -WALL_THICKNESS * .5,
        WORLD_WIDTH * .5 + WALL_THICKNESS, WALL_THICKNESS * .5)
    self.leftWall = self:_Wall("deck_left", -WORLD_WIDTH * .5 - WALL_THICKNESS * .5, wallTop * .5,
        WALL_THICKNESS * .5, wallTop * .5)
    self.rightWall = self:_Wall("deck_right", WORLD_WIDTH * .5 + WALL_THICKNESS * .5, wallTop * .5,
        WALL_THICKNESS * .5, wallTop * .5)
    self.width = WORLD_WIDTH

    local safeHalf = math.max(.05, SPAWN_WIDTH * .5 - maxExtent - .02)
    for index, record in ipairs(self.order) do
        local column = (index - 1) % columns
        local row = math.floor((index - 1) / columns)
        local x = columns > 1 and (-(SPAWN_WIDTH * .5 - margin) + column * spacing) or 0
        -- 由 uid 派生的固定横向抖动，避免整列完全对齐；不占用玩法随机序列。
        local jitter = (((record.uid * 37) % 13) - 6) / 6 * spacing * .12
        x = clamp(x + jitter, -safeHalf, safeHalf)
        local y = WORLD_HEIGHT + .6 + row * math.max(.6, unit * .8)
        self:_CreateBody(record, x, y)
    end
    return self
end

---沙盒打开期间也同步实时倍率；只改重量不重建物体/软体关节。
---仅在世界解锁时调用（Step 推进前），绝不修改规则实例本身。
function Sim:Sync()
    if self.disposed then return end
    for _, record in ipairs(self.order) do
        local source = record.source
        local scale = PhysicalState.Clamp(source.id, "scale", source.scale)
        local weight = PhysicalState.Clamp(source.id, "weight", source.weight)
        local woolCount = source.woolCount or 0
        local woolTier = source.id == "sheep" and (woolCount >= 5 and 5 or (woolCount >= 1 and 1 or 0)) or 0
        record.rollValue, record.woolCount = source.rollValue, woolCount
        if record.node and (record.id ~= source.id or record.scale ~= scale or record.woolTier ~= woolTier) then
            local position = record.node.position2D
            local angle = record.node.rotation2D
            local velocity = record.body and record.body.linearVelocity or Vector2(0, 0)
            local angularVelocity = record.body and record.body.angularVelocity or 0
            if record.soft then record.soft:Dispose()
            else record.node:Remove(); record.node:Dispose() end
            record.soft, record.node, record.body = nil, nil, nil
            record.shapes = {}
            record.id, record.scale, record.weight, record.woolTier = source.id, scale, weight, woolTier
            self:_CreateBody(record, position.x, position.y)
            if record.soft then
                for _, segment in ipairs(record.soft.segments) do
                    segment.body.linearVelocity = velocity
                    segment.body.angularVelocity = angularVelocity
                end
            elseif record.node and record.body then
                record.node.rotation2D = record.id == "ghost" and 0 or angle
                record.body.linearVelocity = velocity
                record.body.angularVelocity = record.id == "ghost" and 0 or angularVelocity
            end
        elseif record.weight ~= weight then
            if record.soft then
                record.soft:SetWeight(weight)
            else
                local density = weight * (record.id == "balloon" and .35 or 1)
                for _, fixture in ipairs(record.shapes) do fixture.density = density end
                if record.body then record.body.awake = true end
            end
            record.weight = weight
        end
    end
end

---@param dt number
function Sim:Step(dt)
    if self.disposed or not finite(dt) or dt <= 0 then return end
    self:Sync()
    for _, record in ipairs(self.order) do
        if record.soft then record.soft:Step(dt) end
    end
    self.scene:Update(dt)
end

---@param uid number
---@return BottleSoftPose[]?
function Sim:GetSoftPose(uid)
    local record = self.records[uid]
    return not self.disposed and record and record.soft and record.soft:GetPose() or nil
end

---@param uid number
---@param x number 世界米坐标
---@param y number
---@return boolean
function Sim:ContainsPoint(uid, x, y)
    local record = self.records[uid]
    if self.disposed or not record or not record.node or not finite(x) or not finite(y) then return false end
    if record.soft then return record.soft:ContainsPoint(x, y) end
    local position = record.node.position2D
    return Art.HitItem(record.id, x - position.x, position.y - y,
        record.radius or .27, -record.node.rotation2D * math.pi / 180, record.woolCount)
end

---@param uid number
---@return number x
---@return number y
---@return number angle
---@return number radius
function Sim:GetPose(uid)
    local record = self.records[uid]
    if self.disposed or not record or not record.node then return 0, 0, 0, .27 end
    local position = record.node.position2D
    return position.x, position.y, record.node.rotation2D * math.pi / 180, record.radius or .27
end

function Sim:Dispose()
    if self.disposed then return end
    self.disposed = true
    self.world.updateEnabled = false
    for _, record in pairs(self.records) do
        if record.soft then
            record.soft:Dispose()
        elseif record.node then
            record.node:Remove()
            record.node:Dispose()
        end
    end
    for _, node in ipairs(self.wallNodes) do
        node:Remove()
        node:Dispose()
    end
    self.scene:RemoveAllComponents()
    self.world:Dispose()
    self.scene:Dispose()
end

---@class BottleDeckBoard : Widget
---@field sim BottleDeckSim
---@field onPick fun(uid:number)
---@field accumulator number
---@overload fun(props:WidgetProps): BottleDeckBoard
local Board = UI.Widget:Extend("BottleDeckBoard")

function Board:Init(props)
    self.sim = props.sim
    self.onPick = props.onPick
    self.accumulator = 0
    self.pressId = -1
    self.pressX, self.pressY = 0, 0
    self.clickMoved = false
    props.sim, props.onPick = nil, nil
    UI.Widget.Init(self, props)
end

-- 世界米制坐标 → 屏幕坐标：高度铺满面板，宽度按面板宽高比同步收缩/扩张，
-- 因此左右墙与底墙正好落在牌库区域边框上。
---@return number x
---@return number y
---@return number ppu
function Board:GetTransform()
    local layout = self:GetAbsoluteLayout()
    local ppu = math.max(1, layout.h / WORLD_HEIGHT)
    self.sim:SetBounds(layout.w / ppu)
    return layout.x + layout.w * .5, layout.y + layout.h, ppu
end

---@param uid integer
---@return {x:number,y:number,w:number,h:number}
function Board:GetItemBounds(uid)
    local x, y, ppu = self:GetTransform()
    local poses = self.sim:GetSoftPose(uid)
    if poses then
        local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
        for _, pose in ipairs(poses) do
            local cosine, sine = math.abs(math.cos(pose.angle)), math.abs(math.sin(pose.angle))
            local ex = cosine * pose.halfLength + sine * pose.halfWidth
            local ey = sine * pose.halfLength + cosine * pose.halfWidth
            minX, maxX = math.min(minX, pose.x - ex), math.max(maxX, pose.x + ex)
            minY, maxY = math.min(minY, pose.y - ey), math.max(maxY, pose.y + ey)
        end
        return {x = x + minX * ppu - 4, y = y - maxY * ppu - 4,
            w = (maxX - minX) * ppu + 8, h = (maxY - minY) * ppu + 8}
    end
    local px, py, angle, radius = self.sim:GetPose(uid)
    local record = self.sim.records[uid]
    local extent = Art.ItemExtent(record and record.id or "apple", radius * ppu, -angle,
        record and record.woolCount or nil) + 4
    return {x = x + px * ppu - extent, y = y - py * ppu - extent, w = extent * 2, h = extent * 2}
end

---@param x number
---@param y number
---@return number
function Board:PickItem(x, y)
    local layout = self:GetAbsoluteLayout()
    if x < layout.x or x > layout.x + layout.w or y < layout.y or y > layout.y + layout.h then return 0 end
    local originX, originY, ppu = self:GetTransform()
    for index = #self.sim.order, 1, -1 do
        local record = self.sim.order[index]
        if self.sim:ContainsPoint(record.uid, (x - originX) / ppu, (originY - y) / ppu) then
            return record.uid
        end
    end
    return 0
end

function Board:Update(dt)
    if self.sim.disposed then return end
    local layout = self:GetAbsoluteLayout()
    if layout.w <= 0 or layout.h <= 0 then return end
    -- 先按当前面板尺寸校准沙盒边界，再推进物理。
    self:GetTransform()
    self.accumulator = self.accumulator + math.min(math.max(dt, 0), .1)
    local steps = 0
    while self.accumulator >= FIXED_STEP and steps < MAX_STEPS do
        self.sim:Step(FIXED_STEP)
        self.accumulator = self.accumulator - FIXED_STEP
        steps = steps + 1
    end
end

---@param event PointerEvent
function Board:OnPointerDown(event)
    self.pressId = event.pointerId
    self.pressX, self.pressY = event.x, event.y
    self.clickMoved = false
end

---@param event PointerEvent
function Board:OnPointerMove(event)
    if event.pointerId ~= self.pressId then return end
    local dx, dy = event.x - self.pressX, event.y - self.pressY
    if dx * dx + dy * dy > 64 then self.clickMoved = true end
end

---@param event PointerEvent
function Board:OnPointerUp(event)
    self:OnPointerMove(event)
end

---@param event PointerEvent?
function Board:OnClick(event)
    if not event or not event:IsPrimaryButton() or self.clickMoved then return end
    self.clickMoved = true
    local uid = self:PickItem(event.x, event.y)
    if uid ~= 0 and self.onPick then self.onPick(uid) end
end

function Board:Render(vg)
    local layout = self:GetAbsoluteLayout()
    if layout.w <= 0 or layout.h <= 0 or self.sim.disposed then return end
    local originX, originY, ppu = self:GetTransform()
    nvgSave(vg)
    nvgIntersectScissor(vg, layout.x, layout.y, layout.w, layout.h)
    for _, record in ipairs(self.sim.order) do
        local poses = self.sim:GetSoftPose(record.uid)
        if poses then
            SoftView.Draw(vg, poses, originX, originY, ppu)
        else
            local px, py, angle, radius = self.sim:GetPose(record.uid)
            Art.Item(vg, record.id, originX + px * ppu, originY - py * ppu,
                radius * ppu, -angle, false, record.rollValue, record.woolCount)
        end
    end
    nvgRestore(vg)
end

local DeckBoard = {}
DeckBoard.Sim = Sim
DeckBoard.Widget = Board
return DeckBoard
