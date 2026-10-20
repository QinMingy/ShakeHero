-- Functional-only checks around actual main/Board/Box2D. Called after perf samples freeze.
-- Never opens UI, changes service config, or accesses a player save file.
local Functional = {}

local function finite(value)
    return type(value)=="number" and not tostring(value):lower():find("nan",1,true) and math.abs(value)<math.huge
end
local function numeric(value,label)
    assert(finite(value),label.." must be finite; got "..tostring(value))
end
local function equal(actual,expected,label)
    assert(math.abs(actual-expected)<1e-6,(label or "amount").." "..actual.." ~= "..expected)
end
local function contains(array,record)
    for _,value in ipairs(array)do if value==record then return true end end
    return false
end
local function state(context)
    if not context.functionalState then
        context.functionalState={scans=0,records=0,phases={},runningPopup=false,runningCoin=false,
            performanceRunningPopup=false,performanceRunningCoin=false,errors={},functionalMode=false}
    end
    return context.functionalState
end

local function checkPopup(p,queued)
    numeric(p.uid,"popup.uid");assert(p.uid>=0 and p.uid%1==0,"popup UID must be a nonnegative integer")
    numeric(p.value,"popup.value");numeric(p.x,"popup.x");numeric(p.y,"popup.y");numeric(p.age,"popup.age")
    assert(p.age>=0,"popup age must not be negative")
    if not queued then assert(p.age<=(p.life or 2)+1e-6,"expired popup remains active") end
end
local function coins(widget)
    local running,other=0,0
    for _,coin in ipairs(widget.coins)do
        numeric(coin.age,"coin.age");numeric(coin.credit,"coin.credit");numeric(coin.x,"coin.x");numeric(coin.y,"coin.y")
        numeric(coin.vx,"coin.vx");numeric(coin.delay,"coin.delay");numeric(coin.drop,"coin.drop");numeric(coin.flight,"coin.flight")
        numeric(coin.index,"coin.index")
        assert(coin.index>=1 and coin.index%1==0 and coin.credit>=0,"invalid coin identity/credit")
        assert(coin.age>=0 and coin.age<coin.delay+coin.drop+coin.flight+1e-6,"expired coin remains active")
        if coin.source=="running" then running=running+coin.credit else other=other+coin.credit end
    end
    for _,batch in ipairs(widget.waiting)do
        numeric(batch.amount,"coin batch.amount");numeric(batch.x,"coin batch.x");numeric(batch.y,"coin batch.y")
        assert(batch.amount>0,"queued coin amount must be positive")
        if batch.source=="running" then running=running+batch.amount else other=other+batch.amount end
    end
    return running,other
end

-- Entry calls this outside its timed main/physics section. No per-record result allocation.
function Functional.Scan(context,dt)
    local f=state(context)
    if f.error or not context.started or not context.view or not context.game then return not f.error end
    local ok,message=pcall(function()
        local board,game=context.view.board,context.game
        f.scans=f.scans+1;f.phases[game.phase]=true
        if f.initialScore==nil then
            f.initialScore=game._rollback and game._rollback.score or game.score-game.roundScore
            f.initialRound=game.round
        end
        numeric(game.score,"game.score");numeric(game.roundScore,"game.roundScore")
        for _,popup in ipairs(board.particles)do
            checkPopup(popup,false);f.records=f.records+1
            if not context.visualFixture and board.game.phase=="running" and popup.value>0 and popup.rewardKind==nil then
                f.runningPopup=true
                if not f.functionalMode then f.performanceRunningPopup=true end
            end
        end
        for _,popup in ipairs(board.scoreQueue)do checkPopup(popup,true);f.records=f.records+1 end
        local running,other=coins(board.coinPickups)
        local reelRunning,reels=coins(board.reelCoins)
        numeric(board.shakeCoinsInFlight,"shakeCoinsInFlight");numeric(board.coinsInFlight,"coinsInFlight")
        numeric(board.reelCoinsInFlight,"reelCoinsInFlight")
        equal(running,board.shakeCoinsInFlight,"running coin credit conservation")
        equal(other,board.coinsInFlight,"item/transfer coin credit conservation")
        equal(reelRunning+reels,board.reelCoinsInFlight,"reel coin credit conservation")
        if not context.visualFixture and board.game.phase=="running" and running>0 then
            f.runningCoin=true
            if not f.functionalMode then f.performanceRunningCoin=true end
        end
        if dt then numeric(dt,"scan.dt") end
    end)
    if not ok then f.error=tostring(message) end
    return ok
end

local function report(context,name,fn)
    local ok,result=pcall(fn)
    local data=ok and (result or {}) or {error=tostring(result)}
    data.passed=ok
    context.RecordFunctional(name,data)
    return ok,data
end

