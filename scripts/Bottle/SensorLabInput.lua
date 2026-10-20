-- 开发态文件桥的纯 Lua 输入队列；不联网、不读玩家存档，不自行推进物理世界。
-- 每个样本只 Sensor 一次，按源 dt 分段推进 motion；一次 Advance 的总时长仍等于物理步。
local Tuning = require("Bottle.SensorTuning")
---@class BottleSensorLabInput
---@field sessionId string
---@field generation number
---@field cursor number
---@field resetRevision number
---@field deviceId string
---@field screenAngle number
---@field sampleId number
---@field allowed boolean
---@field touchHolding boolean
---@field heartbeatAge number
---@field sampleAge number
---@field settingsRevision number
---@field invertX boolean
---@field invertY boolean
---@field pendingSettings table?
---@field reason string
---@field queue {sample:table,remaining:number,started:boolean,invertX:boolean,invertY:boolean}[]
---@field head number
---@field queuedDuration number
---@field waitingBaseline boolean
---@field pendingReset boolean
local Input = {}
Input.__index = Input
local FORMAT = "shakehero-sensor-bridge/v1"
local STALE, MAX_BACKLOG, MAX_QUEUE, STEP = .25, .15, 128, 1 / 60

local function finite(value)
    return type(value) == "number" and not tostring(value):lower():find("nan", 1, true)
        and math.abs(value) < math.huge
end

local function integer(value)
    return finite(value) and value >= 0 and value == math.floor(value)
end

local function sample(value)
    if type(value) ~= "table" or not integer(value.seq) or value.seq < 1
        or not finite(value.ax) or not finite(value.ay) or math.abs(value.ax) > 100 or math.abs(value.ay) > 100
        or not finite(value.dt) or value.dt <= 0 or not finite(value.screenAngle)
        or type(value.deviceId) ~= "string" or value.deviceId == "" then return nil end
    return {seq=value.seq, sampleId=integer(value.sampleId) and value.sampleId > 0 and value.sampleId or nil,
        deviceId=value.deviceId, screenAngle=value.screenAngle, ax=value.ax, ay=value.ay, dt=value.dt}
end

---@return BottleSensorLabInput
function Input.New()
    local self = setmetatable({}, Input)
    self:Init()
    return self
end

function Input:Init()
    self.sessionId, self.generation, self.cursor, self.resetRevision = "", -1, 0, -1
    self.deviceId, self.screenAngle, self.sampleId = "", 0, 0
    self.allowed, self.touchHolding = false, false
    self.heartbeatAge, self.sampleAge = math.huge, math.huge
    self.settingsRevision = -1
    self.invertX, self.invertY = false, false
    ---@type table?
    self.pendingSettings = nil
    self.reason = "waiting"
    self:Reset()
end

-- 保留网络游标；重复读取同一 ring 不会把校准前、暂停中或拖动中的输入补播。
function Input:Reset()
    self.queue, self.head, self.queuedDuration = {}, 1, 0
    self.waitingBaseline, self.pendingReset = true, true
end

function Input:IsAvailable()
    return self.deviceId ~= "" and self.heartbeatAge <= STALE and self.sampleAge <= STALE
end

function Input:Update(dt, allowed, touchHolding)
    if finite(dt) and dt > 0 then
        self.heartbeatAge, self.sampleAge = self.heartbeatAge + dt, self.sampleAge + dt
    end
    self.allowed, self.touchHolding = allowed == true, touchHolding == true
    if not self.allowed or self.touchHolding then
        self:Reset()
        self.reason = self.touchHolding and "touch" or "paused"
    elseif not self:IsAvailable() then
        if not self.waitingBaseline or self.queuedDuration > 0 then self:Reset() end
        self.reason = "stale"
    end
end

function Input:TakeSettings()
    local value = self.pendingSettings
    self.pendingSettings = nil
    return value
end

function Input:Queue(value)
    if self.head > MAX_QUEUE then
        local tail = {}
        for index = self.head, #self.queue do tail[#tail + 1] = self.queue[index] end
        self.queue, self.head = tail, 1
    end
    local duration = value.dt > MAX_BACKLOG and STEP or value.dt
    self.queue[#self.queue + 1] = {sample=value, remaining=duration, started=false,
        invertX=self.invertX, invertY=self.invertY}
    self.queuedDuration = self.queuedDuration + duration
end

