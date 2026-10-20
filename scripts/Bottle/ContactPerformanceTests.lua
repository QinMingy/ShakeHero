-- 接触查询优化回归：纯规则、内存夹具，不读取存档或启动物理/预览。
local Game = require("Bottle.Game")
local Effects = require("Bottle.Effects")
local RelicExpansion = require("Bottle.RelicExpansion")
local BudgetSort = require("Bottle.BudgetSort")
local FrameBudget = require("Bottle.FrameBudget")
local Repair = require("Bottle.RepairTests")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end
---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
local function Fixture(ids, relics)
    local game = Repair.Fixture(ids, relics)
    assert(game:Start())
    return game
end
---@param game BottleGame
---@param uid number
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid)) end
---@param items ItemInstance[]
---@return string
local function Uids(items)
    local ids = {}
    for _, item in ipairs(items) do ids[#ids + 1] = tostring(item.uid) end
    return table.concat(ids, ",")
end

---@param work fun()
---@param pending (fun())?
---@return integer yields
local function Sliced(work, pending)
    local budget = FrameBudget.New(4, function() return 0 end, 8)
    budget:Start(work)
    local frames = 0
    while budget:Busy() do
        frames = frames + 1
        assert(frames < 100000, "分片工作未完成")
        budget:BeginFrame()
        if not budget:Resume() and pending then pending() end
    end
    return budget.totalYields
end

Test("分块排序在块边界保持原生数值顺序且不丢失成员", function()
    for _, count in ipairs({0,1,127,128,129,255,256,257,4950}) do
        local actual, expected = {}, {}
        for index = 1, count do
            local value = (index * 97) % 137
            actual[index], expected[index] = value, value
        end
        table.sort(expected)
        BudgetSort.Sort(actual, function(a,b) return a < b end)
        assert(#actual == count)
        for index = 1, count do assert(actual[index] == expected[index]) end
    end
end)

Test("大数组重复键稳定且强制跨帧后保持对象身份", function()
    local actual, expected = {}, {}
    for index = 1, 4950 do
        local value = {key=(index * 97) % 23, original=index}
        actual[index], expected[index] = value, value
    end
    table.sort(expected, function(a,b)
        return a.key == b.key and a.original < b.original or a.key < b.key
    end)
    local yields = Sliced(function()
        BudgetSort.Sort(actual, function(a,b) return a.key < b.key end)
    end)
    assert(yields > 10, "大排序未经过多个可让出边界")
    assert(#actual == #expected)
    for index = 1, #expected do assert(actual[index] == expected[index]) end
end)

Test("百实例稠密接触跨帧排序保持UID去重和RNG且仅完成后发布", function()
    local game = Fixture({})
    for _ = 1, 100 do assert(game:_Spawn("ball", {})) end
    assert(#game:BottleItems() == 100)
    local raw = {}
    for first = 100, 1, -1 do
        for second = first - 1, 1, -1 do
            raw[#raw + 1] = {first,second}
            if second == 1 then raw[#raw + 1] = {second,first} end
        end
    end
    local originalFirst, originalLast = raw[1], raw[#raw]
    local state = {pairs={},rawPairs=raw} --[[@as BottleStepContacts]]
    local oldPairs, rng = state.pairs, game._rngState
    local yields = Sliced(function() RelicExpansion.ExpandContacts(game, state) end, function()
        assert(state.pairs == oldPairs and state._managedGraph == nil,
            "扩图在完成前发布了部分结果")
    end)
    assert(yields > 10 and #state.pairs == 4950)
    assert(raw[1] == originalFirst and raw[#raw] == originalLast)
    assert(raw[1][1] == 100 and raw[1][2] == 99 and game._rngState == rng)
    local index = 0
    for first = 1, 99 do
        for second = first + 1, 100 do
            index = index + 1
            assert(state.pairs[index][1] == first and state.pairs[index][2] == second)
        end
    end
    ---@type ItemInstance[]
    local result = {}
    yields = Sliced(function() result = game:_Adjacents(50, state) end, function()
        assert(state._adjacencyUids == nil and state._adjacencyPairs == nil,
            "邻居索引在完成前发布了部分结果")
    end)
    assert(yields > 10 and #result == 99 and game._rngState == rng)
    for position, item in ipairs(result) do
        assert(item.uid == (position < 50 and position or position + 1))
    end
    local cached = state._adjacencyUids
    assert(#game:_Adjacents(50, state) == 99 and state._adjacencyUids == cached)
end)

Test("外部可变接触保持去重和UID顺序且不缓存原地修改", function()
    local game = Fixture({"apple","apple","apple","apple","apple"})
    local contacts = {pairs={{4,3},{1,4},{4,2},{4,3}}} --[[@as BottleStepContacts]]
    assert(Uids(game:_Adjacents(4, contacts)) == "1,2,3")
    contacts.pairs[1] = {5,4}
    assert(Uids(game:_Adjacents(4, contacts)) == "1,2,3,5")
    assert(contacts._adjacencyPairs == nil)
end)

Test("核心图索引复用但返回新数组并即时过滤已离场实例", function()
    local game = Fixture({"apple","apple","apple","apple","apple"})
    local contacts = game:_ContactSnapshot({pairs={{4,3},{1,4},{4,2},{4,3}}})
    local first = game:_Adjacents(4, contacts)
    local index = contacts._adjacencyUids
    assert(Uids(first) == "1,2,3")
    first[1] = nil
    assert(Uids(game:_Adjacents(4, contacts)) == "1,2,3")
    assert(contacts._adjacencyUids == index)
    Item(game, 3).location = "discard"
    assert(Uids(game:_Adjacents(4, contacts)) == "1,2")
    contacts.pairs = {{4,5},{4,1},{1,4}}
    assert(Uids(game:_Adjacents(4, contacts)) == "1,5")
    assert(contacts._adjacencyUids ~= index)
end)

Test("培根派生仅基于真实一跳且重新扩图替换旧索引", function()
    local game = Fixture({"bacon","apple","knife","bacon","ball"}, {bacon_network=true})
    local contacts = game:_ContactSnapshot({pairs={{1,2},{1,3},{1,4},{4,5}}})
    assert(Uids(game:_Adjacents(2, contacts)) == "1,3,4")
    assert(Uids(game:_Adjacents(5, contacts)) == "1,4")
    local index = contacts._adjacencyUids
    contacts.rawPairs = {{1,2},{4,5}}
    RelicExpansion.ExpandContacts(game, contacts)
    assert(contacts._adjacencyUids == nil)
    assert(Uids(game:_Adjacents(2, contacts)) == "1")
    assert(contacts._adjacencyUids ~= index)
    assert(#contacts.rawPairs == 2 and #contacts.pairs == 2)
end)

Test("无fixture变化的完整规则步只扩图一次", function()
    local game = Fixture({"apple","apple","apple","apple"})
    local original, count = RelicExpansion.ExpandContacts, 0
    RelicExpansion.ExpandContacts = function(...)
        count = count + 1
        return original(...)
    end
    local ok, err = pcall(function()
        local events = game:Step(1/60, {pairs={{1,2},{2,3},{3,4}}})
        assert(#events == 0)
    end)
    RelicExpansion.ExpandContacts = original
    assert(ok, tostring(err))
    assert(count == 1, "无变化重复重建接触图：" .. count)
end)

Test("没有光环源也重置过期倍率并更新计数器但不查询邻居", function()
    local game = Fixture({"apple","counter","apple"})
    local contacts = game:_ContactSnapshot({pairs={{1,2},{2,3}}})
    Item(game, 1).mult, Item(game, 1).eventMult = 8, 3
    local original, queries = Game._Adjacents, 0
    Game._Adjacents = function(...)
        queries = queries + 1
        return original(...)
    end
    local events = {}
    local ok, err = pcall(function() Effects.Continuous(game, contacts, events) end)
    Game._Adjacents = original
    assert(ok, tostring(err))
    assert(queries == 0 and Item(game, 1).mult == 3 and Item(game, 2).bonus == 1)
    assert(#events == 1 and events[1].kind == "buff")
end)

Test("厨师水果商人叠乘与离场后的光环立即更新", function()
    local game = Fixture({"chef","chef","fruit_merchant","apple"})
    local contacts = game:_ContactSnapshot({pairs={{1,4},{2,4},{3,4}}})
    Item(game, 4).eventMult = 1.5
    Effects.Continuous(game, contacts, {})
    assert(Item(game, 4).mult == 12)
    Item(game, 1).location = "discard"
    Effects.Continuous(game, contacts, {})
    assert(Item(game, 4).mult == 6)
    Item(game, 2).location = "discard"
    Effects.Continuous(game, contacts, {})
    assert(Item(game, 4).mult == 3)
    Item(game, 3).location = "discard"
    Effects.Continuous(game, contacts, {})
    assert(Item(game, 4).mult == 1.5)
end)

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.ContactPerformanceTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end
return Tests
