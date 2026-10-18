-- 八项修复的纯规则专项。只使用内存快照，不调用 Storage.Load/Save。
-- 由Tests.Run统一执行，也可独立调用 require("Bottle.RepairTests").Run()。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicEffects = require("Bottle.RelicEffects")
local T = {}

---@param actual number
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(math.abs(actual - expected) < 1e-7,
        (label or "数值") .. ": expected=" .. expected .. " actual=" .. actual)
end

---通过正式 Restore 构造夹具，避免创造时触发 savings 污染基线。
---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
function T.Fixture(ids, relics)
    local snap = Game.New(31):Snapshot()
    snap.instances, snap.deck, snap.discard, snap.drawn = {}, {}, {}, {}
    snap.nextUid, snap.relics = #ids + 1, relics or {}
    for uid, id in ipairs(ids) do
        snap.instances[#snap.instances + 1] = {
            uid=uid, id=id, location="bottle", temporary=false,
            bonus=0, permBonus=0, mult=1, permMult=1, tokenAttempted=false,
            remaining=Items.byId[id].cooldown, bottleRounds=0,
            scale=1, counter=0, settleCount=0, distance=0,
        }
        snap.deck[#snap.deck + 1], snap.drawn[#snap.drawn + 1] = uid, uid
    end
    return Game.Restore(snap)
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid), "缺少测试实例") end