-- snapshot 是 Node 原子写出的 heartbeat 快照。重复 generation 不刷新存活时间。
function Input:Ingest(snapshot)
    if type(snapshot) ~= "table" or snapshot.format ~= FORMAT
        or type(snapshot.sessionId) ~= "string" or snapshot.sessionId == ""
        or not integer(snapshot.generation) or not integer(snapshot.resetRevision)
        or type(snapshot.samples) ~= "table" or #snapshot.samples > MAX_QUEUE then return false end
    local freshSession = snapshot.sessionId ~= self.sessionId
    if not freshSession and snapshot.generation <= self.generation then return false end
    local settings = snapshot.settings
    local gain = type(settings) == "table" and Tuning.Normalize(settings.gain) or nil
    if not gain or not integer(settings.revision) or type(settings.invertX) ~= "boolean"
        or type(settings.invertY) ~= "boolean" then return false end
    local age = snapshot.sampleAgeMs
    if type(age) == "number" and (not finite(age) or age < 0) then return false end
    local incoming, previous = {}, 0
    for _, value in ipairs(snapshot.samples) do
        local item = sample(value)
        if not item or item.seq <= previous then return false end
        previous = item.seq
        incoming[#incoming + 1] = item
    end
    if freshSession then
        self.sessionId, self.cursor, self.settingsRevision = snapshot.sessionId, 0, -1
        self.deviceId, self.sampleId = "", 0
        self:Reset()
    end
    self.generation = snapshot.generation
    self.heartbeatAge, self.sampleAge = 0, snapshot.stopped ~= true and finite(age) and age / 1000 or math.huge
    if self.resetRevision ~= snapshot.resetRevision then self:Reset() end
    self.resetRevision = snapshot.resetRevision
    if settings.revision > self.settingsRevision then
        if self.invertX ~= settings.invertX or self.invertY ~= settings.invertY then self:Reset() end
        self.invertX, self.invertY = settings.invertX, settings.invertY
        self.settingsRevision = settings.revision
        self.pendingSettings = {gain=gain, invertX=self.invertX, invertY=self.invertY, revision=settings.revision}
    end
    local added, discontinuity = {}, false
    local device, angle, id = self.deviceId, self.screenAngle, self.sampleId
    for _, item in ipairs(incoming) do
        if item.seq > self.cursor then
            if self.cursor > 0 and item.seq ~= self.cursor + 1 then discontinuity = true end
            self.cursor = item.seq
            local switched = device ~= "" and (device ~= item.deviceId or angle ~= item.screenAngle)
            if switched then discontinuity = true end
            local same = device == item.deviceId
            if not (same and item.sampleId and item.sampleId <= id) then
                if same and item.sampleId and id > 0 and item.sampleId ~= id + 1 then discontinuity = true end
                if item.dt > MAX_BACKLOG then discontinuity = true end
                added[#added + 1] = item
                device, angle, id = item.deviceId, item.screenAngle, item.sampleId or 0
            end
        end
    end
    self.deviceId, self.screenAngle, self.sampleId = device, angle, id
    if snapshot.stopped == true then
        self:Reset()
        self.reason = "stopped"
        return true
    end
    if not self.allowed or self.touchHolding or not self:IsAvailable() then
        if not self.waitingBaseline or self.queuedDuration > 0 then self:Reset() end
        return true
    end
    if #added == 0 then return true end
    local duration = self.queuedDuration
    for _, item in ipairs(added) do duration = duration + math.min(item.dt, MAX_BACKLOG + STEP) end
    if discontinuity or duration > MAX_BACKLOG + 1e-9 or #self.queue - self.head + #added + 1 > MAX_QUEUE then
        self:Reset()
        self.reason = discontinuity and "discontinuity" or "backlog"
    end
    if self.waitingBaseline then
        self:Queue(added[#added])
        self.waitingBaseline = false
        self.reason = "calibrating"
    else
        for _, item in ipairs(added) do self:Queue(item) end
        self.reason = "online"
    end
    return true
end

-- 由 Physics:Step 的开发体感入口调用，替代该步原本的 motion:Step。
-- Sensor 仍走 Physics:Sensor -> Shake -> Move，惯性返回给原来的一次物理解算。
function Input:Advance(dt, physics)
    if not finite(dt) or dt <= 0 or not physics then return 0, 0 end
    local motion = physics.motion
    if self.pendingReset then motion:ResetSensor(); self.pendingReset = false end
    if not self.allowed or self.touchHolding or motion.holding then
        self:Reset()
        motion:ResetSensor()
        self.pendingReset = false
        return motion:Step(dt)
    end
    -- 断流只在交接时清一次传感器，之后允许原生输入正常建立自己的基线。
    if not self:IsAvailable() then return motion:Step(dt) end
    local remaining, dvx, dvy = dt, 0, 0
    while remaining > 0 do
        local entry = self.queue[self.head]
        if not entry then
            local x, y = motion:Step(remaining)
            dvx, dvy = dvx + x, dvy + y
            break
        end
        if not entry.started then
            local value = entry.sample
            physics:Sensor(value.ax * (entry.invertX and -1 or 1), value.ay * (entry.invertY and -1 or 1), value.dt)
            entry.started = true
        end
        local step = math.min(remaining, entry.remaining)
        local x, y = motion:Step(step)
        dvx, dvy = dvx + x, dvy + y
        remaining = math.max(0, remaining - step)
        entry.remaining = math.max(0, entry.remaining - step)
        self.queuedDuration = math.max(0, self.queuedDuration - step)
        if entry.remaining <= 1e-12 then
            self.head = self.head + 1
            if self.head > #self.queue then self.queue, self.head = {}, 1 end
        end
    end
    return dvx, dvy
end

return Input
