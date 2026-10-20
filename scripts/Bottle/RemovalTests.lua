-- 主动移除与移除币规则专项；只用内存快照，不读写玩家存档。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Repair = require("Bottle.RepairTests")
local Expansion = require("Bottle.ExpansionEffects")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}
local function Case(name, run) cases[#cases+1] = {name=name,run=run} end
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid)) end
---@param game BottleGame
local function Finish(game)
    assert(game:Start())
    game:Finish()
    game:RevealStep(100)
end

Case("新局0次、无次数失败不修改任何快照字段", function()
    local game = Game.New(21)
    assert(game.removals == 0 and game:Snapshot().removals == 0)
    local before = game:Snapshot()
    assert(not game:CanRemoveOwned(game.deck[1].uid))
    assert(not game:RemoveOwned(game.deck[1].uid))
    assert(Equal(before, game:Snapshot()))
end)

Case("按UID移除一件永久成长物品、不补抽不改变同名实例", function()
    local game = Repair.Fixture({"apple","apple","ball"})
    game.removals = 2
    local removed, survivor = Item(game,1), Item(game,2)
    removed.permBonus, survivor.permBonus, survivor.permMult = 9, 17, 2
    local rng, nextUid, refreshes = game._rngState, game._nextUid, game.refreshes
    assert(game:CanRemoveOwned(1) and game:RemoveOwned(1))
    assert(game:Get(1) == nil and removed.location == "removed" and #game.discard == 0)
    assert(#game.deck == 2 and #game.drawn == 2 and #game:BottleItems() == 2)
    assert(game.drawn[1] == 2 and game.drawn[2] == 3 and game:Get(2) == survivor)
    assert(survivor.permBonus == 17 and survivor.permMult == 2)
    assert(game.removals == 1 and game.refreshes == refreshes and game._rngState == rng and game._nextUid == nextUid)
    local before = game:Snapshot()
    assert(not game:RemoveOwned(1) and Equal(before, game:Snapshot()))
    local restored = Game.Restore(before)
    assert(not restored:Get(1) and Item(restored,2).permBonus == 17 and restored.removals == 1)
    assert(game:Start()); game:Finish(); game:RevealStep(100); assert(game:Skip())
    assert(not game:Get(1), "跨回合不得复活被主动移除的UID")
end)

Case("移除不触发香蕉变皮、幽灵金币、金针菇重生或水果遗物", function()
    local game = Repair.Fixture({"banana","ghost","enoki","apple","necromancer"},
        {gm_fruit=true,see_you_tomorrow=true,small_savings=true})
    game.removals = 4
    local rng, score, nextUid = game._rngState, game.score, game._nextUid
    for uid = 1, 4 do assert(game:RemoveOwned(uid)) end
    assert(game.score == score and game._rngState == rng and game._nextUid == nextUid)
    assert(#game.discard == 0 and #game:AllInstances() == 1)
    Finish(game)
    assert(#game.deck == 1 and not game:Get(1) and not game:Get(2) and not game:Get(3) and not game:Get(4),
        "死灵不能返还未入弃牌的主动移除物")
end)

Case("running/settle/reveal/over阶段与非拥有实例都拒绝且不扣", function()
    local game = Repair.Fixture({"apple"})
    game.removals = 3
    for _, phase in ipairs({"running","settle","reveal","over"}) do
        game.phase = phase
        local revision, rng = game.revision, game._rngState
        assert(not game:RemoveOwned(1) and game.removals == 3 and game.revision == revision and game._rngState == rng)
    end
    game.phase = "prepare"
    for _, uid in ipairs({0,-1,1.5,999}) do
        assert(not (game --[[@as any]]):RemoveOwned(uid) and game.removals == 3)
    end
    local item = Item(game,1)
    for _, location in ipairs({"discard","queued","consumed","removed"}) do
        item.location = location
        assert(not game:RemoveOwned(1) and game.removals == 3)
    end
    item.location = "deck"; game.deck = {}
    assert(not game:RemoveOwned(1) and game.removals == 3)
end)

Case("物品/遗物draft均能移除拥有物品且候选保持原样", function()
    for _, relicDraft in ipairs({false,true}) do
        local game = Repair.Fixture({"apple","banana"})
        Finish(game)
        game.removals, game.relicDraft = 1, relicDraft
        game.relicRefreshes = relicDraft and 1 or 0
        game.options = relicDraft and game:_RelicDraftOptions() or game:_DraftOptions()
        local options, rng = table.concat(game.options,","), game._rngState
        assert(game:RemoveOwned(1) and game.removals == 0)
        assert(table.concat(game.options,",") == options and game._rngState == rng)
        assert(not Game.Restore(game:Snapshot()):Get(1))
    end
end)

Case("移除追杀目标只维护引用、不触发杀手倍率奖励", function()
    local game = Repair.Fixture({"student","student","killer"})
    game.relics.jungle_hunt, game.huntTargetUid, game.removals = true, 1, 1
    assert(game:RemoveOwned(1) and game.huntTargetUid == 2 and Item(game,3).permMult == 1)
    assert(Game.Restore(game:Snapshot()).huntTargetUid == 2)
end)

Case("第5和10回合各仅奖励1次、累计、失败考核不奖", function()
    local game = Repair.Fixture({"apple"})
    game.score = 10000
    for round = 1, 10 do
        assert(game.round == round)
        Finish(game)
        local expected = math.floor(round / 5)
        assert(game.removals == expected, "考核次数奖励错误 round=" .. round)
        game:RevealStep(100); game:_FinishReveal()
        assert(game.removals == expected, "重复结束展示不重复发奖")
        if game.pendingRelicDraft then
            assert(game:Skip() and game.relicDraft and game.removals == expected)
        end
        assert(game:Skip() and game.phase == "prepare" and game.removals == expected)
    end
    local failed = Repair.Fixture({})
    failed.round = 5
    Finish(failed)
    assert(failed.phase == "over" and failed.removals == 0)
end)

Case("新7/8严格移除次数校验、旧nil/5/6缺字段补0不追溯", function()
    local valid = Game.New(51):Snapshot()
    valid.round, valid.stage, valid.target = 16, 4, Game.GetTarget(4)
    for _, rules in ipairs({false,5,6}) do
        local legacy = Game.Restore(valid):Snapshot()
        legacy.rulesVersion, legacy.removals = rules or nil, nil
        local restored = Game.Restore(legacy)
        assert(restored.removals == 0 and restored.round == 16 and restored:Snapshot().rulesVersion == 8)
    end
    valid.removals = 7
    assert(Game.Restore(valid).removals == 7)
    for _, value in ipairs({false,true,-1,1.5,"2",{},math.huge,-math.huge,0/0}) do
        (valid --[[@as table]]).removals = value
        assert(not pcall(Game.Restore,valid), "损坏移除次数被接受")
    end
    valid.removals = nil
    for _, rules in ipairs({7,8}) do
        valid.rulesVersion = rules
        assert(not pcall(Game.Restore,valid), "rules7/8缺移除次数必须拒绝")
    end
end)

Case("回滚包括已花移除次数与UID注销、运行中新增机会回退", function()
    local game = Repair.Fixture({"apple","removal_coin"})
    game.removals = 2
    assert(game:RemoveOwned(1))
    local before = game:Snapshot()
    assert(game:Start())
    assert(Equal(before, game:Snapshot()))
    game:Step(10)
    assert(game.phase == "settle" and Equal(before,game:Snapshot()))
    game:SettleStep(2)
    assert(game.phase == "reveal" and game.removals == 3 and Equal(before,game:Snapshot()))
    local restored = Game.Restore(game:Snapshot())
    assert(restored.removals == 1 and not restored:Get(1) and restored:Get(2))
    game:RevealStep(100)
    assert(Game.Restore(game:Snapshot()).removals == 3)
end)

Case("移除币目录98、先全体收益再自耗、普通弃牌生命周期与重复守卫", function()
    local def = assert(Items.byId.removal_coin)
    assert(def.numberId == 98 and def.base == 4 and def.rarity == 2 and def.pool
        and def.trigger == "none" and def.cooldown == 0 and not def.unique and #(def.tags or {}) == 0)
    local game = Repair.Fixture({"removal_coin","apple"})
    assert(game:Start())
    local events = game:Finish()
    assert(game.removals == 2 and game.roundScore == 6 and #game.discard == 1 and Item(game,1).location == "discard")
    local removeIndex, lastScoreIndex = 0, 0
    for index, event in ipairs(events) do
        if event.kind == "score" then lastScoreIndex = index end
        if event.kind == "remove" and event.uid == 1 then removeIndex = index end
    end
    assert(removeIndex > lastScoreIndex and lastScoreIndex > 0)
    Expansion.AfterSettle(game,{})
    assert(game.removals == 2, "已弃牌移除币不能再领奖")
    game:RevealStep(100)
    assert(Game.Restore(game:Snapshot()).removals == 2)
    assert(game:Skip() and not game:Get(1) and game.removals == 2)
end)

Case("移除币被护盾拦截或提前被耗不奖、临时产物结算后彻底删除", function()
    local blocked = Repair.Fixture({"removal_coin"})
    assert(blocked:Start()); Item(blocked,1).shielded = true
    blocked:Finish()
    assert(blocked.removals == 0 and Item(blocked,1).location == "deck")
    local eaten = Repair.Fixture({"removal_coin"})
    assert(eaten:Start()); assert(eaten:_Destroy(1,false,{})); eaten:Finish()
    assert(eaten.removals == 0)
    local temporary = Repair.Fixture({})
    assert(temporary:Start())
    local coin = temporary:_Spawn("removal_coin",{},true)
    temporary:Finish()
    assert(temporary.removals == 2 and not temporary:Get(coin.uid) and #temporary.discard == 0)
end)

Case("满瓶排队移除币未入瓶不结算、不自耗领奖", function()
    local game = Repair.Fixture({})
    assert(game:Start())
    for _ = 1, Items.Settings.bottleLimit do game:_Spawn("apple",{}) end
    local coin = game:_Spawn("removal_coin",{})
    assert(coin.location == "queued")
    game:Finish()
    assert(game.removals == 0 and coin.location == "deck" and game:Get(coin.uid) == coin)
end)

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.RemovalTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end
return Tests
