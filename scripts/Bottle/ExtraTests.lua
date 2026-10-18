-- 新35件物品独立回归。基于 Bottle.Tests 的纯 Lua Fixture/Close 模式扩展。
-- 不加载 Storage/UI，不写存档、不创建引擎对象；由主测试入口显式调用 Run()。
-- 接触仅为规则输入夹具，不宣称代替真实 Box2D 物理验收。
local Items = require("Bottle.Items")
local Game = require("Bottle.Game")
local Extra = require("Bottle.ExtraEffects")
local Tests = {}

---@param actual number?
---@param expected number
---@param message string?
local function Close(actual, expected, message)
    assert(type(actual) == "number", (message or "数值") .. "：实际值缺失")
    assert(math.abs(actual - expected) < 1e-7,
        string.format("%s：期望%g，实际%g", message or "数值", expected, actual))
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid)
    local item = game:Get(uid)
    assert(item, "缺少实例uid=" .. uid)
    return item
end

---@param ids string[]
---@param bottleCount integer?
---@return BottleGame
local function Fixture(ids, bottleCount)
    local snapshot = Game.New(137):Snapshot()
    snapshot.instances, snapshot.deck, snapshot.discard, snapshot.drawn = {}, {}, {}, {}
    snapshot.nextUid = #ids + 1
    local count = bottleCount == nil and #ids or bottleCount
    for uid, id in ipairs(ids) do
        snapshot.instances[#snapshot.instances + 1] = {
            uid = uid, id = id, bonus = 0, permBonus = 0, mult = 1,
            permMult = 1, tokenAttempted = false,
            remaining = Items.byId[id].cooldown, bottleRounds = 0,
            location = uid <= count and "bottle" or "deck", temporary = false,
            scale = 1, weight = 1, counter = 0, settleCount = 0, distance = 0,
            eventMult = 1, generatedTemporary = false, shielded = false, anchored = false,
            refreshCount = 0, woolCount = 0, abacusMerges = 0, calfDashRemaining = 0,
            discusWait = 0, compassProgress = 0,
        }
        snapshot.deck[#snapshot.deck + 1] = uid
        if uid <= count then snapshot.drawn[#snapshot.drawn + 1] = uid end
    end
    return Game.Restore(snapshot)
end

-- 仅替换单个测试对局的 RNG，不改全局随机、共享数据表或其他测试。
---@param game BottleGame
---@param value integer
local function RandomConstant(game, value)
    rawset(game, "_RandomInt", function(_, maximum)
        return math.min(maximum, math.max(1, value))
    end)
end

---@param game BottleGame
---@param values integer[]
local function RandomSequence(game, values)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local value = assert(values[index], "确定性随机序列用尽")
        assert(value >= 1 and value <= maximum, "随机夹具超出范围")
        return value
    end)
end

---@param events GameEvent[]
---@param kind string
---@param uid integer?
---@return GameEvent[]
local function Events(events, kind, uid)
    ---@type GameEvent[]
    local found = {}
    for _, event in ipairs(events) do
        if event.kind == kind and (uid == nil or uid == event.uid) then
            found[#found + 1] = event
        end
    end
    return found
end

---@param game BottleGame
---@param id string
---@return integer
local function BottleCount(game, id)
    local count = 0
    for _, item in ipairs(game:BottleItems()) do
        if item.id == id then count = count + 1 end
    end
    return count
end

---@param game BottleGame
---@param contacts BottleContacts?
---@return GameEvent[]
local function Finish(game, contacts)
    local events = game:Finish(contacts)
    assert(game.phase == "reveal", "结算进入展示")
    -- reveal 时长 = 浮字队列时长 + 2秒；按阶段推进直到进入三选一/结束。
    local guard = 0
    while game.phase == "reveal" do
        guard = guard + 1
        assert(guard < 120, "结算展示未在有限步内结束")
        game:RevealStep(0.1)
    end
    return events
end

---@param game BottleGame
local function Identity(game)
    ---@type table<number, boolean>
    local owned = {}
    for _, item in ipairs(game.deck) do
        assert(not owned[item.uid] and game:Get(item.uid) == item, "牌库实例身份重复")
        owned[item.uid] = true
    end
    for _, item in ipairs(game.discard) do
        assert(game:Get(item.uid) == item and item.location == "discard", "弃牌实例身份失效")
        assert(not owned[item.uid] or item.temporary, "永久弃牌仍在拥有牌库")
    end
    for _, item in ipairs(game:BottleItems()) do assert(owned[item.uid], "瓶内实例不在牌库") end
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run)
    cases[#cases + 1] = { name = name, run = run }
end

Test("93件全实装、26件屏蔽与硬币配方", function()
    assert(#Items.list == 93)
    local blocked = {
        rotten_banana = true, banana_peel = true, apple_half = true, banana_half = true,
        orange_half = true, cherry_half = true, fruit_ninja = true, tomato_egg = true,
        coin_4 = true, coin_8 = true, coin_16 = true, coin_32 = true, coin_64 = true,
        coin_128 = true, coin_256 = true, coin_512 = true, coin_1024 = true, coin_2048 = true,
        juice = true, poop = true, golden_poop = true, diamond_poop = true, rainbow_poop = true,
        discus = true, wool = true, sweater = true,
    }
    local blockedCount, normalCount = 0, 0
    for index, def in ipairs(Items.list) do
        assert(def.numberId == index and def.implemented, "仍有未实装物品：" .. def.id)
        assert(def.pool == (not blocked[def.id]), "卡池与源表及追加果汁约定不一致：" .. def.id)
        if def.pool then normalCount = normalCount + 1 else blockedCount = blockedCount + 1 end
    end
    assert(blockedCount == 26 and normalCount == 67, "源表93件中26件屏蔽、67件入池")
    for _, value in ipairs({ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 }) do
        local id = "coin_" .. value
        assert(Items.Recipe(id, id) == "coin_" .. (value * 2), "硬币配方缺失：" .. id)
    end
    assert(Items.Recipe("coin_2048", "coin_2048") == nil, "终点硬币不再合成")
end)

Test("骰子开局只投瓶内实例、点数独立且即时结算", function()
    local game = Fixture({ "die_d4", "die_d6", "die_d4" }, 2)
    RandomSequence(game, { 4, 6 })
    assert(game:Start())
    Close(game:_Value(Item(game, 1)), 4)
    Close(game:_Value(Item(game, 2)), 6)
    Close(game.roundScore, 10, "两颗入瓶骰子投完立刻结算")
    local data = game --[[@as any]]
    assert(#Events(data.startEvents or {}, "score") == 2, "开局收益事件可供main展示")
    assert((Item(game, 3) --[[@as any]]).rollValue == nil, "牌库骰子不投掷")
    Close(Items.byId.die_d4.base, 1, "不改共享基础值")
    Close(Items.byId.die_d6.base, 1)
    local rollback = Game.Restore(game:Snapshot())
    Close(rollback.score, 0, "开局投掷收益可回滚")
end)

Test("作弊骰子排除1点", function()
    local game = Fixture({ "die_d4", "die_d6" })
    game.relics.cheat_dice = true
    RandomConstant(game, 1)
    assert(game:Start())
    Close(game:_Value(Item(game, 1)), 2)
    Close(game:_Value(Item(game, 2)), 2)
    Close(game.roundScore, 4)
end)

Test("赌徒每位每骰每回合一次、不同赌徒额度独立", function()
    local game = Fixture({ "gambler", "gambler", "die_d4", "die_d6" })
    RandomConstant(game, 2)
    assert(game:Start())
    local before = game.roundScore
    local contacts = { pairs = { { 1, 3 }, { 1, 4 }, { 2, 3 } } }
    game:Step(1, contacts)
    Close(Item(game, 1).permBonus, 2, "第一赌徒各投两颗骰子一次")
    Close(Item(game, 2).permBonus, 1, "第二赌徒也能投同颗骰子")
    Close(game.roundScore - before, 6, "三次骰子本体收益")
    local score = game.roundScore
    game:Step(3, contacts)
    Close(game.roundScore, score, "同回合不能重复投")
    Close(Item(game, 1).permBonus, 2)
end)

Test("赌徒投1先加1结算自身再归零", function()
    local game = Fixture({ "gambler", "die_d4" })
    RandomConstant(game, 2)
    assert(game:Start())
    Item(game, 1).permBonus, Item(game, 1).bonus = 5, 2
    local before = game.roundScore
    RandomConstant(game, 1)
    local events = game:Step(1, { pairs = { { 1, 2 } } })
    local scores = Events(events, "score", 1)
    assert(#scores == 1)
    Close(scores[1].value, 8, "5永久+2临时+本次1")
    Close(game.roundScore - before, 9, "骰子1+赌徒8")
    Close(game:_Value(Item(game, 1)), 0)
    Close(Item(game, 1).bonus, 0)
    Close(Item(game, 1).permBonus, 0)
end)

Test("赌徒及赌神最大点结算自身、赌神永久加点数", function()
    local game = Fixture({ "gambler", "gambling_god", "die_d4", "die_d6" })
    RandomConstant(game, 2)
    assert(game:Start())
    local before = game.roundScore
    RandomSequence(game, { 4, 6 })
    local events = game:Step(1, { pairs = { { 1, 3 }, { 2, 4 } } })
    Close(Item(game, 1).permBonus, 1)
    Close(Item(game, 2).permBonus, 6)
    Close(Events(events, "score", 1)[1].value, 1)
    Close(Events(events, "score", 2)[1].value, 14)
    Close(game.roundScore - before, 4 + 6 + 1 + 14)
end)

Test("再来一把只扩展赌徒为连续两投", function()
    local game = Fixture({ "gambler", "gambling_god", "die_d4" })
    game.relics.one_more_round = true
    RandomConstant(game, 2)
    assert(game:Start())
    local before = game.roundScore
    game:Step(1, { pairs = { { 1, 3 }, { 2, 3 } } })
    Close(Item(game, 1).permBonus, 2)
    Close(Item(game, 2).permBonus, 2, "赌神仍只投一次")
    Close(game.roundScore - before, 6)
end)

Test("果树10秒周期、概率失败也重置冷却", function()
    local game = Fixture({ "fruit_tree" })
    RandomConstant(game, 2)
    assert(game:Start())
    game:Step(9)
    assert(#game:BottleItems() == 1)
    local events = game:Step(1)
    assert(#Events(events, "spawn") == 0, "50%失败不生成")
    Close(Item(game, 1).remaining, 10)
    local success = Fixture({ "fruit_tree" })
    RandomConstant(success, 1)
    assert(success:Start())
    events = success:Step(10, { positions = { [1] = { x = .2, y = 3 } } })
    assert(#Events(events, "spawn") == 1)
    assert(Items.HasTag(Item(success, 2).id, "水果"))
    Close(Events(events, "spawn")[1].x, .2)
    assert(not Item(success, 2).temporary, "生成水果永久入库")
end)

Test("农民祝福下一次保底加额外、消耗后可再获得", function()
    local game = Fixture({ "farmer", "fruit_tree" })
    RandomConstant(game, 1)
    assert(game:Start())
    local state = game:_ContactSnapshot({ pairs = { { 1, 2 } } })
    game:Step(1, state)
    assert((Item(game, 2) --[[@as any]]).treeBlessed == true)
    local remaining = Item(game, 2).remaining
    ---@type GameEvent[]
    local events = {}
    Extra.Crop(game, Item(game, 2), state, events)
    assert(#Events(events, "spawn") == 2, "祝福保底一份+额外成功一份")
    assert(not (Item(game, 2) --[[@as any]]).treeBlessed)
    Close(Item(game, 2).remaining, remaining, "主动判定不改周期")
    game:Step(1, state)
    assert((Item(game, 2) --[[@as any]]).treeBlessed == true, "消耗后重新触碰授予")
end)

Test("水珠同时触发相邻种子果树且不重置果树周期", function()
    local game = Fixture({ "droplet", "seed", "fruit_tree" })
    RandomConstant(game, 1)
    assert(game:Start())
    Item(game, 1).remaining, Item(game, 3).remaining = 0, 7
    local events = game:Step(0, { pairs = { { 1, 2 }, { 1, 3 } } })
    assert(Item(game, 1).location == "discard")
    assert(Items.HasTag(Item(game, 2).id, "植物"))
    assert(#Events(events, "spawn") == 1)
    Close(Item(game, 3).remaining, 7)
end)

Test("水珠概率失败也自耗、没有农作物不自耗", function()
    local game = Fixture({ "droplet", "seed", "droplet", "apple" })
    RandomConstant(game, 2)
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 2 }, { 3, 4 } } })
    assert(Item(game, 1).location == "discard", "种子判定失败也已触发")
    assert(Item(game, 2).id == "seed")
    assert(Item(game, 3).location == "bottle", "无合法农作物保留水珠")
end)

Test("云朵5秒生成永久水珠、硬币雨替换生成", function()
    local game = Fixture({ "cloud" })
    assert(game:Start())
    game:Step(4)
    assert(BottleCount(game, "droplet") == 0)
    local state = { positions = { [1] = { x = -.2, y = 4 } } }
    local events = game:Step(1, state)
    assert(BottleCount(game, "droplet") == 1)
    Close(Events(events, "spawn")[1].y, 4)
    game:Step(5, state)
    assert(BottleCount(game, "droplet") == 2)
    Close(game.roundScore, 0, "生成不自动结算")
    assert(not Item(game, 2).temporary)
    local coins = Fixture({ "cloud" })
    coins.relics.coin_rain = true
    assert(coins:Start())
    coins:Step(5)
    assert(BottleCount(coins, "coin_1") == 1 and BottleCount(coins, "droplet") == 0)
end)

Test("猴子固定7金币且香蕉消耗变皮、半香蕉不匹配", function()
    local game = Fixture({ "monkey", "banana", "banana_half" })
    Item(game, 2).permBonus = 100
    assert(game:Start())
    game:Step(5, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(game.roundScore, 7)
    assert(Item(game, 2).id == "banana_peel" and Item(game, 2).location == "bottle")
    assert(Item(game, 3).id == "banana_half" and Item(game, 3).location == "bottle")
    game:Step(5, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(game.roundScore, 7, "不能吃香蕉皮/半根香蕉")
end)

Test("幸运硬币5秒投掷成功结算、失败不结算", function()
    for _, face in ipairs({ 1, 2 }) do
        local game = Fixture({ "lucky_coin" })
        RandomConstant(game, face)
        Item(game, 1).permBonus = 3
        assert(game:Start())
        game:Step(4)
        Close(game.roundScore, 0)
        game:Step(1)
        Close(game.roundScore, face == 1 and 5 or 0)
        Close(Item(game, 1).remaining, 5)
    end
end)

Test("兔子每移动10米永久加1、成群结队为其他兔子加值", function()
    for _, grouped in ipairs({ false, true }) do
        local game = Fixture({ "rabbit", "rabbit" })
        game.relics.in_groups = grouped or nil
        assert(game:Start())
        for sample = 0, 20 do
            game:Step(0, { positions = {
                [1] = { x = sample * .5, y = 2 }, [2] = { x = 0, y = 4 },
            } })
        end
        Close(Item(game, 1).permBonus, 1)
        Close(Item(game, 2).permBonus, grouped and 1 or 0)
        Finish(game)
        Close(Item(game, 1).permBonus, 1, "永久增长回合末保留")
    end
end)

Test("大胃王移动10米缩小、教练使缩幅翻倍且不低于1", function()
    for _, coached in ipairs({ false, true }) do
        local game = Fixture(coached and { "glutton", "fitness_coach" } or { "glutton" })
        Item(game, 1).scale = 1.5
        assert(game:Start())
        for sample = 0, 20 do
            game:Step(0, { positions = { [1] = { x = sample * .5, y = 2 } } })
        end
        Close(Item(game, 1).scale, coached and 1.3 or 1.4)
        for sample = 21, 120 do
            game:Step(0, { positions = { [1] = { x = sample * .5, y = 2 } } })
        end
        Close(Item(game, 1).scale, 1, "缩小有100%下限")
    end
end)

Test("计数器按瓶内元素每3个加1、不累积且离瓶即刷新", function()
    local game = Fixture({ "counter", "apple", "apple", "apple", "apple", "apple", "apple" }, 6)
    assert(game:Start())
    game:Step(0)
    Close(game:_Value(Item(game, 1)), 2)
    game:Step(1)
    Close(game:_Value(Item(game, 1)), 2, "不是每帧叠加")
    game:Consume(2)
    game:Step(0)
    Close(game:_Value(Item(game, 1)), 1, "5件向下取整")
    Close(Item(game, 1).permBonus, 0, "数量加成为临时")
end)

Test("水果商人接触光环翻倍、离开失效", function()
    local game = Fixture({ "fruit_merchant", "apple", "egg" })
    assert(game:Start())
    game:Step(0, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(game:_Value(Item(game, 2)), 4)
    Close(game:_Value(Item(game, 3)), 3, "食物但非水果不翻倍")
    game:Step(0)
    Close(game:_Value(Item(game, 2)), 2)
end)

Test("死灵术士返还弃牌保永久值、不重复结算或重复返还", function()
    local game = Fixture({ "necromancer", "necromancer", "apple", "orange" })
    RandomConstant(game, 1)
    Item(game, 3).permBonus, Item(game, 4).permBonus = 7, 9
    assert(game:Start())
    game:Consume(3)
    game:Consume(4)
    local events = Finish(game)
    assert(Item(game, 3).location == "deck" and Item(game, 4).location == "deck")
    assert(#game.discard == 0 and #game.deck == 4)
    Close(Item(game, 3).permBonus, 7)
    Close(Item(game, 4).permBonus, 9)
    assert(#Events(events, "score", 3) == 0 and #Events(events, "score", 4) == 0,
        "返还不补结算弃牌")
    Close(game.lastRoundScore, 6, "只有两位死灵各自基础3")
    Identity(game)
    Game.Restore(game:Snapshot())
end)

Test("培根相邻食物1.5连乘、无接触不生效", function()
    local game = Fixture({ "bacon", "apple", "egg", "ball" })
    assert(game:Start())
    local events = Finish(game, { pairs = { { 1, 2 }, { 1, 3 }, { 1, 4 } } })
    local scores = Events(events, "score", 1)
    assert(#scores == 1)
    Close(scores[1].value, 7, "培根3×1.5×1.5最终收益向上取整")
    Close(Item(game, 1).mult, 1, "结算倍率回合末复位")
    local solo = Fixture({ "bacon", "apple" })
    assert(solo:Start())
    events = Finish(solo)
    Close(Events(events, "score", 1)[1].value, 3)
end)

Test("幽灵被消耗立即按当前值结算并进弃牌", function()
    local game = Fixture({ "ghost" })
    Item(game, 1).permBonus = 4
    assert(game:Start())
    local events = game:Consume(1)
    Close(game.roundScore, 6)
    assert(#Events(events, "score", 1) == 1 and Item(game, 1).location == "discard")
    assert(#game:Consume(1) == 0, "同一弃牌不能再次消耗")
end)

Test("灵魂罐碰任意瓶壁消耗并随机生成1至3幽灵", function()
    for _, count in ipairs({ 1, 3 }) do
        local game = Fixture({ "soul_jar" })
        RandomConstant(game, count)
        assert(game:Start())
        game:Step(1, { top = { [1] = true } })
        assert(Item(game, 1).location == "discard")
        Close(BottleCount(game, "ghost"), count)
        for _, item in ipairs(game:BottleItems()) do
            assert(not item.temporary, "幽灵永久入库")
        end
    end
end)

Test("棺材墓碑开局就绪且每4秒各触发一次、不按幽灵数放大", function()
    local game = Fixture({ "coffin", "tombstone", "ghost", "ghost" })
    assert(game:Start())
    local state = { pairs = { { 1, 3 }, { 1, 4 }, { 2, 3 }, { 2, 4 } } }
    game:Step(0, state)
    Close(BottleCount(game, "ghost"), 3, "开局仅产一只而非按两个邻居倍增")
    Close(Item(game, 2).permBonus, 1)
    game:Step(3.99, state)
    Close(BottleCount(game, "ghost"), 3)
    Close(Item(game, 2).permBonus, 1)
    game:Step(.01, state)
    Close(BottleCount(game, "ghost"), 4)
    Close(Item(game, 2).permBonus, 2)
    game:Step(4, state)
    Close(BottleCount(game, "ghost"), 5)
    Close(Item(game, 2).permBonus, 3)
end)

Test("灵魂石消耗幽灵时双方各结算一次、重生旧接触不复用", function()
    local game = Fixture({ "soul_stone", "ghost" })
    assert(game:Start())
    local state = { pairs = { { 1, 2 } } }
    local events = game:Step(1, state)
    Close(game.roundScore, 7)
    assert(#Events(events, "score", 1) == 1 and #Events(events, "score", 2) == 1)
    assert(Item(game, 2).location == "discard")
    game:Step(2, state)
    Close(game.roundScore, 7, "已消耗幽灵不能沿用旧接触")
end)

Test("灵魂共振复制最高墓碑价值再叠加自身倍率", function()
    local game = Fixture({ "soul_stone", "tombstone", "tombstone" })
    game.relics.soul_resonance = true
    Item(game, 2).permBonus, Item(game, 3).permBonus = 4, 10
    Item(game, 1).mult = 2
    Close(game:_Value(Item(game, 1)), 22, "最高墓碑11，灵魂石自身倍率2")
end)

Test("硬币默认最高64、遗物解锁至2048", function()
    for _, value in ipairs({ 1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1024 }) do
        local id = "coin_" .. value
        local game = Fixture({ id, id })
        assert(game:Start())
        local events = game:Step(1, { pairs = { { 1, 2 } } })
        if value < 64 then
            assert(#Events(events, "merge") == 1, "64以下默认可合成")
            assert(BottleCount(game, "coin_" .. (value * 2)) == 1)
        else
            assert(#Events(events, "merge") == 0, "无遗物不能突破64")
            assert(BottleCount(game, id) == 2)
        end
        local unlocked = Fixture({ id, id })
        unlocked.relics.merge_2048 = true
        assert(unlocked:Start())
        events = unlocked:Step(1, { pairs = { { 1, 2 } } })
        assert(#Events(events, "merge") == 1)
        assert(BottleCount(unlocked, "coin_" .. (value * 2)) == 1)
        Identity(unlocked)
    end
    local terminal = Fixture({ "coin_2048", "coin_2048" })
    terminal.relics.merge_2048 = true
    assert(terminal:Start())
    assert(#Events(terminal:Step(1, { pairs = { { 1, 2 } } }), "merge") == 0)
end)

Test("硬币机按相邻人类数顶落硬币、升级可产4元", function()
    for _, upgrade in ipairs({ false, true }) do
        local game = Fixture({ "coin_machine", "student", "doctor", "apple" })
        game.relics.upgrade_coin_machine = upgrade or nil
        RandomConstant(game, 3)
        assert(game:Start())
        local events = game:Step(0, { pairs = { { 1, 2 }, { 1, 3 }, { 1, 4 } } })
        local spawns = Events(events, "spawn")
        assert(#spawns == 2, "两个人类只产两枚，不按每种各产两枚")
        for _, event in ipairs(spawns) do
            assert(event.id == (upgrade and "coin_4" or "coin_2"))
            Close(event.y, 6)
            assert(event.x and math.abs(event.x) <= .4)
        end
        Close(game.roundScore, 0)
    end
end)

Test("星星仅触底传送、保留身份永久值并清除旧接触", function()
    local game = Fixture({ "star" })
    Item(game, 1).permBonus = 8
    assert(game:Start())
    assert(#game:Step(1, { wall = { [1] = true } }) == 0, "侧壁不传送")
    local events = game:Step(0, { bottom = { [1] = true } })
    local teleports = Events(events, "respawn", 1)
    assert(#teleports == 1 and teleports[1].y == 6)
    assert(Item(game, 1).id == "star" and Item(game, 1).location == "bottle")
    Close(Item(game, 1).permBonus, 8)
    Close(Item(game, 1).bonus, 1, "每次传送临时价值+1")
    Close(game:_Value(Item(game, 1)), 12)
end)

Test("食客最后一批全部吃完再自耗、允许计数超过5", function()
    local game = Fixture({ "diner", "apple", "apple", "apple" })
    Item(game, 1).counter = 4
    assert(game:Start())
    game:Step(0, { pairs = { { 1, 2 }, { 1, 3 }, { 1, 4 } } })
    Close(Item(game, 1).counter, 7)
    assert(Item(game, 1).location == "discard" and Item(game, 2).location == "discard")
    assert(Item(game, 3).location == "discard" and Item(game, 4).location == "discard")
    Close(game.roundScore, 12, "三颗苹果各2×2，整批12金币")
end)

Test("带临时价值倍率的永久弃牌可存档恢复", function()
    local game = Fixture({ "apple", "orange", "ball" })
    assert(game:Start())
    Item(game, 1).bonus, Item(game, 1).mult = 2, 2
    Item(game, 2).bonus, Item(game, 2).mult = 2, 4
    Item(game, 2).permBonus = 7
    game:Consume(1)
    game:Consume(2)
    Finish(game)
    local restored = Game.Restore(game:Snapshot())
    Close(Item(restored, 1).bonus, 0)
    Close(Item(restored, 2).mult, 1)
    Close(Item(restored, 2).permBonus, 7)
    assert(#restored.discard == 2)
    Identity(restored)
end)

Test("满100件两材料合成仍可执行且最终99件", function()
    local game = Fixture({ "slipper_left", "slipper_right" })
    assert(game:Start())
    for _ = 3, 100 do game:_EnterBottle(game:_Create("ball")) end
    local events = game:Step(1, { pairs = { { 1, 2 } } })
    assert(#Events(events, "merge") == 1)
    assert(#game:BottleItems() == 99 and BottleCount(game, "fruit_ninja") == 1)
    Identity(game)
end)

Test("气球自然10次结算爆炸后的弃牌存档合法", function()
    local game = Fixture({ "balloon", "apple" })
    game.score, game.totalScore = 10000, 10000
    for round = 1, 10 do
        assert(game:Start())
        Finish(game)
        local restored = Game.Restore(game:Snapshot())
        if round < 10 then
            assert(Item(restored, 1).location == "deck", "10次前气球仍存在")
            Close(Item(restored, 1).scale, 1 + round * .1)
            assert(game:Skip())
            if game.relicDraft then assert(game:Skip()) end
        else
            assert(Item(restored, 1).location == "discard", "第10次爆炸")
            Close(game.lastRoundScore, 4, "仅苹果翻倍收益4")
        end
    end
end)

Test("大胃王resize后其他实例不得沿用旧接触偷取", function()
    local game = Fixture({ "glutton", "thief", "apple" })
    assert(game:Start())
    Item(game, 1).remaining, Item(game, 2).remaining = 0, 0
    game:Step(0, { pairs = { { 1, 3 }, { 1, 2 } } })
    Close(Item(game, 1).scale, 1.1)
    Close(Item(game, 1).permBonus, 1, "本步吃水果后重建，不能再被旧接触偷取")
    Close(Item(game, 2).permBonus, 0)
end)

Test("最后一秒通过固定步Game完整运行11秒", function()
    local game = Fixture({ "ball" })
    game.relics.last_second = true
    assert(game:Start())
    for _ = 1, 600 do game:Step(1 / 60) end
    assert(game.phase == "running", "10秒仍在摇晃")
    Close(game.elapsed, 10)
    for _ = 1, 60 do game:Step(1 / 60) end
    assert(game.phase == "settle", "11秒进入结算")
    Close(game.elapsed, 11)
    game:SettleStep(2)
    assert(game.phase == "reveal")
    game:RevealStep(2)
    assert(game.phase == "draft")
end)

Test("厨师精进刀法第三份同样获得永久加成", function()
    local game = Fixture({ "chef", "apple" })
    game.relics.knife_skill = true
    RandomConstant(game, 1)
    assert(game:Start())
    game:Step(5, { pairs = { { 1, 2 } } })
    assert(BottleCount(game, "apple_half") == 3, "确定性成功必须产第三份")
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "apple_half" then Close(item.permBonus, 3) end
    end
end)

Test("香蕉消耗也执行转基因水果判定", function()
    local game = Fixture({ "banana" })
    game.relics.gm_fruit = true
    RandomConstant(game, 1)
    assert(game:Start())
    local events = game:Consume(1)
    assert(Item(game, 1).id == "banana_peel")
    assert(#Events(events, "spawn") == 1, "任意水果包括香蕉")
    assert(#game:BottleItems() == 2)
end)

Test("实例说明正确展示百分号及消耗计数", function()
    local text = require("Bottle.ItemText")
    local game = Fixture({ "glutton", "diner", "tomato_egg" })
    Item(game, 1).scale = 1.5
    Item(game, 2).counter = 3
    Item(game, 3).counter = 4
    assert(text.Effect(game, "glutton", Item(game, 1)):find("当前：150%", 1, true))
    assert(text.Effect(game, "diner", Item(game, 2)):find("当前：3", 1, true))
    assert(text.Effect(game, "tomato_egg", Item(game, 3)):find("当前：4", 1, true))
end)

Test("硬币遗物解锁不追加物品说明且不改共享原文", function()
    local text = require("Bottle.ItemText")
    local game = Fixture({ "coin_64" })
    local original = Items.byId.coin_64.effect
    assert(text.Effect(game, "coin_64") == original)
    game.relics.merge_2048 = true
    local unlocked = text.Effect(game, "coin_64")
    assert(unlocked == original, "合成解锁保留在遗物说明，物品正文保持基础规则")
    assert(Items.byId.coin_64.effect == original)
    assert(text.Effect(game, "coin_2048") == Items.byId.coin_2048.effect)
end)

---@return integer passed 失败时一次性报告所有独立案例，方便定位跨模块接线缺漏。
function Tests.Run()
    local passed = 0
    ---@type string[]
    local failures = {}
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then
            passed = passed + 1
        else
            failures[#failures + 1] = case.name .. "：" .. tostring(message)
        end
    end
    assert(#failures == 0, "Bottle.ExtraTests " .. passed .. "/" .. #cases
        .. " 通过\n" .. table.concat(failures, "\n"))
    return passed
end

return Tests
