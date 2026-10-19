-- 成功生效才进入触发冷却的专项回归。真Game/正式Restore夹具，无引擎/磁盘依赖。
-- 周期失败仍等待原周期；护盾会发事件但主动消费者失败，不用事件数组判成功。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Repair = require("Bottle.RepairTests")
local Effects = require("Bottle.Effects")
local Extra = require("Bottle.ExtraEffects")
local Expansion = require("Bottle.ExpansionEffects")
local Tests = {}

---@param actual any
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (label or "数值") .. " expected=" .. expected .. " actual=" .. tostring(actual))
end
---@param game any
---@param uid number
---@return any
local function Item(game, uid)
    local item = assert(game:Get(uid), "缺少实例" .. uid)
    return item
end
---@param ids string[]
---@param relics table<string,boolean>?
---@return any
local function Fixture(ids, relics)
    local game = Repair.Fixture(ids, relics)
    assert(game:Start())
    return game
end
---@param game any
---@param value integer
---@return fun():integer
local function Constant(game, value)
    local count = 0
    rawset(game, "_RandomInt", function(_, maximum)
        assert(value <= maximum)
        count = count + 1
        return value
    end)
    return function() return count end
end
---@param game any
---@param uid number
local function Ready(game, uid) Close(Item(game, uid).remaining, 0, "失败应保持就绪") end
---@param game any
---@param uid number
local function Cooling(game, uid)
    Close(Item(game, uid).remaining, game:CooldownOf(Item(game, uid).id), "成功才完整冷却")
end

