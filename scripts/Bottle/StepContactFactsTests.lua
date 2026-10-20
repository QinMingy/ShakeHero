-- 宏物理步真实Begin事实的纯Lua生命周期回归；不启动Scene、预览或读写存档。
local Facts=require("Bottle.StepContactFacts")
local FrameBudget=require("Bottle.FrameBudget")
local Tests={}
---@type {name:string,run:fun()}[]
local cases={}
---@param name string
---@param run fun()
local function Test(name,run) cases[#cases+1]={name=name,run=run} end

---@param uid number
---@return BottleBody
local function Body(uid) return {uid=uid} --[[@as BottleBody]] end

---@return BottlePhysicsContacts
local function Snapshot()
    return {pairs={},bottom={},top={},wall={},side={},positions={},angles={},
        rotateOffsets={},angularTravel={},flightArrived={},flightHits={},shakeStrength=0,
        members={},generations={},poses={},pathLengths={},pathGeneration={}}
end

---@param result BottlePhysicsContacts
---@return string
local function PairList(result)
    local keys={}
    for _,pair in ipairs(result.pairs) do keys[#keys+1]=pair[1]..":"..pair[2] end
    table.sort(keys)
    return table.concat(keys,",")
end

Test("窗口外和零dt屏障不记录且不从几何状态推测碰撞",function()
    local facts=Facts.New()
    local a,b=Body(1),Body(2)
    local bodies={[1]=a,[2]=b}
    assert(not facts:Pair(a,b) and not facts:Wall(a,"wall_right"))
    local result=Snapshot()
    result.positions[1]={x=2.4,y=0}
    facts:Merge(result,bodies)
    assert(#result.pairs==0 and not result.side[1] and not result.bottom[1])
    facts:BeginStep(bodies)
    facts:EndStep()
    -- Physics的零dt删除屏障不会BeginStep；关闭后迟到的回调也不得产生事实。
    assert(not facts:Pair(a,b) and not facts:Wall(a,"floor"))
    facts:Merge(result,bodies)
    assert(#result.pairs==0 and not result.wall[1])
end)

Test("本宏Begin后End保留一次物品对且下一宏自动清空",function()
    local facts=Facts.New()
    local a,b=Body(1),Body(2)
    local bodies={[1]=a,[2]=b}
    facts:BeginStep(bodies)
    assert(facts:Pair(b,a) and facts:Pair(a,b) and not facts:Pair(a,a))
    assert(facts:Wall(a,"wall_right"))
    facts:EndStep()
    -- End仅改变Physics的持续计数；这里用空持续快照代表同宏已分离。
    local result=Snapshot()
    facts:Merge(result,bodies)
    assert(PairList(result)=="1:2" and facts:HasPair(2,1,bodies) and result.side[1])
    facts:BeginStep(bodies)
    facts:EndStep()
    result=Snapshot()
    facts:Merge(result,bodies)
    assert(#result.pairs==0 and not facts:HasPair(1,2,bodies) and not result.wall[1] and not result.side[1])
end)

Test("真实floor top side事实准确合并且不串用分类",function()
    local facts=Facts.New()
    local a,b,c=Body(1),Body(2),Body(3)
    local bodies={[1]=a,[2]=b,[3]=c}
    facts:BeginStep(bodies)
    facts:Wall(a,"floor");facts:Wall(a,"floor")
    facts:Wall(b,"top")
    facts:Wall(c,"shoulder_left");facts:Wall(c,"neck_right")
    facts:EndStep()
    local result=Snapshot()
    facts:Merge(result,bodies)
    assert(result.bottom[1] and result.wall[1] and not result.top[1] and not result.side[1])
    assert(result.top[2] and result.wall[2] and not result.bottom[2] and not result.side[2])
    assert(result.side[3] and result.wall[3] and not result.bottom[3] and not result.top[3])
end)

Test("与持续接触取并集且重复Merge不消费或增加重复pair",function()
    local facts=Facts.New()
    local a,b,c=Body(1),Body(2),Body(3)
    local bodies={[1]=a,[2]=b,[3]=c}
    facts:BeginStep(bodies)
    facts:Pair(a,b);facts:Pair(b,c);facts:Wall(a,"floor")
    facts:EndStep()
    local result=Snapshot()
    result.pairs={{1,2},{1,3}}
    result.side[1],result.wall[1]=true,true
    facts:Merge(result,bodies)
    facts:Merge(result,bodies)
    assert(PairList(result)=="1:2,1:3,2:3")
    assert(result.bottom[1] and result.side[1] and result.wall[1])
    local another=Snapshot()
    facts:Merge(another,bodies)
    assert(PairList(another)=="1:2,2:3")
    facts:BeginStep(bodies)
    facts:EndStep()
    local persistent=Snapshot()
    persistent.pairs={{1,2}}
    persistent.side[1],persistent.wall[1]=true,true
    facts:Merge(persistent,bodies)
    assert(PairList(persistent)=="1:2" and persistent.side[1] and not persistent.bottom[1])
end)

Test("CJSON浮点整数UID与节点整数UID共用同一键且不接受非法小数",function()
    local facts=Facts.New()
    local a,b=Body(1.0),Body(2.0)
    local bodies={[1]=a,[2]=b}
    assert(math.type(a.uid)=="float" and math.type(1)=="integer")
    facts:BeginStep(bodies);assert(facts:Pair(a,b));facts:EndStep()
    local result=Snapshot()
    result.pairs={{1,2}}
    facts:Merge(result,bodies);facts:Merge(result,bodies)
    assert(#result.pairs==1 and result.pairs[1][1]==1 and result.pairs[1][2]==2)
    assert(facts:HasPair(1,2,bodies) and facts:HasPair(1.0,2.0,bodies)
        and facts:HasPair(2,1.0,bodies))
    local onlyFacts=Snapshot();facts:Merge(onlyFacts,bodies)
    assert(#onlyFacts.pairs==1 and math.type(onlyFacts.pairs[1][1])=="integer"
        and math.type(onlyFacts.pairs[1][2])=="integer")
    for _,invalid in ipairs({0,-1,1.5,2147483648,math.huge}) do
        assert(not pcall(function() facts:HasPair(invalid,2,bodies) end),
            "非法UID不得取整到有效接触："..tostring(invalid))
    end
end)

Test("同UID替换拒绝旧record回调并过滤旧fixture事实",function()
    local facts=Facts.New()
    local old,b=Body(1),Body(2)
    local bodies={[1]=old,[2]=b}
    facts:BeginStep(bodies)
    facts:Pair(old,b);facts:Wall(old,"floor")
    local replacement=Body(1)
    bodies[1]=replacement
    assert(not facts:Pair(old,b) and not facts:Wall(old,"top"))
    assert(not facts:HasPair(1,2,bodies))
    local result=Snapshot()
    facts:Merge(result,bodies)
    assert(#result.pairs==0 and not result.wall[1])
    -- 新fixture必须有自己的真实Begin，不能继承旧fixture的floor事实。
    assert(facts:Pair(replacement,b) and facts:Wall(replacement,"wall_right"))
    facts:EndStep()
    result=Snapshot()
    facts:Merge(result,bodies)
    assert(PairList(result)=="1:2" and result.side[1] and not result.bottom[1])
    bodies[1]=nil
    assert(not facts:HasPair(1,2,bodies))
    result=Snapshot();facts:Merge(result,bodies)
    assert(#result.pairs==0 and not result.wall[1])
end)

Test("Forget用于离场重建teleport且保留其他物品事实",function()
    local facts=Facts.New()
    local a,b,c=Body(1),Body(2),Body(3)
    local bodies={[1]=a,[2]=b,[3]=c}
    facts:BeginStep(bodies)
    facts:Pair(a,b);facts:Pair(b,c)
    facts:Wall(a,"floor");facts:Wall(c,"top")
    facts:Forget(1)
    assert(not facts:HasPair(1,2,bodies) and facts:HasPair(2,3,bodies))
    local result=Snapshot();facts:Merge(result,bodies)
    assert(PairList(result)=="2:3" and not result.wall[1] and result.top[3])
    -- 保留同一record的teleport也清事实；新的真实Begin可以再次登记。
    assert(facts:Wall(a,"wall_left") and facts:Pair(a,c))
    facts:EndStep()
    facts:Forget(3)
    result=Snapshot();facts:Merge(result,bodies)
    assert(#result.pairs==0 and result.side[1] and not result.top[3])
end)

Test("Clear关闭窗口并释放旧记录且reset后可正常重新开始",function()
    local facts=Facts.New()
    local a,b=Body(1),Body(2)
    local bodies={[1]=a,[2]=b}
    facts:BeginStep(bodies);facts:Pair(a,b);facts:Wall(a,"floor")
    facts:Clear()
    assert(not facts.active and facts.bodies==nil and next(facts.pairs)==nil and next(facts.walls)==nil)
    assert(not facts:Pair(a,b) and not facts:Wall(a,"floor"))
    local result=Snapshot();facts:Merge(result,bodies)
    assert(#result.pairs==0 and not result.wall[1])
    facts:BeginStep(bodies);assert(facts:Pair(a,b));facts:EndStep()
    assert(facts:HasPair(1,2,bodies))
end)

Test("快照不共享事实条目且不改positions angles或其他字段",function()
    local facts=Facts.New()
    local a,b=Body(1),Body(2)
    local bodies={[1]=a,[2]=b}
    facts:BeginStep(bodies);facts:Pair(a,b);facts:EndStep()
    local result=Snapshot()
    local positions,angles=result.positions,result.angles
    result.positions[1]={x=3,y=4};result.angles[1]=.75;result.shakeStrength=7
    facts:Merge(result,bodies)
    assert(result.positions==positions and result.angles==angles and result.positions[1].x==3
        and result.positions[1].y==4 and result.angles[1]==.75 and result.shakeStrength==7)
    result.pairs[1][1]=99
    local again=Snapshot();facts:Merge(again,bodies)
    assert(PairList(again)=="1:2" and facts:HasPair(1,2,bodies))
end)

Test("回调记录多个fixture时不执行任何协作式yield",function()
    local facts=Facts.New()
    local a,b=Body(1),Body(2)
    local bodies={[1]=a,[2]=b}
    local budget=FrameBudget.New(4,function() return 0 end,1)
    budget:Start(function()
        facts:BeginStep(bodies)
        for _=1,100 do facts:Pair(a,b);facts:Wall(a,"floor") end
        facts:EndStep()
    end)
    budget:BeginFrame()
    assert(budget:Resume() and budget.checkpoints==0 and budget.totalYields==0)
end)

Test("大事实快照可跨帧且取消读取不会消费事实",function()
    local facts=Facts.New()
    ---@type table<number,BottleBody>
    local bodies={}
    for uid=1,100 do bodies[uid]=Body(uid) end
    facts:BeginStep(bodies)
    for first=1,100 do
        facts:Wall(bodies[first],"floor")
        for second=first+1,100 do facts:Pair(bodies[first],bodies[second]) end
    end
    facts:EndStep()
    local actual=nil ---@type BottlePhysicsContacts?
    local budget=FrameBudget.New(4,function() return 0 end,1)
    budget:Start(function()
        local result=Snapshot();facts:Merge(result,bodies);actual=result
    end)
    budget:BeginFrame()
    assert(not budget:Resume() and actual==nil)
    budget:Cancel()
    assert(facts:HasPair(1,100,bodies))
    budget:Start(function()
        local result=Snapshot();facts:Merge(result,bodies);facts:Merge(result,bodies);actual=result
    end)
    local frames=0
    repeat
        frames=frames+1;assert(frames<1000)
        budget:BeginFrame()
        if not budget:Resume() then assert(actual==nil) end
    until not budget:Busy()
    local result=assert(actual)
    assert(frames>20 and #result.pairs==4950 and result.bottom[1] and result.bottom[100])
    assert(facts:HasPair(1,100,bodies))
end)

---@return integer
function Tests.Run()
    for _,case in ipairs(cases) do
        local ok,err=pcall(case.run)
        assert(ok,"Bottle.StepContactFactsTests ["..case.name.."] "..tostring(err))
    end
    return #cases
end

return Tests
