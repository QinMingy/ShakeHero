-- #71-93 确定性规则回归。真实 Game 核心夹具，不创建引擎对象、不读写文件。
-- 接触为纯 Lua 输入；物理轨迹/图案仍由独立运行时验收负责。
local Items = require("Bottle.Items")
local Game = require("Bottle.Game")
local Expansion = require("Bottle.ExpansionEffects")
local Effects = require("Bottle.Effects")
local Tests = {}
local TURN = math.pi * 2

---@param actual any
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        string.format("%s：期望%g，实际%s", label or "数值", expected, tostring(actual)))
end

---@param ids string[]
---@return any
local function Fixture(ids)
    local game = Game.New(71593) --[[@as any]]
    game._instances, game.deck, game.discard, game.drawn = {}, {}, {}, {}
    game._lastPositions, game._nextUid = {}, 1
    game.score, game.totalScore, game.roundScore = 0, 0, 0
    game.phase, game.elapsed = "running", 0
    for _, id in ipairs(ids) do
        local item = game:_Create(id)
        item.location, item.remaining = "bottle", 0
        game.drawn[#game.drawn + 1] = item.uid
    end
    return game
end

---@param game any
---@param uid integer
---@return any
local function Item(game, uid) return assert(game:Get(uid), "缺少实例：" .. uid) end

---@param pairsInput number[][]?
---@return any
local function Contacts(pairsInput)
    return { pairs = pairsInput or {}, positions = {}, side = {}, angles = {},
        angularTravel = {}, rotateOffsets = {}, flightHits = {}, flightArrived = {},
        wall = {}, bottom = {}, top = {} }
end

---@param game any
---@param values integer[]
local function Sequence(game, values)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local value = assert(values[index], "随机序列耗尽")
        assert(value >= 1 and value <= maximum, "随机序列超范围")
        return value
    end)
end

---@param game any
---@param value integer
local function Constant(game, value)
    rawset(game, "_RandomInt", function(_, maximum) return math.min(maximum, value) end)
end

