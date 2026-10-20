-- 独立物理输入/规则FIFO回归：真实 Game/FrameBudget/PresentationState，physics仅为边界替身。
-- 独立入口：require("Bottle.SimulationTests").Run()；不创建引擎对象、不构建、不读写存档。
local FrameBudget = require("Bottle.FrameBudget")
local Simulation = require("Bottle.Simulation")
local PresentationState = require("Bottle.PresentationState")
local Game = require("Bottle.Game")
local Items = require("Bottle.Items")
local Repair = require("Bottle.RepairTests")
local Tests = {}
local STEP = 1 / 60

---@param actual number
---@param expected number
---@param label string?
local function Close(actual, expected, label)
    assert(math.abs(actual - expected) < 1e-7,
        (label or "数值") .. " expected=" .. expected .. " actual=" .. actual)
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

---@generic T
---@param value T
---@return T
local function Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = Copy(entry) end
    return copy --[[@as T]]
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid), "缺少测试实例 " .. uid) end

-- 沿用 Tests/RepairTests 的 Snapshot→Restore 夹具，保留正式实例初始化及真实 PRNG。
---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
local function Fixture(ids, relics)
    local game = Repair.Fixture(ids, relics)
    assert(game:Start())
    return game
end

---@param game BottleGame
local function Identity(game)
    for _, list in ipairs({game.deck, game.discard, game:BottleItems()}) do
        local seen = {}
        for _, item in ipairs(list) do
            assert(not seen[item.uid] and game:Get(item.uid) == item, "实例身份丢失或重复")
            seen[item.uid] = true
        end
    end
end

---@class BottleSimulationProbe
---@field game BottleGame
---@field bound BottleGame
---@field boundPending boolean
---@field physics any
---@field before integer
---@field after integer
---@field contactReads integer
---@field remembers integer
---@field effects integer
---@field syncs integer
---@field publishes integer
---@field log string[]
---@field flat GameEvent[]
---@field batches GameEvent[][]
---@field remembered GameEvent[][]
---@field published GameEvent[][]
---@field onEffects (fun(events:GameEvent[],physicsView:table))?

-- 明确输入包含物理成员身份，避免把测试替身冒充原生碰撞求解器。
---@param game BottleGame
---@param contacts BottleContacts?
---@return table
local function Input(game, contacts)
    local result = Copy(contacts or {}) --[[@as table]]
    result.members, result.generations = {}, {}
    for _, item in ipairs(game:BottleItems()) do
        result.members[item.uid], result.generations[item.uid] = item.id, 1
    end
    return result
end

-- 同步对照也使用同一物理成员契约；批内新生成但尚未入物理世界的实例不提前走冷却。
---@param game BottleGame
---@param dt number
---@param contacts table
---@return GameEvent[]
local function DirectStep(game,dt,contacts)
    game._physicalMembers=contacts.members
    local events=game:Step(dt,contacts)
    game._physicalMembers=nil
    return events
end

