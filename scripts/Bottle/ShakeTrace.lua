-- Fixed-step presentation samples only. Never feeds back into shake integration.
local RecordPool = require("Bottle.RecordPool")
---@class BottleShakeTracePoint
---@field serial number
---@field time number
---@field x number Metres, bottle-local +Y up.
---@field y number
---@field vx number Metres per second.
---@field vy number
---@field ax number Smoothed metres per second squared, limited to +/-30.
---@field ay number
---@field turn number Smoothed signed direction cross per second, limited to +/-1.

---@class BottleShakeTrace
---@field generation number Reset identity within this trace instance.
---@field serial number Advances once per accepted fixed step.
---@field time number Accepted fixed-step time only.
---@field latest BottleShakeTracePoint?
---@field points BottleShakeTracePoint[] Oldest first; at most six samples.
---@field previousVx number
---@field previousVy number
---@field hasBaseline boolean
---@field pointElapsed number
---@field accelerationX number
---@field accelerationY number
---@field turning number
---@field _pointPool any Private RecordPool; retained snapshots own their lease.
---@field _latestInHistory boolean
local Trace = {}
Trace.__index = Trace

local POINT_INTERVAL, POINT_LIMIT = .08, 6
local MIN_SPEED, MAX_ACCELERATION = .08, 30
local ACCELERATION_TAU, TURN_TAU = .045, .07

---@param value number
---@return boolean
local function finite(value)
    return type(value) == "number" and not tostring(value):lower():find("nan", 1, true)
        and math.abs(value) < math.huge
end

---@param value number
---@param limit number
---@return number
local function clamp(value, limit)
    return math.max(-limit, math.min(limit, value))
end

-- Scale first so very large finite velocities cannot overflow normalization.
---@param vx number
---@param vy number
---@return number x
---@return number y
---@return boolean moving
local function direction(vx, vy)
    local scale = math.max(math.abs(vx), math.abs(vy))
    if scale == 0 then return 0, 0, false end
    local x, y = vx / scale, vy / scale
    local length = math.sqrt(x * x + y * y)
    if scale < MIN_SPEED / length then return 0, 0, false end
    return x / length, y / length, true
end

---@return BottleShakeTrace
function Trace.New()
    local self = setmetatable({generation = 0, points = {}, _pointPool = RecordPool.New(8)}, Trace)
    self:Reset()
    return self
end

function Trace:Reset()
    if self.latest and not self._latestInHistory then self._pointPool:Release(self.latest) end
    self._pointPool:ClearActive(self.points)
    self.generation = self.generation + 1
    self.serial, self.time = 0, 0
    self.latest, self._latestInHistory = nil, false
    self.previousVx, self.previousVy = 0, 0
    self.hasBaseline, self.pointElapsed = false, 0
    self.accelerationX, self.accelerationY, self.turning = 0, 0, 0
end

---@param dt number
---@param x number
---@param y number
---@param vx number
---@param vy number
---@return boolean accepted
function Trace:Sample(dt, x, y, vx, vy)
    if not finite(dt) or dt <= 0 or not finite(x) or not finite(y)
        or not finite(vx) or not finite(vy) then return false end
    local nextTime = self.time + dt
    if not finite(nextTime) then return false end
    local first = not self.hasBaseline
    if not first then
        local accelerationBlend = 1 - math.exp(-dt / ACCELERATION_TAU)
        local ax = clamp((vx - self.previousVx) / dt, MAX_ACCELERATION)
        local ay = clamp((vy - self.previousVy) / dt, MAX_ACCELERATION)
        self.accelerationX = clamp(self.accelerationX + (ax - self.accelerationX)
            * accelerationBlend, MAX_ACCELERATION)
        self.accelerationY = clamp(self.accelerationY + (ay - self.accelerationY)
            * accelerationBlend, MAX_ACCELERATION)

        local previousX, previousY, wasMoving = direction(self.previousVx, self.previousVy)
        local currentX, currentY, moving = direction(vx, vy)
        local turn = 0
        -- A near-180-degree reversal is a stroke, not evidence of an orbit.
        if wasMoving and moving and previousX * currentX + previousY * currentY > 0 then
            turn = clamp((previousX * currentY - previousY * currentX) / dt, 1)
        end
        local turnBlend = 1 - math.exp(-dt / TURN_TAU)
        self.turning = clamp(self.turning + (turn - self.turning) * turnBlend, 1)
    end
    self.serial, self.time = self.serial + 1, nextTime
    self.previousVx, self.previousVy, self.hasBaseline = vx, vy, true
    -- The latest step and six retained snapshots have distinct ownership. A latest
    -- record is reusable only after it is no longer also a history snapshot.
    if self.latest and not self._latestInHistory then self._pointPool:Release(self.latest) end
    local point = self._pointPool:Acquire()
    point.serial, point.time, point.x, point.y = self.serial, self.time, x, y
    point.vx, point.vy = vx, vy
    point.ax, point.ay, point.turn = self.accelerationX, self.accelerationY, self.turning
    self.latest = point
    self._latestInHistory = false
    self.pointElapsed = self.pointElapsed + dt
    if first or self.pointElapsed + 1e-9 >= POINT_INTERVAL then
        if #self.points >= POINT_LIMIT then
            local oldest = self.points[1]
            for i = 2, #self.points do self.points[i - 1] = self.points[i] end
            self.points[#self.points] = nil
            self._pointPool:Release(oldest)
        end
        self.points[#self.points + 1] = point
        self._latestInHistory = true
        local remainder = self.pointElapsed % POINT_INTERVAL
        -- A tolerant boundary must also consume the interval; modulo alone can
        -- otherwise retain .079999... and emit a second point one step later.
        self.pointElapsed = (first or remainder > POINT_INTERVAL - 1e-9) and 0 or remainder
    end
    return true
end

return Trace
