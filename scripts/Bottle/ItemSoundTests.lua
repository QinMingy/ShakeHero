-- 验证密集真实语义反馈不会变回全场碰撞声，也不会把被丢弃音效排队到后续帧。
local State = require("Bottle.ItemSoundState")
local T = {}
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end

---@param action string
---@return GameEvent
local function Event(action)
    if action == "merge" then return {kind="merge",uid=1,id="coin_2"} end
    if action == "eat" then
        return {kind="consume",uid=2,id="apple",reason="consume",consumerId="pig"}
    end
    if action == "killer" then
        return {kind="consume",uid=2,id="student",reason="eliminate",consumerId="killer"}
    end
    return {kind="itemFeedback",action=action,uid=1,value=-1,count=1} --[[@as GameEvent]]
end

Test("只接受成功特殊事件，普通接触与金币跳字静音", function()
    for _, event in ipairs({{kind="score",uid=1,value=4}, {kind="triggerReward",uid=1,trigger="collision"},
        {kind="spawn",uid=1,id="apple"}, {kind="buff",uid=1,value=1},
        {kind="consume",uid=1,consumerId="police",reason="eliminate"},
        {kind="consume",uid=1,consumerId="killer",reason="consume"}}) do
        assert(State.Action(event --[[@as GameEvent]]) == nil)
    end
    assert(State.Action(Event("killer")) == "killer")
    assert(State.Action(Event("merge")) == "merge")
end)

Test("吞食补默认咀嚼声，小牛保留已有专属牛叫", function()
    for _, id in ipairs({"glutton","diner","pig","monkey","sheep","rabbit","chick","gecko"}) do
        local event = Event("eat")
        event.consumerId = id
        assert(State.Action(event) == "eat", id.."吞食应有默认声")
    end
    local calf = Event("eat")
    calf.consumerId = "calf"
    assert(State.Action(calf) == nil, "已有消费牛叫不叠加默认声")
    for _, id in ipairs({"trash_can","soul_stone","cactus","chicken_keeper","sweater","chef"}) do
        local event = Event("eat")
        event.consumerId = id
        assert(State.Action(event) == nil, "回收、吸收和收取不误播咀嚼："..id)
    end
    for _, reason in ipairs({"self","eliminate","burst","merge_checked","remove","exhausted"}) do
        local event = Event("eat")
        event.reason = reason
        assert(State.Action(event) == nil)
    end
    assert(State.Action({kind="itemFeedback",action="eat",uid=1} --[[@as GameEvent]]) == nil,
        "咀嚼只接受成功消费，不能靠表现事件伪造")
end)