---@param game any
---@param id string
---@param location string?
---@return any[]
local function Find(game, id, location)
    local found = {}
    for _, item in ipairs(game:AllInstances()) do
        if item.id == id and (not location or item.location == location) then found[#found + 1] = item end
    end
    return found
end

---@param events any[]
---@param kind string
---@return any[]
local function Events(events, kind)
    local found = {}
    for _, event in ipairs(events) do if event.kind == kind then found[#found + 1] = event end end
    return found
end

local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = { name = name, run = run } end

Test("新增23类型、编号、tag与穿透属性", function()
    local ids = { "chick", "sheep", "pig", "calf", "grass", "hay", "poop", "golden_poop",
        "diamond_poop", "rainbow_poop", "gecko", "cactus", "abacus", "bodyguard", "chicken_keeper",
        "splitter", "juice", "discus_athlete", "discus", "compass", "jelly", "wool", "sweater" }
    assert(#Items.list == 98)
    for index, id in ipairs(ids) do
        assert(Items.byId[id].numberId == 70 + index and Items.byId[id].implemented, "编号/实装错：" .. id)
    end
    for _, id in ipairs({ "poop", "golden_poop", "diamond_poop", "rainbow_poop" }) do
        assert(Items.HasTag(id, "垃圾"), "便便按垃圾tag")
    end
    assert(Items.byId.ghost.piercing and Items.byId.discus.piercing)
end)

Test("新建与回合清理只清临时状态", function()
    local item = { id = "pig", scale = 1.6, weight = 1.4, permBonus = 8, permMult = 1.2,
        counter = 2, refreshCount = 3, valueBase = 7 }
    Expansion.ResetRound(item)
    Close(item.scale, 1.6); Close(item.weight, 1.4); Close(item.permBonus, 8)
    Close(item.permMult, 1.2); Close(item.refreshCount, 3); Close(item.valueBase, 7)
    Expansion.InitItem(item)
    assert(item.valueBase == nil and item.refreshCount == 0 and item.cactusScale == nil)
    assert(item.shielded == false and item.calfDashHits == nil)
end)

Test("Touches不抢旧规则并区分便便合法touch与纯被动类型", function()
    local game = Fixture({ "apple", "diamond_poop", "calf", "wool", "rainbow_poop" })
    local contacts = Contacts({ { 1, 2 }, { 3, 4 }, { 1, 5 } })
    assert(Expansion.Touches(game, Item(game, 1), contacts) == nil)
    for _, uid in ipairs({ 2, 5 }) do
        assert(Expansion.Touches(game, Item(game, uid), contacts) == true)
    end
    for uid = 3, 4 do assert(Expansion.Touches(game, Item(game, uid), contacts) == false) end
end)

Test("小鸡每5秒判定30%产永久鸡蛋、不在零时刻生成", function()
    local game = Fixture({ "chick" })
    Constant(game, 30)
    Item(game, 1).remaining = 5
    game:Step(4.9, Contacts())
    assert(#Find(game, "egg") == 0)
    game:Step(0.1, Contacts())
    local eggs = Find(game, "egg")
    assert(#eggs == 1 and not eggs[1].temporary and not eggs[1].generatedTemporary
        and eggs[1].location == "bottle")
    Close(Item(game, 1).remaining, 5)
end)

Test("小鸡百分签完整覆盖恰好30个成功签，其余不产蛋", function()
    local successes = 0
    for ticket = 1, 100 do
        local game = Fixture({ "chick" })
        Sequence(game, { ticket })
        local events = {}
        local applied = Expansion.Apply(game, Item(game, 1), Contacts(), events)
        local expected = ticket <= 30
        assert(applied == expected, "小鸡概率边界错误：" .. ticket)
        assert(#Find(game, "egg") == (expected and 1 or 0))
        assert(#Events(events, "spawn") == (expected and 1 or 0))
        if applied then successes = successes + 1 end
    end
    assert(successes == 30)
end)

Test("小鸡判定失败仍续5秒，不在零步或期间逐帧重抽", function()
    local game = Fixture({ "chick" })
    local calls = 0
    rawset(game, "_RandomInt", function(_, maximum)
        assert(maximum == 100 and calls < 2, "小鸡只应在5秒与10秒各判定一次")
        calls = calls + 1
        return calls == 1 and 31 or 30
    end)
    Item(game, 1).remaining = 5
    game:Step(5, Contacts())
    assert(calls == 1 and #Find(game, "egg") == 0)
    Close(Item(game, 1).remaining, 5)
    for _ = 1, 10 do game:Step(0, Contacts()) end
    for _ = 1, 49 do game:Step(.1, Contacts()) end
    game:Step(.09, Contacts())
    assert(calls == 1 and #Find(game, "egg") == 0)
    game:Step(.01, Contacts())
    assert(calls == 2 and #Find(game, "egg", "bottle") == 1)
    assert(game.phase == "settle", "10秒端点仍应判定产蛋")
end)

Test("运行中新生小鸡从实际入瓶后完整等待5秒", function()
    local game = Fixture({ "apple" })
    game:Step(4, Contacts())
    local chick = game:_Spawn("chick", {}, false, {x=.2,y=3})
    assert(chick.location == "bottle")
    Close(chick.remaining, 5)
    Sequence(game, { 1 })
    game:Step(4.99, Contacts())
    assert(#Find(game, "egg") == 0)
    local events = game:Step(.01, Contacts())
    assert(#Find(game, "egg", "bottle") == 1 and #Events(events, "spawn") == 1)
end)

Test("小鸡成功产蛋保持近源永久生成，满瓶按FIFO排队不丢失", function()
    local ids = { "chick" }
    for _ = 2, 100 do ids[#ids + 1] = "apple" end
    local game = Fixture(ids)
    local chick = Item(game, 1)
    local contacts = Contacts()
    contacts.positions[1] = {x=.2,y=3}
    Sequence(game, { 1 })
    chick.remaining = 5
    local events = game:Step(5, contacts)
    local eggs = Find(game, "egg")
    assert(#eggs == 1 and eggs[1].location == "queued" and #game:BottleItems() == 100)
    assert(not eggs[1].temporary and not eggs[1].generatedTemporary)
    assert(#game.spawnQueue == 1 and game.spawnQueue[1] == eggs[1].uid)
    assert(#Events(events, "spawn") == 0, "排队期间不提前生成物理实体")
    Close(chick.remaining, 5, "进入队列也属于成功产蛋")
    assert(game:_Destroy(2, false, {}, nil, "self"))
    local entered = Events(game:Step(0, Contacts()), "spawn")
    assert(eggs[1].location == "bottle" and #game.spawnQueue == 0 and #entered == 1)
    Close(entered[1].x, .2); Close(entered[1].y, 3)
end)

Test("草只选相邻最早uid动物，不选人类或远处动物", function()
    local game = Fixture({ "pig", "sheep", "doctor", "grass", "calf" })
    local contacts = Contacts({ { 4, 3 }, { 4, 2 }, { 4, 1 } })
    Constant(game, 1)
    assert(Expansion.Apply(game, Item(game, 4), contacts, {}))
    Close(Item(game, 1).scale, 1.1)
    Close(Item(game, 1).weight, 1.1)
    assert(Item(game, 4).location == "discard" and #Find(game, "wool") == 0)
end)

Test("草产物概率全部边界确定性覆盖", function()
    local checks = { { 1, "" }, { 40, "" }, { 41, "poop" }, { 80, "poop" },
        { 81, "golden_poop" }, { 95, "golden_poop" }, { 96, "diamond_poop" },
        { 99, "diamond_poop" }, { 100, "rainbow_poop" } }
    for _, check in ipairs(checks) do
        local game = Fixture({ "doctor", "grass" })
        Sequence(game, { check[1] })
        assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
        if check[2] == "" then assert(#game:BottleItems() == 1)
        else assert(#Find(game, check[2], "bottle") == 1) end
    end
end)

Test("羊吃草额外独立抽一次产物并50%积攒永久羊毛库存", function()
    local game = Fixture({ "sheep", "grass" })
    Sequence(game, { 41, 96, 1 })
    assert(Expansion.Apply(game, Item(game, 2), Contacts({ { 1, 2 } }), {}))
    assert(#Find(game, "poop", "bottle") == 1 and #Find(game, "diamond_poop", "bottle") == 1)
    Close(Item(game, 1).woolCount, 1)
    assert(#Find(game, "wool") == 0, "吃草只积毛，不提前生成")
    Expansion.ResetRound(Item(game, 1))
    Close(Item(game, 1).woolCount, 1, "库存跨回合保留")
end)

Test("羊毛概率失败不生成、人类只抽一次草产物", function()
    local game = Fixture({ "sheep", "grass" })
    Sequence(game, { 40, 40, 2 })
    assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
    assert(#game:BottleItems() == 1)
    local human = Fixture({ "glutton", "grass" })
    Sequence(human, { 100 })
    assert(human:_Destroy(2, false, {}, Item(human, 1), "consume"))
    assert(#Find(human, "rainbow_poop", "bottle") == 1)
end)

Test("草堆每批只扣1且每动物一草立即消费", function()
    local game = Fixture({ "hay", "pig", "calf", "doctor" })
    Constant(game, 1)
    assert(Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 4 }, { 1, 3 }, { 1, 2 } }), {}))
    Close(Item(game, 1).permBonus, -1)
    assert(#Find(game, "grass", "discard") == 2)
    Close(Item(game, 2).scale, 1.1)
    Close(Item(game, 3).calfDashRemaining, 0.35)
end)

Test("草堆价值耗尽自耗、幸运符改扣为加", function()
    local game = Fixture({ "hay", "rabbit" })
    Constant(game, 1)
    Item(game, 1).permBonus = -4
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 } }), {})
    assert(Item(game, 1).location == "discard")
    local lucky = Fixture({ "hay", "rabbit" })
    lucky.relics.lucky_charm = true
    Constant(lucky, 1)
    Expansion.Apply(lucky, Item(lucky, 1), Contacts({ { 1, 2 } }), {})
    Close(Item(lucky, 1).permBonus, 1)
end)

Test("满瓶草排队不预消费、入瓶再喂指定动物", function()
    local ids = { "hay", "pig" }
    for _ = 3, 100 do ids[#ids + 1] = "apple" end
    local game = Fixture(ids)
    Constant(game, 1)
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 } }), {})
    local grass = Find(game, "grass")[1]
    assert(grass.location == "queued" and grass.pendingConsumerUid == 2)
    Close(Item(game, 2).scale, 1)
    -- 直接移出一个非关联占位物，验证OnEnter本身，不依赖队列调度内部实现。
    Item(game, 100).location = "discard"
    grass.location = "bottle"
    Expansion.OnEnter(game, grass, {})
    assert(grass.location == "discard" and grass.pendingConsumerUid == nil)
    Close(Item(game, 2).scale, 1.1)
end)

Test("排队草目标离场不擅自喂其他动物", function()
    local game = Fixture({ "grass", "pig", "sheep" })
    Item(game, 1).pendingConsumerUid = 2
    Item(game, 2).location = "discard"
    Expansion.OnEnter(game, Item(game, 1), {})
    assert(Item(game, 1).location == "bottle" and Item(game, 1).pendingConsumerUid == nil)
end)

Test("普通黄金便便由植物消费、永久加值和20%额外", function()
    for _, check in ipairs({ { "poop", 1 }, { "golden_poop", 3 } }) do
        local game = Fixture({ check[1], "apple", "pig" })
        Constant(game, 1)
        assert(Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 3 }, { 1, 2 } }), {}))
        Close(Item(game, 2).permBonus, check[2] * 2)
        Close(Item(game, 3).permBonus, 0)
        Expansion.ResetRound(Item(game, 2))
        Close(Item(game, 2).permBonus, check[2] * 2)
    end
end)

Test("便便20%失败只加基础、垃圾桶仍得消费钩子", function()
    local game = Fixture({ "trash_can", "golden_poop" })
    Constant(game, 2)
    assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
    Close(Item(game, 1).permBonus, 3)
end)

Test("钻石彩虹仅被相邻植物tag目标自动消费", function()
    local game = Fixture({ "apple", "diamond_poop", "rainbow_poop", "egg" })
    local plants = Contacts({ { 1, 2 }, { 1, 3 } })
    local foodOnly = Contacts({ { 4, 2 }, { 4, 3 } })
    for _, uid in ipairs({ 2, 3 }) do
        assert(Expansion.Touches(game, Item(game, uid), plants) == true)
        assert(Expansion.Touches(game, Item(game, uid), foodOnly) == false)
        assert(Items.byId[Item(game, uid).id].effect:find("被相邻植物消耗", 1, true))
    end
end)

Test("钻石永久倍率和彩虹临时倍率独立", function()
    local game = Fixture({ "trash_can", "diamond_poop", "rainbow_poop" })
    Constant(game, 2)
    assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
    assert(game:_Destroy(3, false, {}, Item(game, 1), "consume"))
    Close(Item(game, 1).permMult, 1.2)
    Close(Item(game, 1).eventMult, 1.5)
    Close(Item(game, 1).mult, 1.5)
    Expansion.ResetRound(Item(game, 1))
    Close(Item(game, 1).permMult, 1.2); Close(Item(game, 1).eventMult, 1)
end)

Test("彩虹20%瓶顶永久生成三种便便", function()
    local game = Fixture({ "trash_can", "rainbow_poop" })
    Constant(game, 1)
    local events = {}
    assert(game:_Destroy(2, false, events, Item(game, 1), "consume"))
    local spawns = Events(events, "spawn")
    assert(#spawns == 3)
    for _, event in ipairs(spawns) do Close(event.y, 6) end
    for _, id in ipairs({ "poop", "golden_poop", "diamond_poop" }) do
        assert(#Find(game, id, "bottle") == 1 and not Find(game, id)[1].temporary)
    end
end)

Test("壁虎侧壁连续延迟后只锚定一次，底顶不触发", function()
    local game = Fixture({ "gecko" })
    local contacts = Contacts()
    contacts.bottom[1], contacts.top[1], contacts.wall[1] = true, true, true
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    contacts.side[1], contacts.positions[1] = true, { x = 2, y = 3 }
    local events = {}
    assert(not Expansion.Apply(game, Item(game, 1), contacts, events), "不能瞬间锚定")
    Expansion.Step(game, 0.24, contacts, events)
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    Expansion.Step(game, 0.01, contacts, events)
    assert(Expansion.Apply(game, Item(game, 1), contacts, events))
    assert(#Events(events, "anchor") == 1 and Item(game, 1).anchored)
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    Expansion.ResetRound(Item(game, 1))
    assert(not Item(game, 1).anchored)
end)

Test("仙人掌吃水珠按实际尺寸临时加倍率、上限不超收且旧永久倍率保留", function()
    local game = Fixture({ "cactus", "droplet", "droplet" })
    Item(game, 1).scale, Item(game, 1).permMult = 1.95, 1.5
    local events = {}
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 }, { 1, 3 } }), events)
    Close(Item(game, 1).scale, 2)
    Close(Item(game, 1).cactusBonus, .05)
    Close(Item(game, 1).permMult, 1.5)
    Close(game:_Value(Item(game, 1)), 4 * 1.55, "旧永久倍率与本回合加数相加而非连乘")
    assert(Item(game, 2).location == "discard" and Item(game, 3).location == "discard")
    local settled = game:Finish()
    Close(Events(settled, "score")[1].value, 4 * 1.55)
    Close(Item(game, 1).cactusBonus, 0)
    Close(Item(game, 1).scale, 2)
    Close(Item(game, 1).permMult, 1.5)
    game:RevealStep(100)
    local restored = Game.Restore(game:Snapshot())
    Close(Item(restored, 1).scale, 2)
    Close(Item(restored, 1).permMult, 1.5, "旧存量倍率不得因新规则剥离")
    Close(restored:_Value(Item(restored, 1)), 6)
    for _,rules in ipairs({"nil",5,6}) do
        local legacy = game:Snapshot() --[[@as any]]
        if rules == "nil" then legacy.rulesVersion = nil else legacy.rulesVersion = rules end
        local migrated = Game.Restore(legacy)
        Close(Item(migrated, 1).permMult, 1.5, "旧档已有仙人掌永久倍率不追溯剥离")
        Close(Item(migrated, 1).scale, 2)
        Close(Item(migrated, 1).cactusBonus, 0)
        Close(migrated:_Value(Item(migrated, 1)), 6)
        assert(migrated:Snapshot().rngState == legacy.rngState)
    end
    assert(restored:Skip() and restored:Start())
    restored:Step(0, Contacts())
    Close(Item(restored, 1).cactusBonus, 0, "新回合不把永久尺寸重新兑换临时倍率")
    Close(restored:_Value(Item(restored, 1)), 6)
end)

Test("仙人掌追踪其他正向尺寸变化，不奖励缩小且清理只清临时倍率", function()
    local game = Fixture({ "cactus" })
    Expansion.Step(game, 0, Contacts(), {})
    Item(game, 1).scale = 1.3
    Expansion.Step(game, 0, Contacts(), {})
    Close(Item(game, 1).cactusBonus, .3)
    Close(Item(game, 1).permMult, 1)
    Close(game:_Value(Item(game, 1)), 5.2)
    Item(game, 1).scale = 1.1
    Expansion.Step(game, 0, Contacts(), {})
    Close(Item(game, 1).cactusBonus, .3)
    Close(Item(game, 1).permMult, 1)
    Expansion.ResetRound(Item(game, 1))
    Close(Item(game, 1).cactusBonus, 0)
    Close(Item(game, 1).scale, 1.1)
    Close(game:_Value(Item(game, 1)), 4)
end)

Test("仙人掌气球公共爆炸只一次、事件倍率不被光环刷新抹去", function()
    local game = Fixture({ "cactus", "balloon", "apple" })
    local events = {}
    assert(Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 } }), events))
    assert(Item(game, 2).location == "discard" and #Events(events, "burst") == 1)
    Close(Item(game, 1).eventMult, 2); Close(Item(game, 3).eventMult, 2)
    assert(not Expansion.BurstBalloon(game, Item(game, 2), events, Item(game, 1)))
    Close(Item(game, 3).eventMult, 2)
    game:Step(0, Contacts())
    Close(Item(game, 3).mult, 2)
end)

Test("算盘每成功硬币合成永久+1，每三次即时结算", function()
    local game = Fixture({ "abacus", "abacus", "coin_1", "coin_1" })
    local result = { id = "coin_2" }
    local events = {}
    for _ = 1, 3 do Expansion.OnMerge(game, Item(game, 3), Item(game, 4), result, Contacts(), events) end
    Close(Item(game, 1).permBonus, 3); Close(Item(game, 2).permBonus, 3)
    Close(game.roundScore, 16)
    assert(#Events(events, "score") == 2)
    Expansion.OnMerge(game, Item(game, 3), Item(game, 4), { id = "wool" }, Contacts(), events)
    Close(Item(game, 1).permBonus, 3)
    Expansion.ResetRound(Item(game, 1)); Close(Item(game, 1).abacusMerges, 0)
end)

Test("保镖按uid最早选且不保护自身，护盾禁止整回合重复消费", function()
    local game = Fixture({ "bodyguard", "bodyguard", "doctor", "killer" })
    local events = {}
    assert(not game:_Destroy(3, false, events, Item(game, 4), "consume"))
    assert(Item(game, 3).shielded and Item(game, 3).location == "bottle")
    Close(Item(game, 1).counter, 1); Close(Item(game, 2).counter, 0)
    Close(game.roundScore, 5)
    assert(not game:_Destroy(3, false, events, Item(game, 4), "consume"))
    Close(game.roundScore, 5); Close(Item(game, 1).counter, 1)
    assert(not game:_Destroy(1, false, events, Item(game, 4), "consume"))
    Close(Item(game, 2).counter, 1)
    local score = game.roundScore
    game:Step(0, Contacts({ { 3, 4 } }))
    Close(Item(game, 4).remaining, 0, "杀手消费被护盾拦截不进入冷却")
    Close(game.roundScore, score, "同一护盾反复阻拦不重复收益")
    assert(Item(game, 3).location == "bottle" and Item(game, 3).shielded)
end)

Test("保镖三盾直接离场，不被第二保镖套娃保护", function()
    local game = Fixture({ "bodyguard", "bodyguard", "doctor", "student", "soldier" })
    for uid = 3, 5 do assert(not game:_Destroy(uid, false, {}, nil, "consume")) end
    assert(Item(game, 1).location == "discard")
    Close(Item(game, 1).counter, 3); Close(Item(game, 2).counter, 0)
    Expansion.ResetRound(Item(game, 3))
    assert(not Item(game, 3).shielded)
end)

Test("无其他保镖可自耗、人类成长不触发保护", function()
    local game = Fixture({ "bodyguard", "student" })
    game:_Transform(Item(game, 2), "doctor", {})
    Close(Item(game, 1).counter, 0)
    assert(game:_Destroy(1, false, {}, nil, "self"))
    assert(Item(game, 1).location == "discard")
end)

Test("养鸡人吃蛋按蛋有效值给金币，50%永久小鸡", function()
    local game = Fixture({ "chicken_keeper", "egg", "egg" })
    Item(game, 2).permBonus, Item(game, 2).permMult = 2, 2
    Sequence(game, { 1, 2 })
    assert(Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 }, { 1, 3 } }), {}))
    Close(game.roundScore, 13)
    local chicks = Find(game, "chick", "bottle")
    assert(#chicks == 1 and not chicks[1].temporary)
end)

Test("养鸡人刷新跨回合累计且牌库生效、弃牌不计", function()
    local game = Fixture({ "chicken_keeper", "chicken_keeper", "chicken_keeper" })
    Item(game, 2).location, Item(game, 3).location = "deck", "discard"
    for _ = 1, 4 do Expansion.OnRefresh(game) end
    Expansion.ResetRound(Item(game, 1))
    Close(Item(game, 1).refreshCount, 4)
    Expansion.OnRefresh(game)
    Close(Item(game, 1).permBonus, 1); Close(Item(game, 2).permBonus, 1)
    Close(Item(game, 3).permBonus, 0); Close(Item(game, 1).refreshCount, 0)
end)

Test("小猪主动吃完整苹果橘子香蕉及香蕉皮，半份樱桃不匹配", function()
    local game = Fixture({ "pig", "apple_half", "cherry", "apple", "banana", "orange", "banana_peel" })
    assert(not Expansion.Touches(game, Item(game, 1), Contacts({ { 1, 2 }, { 1, 3 } })))
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 4 }, { 1, 5 }, { 1, 6 } }), {})
    Close(Item(game, 1).scale, 1.3); Close(Item(game, 1).weight, 1.3)
    Close(game.roundScore, 20, "三件按消费前价值2/6/2分别奖励两倍金币")
    assert(Item(game, 5).id == "banana_peel", "香蕉变皮仍给猪增长")
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 5 }, { 1, 7 } }), {})
    assert(Item(game, 5).location == "discard" and Item(game, 7).location == "discard",
        "新产生和既有香蕉皮都可被主动消费")
    Close(Item(game, 1).scale, 1.5); Close(Item(game, 1).weight, 1.5)
    Close(game.roundScore, 24, "两份基础1香蕉皮成功消费各奖励2金币")
    assert(Item(game, 2).location == "bottle" and Item(game, 3).location == "bottle")
