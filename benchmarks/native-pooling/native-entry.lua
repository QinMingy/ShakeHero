-- Isolated benchmark: actual main, UI/NanoVG and native physics, no player IO.
local config=require("native-config")
local Storage=require("Bottle.Storage")
local TutorialState=require("Bottle.TutorialState")
local context={config=config,samples={},frames=0,storageSaves=0,started=false,nonFinite=0,functional={}}
_G.PoolingNative=context
local function IsolateStorage()
    Storage.tutorial,Storage.sequence=TutorialState.New(true),0
    Storage.Load=function() return nil end
    Storage.Save=function() context.storageSaves=context.storageSaves+1;return true end
    Storage.status="native benchmark memory-only"
    Storage.poolingIsolated=true
end
local Tests=require("Bottle.Tests")
local runTests=Tests.Run
Tests.Run=function(...) local result=runTests(...);IsolateStorage();return result end
-- Preallocate identical measurement rows in both variants before native Start.
for i=1,config.measured do
    context.samples[i]={frame=0,dt_ms=0,physics_cpu_ms=0,simulation_cpu_ms=0,physics_steps=0,
        wall_interval_ms=0,handle_update_cpu_ms=0,heap_kb=0,heap_delta_kb=0,heap_drop_kb=0,
        phase="",dragging=false,busy=false,backlog_ms=0,completed_steps=0,bodies=0,
        particles=0,score_queue=0,coins=0,coin_waiting=0,target_particles=0}
end
context.captured=0
local scratch={}
local cpu=function() return os.clock()*1000 end
local clockProbeOk,clockProbe=pcall(function() return time:GetTimeSinceEpochMs() end)
local wall=clockProbeOk and function() return time:GetTimeSinceEpochMs() end or cpu
context.wallClock=clockProbeOk and "time:GetTimeSinceEpochMs" or "os.clock()*1000 fallback; compare native log boundary timestamps"
context.wallClockProbe={ok=clockProbeOk,result=tostring(clockProbe)}
context.Clock=wall
local Physics=require("Bottle.Physics")
local step=Physics.Step
Physics.Step=function(self,...)
    local begin=cpu()
    local result=step(self,...)
    if context.sample then
        context.sample.physics_cpu_ms=context.sample.physics_cpu_ms+math.max(0,cpu()-begin)
        context.sample.physics_steps=context.sample.physics_steps+1
    end
    return result
end
local View=require("Bottle.View")
local newView=View.New
View.New=function(game,physics,actions)
    local view=newView(game,physics,actions)
    context.game,context.physics,context.view=game,physics,view
    return view
end
local Simulation=require("Bottle.Simulation")
local newSimulation,updateSimulation=Simulation.New,Simulation.Update
Simulation.New=function(...)
    local sim=newSimulation(...);context.sim=sim;return sim
end
Simulation.Update=function(self,...)
    local begin=cpu()
    local result=updateSimulation(self,...)
    if context.sample then context.sample.simulation_cpu_ms=context.sample.simulation_cpu_ms+math.max(0,cpu()-begin) end
    return result
end
require("main")
local originalStart,originalUpdate,originalStop=Start,HandleUpdate,Stop
local UI=require("urhox-libs/UI")
local MIXED={"ball","apple","orange","banana","coin_1","coin_2","gecko","cactus",
    "spinning_top","windmill","gear","roulette","calf","sheep","jelly","knife",
    "fruit_tree","cloud","chick","bodyguard"}
local totalX,totalY,driveTime=0,0,0
local inputEvent={pointerId=1,x=0,y=0,totalDeltaX=0,totalDeltaY=0,deltaX=0,deltaY=0}
local stressEvents={}
for i=1,8 do stressEvents[i]={kind="score",uid=i,value=1,x=(i-4.5)*.4,y=2.5+(i%3)*.3} end
for i,kind in ipairs({"value","permanent","size"}) do
    stressEvents[8+i]={kind="triggerReward",uid=i,value=kind=="size" and .1 or 1,
        rewardKind=kind,trigger=i==1 and "collision" or i==2 and "rotate" or "move",x=(i-2)*.7,y=4}
