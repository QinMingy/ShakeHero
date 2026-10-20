-- 表现事件只观察真实规则结果：不伪造坐标、排队入场、偷取或逻辑相邻碰撞。
local Game = require("Bottle.Game")
local Effects = require("Bottle.Effects")
local Extra = require("Bottle.ExtraEffects")
local Expansion = require("Bottle.ExpansionEffects")
local Repair = require("Bottle.RepairTests")
local Tests = {}

---@param ids string[]
---@return any
local function Fixture(ids)
    local game = Game.New(61020) --[[@as any]]
    game._instances, game.deck, game.discard, game.drawn = {}, {}, {}, {}
    game._lastPositions, game._nextUid = {}, 1
    game.score, game.totalScore, game.roundScore = 0, 0, 0
    game.phase, game.elapsed = "running", 0
    for _, id in ipairs(ids) do
        local item = game:_Create(id)
        item.location, item.remaining = "bottle", 0
        game.drawn[#game.drawn + 1] = item.uid
    end
    return game
end

---@param input number[][]?
---@return any
local function Contacts(input)
    return {pairs = input or {}, positions = {}, side = {}, angles = {},
        angularTravel = {}, rotateOffsets = {}, flightHits = {}, flightArrived = {},
        wall = {}, bottom = {}, top = {}}
end

---@param events any[]
---@param action string
---@return any[]
local function Feedback(events, action)
    local found = {}
    for _, event in ipairs(events) do
        if event.kind == "itemFeedback" and event.action == action then found[#found + 1] = event end
    end
    return found
end

---@param game any
---@param value integer
---@return fun():integer
local function Constant(game, value)
    local calls = 0
    rawset(game, "_RandomInt", function(_, maximum)
        calls = calls + 1
        return math.min(maximum, value)
    end)
    return function() return calls end
end

---@param source string
---@param neighbor string?
---@return any
local function FullBottle(source, neighbor)
    local ids = {source, neighbor or "apple"}
    for _ = 3, 100 do ids[#ids + 1] = "apple" end
    return Fixture(ids)
end

local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end

Test("两种切果者保留真实来源及完整水果身份，一批多果逐个上报", function()
    for _, source in ipairs({"knife", "fruit_ninja"}) do
        local game = Fixture({source, "apple", "orange", "apple_half"})
        local contacts, events = Contacts({{1, 2}, {1, 3}, {1, 4}}), {}
        contacts.positions[1], contacts.positions[2], contacts.positions[3] =
            {x = -1, y = 2}, {x = 1, y = 3}, {x = 2, y = 4}
        assert(Effects.Apply(game, game:Get(1), contacts, events))
        local feedback = Feedback(events, "cut")
        assert(#feedback == 2 and feedback[1].uid == 1 and feedback[1].id == source)
        assert(feedback[1].targetUid == 2 and feedback[1].targetId == "apple")
        assert(feedback[2].targetUid == 3 and feedback[2].targetId == "orange")
        assert(feedback[1].x == -1 and feedback[1].y == 2
            and feedback[1].toX == 1 and feedback[1].toY == 3)
        assert(#feedback[1].producedUids == 1 and #feedback[2].producedUids == 1)
        assert(feedback[1].producedUids[1] ~= 2 and game:Get(2).id == "apple_half")
        assert(game:Get(feedback[1].producedUids[1]).location == "bottle")
    end
end)

Test("切果遗物第三份加入实际产物，满瓶切果不把 queued 当入瓶", function()
    local game = Fixture({"knife", "apple"})
    game.relics.knife_skill = true
    local calls, events = Constant(game, 1), {}
    assert(Effects.Apply(game, game:Get(1), Contacts({{1, 2}}), events))
    local cut = Feedback(events, "cut")[1]
    assert(#cut.producedUids == 2 and calls() == 1)
    assert(cut.x == nil and cut.y == nil and cut.toX == nil and cut.toY == nil)
    game, events = FullBottle("knife"), {}
    assert(Effects.Apply(game, game:Get(1), Contacts({{1, 2}}), events))
    cut = Feedback(events, "cut")[1]
    assert(cut and #cut.producedUids == 0 and #game.spawnQueue == 1)
end)

Test("消耗小鸡不冒充切水果，羊及半份不触发小刀", function()
    local game = Fixture({"knife", "sheep", "apple_half", "chick"})
    game:Get(2).woolCount = 1
    local events = {}
    assert(not Effects.Apply(game, game:Get(1), Contacts({{1, 2}, {1, 3}}), events))
    assert(game:Get(2).woolCount == 1 and #events == 0)
    assert(Effects.Apply(game, game:Get(1), Contacts({{1, 4}}), events))
    assert(game:Get(4).location == "discard" and #Feedback(events, "cut") == 0)
    assert(#Repair.Events(events, "consume", 4) == 1)
end)

Test("学生自然成长捕获变化前图案位置，成长后职业作为目标", function()
    local game = Fixture({"student"})
    game._lastPositions[1] = {x = .25, y = 5}
    local calls, events = Constant(game, 2), {}
    Effects.GrowStudent(game, game:Get(1), events, false)
    local grow = Feedback(events, "grow")[1]
    assert(grow.uid == 1 and grow.id == "student" and grow.targetUid == 1)
    assert(grow.targetId == game:Get(1).id and grow.x == .25 and grow.toY == 5)
    assert(game._lastPositions[1] == nil and calls() == 2)
end)

Test("老师催熟使用学生为成长主体，坐标来自当前真实接触", function()
    local game = Fixture({"teacher", "student"})
    local contacts, events = Contacts({{1, 2}}), {}
    contacts.positions[2] = {x = 1.25, y = 2.5}
    local calls = Constant(game, 1)
    assert(Effects.Apply(game, game:Get(1), contacts, events))
    local grow = Feedback(events, "grow")[1]
    assert(grow.uid == 2 and grow.id == "student" and grow.targetId == "police")
    assert(grow.x == 1.25 and grow.toY == 2.5 and calls() == 1)
end)

Test("小偷报告目标实际价值差，正向遗物增益不伪称负向偷取", function()
    for _, relic in ipairs({"none", "wash_hands", "lucky_charm"}) do
        local game = Fixture({"thief", "police"})
        if relic ~= "none" then game.relics[relic] = true end
        game:Get(2).mult = 2
        local contacts, events = Contacts({{1, 2}}), {}
        game._lastPositions[1] = {x = -1, y = 1}
        contacts.positions[2] = {x = 2, y = 3}
        local before = game:_Value(game:Get(2))
        assert(Effects.Apply(game, game:Get(1), contacts, events))
        local steal = Feedback(events, "steal")[1]
        assert(steal.value == game:_Value(game:Get(2)) - before)
        assert(steal.value == (relic == "none" and -2 or 2))
        assert(steal.uid == 1 and steal.targetUid == 2 and steal.targetId == "police")
        assert(steal.x == -1 and steal.toY == 3)
    end
end)

Test("零价值或不合法目标不发偷取事件", function()
    local game = Fixture({"thief", "student", "apple"})
    game:Get(2).permBonus = -3
    local events = {}
    assert(not Effects.Apply(game, game:Get(1), Contacts({{1, 2}, {1, 3}}), events))
    assert(#Feedback(events, "steal") == 0)
end)

Test("果冻只为实际弹射目标上报，穿透与逻辑相邻不能触发", function()
    local game = Fixture({"jelly", "apple", "ghost", "orange"})
    local contacts, events = Contacts({{1, 2}, {1, 3}, {1, 4}}), {}
    contacts.rawPairs = {{1, 2}, {1, 3}}
    contacts.positions[1], contacts.positions[2] = {x = 0, y = 1}, {x = .5, y = 1}
    assert(Expansion.Apply(game, game:Get(1), contacts, events))
    local jelly = Feedback(events, "jelly")
    assert(#jelly == 1 and jelly[1].uid == 1 and jelly[1].targetUid == 2)
    assert(jelly[1].targetId == "apple" and jelly[1].x == 0 and jelly[1].toX == .5)
    assert(events[1].kind == "impulse" and events[1].strength == 6)
    contacts.rawPairs, events = {}, {}
    assert(not Expansion.Apply(game, game:Get(1), contacts, events) and #events == 0)
end)

Test("果冻缺少位置时保持 nil，不把物理方向兜底冒充坐标", function()
    local game = Fixture({"jelly", "apple"})
    local events = {}
    assert(Expansion.Apply(game, game:Get(1), Contacts({{1, 2}}), events))
    local jelly = Feedback(events, "jelly")[1]
    assert(jelly.x == nil and jelly.y == nil and jelly.toX == nil and jelly.toY == nil)
end)

Test("果树祝福一次生产批合并两件，保持原随机调用次数", function()
    local game = Fixture({"fruit_tree"})
    game:Get(1).treeBlessed = true
    local contacts, events = Contacts(), {}
    contacts.positions[1] = {x = -2, y = 4}
    local calls = Constant(game, 1)
    assert(Extra.Apply(game, game:Get(1), contacts, events))
    local produce = Feedback(events, "produce")
    assert(#produce == 1 and produce[1].count == 2 and #produce[1].producedUids == 2)
    assert(produce[1].id == "fruit_tree" and produce[1].x == -2 and calls() == 3)
end)

Test("云朵七件产物只发一批反馈，近满瓶只计真正入瓶部分", function()
    for _, free in ipairs({7, 2}) do
        local ids = {"cloud"}
        for _ = 2, 100 - free do ids[#ids + 1] = "apple" end
        local game, events = Fixture(ids), {}
        local calls = Constant(game, 1)
        assert(Extra.Apply(game, game:Get(1), Contacts(), events))
        local produce = Feedback(events, "produce")
        assert(#produce == 1 and produce[1].count == free and #produce[1].producedUids == free)
        assert(#game.spawnQueue == 7 - free and calls() == 7)
        assert(produce[1].x == nil and produce[1].y == nil)
        for _, uid in ipairs(produce[1].producedUids) do assert(game:Get(uid).location == "bottle") end
    end
end)

Test("小鸡实际下蛋与硬币机批量出币报告真实产物及来源", function()
    local game, events = Fixture({"chick"}), {}
    Constant(game, 1)
    assert(Expansion.Apply(game, game:Get(1), Contacts(), events))
    local produce = Feedback(events, "produce")[1]
    assert(produce.id == "chick" and produce.count == 1)
    assert(game:Get(produce.producedUids[1]).id == "egg")
    game, events = Fixture({"coin_machine", "student", "police", "apple"}), {}
    Constant(game, 1)
    assert(Extra.Apply(game, game:Get(1), Contacts({{1, 2}, {1, 3}, {1, 4}}), events))
    produce = Feedback(events, "produce")[1]
    assert(produce.id == "coin_machine" and produce.count == 2 and #produce.producedUids == 2)
end)

Test("所有生产者满瓶排队仍算规则成功，但不伪报实际出现", function()
    for _, id in ipairs({"fruit_tree", "cloud", "chick", "coin_machine"}) do
        local game, events = FullBottle(id, "student"), {}
        Constant(game, 1)
        local contacts = Contacts({{1, 2}})
        local applied = id == "chick" and Expansion.Apply(game, game:Get(1), contacts, events)
            or id ~= "chick" and Extra.Apply(game, game:Get(1), contacts, events)
        assert(applied and #game.spawnQueue > 0 and #Feedback(events, "produce") == 0, id)
    end
end)

Test("生产概率失败或硬币机无合法邻居不发反馈", function()
    local game, events = Fixture({"fruit_tree"}), {}
    Constant(game, 2)
    assert(not Extra.Apply(game, game:Get(1), Contacts(), events))
    game = Fixture({"chick"}); Constant(game, 31)
    assert(not Expansion.Apply(game, game:Get(1), Contacts(), events))
    game = Fixture({"coin_machine", "apple"})
    assert(not Extra.Apply(game, game:Get(1), Contacts({{1, 2}}), events))
    assert(#Feedback(events, "produce") == 0)
end)

---@return integer
function Tests.Run()
    local passed, failures = 0, {}
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then passed = passed + 1
        else failures[#failures + 1] = case.name .. "：" .. tostring(message) end
    end
    assert(#failures == 0, "Bottle.ItemFeedbackEventTests " .. passed .. "/" .. #cases
        .. " 通过\n" .. table.concat(failures, "\n"))
    return passed
end

return Tests