end)

Test("猪消费草照样增长，到体积上限转培根且保物理", function()
    local game = Fixture({ "pig", "grass" })
    Item(game, 1).scale, Item(game, 1).weight = 1.95, 1.4
    Constant(game, 1)
    assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
    assert(Item(game, 1).id == "bacon")
    Close(Item(game, 1).scale, 2); Close(Item(game, 1).weight, 1.5)
end)

Test("牛成功消费后短冲刺、每目标每冲刺临时+1", function()
    local game = Fixture({ "calf", "grass", "apple", "ball" })
    Constant(game, 1)
    local events = {}
    assert(game:_Destroy(2, false, events, Item(game, 1), "consume"))
    assert(#Events(events, "dash") == 1)
    Close(Item(game, 1).calfDashRemaining, 0.35)
    local contacts = Contacts({ { 1, 3 }, { 1, 4 }, { 1, 3 } })
    Expansion.Step(game, 0.1, contacts, events)
    Expansion.Step(game, 0.1, contacts, events)
    Close(Item(game, 1).bonus, 2); Close(Item(game, 1).permBonus, 0)
    Expansion.Step(game, 0.2, Contacts(), events)
    Expansion.Step(game, 0.1, contacts, events)
    Close(Item(game, 1).bonus, 2)
end)

Test("果汁被消耗按当前有效值永久加给消费者", function()
    local game = Fixture({ "glutton", "juice" })
    Item(game, 2).valueBase, Item(game, 2).permBonus = 7, 2
    Item(game, 2).mult, Item(game, 2).permMult = 2, 1.2
    assert(game:_Destroy(2, false, {}, Item(game, 1), "consume"))
    Close(Item(game, 1).permBonus, 21.6)
end)

Test("分裂只穿透物，向上取整且不触发消耗幽灵收益", function()
    local game = Fixture({ "splitter", "ghost", "apple" })
    Item(game, 2).permBonus, Item(game, 2).permMult = 3, 2
    Item(game, 2).mult, Item(game, 2).eventMult = 1.5, 1.5
    Item(game, 2).scale, Item(game, 2).weight = 1.3, 1.4
    local events = {}
    assert(Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 }, { 1, 3 } }), events))
    local ghosts = Find(game, "ghost", "bottle")
    assert(#ghosts == 2 and #Events(events, "remove") == 0 and #Events(events, "score") == 0)
    for _, ghost in ipairs(ghosts) do
        Close(game:_Value(ghost), 8); Close(ghost.valueBase, 8)
        Close(ghost.permBonus, 0); Close(ghost.permMult, 1); Close(ghost.eventMult, 1)
        Close(ghost.scale, 1.3); Close(ghost.weight, 1.4)
    end
    assert(Item(game, 3).id == "apple")
end)

