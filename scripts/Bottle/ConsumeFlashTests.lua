-- 消耗反馈回归：规则立即完成，表现只读快照与消耗者当前姿态。
-- 纯 Lua 内存测试；不启动预览，不读写玩家存档，不创建引擎对象。
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Repair = require("Bottle.RepairTests")
local Expansion = require("Bottle.ExpansionEffects")
local PhysicsCore = require("Bottle.Physics")
local ConsumeFlash = require("Bottle.ConsumeFlash")
local Tests = {}

---@param actual number?
---@param expected number
local function Close(actual, expected)
    assert(type(actual)=="number" and math.abs(actual-expected)<1e-7,
        "expected=" .. expected .. " actual=" .. tostring(actual))
end
---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid)) end
---@param ids string[]
---@return BottleGame
local function Fixture(ids)
    local game=Repair.Fixture(ids)
    assert(game:Start())
    for _,item in ipairs(game:BottleItems()) do item.remaining=0 end
    return game
end
---@param events GameEvent[]
---@param uid integer?
---@return GameEvent[]
local function Consumed(events, uid) return Repair.Events(events,"consume",uid) end
---@return any
local function Physics()
    return {bodies={[1]={kind="apple"}},
        GetPose=function() return .4,1.2,.7,.55 end,
        GetSoftPose=function() return nil end}
end

---@type {name:string,run:fun()}[]
local cases={}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases+1]={name=name,run=run} end

