local Trace = require("Bottle.ShakeTrace")
local Motion = require("Bottle.ShakeMotion")
local Tests = {}
local cases = {}

---@param name string
---@param run fun()
local function test(name, run) cases[#cases + 1] = {name = name, run = run} end
local function close(a, b, tolerance)
    assert(math.abs(a - b) <= (tolerance or 1e-8), tostring(a) .. " ~= " .. tostring(b))
end

test("first moving sample establishes a baseline without artificial force", function()
    local trace = Trace.New()
    assert(trace:Sample(1 / 120, .2, -.1, 4, -3))
    local point = assert(trace.latest)
    assert(point.serial == 1 and #trace.points == 1)
    assert(point.x == .2 and point.y == -.1 and point.vx == 4 and point.vy == -3)
    assert(point.ax == 0 and point.ay == 0 and point.turn == 0)
    close(point.time, 1 / 120)
end)

test("constant velocity remains force-free and acceleration follows fixed-step changes", function()
    local trace = Trace.New()
    for i = 1, 30 do trace:Sample(.02, i * .02, 0, 1, 0) end
    assert(trace.latest.ax == 0 and trace.latest.ay == 0 and trace.latest.turn == 0)
    for i = 1, 40 do trace:Sample(.02, i * .02, 0, 1 + i * .2, -i * .1) end
    close(trace.latest.ax, 10, 1e-5)
    close(trace.latest.ay, -5, 1e-5)
end)

test("jerks are smoothed and limited for either sign", function()
    local trace = Trace.New()
    trace:Sample(.01, 0, 0, 0, 0)
    trace:Sample(.01, 0, 0, 100, -100)
    assert(trace.latest.ax > 0 and trace.latest.ax < 30)
    assert(trace.latest.ay < 0 and trace.latest.ay > -30)
    for i = 1, 80 do trace:Sample(.01, 0, 0, 100 + i * 100, -100 - i * 100) end
    assert(trace.latest.ax <= 30 and trace.latest.ay >= -30)
    close(trace.latest.ax, 30, 1e-5)
    close(trace.latest.ay, -30, 1e-5)
end)

test("clockwise and counter-clockwise strokes preserve their turn sign", function()
    for _, sign in ipairs({-1, 1}) do
        local trace = Trace.New()
        for i = 0, 180 do
            local angle = sign * i / 120
            trace:Sample(1 / 120, .2 * math.sin(angle), -.2 * math.cos(angle),
                math.cos(angle), math.sin(angle))
        end
        assert(sign * trace.latest.turn > .95 and math.abs(trace.latest.turn) <= 1)
    end
end)

test("linear reversals and sub-threshold jitter never invent an orbit", function()
    local trace = Trace.New()
    for i = 1, 100 do
        local sign = i % 2 == 0 and 1 or -1
        trace:Sample(.01, sign * .3, 0, sign * 2, .0001)
    end
    assert(trace.latest.turn == 0)
    trace:Reset()
    for i = 1, 100 do
        trace:Sample(.01, 0, 0, .03 * math.cos(i), .03 * math.sin(i))
    end
    assert(trace.latest.turn == 0)
    -- A real orbit stops adding turn when it slows below the threshold.
    trace:Sample(.02, 0, 0, 1, 0)
    trace:Sample(.02, 0, 0, .98, .2)
    local turn = trace.latest.turn
    assert(turn > 0)
    for _ = 1, 40 do trace:Sample(.02, 0, 0, 0, 0) end
    assert(trace.latest.turn >= 0 and trace.latest.turn < turn * .001)
end)

test("history has bounded chronological snapshots at about 80 milliseconds", function()
    local trace = Trace.New()
    for i = 1, 120 do trace:Sample(1 / 120, i / 120, 0, 1, 0) end
    assert(trace.serial == 120 and #trace.points == 6)
    close(trace.time, 1)
    local previous = trace.points[1]
    for i = 2, #trace.points do
        local point = trace.points[i]
        assert(point.serial > previous.serial and point.time > previous.time)
        assert(point.time - previous.time >= .07 and point.time - previous.time <= .09)
        for _, field in ipairs({"serial", "time", "x", "y", "vx", "vy", "ax", "ay", "turn"}) do
            assert(type(point[field]) == "number", field)
        end
        previous = point
    end
    local snapshot, oldTime, oldX = trace.points[6], trace.points[6].time, trace.points[6].x
    trace:Sample(1 / 120, 8, 9, -1, 2)
    assert(snapshot.time == oldTime and snapshot.x == oldX and snapshot ~= trace.latest)
    assert(trace.latest.serial == 121 and trace.latest.x == 8 and trace.latest.y == 9)
end)

test("invalid samples leave every cursor and baseline unchanged", function()
    local trace = Trace.New()
    trace:Sample(.02, .1, .2, 1, 2)
    local latest, points, generation = trace.latest, trace.points, trace.generation
    for _, bad in ipairs({0 / 0, math.huge, -math.huge}) do
        assert(not trace:Sample(bad, 0, 0, 0, 0))
        for column = 1, 4 do
            local values = {.02, .1, .2, 1, 2}
            values[column + 1] = bad
            assert(not trace:Sample(table.unpack(values)))
        end
    end
    assert(not trace:Sample(0, 0, 0, 0, 0) and not trace:Sample(-.02, 0, 0, 0, 0))
    assert(trace.serial == 1 and trace.time == .02 and trace.latest == latest)
    assert(trace.points == points and #points == 1 and trace.generation == generation)
    trace:Sample(.02, .12, .24, 1, 2)
    assert(trace.latest.ax == 0 and trace.latest.ay == 0 and trace.latest.turn == 0)
end)

test("large finite velocities stay finite through differences and normalization", function()
    local trace = Trace.New()
    trace:Sample(.01, 0, 0, -1e308, -1e308)
    trace:Sample(.01, 0, 0, 1e308, 1e308)
    local point = trace.latest
    assert(point.ax >= -30 and point.ax <= 30 and point.ay >= -30 and point.ay <= 30)
    assert(point.turn == 0)
end)

test("reset changes generation and drops all presentation memory", function()
    local trace = Trace.New()
    trace:Sample(.1, .3, -.2, 1, -1)
    trace:Sample(.1, .4, -.1, -1, 1)
    local generation = trace.generation
    trace:Reset()
    assert(trace.generation == generation + 1 and trace.serial == 0 and trace.time == 0)
    assert(trace.latest == nil and #trace.points == 0)
    trace:Sample(.01, 0, 0, -50, 50)
    assert(trace.latest.ax == 0 and trace.latest.ay == 0 and trace.latest.turn == 0)
end)

test("motion samples only completed steps and sensor calibration preserves history", function()
    local motion = Motion.New()
    local trace = motion.trace
    motion:Begin()
    motion:Move(.3, -.2)
    local impulseX, impulseY = motion:Step(1 / 120)
    assert(impulseX < 0 and impulseY > 0)
    local point = assert(trace.latest)
    assert(point.serial == 1 and point.x == motion.x and point.y == motion.y)
    assert(point.vx == motion.vx and point.vy == motion.vy)
    local generation = trace.generation
    motion:ResetSensor()
    assert(trace.latest == point and trace.generation == generation)
    motion:Step(0)
    motion:Step(0 / 0)
    assert(trace.serial == 1)
    motion:Reset()
    assert(motion.trace == trace and trace.generation == generation + 1)
    assert(trace.latest == nil and trace.serial == 0 and #trace.points == 0)
end)

test("all retained snapshots stay distinct and unchanged until eviction", function()
    local trace = Trace.New()
    local previous = {}
    local identities = {}
    for step = 1, 2400 do
        for key in pairs(previous) do previous[key] = nil end
        for _, point in ipairs(trace.points) do
            previous[point] = {serial = point.serial, time = point.time, x = point.x}
        end
        trace:Sample(1 / 120, step / 120, step / 240, math.sin(step / 60), math.cos(step / 60))
        for _, point in ipairs(trace.points) do
            local before = previous[point]
            if before then
                assert(point.serial == before.serial and point.time == before.time and point.x == before.x)
            end
            assert(point == trace.latest or point.serial < trace.latest.serial)
        end
        for first = 1, #trace.points do
            for second = first + 1, #trace.points do assert(trace.points[first] ~= trace.points[second]) end
        end
        identities[trace.latest] = true
    end
    local count = 0
    for _ in pairs(identities) do count = count + 1 end
    assert(count <= 8, "sample records kept allocating after the fixed history warmed")
    trace:Reset()
    assert(trace.latest == nil and #trace.points == 0)
end)

test("a pinned borrower keeps an evicted sample until its transaction closes", function()
    local Records = require("Bottle.RecordPool")
    local trace = Trace.New()
    for step = 1, 10 do trace:Sample(.08, step, 0, 1, 0) end
    local snapshot = trace.points[1]
    local serial, x = snapshot.serial, snapshot.x
    do
        local guard <close> = Records.Pin()
        guard:BorrowDeep(trace.points)
        guard:Commit()
        for step = 11, 30 do trace:Sample(.08, step, 0, 1, 0) end
        assert(snapshot.serial == serial and snapshot.x == x)
        for _, point in ipairs(trace.points) do assert(point ~= snapshot) end
        guard:KeepDeep(trace)
    end
    assert(trace.latest.serial == 30 and #trace.points == 6)
end)

function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        assert(ok, "Bottle.ShakeTraceTests [" .. case.name .. "] " .. tostring(message))
    end
    return #cases
end

return Tests
