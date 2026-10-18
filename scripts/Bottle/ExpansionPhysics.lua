-- 扩展物品的真实运动适配；只在 Physics 世界解锁的同步/步进屏障调用。
-- 碰撞设计（单位米，+Y向上）：
--   动态物品 [飞盘sensor] -> 二次弧线 -> [目标真实fixture]
--   穿透只取消响应，不取消Begin/End；命中事实只能来自真实接触，终点不伪造邻接。
--   壁虎 [kinematic] |左右/肩/颈壁：锁定位置，reset重建后恢复dynamic。
--   培根 [1]-[2]-[3]-[4]-[5]：强制旋转时五段共同绕第3段中心刚性转动。
-- 边界：飞盘每步预测终点按完整旋转包络留瓶内；失去目标到期仍上报到达让规则接力。
-- 本模块不发规则收益、不改物品实例、不在Contact回调建删或移动原生对象。

---@class BottleFlight
---@field fromX number
---@field fromY number
---@field toX number
---@field toY number
---@field duration number
---@field elapsed number 真实飞行时间，不受加速器倍率影响
---@field progress number 空间弧线进度
---@field endpointAge number 到端点后的真实等待时间
---@field arc number
---@field targetUid number?
---@field endpointWait boolean

---@class BottleExpansionMotion
---@field anchored boolean
---@field flight BottleFlight?
---@field dashRemaining number
---@field dashX number
---@field dashY number
---@field angle number
---@field angularTravel number
---@field rotateOffset number
---@field arrived boolean
---@field hit number?
---@field discVX number
---@field discVY number
---@field idleHold boolean

local Shapes = require("Bottle.Shapes")

---@class BottleExpansionPhysics
---@field states table<number, BottleExpansionMotion>
---@field pending table[]
---@field shakePendingX number
---@field shakePendingY number
---@field inputTouch boolean
---@field inputSensor boolean
---@field shakeCooldown number
---@field shakeStrength number
---@field shakeStrong boolean
local Expansion = {}
Expansion.__index = Expansion
local PI, RAD = math.pi, math.pi / 180
local DISC_SPEED = 3.0
local DASH_SPEED = 4.0

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@return BottleExpansionPhysics
function Expansion.New()
    local self = setmetatable({}, Expansion)
    self:Reset()
    return self
end

function Expansion:Reset()
    self.states, self.pending = {}, {}
    self:ResetShake()
end

function Expansion:ResetShake()
    self.shakePendingX, self.shakePendingY = 0, 0
    self.inputTouch, self.inputSensor = false, false
    self.shakeCooldown, self.shakeStrength = 0, 0
    self.shakeStrong = false
end

---@param touch boolean
---@param sensor boolean
---@param dx number?
---@param dy number?
function Expansion:Input(touch, sensor, dx, dy)
    self.inputTouch = self.inputTouch or touch
    self.inputSensor = self.inputSensor or sensor
    self.shakePendingX = self.shakePendingX + (dx or 0)
    self.shakePendingY = self.shakePendingY + (dy or 0)
end

---只采真实输入产生的dv，不采碰撞、松手回中或无输入的残余运动。
---强摇>=4m/s上升沿输出一次原始幅值，持续输入防抖0.35秒；其他步骤为0。
function Expansion:SampleShake(dt, touchX, touchY, sensorX, sensorY)
    local dx,dy=self.shakePendingX,self.shakePendingY
    if self.inputTouch then dx,dy=dx+touchX,dy+touchY end
    if self.inputSensor then dx,dy=dx+sensorX,dy+sensorY end
    local strength=math.sqrt(dx*dx+dy*dy)
    self.shakeCooldown=math.max(0,self.shakeCooldown-dt)
    local strong=strength>=4
    self.shakeStrength=0
    if strong and not self.shakeStrong and self.shakeCooldown<=0 then
        self.shakeStrength=strength
        self.shakeCooldown=.35
    end
    self.shakeStrong=strong
    self.shakePendingX,self.shakePendingY=0,0
    self.inputTouch,self.inputSensor=false,false
end

---@param uid number
function Expansion:Forget(uid)
    self.states[uid] = nil
end