---@type {name:string,run:fun()}[]
Tests.cases = {}
---@param name string
---@param run fun()
local function Test(name, run) Tests.cases[#Tests.cases + 1] = {name=name,run=run} end

Test("旧首批touch无合法目标全保持就绪且正dt不死循环", function()
    for _, id in ipairs({"trash_can","glutton","fruit_ninja","police","thief","teacher",
        "knife","fruit_farmer","diner","chef","killer"}) do
        local game = Fixture({id,"ball"})
        local contacts = {pairs={{1,2}}}
        game:Step(0, contacts); Ready(game, 1)
        game:Step(.2, contacts); Ready(game, 1); Close(game.elapsed, .2)
        game:Step(0, contacts); Ready(game, 1)
    end
end)

Test("Extra与Expansion不合法接触不进冷却", function()
    for _, id in ipairs({"gambler","gambling_god","farmer","droplet","monkey","coffin",
        "tombstone","soul_stone","coin_machine","pig","hay","grass","poop","golden_poop",
        "cactus","chicken_keeper","splitter","jelly","sweater"}) do
        local game = Fixture({id,"ghost"})
        -- 对这些本可接受ghost的类型改用apple，其他用ghost阻止意外规则。
        local other = id == "coffin" or id == "tombstone" or id == "soul_stone" or id == "splitter"
        if other then game:_Transform(Item(game, 2), "apple", {}) end
        game:Step(.25, {pairs={{1,2}}}); Ready(game, 1)
    end
end)

Test("大胃王满体积和小偷零值目标不进冷却", function()
    local glutton = Fixture({"glutton","apple"})
    Item(glutton, 1).scale = 2
    glutton:Step(.5, {pairs={{1,2}}})
    Ready(glutton, 1); assert(Item(glutton, 2).location == "bottle")
    Item(glutton, 1).scale = 1.9
    glutton:Step(0, {pairs={{1,2}}})
    Cooling(glutton, 1); Close(Item(glutton, 1).permBonus, 1)
    local thief = Fixture({"thief","credit_card"})
    Item(thief, 2).permBonus = -10
    thief:Step(.5, {pairs={{1,2}}}); Ready(thief, 1)
    Item(thief, 2).permBonus = -9
    thief:Step(0, {pairs={{1,2}}}); Cooling(thief, 1)
end)

Test("护盾发出金币buff也不使失败杀手冷却", function()
    local game = Fixture({"killer","doctor","bodyguard"})
    local events = game:Step(0, {pairs={{1,2}}})
    assert(Item(game, 2).shielded and #Repair.Events(events, "score", 2) == 1)
    Ready(game, 1); Close(Item(game, 3).counter, 1)
    local retry = game:Step(1, {pairs={{1,2}}})
    Ready(game, 1); assert(#Repair.Events(retry, "score") == 0)
    Close(game.elapsed, 1); Close(Item(game, 3).counter, 1)
end)

Test("消费护盾拦截逐类返回false与保持就绪", function()
    for _, id in ipairs({"trash_can","glutton","police","killer","diner","soul_stone",
        "monkey","pig","cactus","chicken_keeper","sweater","grass","poop","golden_poop"}) do
        local target = id == "police" and "gambler" or id == "killer" and "doctor"
            or id == "soul_stone" and "ghost" or id == "monkey" and "banana"
            or id == "cactus" and "droplet" or id == "chicken_keeper" and "egg"
            or id == "sweater" and "wool" or id == "grass" and "sheep"
            or (id == "poop" or id == "golden_poop") and "apple" or "apple"
        local game = Fixture({id,target})
        if id == "trash_can" then Item(game, 2).temporary = true end
        local sourceConsumesItself = id == "grass" or id == "poop" or id == "golden_poop"
        Item(game, sourceConsumesItself and 1 or 2).shielded = true
        local contacts = game:_ContactSnapshot({pairs={{1,2}}})
        assert(Effects.Apply(game, Item(game, 1), contacts, {}) == false, id)
        game:Step(.25, contacts); Ready(game, 1)
        assert(Item(game, 1).location == "bottle" and Item(game, 2).location == "bottle", id)
    end
end)

Test("部分目标受盾另一目标成功仍冷却整批一次", function()
    local game = Fixture({"trash_can","banana_peel","rotten_banana"})
    Item(game, 2).shielded = true
    local events = game:Step(0, {pairs={{1,2},{1,3}}})
    assert(Item(game, 2).location == "bottle" and Item(game, 3).location == "discard")
    Cooling(game, 1); Close(Item(game, 1).permBonus, 1)
    assert(#Repair.Events(events, "remove") == 1)
end)

Test("失败后新Step有真实目标可立即成功不等伪冷却", function()
    local game = Fixture({"knife","ball","apple"})
    game:Step(.4, {pairs={{1,2}}}); Ready(game, 1)
    game:Step(0, {pairs={{1,3}}})
    Cooling(game, 1); assert(Item(game, 3).id == "apple_half")
end)

Test("首批全部成功分派返回真实效果并设置完整冷却", function()
    for _, row in ipairs({
        {"trash_can","banana_peel"},{"glutton","apple"},{"fruit_ninja","apple"},
        {"police","gambler"},{"thief","credit_card"},{"teacher","student"},
        {"knife","apple"},{"fruit_farmer","apple"},{"diner","apple"},
        {"chef","apple"},{"killer","doctor"},
    }) do
        local game = Fixture(row)
        Constant(game, 1)
        game:Step(0, {pairs={{1,2}}})
        Cooling(game, 1)
    end
    local ball = Fixture({"ball"})
    ball:Step(0, {wall={[1]=true}}); Cooling(ball, 1)
end)

Test("厨师仅成功吃刀也算生效而非必须有水果", function()
    local game = Fixture({"chef","knife"}, {chef_hat=true})
    game:Step(0, {pairs={{1,2}}})
    assert(Item(game, 2).location == "discard"); Cooling(game, 1)
    local blocked = Fixture({"chef","knife"}, {chef_hat=true})
    Item(blocked, 2).shielded = true
    blocked:Step(.5, {pairs={{1,2}}}); Ready(blocked, 1)
end)

Test("刀只碰无库存羊不生效有库存才冷却", function()
    local game = Fixture({"knife","sheep"})
    game:Step(.2, {pairs={{1,2}}}); Ready(game, 1)
    Item(game, 2).woolCount = 1
    game:Step(0, {pairs={{1,2}}}); Cooling(game, 1)
    Close(Item(game, 2).woolCount, 0)
end)

Test("农民已有祝福不重复生效祝福被消费后立即可重施", function()
    local game = Fixture({"farmer","fruit_tree"})
    local contacts = {pairs={{1,2}}}
    game:Step(0, contacts); Cooling(game, 1)
    game:Step(1, contacts); Ready(game, 1)
    assert(Item(game, 2).treeBlessed)
    Item(game, 2).treeBlessed = false
    game:Step(0, contacts); Cooling(game, 1)
end)

Test("赌徒与赌神重投额度用尽不重复冷却不重抽", function()
    for _, id in ipairs({"gambler","gambling_god"}) do
        local game = Fixture({id,"die_d4"})
        local calls = Constant(game, 2)
        local contacts = {pairs={{1,2}}}
        game:Step(0, contacts); Cooling(game, 1); Close(calls(), 1)
        game:Step(1, contacts); Ready(game, 1); Close(calls(), 1)
        game:Step(2, contacts); Ready(game, 1); Close(calls(), 1)
        Item(game, 1).rerolled[2] = nil
        game:Step(0, contacts); Cooling(game, 1); Close(calls(), 2)
    end
end)

Test("周期性概率失败不提前重抽且完整保留5和10秒周期", function()
    local game = Fixture({"lucky_coin","fruit_tree"})
    local calls = Constant(game, 2) -- 幸运硬币与果树都失败。
    local before = game.roundScore
    game:Step(5)
    Close(calls(), 1); Close(Item(game, 1).remaining, 5); Close(Item(game, 2).remaining, 5)
    game:Step(0); Close(calls(), 1)
    game:Step(4.99); Close(calls(), 1)
    game:Step(.01)
    Close(calls(), 3); Close(game.roundScore, before)
    Close(Item(game, 1).remaining, 5); Close(Item(game, 2).remaining, 10)
end)

Test("Crop区别已判定和生效而Apply返回生效", function()
    local game = Fixture({"fruit_tree","seed"})
    Constant(game, 2)
    local state = game:_ContactSnapshot({})
    local attempted, applied = Extra.Crop(game, Item(game, 1), state, {})
    assert(attempted and not applied)
    local seedAttempted, seedApplied = Extra.Crop(game, Item(game, 2), state, {})
    assert(seedAttempted and not seedApplied)
    assert(Extra.Apply(game, Item(game, 1), state, {}) == false)
end)

Test("水珠抽签失败自耗成功仍生效不改果树周期", function()
    local game = Fixture({"droplet","fruit_tree"})
    Constant(game, 2)
    Item(game, 2).remaining = 7
    game:Step(0, {pairs={{1,2}}})
    assert(Item(game, 1).location == "discard"); Close(Item(game, 2).remaining, 7)
end)

Test("满瓶生成真实排队算成功不能以spawn事件为空拒冷却", function()
    local game = Fixture({"coffin","ghost"})
    for _ = 3, 100 do assert(game:_Spawn("apple", {})) end
    local events = game:Step(0, {pairs={{1,2}}})
    Cooling(game, 1)
    assert(#game.spawnQueue == 1 and #Repair.Events(events, "spawn") == 0)
    assert(Item(game, game.spawnQueue[1]).id == "ghost")
end)

Test("所有Expansion成功分支及无邻居失败契约", function()
    for _, row in ipairs({
        {"pig","apple"},{"cactus","droplet"},{"chicken_keeper","egg"},
        {"sweater","wool"},{"splitter","ghost"},{"jelly","apple"},{"hay","sheep"},
    }) do
        local game = Fixture(row)
        Constant(game, 2)
        game:Step(0, {pairs={{1,2}}}); Cooling(game, 1)
    end
    local compass = Fixture({"compass"})
    Item(compass, 1).compassProgress = math.pi*2
    compass:Step(0); Cooling(compass, 1)
    local gecko = Fixture({"gecko"})
    gecko:Step(.25, {side={[1]=true},positions={[1]={x=-2,y=2}}})
    assert(Item(gecko, 1).anchored)
    Close(Item(gecko, 1).remaining, gecko:CooldownOf("gecko") - .25)
    local state = compass:_ContactSnapshot({})
    assert(not Expansion.Apply(compass, Item(compass, 1), state, {}))
end)

Test("成功冷却不受同Step其他失败UID干扰", function()
    local game = Fixture({"knife","ball","tombstone","ghost"})
    game:Step(0, {pairs={{1,2},{3,4}}})
    Ready(game, 1); Cooling(game, 3)
    game:Step(4, {pairs={{1,2},{3,4}}})
    Ready(game, 1); Cooling(game, 3)
    Close(Item(game, 3).permBonus, 2); Close(game.elapsed, 4)
end)

Test("小猪六类主动食物逐件按消费前有效值双倍给金币", function()
    for _, id in ipairs({"apple","orange","enoki","tomato_egg","banana","banana_peel"}) do
        local game = Fixture({"pig",id})
        local target = Item(game, 2)
        target.permBonus, target.permMult = 3, 2
        local expected = game:_Value(target) * 2
        local events = game:Step(0, {pairs={{1,2}},positions={[1]={x=.4,y=2}}})
        Cooling(game, 1)
        Close(game.roundScore, expected)
        Close(Item(game, 1).scale, 1.1); Close(Item(game, 1).weight, 1.1)
        local scores = Repair.Events(events, "score", 1)
        assert(#scores == 1); Close(scores[1].value, expected)
        Close(scores[1].x, .4); Close(scores[1].y, 2)
        local respawns = id == "banana" or id == "enoki" or id == "tomato_egg"
        assert(target.location == (respawns and "bottle" or "discard"))
        if id == "banana" then assert(target.id == "banana_peel") end
    end
end)

Test("小猪整批收益按件相加且香蕉皮可在下一冷却成功吃掉", function()
    local game = Fixture({"pig","apple","orange","banana","banana_peel"})
    ---@type number
    local expected = 0
    for uid = 2, 5 do expected = expected + game:_Value(Item(game, uid)) * 2 end
    local first = game:Step(0, {pairs={{1,2},{1,3},{1,4},{1,5}}})
    Close(game.roundScore, expected)
    assert(#Repair.Events(first, "score", 1) == 4, "每件仅发一次主动消费收益")
    Close(Item(game, 1).scale, 1.4); Close(Item(game, 1).weight, 1.4)
    assert(Item(game, 4).id == "banana_peel" and Item(game, 4).location == "bottle")
    local peelReward = game:_Value(Item(game, 4)) * 2
    local second = game:Step(2, {pairs={{1,4}}})
    Close(game.roundScore, expected + peelReward)
    assert(#Repair.Events(second, "score", 1) == 1 and Item(game, 4).location == "discard")
end)

Test("小猪变培根最后一餐不丢消费前价值奖励且不继续旧批次", function()
    local game = Fixture({"pig","banana","apple"})
    local pig, banana = Item(game, 1), Item(game, 2)
    pig.scale, pig.weight = 1.9, 1.9
    banana.permBonus, banana.permMult = 8, 2
    local expected = game:_Value(banana) * 2
    local events = game:Step(0, {pairs={{1,2},{1,3}}})
    assert(pig.id == "bacon" and Item(game, 3).location == "bottle")
    Close(pig.scale, 2); Close(pig.weight, 2); Close(game.roundScore, expected)
    assert(#Repair.Events(events, "score", 1) == 1)
    assert(banana.id == "banana_peel")
end)

Test("小猪护盾拦截不给金币不增长不冷却且被动吃草不冒领主动奖", function()
    local game = Fixture({"pig","banana_peel"})
    Item(game, 2).shielded = true
    game:Step(.25, {pairs={{1,2}}})
    Ready(game, 1); Close(game.roundScore, 0)
    Close(Item(game, 1).scale, 1); Close(Item(game, 1).weight, 1)
    local grass = Fixture({"pig","grass"})
    Constant(grass, 1)
    grass:Step(0, {pairs={{1,2}}})
    Close(grass.roundScore, 0); Close(Item(grass, 1).scale, 1.1)
    Ready(grass, 1)
end)

Test("小猪重生食物消费前双倍入账且两秒内不能无冷却重吃", function()
    for _, id in ipairs({"enoki","tomato_egg"}) do
        local game = Fixture({"pig",id}, {see_you_tomorrow=true})
        Constant(game, 1)
        local pig, target = Item(game, 1), Item(game, 2)
        target.bonus, target.permBonus, target.permMult = 4, 3, 2
        local firstReward = game:_Value(target) * 2
        local first = game:Step(0, {pairs={{1,2}}})
        Cooling(game, 1); Close(game.roundScore, firstReward)
        Close(pig.scale, 1.1); Close(pig.weight, 1.1)
        assert(target.location == "bottle" and target.id == id)
        assert(#Repair.Events(first, "respawn", 2) == 1)
        assert(#Repair.Events(first, "score", 1) == 1)
        Close(target.bonus, 0)
        Close(target.counter, id == "tomato_egg" and 1 or 0)
        Close(target.permBonus, id == "enoki" and 4 or 3)
        assert(#Repair.Events(game:Step(0, {pairs={{1,2}}}), "score", 1) == 0)
        assert(#Repair.Events(game:Step(1.99, {pairs={{1,2}}}), "score", 1) == 0)
        Close(game.roundScore, firstReward); Close(pig.scale, 1.1)
        local secondReward = game:_Value(target) * 2
        local second = game:Step(.01, {pairs={{1,2}}})
        Cooling(game, 1); Close(game.roundScore, firstReward + secondReward)
        Close(pig.scale, 1.2); Close(pig.weight, 1.2)
        assert(#Repair.Events(second, "respawn", 2) == 1)
        assert(#Repair.Events(second, "score", 1) == 1)
        Close(target.counter, id == "tomato_egg" and 2 or 0)
    end
end)

Test("小猪重生食物受盾失败不成长不奖励解除后立即可吃", function()
    for _, id in ipairs({"enoki","tomato_egg"}) do
        local game = Fixture({"pig",id})
        local calls = Constant(game, 1)
        local target = Item(game, 2)
        target.shielded = true
        local blocked = game:Step(.25, {pairs={{1,2}}})
        Ready(game, 1); Close(game.roundScore, 0); Close(calls(), 0)
        Close(Item(game, 1).scale, 1); Close(Item(game, 1).weight, 1)
        Close(target.counter, 0); assert(#Repair.Events(blocked, "respawn") == 0)
        target.shielded = false
        local expected = game:_Value(target) * 2
        local accepted = game:Step(0, {pairs={{1,2}}})
        Cooling(game, 1); Close(game.roundScore, expected)
        Close(Item(game, 1).scale, 1.1); Close(Item(game, 1).weight, 1.1)
        assert(#Repair.Events(accepted, "respawn", 2) == 1)
    end
end)

Test("小猪炒蛋第五次正常耗尽仍发末餐奖励且不增设来源", function()
    local game = Fixture({"pig","tomato_egg"})
    Constant(game, 1)
    local target = Item(game, 2)
    target.counter, target.bonus = 4, 7
    local expected = game:_Value(target) * 2
    local events = game:Step(0, {pairs={{1,2}}})
    assert(target.location == "discard" and target.counter == 5)
    assert(#Repair.Events(events, "respawn") == 0 and #Repair.Events(events, "remove", 2) == 1)
    Close(game.roundScore, expected); Close(Item(game, 1).scale, 1.1); Cooling(game, 1)
    for _, id in ipairs({"cherry","apple_half","orange_half","tomato","egg","juice","wool"}) do
        local excluded = Fixture({"pig",id})
        excluded:Step(.25, {pairs={{1,2}}})
        Ready(excluded, 1); Close(excluded.roundScore, 0)
        assert(Item(excluded, 2).location == "bottle", id)
        Close(Item(excluded, 1).scale, 1)
    end
end)

Test("四种便便按植物tag被动消费且仅给最早uid植物收益", function()
    for _, id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        for _, plantId in ipairs({"apple","tomato","fruit_tree","cactus"}) do
            local game = Fixture({plantId,"orange",id})
            Constant(game, 2)
            local events = game:Step(0, {pairs={{3,2},{3,1}}})
            assert(Item(game, 3).location == "discard", id .. "/" .. plantId)
            assert(#Repair.Events(events, "remove", 3) == 1)
            local consumer, untouched = Item(game, 1), Item(game, 2)
            local amount = id == "poop" and 1 or id == "golden_poop" and 3 or 0
            Close(consumer.permBonus, amount)
            Close(consumer.permMult, id == "diamond_poop" and 1.2 or 1)
            Close(consumer.eventMult, id == "rainbow_poop" and 1.5 or 1)
            Close(untouched.permBonus, 0); Close(untouched.permMult, 1)
            Close(untouched.eventMult, 1); Close(game.roundScore, 0)
            assert(Items.HasTag(id, "垃圾") and not Items.HasTag(id, "植物"))
        end
    end
end)

Test("高阶便便不把非植物食物或动物当植物且新合法接触立即消费", function()
    for _, id in ipairs({"diamond_poop","rainbow_poop"}) do
        for _, nonplant in ipairs({"egg","enoki","pig"}) do
            local game = Fixture({id,nonplant,"apple"})
            local calls = Constant(game, 2)
            local invalid = game:Step(.25, {pairs={{1,2}}})
            Ready(game, 1); Close(calls(), 0)
            assert(Item(game, 1).location == "bottle" and #Repair.Events(invalid, "remove") == 0)
            local valid = game:Step(0, {pairs={{1,3}}})
            assert(Item(game, 1).location == "discard" and #Repair.Events(valid, "remove", 1) == 1)
        end
    end
end)

Test("钻石永久倍率和彩虹临时倍率叠乘且回合结束只清临时", function()
    local game = Fixture({"apple","diamond_poop","diamond_poop","rainbow_poop","rainbow_poop"})
    Constant(game, 2)
    Item(game, 1).permMult = 2
    game:Step(0, {pairs={{1,2},{1,3},{1,4},{1,5}}})
    Close(Item(game, 1).permMult, 2 * 1.2 * 1.2)
    Close(Item(game, 1).eventMult, 1.5 * 1.5)
    Close(game:_Value(Item(game, 1)), 13, "2×2×1.2²×1.5²=12.96向上取整13")
    game:Finish({})
    Close(Item(game, 1).permMult, 2 * 1.2 * 1.2)
    Close(Item(game, 1).eventMult, 1); Close(Item(game, 1).mult, 1)
    Close(game:_Value(Item(game, 1)), 6, "清临时倍率后2×2×1.2²=5.76向上取整6")
end)

Test("高阶便便自身护盾拦截不发倍率产物或随机数解除后可立即成功", function()
    for _, id in ipairs({"diamond_poop","rainbow_poop"}) do
        local game = Fixture({id,"apple"})
        local calls = Constant(game, 2)
        local poop, plant = Item(game, 1), Item(game, 2)
        poop.shielded = true
        local state = game:_ContactSnapshot({pairs={{1,2}}})
        assert(Effects.Apply(game, poop, state, {}) == false)
        local blocked = game:Step(.25, state)
        Ready(game, 1); Close(calls(), 0)
        Close(plant.permMult, 1); Close(plant.eventMult, 1)
        assert(#Repair.Events(blocked, "remove") == 0 and #Repair.Events(blocked, "spawn") == 0)
        poop.shielded = false
        local applied = game:Step(0, {pairs={{1,2}}})
        assert(poop.location == "discard" and #Repair.Events(applied, "remove", 1) == 1)
        Close(plant.permMult, id == "diamond_poop" and 1.2 or 1)
        Close(plant.eventMult, id == "rainbow_poop" and 1.5 or 1)
        Close(calls(), id == "rainbow_poop" and 1 or 0)
    end
end)

Test("彩虹被植物消费中奖三产物沿满瓶FIFO排队并永久保留", function()
    local game = Fixture({"rainbow_poop","apple"})
    for _ = 3, 100 do assert(game:_Spawn("apple", {})) end
    local earlier = assert(game:_Spawn("orange", {}))
    assert(earlier.location == "queued" and #game.spawnQueue == 1)
    local calls = Constant(game, 1)
    local events = game:Step(0, {pairs={{1,2}}})
    Close(calls(), 4) -- 一次20%抽签与三次瓶顶横坐标，不额外给三件产物重抽。
    Close(Item(game, 2).eventMult, 1.5)
    assert(Item(game, 1).location == "discard" and earlier.location == "bottle")
    local firstSpawns = Repair.Events(events, "spawn")
    assert(#firstSpawns == 1 and firstSpawns[1].uid == earlier.uid)
    assert(#game.spawnQueue == 3)
    ---@type number[]
    local products = {}
    for index, id in ipairs({"poop","golden_poop","diamond_poop"}) do
        local uid = assert(game.spawnQueue[index])
        products[#products + 1] = uid
        local product = Item(game, uid)
        assert(product.id == id and product.location == "queued")
        assert(not product.generatedTemporary and not product.temporary)
        Close(game._queueOrigins[uid].y, 6)
    end
    for uid = 3, 5 do assert(game:_Destroy(uid, false, {})) end
    local drained = game:Step(0, {})
    assert(#game.spawnQueue == 0)
    local spawns = Repair.Events(drained, "spawn")
    assert(#spawns == 3)
    for index, uid in ipairs(products) do
        local spawn = assert(spawns[index], "FIFO产物缺少入场事件")
        assert(spawn.uid == uid and Item(game, uid).location == "bottle")
        Close(spawn.y, 6)
    end
    game:Finish({})
    for _, uid in ipairs(products) do
        assert(Item(game, uid).location == "deck" and not Item(game, uid).generatedTemporary)
    end
end)

---@return integer
function Tests.Run()
    local passed = 0
    for _, case in ipairs(Tests.cases) do
        local ok, message = pcall(case.run)
        assert(ok, "[CooldownTests] " .. case.name .. ": " .. tostring(message))
        passed = passed + 1
    end
    print("[CooldownTests] PASS " .. passed)
    return passed
end
return Tests
