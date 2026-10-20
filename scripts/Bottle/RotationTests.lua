-- #94-97专项：正式Repair.Fixture / Game:Step / 生命周期，不创建场景、不读写玩家存档。
-- RotationEffects接线后由Tests.Run统一调用；纯规则输入不冒充真实Box2D动画验收。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Repair = require("Bottle.RepairTests")
local Rotation = require("Bottle.RotationEffects")
local Tests = {}
local TURN = math.pi * 2

---@param actual any
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        (label or "数值") .. ": expected=" .. expected .. " actual=" .. tostring(actual))
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
---@param expected {maximum:integer,value:integer}[]
---@return fun()
local function Sequence(game, expected)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local entry = assert(expected[index], "发生额外随机判定")
        assert(maximum == entry.maximum and entry.value >= 1 and entry.value <= maximum,
            "随机范围不符：" .. maximum .. " expected=" .. entry.maximum)
        return entry.value
    end)
    return function()
        rawset(game, "_RandomInt", nil)
        assert(index == #expected, "遗漏随机判定")
    end
end

---@param game any
---@param id string
---@return any[]
local function Find(game, id)
    local result = {}
    for _, item in ipairs(game:AllInstances()) do
        if item.id == id then result[#result + 1] = item end
    end
    return result
end

---@param game any
local function Finish(game)
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "draft")
end

---@type {name:string,run:fun()}[]
Tests.cases = {}
---@param name string
---@param run fun()
local function Test(name, run) Tests.cases[#Tests.cases + 1] = { name = name, run = run } end

Test("四物品编号基础品质与冷却由真实目录定义", function()
    for index, row in ipairs({
        { id = "spinning_top", base = 3, rarity = 1 },
        { id = "windmill", base = 4, rarity = 2 },
        { id = "gear", base = 4, rarity = 2 },
        { id = "roulette", base = 4, rarity = 2 },
    }) do
        local def = assert(Items.byId[row.id])
        assert(def.numberId == 93 + index and def.implemented and def.pool)
        Close(def.base, row.base); Close(def.rarity, row.rarity)
        assert(Items.byNumber[93 + index] == def)
    end
    Close(Items.byId.gear.cooldown, 4)
    assert(Items.HasCooldown("gear"))
end)

Test("专用Step不进入自动Touches冷却也不抢旧类型", function()
    local game = Fixture({ "spinning_top", "windmill", "gear", "roulette", "apple" })
    local state = game:_ContactSnapshot({ pairs = {{3,5}} })
    for uid = 1, 4 do
        assert(Rotation.Touches(game, Item(game, uid), state) == false)
        assert(not Rotation.Apply(game, Item(game, uid), state, {}))
    end
    assert(Rotation.Touches(game, Item(game, 5), state) == nil)
    game:Step(0, state)
    Close(Item(game, 3).remaining, 4)
    game:Step(0, state)
    Close(Item(game, 3).remaining, 4, "重复Touches不能改写齿轮冷却")
end)

Test("陀螺按自然绝对角程满圈加临时值且多圈保余程", function()
    local game = Fixture({ "spinning_top" })
    rawset(game, "_RandomInt", function(_, maximum) return math.min(maximum, 30) end)
    local top = Item(game, 1)
    game:Step(0, {angularTravel={[1]=TURN-.1}})
    Close(top.bonus, 0)
    local events = game:Step(0, {angularTravel={[1]=TURN}})
    Close(top.bonus, 1); Close(top.permBonus, 0)
    assert(#Repair.Events(events, "buff", 1) == 1)
    game:Step(0, {angularTravel={[1]=3*TURN+.25}})
    Close(top.bonus, 3); Close(top.rotationProgress, .25)
    game:Step(0, {angularTravel={[1]=3*TURN+.25}})
    Close(top.bonus, 3); Close(game.score, 0, "增值不是即时金币")
    Finish(game)
    Close(top.bonus, 0); Close(top.permBonus, 0); Close(top.rotationProgress, 0)
end)

Test("angle回退包含反转和跨pi连续转角且排除强制offset", function()
    local game = Fixture({ "spinning_top" })
    rawset(game, "_RandomInt", function(_, maximum) return math.min(maximum, 30) end)
    game:Step(0, {angles={[1]=0}})
    for _ = 1, 4 do
        game:Step(0, {angles={[1]=math.pi*.75}})
        game:Step(0, {angles={[1]=0}})
    end
    Close(Item(game, 1).bonus, 3, "净角0仍有6pi路程")
    game:Step(0, {angles={[1]=-4*TURN},rotateOffsets={[1]=-4*TURN}})
    Close(Item(game, 1).bonus, 3, "强制多圈不产生奖励")
    local sample = {}
    Close(Rotation.SampleNatural(sample, {angles={}}, "wrap"), 0)
    sample.uid = 1
    Close(Rotation.SampleNatural(sample, {angles={[1]=math.pi-.1}}, "wrap"), 0)
    Close(Rotation.SampleNatural(sample, {angles={[1]=-math.pi+.1}}, "wrap"), .2)
end)

Test("采样channel独立且重建归零不反向发奖", function()
    local item = {uid=1}
    for _, channel in ipairs({"item", "compass", "spin_reward"}) do
        Close(Rotation.SampleNatural(item, {angularTravel={[1]=1}}, channel), 1)
        Close(Rotation.SampleNatural(item, {angularTravel={[1]=1}}, channel), 0)
    end
    Close(Rotation.SampleNatural(item, {angularTravel={[1]=0}}, "item"), 0)
    Close(Rotation.SampleNatural(item, {angularTravel={[1]=.25}}, "item"), .25)
    Close(Rotation.SampleNatural(item, {}, "item"), 0)
    Close(Rotation.SampleNatural(item, {angularTravel={[1]=.25}}, "item"), 0)
end)

Test("风车每圈三等份抽临时产物并沿源位置生成", function()
    local game = Fixture({ "windmill" })
    local done = Sequence(game, {{maximum=3,value=1},{maximum=3,value=2},{maximum=3,value=3}})
    local events = game:Step(0, {angularTravel={[1]=3*TURN},positions={[1]={x=.3,y=2.1}}})
    done()
    for index, id in ipairs({"droplet", "wool", "grass"}) do
        local found = Find(game, id)
        assert(#found == 1 and found[1].temporary and found[1].generatedTemporary)
        local spawn = Repair.Events(events, "spawn", found[1].uid)
        assert(#spawn == 1); Close(spawn[1].x, .3); Close(spawn[1].y, 2.1)
        assert(found[1].uid == index + 1)
    end
    Finish(game)
    for _, id in ipairs({"droplet", "wool", "grass"}) do assert(#Find(game, id) == 0) end
end)

Test("满瓶风车临时产物FIFO不丢失且排队不推进旋转", function()
    local game = Fixture({ "windmill" })
    for _ = 2, 100 do assert(game:_Spawn("apple", {})) end
    local older = assert(game:_Spawn("orange", {}, false, {x=-.4,y=3}))
    local done = Sequence(game, {{maximum=3,value=2},{maximum=3,value=1}})
    local events = game:Step(0, {angularTravel={[1]=2*TURN},positions={[1]={x=.2,y=2}}})
    done()
    assert(#Repair.Events(events, "spawn") == 0 and #game.spawnQueue == 3)
    local wool, water = Find(game, "wool")[1], Find(game, "droplet")[1]
    assert(wool.location == "queued" and water.location == "queued")
    assert(game.spawnQueue[1] == older.uid and game.spawnQueue[2] == wool.uid
        and game.spawnQueue[3] == water.uid)
    Close(game._queueOrigins[wool.uid].x, .2); Close(game._queueOrigins[wool.uid].y, 2)
    game:Consume(2)
    assert(older.location == "bottle" and wool.location == "queued")
    Finish(game)
    assert(game:Get(wool.uid) == nil and game:Get(water.uid) == nil)
    assert(older.location == "deck", "永久旧队列不被临时批误清")
end)

Test("转盘基础正负两种结果永久且幸运符仅改负1", function()
    for _, lucky in ipairs({false, true}) do
        local game = Fixture({ "roulette" }, lucky and {lucky_charm=true} or {})
        local done = Sequence(game, {{maximum=2,value=1},{maximum=2,value=2}})
        local events = game:Step(0, {angularTravel={[1]=2*TURN}})
        done()
        Close(Item(game, 1).permBonus, lucky and 4 or 2)
        Close(Item(game, 1).bonus, 0); Close(game.score, 0)
        assert(#Repair.Events(events, "buff", 1) == 2)
        Finish(game)
        local restored = Game.Restore(game:Snapshot())
        Close(Item(restored, 1).permBonus, lucky and 4 or 2)
    end
end)

Test("幸运转盘5%大奖只发临时77不额外抽基础奖", function()
    local game = Fixture({ "roulette" }, {lucky_roulette=true,lucky_charm=true})
    Item(game, 1).permBonus = -5
    local done = Sequence(game, {{maximum=20,value=1}})
    local events = game:Step(0, {angularTravel={[1]=TURN}})
    done()
    Close(Item(game, 1).bonus, 77); Close(Item(game, 1).permBonus, -5)
    assert(#Repair.Events(events, "buff", 1) == 1)
    Close(game.score, 0)
    Finish(game)
    Close(Item(game, 1).bonus, 0); Close(Item(game, 1).permBonus, -5)
    local restored = Game.Restore(game:Snapshot())
    Close(Item(restored, 1).bonus, 0); Close(Item(restored, 1).permBonus, -5)
end)

Test("幸运转盘其余19签各自再50%基础判定", function()
    for ticket = 2, 20 do
        for result = 1, 2 do
            local game = Fixture({ "roulette" }, {lucky_roulette=true})
            local done = Sequence(game, {{maximum=20,value=ticket},{maximum=2,value=result}})
            game:Step(0, {angularTravel={[1]=TURN}})
            done()
            Close(Item(game, 1).bonus, 0)
            Close(Item(game, 1).permBonus, result == 1 and 3 or -1)
        end
    end
end)

Test("齿轮固定标记初始邻居并共转邻居角路程之和", function()
    local game = Fixture({ "gear", "apple", "orange", "ball" })
    -- 标记前历史不计，齿轮自身角程不计；重复pairs不能重复标记。
    game:Step(0, {pairs={{1,2},{1,3},{2,1}},angularTravel={[1]=100,[2]=10,[3]=20}})
    local gear = Item(game, 1)
    assert(#gear.gearBatch == 2); Close(gear.remaining, 4)
    local mid = game:Step(2, {pairs={{1,4}},angularTravel={[1]=101,[2]=11,[3]=22,[4]=100}})
    assert(#Repair.Events(mid, "rotate") == 0 and #gear.gearBatch == 2)
    local events = game:Step(2, {pairs={{1,4}},angularTravel={[1]=200,[2]=13,[3]=24,[4]=200}})
    local rotates = Repair.Events(events, "rotate")
    assert(#rotates == 3 and #Repair.Events(events, "rotate", 4) == 0)
    for _, event in ipairs(rotates) do
        Close(event.delta, -7, "A走3+B走4，所有目标均共转7而非各自角")
        Close(event.duration, 1); assert(event.excludeCompass)
    end
    assert(gear.gearBatch == nil); Close(gear.gearPlayback, 1); Close(gear.remaining, 0)
end)

Test("齿轮回放完整1秒后才重新标记并开始完整4秒", function()
    local game = Fixture({ "gear", "apple", "orange" })
    game:Step(0, {pairs={{1,2}},angularTravel={[2]=0}})
    game:Step(4, {pairs={{1,3}},angularTravel={[2]=2,[3]=8}})
    local gear = Item(game, 1)
    assert(gear.gearBatch == nil); Close(gear.gearPlayback, 1); Close(gear.remaining, 0)
    game:Step(.99, {pairs={{1,3}},angularTravel={[3]=9}})
    assert(gear.gearBatch == nil); Close(gear.gearPlayback, .01); Close(gear.remaining, 0)
    game:Step(.01, {pairs={{1,3}},angularTravel={[3]=10}})
    ---@type BottleRotationBatchEntry[]
    local batch = assert(gear.gearBatch)
    assert(#batch == 1 and batch[1].uid == 3)
    Close(gear.remaining, 4); Close(gear.gearPlayback, 0)
    game:Step(3.99, {angularTravel={[3]=11}})
    Close(gear.remaining, .01)
    local nextBatch = game:Step(.01, {angularTravel={[3]=13}})
    for _, event in ipairs(Repair.Events(nextBatch, "rotate")) do Close(event.delta, -3) end
    assert(#Repair.Events(nextBatch, "rotate") == 2)
end)

Test("齿轮无邻居不空转回放后无邻居等待新接触", function()
    local game = Fixture({ "gear", "apple" })
    game:Step(1, {})
    local gear = Item(game, 1)
    Close(gear.remaining, 0); assert(gear.gearBatch == nil)
    game:Step(0, {pairs={{1,2}},angularTravel={[2]=0}})
    game:Step(4, {angularTravel={[2]=0}})
    game:Step(1, {})
    Close(gear.remaining, 0); assert(gear.gearBatch == nil)
    local idle = game:Step(1, {})
    assert(#Repair.Events(idle, "rotate") == 0)
    game:Step(0, {pairs={{1,2}},angularTravel={[2]=10}})
    Close(gear.remaining, 4)
    ---@type BottleRotationBatchEntry[]
    local batch = assert(gear.gearBatch)
    local first = assert(batch[1])
    Close(first.travel, 0)
end)

Test("齿轮保留离场前角贡献但只回放仍在场原标记物", function()
    local game = Fixture({ "gear", "apple", "orange", "ball" })
    game:Step(0, {pairs={{1,2},{1,3}},angularTravel={[2]=0,[3]=0}})
    game:Step(2, {angularTravel={[2]=2,[3]=1}})
    game:Consume(2)
    local events = game:Step(2, {pairs={{1,4}},angularTravel={[2]=99,[3]=4,[4]=99}})
    local rotates = Repair.Events(events, "rotate")
    assert(#rotates == 2 and #Repair.Events(events, "rotate", 2) == 0
        and #Repair.Events(events, "rotate", 4) == 0)
    for _, event in ipairs(rotates) do Close(event.delta, -6) end
end)

Test("齿轮角回退反转照计不受当前接触消失影响", function()
    local game = Fixture({ "gear", "apple" })
    game:Step(0, {pairs={{1,2}},angles={[2]=0}})
    game:Step(1, {angles={[2]=math.pi/2}})
    game:Step(1, {angles={[2]=0}})
    game:Step(1, {angles={[2]=-math.pi/2}})
    local events = game:Step(1, {angles={[2]=0}})
    assert(#Repair.Events(events, "rotate") == 2)
    for _, event in ipairs(Repair.Events(events, "rotate")) do Close(event.delta, -TURN) end
end)

Test("齿轮与指南针强制offset均不回灌其他旋转效果", function()
    local game = Fixture({ "gear", "spinning_top", "compass" }, {spin_reward=true})
    local done = Sequence(game, {})
    game:Step(0, {pairs={{1,2},{1,3}},angles={[1]=0,[2]=0,[3]=0}})
    -- 先给batch成员一个自然pi；回放总量pi，不让强制多圈冒领奖励或触发三圈概率签。
    game:Step(4, {angles={[1]=0,[2]=math.pi,[3]=0}})
    local forced = -3*TURN
    local replayed = game:Step(1, {angles={[1]=forced,[2]=math.pi+forced,[3]=forced},
        rotateOffsets={[1]=forced,[2]=forced,[3]=forced}})
    Close(Item(game, 2).bonus, 0); Close(game.score, 0)
    Close(Item(game, 3).compassProgress, 0)
    assert(#Repair.Events(replayed, "rotate") == 0)
    done()
end)

Test("齿轮豁免幽灵及遗物幽灵便便但不豁免飞盘", function()
    for _, ghostPoop in ipairs({false, true}) do
        local game = Fixture({ "gear", "ghost", "diamond_poop", "discus" },
            ghostPoop and {ghost_poop=true} or {})
        local state = {pairs={{1,2},{1,3},{1,4}},angularTravel={[2]=0,[3]=0,[4]=0}}
        game:Step(0, state)
        state.angularTravel[4] = 2
        local events = game:Step(4, state)
        assert(#Repair.Events(events, "rotate", 2) == 0)
        assert(#Repair.Events(events, "rotate", 3) == (ghostPoop and 0 or 1))
        assert(#Repair.Events(events, "rotate", 4) == 1)
    end
end)

Test("回合清理与存档不保存旋转进度标记或动画", function()
    local game = Fixture({ "gear", "spinning_top", "roulette" })
    game:Step(0, {pairs={{1,2}},angularTravel={[2]=.5}})
    Item(game, 3).permBonus = 9
    local gear = Item(game, 1)
    assert(gear.gearBatch and Item(game, 2).rotationSamples)
    Finish(game)
    assert(gear.gearBatch == nil and gear.rotationSamples == nil)
    Close(gear.gearPlayback, 0); Close(Item(game, 2).rotationProgress, 0)
    local snapshot = game:Snapshot()
    for _, saved in ipairs(snapshot.instances) do
        assert(saved.gearBatch == nil and saved.rotationSamples == nil,
            "存档不携带运行时标记/采样表")
        assert((saved.gearPlayback == nil or saved.gearPlayback == 0)
            and (saved.rotationProgress == nil or saved.rotationProgress == 0),
            "存档只允许已清理的旋转零值，不允许半回合进度")
    end
    for _, key in ipairs({"gearPlayback", "rotationProgress", "gearBatch", "rotationSamples"}) do
        local polluted = game:Snapshot()
        polluted.instances[1][key] = (key == "gearPlayback" or key == "rotationProgress") and .1 or {}
        assert(not pcall(Game.Restore, polluted), "污染旋转状态必须拒绝：" .. key)
    end
    local restored = Game.Restore(snapshot)
    Close(Item(restored, 3).permBonus, 9)
    assert(Item(restored, 1).gearBatch == nil)
    assert(restored:Skip()); assert(restored:Start())
    local first = restored:Step(0, {})
    assert(#Repair.Events(first, "rotate") == 0)
    Close(Item(restored, 1).remaining, 0)
end)

Test("非running和排队实例不推进新旋转模块", function()
    local game = Fixture({ "spinning_top", "gear", "apple" })
    local top = Item(game, 1)
    top.location = "queued"
    Rotation.Step(game, 4, {pairs={},angularTravel={[1]=100*TURN}}, {})
    Close(top.bonus, 0)
    top.location = "bottle"
    game.phase = "settle"
    local events = {}
    Rotation.Step(game, 4, {pairs={{2,3}},angularTravel={[1]=TURN}}, events)
    Close(top.bonus, 0); assert(#events == 0 and Item(game, 2).gearBatch == nil)
end)

Test("时长端点仍发旋转收益而settle后不再触发", function()
    local game = Fixture({ "spinning_top" })
    rawset(game, "_RandomInt", function(_, maximum) return math.min(maximum, 30) end)
    local events = game:Step(game:Duration(), {angularTravel={[1]=TURN}})
    assert(game.phase == "settle")
    Close(Item(game, 1).bonus, 1)
    assert(#Repair.Events(events, "buff", 1) == 1)
    local after = game:Step(0, {angularTravel={[1]=2*TURN}})
    Close(Item(game, 1).bonus, 1); assert(#after == 0)
end)

Test("ResetRound只清运行态保留永久值及物理姿态", function()
    local item = {uid=1,id="gear",bonus=2,permBonus=5,permMult=2,scale=1.5,weight=.7,
        physicalAngle=-7,rotationProgress=3,rotationSamples={item={travel=10}},
        gearBatch={{uid=2,travel=3}},gearPlayback=.5}
    Rotation.ResetRound(item)
    Close(item.permBonus, 5); Close(item.permMult, 2); Close(item.scale, 1.5)
    Close(item.weight, .7); Close(item.physicalAngle, -7); Close(item.bonus, 2)
    Close(item.rotationProgress, 0); Close(item.gearPlayback, 0)
    assert(item.rotationSamples == nil and item.gearBatch == nil)
end)

---@return integer
function Tests.Run()
    local passed = 0
    for _, case in ipairs(Tests.cases) do
        local ok, message = pcall(case.run)
        assert(ok, "[RotationTests] " .. case.name .. ": " .. tostring(message))
        passed = passed + 1
    end
    print("[RotationTests] PASS " .. passed)
    return passed
end

return Tests
