-- 核心规则升级回归。只构造内存快照/接触夹具，不读写玩家存档、不创建引擎对象。
-- 由 Bottle.Tests.Run 统一执行；真实 Box2D/界面验收由独立运行时专项完成。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local RelicEffects = require("Bottle.RelicEffects")
local Repair = require("Bottle.RepairTests")
local Tests = {}

---@param actual number?
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (label or "数值") .. "：expected=" .. expected .. " actual=" .. tostring(actual))
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid), "缺少实例uid=" .. uid) end

---@param ids string[]
---@param bottleCount integer?
---@return BottleGame
local function Fixture(ids, bottleCount)
    local game = Repair.Fixture(ids)
    if bottleCount ~= nil then
        local snapshot = game:Snapshot()
        snapshot.drawn = {}
        for _, item in ipairs(snapshot.instances) do
            item.location = item.uid <= bottleCount and "bottle" or "deck"
            if item.uid <= bottleCount then snapshot.drawn[#snapshot.drawn + 1] = item.uid end
        end
        return Game.Restore(snapshot)
    end
    return game
end

---@param game BottleGame
---@param contacts BottleContacts?
---@return GameEvent[]
local function Finish(game, contacts)
    local events = game:Finish(contacts)
    assert(game.phase == "reveal", "结算后必须展示")
    game:RevealStep(100)
    assert(game.phase == "draft", "本夹具必须进入三选一")
    return events
end

---@param game BottleGame
local function Fill(game)
    while #game:BottleItems() < Items.Settings.bottleLimit do game:_Spawn("ball", {}) end
    assert(#game:BottleItems() == 100)
end

---@param array ItemInstance[]
---@param uid integer
---@return boolean
local function Contains(array, uid)
    for _, item in ipairs(array) do if item.uid == uid then return true end end
    return false
end

---@param first any
---@param second any
---@return boolean
local function Equal(first, second)
    if type(first) ~= type(second) then return false end
    if type(first) ~= "table" then return first == second end
    for key, value in pairs(first) do if not Equal(value, second[key]) then return false end end
    for key in pairs(second) do if first[key] == nil then return false end end
    return true
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end

Test("新局物品刷新1次、每完成2回合加1且每回合独立重抽", function()
    local game = Fixture({"apple"})
    assert(Game.New(1).refreshes == 1 and game.refreshes == 1)
    Item(game, 1).permBonus = 100
    for round = 1, 4 do
        assert(not game.rerollUsed and game:Reroll() and not game:Reroll(), "每回合重抽一次并重置")
        Close(game.refreshes, 1 + math.floor((round - 1) / 2), "准备重抽不扣物品刷新池")
        assert(game:Start())
        Finish(game)
        Close(game.refreshes, 1 + math.floor(round / 2), "完成回合后累计")
        local earned = game.refreshes
        assert(game:Skip())
        Close(game.refreshes, earned, "推进准备不重复奖励")
    end
    assert(game.round == 5)
end)

Test("准备重抽、物品刷新池、遗物免费刷新相互独立", function()
    local game = Fixture({"apple"})
    game.refreshes = 4
    assert(game:Reroll())
    local once = game:Snapshot()
    assert(not game:Reroll() and Equal(once, game:Snapshot()), "重抽用尽后原子拒绝，不改RNG")
    Close(game.refreshes, 4)
    assert(game:Start())
    local before = game.refreshes
    assert(not game:Reroll())
    Close(game.refreshes, before, "无效阶段不扣次数")
    Finish(game)
    for _ = 1, 4 do assert(game:DraftRefresh()) end
    Close(game.refreshes, 0)
    local revision = game.revision
    assert(not game:DraftRefresh() and game.revision == revision, "耗尽刷新原子拒绝")
    local snapshot = game:Snapshot()
    snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
    snapshot.target, snapshot.relicDraft = Game.GetTarget(2), true
    snapshot.options, snapshot.refreshes, snapshot.refreshUsed = {"juicer"}, 2, false
    local relic = Game.Restore(snapshot)
    assert(relic:DraftRefresh() and not relic:DraftRefresh())
    Close(relic.refreshes, 2)
end)

Test("物品刷新池为零仍可重抽且用过的重抽读档不补发", function()
    local game = Fixture({"apple", "ball", "orange"})
    game.refreshes = 0
    assert(game:Reroll() and game.rerollUsed)
    local saved = game:Snapshot()
    local restored = Game.Restore(saved)
    assert(not restored:Reroll() and Equal(saved, restored:Snapshot()), "读档保留本回合已用状态")
    Close(restored.refreshes, 0)
    assert(restored:Start())
    assert(not restored:Reroll())
    Finish(restored)
    assert(not restored:DraftRefresh(), "免费重抽未增加物品刷新余额")
    assert(restored:Skip() and not restored.rerollUsed)
    assert(restored:Reroll(), "下一回合即使池为空也获得一次重抽")
    Close(restored.refreshes, 0)
end)

Test("遗物免费刷新不依赖物品余额且读档不能重复领取", function()
    for _, balance in ipairs({0, 8}) do
        local snapshot = Fixture({"chicken_keeper"}):Snapshot()
        snapshot.drawn = {}
        for _, item in ipairs(snapshot.instances) do item.location = "deck" end
        snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
        snapshot.target, snapshot.relicDraft = Game.GetTarget(2), true
        snapshot.options, snapshot.refreshes, snapshot.refreshUsed = {"juicer"}, balance, false
        local game = Game.Restore(snapshot)
        local unspent = game:Snapshot()
        assert(game:DraftRefresh() and game.refreshUsed)
        Close(game.refreshes, balance)
        Close(Item(game, 1).refreshCount, 1, "成功遗物刷新仍通知养鸡人")
        local spent = game:Snapshot()
        assert(not game:DraftRefresh() and Equal(spent, game:Snapshot()), "重复刷新不改状态或RNG")
        local restored = Game.Restore(spent)
        assert(not restored:DraftRefresh() and Equal(spent, restored:Snapshot()), "读档不补发已用免费次数")
        restored = Game.Restore(unspent)
        assert(restored:DraftRefresh() and not restored:DraftRefresh(), "未使用的免费次数随存档保留")
        Close(restored.refreshes, balance)
    end
end)

Test("每次遗物三选一重置一次免费刷新，已用或未用均不累计", function()
    local game = Fixture({"apple"})
    Item(game, 1).permBonus = 10000
    for round = 1, 15 do
        assert(game:Start()); Finish(game)
        if round % 5 == 0 then
            assert(game:Skip() and game.relicDraft and not game.refreshUsed)
            local balance = game.refreshes
            if round ~= 10 then
                assert(game:DraftRefresh() and not game:DraftRefresh())
                Close(game.refreshes, balance)
            end
            assert(game:Skip() and game.phase == "prepare" and not game.relicDraft)
        else
            assert(game:Skip())
        end
    end
    assert(game.round == 16)
end)

Test("所有成功刷新为已拥有养鸡人计数、失败不计且余数读档", function()
    local game = Fixture({"chicken_keeper", "chicken_keeper", "apple"}, 1)
    game.refreshes = 4
    assert(game:Reroll() and not game:Reroll())
    assert(game:Start())
    Finish(game)
    for _ = 1, 3 do assert(game:DraftRefresh()) end
    for uid = 1, 2 do Close(Item(game, uid).refreshCount, 4); Close(Item(game, uid).permBonus, 0) end
    local restored = Game.Restore(game:Snapshot())
    Close(restored.refreshes, 1)
    assert(restored:DraftRefresh())
    for uid = 1, 2 do Close(Item(restored, uid).refreshCount, 0); Close(Item(restored, uid).permBonus, 1) end
    assert(not restored:DraftRefresh())
    assert(restored:Skip())
    assert(restored:Reroll())
    assert(restored:Start())
    assert(not restored:Reroll())
    Finish(restored)
    for uid = 1, 2 do Close(Item(restored, uid).refreshCount, 1); Close(Item(restored, uid).permBonus, 1) end
end)

Test("鸡蛋3次入瓶成功加1刷新、失败不加且不重复领取", function()
    for _, outcome in ipairs({1, 2}) do
        local game = Fixture({"egg"})
        Item(game, 1).bottleRounds = 2
        assert(game:Start())
        local calls = 0
        rawset(game, "_RandomInt", function(_, maximum)
            assert(maximum == 2, "鸡蛋只判一次50%")
            calls = calls + 1
            return outcome
        end)
        game:Finish()
        assert(calls == 1 and Item(game, 1).location == "discard")
        Close(game.refreshes, outcome == 1 and 2 or 1)
        assert(#game:Finish() == 0 and calls == 1)
        rawset(game, "_RandomInt", nil)
        game:RevealStep(100)
        local restored = Game.Restore(game:Snapshot())
        Close(restored.refreshes, outcome == 1 and 2 or 1)
    end
end)

Test("刷新余额prepare与draft读档保留且运行中回滚", function()
    local game = Fixture({"apple"})
    game.refreshes = 7
    assert(game:Reroll())
    local prepare = game:Snapshot()
    assert(prepare.version == 2 and prepare.rulesVersion == 6 and prepare.refreshes == 7 and prepare.rerollUsed)
    local restored = Game.Restore(prepare)
    Close(restored.refreshes, 7)
    assert(not restored:Reroll(), "读档不补发本回合已用重抽")
    assert(restored:Start())
    restored.refreshes = 100
    Close(Game.Restore(restored:Snapshot()).refreshes, 7, "半回合刷新收益不存档")
    assert(game:Start())
    Finish(game)
    Close(Game.Restore(game:Snapshot()).refreshes, 7)
end)

Test("旧档缺刷新只继承当前一次、不追溯已完成回合", function()
    for _, used in ipairs({false, true}) do
        local prepare = Fixture({"apple"}):Snapshot() --[[@as any]]
        prepare.rulesVersion, prepare.refreshes, prepare.rerollUsed = nil, nil, used
        prepare.round, prepare.stage, prepare.target = 17, 4, Game.GetTarget(4)
        local restored = Game.Restore(prepare)
        Close(restored.refreshes, used and 0 or 1)
        local draft = Fixture({"apple"}, 0):Snapshot() --[[@as any]]
        draft.phase, draft.round, draft.stage, draft.target = "draft", 17, 4, Game.GetTarget(4)
        draft.rulesVersion, draft.refreshes, draft.refreshUsed = nil, nil, used
        restored = Game.Restore(draft)
        Close(restored.refreshes, used and 0 or 1)
        assert(restored:Snapshot().rulesVersion == 6 and restored:Snapshot().version == 2)
    end
end)

Test("满瓶生成永久入牌库且FIFO补位、队列只保运行态", function()
    local game = Fixture({"apple"})
    assert(game:Start())
    Fill(game)
    local events = {}
    local first = assert(game:_Spawn("orange", events, false, {x=.1,y=4}))
    local second = assert(game:_Spawn("cherry", events, false, {x=.2,y=5}))
    assert(#events == 0 and #game.spawnQueue == 2)
    assert(game.spawnQueue[1] == first.uid and game.spawnQueue[2] == second.uid)
    assert(first.location == "queued" and second.location == "queued")
    assert(Contains(game.deck, first.uid) and Contains(game.deck, second.uid), "排队时已经永久拥有")
    assert((game:Snapshot() --[[@as any]]).spawnQueue == nil, "运行快照不导出队列")
    local spawned = game:Consume(2)
    assert(first.location == "bottle" and second.location == "queued")
    assert(#Repair.Events(spawned, "spawn", first.uid) == 1)
    Close(Repair.Events(spawned, "spawn", first.uid)[1].x, .1)
    assert(#game.spawnQueue == 1 and game.spawnQueue[1] == second.uid)
    spawned = game:Consume(3)
    assert(second.location == "bottle" and #game.spawnQueue == 0)
    assert(#Repair.Events(spawned, "spawn", second.uid) == 1)
    Close(Repair.Events(spawned, "spawn", second.uid)[1].y, 5)
    local queued = assert(game:_Spawn("juice", {}))
    assert(queued.location == "queued")
    Finish(game)
    assert(queued.location == "deck" and Contains(game.deck, queued.uid) and #game.spawnQueue == 0)
    local snapshot = game:Snapshot() --[[@as any]]
    assert(snapshot.spawnQueue == nil)
    snapshot.spawnQueue = {99999}
    local restored = Game.Restore(snapshot)
    assert(#restored.spawnQueue == 0 and Item(restored, queued.uid).location == "deck")
end)

Test("临时生成瓶内弃牌与排队回合末真正移除", function()
    local game = Fixture({"apple"})
    assert(game:Start())
    local bottled = assert(game:_Spawn("wool", {}, true))
    local consumed = assert(game:_Spawn("wool", {}, true))
    assert(consumed.generatedTemporary and bottled.generatedTemporary)
    game:Consume(consumed.uid)
    Fill(game)
    local queued = assert(game:_Spawn("wool", {}, true))
    assert(queued.location == "queued")
    Finish(game)
    for _, uid in ipairs({bottled.uid, consumed.uid, queued.uid}) do
        assert(game:Get(uid) == nil and not Contains(game.deck, uid) and not Contains(game.discard, uid),
            "临时生成uid必须从注册表/牌库/弃牌全部移除")
    end
    assert(#game.spawnQueue == 0)
    Game.Restore(game:Snapshot())
end)

Test("临时消耗返还原件不混同临时生成、死灵返还也不能永久化产物", function()
    local game = Fixture({"apple", "necromancer"})
    local original = Item(game, 1)
    assert(game:Start())
    game:Consume(original.uid, true)
    assert(original.temporary and not original.generatedTemporary and original.location == "discard")
    local generated = assert(game:_Spawn("wool", {}, true))
    game:Consume(generated.uid)
    rawset(game, "_RandomInt", function() return 1 end)
    Finish(game)
    assert(game:Get(original.uid) == original and original.location == "deck" and not original.temporary)
    assert(not original.generatedTemporary and Contains(game.deck, original.uid))
    assert(game:Get(generated.uid) == nil, "死灵存在也不得把临时生成转为永久")
    Game.Restore(game:Snapshot())
end)

Test("新果汁基础3、消费奖励锁定有效值且榨汁产物不额外加3", function()
    local game = Fixture({"diner", "juice"})
    Close(game:_Value(Item(game, 2)), 3, "普通新果汁基础")
    Item(game, 2).valueBase, Item(game, 2).permMult = 8, 1.5
    assert(game:Start())
    game:Step(0, {pairs={{1,2}}})
    Close(Item(game, 1).permBonus, 12, "消耗者永久得到果汁有效值")
    Close(game.roundScore, 24, "食客金币仍为消耗前12×2")
    assert(Item(game, 2).location == "discard")
    local juicer = Fixture({})
    juicer.relics.juicer = true
    juicer.juicerValue = 12.5
    local ok, _, juice = RelicEffects.UseJuicer(juicer)
    assert(ok and juice)
    Close(juice.valueBase, 12.5); Close(juice.permBonus, 0); Close(juicer:_Value(juice), 12.5)
    local restored = Game.Restore(juicer:Snapshot())
    Close(restored:_Value(Item(restored, juice.uid)), 12.5)
end)

Test("旧果汁迁移基础0保持累计价值、不改其他物品或永久增益", function()
    local snapshot = Fixture({"juice", "apple"}):Snapshot() --[[@as any]]
    snapshot.rulesVersion, snapshot.refreshes = nil, nil
    snapshot.instances[1].valueBase, snapshot.instances[1].permBonus = nil, 12.5
    snapshot.instances[2].permBonus = 4
    local restored = Game.Restore(snapshot)
    Close(Item(restored, 1).valueBase, 0)
    Close(Item(restored, 1).permBonus, 12.5)
    Close(restored:_Value(Item(restored, 1)), 12.5)
    Close(restored:_Value(Item(restored, 2)), 6)
    local again = Game.Restore(restored:Snapshot())
    Close(again:_Value(Item(again, 1)), 12.5, "迁移不重复扣加基础")
end)

Test("金盘洗手小偷不再被警察消灭或老师负面转化", function()
    for _, protected in ipairs({false, true}) do
        local police = Fixture({"police", "thief"})
        police.relics.wash_hands = protected or nil
        assert(police:Start())
        police:Step(0, {pairs={{1,2}}})
        assert(Item(police, 2).location == (protected and "bottle" or "discard"))
        Close(police.roundScore, protected and 0 or 4)
        local teacher = Fixture({"teacher", "thief"})
        teacher.relics.teach_all, teacher.relics.wash_hands = true, protected or nil
        assert(teacher:Start())
        teacher:Step(0, {pairs={{1,2}}})
        assert(Item(teacher, 2).id == (protected and "thief" or "student"))
    end
end)

Test("厨师帽本次小刀加成与1秒冷却、不跨次累计", function()
    local game = Fixture({"chef", "knife", "apple"})
    game.relics.chef_hat = true
    Close(game:CooldownOf("chef"), 1)
    assert(game:Start())
    game:Step(0, {pairs={{1,2},{1,3}}})
    Close(Item(game, 3).permBonus, 4)
    assert(Item(game, 2).location == "discard")
    Close(Item(game, 1).remaining, 1)
    local nextFruit = assert(game:_Spawn("apple", {}))
    game:Step(.99, {pairs={{1,nextFruit.uid}}})
    assert(nextFruit.id == "apple", "冷却未到不得切")
    game:Step(.01, {pairs={{1,nextFruit.uid}}})
    assert(nextFruit.id == "apple_half")
    Close(nextFruit.permBonus, 3, "下次无刀不继承额外+1")
end)

Test("回合重置与读档不清永久物理、触发就绪而timer完整周期", function()
    local game = Fixture({"apple", "ball", "cloud"})
    Item(game, 1).scale, Item(game, 1).weight = .75, 1.5
    assert(game:Start())
    Close(Item(game, 1).scale, .75); Close(Item(game, 1).weight, 1.5)
    Close(Item(game, 2).remaining, 0); Close(Item(game, 3).remaining, 5)
    assert(#Repair.Events(game:Step(0, {wall={[2]=true}}), "buff", 2) == 1)
    assert(#Repair.Events(game:Step(0), "spawn") == 0, "timer不能因开局就绪立即生产")
    Finish(game)
    local restored = Game.Restore(game:Snapshot())
    assert(restored:Skip() and restored:Start())
    Close(Item(restored, 1).scale, .75); Close(Item(restored, 1).weight, 1.5)
    Close(Item(restored, 2).remaining, 0); Close(Item(restored, 3).remaining, 5)
end)

Test("羊毛库存及可入场回合永久读档、旧缺字段安全默认", function()
    local snapshot = Fixture({"sheep", "wool"}, 1):Snapshot() --[[@as any]]
    snapshot.instances[1].woolCount = 2147483647
    snapshot.instances[2].woolReadyRound = 3
    local restored = Game.Restore(snapshot)
    Close(Item(restored, 1).woolCount, 2147483647)
    Close(Item(restored, 2).woolReadyRound, 3)
    assert(restored:Start())
    Finish(restored)
    local again = Game.Restore(restored:Snapshot())
    Close(Item(again, 1).woolCount, 2147483647)
    Close(Item(again, 2).woolReadyRound, 3)
    snapshot.instances[1].woolCount, snapshot.instances[2].woolReadyRound = nil, nil
    local legacy = Game.Restore(snapshot)
    Close(Item(legacy, 1).woolCount, 0)
    assert(Item(legacy, 2).woolReadyRound == nil, "旧档缺ready不擅加等待回合")
end)

Test("额外羊毛prepare原uid与普通drawn分离、Start才临时化并清理", function()
    local snapshot = Fixture({"apple", "wool", "wool"}, 1):Snapshot()
    snapshot.instances[2].location, snapshot.instances[2].woolExtraEntry = "bottle", true
    snapshot.instances[2].woolReadyRound = 1
    snapshot.instances[3].woolExtraEntry = true -- 超额暂留deck的同一白名单形态。
    local restored = Game.Restore(snapshot)
    assert(#restored.drawn == 1 and restored.drawn[1] == 1)
    for uid = 2, 3 do
        assert(Item(restored, uid).woolExtraEntry and not Item(restored, uid).generatedTemporary)
    end
    local again = Game.Restore(restored:Snapshot())
    assert(again:Start())
    for uid = 2, 3 do
        assert(Item(again, uid).generatedTemporary and Item(again, uid).temporary)
        assert(Item(again, uid).woolExtraEntry == nil)
    end
    assert(Item(again, 3).location == "queued" and again.spawnQueue[1] == 3)
    local rollback = Game.Restore(again:Snapshot())
    assert(rollback.phase == "prepare" and Item(rollback, 2).woolExtraEntry
        and Item(rollback, 3).woolExtraEntry and #rollback.spawnQueue == 0)
    Finish(again)
    assert(again:Get(2) == nil and again:Get(3) == nil and #again.spawnQueue == 0)
    Game.Restore(again:Snapshot())
end)

Test("额外羊毛存档拒绝错误类型价值回合抽取位置及瓶容量", function()
    ---@type fun(snapshot:any)[]
    local corruptions = {
        function(snapshot) snapshot.instances[2].id = "apple" end,
        function(snapshot) snapshot.instances[2].permBonus = 1 end,
        function(snapshot) snapshot.instances[2].woolReadyRound = 2 end,
        function(snapshot) snapshot.drawn[#snapshot.drawn + 1] = 2 end,
        function(snapshot)
            snapshot.phase, snapshot.drawn = "draft", {}
            snapshot.instances[1].location, snapshot.instances[2].location = "deck", "deck"
        end,
        function(snapshot)
            snapshot.phase, snapshot.drawn, snapshot.deck, snapshot.discard = "draft", {}, {1}, {2}
            snapshot.instances[1].location, snapshot.instances[2].location = "deck", "discard"
        end,
    }
    for _, corrupt in ipairs(corruptions) do
        local snapshot = Fixture({"apple", "wool"}, 1):Snapshot() --[[@as any]]
        snapshot.instances[2].location, snapshot.instances[2].woolExtraEntry = "bottle", true
        corrupt(snapshot)
        assert(not pcall(Game.Restore, snapshot), "错误额外入场状态不得绕过严格drawn规则")
    end
    local game = Fixture({"apple"})
    for _ = 1, 100 do
        local item = game:_Create("wool")
        item.location, item.woolExtraEntry, item.woolReadyRound = "bottle", true, 1
    end
    assert(not pcall(Game.Restore, game:Snapshot()), "额外入场仍受100瓶容量限制")
end)

Test("存档严格拒绝新永久字段非法值和所有运行态残留", function()
    local invalid = {
        refreshes={-1,.5,false,"1",0/0,math.huge},
        rulesVersion={0,4,7,false,"6"},
        valueBase={false,"3",{},0/0,math.huge,-math.huge},
        refreshCount={-1,5,.5,false,"1",0/0,math.huge},
        woolCount={-1,2147483648,.5,false,"1",0/0,math.huge},
        woolReadyRound={0,-1,2147483648,.5,false,"1",0/0,math.huge},
        woolExtraEntry={0,"true",{}},
        eventMult={0,2,false,"1",{}}, generatedTemporary={true,0,"false"},
        shielded={true,0,"false"}, anchored={true,0,"false"},
        abacusMerges={1,false,{}}, calfDashRemaining={.1,false,{}},
        discusWait={1,false,{}}, compassProgress={1,false,{}},
        ghostTravel={.1,false,{}}, spinProgress={.1,false,{}}, geckoContactTime={.1,false,{}},
        spinTravel={0}, spinAngle={0}, spinForced={0},
        pendingConsumerUid={1}, calfDashHits={{}}, discusOwnerUid={1}, discusTargetUid={1},
        discusState={"flying"}, discusHolderUid={1}, compassAngle={0}, compassTravel={0},
        compassForced={0}, cactusScale={1},
    }
    for field, values in pairs(invalid) do
        for _, value in ipairs(values) do
            local snapshot = Fixture({"apple"}):Snapshot() --[[@as any]]
            local target = (field == "refreshes" or field == "rulesVersion") and snapshot or snapshot.instances[1]
            target[field] = value
            assert(not pcall(Game.Restore, snapshot), "必须拒绝损坏字段 " .. field .. "=" .. tostring(value))
        end
    end
    local missingRefresh = Fixture({"apple"}):Snapshot() --[[@as any]]
    missingRefresh.refreshes = nil
    assert(not pcall(Game.Restore, missingRefresh), "新规则不得套用旧档缺余额默认")
    local valid = Fixture({"apple"}):Snapshot()
    valid.refreshes = 100
    valid.instances[1].valueBase, valid.instances[1].refreshCount = -2.5, 4
    local restored = Game.Restore(valid)
    Close(restored.refreshes, 100); Close(Item(restored, 1).valueBase, -2.5)
    Close(Item(restored, 1).refreshCount, 4)
end)

Test("新局移除为0、每次考核付款后加1且未用机会跨考核累计", function()
    local game = Fixture({"apple"})
    Close(Game.New(1).removals, 0)
    Close(game.removals, 0)
    game.score = 10000
    for round = 1, 10 do
        assert(game:Start())
        local earned = math.floor((round - 1) / 5)
        game:Finish()
        assert(game.phase == "reveal")
        Close(game.removals, earned, "结算展示尚未发放考核奖励")
        game:RevealStep(100)
        assert(game.phase == "draft")
        Close(game.removals, math.floor(round / 5), "仅考核付款发放1次")
        local afterAward = game.removals
        game:RevealStep(100)
        game:Finish()
        game:_FinishReveal()
        Close(game.removals, afterAward, "重复推进结算不重复发放")
        assert(game:Skip())
        if game.phase == "draft" then
            assert(game.relicDraft and game:Skip())
        end
        assert(game.phase == "prepare" and game.round == round + 1)
        Close(game.removals, afterAward, "跳过物品与遗物不重复发放")
    end
    Close(game.removals, 2)
end)

Test("考核余额不足保留既有移除次数且不发新机会", function()
    local snapshot = Fixture({"apple"}):Snapshot()
    snapshot.round, snapshot.removals = 5, 3
    local game = Game.Restore(snapshot)
    assert(game:Start())
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "over")
    Close(game.removals, 3)
    game:RevealStep(100)
    game:_FinishReveal()
    Close(game.removals, 3)
    Close(Game.Restore(game:Snapshot()).removals, 3)
end)

Test("移除余额新档往返保留、不升级版本且旧档缺省0不追溯", function()
    local game = Fixture({"apple"})
    game.removals = 7
    local snapshot = game:Snapshot()
    assert(snapshot.version == 2 and snapshot.rulesVersion == 6 and snapshot.removals == 7)
    assert(Equal(snapshot, Game.Restore(snapshot):Snapshot()))
    local json = rawget(_G, "cjson") --[[@as BottleTestJsonCodec?]]
    if json then
        assert(Equal(snapshot, Game.Restore(json.decode(json.encode(snapshot)) --[[@as BottleSnapshot]]):Snapshot()))
    end
    for _, version in ipairs({0, 5, 6}) do
        local legacy = Fixture({"apple"}):Snapshot() --[[@as any]]
        legacy.rulesVersion = version
        if version == 0 then legacy.rulesVersion = nil end
        legacy.round, legacy.stage, legacy.target = 21, 5, Game.GetTarget(5)
        legacy.removals = nil
        local restored = Game.Restore(legacy)
        Close(restored.removals, 0, "旧局只迁移为0，不按4次历史考核补发")
        assert(restored:Snapshot().version == 2 and restored:Snapshot().rulesVersion == 6)
        assert(legacy.removals == nil, "恢复不能改写源快照")
    end
end)

Test("移除存档拒绝负数小数非数字及非有限计数", function()
    for _, value in ipairs({-1, .5, false, "1", {}, 0/0, math.huge, -math.huge}) do
        local snapshot = Fixture({"apple"}):Snapshot() --[[@as any]]
        snapshot.removals = value
        assert(not pcall(Game.Restore, snapshot), "拒绝损坏移除次数=" .. tostring(value))
    end
    local valid = Fixture({"apple"}):Snapshot()
    valid.removals = 0
    Close(Game.Restore(valid).removals, 0)
end)

Test("移除消费与永久删除纳入回合前快照、半回合余额不保存", function()
    for _, phase in ipairs({"running", "settle", "reveal"}) do
        local game = Fixture({"apple", "apple"})
        game.removals = 2
        assert(game:RemoveItem(1))
        local prepare = game:Snapshot()
        assert(game:Start())
        game.phase = phase
        game.removals = 99
        local restored = Game.Restore(game:Snapshot())
        assert(Equal(prepare, restored:Snapshot()), "半回合恢复应保留移除后的准备快照")
        Close(restored.removals, 1)
        assert(restored:Get(1) == nil and restored:Get(2) ~= nil)
    end
end)

Test("主动移除只删选中同名实例、清理抽取位置且永久不返还", function()
    local game = Fixture({"apple", "apple", "ball"})
    game.removals = 2
    local other = Item(game, 2)
    other.permBonus = 3
    game._lastPositions[1] = {x=1, y=2}
    local revision, nextUid = game.revision, game._nextUid
    local ok, message = game:RemoveItem(1)
    assert(ok and type(message) == "string")
    Close(game.removals, 1)
    assert(game.revision > revision and game._nextUid == nextUid)
    assert(game:Get(1) == nil and not Contains(game.deck, 1) and not Contains(game.discard, 1))
    assert(game._lastPositions[1] == nil and #game:BottleItems() == 2 and #game.drawn == 2)
    for _, uid in ipairs(game.drawn) do assert(uid ~= 1) end
    assert(game:Get(2) == other and Contains(game.deck, 2))
    Close(other.permBonus, 3)
    local after = game:Snapshot()
    assert(not game:RemoveItem(1) and Equal(after, game:Snapshot()), "连点不再扣机会")
    local restored = Game.Restore(after)
    assert(restored:Get(1) == nil and restored:Get(2) ~= nil and restored.removals == 1)
    assert(restored:Reroll() and restored:Get(1) == nil, "重抽不能令移除实例返回")
    assert(restored:Start())
    Finish(restored)
    assert(restored:Skip() and restored:Get(1) == nil, "推进回合不能令移除实例返回")
end)

Test("主动移除支持牌库备用物品、物品draft及终局详情", function()
    local deck = Fixture({"apple", "apple"}, 0)
    deck.removals = 1
    assert(deck:RemoveItem(1) and #deck.drawn == 0 and deck:Get(2) ~= nil)
    Game.Restore(deck:Snapshot())
    local draft = Fixture({"apple"})
    draft.removals = 1
    assert(draft:Start())
    Finish(draft)
    local options, rngState = draft:Snapshot().options, draft._rngState
    assert(draft:RemoveItem(1) and #draft.deck == 0)
    assert(Equal(options, draft.options) and rngState == draft._rngState, "移除不重抽候选")
    Game.Restore(draft:Snapshot())
    local failed = Fixture({"apple"}):Snapshot()
    failed.round, failed.removals = 5, 1
    local over = Game.Restore(failed)
    assert(over:Start())
    over:Finish(); over:RevealStep(100)
    assert(over.phase == "over" and over:RemoveItem(1))
    assert(#over.deck == 0 and over.removals == 0)
    Game.Restore(over:Snapshot())
end)

Test("无移除次数和陌生UID原子拒绝、余额与物品不变", function()
    local game = Fixture({"apple"})
    local before = game:Snapshot()
    assert(not game:RemoveItem(1) and Equal(before, game:Snapshot()))
    game.removals = 2
    before = game:Snapshot()
    for _, uid in ipairs({0, -1, 1.5, 999999, "1", true, {}, 0/0, math.huge}) do
        assert(not game:RemoveItem(uid --[[@as any]]) and Equal(before, game:Snapshot()),
            "无效UID不得消费移除机会或改变状态：" .. tostring(uid))
    end
    assert(not game:RemoveItem(nil --[[@as any]]) and Equal(before, game:Snapshot()))
end)

Test("运行结算展示阶段移除原子拒绝", function()
    for _, phase in ipairs({"running", "settle", "reveal"}) do
        local game = Fixture({"apple"})
        game.removals = 2
        assert(game:Start())
        game.phase = phase
        local revision, rngState, item = game.revision, game._rngState, Item(game, 1)
        assert(not game:RemoveItem(1))
        assert(game.phase == phase and game:Get(1) == item and #game.deck == 1
            and game.revision == revision and game._rngState == rngState)
        Close(game.removals, 2)
    end
end)

Test("已消耗弃牌不能再次花机会移除", function()
    local game = Fixture({"apple", "ball"})
    game.removals = 2
    assert(game:Start())
    game:Consume(1)
    Finish(game)
    assert(Item(game, 1).location == "discard" and not Contains(game.deck, 1))
    local snapshot = game:Snapshot()
    assert(not game:RemoveItem(1) and Equal(snapshot, game:Snapshot()))
end)

Test("主动移除不触发香蕉皮重生返还榨汁消费或金币遗物奖励", function()
    local game = Repair.Fixture({"banana", "enoki", "ghost", "rainbow_poop", "apple_half", "tomato_egg", "necromancer", "pig"},
        {gm_fruit=true, small_savings=true, see_you_tomorrow=true, juicer=true})
    game.removals, game.juicerValue = 6, 7.5
    local score, totalScore, roundScore, nextUid = game.score, game.totalScore, game.roundScore, game._nextUid
    local rngState, relics = game._rngState, game:Snapshot().relics
    for uid = 1, 6 do assert(game:RemoveItem(uid)) end
    Close(game.removals, 0)
    Close(game.score, score); Close(game.totalScore, totalScore); Close(game.roundScore, roundScore)
    Close(game.juicerValue, 7.5)
    assert(game._nextUid == nextUid and game._rngState == rngState and #game:AllInstances() == 2
        and #game.deck == 2 and #game.discard == 0 and Equal(relics, game.relics))
    Close(Item(game, 8).permBonus, 0)
    assert(not Item(game, 8).generatedTemporary)
    local restored = Game.Restore(game:Snapshot())
    assert(restored:Start())
    Finish(restored)
    assert(restored:Skip())
    for uid = 1, 6 do assert(restored:Get(uid) == nil, "死灵也不能返还主动移除的实例") end
end)

Test("主动移除追杀目标会换合法目标但不触发击杀奖励", function()
    local game = Repair.Fixture({"killer", "student", "doctor", "apple"}, {jungle_hunt=true})
    game.huntTargetUid, game.removals = 2, 3
    local score, mult = game.score, Item(game, 1).permMult
    assert(game:RemoveItem(4) and game.huntTargetUid == 2, "移除无关物品保留稳定追杀目标")
    assert(game:RemoveItem(2) and game.huntTargetUid == 3)
    Close(game.score, score); Close(Item(game, 1).permMult, mult)
    assert(game:RemoveItem(3) and game.huntTargetUid == 0)
    Close(game.score, score); Close(Item(game, 1).permMult, mult)
    Game.Restore(game:Snapshot())
end)

Test("移空牌库仍可保存继续回合并跳过候选", function()
    local game = Fixture({"apple"})
    game.removals = 1
    assert(game:RemoveItem(1) and #game.deck == 0 and #game.drawn == 0)
    local restored = Game.Restore(game:Snapshot())
    assert(#restored:BottleItems() == 0 and restored:Start())
    Finish(restored)
    assert(restored:Skip() and restored.phase == "prepare" and restored.round == 2)
    assert(#restored.deck == 0 and #restored:BottleItems() == 0)
    Close(restored.removals, 0)
    Game.Restore(restored:Snapshot())
end)

---@return integer
function Tests.Run()
    local passed = 0
    ---@type string[]
    local failures = {}
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then passed = passed + 1 else failures[#failures + 1] = case.name .. "：" .. tostring(message) end
    end
    assert(#failures == 0, "Bottle.CoreUpdateTests " .. passed .. "/" .. #cases
        .. " 通过\n" .. table.concat(failures, "\n"))
    return passed
end

return Tests