end
context.stressBatches=0
local finiteFields={"age","life","x","y","vx","vy","value","credit","delay","drop","flight"}
local function ScanArray(array)
    if not array then return end
    for _,record in ipairs(array) do
        for _,key in ipairs(finiteFields) do
            local value=record[key]
            if type(value)=="number" and (value~=value or value==math.huge or value==-math.huge) then
                context.nonFinite=context.nonFinite+1
            end
        end
    end
end
local functional
if config.functional then local ok,module=pcall(require,"native-functional");if ok then functional=module end end
function context.RecordFunctional(name,data) context.functional[name]=data end
function context.Drive(dt)
    local board=context.view.board
    if context.game.phase~="running" then return end
    local l=board:GetAbsoluteLayout()
    inputEvent.x,inputEvent.y=l.x+l.w/2,l.y+l.h/2
    if not context.dragging then board.shakePressId=1;context.dragging=board:OnPanStart(inputEvent)==true end
    if context.dragging then
        driveTime=driveTime+dt
        local x,y=32*math.sin(driveTime*7),25*math.sin(driveTime*9)
        inputEvent.totalDeltaX,inputEvent.totalDeltaY=x,y
        inputEvent.deltaX,inputEvent.deltaY=x-totalX,y-totalY
        board:OnPanMove(inputEvent);totalX,totalY=x,y
    end
end
function context.Advance(dt)
    context.Drive(dt)
    originalUpdate("Update",{GetFloat=function() return dt end})
    UI.Update(dt)
    if functional and functional.Scan then functional.Scan(context,dt) end