---@param record BottleBody
---@return BottleExpansionMotion
function Expansion:State(record)
    ---@type BottleExpansionMotion?
    local state = self.states[record.uid]
    if not state then
        state = {anchored = false, dashRemaining = 0, dashX = 0, dashY = 0,
            angle = record.node.rotation2D * RAD, angularTravel = 0, rotateOffset = 0, arrived = false,
            discVX = record.uid % 2 == 0 and -DISC_SPEED or DISC_SPEED, discVY = 0, idleHold = false}
        self.states[record.uid] = state
    end
    return state
end

---@param kind string
---@param ghostPoop boolean?
---@return boolean
function Expansion.IsGhostLike(kind, ghostPoop)
    return kind == "ghost" or (ghostPoop == true and (kind == "poop" or kind == "golden_poop"
        or kind == "diamond_poop" or kind == "rainbow_poop"))
end

---@param kind string
---@param ghostPoop boolean?
---@return boolean
function Expansion.IsSensor(kind, ghostPoop)
    return kind == "discus" or Expansion.IsGhostLike(kind, ghostPoop)
end

---@param record BottleBody
---@return boolean
function Expansion:Controlled(record)
    ---@type BottleExpansionMotion?
    local state = self.states[record.uid]
    return record.sensor or (state ~= nil and state.anchored)
end