---@param game BottleGame
---@param contacts BottleContacts?
---@param budget BottleFrameBudget?
---@param yieldEffects boolean?
---@return BottleSimulation, BottleSimulationProbe
local function Harness(game, contacts, budget, yieldEffects)
    ---@type BottleSimulationProbe
    local probe = {game=game,bound=game,boundPending=false,before=0,after=0,contactReads=0,
        remembers=0,effects=0,syncs=0,publishes=0,log={},flat={},batches={},remembered={},published={}}
    local physics = {bodies={}} --[[@as any]]
    probe.physics = physics
    for _, item in ipairs(game:BottleItems()) do physics.bodies[item.uid]={generation=1,kind=item.id} end
    function physics:Step() error("规则Update不得调用Physics.Step") end
    function physics:BeforeStep() probe.before=probe.before+1 end
    function physics:AfterStep() probe.after=probe.after+1 end
    function physics:TakeImpacts() return {} end
    function physics:Contacts()
        probe.contactReads=probe.contactReads+1
        local result=Copy(contacts or {}) --[[@as table]]
        result.members,result.generations={},{}
        for uid,record in pairs(self.bodies) do
            result.members[uid],result.generations[uid]=record.kind,record.generation
        end
        return result
    end
    function physics:RememberEvents(events)
        assert(not coroutine.isyieldable(),"物理命令只能在规则协程之外完整提交")
        probe.remembers=probe.remembers+1
        probe.remembered[#probe.remembered+1]=Copy(events)
        probe.log[#probe.log+1]="Remember"
    end
    local callbacks={
        bind=function(bound,pending) probe.bound,probe.boundPending=bound,pending end,
        events=function(events,physicsView)
            probe.effects=probe.effects+1
            probe.batches[#probe.batches+1]=Copy(events)
            probe.log[#probe.log+1]="Effects"
            if probe.onEffects then probe.onEffects(events,physicsView) end
            for _,event in ipairs(events) do
                if yieldEffects then FrameBudget.Checkpoint() end
                probe.flat[#probe.flat+1]=Copy(event)
            end
        end,
        sync=function()
            assert(not coroutine.isyieldable(),"Sync不能随规则协程半批提交")
            probe.syncs=probe.syncs+1;probe.log[#probe.log+1]="Sync"
        end,
        publish=function(events)
            assert(not coroutine.isyieldable(),"反馈只能在规则协程之外发布")
            assert(probe.syncs==probe.publishes+1 and probe.bound==game and not probe.boundPending,
                "必须先完成Sync与bind(false)再发布整批反馈")
            probe.publishes=probe.publishes+1
            probe.published[#probe.published+1]=Copy(events)
            probe.log[#probe.log+1]="Publish"
        end,
    }
    return Simulation.New(game,physics,callbacks,
        budget or FrameBudget.New(4,function() return 0 end,1000000)),probe
end

---@param simulation BottleSimulation
---@param count integer
---@return integer
local function Drain(simulation,count)
    local frames=0
    while simulation:Busy() or simulation.completedSteps<count do
        frames=frames+1
        assert(frames<30000,"规则FIFO未在有限帧数内完成")
        simulation:Update(0)
    end
    assert(simulation.completedSteps==count,"规则包重复消费或凭空生成")
    return frames
end

---@param probe BottleSimulationProbe
---@param count integer
local function CommitOrder(probe,count)
    local expected={"Effects","Remember","Sync","Publish"}
    assert(#probe.log==count*#expected,"提交缺项或重复")
    for index,call in ipairs(probe.log) do
        assert(call==expected[(index-1)%#expected+1],"提交次序错误 "..index..":"..call)
    end
    assert(probe.remembers==count and probe.effects==count and probe.syncs==count and probe.publishes==count)
    assert(Equal(probe.remembered,probe.published),"发布必须使用已完整同步的同一批事件")
    assert(probe.bound==probe.game and not probe.boundPending)
end

---@type {name:string,run:fun()}[]
local cases={}
---@param name string
---@param run fun()
local function Test(name,run) cases[#cases+1]={name=name,run=run} end

Test("展示副本冻结标量和实例属性，保留查询能力及uid身份，不抽随机数", function()
    local game = Fixture({"glutton", "apple", "fruit_tree"})
    game.spawnQueue = {3}
    local rng, revision = game._rngState, game.revision
    local view = PresentationState.Capture(game)
    assert(getmetatable(view) == getmetatable(game) and view ~= game)
    assert(view._instances ~= game._instances and view.deck ~= game.deck)
    assert(view.discard ~= game.discard and view.drawn ~= game.drawn)
    assert(view.spawnQueue ~= game.spawnQueue and view.options ~= game.options and view.relics ~= game.relics)
    assert(view:Get(1) ~= game:Get(1) and view.deck[1] == view:Get(1))
    assert(game._rngState == rng and game.revision == revision)
    local frozen = Copy(view)
    local value = view:_Value(Item(view, 2))
    game.score, game.roundScore = 123, 12
    Item(game, 2).bonus, Item(game, 2).id = 99, "banana"
    game.deck[1], game.spawnQueue[1], game.drawn[1] = game.deck[2], 99, 99
    game.options[1], game.relics.small_savings = "apple", true
    assert(Equal(frozen, view), "展示副本不能泄漏顶层或实例标量写入")
    assert(view.deck[1] == view:Get(1) and view:_Value(Item(view, 2)) == value)
    assert(view._rollback == game._rollback, "回滚快照按约定只读共享，不递归复制")
end)

Test("Update没有物理包时不推进引擎、规则或独立时钟",function()
    local game=Fixture({"apple"})
    local simulation,probe=Harness(game)
    for _=1,3 do assert(not simulation:Update(100)) end
    Close(game.elapsed,0);Close(simulation:Clock().elapsed,0)
    assert(simulation.completedSteps==0 and not simulation:Busy())
    assert(probe.before==0 and probe.after==0 and probe.contactReads==0 and probe.effects==0)
end)

Test("原生Post零dt用Pre令牌完成该步，无令牌的零dt删除屏障不造时间",function()
    local game=Fixture({"apple"})
    local simulation,probe=Harness(game,{})
    simulation:AfterPhysics(0)
    Close(simulation:Clock().elapsed,0)
    assert(probe.after==0 and probe.contactReads==0 and not simulation:Busy())
    assert(simulation:BeforePhysics(.05))
    simulation:AfterPhysics(0)
    Close(simulation:Clock().elapsed,.05)
    assert(probe.before==1 and probe.after==1 and probe.contactReads==1)
    Drain(simulation,1);Close(game.elapsed,.05)
    -- Post令牌只消费一次，既不重复，也不能阻塞下一帧的原生Pre。
    simulation:AfterPhysics(0)
    assert(probe.after==1 and probe.contactReads==1 and not simulation:Busy())
    assert(simulation:BeforePhysics(.05))
    simulation:AfterPhysics(0)
    Drain(simulation,2)
    Close(simulation:Clock().elapsed,.1);Close(game.elapsed,.1)
    assert(probe.before==2 and probe.after==2 and probe.contactReads==2)
    CommitOrder(probe,2)
end)

Test("规则pending期间Before和After照常执行，UI保持步前状态",function()
    local game=Fixture({"glutton","apple"})
    local before=Copy(game)
    local simulation,probe=Harness(game,{pairs={{1,2}}},FrameBudget.New(4,function() return 0 end,1))
    assert(simulation:BeforePhysics(STEP));simulation:AfterPhysics(STEP)
    assert(not simulation:Update(0) and simulation.budget:Busy() and simulation.completedSteps==0)
    assert(probe.bound~=game and probe.bound==simulation.presentation and Equal(probe.bound,before))
    for _=1,3 do
        assert(simulation:BeforePhysics(STEP));simulation:AfterPhysics(STEP)
        assert(not simulation:Update(0) and simulation:Busy())
        assert(probe.remembers==0 and probe.syncs==0 and Equal(probe.bound,before))
    end
    assert(probe.before==4 and probe.after==4 and probe.contactReads==4)
    Close(simulation:Clock().elapsed,STEP*4)
    assert(Drain(simulation,4)>0)
    assert(Item(game,2).location=="discard");Close(Item(game,1).permBonus,1)
    Close(game.elapsed,STEP*4);Close(simulation.accumulator,0);CommitOrder(probe,4)
end)

Test("20fps三秒推进三秒物理时钟，即使规则worker持续积压",function()
    local game=Fixture({"apple","orange"})
    local simulation,probe=Harness(game,{},FrameBudget.New(4,function() return 0 end,1))
    for _=1,60 do simulation:Capture(.05,{});simulation:Update(.05) end
    Close(simulation:Clock().elapsed,3)
    assert(simulation:Clock().phase=="running" and game.elapsed<3 and simulation:Busy())
    assert(Drain(simulation,60)>0)
    Close(game.elapsed,3);Close(simulation:Clock().elapsed,3);CommitOrder(probe,60)
end)

Test("规则和分帧FIFO的事件、金额、RNG及生成合成状态逐包一致",function()
    local function Scene()
        local game=Fixture({"coin_1","coin_1","glutton","apple","fruit_tree","diner","orange"},
            {small_savings=true})
        Item(game,5).remaining,Item(game,5).treeBlessed=0,true
        return game
    end
    local direct,game=Scene(),Scene()
    local contacts=Input(game,{pairs={{1,2},{3,4},{6,7}},positions={
        [1]={x=0,y=1},[2]={x=.2,y=1},[3]={x=.5,y=2},[4]={x=.6,y=2},
        [5]={x=-.5,y=3},[6]={x=-.2,y=2},[7]={x=0,y=2}}})
    local expected={}
    for _=1,3 do expected[#expected+1]=DirectStep(direct,STEP,Copy(contacts)) end
    local simulation,probe=Harness(game,contacts,FrameBudget.New(4,function() return 0 end,3),true)
    for _=1,3 do simulation:Capture(STEP,contacts) end
    assert(not simulation:Update(100) and simulation:Busy())
    assert(Drain(simulation,3)>3 and simulation.budget.totalYields>3)
    assert(Equal(expected,probe.batches) and Equal(expected,probe.remembered))
    local flat={}
    for _,batch in ipairs(expected) do for _,event in ipairs(batch) do flat[#flat+1]=event end end
    assert(Equal(flat,probe.flat) and Equal(direct,game),"恢复不得改变日志或实际规则状态")
    assert(#Repair.Events(probe.flat,"merge")==1 and #Repair.Events(probe.flat,"spawn")>=1)
    assert(#Repair.Events(probe.flat,"consume",4)==1 and #Repair.Events(probe.flat,"consume",7)==1)
    Close(Item(game,3).permBonus,1);Close(game.roundScore,4)
    Identity(game);CommitOrder(probe,3)
end)

Test("表现跨帧期间物理继续，整批结束后才Remember和Sync",function()
    local game=Fixture({"diner","apple"})
    local simulation,probe=Harness(game,{})
    local entered,finished=false,false
    probe.onEffects=function(events)
        if entered then return end
        assert(#events>0 and probe.remembers==0 and probe.syncs==0)
        entered=true;coroutine.yield()
        assert(probe.before==1 and probe.after==1 and probe.remembers==0 and probe.syncs==0)
        finished=true
    end
    simulation:Capture(STEP,Input(game,{pairs={{1,2}}}))
    assert(not simulation:Update(0) and entered and not finished and simulation:Busy())
    assert(game.score==4 and Item(game,2).location=="discard")
    assert(probe.bound~=game and probe.bound.score==0 and #probe.bound:BottleItems()==2)
    assert(simulation:BeforePhysics(STEP));simulation:AfterPhysics(STEP)
    Drain(simulation,2)
    assert(finished and #Repair.Events(probe.flat,"consume",2)==1);CommitOrder(probe,2)
end)

Test("Capture冻结容器与位置行，Begin后End短碰不因新包覆盖而丢失",function()
    local direct,game=Fixture({"diner","apple"}),Fixture({"diner","apple"})
    local contacts=Input(game,{pairs={{1,2}},positions={[1]={x=.2,y=2},[2]={x=.4,y=2}}})
    local expected={DirectStep(direct,STEP,Copy(contacts)),DirectStep(direct,STEP,{})}
    local simulation,probe=Harness(game)
    simulation:Capture(STEP,contacts)
    contacts.pairs[1][1],contacts.pairs[1][2]=99,100
    contacts.positions[1].x,contacts.positions[2].y=100,100
    contacts.pairs,contacts.positions={},{}
    simulation:Capture(STEP,contacts);Drain(simulation,2)
    assert(Equal(expected,probe.batches) and Equal(direct,game))
    assert(#Repair.Events(probe.flat,"consume",2)==1 and game.score==4)
    local frozen,log=Copy(game),Copy(probe.log)
    for _=1,3 do simulation:Update(100) end
    assert(Equal(frozen,game) and Equal(log,probe.log),"相同包不能以零dt重试概率/收益")
    CommitOrder(probe,2)
end)

Test("同UID重建代际过滤旧接触和位置，新代际新包可正常触发",function()
    local game=Fixture({"diner","apple"})
    local simulation,probe=Harness(game)
    local contacts=Input(game,{pairs={{1,2}},bottom={[1]=true},
        positions={[1]={x=0,y=2},[2]={x=.2,y=2}}})
    simulation:Capture(STEP,contacts);probe.physics.bodies[1].generation=2
    Drain(simulation,1)
    assert(game.score==0 and Item(game,2).location=="bottle" and game._lastPositions[1]==nil)
    contacts.generations[1]=2
    simulation:Capture(STEP,contacts);Drain(simulation,2)
    assert(game.score==4 and Item(game,2).location=="discard")
    assert(#Repair.Events(probe.flat,"consume",2)==1);CommitOrder(probe,2)
end)

Test("真实飞盘回传清位置基线后，同代累计路程不重复发五米收益",function()
    local game=Fixture({"discus","apple"})
    local disc=Item(game,1)
    disc.discusOwnerUid,disc.discusState,disc.discusWait=2,"flying",0
    local simulation,probe=Harness(game)
    local first=Input(game,{positions={[1]={x=0,y=2},[2]={x=.4,y=2}},
        pathLengths={[1]=6,[2]=0},pathGeneration={[1]=1,[2]=2},flightArrived={[1]=true}})
    simulation:Capture(STEP,first);Drain(simulation,1)
    assert(#Repair.Events(probe.flat,"score",1)==1 and #Repair.Events(probe.flat,"teleport",1)==1)
    assert(game._lastPositions[1]==nil,"真实ReturnDiscus须继续排除传送的位置跳变")
    Close(disc.distance,1)
    local second=Input(game,{positions={[1]={x=.4,y=2},[2]={x=.4,y=2}},
        pathLengths={[1]=6.1,[2]=0},pathGeneration={[1]=1,[2]=2}})
    simulation:Capture(STEP,second);Drain(simulation,2)
    assert(#Repair.Events(probe.flat,"score",1)==1,"已消费的历史六米不能在回传后再领一次五米收益")
    Close(disc.distance,1.1)
    assert(disc.discusState=="owner_wait");CommitOrder(probe,2)
end)

Test("旧物理包尚未采入的新生实例不提前扣冷却，首次实际采入才推进",function()
    local game=Fixture({"apple"})
    local simulation,probe=Harness(game)
    local old=Input(game,{})
    for _=1,3 do simulation:Capture(.05,old) end
    local born=game:_Create("fruit_tree")
    game:_EnterBottle(born)
    born.remaining=1
    Drain(simulation,3)
    Close(game.elapsed,.15);Close(born.remaining,1)
    assert(#Repair.Events(probe.flat,"spawn")==0,"新生实例不能在入物理前提前产物")
    probe.physics.bodies[born.uid]={generation=2,kind=born.id}
    local fresh=Input(game,{})
    fresh.generations[born.uid]=2
    simulation:Capture(.05,fresh);Drain(simulation,4)
    Close(born.remaining,.95);Close(game.elapsed,.2);CommitOrder(probe,4)
end)

Test("未采入齿轮不提前消耗回放时间或开始标记，采入后按实际dt继续",function()
    local game=Fixture({"apple"})
    local gear=game:_Create("gear")
    game:_EnterBottle(gear)
    gear.remaining,gear.gearPlayback=4,.5
    game._physicalMembers={[1]="apple"}
    game:Step(.2,{positions={[1]={x=0,y=2}}})
    game._physicalMembers=nil
    Close(gear.remaining,4);Close(gear.gearPlayback,.5)
    assert(gear.gearBatch==nil,"历史包不能提前启动新齿轮的回放或标记")
    game._physicalMembers={[1]="apple",[gear.uid]="gear"}
    game:Step(.1,{positions={[1]={x=0,y=2},[gear.uid]={x=.4,y=2}}})
    game._physicalMembers=nil
    Close(gear.remaining,3.9);Close(gear.gearPlayback,.4)
end)

Test("未采入旧包保留转圈圈累计角游标，下一有效采样不重复累计历史",function()
    local game=Fixture({"apple"},{spin_reward=true})
    local item=Item(game,1)
    game._physicalMembers={[1]="apple"}
    game:Step(.01,{angularTravel={[1]=2}})
    Close(item.spinProgress,2);Close(item.spinTravel,2)
    game._physicalMembers={}
    local skipped=game:Step(.01,{})
    Close(item.spinProgress,2);Close(item.spinTravel,2)
    assert(#Repair.Events(skipped,"score",1)==0)
    game._physicalMembers={[1]="apple"}
    local fresh=game:Step(.01,{angularTravel={[1]=2.1}})
    game._physicalMembers=nil
    Close(item.spinProgress,2.1);Close(item.spinTravel,2.1)
    assert(#Repair.Events(fresh,"score",1)==0,"同一历史角路程不能再次参与三圈抽奖")
end)

Test("表现跨yield始终读取同包冻结姿态，不借用运动中的刚体或原始soft行",function()
    local game=Fixture({"diner","apple"})
    local simulation,probe=Harness(game)
    local contacts=Input(game,{pairs={{1,2}},positions={[1]={x=.2,y=2},[2]={x=.4,y=2}}})
    contacts.poses={[1]={x=.2,y=2,angle=.7,radius=.3,soft={{x=.1,y=2,angle=.4}}}}
    local entered,finished=false,false
    probe.onEffects=function(events,view)
        assert(#events>0 and view~=probe.physics and view.bodies[1].kind=="diner")
        local x,y,angle,radius=view:GetPose(1)
        Close(x,.2);Close(y,2);Close(angle,.7);Close(radius,.3)
        assert(view:GetSoftPose(1)[1].x==.1 and probe.remembers==0)
        entered=true;coroutine.yield()
        x,y,angle,radius=view:GetPose(1)
        Close(x,.2);Close(y,2);Close(angle,.7);Close(radius,.3)
        assert(view:GetSoftPose(1)[1].x==.1 and probe.remembers==0)
        finished=true
    end
    simulation:Capture(STEP,contacts);simulation:Update(0)
    assert(entered and not finished and simulation:Busy())
    contacts.poses[1].x,contacts.poses[1].soft[1].x=200,100
    probe.physics.bodies[1].node={position2D={x=300,y=300}}
    Drain(simulation,1)
    assert(finished);CommitOrder(probe,1)
end)

Test("每画面最多四逻辑包，Update零dt可清队列但不制造物理时间",function()
    local game=Fixture({"apple"})
    local simulation,probe=Harness(game)
    for _=1,13 do simulation:Capture(STEP,{}) end
    Close(simulation:Clock().elapsed,STEP*13)
    for frame=1,4 do
        local before=simulation.completedSteps
        assert(not simulation:Update(100))
        assert(simulation.completedSteps-before<=4 and not simulation.budget:Busy())
        assert(simulation.completedSteps==math.min(frame*4,13))
        assert(simulation:Busy()==(frame<4));Close(simulation:Clock().elapsed,STEP*13)
    end
    Close(game.elapsed,STEP*13);CommitOrder(probe,13)
end)

Test("running终点拆包，settle两秒封顶而不等待慢规则完成",function()
    local game=Fixture({"apple"})
    game.elapsed=game:Duration()-STEP
    local simulation,probe=Harness(game,{},FrameBudget.New(4,function() return 0 end,1))
    simulation:Capture(STEP*13,{})
    local clock=simulation:Clock()
    assert(clock.phase=="settle");Close(clock.elapsed,game:Duration());Close(clock.settleElapsed,STEP*12)
    simulation:Update(0)
    assert(simulation:Busy() and game.phase=="running")
    simulation:Capture(100,{})
    clock=simulation:Clock()
    Close(clock.elapsed,clock.duration);Close(clock.settleElapsed,Game.SETTLE_DELAY)
    assert(not simulation:PhysicsActive(),"物理截止不能等待规则worker")
    local stopped=Copy(clock)
    simulation:Capture(100,{})
    assert(Equal(stopped,simulation:Clock()))
    Drain(simulation,3)
    assert(game.phase=="reveal" and game.revealElapsed==0)
    Close(game.elapsed,game:Duration());Close(game.settleElapsed,Game.SETTLE_DELAY)
    assert(#Repair.Events(probe.flat,"score",1)==1,"最终结算只能一次")
    CommitOrder(probe,3)
end)

Test("最终结算跨帧停在Reveal，扣款与三选一仍由RevealStep推进",function()
    local function Scene()
        local game=Fixture({"apple","credit_card","banana","fruit_tree"})
        game.round,game.score,game.totalScore=5,100,100
        Item(game,3).bottleRounds=3
        game.phase,game.settleElapsed="settle",Game.SETTLE_DELAY-STEP
        return game
    end
    local direct,game=Scene(),Scene()
    local events,rng=direct:SettleStep(STEP,{}),game._rngState
    local simulation,probe=Harness(game,{},FrameBudget.New(4,function() return 0 end,1),true)
    simulation:Capture(1,{})
    assert(not simulation:Update(0) and simulation:Busy() and probe.bound.phase=="settle")
    assert(Drain(simulation,1)>2)
    assert(game.phase=="reveal" and game.revealElapsed==0 and #game.options==0)
    assert(game.stage==1 and game._rngState==rng and not game.pendingRelicDraft)
    assert(Equal(events,probe.flat) and Equal(direct,game))
    assert(Item(game,3).id=="rotten_banana");Close(Item(game,2).permBonus,-1)
    assert(#Repair.Events(probe.flat,"deduction")==0)
    local frozen=Copy(game)
    simulation:Capture(100,{});simulation:Update(100)
    assert(Equal(frozen,game) and simulation.completedSteps==1)
    assert(#game:RevealStep(100,true)==0 and #direct:RevealStep(100,true)==0)
    assert(Equal(game:RevealStep(0,false,true),direct:RevealStep(0,false,true)))
    assert(game.phase=="draft" and game.stage==2 and game.pendingRelicDraft and game.removals==1)
    assert(Equal(game:Snapshot(),direct:Snapshot()));CommitOrder(probe,1)
end)

Test("Dispose废弃worker与队列，旧回调不能复活旧局",function()
    local game=Fixture({"glutton","apple"})
    local budget=FrameBudget.New(4,function() return 0 end,1)
    local simulation,probe=Harness(game,{},budget)
    for _=1,3 do simulation:Capture(STEP,Input(game,{pairs={{1,2}}})) end
    simulation:Update(0);assert(simulation:Busy());simulation:Dispose()
    assert(simulation.disposed and not simulation:Busy() and not budget:Busy())
    local abandoned,log=Copy(game),Copy(probe.log)
    for _=1,4 do
        simulation:Capture(100,{});assert(not simulation:BeforePhysics(STEP))
        simulation:AfterPhysics(STEP);assert(not simulation:Update(100))
    end
    budget:BeginFrame();assert(budget:Resume());simulation:Dispose()
    assert(Equal(abandoned,game) and Equal(log,probe.log) and simulation.completedSteps==0)
    assert(probe.remembers==0 and probe.syncs==0 and probe.publishes==0 and probe.before==0 and probe.after==0)
    local fresh,freshProbe=Harness(Fixture({"apple"}))
    fresh:Capture(STEP,{});Drain(fresh,1)
    assert(Equal(abandoned,game));CommitOrder(freshProbe,1)
end)

Test("反馈publish仅在整批表现完成且Sync及解除展示隔离之后发布一次",function()
    local game=Fixture({"diner","apple"})
    local simulation,probe=Harness(game)
    local entered,finished=false,false
    probe.onEffects=function(events)
        assert(#events>0 and probe.syncs==0 and probe.publishes==0)
        entered=true;coroutine.yield()
        assert(probe.syncs==0 and probe.publishes==0)
        finished=true
    end
    simulation:Capture(STEP,Input(game,{pairs={{1,2}}}))
    simulation:Update(0)
    assert(entered and not finished and simulation:Busy() and probe.publishes==0)
    Drain(simulation,1)
    assert(finished and probe.publishes==1 and Equal(probe.published[1],probe.flat))
    local score,rng=game.score,game._rngState
    for _=1,3 do simulation:Update(100) end
    assert(probe.publishes==1 and game.score==score and game._rngState==rng)
    CommitOrder(probe,1)
end)

Test("表现中断后Dispose不能publish半批或在后续帧补播旧反馈",function()
    local game=Fixture({"diner","apple"})
    local simulation,probe=Harness(game)
    local entered,finished=false,false
    probe.onEffects=function()
        entered=true;coroutine.yield();finished=true
    end
    simulation:Capture(STEP,Input(game,{pairs={{1,2}}}))
    simulation:Update(0)
    assert(entered and not finished and simulation.budget:Busy() and game.score==4)
    local worker=assert(simulation.budget.worker)
    simulation:Dispose()
    for _=1,3 do simulation:Update(100) end
    assert(not coroutine.resume(worker) and not finished)
    assert(probe.effects==1 and probe.syncs==0 and probe.remembers==0 and probe.publishes==0)
    assert(#probe.published==0 and simulation.completedSteps==0)
end)

Test("暂停不Capture便不计时，ResetClock拒绝丢弃未处理包并可在空闲重置",function()
    local game=Fixture({"apple"})
    local simulation,probe=Harness(game)
    simulation:Capture(STEP,{})
    assert(not pcall(function() simulation:ResetClock() end),"重置不得静默删除未处理输入")
    Drain(simulation,1);simulation:ResetClock()
    for _=1,5 do simulation:Update(1) end
    Close(game.elapsed,STEP);Close(simulation:Clock().elapsed,STEP)
    simulation:Capture(0,{});simulation:Update(0)
    assert(simulation.completedSteps==1 and not simulation:Busy())
    simulation:Capture(STEP,{});Drain(simulation,2)
    Close(game.elapsed,STEP*2);CommitOrder(probe,2)
end)

Test("满瓶生成FIFO仍按原规则补位，合成先占位且永久产物不丢",function()
    local function Scene()
        local game=Fixture({"coin_1","coin_1","glutton","apple","apple"},{small_savings=true})
        for _=6,Items.Settings.bottleLimit do game:_EnterBottle(game:_Create("orange")) end
        local events={}
        for index,id in ipairs({"juice","apple_half","ball"}) do
            assert(game:_Spawn(id,events,false,{x=index*.1,y=4+index}).location=="queued")
        end
        assert(#Repair.Events(events,"spawn")==0 and #game.spawnQueue==3)
        local relics=Repair.Events(events,"relicTrigger")
        assert(#relics==1 and relics[1].id=="small_savings","成功排队生成仍发一次积少成多反馈")
        return game
    end
    local direct,game=Scene(),Scene()
    local queued,money=Copy(game.spawnQueue),game.score
    local contacts=Input(game,{pairs={{1,2},{3,4},{3,5}},positions={
        [1]={x=0,y=1},[2]={x=.2,y=1},[3]={x=.5,y=2},[4]={x=.6,y=2},[5]={x=.4,y=2}}})
    local expected=DirectStep(direct,STEP,Copy(contacts))
    local simulation,probe=Harness(game,contacts,FrameBudget.New(4,function() return 0 end,7),true)
    simulation:Capture(STEP,contacts);simulation:Update(0)
    assert(simulation:Busy() and Drain(simulation,1)>3)
    assert(Equal(expected,probe.flat) and Equal(direct,game))
    local spawns,merges=Repair.Events(probe.flat,"spawn"),Repair.Events(probe.flat,"merge")
    assert(#spawns==3 and #merges==1 and merges[1].id=="coin_2")
    for index,uid in ipairs(queued) do
        assert(spawns[index].uid==uid and Item(game,uid).location=="bottle")
        assert(not Item(game,uid).temporary and not Item(game,uid).generatedTemporary)
        Close(assert(spawns[index].x),index*.1);Close(assert(spawns[index].y),4+index)
    end
    assert(#game.spawnQueue==0 and not game._drainingQueue and #game:BottleItems()==Items.Settings.bottleLimit)
    Close(Item(game,3).permBonus,2);Close(game.score,money+1)
    local mergeAt,firstSpawn=0,0
    for index,event in ipairs(probe.flat) do
        if event.kind=="merge" then mergeAt=index end
        if event.kind=="spawn" and firstSpawn==0 then firstSpawn=index end
    end
    assert(mergeAt>0 and firstSpawn>mergeAt);Identity(game);CommitOrder(probe,1)
end)

Test("大牌库展示捕获分片时规则未变，外部物理回调仍推进",function()
    local game=Fixture({"apple","orange"})
    for _=1,300 do game:_Create("apple") end
    local before=Copy(game)
    local simulation,probe=Harness(game,{},FrameBudget.New(4,function() return 0 end,1))
    simulation:Capture(STEP,{})
    assert(not simulation:Update(0) and simulation:Busy() and simulation.presentation==nil)
    assert(Equal(before,game))
    for _=1,3 do
        assert(simulation:BeforePhysics(STEP));simulation:AfterPhysics(STEP)
        assert(not simulation:Update(0) and simulation:Busy() and Equal(before,game))
    end
    assert(probe.before==3 and probe.after==3 and probe.contactReads==3)
    Close(simulation:Clock().elapsed,STEP*4)
    assert(Drain(simulation,4)>3);Close(game.elapsed,STEP*4);CommitOrder(probe,4)
end)

---@return integer
function Tests.Run()
    local passed=0
    for _,case in ipairs(cases) do
        local ok,message=pcall(case.run)
        assert(ok,"Bottle.SimulationTests ["..case.name.."] "..tostring(message))
        passed=passed+1
    end
    return passed
end

return Tests