---@param events GameEvent[]
---@param kind string
---@param uid integer?
---@return GameEvent[]
function T.Events(events, kind, uid)
    ---@type GameEvent[]
    local found = {}
    for _, event in ipairs(events) do
        if event.kind == kind and (not uid or event.uid == uid) then found[#found + 1] = event end
    end
    return found
end

---@param game BottleGame
local function Reveal(game)
    game:RevealStep(10)
    assert(game.phase == "draft", "结算展示结束应进入三选一")
end

---@class BottleRepairCase
---@field name string
---@field run fun()
---@type BottleRepairCase[]
T.cases = {}
---@param name string
---@param run fun()
local function Case(name, run) T.cases[#T.cases + 1] = {name=name, run=run} end

Case("积少成多文案明确金币而非物品增值", function()
    local text = Relics.byId.small_savings.effect
    assert(text:find("立即获得1金币", 1, true) and text:find("不增加物品价值", 1, true), text)
end)

Case("GM添加含负值信用卡边界及无遗物对照", function()
    for _, savings in ipairs({false, true}) do
        local game = T.Fixture({}, savings and {small_savings=true,credit_line=true} or {credit_line=true})
        for _, id in ipairs({"apple", "trash_can", "credit_card", "ghost"}) do
            local score, total, roundScore = game.score, game.totalScore, game.roundScore
            assert(game:GmAddItem(id))
            local item = game.deck[#game.deck]
            Close(game.score - score, savings and 1 or 0)
            Close(game.totalScore - total, savings and 1 or 0)
            Close(game.roundScore, roundScore, "沿用积少成多不计入roundScore")
            Close(item.bonus, 0)
            Close(item.permBonus, id == "credit_card" and 15 or 0)
            Close(game:_Value(item), id == "credit_card" and 25 or Items.byId[id].base)
            assert(item.location == "deck", "GM只添加牌库")
        end
        local score, count = game.score, #game.deck
        assert(not game:GmAddItem("unknown_repair_item"))
        Close(game.score, score); assert(#game.deck == count)
        assert(game:Start())
        assert(not game:GmAddItem("apple")); Close(game.score, score)
    end
end)

Case("永久与临时生成各入账一次且不增加产物价值", function()
    local game = T.Fixture({}, {small_savings=true})
    local events = {}
    for _, temporary in ipairs({false, true}) do
        local score, total = game.score, game.totalScore
        local item = assert(game:_Spawn("apple", events, temporary))
        Close(game.score - score, 1); Close(game.totalScore - total, 1)
        Close(game:_Value(item), 2); Close(item.permBonus, 0); Close(game.roundScore, 0)
        assert(item.temporary == temporary and item.location == "bottle")
    end
    assert(#T.Events(events, "spawn") == 2)
end)

Case("满瓶生成原子拒绝不发积少成多金币", function()
    local game = T.Fixture({}, {small_savings=true})
    for _ = 1, Items.Settings.bottleLimit do assert(game:_Spawn("apple", {})) end
    local score, total, nextUid = game.score, game.totalScore, game._nextUid
    assert(game:_Spawn("apple", {}) == nil)
    Close(game.score, score); Close(game.totalScore, total); assert(game._nextUid == nextUid)
end)

Case("合成仅新产物入账与原地转化不入账", function()
    local game = T.Fixture({"coin_1", "coin_1", "banana"}, {small_savings=true})
    assert(game:Start())
    local events = game:Step(0, {pairs={{1,2}}})
    assert(#T.Events(events, "merge") == 1)
    local result = Item(game, T.Events(events, "merge")[1].uid)
    Close(game.score, 1); Close(game.totalScore, 1); Close(game.roundScore, 0)
    Close(result.permBonus, 0); Close(game:_Value(result), 2)
    game:_Transform(Item(game, 3), "banana_peel", {})
    Close(game.score, 1); Close(game:_Value(Item(game, 3)), 1)
    game:Step(0, {pairs={{1,2}}}); Close(game.score, 1)
end)

Case("果汁累计价值与积少成多金币分离且失败不入账", function()
    local game = T.Fixture({}, {small_savings=true,juicer=true})
    game.juicerValue = 13.5
    local ok, _, juice = RelicEffects.UseJuicer(game)
    assert(ok and juice)
    Close(game.score, 1); Close(game.totalScore, 1); Close(game.roundScore, 0)
    Close(game:_Value(juice), 13.5); Close(juice.permBonus, 13.5); Close(game.juicerValue, 0)
    assert(not RelicEffects.UseJuicer(game)); Close(game.score, 1)
    game.juicerValue = 2
    assert(game:Start())
    assert(not RelicEffects.UseJuicer(game)); Close(game.juicerValue, 2); Close(game.score, 1)
end)

Case("重抽读档返还均不重复发添加金币或价值", function()
    local game = T.Fixture({"apple", "orange"}, {small_savings=true})
    assert(game:GmAddItem("ball")); Close(game.score, 1)
    assert(game:Reroll()); assert(not game:Reroll())
    Close(game.score, 1); Close(game.totalScore, 1)
    for _, item in ipairs(game.deck) do Close(item.permBonus, 0) end
    local snap = game:Snapshot()
    local restored = Game.Restore(cjson.decode(cjson.encode(snap)))
    Close(restored.score, 1); Close(restored.totalScore, 1); Close(restored.roundScore, 0)
    for _, item in ipairs(restored.deck) do Close(item.permBonus, 0) end
    assert(restored:Start())
    assert(restored:_Destroy(1, false, {})); assert(restored:_ReturnToDeck(Item(restored, 1)))
    Close(restored.score, 1)
    local rolledBack = Game.Restore(restored:Snapshot())
    Close(rolledBack.score, 1); Close(rolledBack.totalScore, 1)
end)

Case("真正冷却predicate逐项覆盖71件且不改原时长", function()
    local active = {
        trash_can=2,glutton=1,fruit_ninja=5,police=1,thief=6,teacher=1,killer=1,
        knife=5,fruit_farmer=8,diner=1,chef=5,gambler=1,gambling_god=1,
        farmer=1,droplet=1,monkey=5,ball=3,coffin=4,tombstone=4,coin_machine=5,
    }
    assert(#Items.list == 71)
    for _, def in ipairs(Items.list) do
        assert(Items.HasCooldown(def.id) == (active[def.id] ~= nil), def.id .. "冷却predicate不符")
        if active[def.id] then Close(def.cooldown, active[def.id], def.id) end
    end
    assert(not Items.HasCooldown("unknown_repair_item"))
    for _, id in ipairs({"star", "soul_jar", "soul_stone", "ghost"}) do Close(Items.byId[id].cooldown, 1, id) end
    Close(Items.byId.fruit_tree.cooldown, 10)
    Close(Items.byId.cloud.cooldown, 5); Close(Items.byId.lucky_coin.cooldown, 5)
end)

Case("timer保留10秒和5秒原周期不提前触发", function()
    local game = T.Fixture({"cloud", "fruit_tree", "lucky_coin"})
    assert(game:Start())
    local first = game:Step(4.99)
    assert(#T.Events(first, "spawn") == 0 and #T.Events(first, "score") == 0)
    Close(Item(game,1).remaining, .01); Close(Item(game,2).remaining, 5.01)
    local atFive = game:Step(.01)
    assert(#T.Events(atFive, "spawn") == 1, "5秒云朵仅生成一滴水珠")
    Close(Item(game,1).remaining, 5); Close(Item(game,2).remaining, 5)
    game:Step(4.99); Close(Item(game,2).remaining, .01)
    game:Step(.01)
    Close(Item(game,2).remaining, 10); Close(Item(game,1).remaining, 5)
    assert(game.phase == "settle")
end)

Case("星星保持内部1秒节流而非显示修正提频", function()
    local game = T.Fixture({"star"})
    assert(game:Start())
    local contacts = {bottom={[1]=true}}
    assert(#T.Events(game:Step(.99, contacts), "respawn") == 0)
    assert(#T.Events(game:Step(.01, contacts), "respawn") == 1)
    Close(Item(game,1).remaining, 1)
    assert(#T.Events(game:Step(0, contacts), "respawn") == 0)
    assert(#T.Events(game:Step(.99, contacts), "respawn") == 0)
    assert(#T.Events(game:Step(.01, contacts), "respawn") == 1)
    Close(game.score, 0)
end)

Case("气球1到1.9逐回合增长并经JSON读档保持", function()
    local game = T.Fixture({"balloon", "apple"})
    game.score, game.totalScore = 10000, 10000
    for round = 1, 9 do
        assert(game:Start())
        local events = game:Finish()
        Close(Item(game,1).scale, 1 + round * .1)
        assert(#T.Events(events, "resize", 1) == 1 and #T.Events(events, "burst", 1) == 0)
        Reveal(game)
        local restored = Game.Restore(cjson.decode(cjson.encode(game:Snapshot())))
        Close(Item(restored,1).scale, 1 + round * .1)
        assert(restored:Skip())
        if restored.phase == "draft" then assert(restored:Skip()) end
        assert(restored.phase == "prepare")
        game = restored
    end
end)

Case("气球200%爆炸只发一次先burst后remove并正确双倍收益清倍率", function()
    local game = T.Fixture({"balloon", "apple", "ball"})
    Item(game,1).scale = 1.9
    assert(game:Start())
    local events = game:Finish()
    local bursts, removes = T.Events(events, "burst", 1), T.Events(events, "remove", 1)
    assert(#bursts == 1 and #removes == 1 and bursts[1].id == "balloon")
    Close(bursts[1].value, 2); Close(Item(game,1).scale, 2)
    local burstIndex, removeIndex = 0, 0
    for index, event in ipairs(events) do
        if event.kind == "burst" then burstIndex = index end
        if event.kind == "remove" and event.uid == 1 then removeIndex = index end
    end
    assert(burstIndex < removeIndex)
    Close(game.score, 6); Close(game.totalScore, 6); Close(game.lastRoundScore, 6)
    assert(#T.Events(events, "score", 1) == 0, "爆掉的气球不重复结算本体")
    assert(Item(game,1).location == "discard" and #game.deck == 2)
    for _, item in ipairs(game:AllInstances()) do Close(item.mult, 1) end
    assert(#game:Finish() == 0 and #game:SettleStep(2) == 0)
    Close(game.score, 6)
    Reveal(game)
    local restored = Game.Restore(cjson.decode(cjson.encode(game:Snapshot())))
    assert(Item(restored,1).location == "discard"); Close(Item(restored,1).scale, 2)
    assert(restored:Skip()); assert(restored:Get(1) == nil)
    assert(restored:Start()); restored:Finish(); Close(restored.lastRoundScore, 3)
end)

Case("气球摇晃中读档回滚scale且不提前爆炸", function()
    local game = T.Fixture({"balloon", "apple"})
    Item(game,1).scale = 1.9
    assert(game:Start()); game:Finish()
    local restored = Game.Restore(game:Snapshot())
    assert(restored.phase == "prepare")
    Close(Item(restored,1).scale, 1.9); Close(restored.score, 0)
    assert(restored:Start())
    assert(#T.Events(restored:Finish(), "burst", 1) == 1)
end)

Case("骰子score事件携带实际点数且赌徒重投不混用有效价值", function()
    local game=T.Fixture({"die_d4","die_d6","gambler"})
    assert(game:Start())
    for _,event in ipairs(T.Events(game.startEvents,"score")) do
        assert(event.rollValue==Item(game,event.uid).rollValue,"开局score携带真实点数")
    end
    local d4,d6=Item(game,1),Item(game,2)
    d4.permBonus,d4.permMult=20,2
    d6.permBonus,d6.permMult=30,3
    Item(game,3).remaining=0
    local events=game:Step(0,{pairs={{1,3},{2,3}}})
    assert(#T.Events(events,"score",1)==1 and #T.Events(events,"score",2)==1)
    for _,uid in ipairs({1,2}) do
        local event=T.Events(events,"score",uid)[1]
        assert(event.rollValue==Item(game,uid).rollValue)
        assert(event.value>event.rollValue,"价值加成不能代替骰面点数")
    end
    local finalD4,finalD6=d4.rollValue,d6.rollValue
    local settled=game:Finish()
    assert(T.Events(settled,"score",1)[1].rollValue==finalD4)
    assert(T.Events(settled,"score",2)[1].rollValue==finalD6)
    assert(d4.rollValue==nil and d6.rollValue==nil,"回合cleanup清临时点数")
end)

---@return integer
function T.Run()
    local passed = 0
    for _, case in ipairs(T.cases) do
        local ok, message = pcall(case.run)
        assert(ok, "[RepairTests] " .. case.name .. ": " .. tostring(message))
        passed = passed + 1
    end
    return passed
end
return T
