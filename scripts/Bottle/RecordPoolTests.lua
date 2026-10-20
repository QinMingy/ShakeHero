local Records = require("Bottle.RecordPool")
local FrameBudget = require("Bottle.FrameBudget")
local Tests = {}

function Tests.Run()
    local pool = Records.New(2)
    local first = pool:Acquire()
    first.uid, first.payload = 7, {x = 1}
    assert(pool:Release(first) and not pool:Release(first))
    local reused = pool:Acquire()
    assert(first == reused and next(reused) == nil)
    assert(not pool:Release({uid = 4}))
    local a, b = pool:Acquire(), pool:Acquire()
    pool:Release(reused);pool:Release(a);pool:Release(b)
    local stats = pool:GetStats()
    assert(stats.free == 2 and stats.active == 0 and stats.created == 3 and stats.reused == 1)

    local borrowed = pool:Acquire()
    borrowed.uid = 9
    local guard = Records.Pin()
    guard:BorrowDeep({borrowed})
    assert(not pool:Release(borrowed), "staged deletion cannot retire a live borrowed object")
    local liveRelease = coroutine.create(function() assert(pool:Release(borrowed)) end)
    assert(coroutine.resume(liveRelease))
    assert(borrowed.uid == 9 and pool:GetStats().pending == 1)
    local distinct = pool:Acquire()
    assert(distinct ~= borrowed, "pinned snapshot must not see an ABA reuse")
    guard:Commit();guard:KeepDeep({distinct});guard:Close()
    assert(next(borrowed) == nil and pool:GetStats().pending == 0)
    pool:Release(distinct)

    local kept, discarded
    do
        local scope <close> = Records.Pin()
        kept, discarded = pool:Acquire(), pool:Acquire()
        kept.name, discarded.name = "published", "private"
        scope:Commit();scope:KeepDeep({kept})
    end
    assert(kept.name == "published" and next(discarded) == nil)
    pool:Release(kept)

    local budget = FrameBudget.New(4, function() return 0 end, 1)
    local abandoned
    budget:Start(function()
        local scope <close> = Records.Pin()
        abandoned = pool:Acquire();abandoned.uid = 99
        FrameBudget.Checkpoint()
        scope:Commit();scope:KeepDeep(abandoned)
    end)
    budget:BeginFrame();assert(not budget:Resume() and Records.PinnedCount() == 1)
    budget:Cancel()
    assert(Records.PinnedCount() == 0 and next(abandoned) == nil,
        "cancelling a yielded transaction must unpin and recycle private records")

    local childPool = Records.New(2)
    local parent, child = pool:Acquire(), childPool:Acquire()
    parent.parts, child.x = {child}, 2
    assert(Records.ReleaseRecord(parent))
    assert(childPool:GetStats().active == 0 and next(child) == nil)
    local baseline = pool:GetStats().created
    for _ = 1, 1000 do
        local value = pool:Acquire();value.age = .5;pool:Release(value)
    end
    assert(pool:GetStats().created == baseline, "warmed pool should stop creating records")
    local shared
    do
        local scope <close> = Records.Pin()
        local private = pool:Acquire()
        shared = childPool:Acquire();shared.uid = 42
        private.child = shared
        scope:Commit();scope:KeepDeep({shared})
    end
    assert(shared.uid == 42, "discarding an unpublished parent must preserve its published child")
    childPool:Release(shared)
    local nestedBorrow = pool:Acquire();nestedBorrow.uid = 81
    do
        local outer <close> = Records.Pin()
        outer:BorrowDeep(nestedBorrow)
        do
            local inner <close> = Records.Pin()
            inner:Commit()
            assert(Records.IsBorrowed(nestedBorrow) and not pool:Release(nestedBorrow),
                "an inner commit must not retire an outer transaction's borrowed record")
        end
        assert(nestedBorrow.uid == 81)
        outer:Commit();outer:KeepDeep(nestedBorrow)
    end
    assert(pool:Release(nestedBorrow) and Records.PinnedCount() == 0)
    return 8
end

return Tests
