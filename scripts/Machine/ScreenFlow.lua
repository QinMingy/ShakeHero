-- 屏幕流动的纯表现时钟：读取瓶子速度，不写玩法、物理或共享时间。
-- time 累积平滑速度的解析积分，改变速度时不会重置纹理相位。
local RecordPool = require("Bottle.RecordPool")
---@class MachineScreenFlowMotion
---@field vx number?
---@field vy number?
---@field trace MachineScreenFlowTrace?

---@class MachineScreenFlowSample
---@field serial number
---@field time number
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field ax number
---@field ay number
---@field turn number

---@class MachineScreenFlowTrace
---@field generation number
---@field serial number
---@field time number
---@field latest MachineScreenFlowSample?
---@field points MachineScreenFlowSample[]

---@class MachineScreenFlowTrail
---@field x number UV
---@field y number UV，向下为正
---@field dx number UV方向，已翻转世界Y
---@field dy number
---@field age number 秒
---@field strength number 初始强度
---@field weight number 初始强度乘以平滑年龄衰减；上传dx*weight、dy*weight

---@class MachineScreenFlow
---@field time number 连续纹理相位
---@field speed number 当前流动速度
---@field vortex number 旋涡强度，0..1
---@field directionX number 平滑速度方向乘强度，世界坐标
---@field directionY number 世界坐标，+Y向上
---@field accelX number 已消费的固定步加速度脉冲，-1..1
---@field accelY number 世界坐标，+Y向上
---@field spin number 平滑有符号转向，-1..1
---@field rotation number 连续有符号旋转相位
---@field trails MachineScreenFlowTrail[]
---@field _trace MachineScreenFlowTrace?
---@field _generation number?
---@field _serial number
---@field _trailSerial number
---@field _turn number
---@field _sampleAge number
---@field _wasPaused boolean
---@field _clearTrace boolean
---@field _accelInputX number 已去重的输入脉冲；公开accel只通过缓冲跟随
---@field _accelInputY number
---@field _lastTrailTime number?
---@field _trailPool any Private record storage, independent of presentation state.
local Flow = {}
Flow.__index = Flow

local IDLE_SPEED, SHAKE_SPEED, REST_SPEED = .12, 1.2, .025
local DEAD_ZONE, FULL_MOTION_SPEED = .08, 2.2 -- 米/秒，与瓶子真实运动一致。
local ATTACK_RATE, RELEASE_RATE, VORTEX_RELEASE_RATE = 2.4, 2, 1.6
local REST_VORTEX = .15
local DIRECTION_RATE, SPIN_RATE, INPUT_DECAY = 2.4, 2.2, 4
local ACCEL_LIMIT, ACCEL_DECAY, ACCEL_FOLLOW = 30, 3, 4
local TRAIL_LIFE, TRAIL_ATTACK, TRAIL_SPACING = .9, .2, .14

---@param value any
---@return boolean
local function finite(value)
    -- Match ShakeMotion's Windows Runtime NaN guard (NaN == NaN can be true there).
    return type(value) == "number" and not tostring(value):lower():find("nan", 1, true)
        and math.abs(value) < math.huge
end

---@param motion MachineScreenFlowMotion|MachineScreenFlowSample|nil
---@return number
local function intensity(motion)
    if not motion then return 0 end
    -- 大于满强度的轴先限幅，避免有限但极大的外部值在平方时溢出。
    local vx = finite(motion.vx) and math.min(FULL_MOTION_SPEED, math.abs(motion.vx or 0)) or 0
    local vy = finite(motion.vy) and math.min(FULL_MOTION_SPEED, math.abs(motion.vy or 0)) or 0
    local speed = math.sqrt(vx * vx + vy * vy)
    return math.max(0, math.min(1, (speed - DEAD_ZONE) / (FULL_MOTION_SPEED - DEAD_ZONE)))
end

---@param value any
---@return number
local function number(value)
    return finite(value) and value or 0
end

---@param value number
---@return number
local function signed(value)
    return math.max(-1, math.min(1, value))
end

---@param x number
---@param y number
---@return number,number,number
local function direction(x, y)
    -- 缩放后求单位向量，有限但极大输入也不会产生 inf / inf。
    local scale = math.max(math.abs(x), math.abs(y))
    if scale <= .000001 then return 0, 0, 0 end
    local sx, sy = x / scale, y / scale
    local length = math.sqrt(sx * sx + sy * sy)
    return sx / length, sy / length, math.min(1, scale * length)
end

---@param trail MachineScreenFlowTrail
local function fadeTrail(trail)
    local remaining = math.max(0, 1 - trail.age / TRAIL_LIFE)
    local enter = math.min(1, trail.age / TRAIL_ATTACK)
    trail.weight = trail.strength * remaining * remaining * (3 - 2 * remaining)
        * enter * enter * (3 - 2 * enter)
end