Test("真实接触消耗当步离瓶并加永久价值、保留原始属性和位置",function()
    local game=Fixture({"glutton","apple"})
    local target=Item(game,2)
    target.scale,target.rollValue,target.woolCount=1.3,4,2
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.4,y=1.2}}})
    local consumed=Consumed(events,2)
    assert(#consumed==1 and consumed[1].id=="apple" and consumed[1].reason=="consume")
    assert(consumed[1].consumerUid==1 and consumed[1].consumerId=="glutton")
    Close(consumed[1].toX,0)
    Close(consumed[1].toY,1)
    Close(consumed[1].scale,1.3)
    Close(consumed[1].rollValue,4)
    Close(consumed[1].woolCount,2)
    Close(consumed[1].x,.4)
    Close(consumed[1].y,1.2)
    assert(target.location=="discard" and #game:BottleItems()==1)
    Close(Item(game,1).permBonus,1)
    Close(Item(game,1).scale,1.1)
    Close(game.roundScore,0)
    local consumedAt,removedAt=0,0
    for i,event in ipairs(events) do
        if event.uid==2 and event.kind=="consume" then consumedAt=i end
        if event.uid==2 and event.kind=="remove" then removedAt=i end
    end
    assert(consumedAt>0 and removedAt>consumedAt)
    assert(#Consumed(game:Step(0,{pairs={{1,2}}}),2)==0)
end)

Test("食客消耗金币即时入账、不等待任何闪烁时间",function()
    local game=Fixture({"diner","apple"})
    local expected=game:_Value(Item(game,2))*2
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    assert(#Consumed(events,2)==1 and Item(game,2).location=="discard")
    Close(game.roundScore,expected)
    Close(game.score,expected)
    Close(game.totalScore,expected)
    assert(#Repair.Events(events,"score",1)==1)
end)

Test("正式Physics同步当步移除刚体和接触而闪烁仅保留独立快照",function()
    for _,id in ipairs({"ghost","balloon"}) do
        local game=Fixture({id})
        game._lastPositions[1]={x=.4,y=1.2}
        local node={position2D={x=.4,y=1.2},rotation2D=30}
        function node:Remove() self.removed=true end
        function node:Dispose() self.disposed=true end
        local sceneSteps={}
        local physics=setmetatable({bodies={[1]={uid=1,kind=id,node=node,radius=.3}},
            _retired={},_pairs={["1:2"]={a=1,b=2,count=1}},_impactContacts={},
            stepContactFacts=require("Bottle.StepContactFacts").New(),
            _bottom={[1]=true},_top={},_wall={[1]=true},_side={},_eventRemoved={},
            _mergeSpawns={},_nearSpawns={},_exactSpawns={},clock=.2,
            expansion={Remember=function() end,Forget=function() end,Flush=function() end},
            scene={Update=function(_,dt) sceneSteps[#sceneSteps+1]=dt end}},
            {__index=PhysicsCore}) --[[@as any]]
        local expected=id=="ghost" and game:_Value(Item(game,1)) or 0
        local events={}
        if id=="balloon" then
            assert(Expansion.BurstBalloon(game,Item(game,1),events))
        else events=game:Consume(1) end
        Close(game.score,expected)
        assert(#game:BottleItems()==0)
        physics:RememberEvents(events)
        local flash=ConsumeFlash.New()
        assert(flash:Capture(assert(Consumed(events,1)[1]),physics))
        physics:Sync(game:BottleItems())
        assert(physics.bodies[1]==nil and node.removed and node.disposed)
        assert(next(physics._pairs)==nil and physics._bottom[1]==nil and physics._wall[1]==nil)
        assert(#sceneSteps==1 and sceneSteps[1]==0,"删除屏障不推进任何物理时间")
        Close(physics.clock,.2)
        assert(#flash.flashes==1 and flash.flashes[1].id==id)
        Close(flash.flashes[1].age,0)
        Close(game.score,expected)
    end
end)

Test("香蕉立即变皮而消耗事件保留香蕉旧图案",function()
    local game=Fixture({"glutton","banana"})
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    local consumed=Consumed(events,2)
    assert(#consumed==1 and consumed[1].id=="banana")
    assert(Item(game,2).id=="banana_peel" and Item(game,2).location=="bottle")
    assert(#Repair.Events(events,"transform",2)==1)
    Close(consumed[1].x,.5)
    Close(consumed[1].y,1)
end)

Test("金针菇和炒蛋立即重生且事件保存传送前位置",function()
    for _,id in ipairs({"enoki","tomato_egg"}) do
        local game=Fixture({id})
        game._lastPositions[1]={x=.3,y=1.7}
        local events={}
        assert(game:_Destroy(1,false,events,nil,"consume"))
        local consumed=Consumed(events,1)
        assert(#consumed==1 and consumed[1].id==id and Item(game,1).location=="bottle")
        Close(consumed[1].x,.3)
        Close(consumed[1].y,1.7)
        assert(#Repair.Events(events,"respawn",1)==1 and game._lastPositions[1]==nil)
    end
end)

Test("护盾拒绝和重复消耗不会产生伪消耗事件",function()
    local game=Fixture({"apple"})
    Item(game,1).shielded=true
    local rejected=game:Consume(1)
    assert(#Consumed(rejected)==0 and Item(game,1).location=="bottle")
    Item(game,1).shielded=false
    assert(#Consumed(game:Consume(1),1)==1 and Item(game,1).location=="discard")
    assert(#Consumed(game:Consume(1),1)==0)
end)

Test("气球爆裂同时保留爆炸和消耗闪烁、实体立即离瓶",function()
    local game=Fixture({"balloon"})
    local events={}
    assert(Expansion.BurstBalloon(game,Item(game,1),events))
    assert(Item(game,1).location=="discard" and #Repair.Events(events,"burst",1)==1)
    local consume=Consumed(events,1)
    assert(#consume==1 and consume[1].reason=="burst")
    local flash=ConsumeFlash.New()
    local physics=Physics()
    physics.bodies[1].kind="balloon"
    assert(flash:Capture(consume[1],physics) and #flash.flashes==1)
    assert(flash.flashes[1].id=="balloon" and not flash:Capture(consume[1],physics))
end)

Test("匹配旧刚体时快照真实姿态且不改变规则或物理对象",function()
    local flash=ConsumeFlash.New()
    local physics=Physics()
    local event={kind="consume",uid=1,id="apple",scale=1.3,rollValue=6,woolCount=2,x=8,y=9}
    assert(flash:Capture(event,physics))
    local pose=assert(flash.flashes[1])
    assert(#flash.flashes==1 and pose.id=="apple")
    Close(pose.x,.4)
    Close(pose.y,1.2)
    Close(pose.angle,.7)
    Close(pose.radius,Items.byId.apple.radius*1.3)
    Close(pose.rollValue,6)
    Close(pose.woolCount,2)
    assert(physics.bodies[1].kind=="apple" and event.x==8 and event.y==9)
end)

Test("已换图案的刚体不能冒充消耗前姿态、使用事件坐标",function()
    local flash=ConsumeFlash.New()
    local physics=Physics()
    physics.bodies[1].kind="banana_peel"
    physics.GetPose=function() error("不同图案的刚体不能读取") end
    assert(flash:Capture({kind="consume",uid=1,id="banana",scale=1.2,x=.2,y=1},physics))
    local pose=assert(flash.flashes[1])
    assert(pose.id=="banana")
    Close(pose.x,.2)
    Close(pose.y,1)
end)

Test("无刚体回退生成原点、缺乏位置不制造瓶中残影",function()
    local flash=ConsumeFlash.New()
    local physics=Physics()
    physics.bodies={}
    physics.GetPose=function() error("缺失刚体不能读取默认姿态") end
    assert(not flash:Capture({kind="consume",uid=1,id="apple",scale=1},physics))
    assert(#flash.flashes==0)
    assert(flash:Capture({kind="consume",uid=2,id="apple",scale=1},physics,{x=0,y=6}))
    Close(flash.flashes[1].x,0)
    Close(flash.flashes[1].y,6)
end)

Test("软体段深复制、物理同步移除后旧外形保持稳定",function()
    local flash=ConsumeFlash.New()
    local soft={{x=.2,y=1,angle=.4,halfLength=.3,halfWidth=.1,u0=0,u1=.5}}
    local physics=Physics()
    physics.bodies[1].kind="bacon"
    physics.GetSoftPose=function() return soft end
    assert(flash:Capture({kind="consume",uid=1,id="bacon",scale=1},physics))
    local pose=assert(flash.flashes[1])
    assert(pose.soft~=soft and pose.soft[1]~=soft[1])
    soft[1].x,soft[1].halfLength=99,99
    physics.bodies={}
    physics.GetPose=function() error("快照后不得访问物理") end
    physics.GetSoftPose=function() error("快照后不得访问软体") end
    flash:Update(.01)
    Close(pose.soft[1].x,.2)
    Close(pose.soft[1].halfLength,.3)
end)

Test("闪烁在规定间隔切换并在0.48秒到期移除",function()
    Close(ConsumeFlash.LIFETIME,.48)
    Close(ConsumeFlash.INTERVAL,.08)
    local flash=ConsumeFlash.New()
    assert(flash:Capture({kind="consume",uid=1,id="apple",scale=1},Physics()))
    local pose=assert(flash.flashes[1])
    assert(ConsumeFlash.Visible(pose))
    flash:Update(.079)
    assert(ConsumeFlash.Visible(pose))
    flash:Update(.0011)
    assert(not ConsumeFlash.Visible(pose))
    flash:Update(.08)
    assert(ConsumeFlash.Visible(pose))
    -- 到期对象归还池后不能继续读取该借用引用；独立快照验证端点可见性。
    local endpoint={animation=pose.animation,age=ConsumeFlash.LIFETIME,lifetime=pose.lifetime}
    assert(not ConsumeFlash.Visible(endpoint --[[@as BottleConsumedPose]]))
    flash:Update(.32)
    assert(#flash.flashes==0)
end)

Test("原物品重生后消耗跳字仍保留原始图标和旧位置",function()
    local game=Fixture({"enoki"})
    game._lastPositions[1]={x=.3,y=1.7}
    local events=game:Consume(1)
    local event=Consumed(events,1)[1]
    assert(event and Item(game,1).location=="bottle")
    local flash=ConsumeFlash.New()
    assert(flash:Capture(event,{bodies={}} --[[@as any]]))
    local popup=flash.popups[1]
    assert(popup.id=="enoki" and popup.uid==1)
    Close(popup.x,.3)
    Close(popup.y,1.7)
    assert(not flash:Capture(event,{bodies={}} --[[@as any]]) and #flash.popups==1)
    local score=game.score
    flash:Update(.5)
    assert(#flash.flashes==0 and #flash.popups==1,"白闪结束不能提前移除跳字")
    Close(game.score,score)
    flash:Update(1.5)
    assert(#flash.popups==0,"跳字到期清理")
end)

Test("重复同一事件不重放闪烁或延长寿命、重置清空残影",function()
    local flash=ConsumeFlash.New()
    local physics=Physics()
    local event={kind="consume",uid=1,id="apple",scale=1}
    assert(flash:Capture(event,physics))
    flash:Update(.2)
    assert(not flash:Capture(event,physics) and #flash.flashes==1)
    assert(#flash.popups==1)
    Close(flash.flashes[1].age,.2)
    flash:Update(.3)
    assert(#flash.flashes==0)
    assert(not flash:Capture(event,physics) and #flash.flashes==0)
    local nextEvent={kind="consume",uid=1,id="apple",scale=1}
    assert(flash:Capture(nextEvent,physics) and #flash.flashes==1)
    flash:Reset()
    assert(#flash.flashes==0 and #flash.popups==0)
end)

---@return any
local function EatingPhysics()
    return {bodies={[1]={kind="apple"},[2]={kind="glutton"}},
        GetPose=function(_,uid)
            if uid==2 then return 1,1.2,0,.4 end
            return .4,1.2,.7,.3
        end,GetSoftPose=function() return nil end}
end
---@param uid integer?
---@return GameEvent
local function EatingEvent(uid)
    return {kind="consume",uid=uid or 1,id="apple",reason="consume",scale=1,
        consumerUid=2,consumerId="glutton",x=.4,y=1.2,toX=1,toY=1.2}
end

Test("原色吸入连续可见、先放大再沿弧线缩入真实消耗者",function()
    local flash,physics=ConsumeFlash.New(),EatingPhysics()
    assert(flash:Capture(EatingEvent(),physics))
    local pose=assert(flash.flashes[1])
    assert(pose.consumerUid==2 and pose.emphasis and #flash.popups==0)
    local x,y,scale=ConsumeFlash.VisualPose(pose)
    Close(x,.4);Close(y,1.2);Close(scale,1)
    flash:Update(ConsumeFlash.HOLD,physics)
    x,y,scale=ConsumeFlash.VisualPose(pose)
    Close(x,.4);assert(y>1.2 and scale>1)
    flash:Update(ConsumeFlash.FLIGHT/2,physics)
    x,y,scale=ConsumeFlash.VisualPose(pose)
    assert(x>.4 and x<1 and y>1.2 and scale<1 and ConsumeFlash.Visible(pose))
    physics.GetPose=function(_,uid) assert(uid==2);return 1.5,1.7,0,.4 end
    flash:Update(.01,physics)
    Close(pose.targetX,1.5);Close(pose.targetY,1.7)
    local endpoint={} --[[@as BottleConsumedPose]]
    for key,value in pairs(pose) do endpoint[key]=value end
    endpoint.age=ConsumeFlash.ABSORB_LIFETIME
    x,y,scale=ConsumeFlash.VisualPose(endpoint)
    Close(x,1.5);Close(y,1.7);Close(scale,0)
    flash:Update(1,physics)
    assert(#flash.flashes==0 and next(flash.rebounds)==nil,"大dt不得补播过期回弹")
end)

Test("吸入抵达后才回弹、连续吃多个合并且完整恢复",function()
    local flash,physics=ConsumeFlash.New(),EatingPhysics()
    flash:Capture(EatingEvent(),physics)
    flash:Update(ConsumeFlash.ABSORB_LIFETIME-.001,physics)
    assert(next(flash.rebounds)==nil)
    flash:Update(.002,physics)
    assert(#flash.flashes==0 and flash.rebounds[2])
    local sx,sy=flash:ReboundScale(2,.04)
    assert(sx>1 and sy<1)
    sx,sy=flash:ReboundScale(2,.12)
    assert(sx<1 and sy>1)
    -- 新到达者只合并，不能把进行中的回弹重置到零。
    flash:Capture(EatingEvent(3),physics)
    flash.flashes[1].age=ConsumeFlash.ABSORB_LIFETIME-.01
    flash:Update(.04,physics)
    Close(flash.rebounds[2].age,.041)
    flash:Update(ConsumeFlash.REBOUND,physics)
    sx,sy=flash:ReboundScale(2)
    Close(sx,1);Close(sy,1);assert(next(flash.rebounds)==nil)
end)

Test("消耗者消失或转化时保留最后终点且不让新身份回弹",function()
    for _,kind in ipairs({"missing","banana_peel"}) do
        local flash,physics=ConsumeFlash.New(),EatingPhysics()
        flash:Capture(EatingEvent(),physics)
        if kind=="missing" then physics.bodies[2]=nil else physics.bodies[2].kind=kind end
        physics.GetPose=function() error("失效目标不得读取") end
        flash:Update(ConsumeFlash.ABSORB_LIFETIME,physics)
        assert(#flash.flashes==0 and next(flash.rebounds)==nil)
    end
end)

Test("同批最多强调三组、普通吸入仍保留且重置清空回弹",function()
    local flash,physics=ConsumeFlash.New(),EatingPhysics()
    for uid=3,9 do assert(flash:Capture(EatingEvent(uid),physics)) end
    local emphasized=0
    for _,pose in ipairs(flash.flashes) do if pose.emphasis then emphasized=emphasized+1 end end
    assert(#flash.flashes==7 and emphasized==3 and #flash.popups==0)
    flash:Update(ConsumeFlash.ABSORB_LIFETIME,physics)
    assert(flash.rebounds[2])
    flash:Reset()
    assert(next(flash.rebounds)==nil and #flash.flashes==0)
end)

Test("合成自耗爆裂消灭和主动移除不伪装成吞食",function()
    for _,reason in ipairs({"merge_checked","self","burst","eliminate","exhausted"}) do
        local flash=ConsumeFlash.New()
        local event=EatingEvent()
        event.reason=reason
        assert(flash:Capture(event,EatingPhysics()))
        local hasPopup = reason ~= "eliminate" and reason ~= "burst"
        assert(not flash.flashes[1].consumerUid and #flash.popups==(hasPopup and 1 or 0))
    end
end)

---@return integer
function Tests.Run()
    for _,case in ipairs(cases) do
        local ok,err=pcall(case.run)
        assert(ok,"Bottle.ConsumeFlashTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end

return Tests
