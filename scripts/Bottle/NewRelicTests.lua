-- 补齐源表遗物25-33与云朵/壁虎跨层回归。真Game规则、内存快照；不读写玩家存档。
-- 物理选项的实际速度/传感器验收由ExpansionPhysicsValidation独立负责。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Repair = require("Bottle.RepairTests")
local RelicExpansion = require("Bottle.RelicExpansion")
local Tests = {}
local TURN = math.pi * 2
local IDS = {"teacher_team", "accelerator", "ghost_poop", "premium_grass", "food_comfort",
    "bacon_network", "ghost_sport", "spin_reward", "wool_market"}

---@param actual number?
---@param expected number
local function Close(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        "expected=" .. expected .. " actual=" .. tostring(actual))
end
---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid)) end
---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
local function Fixture(ids, relics) return Repair.Fixture(ids, relics) end
---@param game BottleGame
---@param id string
---@param location string?
---@return ItemInstance[]
local function Find(game, id, location)
    local result = {}
    for _, item in ipairs(game:AllInstances()) do
        if item.id == id and (not location or item.location == location) then result[#result+1] = item end
    end
    return result
end
---@param game BottleGame
---@param expected {maximum:integer,value:integer}[]
---@return fun()
local function Sequence(game, expected)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local entry = assert(expected[index], "发生额外随机判定")
        assert(maximum == entry.maximum and entry.value >= 1 and entry.value <= maximum,
            "随机请求范围或值不符")
        return entry.value
    end)
    return function()
        assert(index == #expected, "遗漏随机判定")
        rawset(game, "_RandomInt", nil)
    end
end
---@param game BottleGame
local function Finish(game)
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "draft")
end
---@param a any
---@param b any
---@return boolean
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases+1] = {name=name,run=run} end