end
function Start()
    originalStart()
    assert(require("PublishConfig").PUBLISH_MODE==true,"retain production permissions")
    assert(Storage.poolingIsolated,"storage isolated after startup tests")
    local game,view,physics=context.game,context.view,context.physics
    assert(game and view and physics and context.sim,"real main constructors captured")
    game.deck,game.discard,game._instances,game.drawn={},{},{},{}
    game.spawnQueue,game._queueOrigins,game._lastPositions={},{},{}
    game._nextUid,game._rngState=1,777
    for i=1,config.count do
        local item=game:_Create(config.kind=="ball" and "ball" or MIXED[(i-1)%#MIXED+1])
        game:_EnterBottle(item);game.drawn[#game.drawn+1]=item.uid
    end
    physics:Sync(game:BottleItems(),true,777)
    view.startScreen.active=false;view.startScreen.root:Hide()
    view:Update(true);view.actions.start()
    assert(game.phase=="running" and context.sim.budget.budgetMs==4,"production round/default budget")
    context.initialBodies=#game:BottleItems()
    context.worldSettings={continuousPhysics=physics.world.continuousPhysics,
        velocityIterations=physics.world.velocityIterations,positionIterations=physics.world.positionIterations,
        subStepping=physics.world.subStepping}
    UI.Layout()
    local board=view.board;local l=board:GetAbsoluteLayout()
    board.shakePressId=1
    inputEvent.target=board;inputEvent.x=l.x+l.w/2;inputEvent.y=l.y+l.h/2
    context.dragging=board:OnPanStart(inputEvent)==true
    context.started=true
    context.previousHeap=collectgarbage("count")
end
function HandleUpdate(eventType,eventData)
    if not context.started then return originalUpdate(eventType,eventData) end
    context.frames=context.frames+1
    local dt=math.max(0,eventData:GetFloat("TimeStep"))
    local now=wall()
    local measured=context.frames>config.warmup and context.frames<=config.warmup+config.measured
    if context.frames==config.warmup+1 or context.frames==config.warmup+math.floor(config.measured/2)
        or context.frames==config.warmup+config.measured then
        print("POOLING_NATIVE_BOUNDARY "..context.frames.." "..now)
    end
    local sample=measured and context.samples[context.frames-config.warmup] or scratch
    sample.frame,sample.dt_ms=context.frames,dt*1000
    sample.physics_cpu_ms,sample.simulation_cpu_ms,sample.physics_steps=0,0,0
    sample.wall_interval_ms=context.previousWall and math.max(0,now-context.previousWall) or 0
    context.previousWall=now
    context.sample=sample
    local board=context.view.board
    if context.frames>=4 and context.game.phase=="running" then
        context.Drive(dt)
    end
    local begin=cpu()
    if config.fxStress and context.frames%12==0 and context.game.phase=="running" then
        -- Deliberate presentation stress fixture. Keep accounting consistent so
        -- real RoundScore/CoinPickup paths execute; do not claim natural rules.
        context.game.score=context.game.score+8
        context.game.totalScore=context.game.totalScore+8
        context.game.roundScore=context.game.roundScore+8
        board:ApplyEffects(stressEvents)
        context.stressBatches=context.stressBatches+1
    end
    originalUpdate(eventType,eventData)
    sample.handle_update_cpu_ms=math.max(0,cpu()-begin)
    context.sample=nil
    local heap=collectgarbage("count")
    sample.heap_kb=heap;sample.heap_delta_kb=heap-context.previousHeap
    sample.heap_drop_kb=math.max(0,context.previousHeap-heap);context.previousHeap=heap
    sample.phase,sample.dragging=context.game.phase,context.dragging==true
    sample.busy,sample.backlog_ms=context.sim:Busy(),context.sim.accumulator*1000
    sample.completed_steps=context.sim.completedSteps
    sample.bodies=#context.game:BottleItems()
    sample.particles,sample.score_queue=#board.particles,#board.scoreQueue
    sample.coins,sample.coin_waiting=#board.coinPickups.coins,#board.coinPickups.waiting
    sample.target_particles=context.view.targetBursts and #context.view.targetBursts or 0
    ScanArray(board.particles);ScanArray(board.scoreQueue);ScanArray(board.coinPickups.coins)
    if functional and functional.Scan then functional.Scan(context,dt) end
    if measured then context.captured=context.captured+1 end
end
function context.Finish()
    if context.saved or not context.started then return end
    context.saved=true
    local poolStats={}
    for _,name in ipairs({"Bottle.Board","Bottle.CoinPickup","Bottle.ConsumeFeedback","Bottle.ItemFeedback","Bottle.PopIn"}) do
        local module=require(name)
        if module.PoolStats then poolStats[name]=module.PoolStats() end
    end
    local trace=context.physics.motion.trace
    if trace and trace._pointPool then poolStats.trace=trace._pointPool:GetStats() end
    local flow=context.view.machineSkin.litScene.screenFlow
    if flow._trailPool then poolStats.trails=flow._trailPool:GetStats() end
    local meta={variant=config.variant,count=config.count,kind=config.kind,fxStress=config.fxStress,
        stressBatches=context.stressBatches,stressScoreEvents=context.stressBatches*8,
        stressTriggerEvents=context.stressBatches*3,warmup=config.warmup,measured=config.measured,
        captured=context.captured,initialBodies=context.initialBodies,defaultBudgetMs=context.sim.budget.budgetMs,
        publishMode=require("PublishConfig").PUBLISH_MODE,worldSettings=context.worldSettings,
        storageSaves=context.storageSaves,storageIsolated=Storage.poolingIsolated,
        nonFinite=context.nonFinite,completedSteps=context.sim.completedSteps,
        elapsed=context.game.elapsed,backlogMs=context.sim.accumulator*1000,
        frameBudgetYields=context.sim.budget.totalYields,poolStats=poolStats,functional=context.functional,
        wallClock=context.wallClock,wallClockProbe=context.wallClockProbe,
        cpuClock="os.clock()*1000 duration proxy; not independently verified CPU clock",gcMode="default natural GC; count only"}
    print("POOLING_NATIVE_META "..cjson.encode(meta))
    for i=1,context.captured do print("POOLING_NATIVE_SAMPLE "..cjson.encode(context.samples[i])) end
    print("POOLING_NATIVE_DONE "..context.captured)
end
function Stop()
    if context.started then context.Finish() end
    if originalStop then originalStop() end
end
