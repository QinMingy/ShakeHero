-- 独立入口 require("Machine.ScreenFlowTests").Run()，不创建引擎对象、不读存档。
local Flow = require("Machine.ScreenFlow")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}

---@param name string
---@param run fun()
local function case(name, run)
    cases[#cases + 1] = {name = name, run = run}
end

---@param actual number
---@param expected number
---@param tolerance number?
local function close(actual, expected, tolerance)
    assert(math.abs(actual - expected) <= (tolerance or 1e-10),
        "expected=" .. expected .. " actual=" .. actual)
end

---@param flow MachineScreenFlow
---@param phase string
---@param seconds number
---@param hz integer
---@param motion MachineScreenFlowMotion?
local function advance(flow, phase, seconds, hz, motion)
    for _ = 1, math.floor(seconds * hz + .5) do flow:Tick(1 / hz, phase, motion) end
end

case("idle/reset are independent per instance", function()
    local flow, other = Flow.New(), Flow.New()
    advance(flow, "prepare", 2, 60)
    close(flow.speed, .12);close(flow.vortex, 0);close(flow.time, .24)
    close(other.time, 0)
    flow:Tick(1, "running", {vx = 8, vy = 0})
    flow:Reset()
    close(flow.time, 0);close(flow.speed, .12);close(flow.vortex, 0)
end)

case("holding still and the continuous dead zone remain calm", function()
    for _, motion in ipairs({{vx = 0, vy = 0, holding = true},
        {vx = .08, vy = 0}, {vx = .03, vy = .04}, {}}) do
        local flow = Flow.New()
        flow:Tick(2, "running", motion)
        close(flow.speed, .12);close(flow.vortex, 0);close(flow.time, .24)
    end
    local flow = Flow.New()
    flow:Tick(2, "running")
    close(flow.speed, .12);close(flow.vortex, 0)
end)

case("crossing the dead zone has no intensity jump", function()
    local flow = Flow.New()
    flow:Tick(2, "running", {vx = .080001, vy = 0})
    assert(flow.speed > .12 and flow.speed < .120001)
    assert(flow.vortex > 0 and flow.vortex < .000001)
end)

case("shake intensity uses vector speed regardless of direction", function()
    local axis, diagonal, negative = Flow.New(), Flow.New(), Flow.New()
    axis:Tick(.4, "running", {vx = 1, vy = 0})
    diagonal:Tick(.4, "running", {vx = .6, vy = .8})
    negative:Tick(.4, "running", {vx = -.6, vy = -.8})
    close(axis.speed, diagonal.speed);close(axis.time, diagonal.time)
    close(axis.vortex, negative.vortex);close(axis.time, negative.time)
end)

case("shake builds with inertia without overshoot or phase teleport", function()
    local flow = Flow.New()
    flow:Tick(.25, "running", {vx = 4, vy = 0})
    assert(flow.speed > .5 and flow.speed < .7)
    assert(flow.vortex > .4 and flow.vortex < .6)
    assert(flow.time > .12 * .25 and flow.time < flow.speed * .25)
    advance(flow, "running", 8, 60, {vx = 1e300, vy = -1e300})
    assert(flow.speed <= 1.2 and flow.vortex <= 1)
    close(flow.speed, 1.2, 1e-8);close(flow.vortex, 1, 1e-8)
end)

case("timer expiry decelerates despite residual bottle motion", function()
    local flow = Flow.New()
    flow:Tick(4, "running", {vx = 4, vy = 0})
    local previousTime, previousSpeed, previousVortex = flow.time, flow.speed, flow.vortex
    flow:Tick(1 / 60, "settle", {vx = 4, vy = 0})
    assert(flow.time > previousTime and flow.time - previousTime < previousSpeed / 60)
    assert(flow.speed < previousSpeed and flow.speed > .025)
    assert(flow.vortex < previousVortex and flow.vortex > .15)
    for _ = 1, 119 do
        local oldSpeed, oldVortex = flow.speed, flow.vortex
        flow:Tick(1 / 60, "settle", {vx = 4, vy = -4})
        assert(flow.speed <= oldSpeed and flow.vortex <= oldVortex)
    end
    assert(flow.speed < .05 and flow.vortex < .19)
end)

case("settle/reveal/over all ignore stale input and approach rest", function()
    for _, phase in ipairs({"settle", "reveal", "over"}) do
        local moving, still = Flow.New(), Flow.New()
        moving:Tick(3, phase, {vx = 1e300, vy = -1e300})
        still:Tick(3, phase)
        close(moving.time, still.time);close(moving.speed, still.speed)
        close(moving.vortex, still.vortex)
        assert(moving.speed < .026 and moving.vortex > .149)
    end
end)

case("prepare/draft return to idle without resetting phase", function()
    for _, phase in ipairs({"prepare", "draft"}) do
        local flow = Flow.New()
        flow:Tick(2, "running", {vx = 4, vy = 0})
        local previous = flow.time
        flow:Tick(8, phase, {vx = 4, vy = 0})
        assert(flow.time > previous)
        close(flow.speed, .12, 1e-6);close(flow.vortex, 0, 1e-5)
    end
end)

case("pause freezes and resumes without accumulating wall time", function()
    local paused, reference = Flow.New(), Flow.New()
    paused:Tick(.3, "running", {vx = 4, vy = 0})
    reference:Tick(.3, "running", {vx = 4, vy = 0})
    paused:Tick(30, "settle", nil, true)
    close(paused.time, reference.time);close(paused.speed, reference.speed)
    close(paused.vortex, reference.vortex)
    paused:Tick(.1, "settle");reference:Tick(.1, "settle")
    close(paused.time, reference.time);close(paused.speed, reference.speed)
    close(paused.vortex, reference.vortex)
end)

case("nonpositive/nonfinite dt cannot poison state", function()
    local flow = Flow.New()
    flow:Tick(.3, "running", {vx = 4, vy = 0})
    local time, speed, vortex = flow.time, flow.speed, flow.vortex
    for _, dt in ipairs({0, -1, 0 / 0, math.huge, -math.huge}) do
        flow:Tick(dt, "running", {vx = 4, vy = 0})
        close(flow.time, time);close(flow.speed, speed);close(flow.vortex, vortex)
    end
    flow:Tick(.1, "running", {vx = 0 / 0, vy = math.huge})
    assert(flow.time > time and flow.speed < speed and flow.vortex < vortex)
end)

case("exact phase integration matches 30/60/120 Hz", function()
    local reference = Flow.New()
    ---@type {phase:string,seconds:number}[]
    local segments = {{phase = "prepare", seconds = 1}, {phase = "running", seconds = 1.5},
        {phase = "running", seconds = .5}, {phase = "settle", seconds = 2},
        {phase = "reveal", seconds = 1}, {phase = "draft", seconds = 1}}
    for _, segment in ipairs(segments) do
        reference:Tick(segment.seconds, segment.phase,
            segment.phase == "running" and {vx = 3, vy = 0} or nil)
    end
    for _, hz in ipairs({30, 60, 120}) do
        local flow = Flow.New()
        advance(flow, "prepare", 1, hz)
        advance(flow, "running", 2, hz, {vx = 3, vy = 0})
        advance(flow, "settle", 2, hz)
        advance(flow, "reveal", 1, hz)
        advance(flow, "draft", 1, hz)
        close(flow.time, reference.time);close(flow.speed, reference.speed)
        close(flow.vortex, reference.vortex)
    end
end)

case("effect never writes input or consumes randomness", function()
    local backing = {vx = .6, vy = -.8, holding = true, x = .1, y = .2}
    local motion = setmetatable({}, {__index = backing, __newindex = function()
        error("effect wrote the bottle motion")
    end})
    local random = math.random
    math.random = function() error("effect consumed shared randomness") end
    local ok, message = pcall(function()
        local flow = Flow.New()
        flow:Tick(.2, "running", motion)
        flow:Tick(.5, "settle", motion)
    end)
    math.random = random
    assert(ok, message)
    assert(next(motion) == nil and backing.vx == .6 and backing.vy == -.8)
end)

---@param serial number
---@param time number
---@param vx number
---@param vy number
---@param ax number?
---@param ay number?
---@param turn number?
---@return MachineScreenFlowSample
local function sample(serial, time, vx, vy, ax, ay, turn)
    return {serial = serial, time = time, x = .1, y = .15, vx = vx, vy = vy,
        ax = ax or 0, ay = ay or 0, turn = turn or 0}
end

---@param point MachineScreenFlowSample
---@return MachineScreenFlowMotion
local function traced(point)
    return {vx = point.vx, vy = point.vy, trace = {generation = 1, serial = point.serial,
        time = point.time, latest = point, points = {point}}}
end

---@param motion MachineScreenFlowMotion
---@param point MachineScreenFlowSample
---@param savePoint boolean?
local function record(motion, point, savePoint)
    local trace = assert(motion.trace)
    motion.vx, motion.vy = point.vx, point.vy
    trace.serial, trace.time, trace.latest = point.serial, point.time, point
    if savePoint then
        if #trace.points >= 6 then table.remove(trace.points, 1) end
        trace.points[#trace.points + 1] = point
    end
end

case("direction preserves world axis signs and weights slow movement", function()
    local right, left, up, down = Flow.New(), Flow.New(), Flow.New(), Flow.New()
    right:Tick(1, "running", {vx = 2.2, vy = 0})
    left:Tick(1, "running", {vx = -2.2, vy = 0})
    up:Tick(1, "running", {vx = 0, vy = 2.2})
    down:Tick(1, "running", {vx = 0, vy = -2.2})
    assert(right.directionX > .9 and left.directionX < -.9)
    assert(up.directionY > .9 and down.directionY < -.9)
    close(right.directionX, -left.directionX);close(up.directionY, -down.directionY)
    local slow = Flow.New()
    slow:Tick(1, "running", {vx = .1, vy = 0})
    assert(slow.directionX > 0 and slow.directionX < .02)
end)

case("fixed-step acceleration preserves axes and saturates safely", function()
    local flow = Flow.New()
    flow:Tick(.1, "running", traced(sample(1, .1, 2, 0, 30, -30)))
    assert(flow.accelX > .2 and flow.accelX < .4)
    close(flow.accelX, -flow.accelY)
    local motion = traced(sample(2, .2, 2, 0, -1e300, 1e300))
    flow:Tick(.1, "running", motion)
    assert(flow.accelX < 0 and flow.accelX > -.4)
    close(flow.accelX, -flow.accelY)
end)

case("the same serial cannot reinject acceleration or duplicate trails", function()
    local flow = Flow.New()
    local motion = traced(sample(1, .1, 2, 0, 30, 0, .7))
    flow:Tick(.1, "running", motion)
    local count = #flow.trails
    for _ = 1, 12 do flow:Tick(1 / 60, "running", motion) end
    assert(#flow.trails == count and flow.accelX < .43)
    local reference = Flow.New()
    reference:Tick(.3, "running", motion)
    close(flow.accelX, reference.accelX)
    assert(flow.trails[1].age > .19)
end)

case("a sharp reversal brakes before changing the buffered impulse direction", function()
    local flow = Flow.New()
    local motion = traced(sample(1, .1, 2.2, 0, 30, 0))
    for step = 1, 60 do
        record(motion, sample(step, step / 60, 2.2, 0, 30, 0))
        flow:Tick(1 / 60, "running", motion)
    end
    local previous = flow.accelX
    record(motion, sample(61, 61 / 60, -2.2, 0, -30, 0), true)
    flow:Tick(1 / 60, "running", motion)
    assert(flow.accelX > 0 and flow.accelX < previous)
    for step = 62, 100 do
        record(motion, sample(step, step / 60, -2.2, 0, -30, 0))
        flow:Tick(1 / 60, "running", motion)
    end
    assert(flow.accelX < -.5 and flow.accelX > -1)
end)

case("opposite circles produce opposite spin and signed rotation", function()
    local clockwise, counter = Flow.New(), Flow.New()
    local a, b = traced(sample(0, 0, 2.2, 0)), traced(sample(0, 0, 2.2, 0))
    for step = 1, 120 do
        record(a, sample(step, step / 60, 2.2, 0, 0, 0, .8), step % 5 == 0)
        record(b, sample(step, step / 60, 2.2, 0, 0, 0, -.8), step % 5 == 0)
        clockwise:Tick(1 / 60, "running", a);counter:Tick(1 / 60, "running", b)
    end
    assert(clockwise.spin > .79 and counter.spin < -.79)
    close(clockwise.spin, -counter.spin)
    assert(clockwise.rotation > 1 and counter.rotation < -1)
end)

case("rotation reversal remains local after a long idle", function()
    local flow = Flow.New()
    flow:Tick(600, "prepare")
    local previous = flow.rotation
    flow:Tick(1 / 60, "running", traced(sample(1, .1, 2.2, 0, 0, 0, -1)))
    assert(math.abs(flow.rotation - previous) < .04)
    assert(flow.time > 72 and flow.rotation > 14)
end)

case("trail coordinates use bounded UV and flip velocity Y once", function()
    local point = sample(1, .1, 1, 1)
    point.x, point.y = .52, .36
    local flow = Flow.New()
    flow:Tick(.1, "running", traced(point))
    assert(#flow.trails == 1)
    local trail = flow.trails[1]
    close(trail.x, .72);close(trail.y, .28)
    assert(trail.dx > 0 and trail.dy < 0 and trail.strength > 0 and trail.weight == 0)
    point = sample(2, .2, -1, -1)
    point.x, point.y = -100, -100
    local other = Flow.New()
    other:Tick(.1, "running", traced(point))
    close(other.trails[1].x, .28);close(other.trails[1].y, .72)
    assert(other.trails[1].dx < 0 and other.trails[1].dy > 0)
end)

case("missed render frames consume retained points once within a six-trail budget", function()
    local motion = traced(sample(0, 0, 2.2, 0))
    for step = 1, 10 do record(motion, sample(step, step * .08, 2.2, 0, 8, 0), true) end
    local flow = Flow.New()
    flow:Tick(1 / 60, "running", motion)
    assert(#flow.trails >= 2 and #flow.trails <= 6)
    local count = #flow.trails
    local firstX, age = flow.trails[1].x, flow.trails[1].age
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == count and flow.trails[1].x == firstX and flow.trails[1].age > age)
    flow:Tick(1, "running", motion)
    assert(#flow.trails == 0)
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == 0)
end)

case("paused trace updates are discarded while public state freezes", function()
    local motion = traced(sample(1, .1, 2.2, 0, 30, 0, .7))
    local flow = Flow.New()
    flow:Tick(.1, "running", motion)
    local age, accel, spin, rotation = flow.trails[1].age, flow.accelX, flow.spin, flow.rotation
    record(motion, sample(2, .2, -2.2, 0, -30, 0, -.7), true)
    flow:Tick(10, "running", motion, true)
    close(flow.trails[1].age, age);close(flow.accelX, accel)
    close(flow.spin, spin);close(flow.rotation, rotation)
    -- 恢复首帧也同步游标，不能补播最后一个暂停采样。
    record(motion, sample(3, .3, -2.2, 0, -30, 0, -.7), true)
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == 1 and flow.accelX > 0)
    record(motion, sample(4, .4, -2.2, 0, -30, 0, -.7), true)
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == 2 and flow.accelX < 0)
end)

case("expiry discards new input and cannot replay it on a later running phase", function()
    local motion = traced(sample(1, .1, 2.2, 0, 30, 0, .7))
    local flow = Flow.New()
    flow:Tick(.1, "running", motion)
    record(motion, sample(2, 1.6, -2.2, 0, -30, 0, -.7), true)
    flow:Tick(1.5, "settle", motion)
    assert(#flow.trails == 0 and flow.accelX > 0 and flow.accelX < .06)
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == 0 and flow.accelX >= 0)
    assert(math.abs(flow.spin) < .01)
end)

case("generation changes clear old feedback without resetting texture phases", function()
    local motion = traced(sample(80, 4, 2.2, 0, 30, 0, 1))
    local flow = Flow.New()
    flow:Tick(.2, "running", motion)
    local previousTime, previousRotation = flow.time, flow.rotation
    local trace = assert(motion.trace)
    trace.generation = 2
    local point = sample(1, .01, 0, 0)
    trace.points = {point};record(motion, point)
    flow:Tick(.1, "running", motion)
    assert(#flow.trails == 0)
    close(flow.accelX, 0);close(flow.accelY, 0);close(flow.spin, 0)
    close(flow.directionX, 0);close(flow.directionY, 0)
    assert(flow.time > previousTime and flow.rotation > previousRotation)
    flow:Reset()
    close(flow.time, 0);close(flow.rotation, 0);close(flow.directionX, 0)
    close(flow.accelX, 0);close(flow.spin, 0);assert(#flow.trails == 0)
end)

---@param hz integer
---@return MachineScreenFlow
local function replay(hz)
    local flow = Flow.New()
    local motion = traced(sample(0, 0, 2.2, 0))
    local step = 0
    for frame = 1, hz * 2 do
        local endpoint = math.floor(frame * 60 / hz + .000001)
        for nextStep = step + 1, endpoint do
            local t = nextStep / 60
            local point = sample(nextStep, t, 2.2 * math.cos(t), 2.2 * math.sin(t),
                -2.2 * math.sin(t), 2.2 * math.cos(t), .7)
            point.x, point.y = .2 * math.cos(t), .2 * math.sin(t)
            record(motion, point, nextStep % 5 == 0)
        end
        step = endpoint
        flow:Tick(1 / hz, "running", motion)
    end
    return flow
end

case("fixed-step input remains close across render frequencies", function()
    local reference = replay(60)
    for _, hz in ipairs({30, 120}) do
        local flow = replay(hz)
        close(flow.speed, reference.speed);close(flow.time, reference.time)
        close(flow.directionX, reference.directionX, .02)
        close(flow.directionY, reference.directionY, .02)
        close(flow.accelX, reference.accelX, .01);close(flow.accelY, reference.accelY, .01)
        close(flow.spin, reference.spin, .025);close(flow.rotation, reference.rotation, .06)
        assert(#flow.trails == #reference.trails and #flow.trails <= 6)
        for index, trail in ipairs(flow.trails) do
            close(trail.x, reference.trails[index].x);close(trail.y, reference.trails[index].y)
            close(trail.weight, reference.trails[index].weight, .025)
        end
    end
end)

case("nested trace data are read-only and rendering never differentiates velocity", function()
    local point = sample(1, .1, 2.2, 0)
    local source = traced(point)
    ---@param value any
    ---@return any
    local function readonly(value)
        if type(value) ~= "table" then return value end
        return setmetatable({}, {__index = function(_, key) return readonly(value[key]) end,
            __newindex = function() error("effect mutated nested trace input") end})
    end
    local flow = Flow.New()
    -- 只给velocity跳变，固定步trace.ax仍为0，不能通过渲染帧差分制造冲量。
    flow:Tick(.1, "running", readonly(source))
    close(flow.accelX, 0);close(flow.accelY, 0)
    source.vx = -2.2
    flow:Tick(.1, "running", readonly(source))
    close(flow.accelX, 0);close(flow.accelY, 0)
    assert(point.vx == 2.2 and point.ax == 0 and point.serial == 1)
end)

case("a short pulse rises softly and retains visible momentum for about one second", function()
    local flow = Flow.New()
    local motion = traced(sample(1, .01, 0, 0, 30, 0))
    flow:Tick(.01, "running", motion)
    local initial = flow.accelX
    assert(initial > 0 and initial < .05)
    flow:Tick(.29, "running", motion)
    local peak = flow.accelX
    assert(peak > .4 and peak < .45)
    flow:Tick(.5, "running", motion)
    assert(flow.accelX > .15 and flow.accelX < peak)
    flow:Tick(.7, "running", motion)
    assert(flow.accelX > 0 and flow.accelX < .04)
end)

case("pause freezes private input and generation/reset remove stored energy", function()
    local motion = traced(sample(1, .1, 2.2, 0, 30, -20))
    local flow = Flow.New()
    flow:Tick(.1, "running", motion)
    local inputX, inputY = flow._accelInputX, flow._accelInputY
    flow:Tick(5, "running", motion, true)
    close(flow._accelInputX, inputX);close(flow._accelInputY, inputY)
    local trace = assert(motion.trace)
    trace.generation = 2
    local point = sample(1, .01, 0, 0)
    trace.points = {point};record(motion, point)
    flow:Tick(.1, "running", motion)
    close(flow._accelInputX, 0);close(flow._accelInputY, 0)
    close(flow.accelX, 0);close(flow.accelY, 0)
    flow:Reset()
    close(flow._accelInputX, 0);close(flow._accelInputY, 0)
end)

case("expiry releases stored energy without consuming later opposite pulses", function()
    local reference, changed = Flow.New(), Flow.New()
    local a, b = traced(sample(1, .01, 0, 0, 30, 0)), traced(sample(1, .01, 0, 0, 30, 0))
    reference:Tick(.01, "running", a);changed:Tick(.01, "running", b)
    local initial = changed.accelX
    for step = 1, 120 do
        record(b, sample(step + 1, step / 60 + .01, -2.2, 0, -30, 30, -1), step % 5 == 0)
        reference:Tick(1 / 60, "settle", a);changed:Tick(1 / 60, "settle", b)
        close(changed.accelX, reference.accelX);close(changed.accelY, reference.accelY)
        close(changed._accelInputX, reference._accelInputX)
        if step == 6 then assert(changed.accelX > initial) end
    end
    assert(changed.accelX > 0 and changed.accelX < .01)
end)

case("trails fade in softly and leave the six-point budget after fading", function()
    local motion = traced(sample(0, 0, 2.2, 0))
    local flow = Flow.New()
    for step = 1, 30 do
        local oldest = flow.trails[1]
        local oldWeight = oldest and oldest.weight or 0
        record(motion, sample(step, step * .08, 2.2, 0, 30, 0), true)
        flow:Tick(.08, "running", motion)
        assert(#flow.trails <= 6)
        for _, trail in ipairs(flow.trails) do
            assert(trail.weight <= .55 and trail.strength <= .55)
            if trail.age == 0 then close(trail.weight, 0) end
        end
        if oldest and flow.trails[1] ~= oldest then assert(oldWeight < .02) end
    end
end)

case("trail records are reused without changing the active order or reset state", function()
    local flow = Flow.New()
    local motion = traced(sample(0, 0, 2.2, 0))
    local records = {}
    local list = flow.trails
    for step = 1, 300 do
        record(motion, sample(step, step * .16, 2.2, 0, 5, 0), true)
        flow:Tick(.16, "running", motion)
        for index, trail in ipairs(flow.trails) do
            records[trail] = true
            assert(trail.age >= 0 and trail.age < .9)
            if index > 1 then assert(flow.trails[index - 1].age >= trail.age) end
        end
    end
    local count = 0
    for _ in pairs(records) do count = count + 1 end
    assert(count <= 6)
    flow:Reset()
    assert(flow.trails == list and #list == 0)
    record(motion, sample(301, 48.16, -2.2, 0, -5, 0), true)
    flow:Tick(.16, "running", motion)
    assert(#flow.trails <= 6 and flow.accelX < 0)
end)

---@return integer passed
function Tests.Run()
    local passed = 0
    for _, entry in ipairs(cases) do
        local ok, message = pcall(entry.run)
        assert(ok, "Machine.ScreenFlowTests [" .. entry.name .. "] " .. tostring(message))
        passed = passed + 1
    end
    return passed
end

return Tests