---@param self MachineScreenFlow
local function clearTrace(self)
    self._trailPool:ClearActive(self.trails)
    self.directionX, self.directionY = 0, 0
    self.accelX, self.accelY, self.spin = 0, 0, 0
    self._accelInputX, self._accelInputY, self._lastTrailTime = 0, 0, nil
    self._turn, self._sampleAge, self._clearTrace = 0, 0, false
end

---@param self MachineScreenFlow
---@param trace MachineScreenFlowTrace?
---@param paused boolean?
local function bindTrace(self, trace, paused)
    local generation = trace and trace.generation or nil
    if self._trace == trace and self._generation == generation then return end
    self._trace, self._generation = trace, generation
    self._serial, self._trailSerial = 0, 0
    if paused then self._clearTrace = true else clearTrace(self) end
end

---@param self MachineScreenFlow
---@param motion MachineScreenFlowMotion?
---@param paused boolean?
local function blockTrace(self, motion, paused)
    local trace = motion and motion.trace
    bindTrace(self, trace, paused)
    local serial = trace and math.max(number(trace.serial), number(trace.latest and trace.latest.serial)) or 0
    self._serial, self._trailSerial = serial, serial
    -- 暂停时只推进消费游标，公开表现完全冻结；恢复后不补播暂停中的输入。
    self._turn = 0
end

