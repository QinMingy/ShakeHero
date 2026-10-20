-- 实际Physics.Contacts/ExpansionPhysics.Contacts的纯Lua容器夹具。
-- 不创建原生Scene/刚体，不模拟碰撞求解；只验证快照过滤、UID顺序和协作式续作契约。
local Physics = require("Bottle.Physics")
local Expansion = require("Bottle.ExpansionPhysics")
local FrameBudget = require("Bottle.FrameBudget")
local StepContactFacts = require("Bottle.StepContactFacts")
local Tests = {}

---@param count integer
---@return BottlePhysics
local function Fixture(count)
    local sim = setmetatable({bodies={},_pairs={},_bottom={},_top={},_wall={},_side={},
        expansion=Expansion.New(),stepContactFacts=StepContactFacts.New()}, {__index=Physics}) --[[@as BottlePhysics]]
    for uid = 1, count do
        local record = {uid=uid,node={position2D={x=uid*.01,y=uid*.02},rotation2D=uid*3},ghostLike=false}
        sim.bodies[uid] = record --[[@as BottleBody]]
        local state = sim.expansion:State(sim.bodies[uid])
        state.rotateOffset, state.angularTravel = uid*.1, uid*.2
        state.arrived, state.hit = uid%3==0, uid%2==0 and uid+1 or nil
        sim._bottom[uid], sim._top[uid] = uid%2, uid%3
        sim._wall[uid], sim._side[uid] = uid%4, uid%5
    end
    for a = 1, count do
        for b = a+1, count do
            sim._pairs[tostring(a)..":"..b] = {a=a,b=b,count=(a+b)%7==0 and 0 or 1}
        end
    end
    sim._pairs.missing = {a=1,b=count+1,count=1}
    sim._bottom[count+1], sim._top[count+1], sim._wall[count+1], sim._side[count+1] = 1,1,1,1
    sim.expansion.shakeStrength = 4.25
    return sim
end

---@param expected any
---@param actual any
local function Equal(expected, actual)
    assert(type(actual)==type(expected), "快照字段类型不同")
    if type(expected) ~= "table" then assert(expected==actual, "快照值不同"); return end
    for key, value in pairs(expected) do Equal(value,actual[key]) end
    for key in pairs(actual) do assert(expected[key]~=nil, "快照出现额外字段") end
end

---@param budget BottleFrameBudget
---@param pending (fun())?
---@return integer
local function Finish(budget, pending)
    local frames = 0
    repeat
        frames = frames + 1
        assert(frames<30000, "接触快照未取得进展")
        budget:BeginFrame()
        if not budget:Resume() and pending then pending() end
    until not budget:Busy()
    return frames
end

function Tests.Run()
    local sim = Fixture(100)
    local expected = sim:Contacts()
    local previousA, previousB, count = 0,0,0
    for _, pair in ipairs(expected.pairs) do
        local a,b = pair[1],pair[2]
        assert(a< b and (a>previousA or a==previousA and b>previousB), "UID字典序改变")
        previousA,previousB,count = a,b,count+1
    end
    assert(count>4000 and expected.positions[101]==nil and not expected.bottom[101]
        and not expected.top[101] and not expected.wall[101] and not expected.side[101])
    assert(expected.shakeStrength==4.25 and expected.flightArrived[3] and expected.flightHits[2]==3)
    local actual = nil ---@type BottlePhysicsContacts?
    local budget = FrameBudget.New(4,function() return 0 end,1)
    budget:Start(function() actual=sim:Contacts() end)
    local frames = Finish(budget,function() assert(actual==nil, "半个快照不得暴露给调用方") end)
    assert(frames>20, "大快照未通过多个安全边界分片")
    Equal(expected,assert(actual))

    -- 返回值不共享任何物品坐标/接触pair可变条目，修改快照不能污染物理事实。
    local first = expected.positions[1]
    first.x = -99
    expected.pairs[1][1] = -99
    assert(sim.bodies[1].node.position2D.x==.01 and sim._pairs["1:2"].a==1)

    actual = nil
    budget:Start(function() actual=sim:Contacts() end)
    budget:BeginFrame()
    assert(not budget:Resume() and actual==nil)
    budget:Cancel()
    budget:BeginFrame()
    assert(budget:Resume() and actual==nil and sim.bodies[1].node.position2D.x==.01)
    return 3
end

return Tests
