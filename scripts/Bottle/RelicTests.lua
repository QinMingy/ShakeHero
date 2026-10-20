-- 五遗物纯 Lua 回归：不加载 Storage/main/UI，不创建引擎对象，不读写存档。
-- 单独运行 require("Bottle.RelicTests").Run()；Bottle.Tests.Run() 同时包含本套。
-- 接触只是规则输入夹具，不替代真实 Box2D 或 UI 验收。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Game = require("Bottle.Game")
local RelicEffects = require("Bottle.RelicEffects")
local Tests = {}

---@param actual number?
---@param expected number
---@param message string?
local function Close(actual, expected, message)
    assert(type(actual) == "number", (message or "数值") .. "：实际值缺失")
    assert(math.abs(actual - expected) < 1e-7,
        string.format("%s：期望%g，实际%g", message or "数值", expected, actual))
end

---@param a any
---@param b any
---@return boolean
local function Equal(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key, value in pairs(a) do if not Equal(value, b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid)
    return assert(game:Get(uid), "缺少测试实例uid=" .. uid)
end

-- 从真实合法快照构造夹具；旧 version=2 缺省另有显式回归。
---@param ids string[]
---@param bottleCount integer?
---@return BottleGame
local function Fixture(ids, bottleCount)
    local snapshot = Game.New(137):Snapshot()
    snapshot.instances, snapshot.deck, snapshot.discard, snapshot.drawn = {}, {}, {}, {}
    snapshot.nextUid = #ids + 1
    local count = bottleCount == nil and #ids or bottleCount
    for uid, id in ipairs(ids) do
        snapshot.instances[#snapshot.instances + 1] = {
            uid = uid, id = id, bonus = 0, permBonus = 0, mult = 1,
            permMult = 1, tokenAttempted = false,
            remaining = Items.byId[id].cooldown, bottleRounds = 0,
            location = uid <= count and "bottle" or "deck", temporary = false,
            scale = 1, weight = 1, counter = 0, settleCount = 0, distance = 0,
            eventMult = 1, generatedTemporary = false, shielded = false, anchored = false,
            refreshCount = 0, woolCount = 0, abacusMerges = 0, calfDashRemaining = 0,
            discusWait = 0, compassProgress = 0,
        }
        snapshot.deck[#snapshot.deck + 1] = uid
        if uid <= count then snapshot.drawn[#snapshot.drawn + 1] = uid end
    end
    return Game.Restore(snapshot)
end

-- 仅覆盖单个夹具的随机源；验证每次请求的范围并检测意外重试/多投。
---@param game BottleGame
---@param values integer[]
---@return fun()
local function RandomSequence(game, values)
    local index = 0
    rawset(game, "_RandomInt", function(_, maximum)
        index = index + 1
        local value = assert(values[index], "确定性随机序列用尽：发生额外随机判定")
        assert(value >= 1 and value <= maximum, "确定性随机值超出请求范围")
        return value
    end)
    return function() assert(index == #values, "确定性随机序列未消费完") end
end

---@param events GameEvent[]
---@param kind string
---@param uid integer?
---@return GameEvent[]
local function Events(events, kind, uid)
    ---@type GameEvent[]
    local found = {}
    for _, event in ipairs(events) do
        if event.kind == kind and (uid == nil or event.uid == uid) then found[#found + 1] = event end
    end
    return found
end

---@param game BottleGame
local function Identity(game)
    ---@type table<number, boolean>
    local seen = {}
    for _, item in ipairs(game.deck) do
        assert(not seen[item.uid] and game:Get(item.uid) == item, "牌库身份重复或实例复制")
        assert(item.location == "deck" or item.location == "bottle", "持有牌库位置错误")
        seen[item.uid] = true
    end
    for _, item in ipairs(game.discard) do
        assert(not seen[item.uid] and game:Get(item.uid) == item and item.location == "discard",
            "弃牌身份重复、仍在牌库或位置错误")
        seen[item.uid] = true
    end
    for _, item in ipairs(game:AllInstances()) do assert(seen[item.uid], "实例无归属") end
end

---@param game BottleGame
---@param contacts BottleContacts?
---@return GameEvent[]
local function Finish(game, contacts)
    if game.phase == "running" then game:Step(game:Duration() - game.elapsed) end
    local events = game:SettleStep(2, contacts)
    assert(game.phase == "reveal", "结算后必须进入展示")
    -- 精确随机序列只限定本次规则效果；三选一属于另一个随机过程。
    rawset(game, "_RandomInt", nil)
    game:RevealStep(2 + Game.ScorePopTime(game._revealPopCount or 0))
    assert(game.phase == "draft" or game.phase == "over", "全部浮字加2秒后才离开展示")
    Identity(game)
    return events
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run)
    cases[#cases + 1] = { name = name, run = run }
end

Test("原五遗物仍全部入候选、拥有后排除且39件耗尽", function()
    local game = Fixture({})
    local available = {}
    for _, def in ipairs(Relics.Available(game)) do available[def.id] = true end
    assert(#Relics.list == 39 and #Relics.Available(game) == 39)
    for _, id in ipairs({ "gambling_token", "lucky_charm", "scramble_recipe", "jungle_hunt", "juicer" }) do
        assert(Relics.byId[id].implemented and Relics.byId[id].pool and available[id], "遗物未接线：" .. id)
        game.relics[id] = true
    end
    assert(#Relics.Available(game) == 34)
    for _, def in ipairs(Relics.Available(game)) do assert(not game.relics[def.id]) end
    for _, def in ipairs(Relics.list) do game.relics[def.id] = true end
    assert(#Relics.Available(game) == 0)
end)

Test("遗物选择一次后连点不重复领取，后续考核刷新与读档始终排除", function()
    local snapshot = Fixture({}, 0):Snapshot()
    snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
    snapshot.target, snapshot.relicDraft = Game.GetTarget(2), true
    snapshot.relicRefreshes = 1
    snapshot.options = { "juicer" }
    local game = Game.Restore(snapshot)
    assert(game:Choose(1) and game.relics.juicer and game.round == 6)
    local acquired = game:Snapshot()
    assert(not game:Choose(1), "选择完成后的连点必须拒绝")
    assert(Equal(acquired, game:Snapshot()), "重复点击不得改变回合、遗物、刷新次数或RNG")

    snapshot = Game.Restore(acquired):Snapshot()
    snapshot.phase, snapshot.round, snapshot.stage = "draft", 10, 3
    snapshot.target, snapshot.relicDraft, snapshot.refreshes = Game.GetTarget(3), true, 12
    snapshot.relicRefreshes, snapshot.refreshUsed = 1, false
    game = Game.Restore(snapshot)
    game.options = game:_RelicDraftOptions()
    for remaining = 1, 0, -1 do
        local seen = {}
        for _, id in ipairs(game.options) do
            assert(not game.relics[id] and not seen[id], "后续候选不能包含已拥有或组内重复遗物")
            seen[id] = true
        end
        assert(#game.options == 3 and game.relics.juicer, "新考核有三个未拥有候选且保留已选遗物")
        game = Game.Restore(game:Snapshot())
        Close(game.refreshes, 12, "遗物免费刷新不扣物品余额")
        assert(game.refreshUsed == (remaining == 0), "读档保留本组遗物免费次数")
        if remaining > 0 then assert(game:DraftRefresh()) end
    end
end)

Test("过时的已拥有遗物候选原子拒绝，读档拒绝已有或同组重复候选", function()
    local snapshot = Fixture({}, 0):Snapshot()
    snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
    snapshot.target, snapshot.relicDraft = Game.GetTarget(2), true
    snapshot.relicRefreshes = 1
    snapshot.options = { "juicer" }
    local game = Game.Restore(snapshot)
    -- 模拟候选生成后所有权已变化：提交端仍须复核，不能靠候选界面防重。
    game.relics.juicer = true
    game.juicerValue = 17
    local before = game:Snapshot()
    assert(not game:Choose(1), "过时的已拥有候选不得再次领取")
    assert(Equal(before, game:Snapshot()), "拒绝不得重置效果状态、推进回合或消耗刷新/RNG")

    snapshot = before
    assert(not pcall(Game.Restore, snapshot), "已拥有遗物不得通过存档重新成为候选")
    snapshot.relics = {}
    snapshot.options = { "juicer", "juicer" }
    assert(not pcall(Game.Restore, snapshot), "存档中的同组重复遗物必须拒绝")
end)

Test("遗物只剩一两件时不重复补足，全部拥有后跳过遗物选择", function()
    for remaining = 1, 2 do
        local snapshot = Fixture({}, 0):Snapshot()
        snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
        snapshot.target, snapshot.pendingRelicDraft = Game.GetTarget(2), true
        for _, def in ipairs(Relics.list) do snapshot.relics[def.id] = true end
        snapshot.relics.juicer = nil
        if remaining == 2 then snapshot.relics.lucky_charm = nil end
        local game = Game.Restore(snapshot)
        game:_EnterRelicDraft()
        assert(game.relicDraft and #game.options == remaining, "候选不足三件时只显示实际剩余数量")
        local seen = {}
        for _, id in ipairs(game.options) do
            assert(not game.relics[id] and not seen[id], "剩余候选不能用已拥有或重复遗物补足")
            seen[id] = true
        end
        assert(game:Choose(1))
        if remaining == 2 then
            game.phase = "draft"
            game:_EnterRelicDraft()
            assert(#game.options == 1 and not game.relics[game.options[1]])
            assert(game:Choose(1))
        end
        local round, refreshes = game.round, game.refreshes
        local rngState = game:Snapshot().rngState
        game.phase = "draft"
        game:_EnterRelicDraft()
        assert(game.phase == "prepare" and game.round == round + 1 and #game.options == 0
            and not game.relicDraft and not game.pendingRelicDraft, "全部拥有后平稳推进回合")
        Close(game.refreshes, refreshes)
        assert(game:Snapshot().rngState == rngState, "空遗物池不得消耗随机状态")
    end
end)

Test("令牌49不判定、达到50成功转化保身份与有效价值", function()
    local game = Fixture({ "gambler" })
    game.relics.gambling_token = true
    local gambler = Item(game, 1)
    gambler.permBonus = 49
    assert(game:Start())
    local done = RandomSequence(game, {})
    game:Step(0)
    assert(gambler.id == "gambler" and not gambler.tokenAttempted)
    done()
    -- 阈值基于当前有效价值，而非只看永久加值。
    gambler.permBonus, gambler.bonus, gambler.mult, gambler.permMult = 20, 5, 1, 2
    done = RandomSequence(game, { 1 })
    local events = {}
    assert(RelicEffects.CheckGamblingToken(game, gambler, events))
    done()
    assert(game:Get(1) == gambler and gambler.id == "gambling_god" and gambler.location == "bottle")
    Close(gambler.permBonus, 50)
    Close(gambler.permMult, 1, "转化清旧永久倍率，避免重复乘算")
    Close(game:_Value(gambler), 58, "赌神基础8叠加转化前50")
    assert(#Events(events, "transform", 1) == 1 and not gambler.tokenAttempted)
    Identity(game)
end)

Test("令牌四等签仅一签成功精确25%、每次请求分母4且失败不重试", function()
    local successes = 0
    for ticket=1,4 do
        local game = Fixture({"gambler"})
        game.relics.gambling_token = true
        local gambler = Item(game,1)
        gambler.permBonus = 50
        local calls = 0
        rawset(game,"_RandomInt",function(_,maximum)
            calls = calls+1
            assert(maximum == 4 and calls == 1, "令牌必须1/4且不重复抽签")
            return ticket
        end)
        local transformed = RelicEffects.CheckGamblingToken(game,gambler,{})
        assert(transformed == (ticket == 1) and calls == 1)
        if transformed then successes=successes+1
        else
            assert(gambler.tokenAttempted and gambler.id == "gambler")
            assert(not RelicEffects.CheckGamblingToken(game,gambler,{}) and calls == 1)
        end
    end
    assert(successes == 1 and Relics.byId.gambling_token.effect:find("25%%"))
end)

Test("令牌失败锁定、回合保留、严格归零才刷新", function()
    local game = Fixture({ "gambler" })
    game.relics.gambling_token = true
    local gambler = Item(game, 1)
    gambler.permBonus = 50
    assert(game:Start())
    local done = RandomSequence(game, { 2 })
    game:Step(0)
    assert(gambler.id == "gambler" and gambler.tokenAttempted)
    game:Step(0)
    Finish(game)
    assert(gambler.tokenAttempted, "Cleanup不得自动刷新失败标记")
    done()
    local restored = Game.Restore(game:Snapshot())
    assert(Item(restored, 1).tokenAttempted, "失败标记必须持久化")
    assert(game:Skip() and game:Start())
    done = RandomSequence(game, {})
    for _, value in ipairs({ 49, -1, 50 }) do
        gambler.permBonus = value
        game:Step(0)
        assert(gambler.id == "gambler" and gambler.tokenAttempted, "非零值不得重新尝试")
    end
    gambler.permBonus = 0
    game:Step(0)
    assert(not gambler.tokenAttempted, "严格归零刷新")
    done()
    gambler.permBonus = 50
    done = RandomSequence(game, { 1 })
    game:Step(0)
    done()
    assert(gambler.id == "gambling_god")
end)

Test("令牌投1先结算再归零、不抢先转化", function()
    local game = Fixture({ "gambler", "die_d4" })
    game.relics.gambling_token = true
    Item(game, 1).permBonus = 49
    local done = RandomSequence(game, { 2, 1 }) -- 开局骰子2；赌徒重投1；不应调用令牌概率。
    assert(game:Start())
    local before = game.roundScore
    local events = game:Step(1, { pairs = { { 1, 2 } } })
    done()
    Close(Events(events, "score", 1)[1].value, 50)
    Close(game.roundScore - before, 51)
    Close(game:_Value(Item(game, 1)), 0)
    assert(Item(game, 1).id == "gambler" and not Item(game, 1).tokenAttempted)
    assert(#Events(events, "transform", 1) == 0)
end)

Test("令牌最大点旧收益完成后转化、不按赌神补结算", function()
    local game = Fixture({ "gambler", "die_d4", "die_d6" })
    game.relics.gambling_token = true
    Item(game, 1).permBonus = 49
    local done = RandomSequence(game, { 2, 2, 4, 1 })
    assert(game:Start())
    local before = game.roundScore
    local events = game:Step(1, { pairs = { { 1, 2 }, { 1, 3 } } })
    done()
    Close(game.roundScore - before, 54, "骰子4＋旧赌徒50，不补赌神58")
    assert(#Events(events, "score", 1) == 1)
    Close(Events(events, "score", 1)[1].value, 50)
    assert(Item(game, 1).id == "gambling_god" and Item(game, 1).rerolled[2] == 1)
    assert(Item(game, 1).rerolled[3] == nil, "转化终止原赌徒的邻居批次")
    local scoreIndex, transformIndex = 0, 0
    for index, event in ipairs(events) do
        if event.uid == 1 and event.kind == "score" then scoreIndex = index end
        if event.uid == 1 and event.kind == "transform" then transformIndex = index end
    end
    assert(scoreIndex > 0 and scoreIndex < transformIndex)
end)

Test("令牌配再来一把成功后保重投配额且终止连续投", function()
    local game = Fixture({ "gambler", "die_d4" })
    game.relics.gambling_token, game.relics.one_more_round = true, true
    Item(game, 1).permBonus = 49
    local done = RandomSequence(game, { 2, 2, 1 })
    assert(game:Start())
    local before = game.roundScore
    game:Step(1, { pairs = { { 1, 2 } } })
    assert(Item(game, 1).id == "gambling_god" and Item(game, 1).rerolled[2] == 1)
    Close(game.roundScore - before, 2, "非最大点只结骰子，不补投")
    game:Step(1, { pairs = { { 1, 2 } } })
    Close(game.roundScore - before, 2, "转化后的赌神也不能再投已用骰子")
    done()
end)

Test("令牌投1可刷新旧失败标记、下一投才能再次判定", function()
    local game = Fixture({ "gambler", "die_d4", "die_d6" })
    game.relics.gambling_token = true
    Item(game, 1).permBonus, Item(game, 1).tokenAttempted = 70, true
    local done = RandomSequence(game, { 2, 2, 1 })
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 2 } } })
    done()
    assert(not Item(game, 1).tokenAttempted and Item(game, 1).id == "gambler")
    Item(game, 1).permBonus = 49
    done = RandomSequence(game, { 2, 2 })
    game:Step(1, { pairs = { { 1, 3 } } })
    done()
    assert(Item(game, 1).tokenAttempted and Item(game, 1).id == "gambler")
end)

Test("令牌无遗物或非赌徒不判定、不消耗随机数", function()
    local game = Fixture({ "gambler", "gambling_god", "student" })
    for _, item in ipairs(game.deck) do item.permBonus = 100 end
    assert(game:Start())
    local done = RandomSequence(game, {})
    game:Step(0)
    assert(Item(game, 1).id == "gambler" and not Item(game, 1).tokenAttempted)
    game.relics.gambling_token = true
    assert(not RelicEffects.CheckGamblingToken(game, Item(game, 2), {}))
    assert(not RelicEffects.CheckGamblingToken(game, Item(game, 3), {}))
    done()
end)

Test("幸运符不增加零基础垃圾桶且不抹历史负永久值", function()
    local game = Fixture({ "trash_can", "credit_card", "apple" })
    Item(game, 1).permBonus, Item(game, 2).permBonus = -3, -4
    Close(game:_Value(Item(game, 1)), -3)
    game.relics.lucky_charm = true
    Close(game:_Value(Item(game, 1)), -3, "垃圾桶基础0不加值，历史-3保留")
    Close(game:_Value(Item(game, 2)), 11, "信用卡历史扣值不追溯翻转")
    Close(game:_Value(Item(game, 3)), 2, "正价值物品不改变")
    Close(Items.byId.trash_can.base, 0, "不改共享定义")
end)

Test("幸运符信用卡结算后永久加1、不增加本次金币", function()
    local game = Fixture({ "credit_card" })
    Item(game, 1).permBonus = -4
    game.relics.lucky_charm = true
    assert(game:Start())
    local events = Finish(game)
    Close(game.lastRoundScore, 11)
    Close(Item(game, 1).permBonus, -3)
    Close(Events(events, "score", 1)[1].value, 11)
    local restored = Game.Restore(game:Snapshot())
    Close(restored:_Value(Item(restored, 1)), 12)
end)

Test("幸运符小偷双方加值但零值目标仍不可偷", function()
    local game = Fixture({ "thief", "student", "gambler" })
    game.relics.lucky_charm = true
    assert(game:Start())
    game:Step(0, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(Item(game, 1).permBonus, 1)
    Close(Item(game, 2).permBonus, 1)
    Close(Item(game, 3).permBonus, 0, "幸运符不移除可偷价值>0的条件")
    -- 与金盘洗手叠加仍各+1，不翻倍；金盘洗手自己允许零值目标。
    local washed = Fixture({ "thief", "gambler" })
    washed.relics.lucky_charm, washed.relics.wash_hands = true, true
    assert(washed:Start())
    washed:Step(0, { pairs = { { 1, 2 } } })
    Close(Item(washed, 1).permBonus, 1)
    Close(Item(washed, 2).permBonus, 1)
end)

Test("幸运符不反转冷却缩短与体积缩小", function()
    local game = Fixture({ "glutton", "fitness_coach" })
    game.relics.lucky_charm, game.relics.thief_handbook = true, true
    Close(game:CooldownOf("thief"), 5)
    Item(game, 1).scale = 1.5
    assert(game:Start())
    for sample = 0, 200 do
        game:Step(0, { positions = { [1] = { x = sample * .5, y = 2 } } })
    end
    Close(Item(game, 1).scale, 1.3, "体积缩小不是价值减号")
    Close(Item(game, 2).permBonus, 1, "幸运符不翻倍或取消教练每次真实缩小的永久+1")
end)

Test("炒蛋秘籍总10次、前9次原实例重生第10次弃牌", function()
    local game = Fixture({ "tomato_egg" })
    game.relics.scramble_recipe = true
    assert(game:Start())
    local dish = Item(game, 1)
    for count = 1, 10 do
        local events = game:Consume(1)
        assert(game:Get(1) == dish and dish.counter == count)
        assert(dish.location == (count < 10 and "bottle" or "discard"))
        assert(#Events(events, count < 10 and "respawn" or "remove", 1) == 1)
        assert(#game.discard == (count < 10 and 0 or 1))
        Identity(game)
    end
    assert(#game:Consume(1) == 0 and dish.counter == 10, "第11次不能再次消耗")
end)

Test("炒蛋旧计数跨回合读档延续、获得秘籍不重置计数", function()
    local game = Fixture({ "tomato_egg" })
    Item(game, 1).counter = 4
    game.relics.scramble_recipe = true
    assert(game:Start())
    game:Consume(1)
    Finish(game)
    local restored = Game.Restore(game:Snapshot())
    assert(Item(restored, 1).counter == 5 and restored:Skip() and restored:Start())
    for count = 6, 10 do
        restored:Consume(1)
        assert(Item(restored, 1).counter == count)
        assert(Item(restored, 1).location == (count < 10 and "bottle" or "discard"))
    end
end)

Test("追杀从已有合法人类中选目标、不生成新实例", function()
    local game = Fixture({ "killer", "police", "teacher", "student", "apple" }, 3)
    game.relics.jungle_hunt, game.relics.teach_all = true, true
    local before = #game:AllInstances()
    local done = RandomSequence(game, { 1 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    done()
    assert(RelicEffects.HuntTarget(game) == 4, "可选牌库中的学生，排除警察/杀手/受保护老师/非人类")
    assert(#game:AllInstances() == before, "追杀刷新不是生成一个人类")
    local state = game:Snapshot()
    local restored = Game.Restore(state)
    assert(RelicEffects.HuntTarget(restored) == 4 and restored:Snapshot().rngState == state.rngState,
        "读档保稳定目标，不重新抽签")
end)

Test("追杀目标稳定、重抽不换目标、无候选使用0", function()
    local game = Fixture({ "student", "doctor" })
    game.relics.jungle_hunt = true
    local done = RandomSequence(game, { 2 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    done()
    assert(RelicEffects.HuntTarget(game) == 2)
    done = RandomSequence(game, {})
    RelicEffects.Maintain(game)
    RelicEffects.Maintain(game)
    done()
    rawset(game, "_RandomInt", nil)
    assert(game:Reroll() and RelicEffects.HuntTarget(game) == 2)
    local empty = Fixture({ "killer", "police", "apple" })
    empty.relics.jungle_hunt = true
    done = RandomSequence(empty, {})
    RelicEffects.OnAcquire(empty, "jungle_hunt")
    assert(RelicEffects.HuntTarget(empty) == 0)
    done()
end)

Test("杀手击杀追杀目标永久倍率连乘、即时金币不乘杀手倍率", function()
    local game = Fixture({ "killer", "doctor", "soldier" })
    game.relics.jungle_hunt = true
    local done = RandomSequence(game, { 1, 1 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    assert(game:Start())
    local events = game:Step(1, { pairs = { { 1, 2 }, { 1, 3 } } })
    done()
    Close(Item(game, 1).permMult, 2.25)
    Close(game:_Value(Item(game, 1)), 9, "追杀当步有效价值")
    Close(game.roundScore, 70, "两次目标价值5×7，不乘杀手永久倍率")
    assert(#Events(events, "score", 1) == 2 and RelicEffects.HuntTarget(game) == 0)
    Finish(game)
    Close(Item(game, 1).permMult, 2.25, "Cleanup保永久倍率")
    Close(Item(game, 1).mult, 1)
    local restored = Game.Restore(game:Snapshot())
    Close(restored:_Value(Item(restored, 1)), 9, "追杀读档保留有效价值")
    assert(restored:Skip() and restored:Start())
    restored:Step(0)
    Close(restored:_Value(Item(restored, 1)), 9, "Continuous不得抹除永久倍率")
end)

Test("追杀非目标被杀不奖励、普通消耗目标只刷新不奖励", function()
    local game = Fixture({ "killer", "doctor", "student" })
    game.relics.jungle_hunt = true
    local done = RandomSequence(game, { 1 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 3 } } })
    Close(Item(game, 1).permMult, 1)
    assert(RelicEffects.HuntTarget(game) == 2)
    game:Consume(2)
    assert(RelicEffects.HuntTarget(game) == 0)
    Close(Item(game, 1).permMult, 1)
    done()
end)

Test("追杀目标转成不可击杀类型刷新、警察击杀不奖励", function()
    local game = Fixture({ "police", "gambler", "doctor" })
    game.relics.jungle_hunt = true
    local done = RandomSequence(game, { 1, 1 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 2 } } })
    done()
    assert(Item(game, 2).location == "discard" and RelicEffects.HuntTarget(game) == 3)
    Close(Item(game, 1).permMult, 1)
    game:_Transform(Item(game, 3), "police", {})
    assert(RelicEffects.HuntTarget(game) == 0)
end)

Test("追杀获得有教无类时重新筛掉原老师目标", function()
    local game = Fixture({ "teacher", "doctor" })
    game.relics.jungle_hunt = true
    local done = RandomSequence(game, { 1, 1 })
    RelicEffects.OnAcquire(game, "jungle_hunt")
    assert(RelicEffects.HuntTarget(game) == 1)
    game.relics.teach_all = true
    RelicEffects.OnAcquire(game, "teach_all")
    assert(RelicEffects.HuntTarget(game) == 2)
    done()
end)

Test("榨汁消耗四种半果、保留普通最终金币且不重复累计", function()
    local game = Fixture({ "apple_half", "banana_half", "orange_half", "cherry_half", "apple", "egg" })
    game.relics.juicer = true
    Item(game, 1).permBonus = 3
    Item(game, 4).permMult = 1.5
    game.juicerValue = 7
    assert(game:Start())
    local events = Finish(game, { bottom = { [3] = true } })
    -- 半果当前价值：4＋1＋(1+3)＋2×1.5=12；半樱桃普通结算2次。
    Close(RelicEffects.JuicerValue(game), 19)
    Close(game.lastRoundScore, 4 + 1 + 4 + 6 + 2 + 3)
    assert(#game.discard == 4 and #game.deck == 2)
    for uid = 1, 4 do
        assert(Item(game, uid).location == "discard")
        assert(#Events(events, "remove", uid) == 1 and #Events(events, "score", uid) >= 1)
    end
    assert(Item(game, 5).location == "deck" and Item(game, 6).location == "deck")
    Close(Item(game, 3).bonus, 0, "榨取后才Cleanup弃牌临时值")
    local value = game.juicerValue
    assert(#game:Finish() == 0)
    Close(game.juicerValue, value)
    Game.Restore(game:Snapshot())
end)

Test("榨汁在死灵返还后、不取牌库与旧弃牌半果", function()
    local game = Fixture({ "necromancer", "apple_half", "banana_half", "orange_half" }, 3)
    game.relics.juicer = true
    local done = RandomSequence(game, { 1 })
    assert(game:Start())
    game:Consume(2)
    local events = Finish(game)
    done()
    assert(Item(game, 2).location == "deck", "死灵先返还原弃牌半果")
    assert(Item(game, 3).location == "discard", "最终仍在瓶内的半果被榨取，死灵不能再返还")
    assert(Item(game, 4).location == "deck", "未入瓶半果不榨取")
    Close(game.juicerValue, 1)
    Close(game.lastRoundScore, 6, "死灵5＋瓶内半香蕉1")
    assert(#Events(events, "score", 2) == 0 and #Events(events, "score", 4) == 0)
end)

Test("榨汁采用最终厨师与水果商人倍率、Cleanup前累计", function()
    local game = Fixture({ "apple_half", "chef", "fruit_merchant" })
    game.relics.juicer = true
    Item(game, 1).permBonus, Item(game, 1).permMult = 2, 1.5
    assert(game:Start())
    local events = Finish(game, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(game.juicerValue, 18, "(基础1+永久2)×厨师2×商人2×永久1.5")
    Close(Events(events, "score", 1)[1].value, 18)
    Close(Item(game, 1).mult, 1)
    Close(Item(game, 1).permMult, 1.5)
end)

Test("榨汁仍走转基因消耗钩子、新完整果不追溯结算", function()
    local game = Fixture({ "apple_half" })
    game.relics.juicer, game.relics.gm_fruit = true, true
    local done = RandomSequence(game, { 1, 1, 51 }) -- 概率成功、苹果、瓶顶横坐标。
    assert(game:Start())
    local events = game:Finish()
    done()
    Close(game.juicerValue, 1)
    Close(game.roundScore, 1, "新生成苹果不加入已经完成的全体结算")
    assert(#Events(events, "spawn") == 1 and Item(game, 2).id == "apple")
    rawset(game, "_RandomInt", nil)
    game:RevealStep(2)
    assert(Item(game, 2).location == "deck" and not Item(game, 2).temporary)
    Identity(game)
end)

Test("榨汁无遗物不消耗、跨回合累加保留", function()
    local ordinary = Fixture({ "apple_half" })
    assert(ordinary:Start())
    Finish(ordinary)
    assert(Item(ordinary, 1).location == "deck")
    Close(RelicEffects.JuicerValue(ordinary), 0)
    local game = Fixture({ "apple_half" })
    game.relics.juicer = true
    game.juicerValue = 2.5
    assert(game:Start())
    Finish(game)
    Close(game.juicerValue, 4, "原累计2.5向上取整3，再加入半苹果价值1")
    assert(game:Skip())
    assert(game:_Create("banana_half"))
    game.revision = game.revision + 1
    Identity(game)
    assert(game:Reroll() and game:Start())
    Finish(game)
    Close(game.juicerValue, 5, "第二回合只增加半香蕉价值1")
    assert(#game.discard == 1, "上一回合弃牌已清除，不再次榨取")
end)

Test("使用榨汁机生成永久食物果汁到牌库、清值一次", function()
    local game = Fixture({ "apple" })
    game.relics.juicer, game.relics.small_savings = true, true
    game.juicerValue = 12.5
    local before = game:Snapshot()
    local ok, message, juice = RelicEffects.UseJuicer(game)
    assert(ok and type(message) == "string" and #message > 0 and juice)
    assert(juice.id == "juice" and juice.location == "deck" and not juice.temporary)
    assert(game:Get(juice.uid) == juice and #game.deck == #before.deck + 1)
    assert(Equal(game.drawn, before.drawn), "生成果汁不补进当前瓶内")
    Close(game:_Value(juice), 13)
    Close(game.juicerValue, 0)
    Close(game.score - before.score, 1, "正常添加触发积少成多一次")
    assert(Items.HasTag("juice", "食物") and #Items.byId.juice.tags == 1)
    assert(not Items.HasTag("juice", "水果") and Items.byId.juice.pool == false)
    local after = game:Snapshot()
    ok, message, juice = RelicEffects.UseJuicer(game)
    assert(not ok and type(message) == "string" and juice == nil)
    assert(Equal(after, game:Snapshot()), "重复点击不得生成或修改状态")
    local restored = Game.Restore(after)
    Close(restored:_Value(Item(restored, after.nextUid - 1)), 13)
    Identity(restored)
end)

Test("榨汁机无遗物空值及运行结算展示阶段拒绝且原子保值", function()
    local game = Fixture({ "apple" })
    game.juicerValue = 9
    local before = game:Snapshot()
    local ok, message, item = RelicEffects.UseJuicer(game)
    assert(not ok and type(message) == "string" and item == nil and Equal(before, game:Snapshot()))
    game.relics.juicer = true
    for _, value in ipairs({ 0, -1 }) do
        game.juicerValue = value
        before = game:Snapshot()
        ok, message, item = RelicEffects.UseJuicer(game)
        assert(not ok and item == nil and type(message) == "string" and Equal(before, game:Snapshot()))
    end
    game.juicerValue = 9
    assert(game:Start())
    for _, phase in ipairs({ "running", "settle", "reveal" }) do
        assert(game.phase == phase)
        local count, revision = #game.deck, game.revision
        ok, message, item = RelicEffects.UseJuicer(game)
        assert(not ok and item == nil and type(message) == "string")
        Close(game.juicerValue, 9)
        assert(#game.deck == count and game.revision == revision)
        if phase == "running" then game:Step(10) elseif phase == "settle" then game:SettleStep(2) end
    end
end)

Test("新字段旧金额迁移后prepare与draft往返保值、不共享快照对象", function()
    local game = Fixture({ "killer", "gambler", "doctor", "juice" })
    game.relics.jungle_hunt, game.relics.gambling_token, game.relics.juicer = true, true, true
    game.huntTargetUid, game.juicerValue = 3, 17.25
    Item(game, 1).permMult, Item(game, 2).tokenAttempted = 2.25, true
    Item(game, 2).permBonus, Item(game, 4).permBonus = 55, 7.5
    local snapshot = game:Snapshot()
    local restored = Game.Restore(snapshot)
    local expected = game:Snapshot()
    expected.juicerValue = 18
    assert(Equal(expected, restored:Snapshot()), "旧榨汁累计取整，价值组成项和其他prepare字段保持一致")
    Close(Item(restored, 4).permBonus, 7.5, "旧永久价值加数不能单独取整")
    Close(Item(restored, 1).permMult, 2.25, "小数永久倍率不迁移为整数")
    restored.juicerValue, Item(restored, 1).permMult = 3, 1.5
    Close(snapshot.juicerValue, 17.25)
    Close(snapshot.instances[1].permMult, 2.25)
    Close(snapshot.instances[4].permBonus, 7.5, "恢复不得改写源快照金额")
    game = Game.Restore(snapshot)
    assert(Equal(expected, game:Snapshot()))
    assert(game:Start())
    Finish(game)
    snapshot = game:Snapshot()
    restored = Game.Restore(snapshot)
    assert(Equal(snapshot, restored:Snapshot()) and restored.huntTargetUid == 3)
    assert(Item(restored, 2).tokenAttempted)
end)

Test("v2旧档缺四字段兼容、不重抽目标或消耗RNG", function()
    local game = Fixture({ "killer", "gambler", "doctor" })
    for _, def in ipairs(Relics.list) do game.relics[def.id] = true end
    Item(game, 2).permBonus = 55
    local snapshot = game:Snapshot() --[[@as any]]
    snapshot.juicerValue, snapshot.huntTargetUid = nil, nil
    for _, saved in ipairs(snapshot.instances) do saved.permMult, saved.tokenAttempted = nil, nil end
    local restored = Game.Restore(snapshot)
    assert(restored:Snapshot().version == 2 and restored:Snapshot().rngState == snapshot.rngState)
    Close(restored.juicerValue, 0)
    Close(restored.huntTargetUid, 0)
    for _, item in ipairs(restored:AllInstances()) do
        Close(item.permMult, 1)
        assert(item.tokenAttempted == false)
    end
    assert(Item(restored, 2).id == "gambler", "Restore不运行令牌效果")
    assert(restored.relics.juicer and restored.relics.jungle_hunt)
end)

Test("运行结算展示回滚四字段与RNG到回合前", function()
    local game = Fixture({ "killer", "doctor", "apple_half", "gambler" })
    game.relics.jungle_hunt, game.relics.juicer, game.relics.gambling_token = true, true, true
    game.huntTargetUid, game.juicerValue = 2, 3
    Item(game, 1).permMult, Item(game, 4).permBonus = 1.5, 50
    local before = game:Snapshot()
    assert(game:Start())
    local done = RandomSequence(game, { 1, 2 }) -- 击杀后刷新到唯一赌徒；再判令牌失败。
    game:Step(1, { pairs = { { 1, 2 } } })
    done()
    rawset(game, "_RandomInt", nil)
    assert(Item(game, 4).tokenAttempted and game.huntTargetUid == 4)
    Close(Item(game, 1).permMult, 2.25)
    assert(Equal(before, game:Snapshot()), "running回滚全部新状态")
    game:Step(9)
    assert(game.phase == "settle" and Equal(before, game:Snapshot()))
    game:SettleStep(2)
    assert(game.phase == "reveal" and Equal(before, game:Snapshot()))
    Close(game.juicerValue, 4, "运行时确实发生榨取，快照仍回滚")
    local restored = Game.Restore(game:Snapshot())
    assert(Equal(before, restored:Snapshot()) and not Item(restored, 4).tokenAttempted)
end)

-- 每个无效值独立创建新快照，禁止前一次损坏掩盖后一次校验缺失。
---@param field string
---@param values any[]
---@param instanceField boolean?
local function RejectValues(field, values, instanceField)
    for _, value in ipairs(values) do
        local snapshot = Fixture({ "gambler" }):Snapshot() --[[@as any]]
        local target = instanceField and snapshot.instances[1] or snapshot
        target[field] = value
        assert(not pcall(Game.Restore, snapshot), "损坏字段未拒绝：" .. field .. "=" .. tostring(value))
    end
end

Test("读档拒绝非法juicerValue类型与非有限值", function()
    RejectValues("juicerValue", { false, true, "12", {}, function() end, 0 / 0, math.huge, -math.huge })
    -- 有限旧金额仍合法；向正无穷迁移，不改变负数方向或放宽类型校验。
    local snapshot = Fixture({}):Snapshot()
    snapshot.juicerValue = -2.5
    Close(Game.Restore(snapshot).juicerValue, -2)
end)

Test("读档拒绝非法permMult而保留合法小数永久倍率", function()
    RejectValues("permMult", { false, true, "1.5", {}, function() end, -1, 0, .99,
        0 / 0, math.huge, -math.huge }, true)
    local snapshot = Fixture({ "killer" }):Snapshot()
    snapshot.instances[1].permMult = 1.5 ^ 7
    Close(Item(Game.Restore(snapshot), 1).permMult, 1.5 ^ 7)
end)

Test("读档拒绝非boolean令牌标记、不把false当缺失", function()
    RejectValues("tokenAttempted", { 0, 1, "false", "true", {}, function() end,
        0 / 0, math.huge }, true)
    for _, value in ipairs({ false, true }) do
        local snapshot = Fixture({ "gambler" }):Snapshot()
        snapshot.instances[1].tokenAttempted = value
        assert(Item(Game.Restore(snapshot), 1).tokenAttempted == value)
    end
end)

Test("读档拒绝非法追杀UID类型范围及失效引用", function()
    RejectValues("huntTargetUid", { false, true, "1", {}, function() end, -1, .5,
        2147483647, 9007199254740992, 0 / 0, math.huge, -math.huge })
    for _, id in ipairs({ "apple", "police", "killer", "teacher" }) do
        local snapshot = Fixture({ id }):Snapshot()
        snapshot.relics.jungle_hunt, snapshot.relics.teach_all = true, true
        snapshot.huntTargetUid = 1
        assert(not pcall(Game.Restore, snapshot), "非法目标类型未拒绝：" .. id)
    end
    local missing = Fixture({ "doctor" }):Snapshot()
    missing.relics.jungle_hunt, missing.huntTargetUid = true, 2
    assert(not pcall(Game.Restore, missing), "不存在的目标UID必须拒绝")
    local noRelic = Fixture({ "doctor" }):Snapshot()
    noRelic.huntTargetUid = 1
    assert(not pcall(Game.Restore, noRelic), "没有遗物不能持有非零追杀目标")
    local discarded = Fixture({ "doctor", "apple" })
    assert(discarded:Start())
    discarded:Consume(1)
    Finish(discarded)
    local bad = discarded:Snapshot()
    bad.relics.jungle_hunt, bad.huntTargetUid = true, 1
    assert(not pcall(Game.Restore, bad), "弃牌不能继续作为追杀目标")
end)

Test("持久化弃牌同样校验新字段、倍率与失败标记保留", function()
    local game = Fixture({ "gambler", "apple" })
    Item(game, 1).permMult, Item(game, 1).tokenAttempted = 1.5, true
    Item(game, 1).permBonus = 60
    assert(game:Start())
    game:Consume(1)
    Finish(game)
    local snapshot = game:Snapshot()
    local restored = Game.Restore(snapshot)
    assert(Item(restored, 1).location == "discard" and Item(restored, 1).tokenAttempted)
    Close(Item(restored, 1).permMult, 1.5)
    local invalid = game:Snapshot() --[[@as any]]
    invalid.instances[1].permMult = 0
    assert(not pcall(Game.Restore, invalid))
    invalid = game:Snapshot() --[[@as any]]
    invalid.instances[1].tokenAttempted = "true"
    assert(not pcall(Game.Restore, invalid))
end)

Test("提前Finish同样使用最终接触倍率和半橘贴底加成", function()
    local game = Fixture({ "orange_half", "chef", "fruit_merchant" })
    game.relics.juicer = true
    assert(game:Start())
    -- 不先Step同步接触，直接覆盖GM/提前结束的真实入口。
    local events = game:Finish({ bottom = { [1] = true }, pairs = { { 1, 2 }, { 1, 3 } } })
    Close(Events(events, "score", 1)[1].value, 16, "(基础1+贴底3)×厨师2×商人2")
    Close(game.juicerValue, 16, "提前结束不能遗漏最终接触价值")
end)

Test("榨汁与最终金币统一向上取整且保留零负方向", function()
    local game = Fixture({ "apple_half", "banana_half", "cherry_half" })
    game.relics.juicer = true
    game.juicerValue = 10
    Item(game, 1).permBonus, Item(game, 2).permBonus = -1, -3.5
    assert(game:Start())
    local events = Finish(game)
    Close(game.juicerValue, 10, "原累计10+0-2+2=10，半樱桃只累计本体一次")
    assert(#game.discard == 3 and #game.deck == 0)
    Close(game.lastRoundScore, 2, "零值0、负值-2.5向上取整-2、半樱桃两次共4")
    assert(#Events(events, "remove") == 3)
end)

Test("生成果汁UID耗尽失败不清累计值或发积少成多收益", function()
    local game = Fixture({})
    game.relics.juicer, game.relics.small_savings = true, true
    game.juicerValue = 8
    local snapshot = game:Snapshot()
    snapshot.nextUid = 2147483647
    local restored = Game.Restore(snapshot)
    local before = restored:Snapshot()
    local ok, message, item = RelicEffects.UseJuicer(restored)
    assert(not ok and type(message) == "string" and item == nil)
    assert(Equal(before, restored:Snapshot()), "分配失败必须原子拒绝")
end)

Test("令牌临时值消失严格归零时在Cleanup刷新失败标记", function()
    local game = Fixture({ "gambler" })
    game.relics.gambling_token = true
    assert(game:Start())
    Item(game, 1).bonus = 50
    local done = RandomSequence(game, { 2 })
    game:Step(0)
    assert(Item(game, 1).tokenAttempted)
    Finish(game)
    done()
    Close(game:_Value(Item(game, 1)), 0)
    assert(not Item(game, 1).tokenAttempted, "清临时值后的严格归零同样刷新")
    Game.Restore(game:Snapshot())
end)

Test("五遗物真实三选一选择立即获得并进入下一回合", function()
    for _, id in ipairs({ "gambling_token", "lucky_charm", "scramble_recipe", "jungle_hunt", "juicer" }) do
        local snapshot = Fixture({ "gambler", "doctor" }, 0):Snapshot()
        -- 正常考核后的遗物选择不禁普通；五种既有遗物均走同一真实入口。
        snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
        snapshot.target, snapshot.relicDraft, snapshot.pendingRelicDraft = Game.GetTarget(2), true, true
        snapshot.relicRefreshes = 1
        snapshot.options = { id }
        local game = Game.Restore(snapshot)
        assert(game:Choose(1) and game.relics[id] and game.phase == "prepare" and game.round == 6)
        local expected = id == "scramble_recipe" and 4 or (id == "jungle_hunt" and 3 or 2)
        assert(#game.deck == expected and #game.discard == 0, "遗物本身不占牌库，仅明确附赠新增物品")
        for _, item in ipairs(game:AllInstances()) do assert(item.id ~= "juice", "获得榨汁机不能凭空赠果汁") end
        if id == "scramble_recipe" then
            assert(Item(game,3).id == "egg" and Item(game,4).id == "tomato", "炒蛋秘籍只赠鸡蛋和西红柿")
        elseif id == "jungle_hunt" then
            assert(Item(game,3).id == "killer" and #game:AllInstances() == 3, "追杀仅附赠1杀手，不另生成目标人类")
            local target = Item(game, RelicEffects.HuntTarget(game))
            assert(target.uid <= 2 and (target.id == "gambler" or target.id == "doctor"), "只从原有人类建立目标")
        end
        Identity(game)
        Game.Restore(game:Snapshot())
    end
end)

Test("旧v2遗物候选字段兼容且缺省新状态可继续选择", function()
    local snapshot = Fixture({ "doctor" }, 0):Snapshot() --[[@as any]]
    snapshot.phase, snapshot.round, snapshot.stage = "draft", 5, 2
    snapshot.target, snapshot.relicDraft, snapshot.pendingRelicDraft = Game.GetTarget(2), true, true
    snapshot.options = { "gambling_token", "jungle_hunt", "juicer" }
    snapshot.juicerValue, snapshot.huntTargetUid, snapshot.rulesVersion = nil, nil, nil
    snapshot.relicRefreshes = nil
    snapshot.instances[1].permMult, snapshot.instances[1].tokenAttempted = nil, nil
    local game = Game.Restore(snapshot)
    assert(Equal(game.options, {"gambling_token", "jungle_hunt", "juicer"}) and game.relicDraft,
        "旧普通遗物候选保留原顺序，不套用仅物品的过滤规则")
    local restored = Game.Restore(game:Snapshot())
    assert(Equal(restored.options, game.options), "迁到rules8再读档同样保留普通遗物")
    assert(game:Choose(2) and game.relics.jungle_hunt and RelicEffects.HuntTarget(game) == 1)
    assert(restored:Choose(1) and restored.relics.gambling_token and restored.round == 6)
    Close(game.juicerValue, 0)
end)

---@return integer passed 汇总所有独立案例；失败时抛出真实已执行数和具体用例。
function Tests.Run()
    local passed = 0
    ---@type string[]
    local failures = {}
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        if ok then passed = passed + 1 else failures[#failures + 1] = case.name .. "：" .. tostring(message) end
    end
    assert(#failures == 0, "Bottle.RelicTests " .. passed .. "/" .. #cases
        .. " 通过\n" .. table.concat(failures, "\n"))
    return passed
end

return Tests
