-- 表现事务纯Lua专项：验证私有批次在挂起/取消时不泄漏，不创建UI或读取存档。
local Stage = require("Bottle.BoardEventStage")
local FrameBudget = require("Bottle.FrameBudget")
local SoundState = require("Bottle.ItemSoundState")
local Records = require("Bottle.RecordPool")
local Tests = {}
local function Board()
    local board = {particles={}, pulses={}, residue={[1]={radius=1}}, scoreQueue={},
        feedbackPopMute={}, inflations={}, explodedUids={}, burstRings={}, bursts={},
        dashEmitters={}, dashTrails={}, presentUids={}, pops={}, ppu=50,
        coinsInFlight=0, shakeCoinsInFlight=0,
        itemFeedback={effects={},particles={},stars={},seen=setmetatable({},{__mode="k"}),serial=0},
        consumeFlash={flashes={},popups={},rebounds={},seen=setmetatable({},{__mode="k"})},
        coinPickups={coins={},waiting={},serial=0}}
    function board:GetAbsoluteLayout() return {x=0,y=0,w=370,h=600} end
    function board.coinPickups:Burst(amount, x, y, source, height)
        self.serial = self.serial + 1
        self.coins[#self.coins + 1] = {age=0, credit=amount, source=source,
            serial=self.serial, x=x, y=y, height=height}
    end
    function board.itemFeedback:ForgetStar(uid)
        self.stars[uid] = nil
        for index = #self.particles, 1, -1 do
            if self.particles[index].ownerUid == uid then table.remove(self.particles, index) end
        end
    end
    return board
end

---@param budget BottleFrameBudget
---@param paused (fun())?
local function Finish(budget, paused)
    local frames = 0
    repeat
        frames = frames + 1
        assert(frames < 2048, "表现事务没有取得进展")
        budget:BeginFrame()
        if not budget:Resume() and paused then paused() end
    until not budget:Busy()
    return frames
end

