-- 位移节奏专项：沿用Repair.Fixture，真实米制，不创建物理对象、不读写存档。
local Repair = require("Bottle.RepairTests")
local Extra = require("Bottle.ExtraEffects")
local Expansion = require("Bottle.ExpansionEffects")
local Items = require("Bottle.Items")
local Tests = {}
local cases = {}
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end
local function Close(a, b) assert(math.abs(a - b) < 1e-7, tostring(a) .. " ~= " .. b) end
local function Make(ids, relics)
    local game = Repair.Fixture(ids, relics)
    assert(game:Start())
    rawset(game, "_RandomInt", function(_, maximum) return 1 end)
    return game
end

Test("说明与兔子100米、大胃王100米阈值及运动员屏蔽一致", function()
    assert(Items.byId.rabbit.effect:find("100m", 1, true))
    assert(Items.byId.glutton.effect:find("100m", 1, true))
    assert(Items.byId.discus_athlete.pool == false, "飞盘运动员屏蔽卡池，不删除定义或旧实例")
end)

Test("兔子阈值边界、多段消费与余程不硬限两次", function()
    local game = Make({"rabbit"})
    local rabbit = assert(game:Get(1))
    rabbit.distance = 99.999
    Extra.TrackDistance(game, rabbit, {})
    Close(rabbit.permBonus, 0)
    rabbit.distance = 100
    Extra.TrackDistance(game, rabbit, {})
    Close(rabbit.permBonus, 1); Close(rabbit.distance, 0)
    rabbit.distance = 300.25
    Extra.TrackDistance(game, rabbit, {})
    Close(rabbit.permBonus, 4); Close(rabbit.distance, .25)
end)

Test("真实位置往返200米奖励两次且静止重复不奖励", function()
    local game = Make({"rabbit"})
    local rabbit = assert(game:Get(1))
    game:Step(0, {positions = {[1] = {x = 0, y = 2}}})
    for step = 1, 400 do
        game:Step(1 / 60, {positions = {[1] = {x = step % 2 == 0 and 0 or .5, y = 2}}})
    end
    Close(rabbit.permBonus, 2); Close(rabbit.distance, 0)
    for _ = 1, 30 do game:Step(0, {positions = {[1] = {x = 0, y = 2}}}) end
    Close(rabbit.permBonus, 2); Close(rabbit.distance, 0)
end)

Test("跳变、传送和缺失采样不产生假路程", function()
    local game = Make({"rabbit"})
    local rabbit = assert(game:Get(1))
    rabbit.distance = 99.5
    game:Step(0, {positions = {[1] = {x = 0, y = 2}}})
    game:Step(0, {positions = {[1] = {x = 1, y = 2}}})
    Close(rabbit.permBonus, 0); Close(rabbit.distance, 99.5)
    game:_TeleportTop(rabbit, {})
    game:Step(0, {positions = {[1] = {x = .9, y = 2}}})
    Close(rabbit.permBonus, 0); Close(rabbit.distance, 99.5)
    game:Step(0, {})
    game:Step(0, {positions = {[1] = {x = 0, y = 2}}})
    Close(rabbit.permBonus, 0); Close(rabbit.distance, 99.5)
    game:Step(0, {positions = {[1] = {x = .5, y = 2}}})
    Close(rabbit.permBonus, 1); Close(rabbit.distance, 0)
end)

Test("成群结队只按各兔真实达标奖励且不改群体规则", function()
    local game = Make({"rabbit", "rabbit"}, {in_groups = true})
    local first, second = assert(game:Get(1)), assert(game:Get(2))
    first.distance, second.distance = 100, 99.5
    Extra.TrackDistance(game, first, {})
    Close(first.permBonus, 1); Close(second.permBonus, 1)
    Close(second.distance, 99.5)
    Extra.TrackDistance(game, second, {})
    Close(first.permBonus, 1); Close(second.permBonus, 1)
    second.distance = 100
    Extra.TrackDistance(game, second, {})
    Close(first.permBonus, 2); Close(second.permBonus, 2)
end)

Test("大胃王100米阈值、教练缩幅奖励和下限保留", function()
    local game = Make({"glutton", "fitness_coach"})
    local glutton, coach = assert(game:Get(1)), assert(game:Get(2))
    glutton.scale, glutton.distance = 1.5, 99.999
    Extra.TrackDistance(game, glutton, {})
    Close(glutton.scale, 1.5); Close(coach.permBonus, 0)
    glutton.distance = 100
    Extra.TrackDistance(game, glutton, {})
    Close(glutton.scale, 1.3); Close(coach.permBonus, 1)
    glutton.distance = 200
    Extra.TrackDistance(game, glutton, {})
    Close(glutton.scale, 1); Close(coach.permBonus, 3)
    glutton.distance = 100
    Extra.TrackDistance(game, glutton, {})
    Close(glutton.scale, 1); Close(coach.permBonus, 3); Close(glutton.distance, 0)
end)

Test("飞盘5米边界、真实位置累计和余程", function()
    local game = Make({"discus", "apple"})
    local disc = assert(game:Get(1))
    disc.discusState, disc.discusWait = "owner_wait", 100
    assert(Items.byId.discus.effect:find("5m", 1, true))
    disc.distance = 4.99
    Expansion.Step(game, 0, game:_ContactSnapshot({}), {})
    Close(game.roundScore, 0)
    disc.distance = 12.4
    Expansion.Step(game, 0, game:_ContactSnapshot({}), {})
    Close(game.roundScore, 4); Close(disc.distance, 2.4)
    disc.distance = 4.5
    game:Step(0, {positions = {[1] = {x = 0, y = 2}}})
    game:Step(1 / 60, {positions = {[1] = {x = .5, y = 2}}})
    Close(game.roundScore, 6); Close(disc.distance, 0)
end)

Test("结算下落不累计且回合清余程永久价值保留", function()
    local game = Make({"rabbit"})
    local rabbit = assert(game:Get(1))
    rabbit.distance = 200.5
    Extra.TrackDistance(game, rabbit, {})
    game:Step(10, {positions = {[1] = {x = 0, y = 2}}})
    assert(game.phase == "settle")
    game:SettleStep(.1, {positions = {[1] = {x = .5, y = 2}}})
    Close(rabbit.distance, .5); Close(rabbit.permBonus, 2)
    game:SettleStep(2)
    Close(rabbit.distance, 0); Close(rabbit.permBonus, 2)
end)

function Tests.Run()
    for _, entry in ipairs(cases) do
        local ok, err = pcall(entry.run)
        assert(ok, "[DistanceTests] " .. entry.name .. ": " .. tostring(err))
    end
    print(string.format("[DistanceTests] %d项通过：兔子100米／大胃王100米／飞盘5米／真实位置／群体／生命周期", #cases))
    return #cases
end
return Tests
