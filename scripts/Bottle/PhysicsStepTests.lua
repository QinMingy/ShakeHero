-- 调用实际BeforeStep/AfterStep/Step/Contact/Contacts；fake scene只验原生单步契约，不代替碰撞验收。
local Physics = require("Bottle.Physics")
local StepContactFacts = require("Bottle.StepContactFacts")
local Expansion = require("Bottle.ExpansionPhysics")
local Tests = {}

---@return BottlePhysics,table
local function Fixture()
    local calls={before=0,after=0,beginSpeed=0,endSpeed=0,shake=0,motion=0,flush=0,soft=0,integrations=0}
    local sim=setmetatable({bodies={},world={gravity={x=0,y=0},continuousPhysics=true,
        velocityIterations=12,positionIterations=8},ccdWalls={},stepContactFacts=StepContactFacts.New(),
        _pairs={},_bottom={},_top={},_wall={},_side={},_impactContacts={},_impacts={},_retired={},
        _disposed=false,_updating=false,_flushing=false,_manualStep=false,autoUpdate=false,
        _nextGeneration=2,clock=0,speedMultiplier=1}, {__index=Physics}) --[[@as BottlePhysics]]
    local wall={name="wall_right"} --[[@as Node]]
    sim._walls={wall}
    for uid=1,2 do
        local node={name="item_"..uid,position2D={x=(uid-1)*.6,y=3},rotation2D=0} --[[@as Node]]
        local body={bullet=true,linearVelocity={x=6,y=0},angularVelocity=0,gravityScale=0,mass=1} --[[@as RigidBody2D]]
        sim.bodies[uid]={uid=uid,generation=uid,kind="ball",node=node,body=body,
            parts={{node=node,body=body}},shape="circle",pathLength=0,lastX=node.position2D.x,lastY=3,
            radius=.2,envelope=.2,newbornRemaining=.2,ccdGuardRemaining=0} --[[@as BottleBody]]
    end
    sim.bodies[1].soft={Step=function(_,dt)
        assert(dt==1/60);calls.soft=calls.soft+1
    end,GetPose=function()
        return {{x=sim.bodies[1].node.position2D.x,y=3,angle=0,halfLength=.1,halfWidth=.05,u0=0,u1=1}}
    end} --[[@as BottleSoftBacon]]
    sim.motion={Step=function(_,dt)
        assert(dt==1/60);calls.motion=calls.motion+1;return 0,0
    end} --[[@as BottleShakeMotion]]
    sim.expansion={states={[1]={anchored=false,rotations={},dashRemaining=0},
        [2]={anchored=false,rotations={},dashRemaining=0}},
        Flush=function() calls.flush=calls.flush+1 end,
        SampleShake=function(_,dt) assert(dt==1/60);calls.shake=calls.shake+1 end,
        Controlled=function() return true end,
        Before=function(_,_,dt) assert(dt==1/60);calls.before=calls.before+1 end,
        BeginSpeed=function() calls.beginSpeed=calls.beginSpeed+1;return {} end,
        EndSpeed=function() calls.endSpeed=calls.endSpeed+1 end,
        After=function(_,_,dt) assert(dt==1/60);calls.after=calls.after+1 end,
        Contacts=function() end,
        Remember=function() end,
    } --[[@as BottleExpansionPhysics]]
    local function Event(nodeA,nodeB)
        local function Ptr(value) return {GetPtr=function() return value end} end
        return {World=Ptr(sim.world),NodeA=Ptr(nodeA),NodeB=Ptr(nodeB)} --[[@as PhysicsBeginContact2DEventData]]
    end
    sim.scene={Update=function(_,dt)
        if sim.autoUpdate and not sim._manualStep then assert(sim:BeforeStep(dt)) end
        assert(sim._updating and dt==1/60,"每同步步恰好一次真实dt积分且维持更新屏障")
        assert(sim.clock==(calls.after+1)/60,"clock只能在原生步边界推进一次")
        calls.integrations=calls.integrations+1
        for _,record in pairs(sim.bodies) do
            record.node.position2D.x=record.node.position2D.x+record.body.linearVelocity.x*dt
        end
        if calls.integrations==1 then
            for _,begin in ipairs({true,false}) do
                sim:Contact(Event(sim.bodies[1].node,sim.bodies[2].node),begin)
                sim:Contact(Event(sim.bodies[1].node,wall),begin)
            end
        end
        if calls.integrations==1 then assert(math.abs(sim.bodies[1].node.position2D.x-.1)<1e-12) end
        if sim.autoUpdate and not sim._manualStep then assert(sim:AfterStep(dt)) end
    end} --[[@as Scene]]
    return sim,calls
