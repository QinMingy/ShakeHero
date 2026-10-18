-- 牌库物理沙盒：所有持有实例从顶部落下，在矩形屏幕容器内按真实 Box2D 碰撞停稳。
-- 独立 Scene／World，只用于牌库页表现；不接入回合物理、玩法随机与存档。
local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Shapes = require("Bottle.Shapes")
local Art = require("Bottle.Art")

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
local function createProfile(node, profile, radius, mirror)
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
    end
    for _, spec in ipairs(profile.circles or {}) do
        local x = (spec.x - 8) * radius / 8
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = spec.radius * radius / 8
        circle.center = Vector2(mirror and -x or x, (8 - spec.y) * radius / 8)
        setSurface(circle)
    end
end

---@class BottleDeckSimRecord
---@field uid number
---@field id string
---@field scale number
---@field radius number?
---@field node Node?
---@field body RigidBody2D?

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
            local half = (record.radius or .27)
            local x = clamp(position.x, -limit + half, limit - half)
            if x ~= position.x then record.node:SetPosition2D(x, position.y) end
        end
    end
end

---@param item BottleDeckSimRecord
---@param x number
---@param y number
function Sim:_CreateBody(item, x, y)
    local def = Items.byId[item.id]
    local radius = def.radius * item.scale
    local node = self.scene:CreateChild("deck_item_" .. item.uid)
    node:SetPosition2D(x, y)
    node.rotation2D = (item.uid * 137.507764) % 360
    local body = node:CreateComponent("RigidBody2D")
    body.bodyType = BT_DYNAMIC
    body.useFixtureMass = true
    body.fixedRotation = false
    body.linearDamping = .25
    body.angularDamping = .8
    body.gravityScale = 1
    body.bullet = true
    body.allowSleep = true
    local profile = Shapes.profiles[def.shape]
    if profile then
        createProfile(node, profile, radius, item.id == "slipper_right")
    elseif def.shape == "box" then
        local box = node:CreateComponent("CollisionBox2D")
        local halfSize = radius / math.sqrt(2)
        box:SetSize(halfSize * 2, halfSize * 2)
        setSurface(box)
    else
        local circle = node:CreateComponent("CollisionCircle2D")
        circle.radius = radius
        setSurface(circle)
    end
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
            ---@type table
            local source = item
            local scale = source.scale
            if type(scale) ~= "number" or scale ~= scale or scale <= 0 then scale = 1 end
            local record = {uid = item.uid, id = item.id, scale = scale}
            self.records[item.uid] = record
            self.order[#self.order + 1] = record
        end
    end
    table.sort(self.order, function(a, b) return a.uid < b.uid end)

    -- 生成高度：按最大旋转包络排成若干行，整批从可见区域上方落下。
    local maxExtent = .1
    for _, record in ipairs(self.order) do
        local def = Items.byId[record.id]
        maxExtent = math.max(maxExtent, Shapes.Envelope(def.shape, def.radius * record.scale))
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

---@param dt number
function Sim:Step(dt)
    if self.disposed or not finite(dt) or dt <= 0 then return end
    self.scene:Update(dt)
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
        if record.node then
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
    local px, py, angle, radius = self.sim:GetPose(uid)
    local record = self.sim.records[uid]
    local extent = Art.ItemExtent(record and record.id or "apple", radius * ppu, -angle) + 4
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
        local px, py, angle, radius = self.sim:GetPose(record.uid)
        if Art.HitItem(record.id, x - originX - px * ppu, y - originY + py * ppu, radius * ppu, -angle) then
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
        local px, py, angle, radius = self.sim:GetPose(record.uid)
        Art.Item(vg, record.id, originX + px * ppu, originY - py * ppu, radius * ppu, -angle)
    end
    nvgRestore(vg)
end

local DeckBoard = {}
DeckBoard.Sim = Sim
DeckBoard.Widget = Board
return DeckBoard
