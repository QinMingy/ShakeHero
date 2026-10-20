-- 2026-10-20最新源表专项：概率逐签、成功消费、厨师实例永久强化与旧候选迁移。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Repair = require("Bottle.RepairTests")
local Extra = require("Bottle.ExtraEffects")
local Effects = require("Bottle.Effects")
local Rotation = require("Bottle.RotationEffects")
local Expansion = require("Bottle.ExpansionEffects")
local Tests = {}
local cases = {}
local function Test(name, run) cases[#cases+1] = {name=name,run=run} end
local function Close(a,b) assert(math.abs(a-b)<1e-7,tostring(a).." ~= "..tostring(b)) end
local function Item(game,uid) return assert(game:Get(uid)) end
local function Make(ids,relics)
    local game=Repair.Fixture(ids,relics)
    assert(game:Start())
    return game
end
local function Constant(game,value)
    rawset(game,"_RandomInt",function(_,maximum) return math.min(maximum,value) end)
end
local function Count(game,id)
    local count=0
    for _,item in ipairs(game:AllInstances()) do if item.id==id then count=count+1 end end
    return count
end
local function Finish(game)
    rawset(game,"_RandomInt",nil)
    game:Finish(); game:RevealStep(100)
end

Test("鸡蛋无标签且不参与食物消费与加成，炒蛋配方保留",function()
    assert(not Items.HasTag("egg","食物") and #Items.byId.egg.tags==0)
    assert(not Items.TagsText(Items.byId.egg):find("食物",1,true))
    assert(Items.Recipe("egg","tomato")=="tomato_egg")
    for _,id in ipairs({"glutton","diner","chef","bacon"}) do
        local game=Make({id,"egg"},{food_comfort=true})
        game:Step(0,{pairs={{1,2}}})
        assert(Item(game,2).location=="bottle")
        Close(Item(game,2).permBonus,0)
        Close(game:_Value(Item(game,2)),3)
        if id=="bacon" then
            Extra.BeforeSettle(game,{pairs={{1,2}},bottom={},top={},wall={},positions={},
                side={},angles={},rotateOffsets={},angularTravel={},flightArrived={},flightHits={}},{})
            Close(game:_Value(Item(game,1)),7)
        end
    end
end)

Test("厨师四秒强化全部食物且不切水果、不改非食物",function()
    local game=Make({"chef","apple","enoki","ball"})
    local state={pairs={{1,2},{1,3},{1,4}}}
    game:Step(0,state)
    Close(Item(game,2).permBonus,1); Close(Item(game,3).permBonus,1)
    Close(Item(game,4).permBonus,0); Close(Item(game,1).remaining,4)
    assert(Item(game,2).id=="apple" and #game.deck==4)
    Close(game:_Value(Item(game,2)),6)
    game:Step(3.99,state); Close(Item(game,2).permBonus,1)
    game:Step(.01,state); Close(Item(game,2).permBonus,2)
end)

Test("厨师帽吃刀与食物加值共用本体冷却、新入场仍等待完整周期",function()
    local game=Make({"chef","knife","apple"},{chef_hat=true})
    game:Step(0,{pairs={{1,2},{1,3}}})
    local knife=game:_Spawn("knife",{})
    local state={pairs={{1,knife.uid},{1,3}}}
    game:Step(1,state)
    Close(Item(game,1).chefBoost,1); Close(Item(game,3).permBonus,2)
    assert(knife.location=="bottle")
    game:Step(2.99,state)
    Close(Item(game,1).chefBoost,1); Close(Item(game,3).permBonus,2)
    game:Step(.01,state)
    Close(Item(game,1).chefBoost,2); Close(Item(game,3).permBonus,5)
    assert(knife.location=="discard")
    local chef=game:_Spawn("chef",{})
    Close(chef.remaining,Items.byId.chef.cooldown)
    local fresh={pairs={{chef.uid,3}}}
    game:Step(3.99,fresh); Close(Item(game,3).permBonus,5)
    game:Step(.01,fresh); Close(Item(game,3).permBonus,6)
    local text=require("Bottle.ItemText").Effect(game,"chef",chef)
    assert(text:find("冷却：4秒",1,true) and not text:find("冷却：1秒",1,true))
end)

Test("厨师帽多刀永久增强后续、空批储存、拦截不增强",function()
    local game=Make({"chef","knife","knife","apple","egg"},{chef_hat=true})
    game:Step(0,{pairs={{1,2},{1,3},{1,4},{1,5}}})
    Close(Item(game,4).permBonus,3); Close(Item(game,5).permBonus,0)
    assert(Item(game,2).location=="discard" and Item(game,3).location=="discard")
    Close(Item(game,1).chefBoost,2); Close(game:_Value(Item(game,1)),4)
    game:Step(4,{pairs={{1,4}}}); Close(Item(game,4).permBonus,6)
    local another=game:_Spawn("knife",{})
    game:Step(4,{pairs={{1,another.uid},{1,4}}})
    Close(Item(game,1).chefBoost,3); Close(Item(game,4).permBonus,10)
    local empty=Make({"chef","knife","apple"},{chef_hat=true})
    empty:Step(0,{pairs={{1,2}}})
    empty:Step(4,{pairs={{1,3}}}); Close(Item(empty,3).permBonus,2)
    local blocked=Make({"chef","knife","apple"},{chef_hat=true})
    Item(blocked,2).shielded=true
    blocked:Step(0,{pairs={{1,2},{1,3}}})
    Close(Item(blocked,3).permBonus,1)
    assert(Item(blocked,2).location=="bottle")
end)

Test("厨师强化按实例隔离、同刀仅归成功消费者、说明只读真实值",function()
    local game=Make({"chef","chef","knife","apple","egg"},{chef_hat=true})
    game:Step(0,{pairs={{1,3},{2,3},{1,4},{2,5}}})
    Close(Item(game,1).chefBoost,1); Close(Item(game,2).chefBoost,0)
    Close(Item(game,4).permBonus,2); Close(Item(game,5).permBonus,0)
    local text=require("Bottle.ItemText")
    local rng,revision=game._rngState,game.revision
    assert(text.Effect(game,"chef",Item(game,1)):find("当前：+1",1,true))
    assert(text.Effect(game,"chef",Item(game,2)):find("当前：+0",1,true))
    assert(not text.Effect(game,"chef"):find("当前：",1,true))
    assert(game._rngState==rng and game.revision==revision)
    game:Step(4,{pairs={{1,4},{2,5}}})
    Close(Item(game,4).permBonus,4); Close(Item(game,5).permBonus,0)
    local newcomer=game:_Spawn("chef",{})
    Close(newcomer.chefBoost,0)
end)

Test("厨师永久强化跨回合及原生JSON往返保留、旧档缺省零且不补发",function()
    local game=Make({"chef","knife","apple"},{chef_hat=true})
    game:Step(0,{pairs={{1,2},{1,3}}})
    Finish(game)
    local json=require("cjson")
    local saved=json.decode(json.encode(game:Snapshot()))
    local restored=Game.Restore(saved)
    Close(Item(restored,1).chefBoost,1)
    assert(restored._rngState==saved.rngState and #restored.deck==2)
    assert(restored:Skip() and restored:Start())
    restored:Step(0,{pairs={{1,3}}})
    Close(Item(restored,3).permBonus,4); Close(Item(restored,1).chefBoost,1)
    local old=Repair.Fixture({"chef"},{chef_hat=true}):Snapshot() --[[@as any]]
    old.instances[1].chefBoost=nil
    local legacy=Game.Restore(old)
    Close(Item(legacy,1).chefBoost,0)
    assert(#legacy.deck==1 and legacy._rngState==old.rngState)
    for _,bad in ipairs({-1,.5,"1",false,{},math.huge,-math.huge,0/0,2147483648}) do
        rawset(old.instances[1],"chefBoost",bad)
        assert(not pcall(Game.Restore,old),"拒绝非法厨师强化："..tostring(bad))
    end
    local foreign=Repair.Fixture({"apple"}):Snapshot()
    foreign.instances[1].chefBoost=1
    assert(not pcall(Game.Restore,foreign),"不能把厨师强化写给别的职业")
end)

Test("厨师强化随消费返还保留、转化重置且不转移给新厨师",function()
    local game=Make({"chef","knife","necromancer"},{chef_hat=true})
    game:Step(0,{pairs={{1,2}}})
    assert(game:_Destroy(1,false,{}))
    Close(Item(game,1).chefBoost,1)
    -- 取回随机表第一项厨师；这是一次真实死灵返还，不新建或复制强化。
    game.discard={Item(game,1),Item(game,2)}
    Constant(game,1)
    game:Finish(); game:RevealStep(100)
    assert(Item(game,1).location=="deck"); Close(Item(game,1).chefBoost,1)
    Close(Item(Game.Restore(game:Snapshot()),1).chefBoost,1)
    game:_Transform(Item(game,1),"student",{})
    Close(Item(game,1).chefBoost,0)
    game:_Transform(Item(game,1),"chef",{})
    Close(Item(game,1).chefBoost,0)
end)

Test("厨师强化在摇晃结算展示快照仍按回合前回滚",function()
    local game=Repair.Fixture({"chef","knife","apple"},{chef_hat=true})
    Item(game,1).chefBoost=2
    assert(game:Start())
    game:Step(0,{pairs={{1,2},{1,3}}})
    Close(Item(game,1).chefBoost,3)
    local function CheckRollback()
        local restored=Game.Restore(game:Snapshot())
        Close(Item(restored,1).chefBoost,2)
        assert(Item(restored,2).location=="bottle")
        Close(Item(restored,3).permBonus,0)
    end
    CheckRollback()
    game:Step(10); assert(game.phase=="settle"); CheckRollback()
    game:SettleStep(2); assert(game.phase=="reveal"); CheckRollback()
    game:RevealStep(100)
    Close(Item(Game.Restore(game:Snapshot()),1).chefBoost,3)
end)

Test("炊事兵保留士兵ID只吃鸡、每鸡永久加值并生成永久幽灵",function()
    assert(Items.byId.soldier.name=="炊事兵" and Items.HasTag("soldier","人类"))
    local game=Make({"soldier","chick","chick","egg","rabbit"})
    game:Step(0,{pairs={{1,2},{1,3},{1,4},{1,5}},positions={[1]={x=.2,y=2}}})
    Close(Item(game,1).permBonus,2); Close(Count(game,"ghost"),2)
    assert(Item(game,2).location=="discard" and Item(game,3).location=="discard")
    assert(Item(game,4).location=="bottle" and Item(game,5).location=="bottle")
    for _,item in ipairs(game.deck) do
        if item.id=="ghost" then assert(not item.generatedTemporary) end
    end
    local blocked=Make({"soldier","chick"})
    Item(blocked,2).shielded=true
    blocked:Step(0,{pairs={{1,2}}})
    Close(Item(blocked,1).permBonus,0); Close(Item(blocked,1).remaining,0)
    Close(Count(blocked,"ghost"),0)
    Finish(game)
    assert(Game.Restore(game:Snapshot()):Get(1).id=="soldier")
end)

Test("兔子两等签仅一签永久、群体只让其他兔固定永久",function()
    for ticket=1,2 do
        local game=Make({"rabbit","rabbit"},{in_groups=true})
        Constant(game,ticket)
        local rabbit=Item(game,1)
        rabbit.distance=200.5
        Extra.TrackDistance(game,rabbit,{})
        Close(rabbit.permBonus,ticket==1 and 2 or 0)
        Close(rabbit.bonus,ticket==1 and 0 or 2)
        Close(Item(game,2).permBonus,2); Close(rabbit.distance,.5)
        Close(game.roundScore,0)
        Finish(game)
        Close(rabbit.bonus,0); Close(rabbit.permBonus,ticket==1 and 2 or 0)
        Close(Item(Game.Restore(game:Snapshot()),2).permBonus,2)
    end
end)

Test("云朵和养鸡人百分签逐签得到30和45次成功",function()
    local clouds,chicks=0,0
    for ticket=1,100 do
        local cloud=Make({"cloud"}); Constant(cloud,ticket)
        Extra.Apply(cloud,Item(cloud,1),cloud:_ContactSnapshot({}),{})
        local extras=0
        for _,item in ipairs(cloud.deck) do if item.generatedTemporary then extras=extras+1 end end
        assert(extras==(ticket<=30 and 6 or 0))
        if extras>0 then clouds=clouds+1 end
        local keeper=Make({"chicken_keeper","egg"}); Constant(keeper,ticket)
        local state=keeper:_ContactSnapshot({pairs={{1,2}}})
        assert(Expansion.Apply(keeper,Item(keeper,1),state,{}))
        assert(Count(keeper,"chick")== (ticket<=45 and 1 or 0))
        if ticket<=45 then chicks=chicks+1 end
    end
    assert(clouds==30 and chicks==45 and Items.byId.chicken_keeper.cooldown==5)
end)

Test("陀螺逐百分签仅30签成功、失败消费圈数保留余角",function()
    local successes=0
    for ticket=1,100 do
        local game=Make({"spinning_top"}); Constant(game,ticket)
        local state={angularTravel={[1]=2*math.pi+.25}}
        Rotation.Step(game,0,state,{})
        Close(Item(game,1).bonus,ticket<=30 and 1 or 0)
        Close(Item(game,1).rotationProgress,.25)
        Rotation.Step(game,0,state,{})
        Close(Item(game,1).bonus,ticket<=30 and 1 or 0)
        if ticket<=30 then successes=successes+1 end
    end
    assert(successes==30)
end)

Test("老八秘制四种便便叠本体收益、不改tag、无遗物不吃",function()
    for _,id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        local ordinary=Make({"glutton",id})
        ordinary:Step(0,{pairs={{1,2}}}); assert(Item(ordinary,2).location=="bottle")
        local game=Make({"glutton",id},{secret_recipe=true}); Constant(game,100)
        game:Step(0,{pairs={{1,2}}})
        assert(Item(game,2).location=="discard" and not Items.HasTag(id,"食物"))
        Close(Item(game,1).scale,1.1)
        Close(Item(game,1).permBonus,id=="poop" and 2 or id=="golden_poop" and 4 or 1)
        Close(Item(game,1).permMult,id=="diamond_poop" and 1.2 or 1)
        Close(Item(game,1).eventMult,id=="rainbow_poop" and 1.5 or 1)
        local full=Make({"glutton",id},{secret_recipe=true}); Item(full,1).scale=2
        full:Step(0,{pairs={{1,2}}}); assert(Item(full,2).location=="bottle")
        local blocked=Make({"glutton",id},{secret_recipe=true}); Item(blocked,2).shielded=true
        blocked:Step(0,{pairs={{1,2}}}); Close(Item(blocked,1).permBonus,0)
    end
end)

Test("流星雨五等签仅一签复制触底后状态、新UID不继承接触",function()
    for ticket=1,5 do
        local game=Make({"star"},{meteor_shower=true}); Constant(game,ticket)
        local star=Item(game,1)
        star.permBonus,star.permMult,star.scale,star.weight=7,1.2,1.4,.8
        game:Step(0,{bottom={[1]=true},positions={[1]={x=.2,y=.3}}})
        assert(Count(game,"star")== (ticket==1 and 2 or 1))
        if ticket==1 then
            local copy=Item(game,2)
            assert(copy.generatedTemporary and copy.uid~=star.uid)
            Close(copy.permBonus,7); Close(copy.bonus,1); Close(copy.permMult,1.2)
            Close(copy.scale,1.4); Close(copy.weight,.8)
            game:Step(0,{bottom={[1]=true}})
            Close(copy.bonus,1); Close(Count(game,"star"),2)
            Finish(game); assert(not game:Get(copy.uid) and Count(game,"star")==1)
        end
    end
end)

Test("流星满瓶复制FIFO且临时排队末尾彻底删除",function()
    local game=Make({"star"},{meteor_shower=true})
    while #game:BottleItems()<100 do game:_Spawn("ball",{}) end
    local older=game:_Spawn("apple",{})
    Constant(game,1)
    game:Step(0,{bottom={[1]=true}})
    assert(#game.spawnQueue==2 and game.spawnQueue[1]==older.uid)
    local copy=Item(game,game.spawnQueue[2])
    assert(copy.id=="star" and copy.generatedTemporary)
    Finish(game)
    assert(not game:Get(copy.uid) and game:Get(older.uid) and older.location=="deck")
end)

Test("旧目录只过滤退出池候选、不抽随机、不删除牌库或放过坏档",function()
    local snapshot=Repair.Fixture({"apple","banana","orange","droplet","gambling_god"}):Snapshot()
    snapshot.phase,snapshot.drawn,snapshot.options="draft",{},{"apple","knife","gambling_god"}
    for _,item in ipairs(snapshot.instances) do item.location="deck" end
    assert(not pcall(Game.Restore,snapshot),"新目录必须拒绝已退出池候选")
    snapshot.itemCatalogVersion=nil
    local restored=Game.Restore(snapshot)
    assert(#restored.options==1 and restored.options[1]=="knife" and #restored.deck==5)
    assert(restored._rngState==snapshot.rngState and restored.refreshes==snapshot.refreshes)
    assert(restored:Snapshot().itemCatalogVersion==1)
    for _,options in ipairs({{"apple","apple"},{"unknown"},{"poop"}}) do
        snapshot.options=options; assert(not pcall(Game.Restore,snapshot))
    end
    snapshot.options={"apple"}; snapshot.itemCatalogVersion=2
    assert(not pcall(Game.Restore,snapshot))
end)

Test("新遗物编号品质与拥有存档往返、三件降为优秀",function()
    assert(#Relics.list==39)
    local game=Repair.Fixture({},{secret_recipe=true,meteor_shower=true})
    for index,id in ipairs({"secret_recipe","meteor_shower"}) do
        local def=Relics.byId[id]
        assert(def.numberId==37+index and def.rarity==index and def.pool and def.implemented)
        assert(Game.Restore(game:Snapshot()).relics[id])
    end
    for _,id in ipairs({"soul_resonance","merge_2048","gm_fruit"}) do assert(Relics.byId[id].rarity==2) end
end)

Test("小刀消费前完整有效价值乘二即时入账，消费身份与坐标正确",function()
    local game=Make({"knife","chick"})
    local knife,chick=Item(game,1),Item(game,2)
    chick.valueBase,chick.bonus,chick.permBonus,chick.permMult=4.2,1,2,1.5
    local value=game:_Value(chick)
    local score=game.score
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=.3,y=2},[2]={x=.6,y=2}}})
    Close(value,11); Close(game.score-score,value*2); Close(game.roundScore,value*2)
    assert(chick.location=="discard" and #game.deck==1)
    local gains=Repair.Events(events,"score",1)
    assert(#gains==1 and gains[1].reason=="consume" and gains[1].consumerId=="knife")
    Close(gains[1].x,.3); Close(gains[1].y,2)
    local consumed=Repair.Events(events,"consume",2)
    assert(#consumed==1 and consumed[1].consumerUid==1 and consumed[1].consumerId=="knife")
    Close(knife.remaining,4); Close(knife.permBonus,0); Close(Count(game,"ghost"),0)
    Finish(game)
    assert(chick.location=="discard" and #game.deck==1)
end)

Test("小刀同批切多个完整水果和消费多鸡，重复反向接触不重奖",function()
    local game=Make({"knife","apple","banana","orange","cherry","chick","chick","egg","apple_half","sheep"})
    Item(game,10).woolCount=5
    Item(game,7).permBonus=2
    local pairs={{1,2},{1,3},{1,4},{1,5},{1,6},{6,1},{1,6},{1,7},{1,8},{1,9},{1,10}}
    local events=game:Step(0,{pairs=pairs})
    for uid,id in ipairs({"apple_half","banana_half","orange_half","cherry_half"}) do
        assert(Item(game,uid+1).id==id and Count(game,id)==(id=="apple_half" and 3 or 2))
    end
    assert(Item(game,6).location=="discard" and Item(game,7).location=="discard")
    assert(Item(game,8).location=="bottle" and Item(game,9).location=="bottle")
    Close(Item(game,10).woolCount,5); Close(Count(game,"wool"),0)
    Close(game.roundScore,16); Close(Item(game,1).remaining,4)
    assert(#Repair.Events(events,"score",1)==2 and #Repair.Events(events,"consume")==2)
end)

Test("小刀切果与吃鸡双向共享4秒，3.99不触发4秒边界可触发",function()
    for _,firstId in ipairs({"apple","chick"}) do
        local secondId=firstId=="apple" and "chick" or "apple"
        local game=Make({"knife",firstId,secondId})
        game:Step(0,{pairs={{1,2}}})
        Close(Item(game,1).remaining,4)
        game:Step(3.99,{pairs={{1,3}}})
        assert(Item(game,3).id==secondId and Item(game,3).location=="bottle")
        game:Step(.01,{pairs={{1,3}}})
        assert((secondId=="chick" and Item(game,3).location=="discard")
            or (secondId=="apple" and Item(game,3).id=="apple_half"))
        Close(Item(game,1).remaining,4); Close(game.roundScore,6)
    end
end)

Test("小刀消费被盾拦截不发钱不冷却，混批成功仍冷却",function()
    local game=Make({"knife","chick","apple"})
    Item(game,2).shielded=true
    local events=game:Step(0,{pairs={{1,2}}})
    Close(game.roundScore,0); Close(Item(game,1).remaining,0)
    assert(Item(game,2).location=="bottle" and #Repair.Events(events,"consume")==0)
    game:Step(0,{pairs={{1,2},{1,3}}})
    Close(Item(game,1).remaining,4); Close(game.roundScore,0)
    assert(Item(game,2).location=="bottle" and Item(game,3).id=="apple_half")
    local mixed=Make({"knife","chick","chick"})
    Item(mixed,2).shielded=true
    mixed:Step(0,{pairs={{1,2},{1,3}}})
    Close(mixed.roundScore,6); Close(Item(mixed,1).remaining,4)
    assert(Item(mixed,2).location=="bottle" and Item(mixed,3).location=="discard")
end)

Test("两把小刀争同鸡只消费领奖一次，无接触目标不被消费",function()
    local game=Make({"knife","knife","chick","chick"})
    local events=game:Step(0,{pairs={{1,3},{2,3},{3,1}}})
    Close(game.roundScore,6); Close(Item(game,1).remaining,4); Close(Item(game,2).remaining,0)
    assert(Item(game,3).location=="discard" and Item(game,4).location=="bottle")
    assert(#Repair.Events(events,"consume")==1 and #Repair.Events(events,"score")==1)
end)

Test("满瓶切割先排队，吃鸡释放空位按FIFO补位，不回放旧接触",function()
    local game=Make({"knife","apple","chick"})
    while #game:BottleItems()<100 do game:_Spawn("ball",{}) end
    local older=game:_Spawn("egg",{})
    local nextUid=game._nextUid
    game:Step(0,{pairs={{1,2},{1,3}}})
    assert(Item(game,2).id=="apple_half" and Item(game,3).location=="discard")
    assert(older.location=="bottle" and #game.spawnQueue==1 and game.spawnQueue[1]==nextUid)
    assert(Item(game,nextUid).id=="apple_half" and Item(game,nextUid).location=="queued")
    Close(game.roundScore,6); Close(Item(game,1).remaining,4)
end)

Test("运行中新小刀等完整4秒，回合开局仍就绪且说明全入口同源",function()
    local game=Make({"apple"})
    local knife=game:_Spawn("knife",{})
    local contacts={pairs={{knife.uid,1}}}
    Close(knife.remaining,4)
    game:Step(3.99,contacts); assert(Item(game,1).id=="apple")
    game:Step(.01,contacts); assert(Item(game,1).id=="apple_half")
    local initial=Make({"knife"}); Close(Item(initial,1).remaining,0)
    local text=require("Bottle.ItemText")
    assert(Items.byId.knife.cooldown==4 and Items.HasCooldown("knife"))
    for _,effect in ipairs({text.Effect(initial,"knife"),text.Effect(initial,"knife",Item(initial,1))}) do
        assert(effect==Items.byId.knife.effect and effect:find("[[chick]]",1,true)
            and effect:find("小鸡价值×2",1,true) and effect:find("冷却：4秒",1,true))
        assert(not effect:find("sheep",1,true) and not effect:find("5秒",1,true))
    end
end)

function Tests.Run()
    for _,case in ipairs(cases) do
        local ok,err=pcall(case.run)
        assert(ok,"[SourceUpdateTests] "..case.name..": "..tostring(err))
    end
    print("[SourceUpdateTests] "..#cases.."项通过")
    return #cases
end
return Tests