end

function Tests.Run()
    local sim,calls=Fixture()
    sim:Step(1/60)
    assert(calls.integrations==1 and calls.before==2 and calls.after==1 and calls.soft==1)
    assert(calls.beginSpeed==1 and calls.endSpeed==1 and calls.motion==1 and calls.shake==1 and calls.flush==1)
    assert(sim.clock==1/60 and math.abs(sim.bodies[1].newbornRemaining-(.2-1/60))<1e-12)
    assert(sim.world.continuousPhysics and sim.world.velocityIterations==12 and sim.world.positionIterations==8)
    assert(not sim._updating and sim._pairs["1:2"]==nil and sim._side[1]==nil,"End仍须清掉实时计数")
    local contacts=sim:Contacts()
    assert(#contacts.pairs==1 and contacts.pairs[1][1]==1 and contacts.pairs[1][2]==2)
    assert(contacts.side[1] and contacts.wall[1] and sim:HadPair(1,2),"同宏真实Begin后End不能丢事实")
    assert(#sim:TakeImpacts()==2,"同原生步短接触不能重复发出声音事实")

    sim:Step(0)
    assert(calls.integrations==1 and calls.after==1 and sim.clock==1/60,"零dt不积分或推进动作")
    sim:Step(1/60)
    contacts=sim:Contacts()
    assert(calls.integrations==2 and calls.before==4 and calls.after==2 and calls.soft==2)
    assert(#contacts.pairs==0 and not contacts.side[1] and not sim:HadPair(1,2),"下一个宏步必须清空旧短接触")
    sim._pairs["1:2"]={a=1,b=2,count=1}
    assert(sim:HadPair(1.0,2.0) and not sim:HadPair(1.5,2) and not sim:HadPair(1,nil),
        "CJSON浮点UID应匹配持续接触且安全拒绝非整数/缺失目标")

    -- 前后钩子本身不积分；引擎负责它们之间的唯一物理更新。
    local split,splitCalls=Fixture()
    assert(not split:BeforeStep(0) and not split:AfterStep(0))
    assert(split:BeforeStep(1/60))
    assert(splitCalls.integrations==0 and splitCalls.after==0 and split._updating)
    assert(split.bodies[1].node.position2D.x==0 and split.clock==1/60)
    assert(not split:BeforeStep(1/60),"不能重入同一个尚未收束的原生步")
    assert(split:AfterStep(1/60) and not split:AfterStep(1/60))
    assert(splitCalls.integrations==0 and splitCalls.after==1 and split.bodies[1].pathLength==0)

    -- main自动前后转发和保留的同步入口共存，Step不能重复调用自动钩子。
    local automatic,autoCalls=Fixture()
    automatic:SetAutoUpdate(true)
    assert(automatic.autoUpdate and automatic.scene.updateEnabled and automatic.world.updateEnabled)
    automatic.scene:Update(1/60)
    assert(autoCalls.integrations==1 and autoCalls.before==2 and autoCalls.after==1)
    automatic:Step(1/60)
    assert(autoCalls.integrations==2 and autoCalls.before==4 and autoCalls.after==2 and not automatic._manualStep)
    automatic:SetAutoUpdate(false)
    assert(not automatic.autoUpdate and not automatic.scene.updateEnabled and automatic.world.updateEnabled)

    -- 路程按每个真实步采样，往返不抵消；独立快照不能引用下一帧的Node或段姿态。
    local moving=Fixture()
    moving:Step(1/60)
    local retained=moving:Contacts()
    assert(retained.members[1]=="ball" and retained.generations[1]==1 and retained.pathGeneration[1]==1)
    assert(math.abs(retained.pathLengths[1]-.1)<1e-12)
    assert(retained.poses[1].angle==select(3,moving:GetPose(1)) and retained.poses[1].radius==.2)
    moving.bodies[1].body.linearVelocity.x=-6
    moving:Step(1/60)
    assert(math.abs(moving.bodies[1].pathLength-.2)<1e-12)
    assert(math.abs(retained.positions[1].x-.1)<1e-12 and math.abs(retained.poses[1].x-.1)<1e-12)
    assert(retained.poses[1].soft and math.abs(retained.poses[1].soft[1].x-.1)<1e-12)
    -- 与实际Expansion.moveWhole相同的传送基线重设，不计入跨越跳变。
    moving.bodies[1].node.position2D.x=1
    moving.bodies[1].lastX=1
    moving.bodies[1].body.linearVelocity.x=6
    moving:Step(1/60)
    assert(math.abs(moving.bodies[1].pathLength-.3)<1e-12)

    -- 合成事件坐标属于产生事件的接触快照，不能被继续运行的旧材料位置覆盖。
    moving._mergeSpawns={}
    moving:RememberEvents({{kind="merge",uid=3,a=1,b=2,x=-.7,y=2.4}})
    assert(moving._mergeSpawns[3].x==-.7 and moving._mergeSpawns[3].y==2.4)

    local other=Fixture()
    other:Step(1/60)
    other:_ForgetContacts(1)
    contacts=other:Contacts()
    assert(#contacts.pairs==0 and not contacts.side[1] and not other:HadPair(1,2),"删除/传送接口需同步清理事实窗")
    local flightSim=Fixture()
    flightSim.bodies[2]=nil
    local disc=flightSim.bodies[1]
    disc.sensor,disc.soft=true,nil
    flightSim.expansion=Expansion.New()
    local state=flightSim.expansion:State(disc)
    state.flight={fromX=0,fromY=3,toX=1,toY=3,duration=.2,elapsed=.2,progress=1,
        endpointAge=0,arc=.2,endpointWait=true}
    local vector=Vector2
    if not vector then _G.Vector2=function(x,y) return {x=x,y=y} end end
    local ok,err=pcall(function()
        -- 实际_CreateItem每次换代并把新位置作为路程零基线；同uid重建不沿用旧累计。
        local factory=setmetatable({bodies={},ghostPoop=false,_nextGeneration=7,
            scene={CreateChild=function(_,name)
                local node={name=name}
                function node:SetPosition2D(x,y) self.position2D={x=x,y=y} end
                function node:CreateComponent() return {} end
                return node
            end}}, {__index=Physics}) --[[@as BottlePhysics]]
        local item={uid=1,id="ball",scale=1,weight=1} --[[@as ItemInstance]]
        factory:_CreateItem(item,0,3)
        local first=factory.bodies[1]
        assert(first.generation==8 and first.pathLength==0 and first.lastX==0 and first.lastY==3)
        first.pathLength=9
        factory:_CreateItem(item,1.2,2)
        local replacement=factory.bodies[1]
        assert(replacement~=first and replacement.generation==9 and replacement.pathLength==0)
        assert(replacement.lastX==1.2 and replacement.lastY==2 and factory._nextGeneration==9)
        flightSim.expansion:After(flightSim,1/60)
        assert(state.flight and not state.arrived and state.hit==nil,"无目标飞盘第一宏仍按原端点等待")
        flightSim.expansion:After(flightSim,1/60)
        assert(state.flight==nil and state.arrived and state.hit==nil,"无目标飞盘按原endpoint流程结束")
        assert(disc.body.linearVelocity.x==0 and disc.body.linearVelocity.y==0)
    end)
    _G.Vector2=vector
    assert(ok,err)
    return 10
end

return Tests
