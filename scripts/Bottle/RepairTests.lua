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
            scale=1, weight=1, counter=0, settleCount=0, distance=0,
            eventMult=1, generatedTemporary=false, shielded=false, anchored=false,
            refreshCount=0, woolCount=0, abacusMerges=0, calfDashRemaining=0,
            discusWait=0, compassProgress=0,
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

Case("满瓶生成永久入牌库排队、添加金币只发一次", function()
    local game = T.Fixture({}, {small_savings=true})
    for _ = 1, Items.Settings.bottleLimit do assert(game:_Spawn("apple", {})) end
    local score, total, nextUid = game.score, game.totalScore, game._nextUid
    local events = {}
    local queued = assert(game:_Spawn("apple", events))
    assert(queued.location == "queued" and not queued.generatedTemporary)
    assert(#game:BottleItems() == 100 and #game.deck == 101 and #events == 0)
    assert(#game.spawnQueue == 1 and game.spawnQueue[1] == queued.uid)
    Close(game.score, score + 1); Close(game.totalScore, total + 1)
    assert(game._nextUid == nextUid + 1)
    -- 消耗后补位不算再次获取，不得重复发积少成多。
    assert(game:Start())
    game:Consume(1)
    game:_DrainQueue({})
    Close(game.score, score + 1); Close(game.totalScore, total + 1)
    assert(queued.location == "bottle" and #game.spawnQueue == 0)
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
    Close(game:_Value(juice), 13.5); Close(juice.valueBase, 13.5)
    Close(juice.permBonus, 0); Close(game.juicerValue, 0)
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

Case("真正冷却predicate逐项覆盖93件且不改定义时长", function()
    local active = {
        trash_can=2,glutton=1,fruit_ninja=5,thief=6,
        knife=5,fruit_farmer=8,monkey=5,ball=3,coffin=4,tombstone=4,coin_machine=5,
        pig=2,hay=3,chicken_keeper=3,splitter=4,compass=3,jelly=2.5,
    }
    assert(#Items.list == 93)
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

Case("星星开局就绪、传送后保留内部1秒节流", function()
    local game = T.Fixture({"star"})
    assert(game:Start())
    local contacts = {bottom={[1]=true}}
    Close(Item(game,1).remaining, 0)
    assert(#T.Events(game:Step(0, contacts), "respawn") == 1)
    Close(Item(game,1).remaining, 1)
    Close(Item(game,1).bonus, 1)
    assert(#T.Events(game:Step(0, contacts), "respawn") == 0)
    assert(#T.Events(game:Step(.99, contacts), "respawn") == 0)
    assert(#T.Events(game:Step(.01, contacts), "respawn") == 1)
    Close(Item(game,1).bonus, 2)
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

Case("当前数值在新候选和定义中使用默认值而非同名实例", function()
    local text = require("Bottle.ItemText")
    local game = T.Fixture({"glutton", "glutton", "diner", "tomato_egg"})
    Item(game,1).scale, Item(game,2).scale = 1.5, 1.8
    Item(game,3).counter, Item(game,4).counter = 3, 4
    local before = game:Snapshot()
    assert(text.Effect(game,"glutton"):find("当前：100%",1,true))
    assert(text.Effect(game,"glutton",Item(game,1)):find("当前：150%",1,true))
    assert(text.Effect(game,"glutton",Item(game,2)):find("当前：180%",1,true))
    for _, id in ipairs({"diner", "tomato_egg"}) do
        assert(text.Effect(game,id):find("当前：0",1,true))
    end
    assert(text.Effect(game,"diner",Item(game,3)):find("当前：3",1,true))
    assert(text.Effect(game,"tomato_egg",Item(game,4)):find("当前：4",1,true))
    game.relics.scramble_recipe = true
    local eggText = text.Effect(game,"tomato_egg",Item(game,4))
    assert(eggText:find("被消耗10次",1,true) and eggText:find("当前：4",1,true))
    game.relics.scramble_recipe = nil
    local function Equal(a,b)
        if type(a)~=type(b) then return false end
        if type(a)~="table" then return a==b end
        for key,value in pairs(a) do if not Equal(value,b[key]) then return false end end
        for key in pairs(b) do if a[key]==nil then return false end end
        return true
    end
    assert(Equal(game:Snapshot(),before), "查询文案不得更改状态或消耗随机数")
    for _, def in ipairs(Items.list) do
        assert(not text.Effect(game,def.id):find("当前：x",1,true), def.id)
    end
    assert(Items.byId.glutton.effect:find("当前：100%",1,true), "共享正文也不可泄漏x")
end)

Case("厨师帽消除虚假当前值且保留本次而非累计加成", function()
    local text = Relics.byId.chef_hat.effect
    assert(not text:find("当前：",1,true) and text:find("本次切割产物",1,true), text)
    local game = T.Fixture({"chef", "knife", "apple"}, {chef_hat=true})
    assert(game:Start())
    game:Step(5,{pairs={{1,2},{1,3}}})
    Close(Item(game,3).permBonus,4)
    local apple = assert(game:_Spawn("apple",{}))
    Item(game,1).remaining = 0
    game:Step(0,{pairs={{1,apple.uid}}})
    Close(apple.permBonus,3,"下次切割无小刀不沿用上次额外加成")
end)

Case("物理默认与普通50%到200%边界统一钳制", function()
    local game = T.Fixture({"apple","glutton"})
    local apple, glutton = Item(game,1), Item(game,2)
    Close(apple.scale,1); Close(apple.weight,1)
    local created = game:_Create("ball")
    Close(created.scale,1); Close(created.weight,1)
    apple.scale, apple.weight = .2, 3
    local events = {}
    game:ApplyScale(apple,events)
    Close(apple.scale,.5); Close(apple.weight,2)
    assert(#T.Events(events,"resize",1)==1)
    apple.scale, apple.weight = 4, .1
    game:ApplyWeight(apple,{})
    Close(apple.scale,2); Close(apple.weight,.5)
    glutton.scale=.5; game:ApplyScale(glutton,{})
    Close(glutton.scale,1,"大胃王特殊100%下限")
    game:_Transform(apple,"orange",{})
    Close(apple.scale,1); Close(apple.weight,1)
end)

Case("合法50%与200%物理属性JSON往返及旧档默认100%", function()
    local game = T.Fixture({"apple","bacon"})
    Item(game,1).scale, Item(game,1).weight = .5, 2
    Item(game,2).scale, Item(game,2).weight = 2, .5
    local restored = Game.Restore(cjson.decode(cjson.encode(game:Snapshot())))
    Close(Item(restored,1).scale,.5); Close(Item(restored,1).weight,2)
    Close(Item(restored,2).scale,2); Close(Item(restored,2).weight,.5)
    local old = game:Snapshot()
    for _, saved in ipairs(old.instances) do saved.scale=nil; saved.weight=nil end
    local compatible = Game.Restore(old)
    for _, item in ipairs(compatible.deck) do Close(item.scale,1); Close(item.weight,1) end
end)

Case("物理非法和伪造突破字段不能绕过读档边界", function()
    for _, field in ipairs({"scale","weight"}) do
        for _, value in ipairs({.49,2.01,0,-1,math.huge,-math.huge,0/0}) do
            local snapshot = T.Fixture({"apple"}):Snapshot()
            snapshot.instances[1][field]=value
            snapshot.instances[1].scaleMax=100
            snapshot.instances[1].weightMax=100
            assert(not pcall(Game.Restore,snapshot),field.."非法值不得被接受")
        end
    end
    local snapshot = T.Fixture({"glutton"}):Snapshot()
    snapshot.instances[1].scale=.9
    assert(not pcall(Game.Restore,snapshot),"大胃王读档仍尊重100%下限")
end)

Case("只有可信物品特别说明可以突破通用物理边界", function()
    local def = Items.byId.apple
    local oldMin,oldMax,oldWeightMin,oldWeightMax = def.scaleMin,def.scaleMax,def.weightMin,def.weightMax
    local ok, err = pcall(function()
        -- 测试夹具临时模拟已明示的特殊物品；生产目录不新增突破规则。
        def.scaleMin,def.scaleMax,def.weightMin,def.weightMax = .25,3,.25,3
        local game = T.Fixture({"apple"})
        local item = Item(game,1)
        item.scale,item.weight=.3,2.5
        game:ApplyScale(item,{})
        Close(item.scale,.3); Close(item.weight,2.5)
        local restored=Game.Restore(game:Snapshot())
        Close(Item(restored,1).scale,.3); Close(Item(restored,1).weight,2.5)
    end)
    def.scaleMin,def.scaleMax,def.weightMin,def.weightMax = oldMin,oldMax,oldWeightMin,oldWeightMax
    assert(ok,err)
end)

Case("物理修改默认跨回合保留且运行中存档回滚", function()
    local game=T.Fixture({"apple"})
    assert(game:Start())
    local item=Item(game,1)
    item.scale,item.weight=.75,1.5
    game:ApplyScale(item,{})
    local rollback=Game.Restore(game:Snapshot())
    Close(Item(rollback,1).scale,1); Close(Item(rollback,1).weight,1)
    game:Finish(); Reveal(game)
    Close(item.scale,.75); Close(item.weight,1.5)
    local restored=Game.Restore(game:Snapshot())
    assert(restored:Skip())
    Close(Item(restored,1).scale,.75); Close(Item(restored,1).weight,1.5)
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