Test("所有真实合成路径沿用现有默认声，材料消耗不重复发声", function()
    local fixture = require("Bottle.RepairTests").Fixture
    local merge = require("Bottle.Effects").Merge
    for _, row in ipairs({
        {"slipper_left","slipper_right","fruit_ninja"},
        {"egg","tomato","tomato_egg"},
        {"coin_1","coin_1","coin_2"},
        {"coin_64","coin_64","coin_128"},
        {"wool","wool","wool"},
        {"teacher","teacher","teacher"},
    }) do
        local game = fixture({row[1],row[2]}, {merge_2048=true,teacher_team=true})
        assert(game:Start())
        local events = {}
        merge(game, {pairs={{1,2}},positions={[1]={x=0,y=2},[2]={x=.1,y=2}},
            bottom={},top={},wall={},side={},angles={},rotateOffsets={},angularTravel={},
            flightArrived={},flightHits={},shakeStrength=0}, events)
        local state, merged = State.New(), 0
        for _, event in ipairs(events) do
            if event.kind == "merge" then
                assert(event.id == row[3]); merged = merged+1
            elseif event.kind == "consume" then
                assert(State.Action(event) == nil, "材料不再单独播放")
            end
        end
        state:Collect(events)
        local plays = state:Flush()
        assert(merged == 1 and #plays == 1 and plays[1].action == "merge",row[3])
    end
end)

Test("整批吞食合并且短窗限流，合成仍优先，不补播积压", function()
    local state = State.New()
    for _ = 1, 100 do state:Collect({Event("eat"),Event("eat")}) end
    local plays = state:Flush()
    assert(#plays == 1 and plays[1].action == "eat")
    state:Advance(.10);state:Collect({Event("eat")})
    assert(#state:Flush() == 0)
    state:Advance(.11);state:Collect({Event("eat"),Event("merge"),Event("cut")})
    plays = state:Flush()
    assert(#plays == 2 and plays[1].action == "merge" and plays[2].action == "cut")
    state:Advance(2)
    assert(#state:Flush() == 0)
end)

Test("偷笑必须实际减少目标价值，遗物赠送不偷笑", function()
    local event = Event("steal")
    assert(State.Action(event) == "steal")
    for _, value in ipairs({0, 1, 3}) do
        event.value = value
        assert(State.Action(event) == nil)
    end
    event.value = nil
    assert(State.Action(event) == nil)
    local produced = Event("produce")
    produced.count = 0
    assert(State.Action(produced) == nil)
end)

Test("同帧跨批次合并且超额当场丢弃，没有积压补播", function()
    local state = State.New()
    for _ = 1, 200 do state:Collect({Event("produce"), Event("cut"), Event("merge")}) end
    local plays = state:Flush()
    assert(#plays == 2 and plays[1].action == "merge" and plays[2].action == "cut")
    assert(next(state.pending) == nil and #state:Flush() == 0)
    state:Advance(2)
    assert(#state:Flush() == 0, "被丢弃的生产音不能晚两秒补播")
end)

Test("跨物理步的重复事件受同类短窗限制", function()
    local state = State.New()
    state:Collect({Event("cut")})
    assert(#state:Flush() == 1)
    state:Advance(.02)
    state:Collect({Event("cut")})
    assert(#state:Flush() == 0)
    state:Advance(.12)
    state:Collect({Event("cut")})
    assert(#state:Flush() == 1)
end)

Test("不同事件共享短窗起音总量，不能通过换类型绕过限流", function()
    local state = State.New()
    state:Collect({Event("merge"), Event("cut")})
    assert(#state:Flush() == 2)
    state:Advance(.01)
    state:Collect({Event("steal"), Event("jelly")})
    assert(#state:Flush() == 1)
    state:Advance(.01)
    state:Collect({Event("killer")})
    assert(#state:Flush() == 0 and #state.starts == State.PER_WINDOW)
end)

Test("满池仅重要声音抢占，保持三声源上限", function()
    local state = State.New()
    for action in pairs(State.profiles) do state:SetDuration(action, 2) end
    state:Collect({Event("produce")})
    assert(#state:Flush() == 1)
    state:Advance(.13)
    state:Collect({Event("cut"), Event("jelly")})
    assert(#state:Flush() == 2)
    state:Advance(.13)
    state:Collect({Event("steal")})
    local higher = state:Flush()
    assert(#higher == 1 and higher[1].slot == 1, "偷笑可抢占持续中的生产声")
    state:Advance(.13)
    state:Collect({Event("produce")})
    assert(#state:Flush() == 0, "生产声不能抢占更重要的声音")
    assert(#state.voices == 3)
end)

Test("缺失资源不占配额，重置清除旧音与限流状态", function()
    local state = State.New()
    state:SetDuration("killer", nil)
    state:Collect({Event("killer"), Event("cut"), Event("produce")})
    local plays = state:Flush()
    assert(#plays == 2 and plays[1].action == "cut" and plays[2].action == "produce")
    state:Collect({Event("steal")})
    state:Reset()
    assert(state.time == 0 and #state.starts == 0 and next(state.last) == nil and #state:Flush() == 0)
end)

Test("十秒高密度事件保持有界，输入只读", function()
    local state = State.New()
    local events = {Event("produce"), Event("jelly"), Event("steal"), Event("cut"),
        Event("merge"), Event("grow"), Event("killer"), Event("eat")}
    for _ = 1, 600 do
        state:Advance(1 / 60)
        for _ = 1, 20 do state:Collect(events) end
        local plays = state:Flush()
        assert(#plays <= 2 and #state.starts <= 3 and #state.voices == 3)
        assert(next(state.pending) == nil)
    end
    assert(events[1].action == "produce" and events[3].value == -1 and events[7].reason == "eliminate")
    state:Advance(10)
    assert(#state:Flush() == 0)
end)

---@return integer
function T.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "ItemSoundTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end
return T
