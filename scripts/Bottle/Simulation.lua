-- 引擎物理独立推进；这里只排队不可变物理输入，并预算执行规则与表现。
local FrameBudget = require("Bottle.FrameBudget")
local PresentationState = require("Bottle.PresentationState")
local Game = require("Bottle.Game")
local EPSILON = 1e-7

---@class BottleSimulation
---@field game BottleGame
---@field physics BottlePhysics
---@field budget BottleFrameBudget
---@field callbacks table
---@field queue table[]
---@field head integer
---@field tail integer
---@field accumulator number 未提交的规则输入秒数，不参与物理步进
---@field completedSteps integer
---@field maxSteps integer 仅限制每画面帧处理的逻辑包数
---@field disposed boolean
---@field pending table?
---@field events GameEvent[]?
---@field presentation BottleGame?
---@field presentationCache BottleGame?
---@field clockState table
---@field sequence integer
---@field epoch integer
---@field _ready boolean
---@field _physicsDt number?
local Simulation = {}
Simulation.__index = Simulation

local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, entry in pairs(value) do result[key] = Copy(entry) end
    return result
end

function Simulation.New(game, physics, callbacks, budget)
    local self = setmetatable({}, Simulation)
    self:Init(game, physics, callbacks, budget)
    return self
end

function Simulation:Init(game, physics, callbacks, budget)
    self.game, self.physics, self.callbacks = game, physics, callbacks
    self.budget = budget or FrameBudget.New()
    self.queue, self.head, self.tail = {}, 1, 0
    self.accumulator, self.completedSteps, self.sequence, self.epoch = 0, 0, 0, 1
    self.maxSteps, self.disposed, self._ready = 4, false, false
    self.events, self.presentation, self.presentationCache, self.pending = nil, nil, nil, nil
    self.clockState = {phase=game.phase, elapsed=game.elapsed, settleElapsed=game.settleElapsed,
        duration=game:Duration()}
end

function Simulation:Busy()
    return self.budget:Busy() or self.head <= self.tail or self._ready
end

function Simulation:PhysicsActive()
    return not self.disposed and (self.clockState.phase == "running" or self.clockState.phase == "settle")
end

function Simulation:Clock()
    if not self:PhysicsActive() and not self:Busy() then
        self.clockState.phase = self.game.phase
        self.clockState.elapsed, self.clockState.settleElapsed = self.game.elapsed, self.game.settleElapsed
        self.clockState.duration = self.game:Duration()
    end
    return self.clockState
end

function Simulation:Dispose()
    self.disposed, self.epoch = true, self.epoch + 1
    self.budget:Cancel()
    self.game._physicalMembers = nil
    self.queue, self.head, self.tail = {}, 1, 0
    self.accumulator, self._ready, self._physicsDt = 0, false, nil
    self.events, self.presentation, self.presentationCache, self.pending = nil, nil, nil, nil
end

function Simulation:ResetClock()
    assert(not self:Busy(), "未提交的逻辑输入不能清除")
    local game = self.game
    self.clockState.phase, self.clockState.duration = game.phase, game:Duration()
    self.clockState.elapsed, self.clockState.settleElapsed = game.elapsed, game.settleElapsed
    self.accumulator, self._physicsDt = 0, nil
end

-- 调用方位于原生物理边界：同步冻结数值，绝不借用后续会重写的行。
-- 跨越10/11秒和2秒边界时分割规则输入；物理积分仍由原生引擎执行一次。
function Simulation:Capture(dt, contacts)
    assert(type(dt)=="number" and dt >= 0 and dt == dt and dt < math.huge, "物理dt必须非负有限")
    if self.disposed or not self:PhysicsActive() or dt == 0 then return end
    local snapshot = Copy(contacts or {})
    local clock, remaining = self.clockState, dt
    while remaining > EPSILON and self:PhysicsActive() do
        local running = clock.phase == "running"
        local available = running and clock.duration-clock.elapsed or Game.SETTLE_DELAY-clock.settleElapsed
        local part = math.min(remaining, math.max(0, available))
        if part > EPSILON then
            self.sequence, self.tail = self.sequence + 1, self.tail + 1
            self.queue[self.tail] = {dt=part, phase=clock.phase, contacts=snapshot,
                sequence=self.sequence, epoch=self.epoch}
            self.accumulator = self.accumulator + part
            if running then clock.elapsed = math.min(clock.duration, clock.elapsed + part)
            else clock.settleElapsed = math.min(Game.SETTLE_DELAY, clock.settleElapsed + part) end
            remaining = math.max(0, remaining - part)
        end
        if available-part <= EPSILON then
            clock.phase = running and "settle" or "reveal"
        end
    end
end