Test("分裂临时飞盘保留owner目标和飞行状态", function()
    local game = Fixture({ "splitter", "discus", "doctor" })
    local disc = Item(game, 2)
    disc.temporary, disc.generatedTemporary = true, true
    disc.discusOwnerUid, disc.discusTargetUid, disc.discusState = 3, 3, "flying"
    disc.valueBase = 5
    local events = {}
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 } }), events)
    local copies = Find(game, "discus", "bottle")
    assert(#copies == 2)
    for _, copy in ipairs(copies) do
        Close(game:_Value(copy), 3)
        assert(copy.temporary and copy.generatedTemporary and copy.discusOwnerUid == 3)
        assert(copy.discusTargetUid == 3 and copy.discusState == "flying")
    end
    assert(#Events(events, "flight") == 1)
end)

Test("排队分裂飞盘入场恢复保存的目标飞行", function()
    local game = Fixture({ "discus", "doctor" })
    local disc = Item(game, 1)
    disc.discusOwnerUid, disc.discusTargetUid = 2, 2
    disc.discusHolderUid, disc.discusState = 2, "flying"
    local events = {}
    Expansion.OnEnter(game, disc, events)
    local flights = Events(events, "flight")
    assert(#flights == 1 and flights[1].targetUid == 2 and flights[1].ownerUid == 2)
end)

Test("羊毛合成价值相加且永久，不再有被消费额外金币", function()
    local game = Fixture({ "wool", "wool" })
    Item(game, 1).temporary, Item(game, 1).generatedTemporary = true, true
    Item(game, 1).permBonus = 1
    local events = {}
    assert(Expansion.TryMerge(game, Item(game, 1), Item(game, 2), Contacts({ { 1, 2 } }), events))
    local result = Find(game, "wool", "bottle")[1]
    assert(result and not result.temporary and not result.generatedTemporary)
    Close(game:_Value(result), 3); Close(game.roundScore, 0)
    assert(#Events(events, "merge") == 1)
end)

Test("羊毛合成预检原子性，被护盾阻止不先耗另一份", function()
    local game = Fixture({ "wool", "wool" })
    Item(game, 2).shielded = true
    local events = {}
    assert(not Expansion.TryMerge(game, Item(game, 1), Item(game, 2), Contacts(), events))
    assert(Item(game, 1).location == "bottle" and Item(game, 2).location == "bottle")
    assert(#Events(events, "score") == 0 and #Events(events, "remove") == 0)
end)

Test("羊毛严格大于10才转羊毛衫，外部加值也触发", function()
    local game = Fixture({ "wool", "wool" })
    Item(game, 1).valueBase, Item(game, 2).valueBase = 5, 5
    Expansion.TryMerge(game, Item(game, 1), Item(game, 2), Contacts(), {})
    local wool = Find(game, "wool", "bottle")[1]
    assert(wool and game:_Value(wool) == 10)
    wool.permBonus = 1
    Expansion.Step(game, 0, Contacts(), {})
    assert(wool.id == "sweater"); Close(game:_Value(wool), 10)
    local merged = Fixture({ "wool", "wool" })
    Item(merged, 1).valueBase = 10
    Expansion.TryMerge(merged, Item(merged, 1), Item(merged, 2), Contacts(), {})
    assert(#Find(merged, "sweater", "bottle") == 1)
end)

Test("羊毛衫消费羊毛永久+1但不额外结算羊毛", function()
    local game = Fixture({ "sweater", "wool", "wool" })
    local events = {}
    Expansion.Apply(game, Item(game, 1), Contacts({ { 1, 2 }, { 1, 3 } }), events)
    Close(Item(game, 1).permBonus, 2); Close(game.roundScore, 0)
    assert(#Events(events, "score") == 0)
end)

Test("指南针真实角路程累计、冷却期间不丢进度", function()
    local game = Fixture({ "compass", "apple", "ghost" })
    local contacts, events = Contacts(), {}
    contacts.angularTravel[1] = TURN * 2 + 0.4
    Expansion.Step(game, 0, contacts, events)
    Close(Item(game, 1).compassProgress, TURN * 2 + 0.4)
    assert(Expansion.Apply(game, Item(game, 1), contacts, events))
    local rotations = Events(events, "rotate")
    assert(#rotations == 2 and rotations[1].uid == 1 and rotations[2].uid == 2,
        "每uid仅一事件，不给直立幽灵旋转")
    for _, rotation in ipairs(rotations) do Close(rotation.delta, -math.pi / 2) end
    Close(Item(game, 1).compassProgress, TURN + 0.4)
    contacts.angularTravel[1] = TURN * 2 + 1
    Item(game, 1).remaining = 2
    Expansion.Step(game, 0.1, contacts, events)
    Close(Item(game, 1).compassProgress, TURN + 1)
    assert(Expansion.Apply(game, Item(game, 1), contacts, events))
    Close(Item(game, 1).compassProgress, 1)
end)

Test("指南针回转也计路程、强制90度不计", function()
    local game = Fixture({ "compass" })
    local contacts = Contacts()
    contacts.angles[1] = 0
    Expansion.Step(game, 0, contacts, {})
    contacts.angles[1] = 1
    Expansion.Step(game, 0, contacts, {})
    contacts.angles[1] = 0
    Expansion.Step(game, 0, contacts, {})
    Close(Item(game, 1).compassProgress, 2)
    contacts.angles[1], contacts.rotateOffsets[1] = -math.pi / 2, -math.pi / 2
    Expansion.Step(game, 0, contacts, {})
    Close(Item(game, 1).compassProgress, 2)
end)

Test("果冻对全部实体邻居发中心连线冲量，豁免穿透物", function()
    local game = Fixture({ "jelly", "apple", "ball", "ghost", "discus" })
    local contacts = Contacts({ { 1, 2 }, { 1, 3 }, { 1, 4 }, { 1, 5 } })
    contacts.positions[1], contacts.positions[2], contacts.positions[3] =
        { x = 0, y = 0 }, { x = 1, y = 2 }, { x = -2, y = 0 }
    local events = {}
    assert(Expansion.Apply(game, Item(game, 1), contacts, events))
    local impulses = Events(events, "impulse")
    assert(#impulses == 2 and impulses[1].uid == 2 and impulses[2].uid == 3)
    Close(impulses[1].strength, 6); Close(impulses[2].strength, 6)
    Close(impulses[1].dx, 1); Close(impulses[1].dy, 2); Close(impulses[2].dx, -2)
end)

Test("运动员首帧一枚临时飞盘、正常Step不重复创建", function()
    local game = Fixture({ "discus_athlete", "apple" })
    Constant(game, 1)
    local events = {}
    Expansion.Step(game, 0, Contacts(), events)
    Expansion.Step(game, 0.1, Contacts(), events)
    local discs = Find(game, "discus", "bottle")
    assert(#discs == 1 and discs[1].temporary and discs[1].generatedTemporary)
    assert(discs[1].discusOwnerUid == 1 and discs[1].discusState == "flying")
    assert(discs[1].discusTargetUid == 2, "首抛不能投回当前持有者")
    assert(#Events(events, "flight") == 1)
end)

Test("飞盘命中人类0.2秒后续抛，不持续重读命中", function()
    local game = Fixture({ "discus", "doctor", "apple" })
    local disc = Item(game, 1)
    disc.discusOwnerUid, disc.discusState, disc.discusTargetUid = 2, "flying", 2
    local contacts, events = Contacts(), {}
    contacts.flightHits[1] = 2
    Expansion.Step(game, 0.05, contacts, events)
    assert(disc.discusState == "human_wait"); Close(disc.discusWait, 0.2)
    Expansion.Step(game, 0.19, contacts, events)
    assert(#Events(events, "flight") == 0)
    Constant(game, 1)
    Expansion.Step(game, 0.01, contacts, events)
    assert(disc.discusState == "flying" and #Events(events, "flight") == 1)
end)

Test("飞盘非人类/失联到达闪回owner，等3秒再抛且闪回不计路程", function()
    local game = Fixture({ "discus", "doctor", "apple" })
    local disc = Item(game, 1)
    disc.discusOwnerUid, disc.discusState = 2, "flying"
    game._lastPositions[1] = { x = -1, y = 0 }
    local contacts, events = Contacts(), {}
    contacts.positions[2], contacts.flightHits[1] = { x = 2, y = 3 }, 3
    Expansion.Step(game, 0.1, contacts, events)
    assert(disc.discusState == "owner_wait"); Close(disc.discusWait, 3)
    assert(#Events(events, "teleport") == 1 and game._lastPositions[1] == nil)
    Expansion.Step(game, 2.99, Contacts(), events)
    assert(#Events(events, "flight") == 0)
    Constant(game, 1)
    Expansion.Step(game, 0.01, Contacts(), events)
    assert(#Events(events, "flight") == 1)
    disc.discusState = "flying"
    local missed = Contacts(); missed.flightArrived[1] = true
    Expansion.Step(game, 0, missed, events)
    assert(disc.discusState == "owner_wait")
end)

Test("飞盘每5米按当前值多次结算，保留不足5米余量", function()
    local game = Fixture({ "discus", "apple" })
    local disc = Item(game, 1)
    disc.distance, disc.discusState, disc.discusWait = 12.4, "owner_wait", 3
    disc.permBonus = 1
    Expansion.Step(game, 0, Contacts(), {})
    Close(game.roundScore, 6); Close(disc.distance, 2.4)
end)

Test("鸡蛋仅入瓶累计满3回合才自耗并50%刷新", function()
    local game = Fixture({ "egg", "egg", "egg" })
    Item(game, 1).bottleRounds, Item(game, 2).bottleRounds, Item(game, 3).bottleRounds = 2, 3, 8
    Sequence(game, { 1, 2 })
    local refreshes = game.refreshes or 0
    Expansion.AfterSettle(game, {})
    assert(Item(game, 1).location == "bottle" and Item(game, 2).location == "discard"
        and Item(game, 3).location == "discard")
    Close(game.refreshes, refreshes + 1)
end)

Test("剧烈摇晃脱全部羊毛，温和摇晃与牌库羊不脱", function()
    local game = Fixture({ "sheep", "sheep" })
    Item(game, 1).woolCount, Item(game, 2).woolCount = 5, 2
    Item(game, 2).location = "deck"
    local mild, events = Contacts(), {}
    mild.shakeStrength = 3.99
    Expansion.Step(game, 0.1, mild, events)
    Close(Item(game, 1).woolCount, 5)
    local strong = Contacts(); strong.shakeStrength = 4
    Constant(game, 1)
    Expansion.Step(game, 0.1, strong, events)
    Close(Item(game, 1).woolCount, 0); Close(Item(game, 2).woolCount, 2)
    local wools = Find(game, "wool", "bottle")
    assert(#wools == 5)
    for _, wool in ipairs(wools) do
        assert(not wool.temporary and not wool.generatedTemporary)
        Close(game:_Value(wool), 1)
    end
    assert(#Events(events, "spawn") == 5)
    for _, spawn in ipairs(Events(events, "spawn")) do Close(spawn.y, 6) end
    assert(not Expansion.ShedWool(game, Item(game, 1), events), "脱空后不能重复生成")
end)

Test("小刀真实规则接线脱羊库存，羊不是水果也能触发", function()
    local game = Fixture({ "knife", "sheep" })
    Item(game, 2).woolCount = 3
    Constant(game, 1)
    game:Step(0, Contacts({ { 1, 2 } }))
    Close(Item(game, 2).woolCount, 0)
    assert(#Find(game, "wool", "bottle") == 3 and Item(game, 2).location == "bottle")
end)

Test("满瓶脱羊毛排队仍一根不丢且不是临时生成", function()
    local ids = { "sheep" }
    for _ = 2, 100 do ids[#ids + 1] = "apple" end
    local game = Fixture(ids)
    Item(game, 1).woolCount = 5
    Constant(game, 1)
    assert(Expansion.ShedWool(game, Item(game, 1), {}))
    Close(Item(game, 1).woolCount, 0)
    assert(#Find(game, "wool", "queued") == 5 and #game:BottleItems() == 100)
    for _, wool in ipairs(Find(game, "wool")) do assert(not wool.generatedTemporary) end
end)

Test("额外羊毛只筛价值1且已到下回合，不把同回合新毛预入场", function()
    local game = Fixture({ "wool", "wool", "wool", "wool", "apple" })
    for _, item in ipairs(game:AllInstances()) do item.location = "deck" end
    Item(game, 1).woolReadyRound = game.round
    Item(game, 2).woolReadyRound = game.round + 1
    Item(game, 3).woolReadyRound, Item(game, 3).valueBase = nil, 2
    Item(game, 4).woolReadyRound = nil -- 旧档缺省视为已可入。
    local extras = Expansion.ExtraEntrants(game)
    assert(#extras == 2 and extras[1].uid == 1 and extras[2].uid == 4)
end)

Test("羊毛准备额外入场不占20抽，重抽与prepare存档不复制", function()
    local ids = { "wool", "wool" }
    for _ = 1, 25 do ids[#ids + 1] = "apple" end
    local game = Fixture(ids)
    for uid = 1, 2 do Item(game, uid).woolReadyRound = game.round end
    game:_Prepare()
    assert(#game.drawn == 20 and #game:BottleItems() == 22)
    for uid = 1, 2 do
        assert(Item(game, uid).woolExtraEntry and not Item(game, uid).generatedTemporary)
    end
    local restored = Game.Restore(game:Snapshot()) --[[@as any]]
    assert(#restored:BottleItems() == 22 and #restored.drawn == 20)
    restored.refreshes = 1
    assert(restored:Reroll())
    assert(#Find(restored, "wool") == 2 and #restored:BottleItems() == 22 and #restored.drawn == 20)
    assert(restored:Start())
    for uid = 1, 2 do
        assert(Item(restored, uid).temporary and Item(restored, uid).generatedTemporary
            and not Item(restored, uid).woolExtraEntry)
    end
end)

Test("超100额外羊毛保普通20抽，溢出Start有序入队", function()
    local ids = {}
    for _ = 1, 105 do ids[#ids + 1] = "wool" end
    for _ = 1, 25 do ids[#ids + 1] = "apple" end
    local game = Fixture(ids)
    for uid = 1, 105 do Item(game, uid).woolReadyRound = game.round end
    game:_Prepare()
    assert(#game.drawn == 20 and #game:BottleItems() == 100 and #Find(game, "wool", "deck") == 25)
    local restored = Game.Restore(game:Snapshot()) --[[@as any]]
    assert(restored:Start())
    assert(#Find(restored, "wool", "queued") == 25 and #restored.spawnQueue == 25)
    local before = #restored:BottleItems()
    restored:Consume(restored.drawn[1])
    assert(#restored:BottleItems() == before and #Find(restored, "wool", "queued") == 24)
end)

Test("额外临时羊毛回合末真正移除，不返还再进下回合", function()
    local game = Fixture({ "wool", "apple" })
    Item(game, 1).woolReadyRound = game.round
    game:_Prepare()
    assert(game:Start())
    game:Finish(Contacts())
    assert(#Find(game, "wool") == 0, "临时额外羊毛在统一结算后彻底清理")
    while game.phase == "reveal" do game:RevealStep(1) end
    assert(game:Skip())
    assert(#Find(game, "wool") == 0 and #game:BottleItems() == 1)
end)

Test("结算前奏爆炸推羊毛到>10后按羊毛衫基础结算", function()
    local game = Fixture({ "balloon", "wool" })
    Item(game, 1).scale, Item(game, 2).valueBase = 1.9, 6
    local events = game:Finish(Contacts())
    assert(Item(game, 2).id == "sweater")
    local scores = Events(events, "score")
    assert(#scores == 1 and scores[1].uid == 2)
    Close(scores[1].value, 10, "转化遵循常规重置，不保旧羊毛倍率")
end)

Test("任意壁虎连续真实接触可黏附，断开重置延迟", function()
    local game = Fixture({ "gecko", "gecko", "ball" })
    local contacts = Contacts({ { 1, 2 } })
    Expansion.Step(game, 0.2, contacts, {})
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    Expansion.Step(game, 0.01, Contacts(), {})
    Close(Item(game, 1).geckoContactTime, 0)
    Expansion.Step(game, 0.24, contacts, {})
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    Expansion.Step(game, 0.01, contacts, {})
    assert(Expansion.Apply(game, Item(game, 1), contacts, {}))
    assert(Item(game, 1).anchored and not Item(game, 2).anchored,
        "不要求对方先锚定，锚定仍逐件执行")
end)

Test("培根逻辑相邻不伪造分裂果冻或小牛冲撞", function()
    local game = Fixture({ "splitter", "ghost", "calf", "apple", "jelly", "gecko", "gecko" })
    local contacts = Contacts({ { 1, 2 }, { 3, 4 }, { 4, 5 }, { 6, 7 } })
    contacts.rawPairs = {}
    Item(game, 3).calfDashRemaining, Item(game, 3).calfDashHits = 0.35, {}
    assert(not Expansion.Touches(game, Item(game, 1), contacts))
    assert(not Expansion.Apply(game, Item(game, 1), contacts, {}))
    assert(not Expansion.Touches(game, Item(game, 5), contacts))
    Expansion.Step(game, 0.3, contacts, {})
    Close(Item(game, 3).bonus, 0)
    Close(Item(game, 6).geckoContactTime, 0)
    assert(#Find(game, "ghost") == 1)
end)

Test("壁虎最终仅直接真实邻居逐个额外结算", function()
    local game = Fixture({ "gecko", "gecko", "gecko", "apple" })
    local contacts = Contacts({ { 1, 2 }, { 2, 3 }, { 1, 3 }, { 1, 4 } })
    contacts.rawPairs = { { 1, 2 }, { 2, 1 }, { 2, 3 } }
    local events = {}
    for _, item in ipairs(game:BottleItems()) do
        Effects.SettleItem(game, item, events, nil, contacts)
    end
    local totals, counts = {}, {}
    for _, event in ipairs(Events(events, "score")) do
        totals[event.uid] = (totals[event.uid] or 0) + event.value
        counts[event.uid] = (counts[event.uid] or 0) + 1
    end
    Close(totals[1], 8); Close(totals[2], 12); Close(totals[3], 8)
    assert(counts[1] == 2 and counts[2] == 3 and counts[3] == 2)
    Close(totals[4], 2)
end)

---@return integer
function Tests.Run()
    local passed, failures = 0, {}
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then passed = passed + 1
        else failures[#failures + 1] = case.name .. "：" .. tostring(message) end
    end
    assert(#failures == 0, "Bottle.ExpansionTests " .. passed .. "/" .. #cases
        .. " 通过\n" .. table.concat(failures, "\n"))
    return passed
end

return Tests