---@param self MachineScreenFlow
---@param sample MachineScreenFlowSample
---@param traceTime number
local function addTrail(self, sample, traceTime)
    local sampleTime = number(sample.time)
    if self._lastTrailTime and sampleTime - self._lastTrailTime < TRAIL_SPACING then return end
    local age = math.max(0, traceTime - number(sample.time))
    if age >= TRAIL_LIFE then return end
    local vx, vy = number(sample.vx), number(sample.vy)
    local ax, ay = signed(number(sample.ax) / ACCEL_LIMIT), signed(number(sample.ay) / ACCEL_LIMIT)
    local dx, dy = direction(vx, vy)
    local _, _, acceleration = direction(ax, ay)
    if dx == 0 and dy == 0 then dx, dy = direction(ax, ay) end
    local strength = math.min(1, intensity(sample) * .75 + acceleration * .25) * .55
    if strength < .02 or (dx == 0 and dy == 0) then return end
    if #self.trails >= 6 then
        local oldest = self.trails[1]
        for index = 2, #self.trails do self.trails[index - 1] = self.trails[index] end
        self.trails[#self.trails] = nil
        self._trailPool:Release(oldest)
    end
    local trail = self._trailPool:Acquire() --[[@as MachineScreenFlowTrail]]
    trail.x = .5 + signed(number(sample.x) / .52) * .22
    trail.y = .5 - signed(number(sample.y) / .36) * .22
    trail.dx, trail.dy, trail.age, trail.strength, trail.weight = dx, -dy, age, strength, strength
    fadeTrail(trail)
    self.trails[#self.trails + 1] = trail
    self._lastTrailTime = sampleTime
end

---@param sample MachineScreenFlowSample
local function peakImpulse(sample, previous, traceTime, peakX, peakY, peakLength)
    if not finite(sample.serial) or sample.serial <= previous then return peakX, peakY, peakLength end
    local age = math.max(0, traceTime - number(sample.time))
    local decay = math.exp(-ACCEL_DECAY * age)
    local ax = signed(number(sample.ax) / ACCEL_LIMIT) * decay
    local ay = signed(number(sample.ay) / ACCEL_LIMIT) * decay
    local length = ax * ax + ay * ay
    if length > peakLength then return ax, ay, length end
    return peakX, peakY, peakLength
end

---@param self MachineScreenFlow
---@param motion MachineScreenFlowMotion?
local function consumeTrace(self, motion)
    local trace = motion and motion.trace
    bindTrace(self, trace)
    if not trace then return end
    local traceTime, previous = number(trace.time), self._serial
    local serial = math.max(number(trace.serial), number(trace.latest and trace.latest.serial))
    local peakX, peakY, peakLength = 0, 0, 0
    local points = trace.points
    if points then for _, sample in ipairs(points) do
        peakX, peakY, peakLength = peakImpulse(sample, previous, traceTime, peakX, peakY, peakLength)
        if finite(sample.serial) and sample.serial > self._trailSerial then
            addTrail(self, sample, traceTime)
            self._trailSerial = sample.serial
        end
    end end
    local latest = trace.latest
    if latest and finite(latest.serial) and latest.serial > previous then
        peakX, peakY, peakLength = peakImpulse(latest, previous, traceTime, peakX, peakY, peakLength)
        self._turn, self._sampleAge = signed(number(latest.turn)), 0
        -- trace 已在固定物理步平滑加速度。只消费一次峰值，不按渲染帧重复加力。
        if peakLength > 0 then self._accelInputX, self._accelInputY = peakX, peakY end
    end
    self._serial = math.max(self._serial, serial)
end

---@return MachineScreenFlow
function Flow.New()
    local self = setmetatable({trails = {}, _trailPool = RecordPool.New(8)}, Flow)
    self:Reset()
    return self
end

function Flow:Reset()
    self.time, self.speed, self.vortex = 0, IDLE_SPEED, 0
    self.directionX, self.directionY, self.accelX, self.accelY = 0, 0, 0, 0
    self.spin, self.rotation = 0, 0
    self._trailPool:ClearActive(self.trails)
    self._trace, self._generation = nil, nil
    self._serial, self._trailSerial, self._turn, self._sampleAge = 0, 0, 0, 0
    self._wasPaused, self._clearTrace = false, false
    self._accelInputX, self._accelInputY, self._lastTrailTime = 0, 0, nil
end

---@param dt number 秒；非正数或非有限数不推进表现。
---@param phase string
---@param motion MachineScreenFlowMotion? 只读；holding 不代表摇动。
---@param paused boolean?
function Flow:Tick(dt, phase, motion, paused)
    if paused then
        self._wasPaused = true
        blockTrace(self, motion, true)
        return
    end
    if not finite(dt) or dt <= 0 then return end
    if self._clearTrace then clearTrace(self) end
    local count, write = #self.trails, 1
    for index = 1, count do
        local trail = self.trails[index]
        trail.age = trail.age + dt
        if trail.age >= TRAIL_LIFE then self._trailPool:Release(trail)
        else fadeTrail(trail);self.trails[write] = trail;write = write + 1 end
    end
    for index = write, count do self.trails[index] = nil end
    self._sampleAge = self._sampleAge + dt
    if phase ~= "running" or self._wasPaused then blockTrace(self, motion)
    else consumeTrace(self, motion) end
    self._wasPaused = false
    -- 脉冲输入先缓慢消散，公开输出再跟随；解析耦合解不依赖渲染分帧。
    -- 到时只释放已存余势；blockTrace 已阻止结算阶段再注入新脉冲。
    local inputDecay, outputDecay = math.exp(-ACCEL_DECAY * dt), math.exp(-ACCEL_FOLLOW * dt)
    local transfer = ACCEL_FOLLOW * (inputDecay - outputDecay) / (ACCEL_FOLLOW - ACCEL_DECAY)
    self.accelX = self.accelX * outputDecay + self._accelInputX * transfer
    self.accelY = self.accelY * outputDecay + self._accelInputY * transfer
    self._accelInputX, self._accelInputY = self._accelInputX * inputDecay, self._accelInputY * inputDecay
    local targetSpeed, targetVortex = IDLE_SPEED, 0
    local targetX, targetY = 0, 0
    if phase == "running" then
        local boost = intensity(motion)
        targetSpeed = IDLE_SPEED + (SHAKE_SPEED - IDLE_SPEED) * boost
        targetVortex = boost
        if motion then
            local dx, dy = direction(number(motion.vx), number(motion.vy))
            targetX, targetY = dx * boost, dy * boost
        end
    elseif phase == "settle" or phase == "reveal" or phase == "over" then
        -- 到时后残余的瓶子速度不再加速背景，保留一丝缓慢收拢的旋纹。
        targetSpeed, targetVortex = REST_SPEED, REST_VORTEX
    end

    local rate = targetSpeed > self.speed and ATTACK_RATE or RELEASE_RATE
    local decay = math.exp(-rate * dt)
    local difference = self.speed - targetSpeed
    local phaseDelta = targetSpeed * dt + difference * (1 - decay) / rate
    local nextTime = self.time + phaseDelta
    if not finite(nextTime) then return end
    local spinTarget = phase == "running" and self._turn * math.exp(-INPUT_DECAY * self._sampleAge) or 0
    local spinDifference = self.spin - spinTarget
    -- 对 speed(t) * (.2 + 1.6 * spin(t)) 局部解析积分，反转不会乘上漫长旧time。
    local spinIntegral = spinTarget * phaseDelta + spinDifference *
        (targetSpeed * (1 - math.exp(-SPIN_RATE * dt)) / SPIN_RATE
        + difference * (1 - math.exp(-(rate + SPIN_RATE) * dt)) / (rate + SPIN_RATE))
    self.rotation = self.rotation + .2 * phaseDelta + 1.6 * spinIntegral
    self.spin = spinTarget + spinDifference * math.exp(-SPIN_RATE * dt)
    local directionDecay = math.exp(-DIRECTION_RATE * dt)
    self.directionX = targetX + (self.directionX - targetX) * directionDecay
    self.directionY = targetY + (self.directionY - targetY) * directionDecay
    self.time = nextTime
    self.speed = targetSpeed + difference * decay
    local vortexRate = targetVortex > self.vortex and ATTACK_RATE or VORTEX_RELEASE_RATE
    self.vortex = targetVortex + (self.vortex - targetVortex) * math.exp(-vortexRate * dt)
end

return Flow
