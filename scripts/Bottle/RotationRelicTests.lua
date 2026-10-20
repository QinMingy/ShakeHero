-- 遗物34-37纯Lua回归；只用内存Game，不接触玩家存档或真实物理。
-- 由主套件接线 require("Bottle.RotationRelicTests").Run()，也可独立调用。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicExpansion = require("Bottle.RelicExpansion")
local ExtraEffects = require("Bottle.ExtraEffects")
local Repair = require("Bottle.RepairTests")
local Tests = {}

---@param actual number?
---@param expected number
local function Close(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        "expected=" .. tostring(expected) .. " actual=" .. tostring(actual))
end
---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid)
    return (assert(game:Get(uid))) --[[@as ItemInstance]]
end
---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
local function Fixture(ids, relics) return Repair.Fixture(ids, relics) end
---@param game BottleGame
---@param id string
---@param location string?
---@return ItemInstance[]
local function Find(game, id, location)
    local found = {}
    for _, item in ipairs(game:AllInstances()) do
        if item.id == id and (not location or item.location == location) then found[#found + 1] = item end
    end
    return found
end
---@param game BottleGame
---@param entries {maximum:integer,value:integer}[]
---@return fun()
local function Sequence(game, entries)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local entry = assert(entries[index], "多余随机判定，maximum=" .. maximum)
        assert(maximum == entry.maximum, "随机范围不符，actual=" .. maximum .. " expected=" .. entry.maximum)
        assert(entry.value >= 1 and entry.value <= maximum, "测试随机值越界")
        return entry.value
    end)
    return function()
        assert(index == #entries, "遗漏随机判定")
        rawset(game, "_RandomInt", nil)
    end
end
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end

Test("34至37编号品质开放状态及恢复一致", function()
    local game = Fixture({})
    local ids = {"wool_recycle", "dice_jackpot", "calf_rush", "lucky_roulette"}
    assert(#Relics.list == 39)
    for index, id in ipairs(ids) do
        local def = assert(Relics.byId[id])
        assert(def.numberId == 33 + index and Relics.byNumber[33 + index] == def)
        assert(def.rarity == (index == 1 and 1 or 2) and def.pool and def.implemented)
        game.relics[id] = true
    end
    local restored = Game.Restore(game:Snapshot())
    for _, id in ipairs(ids) do assert(restored.relics[id]) end
    assert(#Relics.Available(restored) == 35)
end)

Test("羊毛回收成功消费命中才临时瓶顶生成", function()
    for _, roll in ipairs({1, 2}) do
        local game = Fixture({"sweater", "wool"}, {wool_recycle = true})
        assert(game:Start())
        local entries = {{maximum = 2, value = roll}}
        if roll == 1 then entries[#entries + 1] = {maximum = 101, value = 51} end
        local done = Sequence(game, entries)
        local events = {}
        assert(game:_Destroy(2, false, events, Item(game, 1), "consume")); done()
        local spawned = Find(game, "wool", "bottle")
        assert(#spawned == (roll == 1 and 1 or 0))
        if spawned[1] then
            assert(spawned[1].temporary and spawned[1].generatedTemporary)
            local event = Repair.Events(events, "spawn", spawned[1].uid)[1]
            Close(event.y, 6)
        end
    end
end)

Test("羊毛合成两份材料独立判定且不重复合成回收钩子", function()
    local game = Fixture({"wool", "wool"}, {wool_recycle = true})
    assert(game:Start())
    local done = Sequence(game, {{maximum=2,value=1},{maximum=101,value=51},
        {maximum=2,value=2}})
    game:Step(0, {pairs = {{1, 2}}}); done()
    assert(Item(game, 1).location == "discard" and Item(game, 2).location == "discard")
    local products = Find(game, "wool", "bottle")
    assert(#products == 2)
    local temporary = 0
    for _, product in ipairs(products) do
        if product.generatedTemporary then temporary = temporary + 1; Close(game:_Value(product), 1)
        else Close(game:_Value(product), 2) end
    end
    assert(temporary == 1)
end)

Test("临时回收羊毛再次成功消费仍可回收且不受羊毛集市替换", function()
    local game = Fixture({"wool"}, {wool_recycle=true,wool_market=true})
    assert(game:Start())
    local original = Item(game, 1)
    original.temporary, original.generatedTemporary = true, true
    local done = Sequence(game, {{maximum=2,value=1},{maximum=101,value=51},
        {maximum=2,value=1},{maximum=101,value=51}})
    assert(game:_Destroy(original.uid, false, {}, nil, "self"))
    local nextWool = assert(Find(game,"wool","bottle")[1])
    assert(game:_Destroy(nextWool.uid, false, {}, nil, "self")); done()
    assert(#Find(game,"wool","bottle") == 1 and #Find(game,"coin_1") == 0)
end)

Test("羊毛失败消费与非羊毛及无遗物不抽回收", function()
    local game = Fixture({"wool", "apple"}, {wool_recycle=true})
    assert(game:Start())
    local done = Sequence(game,{})
    Item(game,1).shielded = true
    assert(not game:_Destroy(1,false,{},nil,"consume"))
    assert(game:_Destroy(2,false,{},nil,"self")); done()
    local ordinary = Fixture({"wool"})
    assert(ordinary:Start())
    done = Sequence(ordinary,{})
    assert(ordinary:_Destroy(1,false,{})); done()
end)

Test("回收临时羊毛满瓶FIFO不丢弃且回合末所有位置彻底清理", function()
    local game = Fixture({"wool"}, {wool_recycle=true})
    assert(game:Start())
    while #game:BottleItems() < 100 do game:_Spawn("ball", {}) end
    local done = Sequence(game,{{maximum=2,value=1},{maximum=101,value=51}})
    RelicExpansion.OnConsumed(game,Item(game,1),{}); done()
    local uid = assert(game.spawnQueue[1])
    assert(Item(game,uid).location == "queued" and Item(game,uid).generatedTemporary)
    game:Finish()
    assert(game:Get(uid) == nil and #game.spawnQueue == 0)
end)

Test("骰号大奖增长后增量逐次加算含封顶重复奖励", function()
    local game = Fixture({"die_d6", "coin_1"}, {dice_jackpot=true})
    local die, coin = Item(game,1), Item(game,2)
    local expected = {0.5,1.5,3,5,7}
    for index=1,5 do
        RelicExpansion.OnRoll(game,die,6,{})
        Close(die.scale,math.min(3,1+index*0.5))
        Close(die.jackpotBonus,expected[index]); Close(coin.jackpotBonus,expected[index])
    end
    Close(coin.eventMult,1); Close(coin.mult,1); Close(coin.permMult,1)
    Close(game:_Value(coin),8)
end)

Test("大奖只发当前瓶内骰子硬币链赌徒赌神不含幸运硬币", function()
    local game = Fixture({"die_d6","die_d4","coin_2048","gambler","gambling_god",
        "lucky_coin","apple","coin_1"}, {dice_jackpot=true})
    Item(game,8).location = "deck"
    RelicExpansion.OnRoll(game,Item(game,1),6,{})
    for uid=1,5 do Close(Item(game,uid).jackpotBonus,0.5) end
    for uid=6,8 do Close(Item(game,uid).jackpotBonus or 0,0) end
    local fresh = game:_Create("coin_1")
    Close(fresh.jackpotBonus or 0,0)
end)

Test("骰号非6复原尺寸但不撤销本回合已授倍率", function()
    local game = Fixture({"die_d6","coin_1"}, {dice_jackpot=true})
    local die = Item(game,1)
    RelicExpansion.OnRoll(game,die,6,{})
    local events = {}
    RelicExpansion.OnRoll(game,die,2,events)
    Close(die.scale,1); Close(die.jackpotBonus,0.5); Close(Item(game,2).jackpotBonus,0.5)
    assert(#Repair.Events(events,"resize",1) == 1)
    RelicExpansion.OnRoll(game,die,6,{})
    Close(die.scale,1.5); Close(Item(game,2).jackpotBonus,1)
end)

Test("多骰奖金加数累计与其他事件及永久倍率独立相乘", function()
    local game = Fixture({"die_d6","die_d6","coin_2"}, {dice_jackpot=true})
    local coin = Item(game,3)
    coin.eventMult,coin.mult,coin.permMult = 2,2,3
    RelicExpansion.OnRoll(game,Item(game,1),6,{})
    RelicExpansion.OnRoll(game,Item(game,2),6,{})
    Close(coin.jackpotBonus,1); Close(game:_Value(coin),24)
end)

Test("开局投6先发大奖再即时结算骰子", function()
    local game = Fixture({"die_d6","coin_1"},{dice_jackpot=true})
    local done = Sequence(game,{{maximum=6,value=6}})
    assert(game:Start()); done()
    Close(Item(game,1).scale,1.5); Close(Item(game,1).jackpotBonus,0.5)
    Close(Repair.Events(game.startEvents,"score",1)[1].value,9)
    Close(game.roundScore,9)
end)

Test("再来一把连续两投均接入大奖且非6不撤旧奖", function()
    local game = Fixture({"gambler","die_d6","coin_1"},
        {dice_jackpot=true,one_more_round=true})
    local done = Sequence(game,{{maximum=6,value=2},{maximum=6,value=6},{maximum=6,value=2}})
    assert(game:Start())
    local events = game:Step(0,{pairs={{1,2}}}); done()
    local scores = Repair.Events(events,"score",2)
    assert(#scores == 2)
    Close(scores[1].value,9); Close(scores[2].value,3)
    Close(Item(game,2).scale,1); Close(Item(game,3).jackpotBonus,0.5)
end)

Test("无大奖遗物不改变骰子尺寸或数值", function()
    local game = Fixture({"die_d6","coin_1"})
    Item(game,1).scale=2
    local events={}
    RelicExpansion.OnRoll(game,Item(game,1),6,events)
    RelicExpansion.OnRoll(game,Item(game,1),2,events)
    Close(Item(game,1).scale,2); Close(Item(game,2).jackpotBonus or 0,0); assert(#events==0)
end)

Test("大奖回合清临时倍率不清永久尺寸且运行快照回滚", function()
    local game=Fixture({"die_d6","coin_1"},{dice_jackpot=true})
    local done=Sequence(game,{{maximum=6,value=6}})
    assert(game:Start()); done()
    local rollback=Game.Restore(game:Snapshot())
    Close(Item(rollback,1).scale,1); Close(Item(rollback,2).jackpotBonus or 0,0)
    game:Finish()
    Close(Item(game,1).scale,1.5); Close(Item(game,2).jackpotBonus,0)
    Close(game:_Value(Item(game,2)),1)
    game:RevealStep(100)
    local restored=Game.Restore(game:Snapshot())
    Close(Item(restored,1).scale,1.5); Close(Item(restored,2).jackpotBonus or 0,0)
end)

Test("牛来每冲刺只一次临时加值并达上限永久加2复原", function()
    local game=Fixture({"calf"},{calf_rush=true})
    local calf=Item(game,1)
    for index=1,5 do
        local events={}
        RelicExpansion.OnDash(game,calf,events)
        Close(calf.bonus,index)
        Close(calf.scale,index==5 and 1 or 1+index*.2)
        Close(calf.permBonus,index==5 and 2 or 0)
        assert(#Repair.Events(events,"resize",1)==1)
    end
    RelicExpansion.OnDash(game,calf,{})
    Close(calf.bonus,6); Close(calf.scale,1.2); Close(calf.permBonus,2)
end)

Test("牛成功消费先resize后dash且原冲撞奖励继续叠加", function()
    local game=Fixture({"calf","grass","apple"},{calf_rush=true})
    assert(game:Start())
    local done=Sequence(game,{{maximum=100,value=1}})
    local events={}
    assert(game:_Destroy(2,false,events,Item(game,1),"consume")); done()
    local resized,dashed=0,0
    for index,event in ipairs(events) do
        if event.kind=="resize" and event.uid==1 then resized=index end
        if event.kind=="dash" and event.uid==1 then dashed=index end
    end
    assert(resized>0 and resized<dashed)
    Close(Item(game,1).bonus,1); Close(Item(game,1).scale,1.2)
    game:Step(.1,{pairs={{1,3}}})
    game:Step(.1,{pairs={{1,3}}})
    Close(Item(game,1).bonus,2); Close(Item(game,1).scale,1.2)
end)

Test("牛非冲刺位移不触发遗物且失败消费不增长", function()
    local game=Fixture({"calf","grass"},{calf_rush=true})
    assert(game:Start())
    game:Step(.1,{positions={[1]={x=0,y=1}}})
    game:Step(.1,{positions={[1]={x=.5,y=1}}})
    Item(game,2).shielded=true
    assert(not game:_Destroy(2,false,{},Item(game,1),"consume"))
    Close(Item(game,1).bonus,0); Close(Item(game,1).scale,1)
    local ordinary=Fixture({"calf"})
    RelicExpansion.OnDash(ordinary,Item(ordinary,1),{})
    Close(Item(ordinary,1).bonus,0); Close(Item(ordinary,1).scale,1)
end)

Test("牛临时收益清理尺寸永久保留", function()
    local game=Fixture({"calf"},{calf_rush=true})
    assert(game:Start())
    RelicExpansion.OnDash(game,Item(game,1),{})
    game:Finish(); Close(Item(game,1).bonus,0); Close(Item(game,1).scale,1.2)
    game:RevealStep(100)
    local restored=Game.Restore(game:Snapshot())
    Close(Item(restored,1).scale,1.2); Close(Item(restored,1).permBonus,0)
end)

Test("转盘无遗物只抽基础50比50且两支永久", function()
    local game=Fixture({})
    for _,entry in ipairs({{1,3},{2,-1}}) do
        local done=Sequence(game,{{maximum=2,value=entry[1]}})
        local delta,permanent=RelicExpansion.RollWheel(game); done()
        Close(delta,entry[2]); assert(permanent)
    end
end)

Test("幸运转盘大奖5%独占且临时不抽基础", function()
    local game=Fixture({},{lucky_roulette=true,lucky_charm=true})
    local done=Sequence(game,{{maximum=20,value=1}})
    local delta,permanent=RelicExpansion.RollWheel(game); done()
    Close(delta,77); assert(not permanent)
end)

Test("幸运转盘未中其余95%基础正负均分幸运符只翻负号", function()
    for _,charm in ipairs({false,true}) do
        for _,roll in ipairs({2,20}) do
            for _,base in ipairs({1,2}) do
                ---@type table<string,boolean>
                local owned = {lucky_roulette=true}
                if charm then owned.lucky_charm = true end
                local game=Fixture({},owned)
                local done=Sequence(game,{{maximum=20,value=roll},{maximum=2,value=base}})
                local delta,permanent=RelicExpansion.RollWheel(game); done()
                Close(delta,base==1 and 3 or charm and 1 or -1); assert(permanent)
            end
        end
    end
end)

Test("幸运转盘40等权组合精确得到2大奖19正19负", function()
    local game=Fixture({},{lucky_roulette=true})
    local counts={jackpot=0,positive=0,negative=0}
    for first=1,20 do
        for second=1,2 do
            local entries={{maximum=20,value=first}}
            if first~=1 then entries[#entries+1]={maximum=2,value=second} end
            local done=Sequence(game,entries)
            local delta,permanent=RelicExpansion.RollWheel(game); done()
            if delta==77 then assert(not permanent); counts.jackpot=counts.jackpot+1
            elseif delta==3 then assert(permanent); counts.positive=counts.positive+1
            else assert(delta==-1 and permanent); counts.negative=counts.negative+1 end
        end
    end
    assert(counts.jackpot==2 and counts.positive==19 and counts.negative==19)
end)

Test("尺寸复原与大胃王缩小向公共物理入口传旧尺寸", function()
    local game=Fixture({"die_d6","calf","glutton"},{dice_jackpot=true,calf_rush=true})
    local calls={}
    rawset(game,"ApplyScale",function(_,item,events,previous)
        calls[#calls+1]={uid=item.uid,previous=previous,current=item.scale}
    end)
    Item(game,1).scale=2.5
    RelicExpansion.OnRoll(game,Item(game,1),2,{})
    Item(game,2).scale=1.8
    RelicExpansion.OnDash(game,Item(game,2),{})
    Item(game,3).scale,Item(game,3).distance=1.5,100
    ExtraEffects.TrackDistance(game,Item(game,3),{})
    assert(#calls==3)
    Close(calls[1].previous,2.5); Close(calls[1].current,1)
    Close(calls[2].previous,1.8); Close(calls[2].current,1)
    Close(calls[3].previous,1.5); Close(calls[3].current,1.4)
    rawset(game,"ApplyScale",nil)
end)

---@return integer
function Tests.Run()
    local passed,failures=0,{}
    for _,case in ipairs(cases) do
        local ok,message=pcall(case.run)
        if ok then passed=passed+1 else failures[#failures+1]=case.name.."："..tostring(message) end
    end
    assert(#failures==0,"Bottle.RotationRelicTests "..passed.."/"..#cases.." 通过\n"..table.concat(failures,"\n"))
    return passed
end
return Tests