---@param event table
function Expansion:Remember(event)
    local kind = event.kind
    if kind == "anchor" or kind == "rotate" or kind == "impulse" or kind == "flight"
        or kind == "teleport" or kind == "dash" then
        -- 复制payload，防止调用者在Sync前复用事件表；回调中只写Lua队列。
        local copy = {}
        for key, value in pairs(event) do copy[key] = value end
        self.pending[#self.pending + 1] = copy
    end
end

---@param record BottleBody
---@param x number
---@param y number
local function moveWhole(record, x, y)
    local center = record.node.position2D
    local dx, dy = x - center.x, y - center.y
    for _, part in ipairs(record.parts) do
        local position = part.node.position2D
        part.node:SetPosition2D(position.x + dx, position.y + dy)
        part.body.linearVelocity = Vector2(0, 0)
        part.body.angularVelocity = 0
        part.body.awake = true
    end
    record.lastX, record.lastY = x, y
end

---@param record BottleBody
---@param delta number
local function rotateWhole(record, delta)
    local center = record.node.position2D
    local cosine, sine = math.cos(delta), math.sin(delta)
    for _, part in ipairs(record.parts) do
        local position, velocity = part.node.position2D, part.body.linearVelocity
        local dx, dy = position.x - center.x, position.y - center.y
        part.node:SetPosition2D(center.x + dx * cosine - dy * sine,
            center.y + dx * sine + dy * cosine)
        part.node.rotation2D = part.node.rotation2D + delta / RAD
        part.body.linearVelocity = Vector2(velocity.x * cosine - velocity.y * sine,
            velocity.x * sine + velocity.y * cosine)
        part.body.awake = true
    end
end

---@param record BottleBody
---@param event table
---@param bodies table<number, BottleBody>
---@return number x
---@return number y
local function direction(record, event, bodies)
    local dx, dy = event.dx, event.dy
    if not finite(dx) or not finite(dy) then
        local target = event.targetUid and bodies[event.targetUid]
        local source = event.sourceUid and bodies[event.sourceUid]
        local other = target or source
        if other then
            local a, b = record.node.position2D, other.node.position2D
            dx, dy = target and b.x - a.x or a.x - b.x, target and b.y - a.y or a.y - b.y
        else
            local angle = (record.uid % 23) * 2.399963229728653
            dx, dy = math.cos(angle), math.sin(angle)
        end
    end
    local length = math.sqrt(dx * dx + dy * dy)
    if length < 1e-8 then return 1, 0 end
    return dx / length, dy / length
end

---@param sim BottlePhysics
---@param event table
function Expansion:Apply(sim, event)
    if event.kind == "rotate" then
        -- 一条rotate只作用于目标uid；全场遍历由规则层产生整批事件，绝不在此二次遍历。
        local record = sim.bodies[event.uid]
        if not record then return end
        local delta = finite(event.delta) and event.delta or -PI * .5
        local state = self:State(record)
        if record.ghostLike then
            record.node.rotation2D = 0
            record.body.angularVelocity = 0
        else
            rotateWhole(record, delta)
            state.rotateOffset = state.rotateOffset + delta
        end
        -- 强制姿态从采样基线排除，不计指南针的自然角路程。
        state.angle = record.node.rotation2D * RAD
        return
    end
    local record = sim.bodies[event.uid]
    if not record then return end
    local state = self:State(record)
    if event.kind == "anchor" then
        if finite(event.x) and finite(event.y) then moveWhole(record, event.x, event.y) end
        state.anchored, state.dashRemaining, state.flight = true, 0, nil
        for _, part in ipairs(record.parts) do
            part.body.linearVelocity = Vector2(0, 0)
            part.body.angularVelocity = 0
            part.body.bodyType = BT_KINEMATIC
        end
    elseif event.kind == "teleport" then
        if not finite(event.x) or not finite(event.y) then return end
        -- 明确的闪现使用精确坐标；不走瓶顶/近源净空搜索，不将跳变计入位移。
        moveWhole(record, event.x, event.y)
        state.flight, state.arrived, state.hit, state.idleHold = nil, false, nil, true
        sim:_ForgetContacts(record.uid)
    elseif event.kind == "impulse" then
        if self:Controlled(record) then return end
        local dx, dy = direction(record, event, sim.bodies)
        local strength = finite(event.strength) and event.strength or 3
        for _, part in ipairs(record.parts) do
            local ix, iy = dx * strength * part.body.mass, dy * strength * part.body.mass
            -- 兼容{x,y}表示真实冲量；dx/dy/strength表示方向与速度增量。
            if finite(event.x) and finite(event.y) and event.dx == nil then ix, iy = event.x, event.y end
            part.body:ApplyLinearImpulseToCenter(Vector2(ix, iy), true)
        end
    elseif event.kind == "flight" and record.kind == "discus" then
        local position = record.node.position2D
        local fromX = finite(event.fromX) and event.fromX or (finite(event.x) and event.x or position.x)
        local fromY = finite(event.fromY) and event.fromY or (finite(event.y) and event.y or position.y)
        local target = event.targetUid and sim.bodies[event.targetUid]
        local targetPosition = target and target.node.position2D
        local toX = finite(event.toX) and event.toX or (targetPosition and targetPosition.x or fromX)
        local toY = finite(event.toY) and event.toY or (targetPosition and targetPosition.y or fromY)
        local distance = math.sqrt((toX - fromX)^2 + (toY - fromY)^2)
        local duration = finite(event.duration) and event.duration > 0 and event.duration
            or math.max(.25, distance / DISC_SPEED)
        moveWhole(record, fromX, fromY)
        state.arrived, state.hit, state.idleHold = false, nil, false
        state.flight = {fromX = fromX, fromY = fromY, toX = toX, toY = toY,
            duration = duration, elapsed = 0, progress = 0, endpointAge = 0,
            arc = math.min(.85, math.max(.18, distance * .22)),
            targetUid = event.targetUid, endpointWait = false}
    elseif event.kind == "dash" and not self:Controlled(record) then
        state.dashX, state.dashY = direction(record, event, sim.bodies)
        state.dashRemaining = finite(event.duration) and math.max(0, math.min(.75, event.duration)) or .35
    end
end

---@param sim BottlePhysics
function Expansion:Flush(sim)
    if sim._updating or sim._flushing then return end
    local pending = self.pending
    self.pending = {}
    for _, event in ipairs(pending) do self:Apply(sim, event) end
end

---@param record BottleBody
---@param dt number
---@param bodies table<number, BottleBody>
---@param clampPoint fun(x:number,y:number,extent:number):number,number
---@param multiplier number? 只加速空间进度，计时dt保持真实固定步长
function Expansion:Before(record, dt, bodies, clampPoint, multiplier)
    local speed = multiplier or 1
    local state = self:State(record)
    if state.anchored then
        record.body.linearVelocity = Vector2(0, 0)
        record.body.angularVelocity = 0
        return
    end
    if record.kind == "discus" then
        local flight = state.flight
        local position = record.node.position2D
        local x, y = position.x, position.y
        if not flight and not state.arrived and not state.idleHold then
            -- 独立生成/分裂的飞盘沿固定私有方向等速直飞；没有幽灵式自主流场。
            -- 运动员flight覆盖此控制，命中/闪回等待时由arrived暂停。
            local rawX, rawY = x + state.discVX * dt * speed, y + state.discVY * dt * speed
            x, y = clampPoint(rawX, rawY, record.envelope)
            if math.abs(x-rawX) > 1e-7 then state.discVX = -state.discVX end
            if math.abs(y-rawY) > 1e-7 then state.discVY = -state.discVY end
        elseif flight and not flight.endpointWait then
            local target = flight.targetUid and bodies[flight.targetUid]
            if target then
                local targetPosition = target.node.position2D
                flight.toX, flight.toY = targetPosition.x, targetPosition.y
            end
            flight.elapsed = flight.elapsed + dt
            flight.progress = math.min(1, flight.progress + dt * speed / flight.duration)
            local t = flight.progress
            -- 二次抛物弧；起终点一致时也有一小段可见弧，不原地瞬移。
            x = flight.fromX + (flight.toX - flight.fromX) * t
            y = flight.fromY + (flight.toY - flight.fromY) * t + 4 * flight.arc * t * (1 - t)
            x, y = clampPoint(x, y, record.envelope)
            if t >= 1 then flight.endpointWait = true end
        end
        record.body.linearVelocity = Vector2((x - position.x) / (dt * speed),
            (y - position.y) / (dt * speed))
        record.body.awake = true
    elseif state.dashRemaining > 0 then
        -- 动态实体短冲刺，不传送、不改成sensor，瓶壁仍由真实CCD阻挡。
        local fraction = math.min(1, state.dashRemaining / dt)
        record.body.linearVelocity = Vector2(state.dashX * DASH_SPEED * fraction,
            state.dashY * DASH_SPEED * fraction)
        record.body.awake = true
        state.dashRemaining = math.max(0, state.dashRemaining - dt)
    end
end

-- 高压生成时Box2D位置求解可能先把重叠物体挤到薄墙外，再发生CCD。
-- 安全兜底只处理真实轮廓已经越界的情况，不用包络逐帧挤压瓶内堆叠。
-- 只整体平移同uid全部段，保持软体相对姿态/关节；绝不伪造wall或pairs。
local function boundaryPoint(x, y)
    local sx, sy = x, y
    if y < -.015 then sy = .006 elseif y > 6.415 then sy = 6.394 end
    local width = y >= 6.05 and 1.15 or math.min(2.4, 2.4 - (2.4-1.15)/.55*(y-5.5))
    if x > width + .015 then sx = width - .006
    elseif x < -width - .015 then sx = -width + .006 end
    return sx-x, sy-y
end

---@param record BottleBody
local function containSolid(record)
    local center = record.node.position2D
    if not record.soft and math.abs(center.x) < 2.4-record.envelope and center.y > record.envelope
        and center.y < 5.5-record.envelope then return end
    local shiftX, shiftY = 0, 0
    for _ = 1, 5 do
        local correctionX, correctionY = 0, 0
        local function point(x,y)
            local dx,dy=boundaryPoint(x+shiftX,y+shiftY)
            if math.abs(dx)>math.abs(correctionX) then correctionX=dx end
            if math.abs(dy)>math.abs(correctionY) then correctionY=dy end
        end
        local function localPoint(part,x,y)
            local position=part.node.position2D
            local angle=part.node.rotation2D*RAD
            local cosine,sine=math.cos(angle),math.sin(angle)
            point(position.x+x*cosine-y*sine,position.y+x*sine+y*cosine)
        end
        if record.soft then
            for _,segment in ipairs(record.soft.segments) do
                for _,sx in ipairs({-1,1}) do
                    for _,sy in ipairs({-1,1}) do
                        localPoint(segment,segment.halfLength*sx,segment.halfWidth*sy)
                    end
                end
            end
        else
            local profile=Shapes.profiles[record.shape]
            if profile then
                for _,polygon in ipairs(profile.polygons or {}) do
                    for i=1,#polygon,2 do
                        local px=(polygon[i]-8)*record.radius/8
                        local py=(8-polygon[i+1])*record.radius/8
                        localPoint(record,record.kind=="slipper_right" and -px or px,py)
                    end
                end
                for _,circle in ipairs(profile.circles or {}) do
                    local angle=record.node.rotation2D*RAD
                    local cosine,sine=math.cos(angle),math.sin(angle)
                    local lx,ly=(circle.x-8)*record.radius/8,(8-circle.y)*record.radius/8
                    local cx,cy=center.x+lx*cosine-ly*sine,center.y+lx*sine+ly*cosine
                    for i=1,16 do
                        local a=i*PI/8
                        point(cx+math.cos(a)*circle.radius*record.radius/8,
                            cy+math.sin(a)*circle.radius*record.radius/8)
                    end
                end
            else
                for i=1,16 do
                    local angle=i*PI/8
                    point(center.x+math.cos(angle)*record.radius,center.y+math.sin(angle)*record.radius)
                end
            end
        end
        shiftX,shiftY=shiftX+correctionX,shiftY+correctionY
        if correctionX==0 and correctionY==0 then break end
    end
    if shiftX==0 and shiftY==0 then return end
    for _,part in ipairs(record.parts) do
        local p,v=part.node.position2D,part.body.linearVelocity
        part.node:SetPosition2D(p.x+shiftX,p.y+shiftY)
        -- 只抵消继续指向瓶外的速度，不给额外反弹能量，保留切向运动。
        part.body.linearVelocity=Vector2(shiftX*v.x<0 and 0 or v.x,shiftY*v.y<0 and 0 or v.y)
        part.body.awake=true
    end
end

---@param sim BottlePhysics
---@param dt number
function Expansion:After(sim, dt)
    for uid, record in pairs(sim.bodies) do
        if not record.sensor then containSolid(record) end
        local state = self:State(record)
        local angle = record.node.rotation2D * RAD
        local delta = (angle - state.angle + PI) % (2 * PI) - PI
        state.angularTravel = state.angularTravel + math.abs(delta)
        state.angle = angle
        local flight = state.flight
        if flight then
            -- 遍历真实接触计数，绝不用到终点的几何距离冒充Box2D触碰。
            for _, pair in pairs(sim._pairs) do
                if pair.count > 0 and ((pair.a == uid and pair.b == flight.targetUid)
                    or (pair.b == uid and pair.a == flight.targetUid)) then state.hit = flight.targetUid end
            end
            if state.hit or (flight.endpointWait and flight.endpointAge >= dt * .5) then
                state.arrived, state.flight = true, nil
                record.body.linearVelocity = Vector2(0, 0)
            elseif flight.endpointWait then
                -- Box2D在下一次步进更新新位置的sensor接触，因此终点等待一拍再兜底。
                flight.endpointAge = flight.endpointAge + dt
            end
        end
    end
end

---@class BottleAcceleratedPart
---@field body RigidBody2D
---@field gravity number

---加速只改变本步真实移动积分，dt/冷却/强摇/角速度均不变。
---v'=m*v、g'=m*g使自由飞行位移严格为原来的m倍；步后v'/m回到基准，
---下一步不会再把上一帧倍率累乘。碰撞/关节响应在同一真实Box2D步中完成。
---@param sim BottlePhysics
---@return BottleAcceleratedPart[]
function Expansion:BeginSpeed(sim)
    ---@type BottleAcceleratedPart[]
    local saved = {}
    local multiplier = sim.speedMultiplier
    if multiplier == 1 then return saved end
    for _, record in pairs(sim.bodies) do
        local state = self:State(record)
        if not state.anchored then
            for _, part in ipairs(record.parts) do
                local body = part.body
                if body.bodyType == BT_DYNAMIC then
                    local velocity = body.linearVelocity
                    saved[#saved + 1] = {body = body, gravity = body.gravityScale}
                    body.linearVelocity = Vector2(velocity.x * multiplier, velocity.y * multiplier)
                    body.gravityScale = body.gravityScale * multiplier
                end
            end
        end
    end
    return saved
end

---@param saved BottleAcceleratedPart[]
---@param multiplier number
function Expansion:EndSpeed(saved, multiplier)
    for _, entry in ipairs(saved) do
        local velocity = entry.body.linearVelocity
        entry.body.linearVelocity = Vector2(velocity.x / multiplier, velocity.y / multiplier)
        entry.body.gravityScale = entry.gravity
    end
end

---@param sim BottlePhysics
---@param result BottlePhysicsContacts
function Expansion:Contacts(sim, result)
    result.shakeStrength = self.shakeStrength
    result.angles, result.rotateOffsets, result.angularTravel = {}, {}, {}
    result.flightArrived, result.flightHits = {}, {}
    for uid, record in pairs(sim.bodies) do
        local state = self:State(record)
        result.angles[uid] = record.node.rotation2D * RAD
        result.rotateOffsets[uid] = state.rotateOffset
        result.angularTravel[uid] = state.angularTravel
        if state.arrived then result.flightArrived[uid] = true end
        if state.hit then result.flightHits[uid] = state.hit end
    end
end

return Expansion
