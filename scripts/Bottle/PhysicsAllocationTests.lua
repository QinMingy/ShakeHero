-- Allocation ownership and aliasing contracts; no native collision solver mock.
local Game = require("Bottle.Game")
local Physics = require("Bottle.Physics")
local Expansion = require("Bottle.ExpansionPhysics")
local Facts = require("Bottle.StepContactFacts")
local SoftBacon = require("Bottle.SoftBacon")
local Presentation = require("Bottle.PresentationState")
local RelicExpansion = require("Bottle.RelicExpansion")
local FrameBudget = require("Bottle.FrameBudget")
local Repair = require("Bottle.RepairTests")
local Tests = {}
local cases = {}
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end

local function ContactSim(count)
    local sim = setmetatable({bodies = {}, _pairs = {}, _bottom = {}, _top = {}, _wall = {}, _side = {},
        expansion = Expansion.New(), stepContactFacts = Facts.New()}, {__index = Physics})
    for uid = 1, count do
        sim.bodies[uid] = {uid = uid, node = {position2D = {x = uid * .1, y = uid}, rotation2D = uid}}
        if uid > 1 then sim._pairs[tostring(uid - 1) .. ":" .. uid] = {a = uid - 1, b = uid, count = 1} end
    end
    return sim
end

Test("public bottle arrays remain independent and explicit targets are reusable", function()
    local game = Game.New(43)
    local old = game:BottleItems()
    local other = game:BottleItems()
    assert(old ~= other and #old == 4)
    table.remove(other, 1)
    table.sort(other, function(a,b) return a.uid > b.uid end)
    assert(game:BottleItems()[1].uid == 1 and #game:BottleItems() == 4)
    local target = {}
    assert(game:BottleItems(target) == target and #target == 4)
    -- Direct test/GM membership edits need no synthetic revision increment.
    game:Get(2).location = "discard"
    assert(game:BottleItems(target) == target and #target == 3 and target[2].uid == 3)
    assert(#old == 4 and old[2].uid == 2, "an earlier traversal array must not be compacted")
    game:Get(2).location = "bottle"
    assert(game:BottleItems(target) == target and #target == 4 and target[2] == game:Get(2))
    local captured = Presentation.Capture(game)
    local copy = captured:BottleItems(target)
    assert(copy[1] == captured:Get(1) and copy[1] ~= game:Get(1))
    assert(game:BottleItems()[1] == game:Get(1), "presentation caches must not cross registries")
end)

Test("contact targets reuse maps rows and transient pairs without leaking old facts", function()
    local sim = ContactSim(3)
    sim.stepContactFacts:BeginStep(sim.bodies)
    sim.stepContactFacts:Pair(sim.bodies[1], sim.bodies[3])
    sim.stepContactFacts:EndStep()
    local retained = sim:Contacts()
    local target = {} --[[@as BottlePhysicsContacts]]
    sim:Contacts(target)
    local positions, pairArray, angles = target.positions, target.pairs, target.angles
    local positionRows, pairRows = {}, {}
    for _, row in pairs(positions) do positionRows[row] = true end
    for _, row in ipairs(target.pairs) do pairRows[row] = true end
    sim.bodies[1].node.position2D.x = 8
    assert(sim:Contacts(target) == target)
    assert(target.positions == positions and target.pairs == pairArray and target.angles == angles)
    for _, row in pairs(target.positions) do assert(positionRows[row]) end
    for _, row in ipairs(target.pairs) do assert(pairRows[row]) end
    assert(retained.positions[1].x == .1 and retained.positions[1] ~= target.positions[1])
    sim.bodies[2], sim._pairs["1:2"], sim._pairs["2:3"] = nil, nil, nil
    sim.stepContactFacts:Clear()
    sim:Contacts(target)
    assert(target.positions[2] == nil and #target.pairs == 0 and target.angles[2] == nil)
    assert(#retained.pairs == 3 and retained.positions[2].y == 2)
end)

Test("cancelled partial contact reads can restart without consuming physics facts", function()
    local sim = ContactSim(100)
    local target = {} --[[@as BottlePhysicsContacts]]
    local published = false
    sim:Contacts(target)
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    budget:Start(function() sim:Contacts(target); published = true end)
    budget:BeginFrame()
    assert(not budget:Resume() and not published)
    budget:Cancel()
    assert(sim:Contacts(target) == target and #target.pairs == 99 and target.positions[100].y == 100)
end)

Test("sync scratch reuses its containers without rebuilding unchanged bodies", function()
    local game = Repair.Fixture({"ball", "apple"})
    local sim = ContactSim(2)
    sim._retired, sim._retiredSpare = {}, {}
    sim._mergeSpawns, sim._nearSpawns, sim._eventRemoved, sim._respawned, sim._exactSpawns = {}, {}, {}, {}, {}
    sim._updating, sim._flushing, sim._disposed = false, false, false
    for _, item in ipairs(game:BottleItems()) do
        local record = sim.bodies[item.uid]
        record.kind, record.shape, record.scale, record.weight, record.sensor = item.id, "circle", 1, 1, false
    end
    sim._CreateItem = function() error("unchanged sync must not create a body") end
    sim._Retire = function() error("unchanged sync must not retire a body") end
    sim:Sync(game:BottleItems(), false, 1)
    local scratch, maps = sim._syncScratch, {}
    for key, values in pairs(scratch) do maps[key] = values end
    local events = sim._mergeSpawns
    for _ = 1, 5 do sim:Sync(game:BottleItems(), false, 1) end
    assert(sim._syncScratch == scratch and sim._mergeSpawns == events)
    for key, values in pairs(scratch) do assert(values == maps[key]) end
    assert(#scratch.ordered == 2 and sim.bodies[1].uid == 1)
end)

Test("retirement reuses two queues while preserving deferred disposal order", function()
    local disposed, removed = {}, {}
    local sim = setmetatable({_retired = {}, _retiredSpare = {}, _flushing = false}, {__index = Physics})
    local function Record(uid, onRemove)
        return {node = {Remove = function()
            removed[#removed + 1] = uid
            if onRemove then onRemove() end
        end, Dispose = function() disposed[#disposed + 1] = uid end}} --[[@as BottleBody]]
    end
    local third = Record(3)
    sim._retired[1] = Record(1, function() sim._retired[#sim._retired + 1] = third end)
    sim._retired[2] = Record(2)
    local first, second = sim._retired, sim._retiredSpare
    sim:_DrainRetired()
    assert(sim._retired == second and sim._retiredSpare == first and #first == 0)
    assert(#disposed == 2 and disposed[1] == 1 and disposed[2] == 2 and #sim._retired == 1)
    sim:_DrainRetired()
    assert(sim._retired == first and #second == 0 and #disposed == 3 and disposed[3] == 3)
    sim:_DrainRetired()
    assert(sim._retired == first and not sim._flushing and #removed == 3)
end)

Test("soft rendering targets reuse poses while retained event snapshots stay frozen", function()
    local soft = setmetatable({segments = {}}, {__index = SoftBacon})
    for index = 1, 5 do
        soft.segments[index] = {node = {position2D = {x = index, y = 2}, rotation2D = 0},
            halfLength = .2, halfWidth = .1, u0 = (index - 1) / 5, u1 = index / 5} --[[@as BottleSoftSegment]]
    end
    local old, target = soft:GetPose(), {}
    soft:GetPose(target)
    local first = target[1]
    soft.segments[1].node.position2D.x = 9
    assert(soft:GetPose(target) == target and target[1] == first and first.x == 9)
    assert(old[1].x == 1 and old[1] ~= first)
    soft.segments[5] = nil
    assert(#soft:GetPose(target) == 4 and #old == 5)
end)

Test("scratch graph publication remains atomic across yields and raw adjacency is non-recursive", function()
    local game = Repair.Fixture({"bacon", "ball", "bacon", "apple"}, {bacon_network = true})
    local state = {pairs = {{1,2},{1,3},{3,4}}} --[[@as BottleStepContacts]]
    RelicExpansion.ExpandContacts(game, state, true)
    assert(#state.pairs == 5)
    local old = state.pairs
    local oldRows = {}
    for index, pair in ipairs(old) do oldRows[index] = pair[1] .. ":" .. pair[2] end
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    budget:Start(function() RelicExpansion.ExpandContacts(game, state) end)
    repeat
        budget:BeginFrame()
        if not budget:Resume() then
            assert(state.pairs == old)
            for index, pair in ipairs(old) do assert(oldRows[index] == pair[1] .. ":" .. pair[2]) end
        end
    until not budget:Busy()
    assert(state.pairs ~= old and #state.pairs == 5)
    for _, pair in ipairs(state.pairs) do assert(not (pair[1] == 2 and pair[2] == 4)) end
    local neighbors = RelicExpansion.Adjacents(game, 2, state)
    assert(#neighbors == 2 and neighbors[1].uid == 1 and neighbors[2].uid == 3)
end)

Test("idle rotation and pending queues retain identity with stable expiry order", function()
    local sim = ContactSim(1)
    local expansion, record = sim.expansion, sim.bodies[1]
    record.kind, record.ghostLike = "apple", false
    local state = expansion:State(record)
    local rotations, pending = state.rotations, expansion.pending
    for _ = 1, 5 do expansion:Before(record, .02, sim.bodies, function(x,y) return x,y end, 1); expansion:Flush(sim) end
    assert(state.rotations == rotations and expansion.pending == pending)
    local keep = {delta = 0, duration = .3, elapsed = 0, applied = 0}
    rotations[1] = {delta = 0, duration = .01, elapsed = 0, applied = 0}
    rotations[2] = keep
    rotations[3] = {delta = 0, duration = .02, elapsed = 0, applied = 0}
    expansion:Before(record, .02, sim.bodies, function(x,y) return x,y end, 1)
    assert(state.rotations == rotations and #rotations == 1 and rotations[1] == keep and keep.elapsed == .02)
    record.ghostLike = true
    expansion:Before(record, .02, sim.bodies, function(x,y) return x,y end, 1)
    assert(state.rotations == rotations and #rotations == 0)
end)

function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        assert(ok, "Bottle.PhysicsAllocationTests [" .. case.name .. "] " .. tostring(message))
    end
    return #cases
end

return Tests