Test("新增9遗物逐ID编号品质已接线且候选去重", function()
    local rarities = {2,2,2,1,2,2,1,2,1}
    local game = Fixture({})
    assert(#Relics.list == 37 and #Relics.Available(game) == 37)
    for index, id in ipairs(IDS) do
        local def = assert(Relics.byId[id])
        assert(def.numberId == 24+index and def.rarity == rarities[index])
        assert(def.implemented and def.pool and Relics.byNumber[24+index] == def)
        game.relics[id] = true
    end
    local seen = {}
    for _, def in ipairs(Relics.Available(game)) do
        assert(not game.relics[def.id] and not seen[def.id]); seen[def.id] = true
    end
    assert(#Relics.Available(game) == 28)
    local restored = Game.Restore(game:Snapshot())
    for _, id in ipairs(IDS) do assert(restored.relics[id]) end
end)

Test("名师合成加法项与倍率分别继承、不把有效值再乘一次", function()
    local game = Fixture({"teacher", "teacher"}, {teacher_team=true})
    assert(game:Start())
    local a, b = Item(game,1), Item(game,2)
    a.valueBase, a.bonus, a.permBonus, a.permMult, a.eventMult, a.mult = 10,2,3,1.5,2,8
    b.valueBase, b.bonus, b.permBonus, b.permMult, b.eventMult, b.mult = 7,1,4,2,3,12
    local events = game:Step(0, {pairs={{1,2}},positions={[1]={x=-1,y=2},[2]={x=1,y=4}}})
    local merged = Find(game,"teacher","bottle")
    assert(#merged == 1 and merged[1].uid > 2 and a.location == "discard" and b.location == "discard")
    local result = merged[1]
    Close(result.valueBase,27); Close(result.permBonus,0); Close(result.bonus,0)
    Close(result.permMult,3); Close(result.eventMult,6); Close(game:_Value(result),486)
    local merge = Repair.Events(events,"merge",result.uid)
    assert(#merge == 1); Close(merge[1].x,0); Close(merge[1].y,3)
    Finish(game)
    local restored = Game.Restore(game:Snapshot())
    Close(Item(restored,result.uid).valueBase,27); Close(Item(restored,result.uid).permMult,3)
    Close(restored:_Value(Item(restored,result.uid)),81)
end)

Test("无名师不合成、有护盾原子拒绝不单耗一位老师", function()
    local ordinary = Fixture({"teacher","teacher"})
    assert(ordinary:Start()); ordinary:Step(0,{pairs={{1,2}}})
    assert(#Find(ordinary,"teacher","bottle") == 2)
    local guarded = Fixture({"teacher","teacher","bodyguard"},{teacher_team=true})
    assert(guarded:Start()); guarded:Step(0,{pairs={{1,2}}})
    assert(Item(guarded,1).location == "bottle" and Item(guarded,2).location == "bottle")
    assert(#Find(guarded,"teacher","bottle") == 2 and #guarded.discard == 0)
    Close(Item(guarded,3).counter,1)
end)

Test("食物+2按tag进入括号并乘倍率、不改共享base或永久加值", function()
    local game = Fixture({"apple","juice","grass","teacher"},{food_comfort=true})
    local apple = Item(game,1)
    apple.permBonus, apple.permMult = 3, 1.5
    assert(game:Start())
    apple.eventMult,apple.mult = 2,2
    Close(game:_Value(apple),21)
    Close(game:_Value(Item(game,2)),5); Close(game:_Value(Item(game,3)),3)
    Close(game:_Value(Item(game,4)),6)
    Close(Items.byId.apple.base,2); Close(apple.permBonus,3)
    for _=1,3 do Close(game:_Value(apple),21) end
    Finish(game)
    local restored = Game.Restore(game:Snapshot())
    Close(restored:_Value(Item(restored,1)),10.5); Close(Item(restored,1).permBonus,3)
end)

Test("幽灵便便仅使四种便便穿透、不修改基础定义", function()
    local game = Fixture({}, {ghost_poop=true})
    local ordinary = Fixture({})
    for _, id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        assert(Items.IsPiercing(id,game) and not Items.IsPiercing(id,ordinary))
        assert(not Items.byId[id].piercing)
    end
    assert(Items.IsPiercing("ghost",ordinary) and Items.IsPiercing("discus",ordinary))
    assert(not Items.IsPiercing("apple",game))
end)

Test("幽灵便便可触发分裂器、无遗物普通便便不可穿透分裂", function()
    for _, enabled in ipairs({false,true}) do
        local game = Fixture({"splitter","poop"}, enabled and {ghost_poop=true} or {})
        assert(game:Start()); game:Step(0,{pairs={{1,2}}})
        assert(#Find(game,"poop","bottle") == (enabled and 2 or 1))
    end
end)

Test("优质小草动物60分母精确边界、人类仍100分母含不产出", function()
    for _, entry in ipairs({{1,"poop"},{40,"poop"},{41,"golden_poop"},{55,"golden_poop"},
        {56,"diamond_poop"},{59,"diamond_poop"},{60,"rainbow_poop"}}) do
        local game = Fixture({"calf","grass"},{premium_grass=true})
        assert(game:Start())
        local done = Sequence(game,{{maximum=60,value=entry[1]}})
        assert(game:_Destroy(2,false,{},Item(game,1),"consume")); done()
        assert(#Find(game,entry[2],"bottle") == 1)
    end
    local human = Fixture({"glutton","grass"},{premium_grass=true})
    assert(human:Start())
    local done = Sequence(human,{{maximum=100,value=1}})
    assert(human:_Destroy(2,false,{},Item(human,1),"consume")); done()
    assert(#Find(human,"poop") == 0 and #Find(human,"golden_poop") == 0)
end)

Test("羊毛集市刀脱库存兑换永久硬币、不直接发钱且只奖创建一次", function()
    local game = Fixture({"knife","sheep"},{wool_market=true,small_savings=true})
    Item(game,2).woolCount = 3
    assert(game:Start())
    local done = Sequence(game,{{maximum=101,value=51},{maximum=101,value=51},{maximum=101,value=51}})
    local before = game.score
    local events = game:Step(0,{pairs={{1,2}}}); done()
    assert(#Find(game,"wool") == 0 and #Find(game,"coin_1","bottle") == 3)
    Close(Item(game,2).woolCount,0); Close(game.score-before,3)
    for _, coin in ipairs(Find(game,"coin_1")) do
        assert(not coin.generatedTemporary); Close(game:_Value(coin),1)
        local spawn = Repair.Events(events,"spawn",coin.uid); assert(#spawn == 1); Close(spawn[1].y,6)
    end
    local score = game.score
    Game.Restore(game:Snapshot()); Close(game.score,score)
end)

Test("幽灵运动逐30米固定金币、非幽灵/重采样/传送不领奖", function()
    local game = Fixture({"ghost","apple"},{ghost_sport=true})
    assert(game:Start())
    Item(game,1).permBonus,Item(game,1).permMult = 50,3
    game:Step(0,{positions={[1]={x=0,y=0},[2]={x=0,y=0}}})
    for index=1,60 do
        local position = {x=index*.5,y=0}
        game:Step(0,{positions={[1]=position,[2]=position}})
        if index == 10 or index == 59 then Close(game.roundScore,0) end
    end
    Close(game.roundScore,1); Close(Item(game,1).ghostTravel,0)
    for index=61,62 do
        game:Step(0,{positions={[1]={x=index*.5,y=0}}})
    end
    Close(game.roundScore,1); Close(Item(game,1).ghostTravel,1)
    game:_TeleportTop(Item(game,1),{})
    game:Step(0,{positions={[1]={x=0,y=6}}})
    Close(game.roundScore,1); Close(Item(game,1).ghostTravel,1)
    local events = {}
    RelicExpansion.TrackDistance(game,Item(game,1),94,events)
    Close(game.roundScore,4); Close(Item(game,1).ghostTravel,5)
    assert(#Repair.Events(events,"score",1) == 3)
    local nextEvents = {}
    RelicExpansion.TrackDistance(game,Item(game,1),25,nextEvents)
    Close(game.roundScore,5); Close(Item(game,1).ghostTravel,0)
    assert(#Repair.Events(nextEvents,"score",1) == 1)
end)

Test("转圈圈每三圈30/31边界、失败耗进度、多批保余角与重建不重领", function()
    local game = Fixture({"apple"},{spin_reward=true})
    assert(game:Start()); Item(game,1).permBonus = 100
    local done = Sequence(game,{{maximum=100,value=30},{maximum=100,value=31},
        {maximum=100,value=100},{maximum=100,value=1}})
    game:Step(0,{angularTravel={[1]=TURN*2+.4}})
    Close(game.roundScore,0); Close(Item(game,1).spinProgress,TURN*2+.4)
    game:Step(0,{angularTravel={[1]=TURN*2+.4}})
    game:Step(0,{angularTravel={[1]=0}})
    Close(game.roundScore,0); Close(Item(game,1).spinProgress,TURN*2+.4)
    game:Step(0,{angularTravel={[1]=TURN-.4}})
    Close(game.roundScore,1); Close(Item(game,1).spinProgress,0)
    game:Step(0,{angularTravel={[1]=TURN*4-.4}})
    Close(game.roundScore,1); Close(Item(game,1).spinProgress,0)
    local events = game:Step(0,{angularTravel={[1]=TURN*10-.15}})
    Close(game.roundScore,2); Close(Item(game,1).spinProgress,.25)
    assert(#Repair.Events(events,"score",1) == 1)
    done()
end)

Test("转圈圈反向绝对角路程仍计、强制转向不计且回合进度清理", function()
    local reverse = Fixture({"apple"},{spin_reward=true})
    assert(reverse:Start())
    local done = Sequence(reverse,{{maximum=100,value=30}})
    reverse:Step(0,{angles={[1]=0}})
    reverse:Step(0,{angles={[1]=math.pi/2},rotateOffsets={[1]=math.pi/2}})
    Close(Item(reverse,1).spinProgress,0)
    for _=1,6 do
        reverse:Step(0,{angles={[1]=0},rotateOffsets={[1]=math.pi/2}})
        reverse:Step(0,{angles={[1]=math.pi/2},rotateOffsets={[1]=math.pi/2}})
    end
    Close(reverse.roundScore,1); Close(Item(reverse,1).spinProgress,0)
    done()
    Item(reverse,1).spinProgress = TURN*2+.1
    Finish(reverse)
    Close(Item(reverse,1).spinProgress,0)
    assert(Item(reverse,1).spinTravel == nil and Item(reverse,1).spinAngle == nil)
end)

Test("转圈圈百分签精确30中70空、无遗物与不足三圈均不抽签", function()
    ---@type number
    local wins = 0
    for ticket=1,100 do
        local game = Fixture({"apple"},{spin_reward=true})
        assert(game:Start())
        local done = Sequence(game,{{maximum=100,value=ticket}})
        game:Step(0,{angularTravel={[1]=TURN*3}}); done()
        Close(game.roundScore,ticket<=30 and 1 or 0)
        Close(Item(game,1).spinProgress,0)
        wins = wins + game.roundScore
    end
    Close(wins,30)
    local ordinary = Fixture({"apple"})
    assert(ordinary:Start())
    local done = Sequence(ordinary,{})
    ordinary:Step(0,{angularTravel={[1]=TURN*30}}); done()
    Close(ordinary.roundScore,0)
    local partial = Fixture({"apple"},{spin_reward=true})
    assert(partial:Start()); done = Sequence(partial,{})
    partial:Step(0,{angularTravel={[1]=TURN*3-.01}}); done()
    Close(partial.roundScore,0); Close(Item(partial,1).spinProgress,TURN*3-.01)
end)

Test("培根仅真实直接邻居成团、不递归传播两根培根链", function()
    local game = Fixture({"bacon","apple","knife","bacon","ball"},{bacon_network=true})
    assert(game:Start())
    local state = game:_ContactSnapshot({pairs={{1,2},{1,3},{1,4},{4,5}}})
    local seen = {}
    for _, pair in ipairs(state.pairs) do seen[pair[1]..":"..pair[2]] = true end
    assert(seen["2:3"] and seen["2:4"] and seen["3:4"] and seen["1:5"])
    assert(not seen["2:5"] and not seen["3:5"], "不得把整连通分量变为邻接团")
    assert(state.rawPairs and #state.rawPairs == 4)
    local original = Fixture({"bacon","apple","knife"})
    assert(original:Start()); local raw = original:_ContactSnapshot({pairs={{1,2},{1,3}}})
    assert(#raw.pairs == 2)
end)

Test("培根派生接触可切水果、消费后清理派生不复用旧邻接", function()
    local game = Fixture({"bacon","knife","apple"},{bacon_network=true})
    assert(game:Start()); game:Step(0,{pairs={{1,2},{1,3}}})
    assert(#Find(game,"apple_half","bottle") == 2)
    assert(Item(game,3).id == "apple_half")
end)

Test("培根派生邻接不触发分裂器果冻或小牛真实碰撞收益", function()
    local split = Fixture({"bacon","splitter","ghost"},{bacon_network=true})
    assert(split:Start()); split:Step(0,{pairs={{1,2},{1,3}}})
    assert(#Find(split,"ghost","bottle") == 1 and Item(split,3).location == "bottle")
    local jelly = Fixture({"bacon","jelly","apple"},{bacon_network=true})
    assert(jelly:Start()); local events = jelly:Step(0,{pairs={{1,2},{1,3}}})
    assert(#Repair.Events(events,"impulse",1) == 1 and #Repair.Events(events,"impulse",3) == 0)
    local calf = Fixture({"bacon","calf","apple"},{bacon_network=true})
    assert(calf:Start()); Item(calf,2).calfDashRemaining,Item(calf,2).calfDashHits = .35,{}
    calf:Step(0,{pairs={{1,2},{1,3}}})
    Close(Item(calf,2).bonus,1) -- 仅真实接触培根，派生苹果不再加1。
    Close(Item(calf,2).permBonus,0)
end)

Test("云周期20%分支追加6临时瓶顶、普通产物永久近源", function()
    for _, coinRain in ipairs({false,true}) do
        for _, outcome in ipairs({1,2}) do
            local game = Fixture({"cloud"},coinRain and {coin_rain=true} or {})
            assert(game:Start()); local expected = {{maximum=5,value=outcome}}
            if outcome == 1 then for _=1,6 do expected[#expected+1]={maximum=101,value=51} end end
            local done = Sequence(game,expected)
            assert(#Repair.Events(game:Step(4.99),"spawn") == 0)
            local events = game:Step(.01,{positions={[1]={x=.2,y=3}}}); done()
            local id = coinRain and "coin_1" or "droplet"
            local generated = Find(game,id,"bottle")
            assert(#generated == (outcome == 1 and 7 or 1))
            local temporary = 0
            for _, item in ipairs(generated) do
                local spawn = Repair.Events(events,"spawn",item.uid); assert(#spawn == 1)
                if item.generatedTemporary then temporary=temporary+1; Close(spawn[1].y,6)
                else Close(spawn[1].x,.2); Close(spawn[1].y,3) end
            end
            assert(temporary == (outcome == 1 and 6 or 0))
            Finish(game)
            assert(#Find(game,id) == 1 and #Find(game,id,"deck") == 1)
            Game.Restore(game:Snapshot())
        end
    end
end)

Test("云满瓶永久及临时产物FIFO且末尾仅永久保留", function()
    local game = Fixture({"cloud"})
    assert(game:Start())
    while #game:BottleItems()<100 do game:_Spawn("ball",{}) end
    local expected = {{maximum=5,value=1}}
    for _=1,6 do expected[#expected+1]={maximum=101,value=51} end
    local done = Sequence(game,expected)
    game:Step(5); done()
    assert(#game.spawnQueue == 7)
    local permanent = Item(game,game.spawnQueue[1]); assert(not permanent.generatedTemporary)
    for index=2,7 do assert(Item(game,game.spawnQueue[index]).generatedTemporary) end
    game:Consume(2); assert(permanent.location == "bottle")
    Finish(game)
    assert(game:Get(permanent.uid) == permanent and permanent.location == "deck")
    assert(#Find(game,"droplet") == 1 and #game.spawnQueue == 0)
end)

Test("壁虎延迟连续接触且中断重置、顶部/底部不能粘", function()
    local game = Fixture({"gecko"})
    assert(game:Start()); game:Step(.24,{side={[1]=true}})
    assert(not Item(game,1).anchored); Close(Item(game,1).geckoContactTime,.24)
    game:Step(0); Close(Item(game,1).geckoContactTime,0)
    game:Step(.24,{side={[1]=true}}); assert(not Item(game,1).anchored)
    local events = game:Step(.01,{side={[1]=true}})
    assert(Item(game,1).anchored and #Repair.Events(events,"anchor",1) == 1)
    assert(#Repair.Events(game:Step(1,{side={[1]=true}}),"anchor",1) == 0)
    local wrong = Fixture({"gecko"}); assert(wrong:Start())
    wrong:Step(.5,{bottom={[1]=true},top={[1]=true},wall={[1]=true}})
    assert(not Item(wrong,1).anchored)
end)

Test("壁虎接触未锚壁虎也可粘、培根派生连接不算真连接", function()
    local game = Fixture({"gecko","gecko"})
    assert(game:Start()); game:Step(.25,{pairs={{1,2}}})
    assert(Item(game,1).anchored and Item(game,2).anchored)
    local derived = Fixture({"bacon","gecko","gecko"},{bacon_network=true})
    assert(derived:Start()); derived:Step(.5,{pairs={{1,2},{1,3}}})
    assert(not Item(derived,2).anchored and not Item(derived,3).anchored)
end)

Test("壁虎额外结算只数真实直接邻居、不按连通分量", function()
    local game = Fixture({"gecko","gecko","gecko","gecko"})
    assert(game:Start())
    local events = game:Finish({pairs={{1,2},{2,3}}})
    local scores = {2,3,2,1}
    for uid=1,4 do assert(#Repair.Events(events,"score",uid) == scores[uid]) end
    Close(game.roundScore,32)
end)

Test("壁虎樱桃及开局即时收益的全部浮字播完再等待2秒", function()
    local game = Fixture({"gecko","gecko","cherry","die_d4"},{cherry_plus=true})
    assert(game:Start())
    local count = 0
    for _, event in ipairs(game.startEvents) do
        if event.kind == "score" and (event.value or 0) > 0 then count=count+1 end
    end
    local events = game:Finish({pairs={{1,2}}})
    for _, event in ipairs(events) do
        if event.kind == "score" and (event.value or 0) > 0 then count=count+1 end
    end
    assert(count > #game:BottleItems(), "额外结算及开局骰子必须计入浮字数")
    local duration = Game.ScorePopTime(count)+2
    game:RevealStep(duration-.001)
    assert(game.phase == "reveal", "必须等全部浮字加2秒，不得按件数提前结束")
    game:RevealStep(.001)
    assert(game.phase == "draft")
end)

Test("金盘洗手只免警察老师、不免杀手追杀也不改学生成长池", function()
    local game = Fixture({"killer","thief"},{wash_hands=true,jungle_hunt=true})
    local done = Sequence(game,{{maximum=1,value=1}})
    require("Bottle.RelicEffects").OnAcquire(game,"jungle_hunt"); done()
    assert(game.huntTargetUid == 2 and game:Start())
    game:Step(0,{pairs={{1,2}}})
    assert(Item(game,2).location == "discard")
    Close(Item(game,1).permMult,1.5)
    local student = Fixture({"student"},{wash_hands=true})
    Item(student,1).settleCount = 4
    assert(student:Start())
    local growth = Sequence(student,{{maximum=10,value=1},{maximum=3,value=1}})
    student:Finish(); growth()
    assert(Item(student,1).id == "thief", "洗手不能擅自删除负面成长池中的小偷")
end)

Test("第5与10回合仅物品及刷新排普通、追加普通遗物可获取刷新存档", function()
    for _, round in ipairs({5,10}) do
        local snapshot = Fixture({"apple"}):Snapshot()
        snapshot.round, snapshot.stage = round, math.floor((round-1)/5)+1
        snapshot.target, snapshot.score, snapshot.refreshes = Game.GetTarget(snapshot.stage),10000,6
        local game = Game.Restore(snapshot)
        assert(game:Start()); Finish(game)
        assert(game.round == round and not game.relicDraft and #game.options == 3)
        local validOptions, count, revision = game.options, #game.deck, game.revision
        game.options = {"apple"}
        assert(not game:Choose(1) and #game.deck == count and game.revision == revision,
            "考核Choose也须拒绝伪造普通物品，不能只过滤抽取")
        game.options = validOptions
        for _=1,3 do
            for _,id in ipairs(game.options) do assert(Items.byId[id].rarity > 1) end
            assert(game:DraftRefresh())
        end
        for _,id in ipairs(game.options) do assert(Items.byId[id].rarity > 1) end
        -- ticket=1命中原普通档；正常进入遗物流程和刷新都不能套用物品禁普通。
        rawset(game,"_RandomInt",function(_,maximum) assert(maximum>=1); return 1 end)
        assert(game:Skip() and game.relicDraft and #game.options == 3)
        for _=1,2 do
            local seen = {}
            for _,id in ipairs(game.options) do
                assert(Relics.byId[id].rarity == 1 and not game.relics[id] and not seen[id])
                seen[id] = true
            end
            if not game.refreshUsed then assert(game:DraftRefresh())
            else assert(not game:DraftRefresh()) end
        end
        for _,id in ipairs(game.options) do assert(Relics.byId[id].rarity == 1) end
        Close(game.refreshes,round % 2 == 0 and 4 or 3) -- 遗物免费刷新不扣物品池，第10回合仍额外+1。
        Close(game.relicRefreshes,0)
        local state = game:Snapshot()
        local restored = Game.Restore(state)
        assert(Equal(state,restored:Snapshot()) and Equal(restored.options,game.options),
            "普通遗物候选存档保序、RNG和刷新余额完全不变")
        rawset(game,"_RandomInt",nil)
        local chosen = game.options[1]
        assert(game:Choose(1) and restored:Choose(1))
        assert(game.relics[chosen] and restored.relics[chosen] and game.round == round+1)
        assert(game.phase == "prepare" and #game.deck == count and Equal(game:Snapshot(),restored:Snapshot()))
        local acquired = Game.Restore(game:Snapshot())
        assert(acquired.relics[chosen], "普通遗物正常获取后永久读档")
        for _,def in ipairs(Relics.Available(acquired)) do assert(def.id ~= chosen) end
    end
end)

Test("非考核物品原白卡概率、遗物考核原权重及不足回退不受物品过滤影响", function()
    local ordinary = Fixture({"apple"})
    assert(ordinary:Start()); Finish(ordinary)
    assert(#ordinary.options == 3)
    for _,id in ipairs(ordinary.options) do assert(Items.byId[id].rarity == 1) end
    for _,round in ipairs({5,10}) do
        local probe = Fixture({})
        probe.round,probe.stage = round,math.floor(round/5)+1
        local weights = Items.DraftWeights(probe.stage)
        -- 第一普通档的最后一签仍普通，下一签恰为优秀；每次请求原权重10000。
        for _,ticket in ipairs({weights[1],weights[1]+1}) do
            local calls = 0
            rawset(probe,"_RandomInt",function(_,maximum)
                calls = calls+1
                if calls%2 == 1 then assert(maximum == 10000); return ticket end
                assert(maximum>=1); return 1
            end)
            local options = probe:_RelicDraftOptions()
            assert(#options == 3 and calls == 6)
            for _,id in ipairs(options) do
                assert(Relics.byId[id].rarity == (ticket == weights[1] and 1 or 2),
                    "遗物普通/优秀分界保持原概率表")
            end
        end
        assert(Equal(weights,Items.DraftWeights(probe.stage)), "抽签不污染共享概率表")
    end
    -- 候选不足与零权重回退仍覆盖物品禁普通，不能随遗物规则修正丢掉这组边界。
    local itemLimited = Fixture({})
    itemLimited.round,itemLimited.stage = 5,2
    local originalPool = {}
    for _,def in ipairs(Items.list) do originalPool[def.id] = def.pool end
    local ok,message = pcall(function()
        for _,def in ipairs(Items.list) do
            if def.rarity > 1 then def.pool = def.id == "knife" or def.id == "teacher" end
        end
        local options = itemLimited:_DraftOptions()
        assert(#options == 2)
        local seen = {}
        for _,id in ipairs(options) do
            assert((id == "knife" or id == "teacher") and not seen[id]); seen[id]=true
        end
        assert(seen.knife and seen.teacher, "考核物品不足三件不拿普通补齐")
        Items.byId.knife.pool = false
        options = itemLimited:_DraftOptions()
        assert(#options == 1 and options[1] == "teacher", "仅剩零权重稀有物品仍按最高非普通档回退")
        Items.byId.teacher.pool = false
        assert(#itemLimited:_DraftOptions() == 0, "无非普通物品时空候选而非普通补位")
    end)
    for _,def in ipairs(Items.list) do def.pool = originalPool[def.id] end
    assert(ok,message)
    local limited = Fixture({})
    limited.round,limited.stage = 5,2
    for _,def in ipairs(Relics.list) do
        if def.id ~= "gambling_token" and def.id ~= "teacher_team" then limited.relics[def.id]=true end
    end
    local options = limited:_RelicDraftOptions()
    assert(#options == 2)
    local seen = {}
    for _,id in ipairs(options) do
        assert((id == "gambling_token" or id == "teacher_team") and not seen[id]); seen[id]=true
    end
    assert(seen.gambling_token and seen.teacher_team, "候选不足时普通遗物仍是合法候选")
    limited.relics.teacher_team = true
    options = limited:_RelicDraftOptions()
    assert(#options == 1 and options[1] == "gambling_token", "只剩普通遗物仍正常抽出")
    limited.relics.gambling_token = true
    assert(#limited:_RelicDraftOptions() == 0, "真正全部拥有才无候选")
    -- 只剩零权重品质3时沿用原最高可用档回退，不因考核新增限制。
    limited.relics.jungle_hunt,limited.relics.soul_resonance = nil,nil
    local fallback = limited:_RelicDraftOptions()
    assert(#fallback == 2)
    for _,id in ipairs(fallback) do
        assert(id == "jungle_hunt" or id == "soul_resonance", "零权重回退至最高可用稀有度")
    end
end)

Test("rules7/8仅拒绝考核普通物品、nil和5和6旧档只过滤物品保PRNG与次数", function()
    for _,relicDraft in ipairs({false,true}) do
        local snapshot = Fixture({"juice"}):Snapshot() --[[@as any]]
        snapshot.phase,snapshot.round,snapshot.stage = "draft",5,2
        snapshot.target,snapshot.drawn,snapshot.relicDraft = Game.GetTarget(2),{},relicDraft
        snapshot.instances[1].location = "deck"
        snapshot.options = relicDraft and {"gambling_token","juicer","teacher_team"}
            or {"apple","teacher","knife"}
        snapshot.refreshes = 7
        snapshot.relicRefreshes = relicDraft and 1 or 0
        assert(snapshot.rulesVersion == 8)
        for _, currentRules in ipairs({7,8}) do
            snapshot.rulesVersion = currentRules
            if relicDraft then
                local current = Game.Restore(snapshot)
                assert(Equal(current.options,snapshot.options) and current._rngState == snapshot.rngState)
            else
                assert(not pcall(Game.Restore,snapshot), "rules7/8考核普通物品必须严格拒绝")
            end
        end
        local expected = relicDraft and {"gambling_token","juicer","teacher_team"} or {"teacher","knife"}
        for _,old in ipairs({"nil",5,6}) do
            if old == "nil" then snapshot.rulesVersion = nil else snapshot.rulesVersion = old end
            local restored = Game.Restore(snapshot)
            assert(Equal(restored.options,expected) and restored._rngState == snapshot.rngState)
            Close(restored.refreshes,7); Close(Item(restored,1).refreshCount,0)
            Close(restored:_Value(Item(restored,1)),old == "nil" and 0 or 3)
            local stable = restored:Snapshot()
            assert(stable.rulesVersion == 8 and Equal(stable,Game.Restore(stable):Snapshot()))
            snapshot.options = relicDraft and {"gambling_token","gambling_token"} or {"apple","apple"}
            assert(not pcall(Game.Restore,snapshot), "先严格拒绝旧重复普通，不能过滤后掩盖损坏")
            snapshot.options = relicDraft and {"gambling_token"} or {"apple"}
            local oneCommon = Game.Restore(snapshot)
            assert(#oneCommon.options == (relicDraft and 1 or 0)
                and oneCommon._rngState == snapshot.rngState and oneCommon.refreshes == 7)
            if relicDraft then assert(oneCommon.options[1] == "gambling_token") end
            snapshot.round = 6
            local ordinaryCopy = Game.Restore(snapshot)
            assert(#ordinaryCopy.options == 1, "非考核旧候选不擅过滤")
            snapshot.round = 5
            snapshot.options = relicDraft and {"gambling_token","juicer","teacher_team"}
                or {"apple","teacher","knife"}
        end
    end
end)

Test("九遗物及新临时字段真实cjson准备回滚draft严格一致", function()
    local json = rawget(_G,"cjson")
    if not json then return end
    local game = Fixture({"ghost","gecko","apple"})
    for _,id in ipairs(IDS) do game.relics[id]=true end
    local prepare = game:Snapshot()
    assert(Equal(prepare,Game.Restore(json.decode(json.encode(prepare))):Snapshot()))
    assert(game:Start())
    game:Step(.24,{side={[2]=true},angularTravel={[3]=TURN+.1},positions={[1]={x=0,y=0}}})
    game:Step(0,{side={[2]=true},positions={[1]={x=3,y=0}}})
    assert(Equal(prepare,Game.Restore(json.decode(json.encode(game:Snapshot()))):Snapshot()))
    Finish(game)
    local snapshot = game:Snapshot()
    assert(Equal(snapshot,Game.Restore(json.decode(json.encode(snapshot))):Snapshot()))
    for _, item in ipairs(snapshot.instances) do
        Close(item.ghostTravel,0); Close(item.spinProgress,0); Close(item.geckoContactTime,0)
        assert(item.spinTravel == nil and item.spinAngle == nil and item.spinForced == nil)
    end
end)

---@return integer
function Tests.Run()
    local passed, failures = 0, {}
    for _,case in ipairs(cases) do
        local ok,message = pcall(case.run)
        if ok then passed=passed+1 else failures[#failures+1]=case.name.."："..tostring(message) end
    end
    assert(#failures == 0,"Bottle.NewRelicTests "..passed.."/"..#cases.." 通过\n"..table.concat(failures,"\n"))
    return passed
end
return Tests
