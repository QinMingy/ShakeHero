-- 物理二的瓶子运动：手势改变有界目标，固定步跟随；不直接移动瓶内物品。
-- 碰撞仍在静止瓶子的局部坐标中解算，物品只接收 -瓶子速度变化 的惯性冲量。
--      手指向右加速 -> 瓶子向右 -> 内容物相对向左
--      匀速/停在边缘 -> 加速度趋零；换向/刹车 -> 反向惯性
-- 墙体与物品碰撞形状不变，最大位移/速度均有界，避免快速摇晃导致穿瓶。
---@class BottleShakeMotion
---@field targetX number
---@field targetY number
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field holding boolean
---@field sensorBaseX number
---@field sensorBaseY number
---@field sensorX number
---@field sensorY number
---@field sensorReady boolean
local Motion = {}
Motion.__index = Motion

local LIMIT_X, LIMIT_Y = .52, .36 -- 米；限制整瓶摆幅，不跟着手指无限拖走。
local FOLLOW_RATE = 24 -- 临界阻尼响应，松手回中但不产生持续振荡。
local INERTIA_GAIN = 1.8

---@param value number
---@return boolean
local function finite(value)
    -- 部分 Windows Runtime 会把 NaN == NaN 判为 true；用其文本表示排除 NaN。
    -- 保留原有无穷值检查，正常输入的限幅、跟随和惯性计算不变。
    return not tostring(value):lower():find("nan", 1, true) and math.abs(value) < math.huge
end

---@return BottleShakeMotion
function Motion.New()
    local self = setmetatable({}, Motion)
    self:Reset()
    return self
end

function Motion:Reset()
    self.targetX, self.targetY, self.x, self.y, self.vx, self.vy = 0, 0, 0, 0, 0, 0
    self.holding = false
    self:ResetSensor()
end

-- 体感断开或重新校准时只清传感器，不打断触摸拖动和瓶子的回中运动。
function Motion:ResetSensor()
    self.sensorBaseX, self.sensorBaseY, self.sensorX, self.sensorY = 0, 0, 0, 0
    self.sensorReady = false
end

function Motion:Begin()
    -- 再次抓住尚未回中的瓶子时保留当前位置/速度，避免视觉瞬移和惯性丢失。
    self.targetX, self.targetY = self.x, self.y
    self.holding = true
end

---@param dx number 米，向右为正。
---@param dy number 米，向上为正。
function Motion:Move(dx, dy)
    if not self.holding or not finite(dx) or not finite(dy) then return end
    -- 每帧累积目标位移，不按事件次数加力，也不逐事件限幅造成采样率差异。
    self.targetX = math.max(-LIMIT_X, math.min(LIMIT_X, self.targetX + dx))
    self.targetY = math.max(-LIMIT_Y, math.min(LIMIT_Y, self.targetY + dy))
end

function Motion:End()
    self.holding = false
    self.targetX, self.targetY = 0, 0
end

---@param position number
---@param velocity number
---@param target number
---@param dt number
---@return number position
---@return number velocity
local function follow(position, velocity, target, dt)
    -- 临界阻尼弹簧解析解，避免欧拉积分在低帧率/大 dt 时抖动或爆炸。
    local error = position - target
    local c = velocity + FOLLOW_RATE * error
    local decay = math.exp(-FOLLOW_RATE * dt)
    return target + (error + c * dt) * decay,
        (velocity - FOLLOW_RATE * c * dt) * decay
end

---@param dt number
---@return number dvx 惯性速度增量（米/秒）。
---@return number dvy
function Motion:Step(dt)
    if not finite(dt) or dt <= 0 then return 0, 0 end
    local x, vx = follow(self.x, self.vx, self.targetX, dt)
    local y, vy = follow(self.y, self.vy, self.targetY, dt)
    local dvx, dvy = -(vx - self.vx) * INERTIA_GAIN, -(vy - self.vy) * INERTIA_GAIN
    self.x, self.y, self.vx, self.vy = x, y, vx, vy
    return dvx, dvy
end

---@param ax number 设备轴向已转换为瓶子坐标，单位为 g。
---@param ay number
---@param dt number
function Motion:Sensor(ax, ay, dt)
    if not finite(ax) or not finite(ay) or not finite(dt) or dt <= 0 then return end
    if not self.sensorReady then
        self.sensorBaseX, self.sensorBaseY = ax, ay
        self.sensorReady = true
        return
    end
    -- 去掉静态重力/倾斜，滤掉手抖；加速度计本来就是加速度，不再二次差分。
    local baseline = 1 - math.exp(-dt / .18)
    self.sensorBaseX = self.sensorBaseX + (ax - self.sensorBaseX) * baseline
    self.sensorBaseY = self.sensorBaseY + (ay - self.sensorBaseY) * baseline
    local smoothing = 1 - math.exp(-dt / .035)
    self.sensorX = self.sensorX + (ax - self.sensorBaseX - self.sensorX) * smoothing
    self.sensorY = self.sensorY + (ay - self.sensorBaseY - self.sensorY) * smoothing
end

---@param dt number
---@return number dvx
---@return number dvy
function Motion:SensorImpulse(dt)
    local ax, ay = self.sensorX, self.sensorY
    local length = math.sqrt(ax * ax + ay * ay)
    if length <= .035 then return 0, 0 end
    local gain = math.min(1, .9 / length) * 9.81 * 2
    return -ax * gain * dt, -ay * gain * dt
end

return Motion
