-- 遗物每次独立免费刷新一次；仅内存规则测试，不接触玩家存档。
local Game = require("Bottle.Game")
local Relics = require("Bottle.Relics")
local Repair = require("Bottle.RepairTests")
local RefreshUI = require("Bottle.RefreshUI")
local Tests = {}

---@param a any
---@param b any
---@return boolean
local function Equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key,value in pairs(a) do if not Equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

---@param ids string[]?
---@param round integer?
---@return BottleGame
local function Prepare(ids,round)
    local snapshot = Repair.Fixture(ids or {"apple"}):Snapshot()
    snapshot.round = round or 5
    snapshot.stage = math.floor((snapshot.round-1)/5)+1
    snapshot.target, snapshot.score = Game.GetTarget(snapshot.stage), 10000
    return Game.Restore(snapshot)
end

---@param game BottleGame
local function Finish(game)
    assert(game:Start())
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "draft" and not game.relicDraft)
end

---@param game BottleGame
local function Enter(game)
    Finish(game)
    assert(game.pendingRelicDraft and game:Skip() and game.relicDraft)
    assert(game.relicRefreshes == 1 and not game.refreshUsed)
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name,run) cases[#cases+1]={name=name,run=run} end

Test("新局普通一次遗物零、准备与物品仍连续共享",function()
    local game = Prepare(nil,1)
    assert(Game.New(31).relicRefreshes == 0 and game.refreshes == 1)
    game.refreshes = 4
    assert(game:Reroll() and game:Reroll() and game.refreshes == 2)
    Finish(game)
    assert(game.relicRefreshes == 0 and game:DraftRefresh() and game:DraftRefresh() and game:DraftRefresh())
    assert(game.refreshes == 0 and not game:DraftRefresh())
end)

Test("遗物免费一次普通零也可刷、普通多次也不能续刷",function()
    for _,balance in ipairs({0,7}) do
        local game = Prepare()
        game.refreshes = balance
        Enter(game)
        game.refreshes = balance
        assert(game.refreshes == balance and game:DraftRefresh())
        assert(game.refreshes == balance and game.relicRefreshes == 0 and game.refreshUsed)
        local spent = game:Snapshot()
        for _=1,3 do assert(not game:DraftRefresh() and Equal(spent,game:Snapshot())) end
    end
end)

Test("第5与10次环节各独立一次、未用不累计",function()
    for _,spendFirst in ipairs({false,true}) do
        local game = Prepare()
        Enter(game)
        if spendFirst then assert(game:DraftRefresh()) end
        local balance = game.refreshes
        assert(game:Skip() and game.phase == "prepare" and game.round == 6 and game.relicRefreshes == 0)
        assert(game.refreshes == balance)
        for round=6,9 do
            assert(game.round == round)
            Finish(game)
            assert(game.relicRefreshes == 0 and game:Skip())
        end
        Enter(game)
        assert(game.round == 10 and game.relicRefreshes == 1)
        assert(game:DraftRefresh() and not game:DraftRefresh())
    end
end)

Test("选择或跳过遗物均清空免费次数不动普通池",function()
    for _,choose in ipairs({false,true}) do
        local game = Prepare()
        Enter(game)
        local balance = game.refreshes
        assert(choose and game:Choose(1) or not choose and game:Skip())
        assert(game.phase == "prepare" and not game.relicDraft and game.relicRefreshes == 0)
        assert(game.refreshes == balance and Game.Restore(game:Snapshot()).relicRefreshes == 0)
    end
end)

Test("所有遗物已拥有时空候选直接推进、不泄漏免费次数",function()
    local game = Prepare()
    for _,def in ipairs(Relics.list) do game.relics[def.id] = true end
    Finish(game)
    local balance = game.refreshes
    assert(game:Skip() and game.phase == "prepare" and game.round == 6)
    assert(game.relicRefreshes == 0 and not game.relicDraft and game.refreshes == balance)
end)

Test("免费刷新照常通知所有养鸡人、失败不通知",function()
    local game = Prepare({"chicken_keeper","chicken_keeper","apple"})
    Enter(game)
    for uid=1,2 do
        local item = assert(game:Get(uid))
        item.refreshCount = 4
        assert(item.location == "deck")
    end
    game.refreshes = 0
    assert(game:DraftRefresh())
    for uid=1,2 do
        local item = assert(game:Get(uid))
        assert(item.refreshCount == 0 and item.permBonus == 1)
    end
    local spent = game:Snapshot()
    assert(not game:DraftRefresh() and Equal(spent,game:Snapshot()))
    local restored = Game.Restore(spent)
    assert(not restored:DraftRefresh() and Equal(spent,restored:Snapshot()))
end)

Test("rules8遗物0和1快照及JSON往返不重复免费",function()
    local game = Prepare()
    Enter(game)
    for _,spend in ipairs({false,true}) do
        if spend then assert(game:DraftRefresh()) end
        local snapshot = game:Snapshot()
        assert(snapshot.rulesVersion == 8 and snapshot.version == 2)
        local restored = Game.Restore(snapshot)
        assert(Equal(snapshot,restored:Snapshot()))
        local json = rawget(_G,"cjson")
        if json then
            restored = Game.Restore(json.decode(json.encode(snapshot)))
            assert(Equal(snapshot,restored:Snapshot()))
        end
        assert(restored:DraftRefresh() == not spend)
        assert(not restored:DraftRefresh() and restored.refreshes == game.refreshes)
    end
end)

Test("旧nil/5/6/7遗物档按已用状态推断、不退还普通池",function()
    local game = Prepare()
    Enter(game)
    for _,rules in ipairs({false,5,6,7}) do
        for _,used in ipairs({false,true}) do
            local snapshot = game:Snapshot() --[[@as any]]
            snapshot.rulesVersion, snapshot.relicRefreshes = rules or nil, nil
            snapshot.refreshes, snapshot.refreshUsed = 6, used
            local restored = Game.Restore(snapshot)
            assert(restored.relicRefreshes == (used and 0 or 1) and restored.refreshes == 6)
            assert(restored._rngState == snapshot.rngState and Equal(restored.options,snapshot.options))
            local migrated = restored:Snapshot()
            assert(migrated.rulesVersion == 8 and Equal(migrated,Game.Restore(migrated):Snapshot()))
            assert(restored:DraftRefresh() == not used and restored.refreshes == 6)
            assert(not restored:DraftRefresh())
        end
    end
end)

Test("旧其他阶段缺遗物次数补零、不按历史考核补发",function()
    for _,phase in ipairs({"prepare","draft","over"}) do
        local game = Prepare()
        if phase ~= "prepare" then Finish(game) end
        if phase == "over" then game.phase,game.options = "over",{}; game.round,game.stage = 10,2 end
        for _,rules in ipairs({false,5,6,7}) do
            local snapshot = game:Snapshot() --[[@as any]]
            snapshot.rulesVersion, snapshot.relicRefreshes = rules or nil, nil
            local restored = Game.Restore(snapshot)
            assert(restored.relicRefreshes == 0 and restored.refreshes == game.refreshes)
        end
    end
end)

Test("新8严格拒绝缺失非法次数、阶段与已用状态不一致",function()
    local game = Prepare()
    Enter(game)
    local missing = game:Snapshot() --[[@as any]]
    missing.relicRefreshes = nil
    assert(not pcall(Game.Restore,missing))
    for _,value in ipairs({-1,2,.5,false,true,"1",{},0/0,math.huge,-math.huge}) do
        local corrupt = game:Snapshot() --[[@as any]]
        corrupt.relicRefreshes = value
        assert(not pcall(Game.Restore,corrupt),"非法遗物次数必须拒绝")
    end
    for _,used in ipairs({false,true}) do
        local mismatch = game:Snapshot()
        mismatch.refreshUsed, mismatch.relicRefreshes = used, used and 1 or 0
        assert(not pcall(Game.Restore,mismatch),"剩余次数必须与已用标记一致")
    end
    for _,phase in ipairs({"prepare","draft","over"}) do
        local outside = Prepare()
        if phase ~= "prepare" then Finish(outside) end
        if phase == "over" then outside.phase,outside.options = "over",{}; outside.round,outside.stage = 10,2 end
        local corrupt = outside:Snapshot()
        corrupt.relicRefreshes = 1
        assert(not pcall(Game.Restore,corrupt),"非遗物环节不能残留免费次数")
    end
end)

Test("遗物用完推进后运行结算展示快照回滚不重发",function()
    local game = Prepare()
    Enter(game)
    assert(game:DraftRefresh() and game:Skip())
    local prepare = game:Snapshot()
    assert(prepare.relicRefreshes == 0 and game:Start())
    game.relicRefreshes = 1 -- 模拟半回合状态；回滚必须仍取开局前的零值。
    assert(Equal(prepare,game:Snapshot()))
    game:Step(10)
    assert(game.phase == "settle" and Equal(prepare,game:Snapshot()))
    game:SettleStep(2)
    assert(game.phase == "reveal" and Equal(prepare,game:Snapshot()))
    assert(Game.Restore(game:Snapshot()).relicRefreshes == 0)
end)

Test("UI按phase和relicDraft动态选池、遗物提示不写共享",function()
    local game = Prepare()
    game.refreshes = 9
    assert(RefreshUI.Count(game) == 9 and RefreshUI.Hint(game):find("共享",1,true))
    Enter(game)
    assert(RefreshUI.Count(game) == 1 and RefreshUI.ButtonText(game) == "免费刷新 · 1 次")
    assert(RefreshUI.Hint(game):find("免费1次",1,true) and not RefreshUI.Hint(game):find("共享",1,true))
    assert(game:DraftRefresh() and RefreshUI.Count(game) == 0)
    assert(RefreshUI.ButtonText(game) == "免费刷新 · 0 次" and game.refreshes == 10)
    assert(game:Skip() and RefreshUI.Count(game) == 10)
end)

---@return integer
function Tests.Run()
    local passed,failures = 0,{}
    for _,case in ipairs(cases) do
        local ok,message = pcall(case.run)
        if ok then passed=passed+1 else failures[#failures+1]=case.name.."："..tostring(message) end
    end
    assert(#failures == 0,"Bottle.RelicRefreshTests "..passed.."/"..#cases.." 通过\n"..table.concat(failures,"\n"))
    return passed
end
return Tests
