-- 展示态独立回归；纯 Lua、只操作新建内存对局，不接入总 Tests，也不读写存档。
local Game = require("Bottle.Game")
local PresentationState = require("Bottle.PresentationState")
local Tests = {}

---@return BottleGame
local function Fixture()
    local game = Game.New(20261020)
    assert(game:Start(), "测试对局应成功开始")
    return game
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid)
    return assert(game:Get(uid), "缺少测试实例 uid=" .. uid)
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run)
    cases[#cases + 1] = {name=name, run=run}
end

Test("完整复制顶层字段并保留原 Game metatable 和查询方法", function()
    local game = Fixture()
    game.score, game.roundScore, game.elapsed = 37, 9, 1.25
    game.options = {"apple", "ball"}
    game.relics.last_second = true
    local captured = PresentationState.Capture(game)
    assert(captured ~= game and getmetatable(captured) == getmetatable(game))
    local copiedFields = {
        _instances=true, deck=true, discard=true, drawn=true,
        options=true, spawnQueue=true, relics=true,
    }
    for key, value in pairs(game) do
        if copiedFields[key] then assert(captured[key] ~= value, "容器未隔离: " .. key)
        else assert(captured[key] == value, "顶层字段遗漏或被改写: " .. key) end
    end
    for key in pairs(captured) do assert(game[key] ~= nil, "展示副本不应额外新增规则字段") end
    assert(captured:Get(1) == captured._instances[1] and captured:Get(999999) == nil)
    assert(captured:Duration() == game:Duration() and captured:Duration() == 11)
    local bottle = captured:BottleItems()
    assert(#bottle == #game:BottleItems())
    for index, item in ipairs(bottle) do
        assert(item == captured:Get(item.uid) and item ~= game:Get(item.uid))
        if index > 1 then assert(bottle[index - 1].uid < item.uid) end
        assert(captured:_Value(item) == game:_Value(Item(game, item.uid)))
    end
end)

Test("后续规则修改实例数值位置及注册表不污染已捕获的展示", function()
    local game = Fixture()
    local source = Item(game, 1)
    source.bonus, source.permBonus, source.scale = 3, 2, 1.2
    local captured = PresentationState.Capture(game)
    local item = Item(captured, 1)
    local expectedValue = captured:_Value(item)
    game.score, game.elapsed, game.phase = 99, 4, "settle"
    source.id, source.bonus, source.permBonus, source.scale = "banana", 40, 50, 2
    source.location = "discard"
    game._instances[1] = nil
    local created = game:_Create("apple")
    assert(item.id == "apple" and item.bonus == 3 and item.permBonus == 2 and item.scale == 1.2)
    assert(item.location == "bottle" and captured:_Value(item) == expectedValue)
    assert(captured.score == 0 and captured.elapsed == 0 and captured.phase == "running")
    assert(captured:Get(1) == item and captured:Get(created.uid) == nil)
    assert(#captured:BottleItems() == 4)
end)

Test("临时弃牌与牌库及注册表同 uid 始终使用同一克隆", function()
    local game = Fixture()
    game:Consume(1, true)
    assert(#game.discard == 1 and Item(game, 1).location == "discard")
    local captured = PresentationState.Capture(game)
    local discarded = Item(captured, 1)
    assert(discarded ~= Item(game, 1) and captured.discard[1] == discarded)
    local found = false
    for index, item in ipairs(game.deck) do
        assert(captured.deck[index] == captured:Get(item.uid))
        assert(captured.deck[index] ~= item)
        if item.uid == 1 then
            found = true
            assert(captured.deck[index] == discarded)
        end
    end
    assert(found and #captured:BottleItems() == 3)
    discarded.bonus = 70 -- 仅测试顶层双向隔离；正式 UI 仍须只读使用。
    assert(Item(game, 1).bonus == 0)
    captured.discard[1] = nil
    assert(#game.discard == 1)
end)

Test("非连续注册表及未入瓶实例也逐一克隆", function()
    local game = Fixture()
    game:Consume(1)
    -- 先消耗再布置排队项：Consume 会正常补 FIFO，不能让它把本例排队物提前入瓶。
    local queued = game:_Create("apple")
    queued.location = "queued"
    game.spawnQueue[#game.spawnQueue + 1] = queued.uid
    game._instances[2] = nil -- 制造稀疏 uid，证明捕获不能使用 ipairs 遍历注册表。
    for index = #game.deck, 1, -1 do
        if game.deck[index].uid == 2 then table.remove(game.deck, index) end
    end
    local captured = PresentationState.Capture(game)
    assert(captured:Get(2) == nil and captured:Get(3) ~= nil)
    for uid, item in pairs(game._instances) do
        local cloned = Item(captured, uid)
        assert(cloned ~= item)
        for key, value in pairs(item) do assert(cloned[key] == value, "实例顶层字段遗漏") end
    end
    assert(Item(captured, queued.uid).location == "queued")
    assert(captured.spawnQueue[1] == queued.uid and #captured:BottleItems() == 2)
end)

Test("候选抽取生成队列数组及遗物映射双向隔离", function()
    local game = Fixture()
    game.options = {"apple", "banana", "orange"}
    game.spawnQueue = {5, 6}
    game.relics.last_second = true
    local drawnUid = game.drawn[1]
    local captured = PresentationState.Capture(game)
    game.drawn[1], game.options[1], game.spawnQueue[1] = 99, "ball", 88
    game.relics.last_second = nil
    game.relics.lucky_charm = true
    assert(captured.drawn[1] == drawnUid and captured.options[1] == "apple")
    assert(captured.spawnQueue[1] == 5 and captured.relics.last_second)
    assert(not captured.relics.lucky_charm)
    captured.drawn[2], captured.options[2], captured.spawnQueue[2] = 77, "ball", 66
    captured.relics.chef_hat = true
    assert(game.drawn[2] ~= 77 and game.options[2] == "banana" and game.spawnQueue[2] == 6)
    assert(not game.relics.chef_hat)
end)

Test("回滚与复杂嵌套状态保留只读共享引用而非递归深拷贝", function()
    local game = Fixture()
    local rollback = assert(game._rollback)
    game._lastPositions[1] = {x=.5, y=1.5}
    game._queueOrigins[5] = {x=0, y=6}
    Item(game, 1).rerolled = {[3]=1}
    Item(game, 3).calfDashHits = {[1]=true}
    local captured = PresentationState.Capture(game)
    local capturedRollback = assert(captured._rollback)
    assert(capturedRollback == rollback and capturedRollback.instances == rollback.instances)
    assert(capturedRollback.instances[1] == rollback.instances[1])
    assert(captured._lastPositions == game._lastPositions)
    assert(captured._lastPositions[1] == game._lastPositions[1])
    assert(captured._queueOrigins == game._queueOrigins and captured.startEvents == game.startEvents)
    assert(Item(captured, 1).rerolled == Item(game, 1).rerolled)
    assert(Item(captured, 3).calfDashHits == Item(game, 3).calfDashHits)
end)

Test("捕获不调用存读档或随机方法且不改原局", function()
    local game = Fixture()
    local control = Fixture()
    local rng, nextUid, revision = game._rngState, game._nextUid, game.revision
    local registry, deck, discard, drawn = game._instances, game.deck, game.discard, game.drawn
    -- 开始已生成真实 _rollback；从此禁止捕获借存档转换或随机操作生成副本。
    game.Snapshot = function() error("Capture 不得调用 Snapshot") end
    game.Restore = function() error("Capture 不得调用 Restore") end
    local randomInt = game._RandomInt
    game._RandomInt = function() error("Capture 不得推进随机数") end
    local captured = PresentationState.Capture(game)
    assert(game._rngState == rng and captured._rngState == rng)
    assert(game._nextUid == nextUid and game.revision == revision)
    assert(game._instances == registry and game.deck == deck and game.discard == discard)
    assert(game.drawn == drawn and game.phase == "running" and #game:BottleItems() == 4)
    assert(captured.Snapshot == game.Snapshot and captured.Restore == game.Restore)
    game._RandomInt = randomInt
    for _ = 1, 8 do assert(game:_RandomInt(1000) == control:_RandomInt(1000)) end
end)

Test("已提交后的副本复用容器和实例并清理旧字段与离场实例", function()
    local game = Fixture()
    local original = Item(game, 1) --[[@as any]]
    original.transientTest = 4
    local captured = PresentationState.Capture(game)
    local registry, deck, discard = captured._instances, captured.deck, captured.discard
    local drawn, options, relics = captured.drawn, captured.options, captured.relics
    local copiedItem = Item(captured, 1) --[[@as any]]
    original.transientTest = nil
    original.bonus = original.bonus + 3
    game._instances[2] = nil
    game.deck, game.discard, game.drawn, game.options = {}, {}, {}, {}
    game.relics = {}
    local nextCapture = PresentationState.Capture(game, captured)
    assert(nextCapture == captured and nextCapture._instances == registry)
    assert(nextCapture.deck == deck and nextCapture.discard == discard)
    assert(nextCapture.drawn == drawn and nextCapture.options == options and nextCapture.relics == relics)
    assert(nextCapture:Get(1) == copiedItem and copiedItem ~= original)
    assert(copiedItem.bonus == original.bonus and copiedItem.transientTest == nil)
    assert(nextCapture:Get(2) == nil and #nextCapture.deck == 0 and #nextCapture.discard == 0)
    assert(nextCapture._instances ~= game._instances and nextCapture.options ~= game.options)
end)

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.PresentationStateTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end

return Tests