local function finishRound(context)
    local f=state(context);f.functionalMode=true
    assert(type(context.Advance)=="function","entry must provide actual main + UI Advance(dt)")
    local board,game,sim=context.view.board,context.game,context.sim
    local steps=0
    -- Advance does the same real gesture/main/UI path, but no performance sample is appended.
    while steps<1800 do
        context.Advance(1/60);steps=steps+1
        Functional.Scan(context,1/60)
        assert(not f.error,f.error)
        if game.phase~="running" and game.phase~="settle" and game.phase~="reveal"
            and not sim:Busy() and not board:CoinPickupsBusy()
            and #board.particles==0 and #board.scoreQueue==0
            and #board.bursts==0 and #board.pops==0
            and #board.itemFeedback.effects==0 and #board.itemFeedback.particles==0
            and #board.consumeFlash.flashes==0 and #board.consumeFlash.popups==0 then break end
    end
    assert(steps<1800,"actual round/presentation did not drain within 30 simulated seconds")
    assert(f.phases.running and f.phases.settle and f.phases.reveal,"real round must traverse running, settle and reveal")
    assert(not board.coinPickups:Busy() and not board.reelCoins:Busy(),"coin queues must drain")
    equal(board.shakeCoinsInFlight,0,"drained running credits")
    equal(board.coinsInFlight,0,"drained item credits")
    equal(board.reelCoinsInFlight,0,"drained reel credits")
    equal(board:DisplayedBalance(),game.score,"final displayed/rules balance")
    local ruleBalanceChecked=false
    if f.initialRound%5~=0 then
        equal(game.score,f.initialScore+game.lastRoundScore,"complete round score conservation")
        ruleBalanceChecked=true
    end
    return {virtualStepsAfterPerformance=steps,finalPhase=game.phase,initialScore=f.initialScore,
        finalScore=game.score,finalDisplayedBalance=board:DisplayedBalance(),
        expectedFinalScore=ruleBalanceChecked and f.initialScore+game.lastRoundScore or nil,
        drainedRunningCredits=board.shakeCoinsInFlight,drainedItemCredits=board.coinsInFlight,
        drainedReelCredits=board.reelCoinsInFlight,
        lastRoundScore=game.lastRoundScore,finiteScans=f.scans,validatedPopupRecords=f.records,
        runningPopup=f.runningPopup,runningCoin=f.runningCoin,ruleBalanceChecked=ruleBalanceChecked,
        performanceRunningPopup=f.performanceRunningPopup,performanceRunningCoin=f.performanceRunningCoin,
        noPlayerStorageAccess=true}
end

