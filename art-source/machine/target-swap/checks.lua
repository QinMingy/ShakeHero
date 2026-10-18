-- Offline observable-contract checks; no engine, preview, filesystem writes or player saves.
-- From project root: dofile("art-source/machine/target-swap/checks.lua").Run()
local source = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("\\", "/")
local root = source:match("^(.*)/art%-source/machine/target%-swap/checks%.lua$") or "."
package.path = root .. "/scripts/?.lua;" .. package.path

local Game = require("Bottle.Game")
local Swap = require("Machine.TargetSwapState")
local Layout = require("Machine.LayeredLayout")
local Checks = {}
local cases = {}

local function case(name, run)
    cases[#cases + 1] = {name = name, run = run}
end

local function near(a, b)
    return math.abs(a - b) < 1e-8
end

local function stationary(p)
    return p.visible and not p.arm and near(p.x, 0) and near(p.y, 0) and near(p.angle, 0)
end

local function finitePose(p)
    for _, key in ipairs({"x", "y", "angle", "armX", "armY", "value"}) do
        local value = p[key]
        assert(type(value) == "number" and value == value and math.abs(value) < math.huge,
            "non-finite observable pose: " .. key)
    end
end

-- A conservative screen intersection of the transformed plaque, independent of
-- the animation's timing or easing. This catches changing an old in-view sign.
local function onScreen(p)
    if not p.visible then return false end
    local rect = Layout.target
    local cx, cy = rect[1] + rect[3] / 2, rect[2] + rect[4] / 2
    local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
    local c, s = math.cos(p.angle), math.sin(p.angle)
    for _, uv in ipairs({{0, 0}, {1, 0}, {1, 1}, {0, 1}}) do
        local dx, dy = (uv[1] - .5) * rect[3], (uv[2] - .5) * rect[4]
        local x, y = cx + c * dx - s * dy + p.x, cy + s * dx + c * dy + p.y
        minX, maxX, minY, maxY = math.min(minX, x), math.max(maxX, x),
            math.min(minY, y), math.max(maxY, y)
    end
    return maxX > 0 and minX < Layout.width and maxY > 0 and minY < Layout.height
end

local function finishRound(game)
    assert(game:Start(), "fixture failed to start a round")
    game:Step(game:Duration())
    assert(game.phase == "settle", "running must enter natural settlement")
    game:SettleStep(Game.SETTLE_DELAY)
    assert(game.phase == "reveal", "settlement must enter score reveal")
    game:RevealStep(100)
end

local function beforeFifthReveal()
    local game = Game.New(71)
    for _ = 1, 4 do
        finishRound(game)
        assert(game:Skip(), "fixture failed to advance draft")
    end
    assert(game.round == 5 and game.target == 40)
    -- Supply a sufficient balance, then use the real running/settle/reveal flow.
    game.score = 1000
    assert(game:Start())
    game:Step(game:Duration())
    game:SettleStep(Game.SETTLE_DELAY)
    assert(game.phase == "reveal" and game.target == 40)
    return game
end

local function upgradedGame()
    local game = beforeFifthReveal()
    game:RevealStep(100)
    assert(game.phase == "draft" and game.target == 80 and game.stage == 2)
    return game
end

local function finishGesture(state, game, step, observe)
    for frame = 1, math.ceil(8 / step) do
        state:Sync(game, false)
        state:Tick(step)
        local p = state:Pose()
        finitePose(p)
        if observe then observe(p, frame) end
        if stationary(p) and p.value == game.target then return frame * step end
    end
    error("merchant did not leave a stable, current plaque within eight seconds")
end

case("real fifth-round assessment changes gameplay immediately, presentation keeps old plaque", function()
    local game = beforeFifthReveal()
    local state = Swap.New(game)
    local balance = game.score
    game:RevealStep(100) -- This publicly invokes Game:_FinishReveal().
    assert(game.target == 80 and game.stage == 2 and game.phase == "draft")
    assert(near(game.score, balance - 40), "assessment payment changed")
    local rng, revision, score = game._rngState, game.revision, game.score
    state:Sync(game, false)
    local p = state:Pose()
    assert(p.visible and p.arm and p.value == 40, "new goal leaked onto the old plaque")
    finishGesture(state, game, 1 / 60)
    assert(game._rngState == rng and game.revision == revision and game.score == score,
        "cosmetic gesture changed gameplay or its random sequence")
end)

case("old number stays attached until departure; new number arrives with the new plaque", function()
    local game = {target = 40}
    local state = Swap.New(game)
    game.target = 80
    state:Sync(game, false)
    local departed, oldFrames, newFrames, sawTake, sawPlace = false, 0, 0, false, false
    finishGesture(state, game, 1 / 120, function(p)
        assert(p.value == 40 or p.value == 80, "plaque displayed an intermediate number")
        if p.value == 40 then
            if onScreen(p) then
                assert(not departed, "old plaque reappeared after departure")
                oldFrames = oldFrames + 1
                sawTake = sawTake or (p.grip and (math.abs(p.x) > 4 or math.abs(p.y) > 4))
            else departed = true end
        elseif onScreen(p) then
            assert(departed, "new number appeared before the old plaque left the screen")
            newFrames = newFrames + 1
            sawPlace = sawPlace or (p.grip and math.abs(p.x) > 4)
        end
    end)
    assert(oldFrames > 10 and newFrames > 10 and sawTake and sawPlace,
        "a visible hand must take and replace two readable plaques")
    local p = state:Pose()
    assert(stationary(p) and p.value == 80, "replacement did not finish at its original mount")
end)

case("repeated sync, draft refresh, GM and relic draft do not replay an unchanged goal", function()
    local game = upgradedGame()
    local state = Swap.New(game)
    local function unchanged()
        for _ = 1, 30 do
            state:Sync(game, false)
            state:Tick(1 / 30)
            assert(stationary(state:Pose()) and state:Pose().value == 80,
                "unchanged target replayed the merchant")
        end
    end
    unchanged()
    assert(game:DraftRefresh()); unchanged()
    assert(game:GmAddItem("apple")); unchanged()
    assert(game:Skip() and game.relicDraft); unchanged()
    assert(game:Skip() and game.phase == "prepare"); unchanged()
end)

case("non-assessment rounds and failed assessments never remove the existing plaque", function()
    local game = Game.New(83)
    local state = Swap.New(game)
    for round = 1, 5 do
        -- Deliberately fail the fifth assessment even if the item roster changes.
        if round == 5 then game.score = -1000 end
        finishRound(game)
        state:Sync(game, false)
        state:Tick(.5)
        assert(stationary(state:Pose()) and state:Pose().value == 40,
            "unchanged or failed assessment removed the target")
        if round < 5 then assert(game:Skip()) end
    end
    assert(game.phase == "over", "fixture must exercise the failed-assessment branch")
end)

case("imported and new-run game objects cancel the previous hand and plaque", function()
    local game = upgradedGame()
    local state = Swap.New({target = 40})
    state:Sync(game, false) -- Rebinding to a high-stage save starts at its own baseline.
    assert(stationary(state:Pose()) and state:Pose().value == 80)
    game.target = 140
    state:Sync(game, false)
    state:Tick(.9)
    assert(state:Pose().arm, "fixture must interrupt an actual gesture")
    local imported = Game.Restore(upgradedGame():Snapshot())
    state:Sync(imported, false)
    assert(stationary(state:Pose()) and state:Pose().value == imported.target,
        "import retained the former game's arm or digits")
    imported.target = 140
    state:Sync(imported, false); state:Tick(.9)
    local fresh = Game.New(97)
    state:Sync(fresh, false)
    assert(stationary(state:Pose()) and state:Pose().value == 40,
        "new run retained an earlier goal or arm")
end)

case("main-menu cover and a lower goal clear the gesture without a deferred replay", function()
    local game = {target = 40}
    local state = Swap.New(game)
    game.target = 80
    state:Sync(game, false); state:Tick(.9)
    state:Sync(game, true)
    assert(stationary(state:Pose()) and state:Pose().value == 80,
        "covered menu retained the gesture")
    for _ = 1, 60 do state:Sync(game, false); state:Tick(1 / 30) end
    assert(stationary(state:Pose()) and state:Pose().value == 80,
        "returning from menu replayed an already applied goal")
    game.target = 140
    state:Sync(game, false); state:Tick(.9)
    game.target = 40
    state:Sync(game, false)
    assert(stationary(state:Pose()) and state:Pose().value == 40,
        "lower replacement goal left an obsolete hand or plaque")
end)

case("low frame rates and a long suspended frame finish with one valid plaque", function()
    for _, step in ipairs({1 / 12, .29, .85, 20}) do
        local game = {target = 40}
        local state = Swap.New(game)
        game.target = 80
        state:Sync(game, false)
        local elapsed = 0
        while elapsed < 8 and not (stationary(state:Pose()) and state:Pose().value == 80) do
            state:Sync(game, false)
            state:Tick(step)
            elapsed = elapsed + step
            local p = state:Pose()
            finitePose(p)
            assert(p.value == 40 or p.value == 80, "large dt corrupted the printed number")
        end
        assert(stationary(state:Pose()) and state:Pose().value == 80,
            "large dt left a stuck hand, a gap or a displaced plaque")
        state:Tick(-1)
        assert(stationary(state:Pose()) and state:Pose().value == 80,
            "negative elapsed time rewound a finished gesture")
    end
end)

case("queued increases preserve the plaque already in hand and eventually show the latest goal", function()
    local game = {target = 40}
    local state = Swap.New(game)
    game.target = 80
    state:Sync(game, false)
    local sawFirstReplacement, sawLatestReplacement, firstCycleEnded = false, false, false
    for frame = 1, 720 do
        if frame == 24 then game.target = 140 end
        if frame == 48 then game.target = 220 end
        state:Sync(game, false)
        state:Tick(1 / 60)
        local p = state:Pose()
        finitePose(p)
        if not firstCycleEnded then
            assert(p.value == 40 or p.value == 80,
                "a later increase changed the plaque already in the hand")
            if onScreen(p) and p.value == 80 then sawFirstReplacement = true end
            if stationary(p) and p.value == 80 then firstCycleEnded = true end
        end
        if onScreen(p) and p.value == 220 then sawLatestReplacement = true end
    end
    assert(sawFirstReplacement and sawLatestReplacement, "queued targets lost the in-flight or latest plaque")
    assert(stationary(state:Pose()) and state:Pose().value == 220,
        "queue failed to drain to the latest target")
end)

function Checks.Run()
    for _, test in ipairs(cases) do
        local ok, err = pcall(test.run)
        assert(ok, test.name .. ": " .. tostring(err))
    end
    return #cases
end

return Checks