function Tests.Run()
    local board = Board()
    local coinWidget, oldPop = board.coinPickups, {uid=7}
    board.pops[1], board.popByUid = oldPop, {[7]=oldPop}
    local stagedSounds = SoundState.New()
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    budget:Start(function()
        Stage.Apply(board --[[@as any]], function(staged)
            local target = staged --[[@as any]] -- 只验证事务容器的最小替身，不冒充完整表现记录。
            target.particles[1] = {uid=0, value=1, life=.9, rewardKind="refresh"}
            target.burstRings[1] = {uid=1}
            target.residue[1].radius = 2
            target.itemFeedback.effects[1] = {action="grow"}
            target.consumeFlash.flashes[1] = {uid=1}
            target.coinPickups:Burst(3, 4, 5, "running", 600)
            FrameBudget.Checkpoint()
            stagedSounds:Collect({{kind="merge",uid=1}} --[[@as GameEvent[] ]])
        end)
    end)
    Finish(budget, function()
        assert(#board.burstRings==0 and board.residue[1].radius==1 and #board.particles==0)
        assert(#board.itemFeedback.effects==0 and #board.consumeFlash.flashes==0)
        assert(#board.coinPickups.coins==0 and board.coinPickups.serial==0)
        assert(#stagedSounds:Flush()==0, "音效待播发布后禁止再次yield，必须与表现同帧提交")
    end)
    assert(#board.burstRings==1 and board.residue[1].radius==2)
    assert(#board.particles==1 and board.particles[1].life==.9
        and board.particles[1].rewardKind=="refresh", "刷新提示只能随完整表现事务发布")
    assert(#board.itemFeedback.effects==1 and #board.consumeFlash.flashes==1)
    assert(board.coinPickups==coinWidget and #coinWidget.coins==1 and coinWidget.serial==1)
    assert(board.pops[1]==board.popByUid[7], "旧pop身份必须保持一致")
    assert(#stagedSounds:Flush()==1)

    local abandoned = Board()
    local prepared = false
    budget:Start(function()
        Stage.Apply(abandoned --[[@as any]], function(staged)
            local target = staged --[[@as any]]
            target.burstRings[1] = {uid=1}
            target.itemFeedback.seen[abandoned] = true
            target.coinPickups:Burst(4, 1, 2, "running", 600)
            target.shakeCoinsInFlight = target.shakeCoinsInFlight + 4
            prepared = true
            FrameBudget.Checkpoint()
        end)
    end)
    while not prepared do budget:BeginFrame(); assert(not budget:Resume()) end
    budget:Cancel()
    budget:BeginFrame(); assert(budget:Resume() and #abandoned.burstRings==0)
    assert(#abandoned.coinPickups.coins==0 and abandoned.shakeCoinsInFlight==0
        and next(abandoned.itemFeedback.seen)==nil, "取消不得泄漏新表现、收益计数或seen")

    local sounds = SoundState.New()
    local events = {{kind="merge",uid=1},{kind="merge",uid=2}} --[[@as GameEvent[] ]]
    budget:Start(function() sounds:Collect(events) end)
    budget:BeginFrame(); assert(not budget:Resume() and #sounds:Flush()==0)
    budget:BeginFrame(); assert(not budget:Resume() and #sounds:Flush()==0)
    budget:BeginFrame(); assert(budget:Resume())
    assert(#sounds:Flush()==1 and #sounds:Flush()==0, "本批声音只能在完整提交后播放一次")
    -- 活动画在挂起期间到期/新增，旧币抵达并继续创建新批次；提交只合入事件差量。
    local live = Board()
    local expired, survivor, during = {uid=1,age=0}, {uid=2,age=0}, {uid=3,age=.2}
    local fresh, freshFlash, freshEffect = {uid=4,age=0}, {uid=4,age=0}, {uid=4,age=0}
    live.particles, live.burstRings = {expired,survivor}, {{uid=1,age=0}}
    live.itemFeedback.effects, live.consumeFlash.flashes = {{age=0}}, {{age=0}}
    live.itemFeedback.stars[9] = {x=0,y=0,carry=0}
    live.itemFeedback.particles = {{ownerUid=9,age=0}}
    live.dashEmitters[9] = {remaining=.1}
    live.dashTrails = {{uid=9,age=0}}
    live.pulses[4], live.coinsInFlight, live.shakeCoinsInFlight = 0, 10, 20
    live.displayScore = 5
    live.coinPickups.coins = {{age=.5,credit=10}}
    local event = {}
    local coinObject, feedbackObject, flashObject = live.coinPickups, live.itemFeedback, live.consumeFlash
    local ready, advanced = false, false
    budget:Start(function()
        Stage.Apply(live --[[@as any]], function(staged)
            local target = staged --[[@as any]]
            target.particles[#target.particles+1] = fresh
            target.burstRings[#target.burstRings+1] = {uid=4,age=0}
            target.itemFeedback.effects[#target.itemFeedback.effects+1] = freshEffect
            target.consumeFlash.flashes[#target.consumeFlash.flashes+1] = freshFlash
            target.itemFeedback:ForgetStar(9)
            target.dashEmitters[9] = nil
            for index=#target.dashTrails,1,-1 do
                if target.dashTrails[index].uid==9 then table.remove(target.dashTrails,index) end
            end
            target.pulses[4] = 0
            target.residue[1].radius = 2
            target.itemFeedback.seen[event] = true
            target.consumeFlash.seen[event] = true
            target.coinsInFlight = target.coinsInFlight + 7
            target.shakeCoinsInFlight = target.shakeCoinsInFlight + 11
            target.itemFeedback.serial = target.itemFeedback.serial + 3
            target.coinPickups:Burst(7,1,2,"item",600)
            ready = true
            FrameBudget.Checkpoint()
        end)
    end)
    Finish(budget, function()
        if ready and not advanced then
            advanced = true
            -- 模拟Board.Update/星星采样/金币抵达；不修改任何私有stage引用。
            survivor.age = .75
            live.particles, live.burstRings = {survivor,during}, {}
            live.itemFeedback.effects, live.consumeFlash.flashes = {}, {}
            live.itemFeedback.stars[9] = {x=1,y=1,carry=0}
            live.itemFeedback.particles = {{ownerUid=9,age=0},{ownerUid=10,age=0}}
            live.dashTrails = {{uid=9,age=0},{uid=10,age=0}}
            live.pulses[4], live.residue[1].liveOnly = .25, 9
            live.coinPickups.coins, live.coinPickups.serial = {}, 4
            live.coinsInFlight, live.shakeCoinsInFlight, live.displayScore = 0, 0, 15
            live.itemFeedback.serial = live.itemFeedback.serial + 5
        end
        if ready then
            assert(fresh.age==0 and freshEffect.age==0 and freshFlash.age==0)
            assert(not live.itemFeedback.seen[event] and not live.consumeFlash.seen[event])
        end
    end)
    local committed = live.particles --[[@as table[] ]]
    assert(advanced and #committed==3 and committed[1]==survivor
        and committed[2]==during and committed[3]==fresh and survivor.age==.75,
        "过期旧粒子不复活，挂起期间新增与已推进的记录保留")
    assert(#live.burstRings==1 and live.burstRings[1].uid==4
        and #live.itemFeedback.effects==1 and live.itemFeedback.effects[1]==freshEffect
        and #live.consumeFlash.flashes==1 and live.consumeFlash.flashes[1]==freshFlash)
    assert(live.coinPickups==coinObject and live.itemFeedback==feedbackObject and live.consumeFlash==flashObject)
    assert(#coinObject.coins==1 and coinObject.coins[1].credit==7 and coinObject.coins[1].age==0
        and coinObject.coins[1].serial==5 and coinObject.serial==5, "旧金币抵达不得复活，串号使用最新值")
    assert(live.coinsInFlight==7 and live.shakeCoinsInFlight==11 and live.displayScore==15,
        "新批计数按差量合入，不覆盖已经抵达的收益")
    assert(live.pulses[4]==0 and live.residue[1].radius==2 and live.residue[1].liveOnly==9,
        "同值脉冲显式重置，残留仅合并实际修改")
    assert(live.itemFeedback.serial==8 and live.itemFeedback.stars[9]==nil
        and #live.itemFeedback.particles==1 and live.itemFeedback.particles[1].ownerUid==10)
    assert(#live.dashTrails==1 and live.dashTrails[1].uid==10)
    assert(live.itemFeedback.seen[event] and live.consumeFlash.seen[event]
        and getmetatable(live.itemFeedback.seen).__mode=="k"
        and getmetatable(live.consumeFlash.seen).__mode=="k", "seen事件身份与弱键语义保留")
    -- A live Update may expire an object while its old identity is still in the
    -- staged snapshot. Pins keep that record intact until the diff is published.
    local pooled, pool = Board(), Records.New(8)
    local removed, expired, kept = pool:Acquire(), pool:Acquire(), pool:Acquire()
    removed.uid, expired.uid, kept.uid = 1, 2, 3
    removed.age, expired.age, kept.age = 0, 0, 0
    pooled.particles = {removed, expired, kept}
    local liveArray = pooled.particles
    local private = nil ---@type table?
    local concurrent = nil ---@type table?
    local stagedReady, liveAdvanced = false, false
    local pinsBefore = Records.PinnedCount()
    local pooledBudget = FrameBudget.New(4, function() return 0 end, 1)
    pooledBudget:Start(function()
        Stage.Apply(pooled --[[@as any]], function(staged)
            local target = staged --[[@as any]]
            assert(not pool:Release(target.particles[1]), "staged removal cannot clear a borrowed live record")
            table.remove(target.particles, 1)
            assert(removed.uid == 1 and #pooled.particles == 3)
            private = pool:Acquire();private.uid, private.age = 5, 0
            target.particles[#target.particles + 1] = private
            target.residue[1].radius = 2
            assert(pooled.residue[1].radius == 1, "entry mutation escaped before commit")
            stagedReady = true
            FrameBudget.Checkpoint()
        end)
    end)
    Finish(pooledBudget, function()
        if stagedReady and not liveAdvanced then
            liveAdvanced = true
            assert(Records.PinnedCount() > pinsBefore and pool:Release(expired))
            assert(expired.uid == 2, "a pinned expiry must retain its identity fields")
            kept.age = .75
            -- Stable in-place Update compression removes expired, then creates a
            -- fresh live effect while the staged worker is suspended.
            liveArray[2], liveArray[3] = kept, nil
            concurrent = pool:Acquire();concurrent.uid, concurrent.age = 4, .2
            assert(concurrent ~= expired and concurrent ~= removed, "ABA reused a snapshot record")
            liveArray[#liveArray + 1] = concurrent
            pooled.residue[1].liveOnly = 9
        end
    end)
    assert(liveAdvanced and pooled.particles == liveArray and #liveArray == 3)
    assert(liveArray[1] == kept and liveArray[2] == concurrent and liveArray[3] == private)
    assert(kept.age == .75 and private.age == 0 and concurrent.age == .2)
    assert(next(removed) == nil and next(expired) == nil, "commit must recycle actual removals")
    assert(pool:GetStats().active == 3 and pool:GetStats().pending == 0)
    assert(pooled.residue[1].radius == 2 and pooled.residue[1].liveOnly == 9)
    assert(Records.PinnedCount() == pinsBefore)

    -- Closing a yielded worker releases only its private acquisitions. The same
    -- workspace must be clean when it is reused for the next complete event.
    local cancelledBoard, cancelPool = Board(), Records.New(8)
    local original = cancelPool:Acquire();original.uid = 7
    cancelledBoard.particles[1] = original
    local cancelArray = cancelledBoard.particles
    local abandonedRecord = nil ---@type table?
    local cancelReady = false
    pooledBudget:Start(function()
        Stage.Apply(cancelledBoard --[[@as any]], function(staged)
            local target = staged --[[@as any]]
            assert(not Records.ReleaseRecord(target.particles[1]))
            table.remove(target.particles, 1)
            abandonedRecord = cancelPool:Acquire();abandonedRecord.uid = 99
            target.particles[#target.particles + 1] = abandonedRecord
            target.pulses[7], target.residue[1].radius = 123, 77
            target.itemFeedback.seen[cancelledBoard] = true
            target.coinsInFlight = target.coinsInFlight + 11
            cancelReady = true
            FrameBudget.Checkpoint()
        end)
    end)
    while not cancelReady do pooledBudget:BeginFrame();assert(not pooledBudget:Resume()) end
    assert(Records.PinnedCount() > pinsBefore)
    pooledBudget:Cancel()
    assert(Records.PinnedCount() == pinsBefore and next(assert(abandonedRecord)) == nil)
    assert(cancelPool:GetStats().active == 1 and cancelPool:GetStats().pending == 0)
    assert(cancelledBoard.particles == cancelArray and #cancelArray == 1 and cancelArray[1] == original)
    assert(original.uid == 7 and cancelledBoard.pulses[7] == nil and cancelledBoard.residue[1].radius == 1)
    assert(cancelledBoard.coinsInFlight == 0 and next(cancelledBoard.itemFeedback.seen) == nil)
    Stage.Apply(cancelledBoard --[[@as any]], function(staged)
        local target = staged --[[@as any]]
        local nextRecord = cancelPool:Acquire();nextRecord.uid = 8
        target.particles[#target.particles + 1] = nextRecord
        target.pulses[7], target.residue[1].liveOnly = 0, 11
    end)
    assert(cancelledBoard.particles == cancelArray and #cancelArray == 2 and cancelArray[2].uid == 8)
    assert(original.uid == 7 and cancelledBoard.pulses[7] == 0 and cancelledBoard.residue[1].radius == 1)
    assert(cancelledBoard.residue[1].liveOnly == 11 and Records.PinnedCount() == pinsBefore)
    return 6
end
return Tests