function Simulation:BeforePhysics(dt, input)
    if dt <= 0 or not self:PhysicsActive() or self._physicsDt then return false end
    if self.physics:BeforeStep(dt, input) == false then return false end
    self._physicsDt = dt
    return true
end

function Simulation:AfterPhysics(dt)
    -- 2D原生Post事件实测会给出0；完成依据本次Pre保存的步长。
    -- 删除屏障/手动步没有打开Pre令牌，不会凭空生成输入包。
    if not self._physicsDt then return end
    local step = self._physicsDt
    self._physicsDt = nil
    self.physics:AfterStep(step)
    self.physics:TakeImpacts()
    self:Capture(step, self.physics:Contacts())
end

-- 剔除已经重建/转化/重生的旧代际；不能让历史接触污染同UID的新实体。
local function ContactsFor(self, packet)
    local contacts = Copy(packet.contacts)
    local generations, members = contacts.generations, contacts.members
    if members then
        for uid, id in pairs(members) do
            local body, item = self.physics.bodies[uid], self.game:Get(uid)
            if not body or not item or item.location ~= "bottle" or item.id ~= id
                or generations and generations[uid] ~= body.generation then
                for _, field in ipairs({"members","generations","positions","bottom","top","wall","side",
                    "angles","rotateOffsets","angularTravel","flightHits","flightArrived","poses",
                    "pathLengths","pathGeneration"}) do
                    if contacts[field] then contacts[field][uid] = nil end
                end
            end
        end
        for i = #(contacts.pairs or {}), 1, -1 do
            local pair = contacts.pairs[i]
            if not members[pair[1]] or not members[pair[2]] then table.remove(contacts.pairs, i) end
        end
    end
    return contacts
end

-- 表现捕获只读取同一输入包的姿态，不跨yield读取正在运动的刚体。
function Simulation.PhysicsView(contacts)
    local poses, members = contacts.poses or {}, contacts.members or {}
    local result = {bodies={}}
    for uid, pose in pairs(poses) do
        result.bodies[uid] = {kind=members[uid], radius=pose.radius}
    end
    function result:GetPose(uid)
        local pose = poses[uid]
        if not pose then return 0, 3.2, 0, .27 end
        return pose.x, pose.y, pose.angle, pose.radius
    end
    function result:GetSoftPose(uid) return poses[uid] and poses[uid].soft or nil end
    return result
end

function Simulation:_StartPacket(packet)
    self.pending = packet
    self.budget:Start(function()
        self.presentation = PresentationState.Capture(self.game, self.presentationCache)
        self.presentationCache = self.presentation
        local contacts = ContactsFor(self, packet)
        self.game._physicalMembers = contacts.members
        self.events = packet.phase == "settle" and self.game:SettleStep(packet.dt, contacts)
            or self.game:Step(packet.dt, contacts)
        self.game._physicalMembers = nil
        FrameBudget.Checkpoint()
        self.callbacks.bind(self.game, true)
        self.callbacks.events(self.events, Simulation.PhysicsView(contacts))
        self._ready = true
    end)
end

-- 在协程以外、世界已解锁时一次性发布完整物理命令和实例描述。
function Simulation:_CommitPacket()
    assert(self._ready and self.pending and self.events)
    self.physics:RememberEvents(self.events)
    self.callbacks.sync()
    self.callbacks.bind(self.game, false)
    if self.callbacks.publish then self.callbacks.publish(self.events) end
    self.accumulator = math.max(0, self.accumulator - self.pending.dt)
    self.completedSteps = self.completedSteps + 1
    self.queue[self.head], self.head = nil, self.head + 1
    self.pending, self.events, self.presentation, self._ready = nil, nil, nil, false
    if self.head > self.tail then self.queue, self.head, self.tail = {}, 1, 0 end
end

-- dt只用于接口兼容；物理和显示时钟均不由规则协程推进。
function Simulation:Update(dt, input)
    if self.disposed then return false end
    assert(dt >= 0 and dt == dt and dt < math.huge, "逻辑dt必须非负有限")
    local phase = self.game.phase
    self.budget:BeginFrame()
    local steps = 0
    while steps < self.maxSteps and self:Busy() do
        if not self.budget:Busy() and not self._ready then
            if steps > 0 and self.budget:Expired() then break end
            local packet = assert(self.queue[self.head])
            assert(packet.epoch == self.epoch, "旧局物理输入不可提交")
            self:_StartPacket(packet)
        end
        self.callbacks.bind(self.game, true)
        if not self.budget:Resume() then
            self.callbacks.bind(self.presentation or self.game, true)
            return self.game.phase ~= phase
        end
        self:_CommitPacket()
        steps = steps + 1
        if self.budget:Expired() then break end
    end
    return self.game.phase ~= phase
end

return Simulation