-- Explicit presentation fixture, after measured/natural play has finished. These
-- legal score event payloads exercise actual Effects/Stage/Update; they are not
-- reported as rewards generated by the natural shaking rules.
local function scoreProbe(context)
    local board,game=context.view.board,context.game
    assert(not context.sim:Busy(),"score fixture requires a committed real simulation")
    assert(board.game==game,"score fixture must use the actual committed game")
    local before={phase=game.phase,score=game.score,roundScore=game.roundScore,rollback=game._rollback,
        pending=board.simulationPending,displayScore=board.displayScore}
    local values={3,5,11}
    local expected=19
    local ok,result=pcall(function()
        board:ResetEffects();board:ResetPopState()
        context.visualFixture=true
        game.phase,game.roundScore,game.score="running",expected,before.score+expected
        game._rollback={score=before.score}
        board.simulationPending=true
        board:Effects({{kind="score",uid=1,value=values[1],x=-.2,y=1.8,trigger="native-functional"},
            {kind="score",uid=2,value=values[2],x=0,y=2,trigger="native-functional"},
            {kind="score",uid=3,value=values[3],x=.2,y=2.2,trigger="native-functional"}})
        board.simulationPending=false
        assert(#board.particles==3,"score fixture did not create three actual popups")
        for index,popup in ipairs(board.particles)do
            equal(popup.value,values[index],"published score event order")
            equal(popup.age,0,"published popup initial age")
        end
        equal(board.shakeCoinsInFlight,expected,"score fixture launched credit")
        local initialCoins=#board.coinPickups.coins
        assert(initialCoins>0,"score fixture did not launch actual coins")
        assert(Functional.Scan(context,0),state(context).error)
        local steps=0
        repeat
            board:Update(1/60);steps=steps+1
            assert(Functional.Scan(context,1/60),state(context).error)
        until (#board.particles==0 and not board.coinPickups:Busy()) or steps>=240
        assert(steps<240,"score fixture popups/coins did not expire")
        equal(board.shakeCoinsInFlight,0,"fixture drained credit")
        equal(board.roundScore.shakeTotal,expected,"fixture coins credited exactly once")
        equal(game.score,before.score+expected,"presentation must preserve the fixture rule balance")
        return {injectedFixture=true,naturalRuleReward=false,afterMeasuredSamples=true,
            eventCount=3,eventTotal=expected,initialCoinCount=initialCoins,virtualSteps=steps,
            allPopupsExpired=true,allCoinsArrived=true,credited=board.roundScore.shakeTotal,
            actualEffects=true,actualStage=true,actualBoardUpdate=true,memoryOnly=true}
    end)
    context.visualFixture=false
    game.phase,game.score,game.roundScore,game._rollback=before.phase,before.score,before.roundScore,before.rollback
    board.simulationPending=before.pending
    board:ResetEffects();board:ResetPopState();board.displayScore=before.displayScore
    if not ok then error(result,0) end
    return result
end

local function stageProbe(context,cancel)
    local FrameBudget=require("Bottle.FrameBudget")
    local Stage=require("Bottle.BoardEventStage")
    local board=context.view.board
    assert(not context.sim:Busy(),"actual simulation must commit before independent stage probe")
    local hasRecords,Records=pcall(require,"Bottle.RecordPool")
    hasRecords=hasRecords and type(board.PoolStats)=="function" and type(Records.PinnedCount)=="function"
    local pinsBefore=hasRecords and Records.PinnedCount() or 0
    board:ResetEffects();board:ResetPopState()
    board:AddRefreshPopup(0,0,2)
    local old=assert(board.particles[1])
    local wasPending=board.simulationPending
    board.simulationPending=true
    local budget=FrameBudget.New(1000000,function()return 0 end,1)
    local created,secondCreated
    local ok,result=pcall(function()
        budget:Start(function()
            Stage.Apply(board,function(staged)
                staged:AddRefreshPopup(0,.1,2)
                created=staged.particles[#staged.particles]
                FrameBudget.Checkpoint()
                if not cancel then
                    staged:AddRefreshPopup(0,.2,2)
                    secondCreated=staged.particles[#staged.particles]
                    FrameBudget.Checkpoint()
                end
            end)
        end)
        local slices=0
        repeat budget:BeginFrame();budget:Resume();slices=slices+1 until created or not budget:Busy() or slices>=512
        assert(created and budget:Busy(),"real Stage must suspend after allocating an unpublished popup")
        if hasRecords then assert(Records.PinnedCount()>0,"real Stage guard must pin records across its yield") end
        assert(not contains(board.particles,created),"uncommitted popup must remain hidden")
        board:Update(.05)
        assert(old.age>=.049 and contains(board.particles,old),"old popup must continue aging while Stage is pending")
        local age=old.age
        if cancel then
            budget:Cancel()
            assert(not budget:Busy() and #board.particles==1 and board.particles[1]==old,"cancel published staged work")
            if hasRecords then
                assert(Records.PinnedCount()==0,"cancel left pinned records")
                assert(next(created)==nil,"cancel did not return the unpublished pooled popup")
            end
        else
            budget.maxCheckpoints=4096
            repeat budget:BeginFrame();budget:Resume();slices=slices+1 until not budget:Busy() or slices>=1024
            assert(not budget:Busy(),"actual Stage commit did not complete")
            assert(#board.particles==3 and board.particles[1]==old and board.particles[2]==created
                and board.particles[3]==secondCreated,"commit changed live popup order")
            equal(old.age,age,"commit restored an older animation age")
            equal(created.age,0,"new popup starts only at commit")
            if hasRecords then assert(Records.PinnedCount()==0,"commit left pinned records") end
        end
        board:Update(1)
        assert(#board.particles==0,"probe popup lifetime did not expire")
        return {actualStage=true,maxCheckpoints=1,slices=slices,oldPopupAgeDuringPending=age,
            cancelled=cancel,poolCapabilityPresent=hasRecords,pinnedCount=hasRecords and Records.PinnedCount() or 0,
            pinsBefore=pinsBefore,pinsAfter=hasRecords and Records.PinnedCount() or 0,
            pinAssertionsSkipped=not hasRecords,commitOrderChecked=not cancel}
    end)
    -- Always close a pending Lua5.4 guard, including a failed assertion.
    budget:Cancel();board.simulationPending=wasPending
    board:ResetEffects();board:ResetPopState()
    if not ok then
        error(tostring(result).." [pinsBefore="..pinsBefore..", pinsAfter="
            ..(hasRecords and Records.PinnedCount() or 0).."]",0)
    end
    return result
end

function Functional.Run(context)
    local results={}
    local ok=report(context,"actual_round_popups_coins_drain",function()return finishRound(context)end)
    results.round=ok
    if ok then
        results.score=report(context,"actual_score_fixture_lifecycle",function()return scoreProbe(context)end)
        results.cancel=report(context,"actual_stage_cancel_pin",function()return stageProbe(context,true)end)
        results.commit=report(context,"actual_stage_commit_order",function()return stageProbe(context,false)end)
    else results.score=false;results.cancel=false;results.commit=false end
    return results.round and results.score and results.cancel and results.commit,results
end

return Functional
