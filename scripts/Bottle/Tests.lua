-- Bottle 规则回归测试（V0.4 新结算模型）：纯 Lua assert，不启动引擎，不写文件，不输出日志。
-- 在资源根 scripts 的环境中：require("Bottle.Tests").Run()
-- 标准 Lua：package.path = "/workspace/scripts/?.lua;" .. package.path
-- 覆盖：93件数据表完整性、新主流程（抽20/摇10/结算2秒/考核/三选一概率表）、
-- 初始4物品、价值临时性、冷却回合重置、香蕉生命周期、橘子贴底、小球碰壁、
-- V0.4 效果（合成/切割/消灭/偷取/催熟/消耗/结算/重生）、遗物三选一与遗物效果、
-- 快照回滚与存档校验、ShakeMotion 物理二、Physics 接触计数（无引擎 mock）。

local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Game = require("Bottle.Game")
local ShakeMotion = require("Bottle.ShakeMotion")
local Physics = require("Bottle.Physics")
local Tests = {}

---@param actual number
---@param expected number
---@param message string?
local function Close(actual, expected, message)
    if math.abs(actual - expected) >= 1e-7 then
        error(string.format("%s期望 %g，实际 %g", message and (message .. "：") or "", expected, actual))
    end
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

---@param events GameEvent[]
---@param kind string
---@param uid integer?
---@return GameEvent[]
local function Events(events, kind, uid)
    ---@type GameEvent[]
    local result = {}
    for _, event in ipairs(events) do
        if event.kind == kind and (not uid or event.uid == uid) then
            result[#result + 1] = event
        end
    end
    return result
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid)
    local item = game:Get(uid)
    assert(item, "测试缺少实例 " .. tostring(uid))
    return item
end

-- 通过公开快照构造确定夹具，不改规则模块，不伪造引擎对象。
---@param ids string[]
---@param bottleCount integer?
---@param seed number?
---@return BottleGame
local function Fixture(ids, bottleCount, seed)
    local snapshot = Game.New(seed or 7):Snapshot()
    snapshot.instances, snapshot.deck, snapshot.discard, snapshot.drawn = {}, {}, {}, {}
    snapshot.nextUid = #ids + 1
    local count = bottleCount or #ids
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

---@param game BottleGame
local function IdentityInvariant(game)
    ---@type table<number, boolean>
    local seen = {}
    for _, item in ipairs(game.deck) do
        assert(not seen[item.uid], "deck uid 重复")
        assert(game:Get(item.uid) == item, "deck 复制了实例")
        assert(item.location == "deck" or item.location == "bottle"
            or (item.location == "discard" and item.temporary), "deck 持有错误状态")
        seen[item.uid] = true
    end
    ---@type table<number, boolean>
    local discarded = {}
    for _, item in ipairs(game.discard) do
        assert(not discarded[item.uid] and item.location == "discard", "弃牌重复/位置错误")
        assert(game:Get(item.uid) == item, "弃牌复制了实例")
        discarded[item.uid] = true
    end
    for _, item in ipairs(game:BottleItems()) do assert(seen[item.uid], "瓶中物品不在持有牌库") end
end

--- 推进 reveal 直到进入下一阶段：展示时长 = 浮字队列时长 + 2秒停顿（按件数动态）。
---@param game BottleGame
local function FinishReveal(game)
    local guard = 0
    while game.phase == "reveal" do
        guard = guard + 1
        assert(guard < 30, "结算展示未在有限步内完成")
        game:RevealStep(1)
    end
end

--- 推进结算（2秒下落）并完成结算展示（队列 + 2秒 reveal），返回 settle 产出的 score/transform 事件。
--- reveal 阶段不产事件；需要分步断言结算下落行为的测试请直接调 SettleStep/RevealStep。
---@param game BottleGame
---@param contacts BottleContacts?
---@return GameEvent[]
local function SettleAndReveal(game, contacts)
    local events = game:SettleStep(2, contacts)
    if game.phase == "reveal" then FinishReveal(game) end
    return events
end

---@class BottleRuleTest
---@field name string
---@field run fun()
---@type BottleRuleTest[]
local cases = {}

---@param name string
---@param run fun()
local function Test(name, run)
    cases[#cases + 1] = { name = name, run = run }
end

Test("93件物品表与数据一致性", function()
    assert(#Items.list == 93 and #Items.rarityNames == 5 and #Items.rarityColors == 5)
    ---@type table<string, boolean>
    local seen = {}
    for index, def in ipairs(Items.list) do
        assert(def.numberId == index, "numberId 与列表顺序一致")
        assert(not seen[def.id], "物品 id 重复：" .. def.id)
        seen[def.id] = true
        assert(def.rarity >= 1 and def.rarity <= 5, "稀有度越界：" .. def.id)
        assert(def.radius > 0, "半径必须为正：" .. def.id)
        assert(type(def.effect) == "string" and #def.effect > 0, "缺少描述：" .. def.id)
        if def.cooldown > 0 then
            assert(def.cooldown >= Items.Settings.minCooldown, "冷却低于下限：" .. def.id)
        end
        -- 描述中的 [[id]] 引用必须存在。
        for ref in def.effect:gmatch("%[%[([%w_]+)%]%]") do
            assert(Items.byId[ref], "描述引用未知物品：" .. ref .. " ← " .. def.id)
        end
    end
    -- 最新源表93件全部实装，原1..70编号保留；juice移至87，71为chick。
    for _, def in ipairs(Items.list) do
        assert(def.implemented, "物品未实装：" .. def.id)
        assert(not def.pool or def.implemented, "未实装物品不能进卡池：" .. def.id)
    end
    -- 新表插入位与末尾位：#22 半个樱桃、#68-70 士兵/医生/鸡蛋。
    assert(Items.byNumber[22].id == "cherry_half", "半个樱桃位于 #22")
    assert(Items.byNumber[48].id == "ball", "小球位于 #48")
    assert(Items.byNumber[68].id == "soldier" and Items.byNumber[69].id == "doctor"
        and Items.byNumber[70].id == "egg", "原末尾三件编号不变")
    assert(Items.byNumber[71].id == "chick", "小鸡位于源表 #71")
    assert(Items.byNumber[87].id == "juice", "果汁保持字符串ID并位于 #87")
    -- 卡池屏蔽（源表第8列=1及追加生成物juice）不进三选一。
    for _, id in ipairs({
        "apple_half", "banana_half", "orange_half", "fruit_ninja", "cherry_half",
        "tomato_egg", "coin_4", "coin_8", "coin_16", "coin_32", "coin_64", "coin_128",
        "coin_256", "coin_512", "coin_1024", "coin_2048", "rotten_banana",
        "banana_peel", "juice", "poop", "golden_poop", "diamond_poop", "rainbow_poop",
        "discus", "wool", "sweater",
    }) do
        assert(Items.byId[id].pool == false, "屏蔽物品不应进卡池：" .. id)
    end
    assert(Items.byId.laurel.pool, "最新源表桂冠应进入卡池")
    assert(Items.byId.apple.base == 2 and Items.byId.banana.base == 2
        and Items.byId.orange.base == 2 and Items.byId.ball.base == 1)
    assert(Items.byId.ball.cooldown == 3 and Items.byId.ball.trigger == "wall")
    assert(Items.HasTag("apple", "水果") and Items.HasTag("apple", "食物")
        and Items.HasTag("rotten_banana", "垃圾") and not Items.HasTag("ball", "水果"))
    assert(Items.HasTag("seed", "农作物"), "种子农作物tag")
    assert(Items.HasTag("tomato", "食物") and Items.HasTag("egg", "食物"), "炒蛋材料tag")
    assert(Items.Recipe("slipper_left", "slipper_right") == "fruit_ninja", "拖鞋合成")
    assert(Items.Recipe("egg", "tomato") == "tomato_egg", "炒蛋合成")
    assert(Items.byId.die_d4.tags and Items.byId.die_d4.tags[1] == "骰子", "骰子tag归位")
    assert(Items.byId.monkey.tags and Items.byId.monkey.tags[1] == "动物", "猴子tag归位")
    assert(Items.byId.fruit_farmer.name == "果农" and Items.byId.fruit_merchant.name == "水果商人")
end)

Test("三选一概率表匹配docs/概率.txt", function()
    assert(Equal(Items.DraftWeights(1), { 10000, 0, 0, 0, 0 }))
    assert(Equal(Items.DraftWeights(2), { 9000, 1000, 0, 0, 0 }))
    assert(Equal(Items.DraftWeights(3), { 7750, 2000, 250, 0, 0 }))
    assert(Equal(Items.DraftWeights(4), { 7250, 2500, 250, 0, 0 }))
    assert(Equal(Items.DraftWeights(5), { 6500, 3000, 375, 100, 25 }))
    assert(Equal(Items.DraftWeights(99), { 6500, 3000, 375, 100, 25 }), "第5次及以后沿用最后一行")
    for stage = 1, 9 do
        local total = 0
        for _, weight in ipairs(Items.DraftWeights(stage)) do total = total + weight end
        assert(total == 10000, "概率权重合计必须为100%")
    end
end)

Test("初始牌库为小羊小草苹果小球各1件", function()
    local game = Game.New(123)
    assert(game.phase == "prepare" and #game.deck == 4 and #game.drawn == 4)
    local starterIds = { "sheep", "grass", "apple", "ball" }
    for i, item in ipairs(game.deck) do
        assert(item.id == starterIds[i], "初始物品按小羊、小草、苹果、小球创建")
    end
    for _, item in ipairs(game:BottleItems()) do
        assert(item.location == "bottle" and item.bonus == 0 and item.permBonus == 0)
    end
    IdentityInvariant(game)
end)

Test("抽取上限20件与不放回重抽", function()
    ---@type string[]
    local ids = {}
    for i = 1, 25 do ids[i] = i % 2 == 1 and "apple" or "orange" end
    local snapshot = Fixture(ids, 0):Snapshot()
    snapshot.phase = "draft"
    snapshot.options = {}
    local game = Game.Restore(snapshot)
    assert(game:Skip() and #game.drawn == 20 and #game.deck == 25, "最多抽20件")
    ---@type table<number, boolean>
    local drawn = {}
    for _, uid in ipairs(game.drawn) do assert(not drawn[uid], "重复抽取"); drawn[uid] = true end
    assert(game:Reroll() and not game:Reroll(), "重抽限一次")
    assert(#game.drawn == 20, "重抽后仍抽20件")
    IdentityInvariant(game)
    -- 牌库不足20件时全部入瓶。
    local small = Fixture({ "apple", "banana" })
    assert(#small.drawn == 2 and #small:BottleItems() == 2, "牌库不足时全部入瓶")
end)

Test("考核目标沿用40/80/140…×1.3序列", function()
    local expected = { 40, 80, 140, 220, 320, 450, 600, 780 }
    for stage, value in ipairs(expected) do
        assert(Game.GetTarget(stage) == value, "阶段" .. stage .. "目标错误")
    end
    assert(Game.GetTarget(9) == math.ceil(780 * 1.3 / 10) * 10, "第9阶段按1.3倍向上取整到10")
    assert(Game.GetTarget(10) == math.ceil(Game.GetTarget(9) * 1.3 / 10) * 10)
    assert(not pcall(Game.GetTarget, 0) and not pcall(Game.GetTarget, 1001))
end)

Test("摇晃10秒内不产金币，只执行效果", function()
    local game = Fixture({ "apple", "ball" })
    assert(game:Start())
    local events = game:Step(10, { wall = { [2] = true } })
    assert(#Events(events, "score") == 0, "摇晃阶段不直接产金币")
    Close(game.roundScore, 0)
    assert(game.phase == "settle", "10秒后自动进入结算阶段")
    Close(game.elapsed, 10)
    Close(game.settleElapsed, 0)
    assert(Item(game, 2).bonus >= 1, "小球碰撞瓶子已加临时价值")
end)

Test("结算阶段2秒下落且不再执行非结算效果", function()
    local game = Fixture({ "ball" })
    assert(game:Start())
    game:Step(10, { wall = { [1] = true } })
    assert(game.phase == "settle")
    local bonusBefore = Item(game, 1).bonus
    -- 结算阶段仍提供 wall 接触：小球不得继续加价值。
    local events = game:SettleStep(1, { wall = { [1] = true } })
    assert(game.phase == "settle" and #events == 0)
    Close(Item(game, 1).bonus, bonusBefore, "结算下落期间不执行非结算效果")
    Close(game.settleElapsed, 1)
    events = game:SettleStep(1, { wall = { [1] = true } })
    assert(game.phase == "reveal", "2秒后进入结算展示")
    FinishReveal(game)
    assert(game.phase == "draft", "结算展示后进入三选一")
    local scores = Events(events, "score", 1)
    assert(#scores == 1 and scores[1].value == 1 + bonusBefore, "按当前价值一次性结算")
    assert(Close(game.roundScore, 1 + bonusBefore) == nil)
end)

Test("结算后价值增益清零、永久增益保留、冷却重置", function()
    local game = Fixture({ "orange", "ball" })
    assert(game:Start())
    game:Step(4, { bottom = { [1] = true } })
    Close(Item(game, 1).bonus, 2, "橘子贴底持有+2")
    Item(game, 2).permBonus = 5 -- 模拟“永久+N”物品（如墓碑）
    game:Step(6, { bottom = { [1] = true }, wall = { [2] = true } })
    assert(game.phase == "settle")
    SettleAndReveal(game, { bottom = { [1] = true } })
    assert(game.phase == "draft")
    -- 结算完成后、新回合开始前：临时价值在 _CleanupRound 清零。
    Close(Item(game, 1).bonus, 0, "临时价值回合末清零")
    Close(Item(game, 2).bonus, 0, "小球临时加成清零")
    Close(Item(game, 2).permBonus, 5, "永久增益保留")
    Close(Item(game, 2).mult, 1, "倍率复位")
    assert(game:Skip())
    Close(Item(game, 1).remaining, 0, "无冷却物品保持0")
    Close(Item(game, 2).remaining, 3, "准备期显示入瓶完整间隔")
    assert(game:Start())
    Close(Item(game, 2).remaining, 0, "触发冷却在回合开始重置为就绪")
    IdentityInvariant(game)
end)

Test("橘子贴底加成为持续状态：离开即清除", function()
    local game = Fixture({ "orange" })
    assert(game:Start())
    local events = game:Step(0, { bottom = { [1] = true } })
    Close(Item(game, 1).bonus, 2)
    assert(#Events(events, "buff", 1) == 1)
    -- 持续贴住：每步同步但不重复叠加。
    events = game:Step(1, { bottom = { [1] = true } })
    Close(Item(game, 1).bonus, 2, "贴住期间保持+2不叠加")
    assert(#Events(events, "buff") == 0, "状态未变不发事件")
    -- 离开瓶底：加成清除。
    events = game:Step(1, {})
    Close(Item(game, 1).bonus, 0, "离开瓶底清除加成")
    assert(#Events(events, "buff", 1) == 1)
    -- 再次贴住：重新+2。
    game:Step(1, { bottom = { [1] = true } })
    Close(Item(game, 1).bonus, 2, "再次贴底重新获得加成")
end)

Test("小球碰撞瓶子+1价值且受3秒冷却", function()
    local game = Fixture({ "ball" })
    assert(game:Start())
    Close(Item(game, 1).remaining, 0, "开始时触发冷却归零就绪")
    local events = game:Step(0, { wall = { [1] = true } })
    Close(Item(game, 1).bonus, 1, "开局接触立即触发+1")
    assert(#Events(events, "buff", 1) == 1)
    Close(Item(game, 1).remaining, 3, "触发后重新进入3秒冷却")
    -- 冷却内持续接触不再触发。
    events = game:Step(2, { wall = { [1] = true } })
    Close(Item(game, 1).bonus, 1, "冷却中不重复加价值")
    -- 冷却结束后仍接触则再次触发。
    events = game:Step(1, { wall = { [1] = true } })
    Close(Item(game, 1).bonus, 2, "冷却就绪后再次触发")
    assert(#Events(events, "buff", 1) == 1)
    Close(Item(game, 1).remaining, 3)
    game:Step(2.99, {wall={[1]=true}})
    Close(Item(game, 1).bonus, 2)
    game:Step(.01, {wall={[1]=true}})
    Close(Item(game, 1).bonus, 3, "第二次完整冷却后再触发")
    -- 物品互撞不算“碰撞瓶子”。
    local two = Fixture({ "ball", "ball" })
    assert(two:Start())
    two:Step(5, { pairs = { { 1, 2 } } })
    Close(Item(two, 1).bonus, 0, "互撞不加价值")
    Close(Item(two, 2).bonus, 0)
end)

Test("香蕉3回合腐烂：入瓶才计数，结算时转化", function()
    local game = Fixture({ "banana" })
    Close(Item(game, 1).bottleRounds, 0)
    assert(game:Start(), "第1回合入瓶")
    Close(Item(game, 1).bottleRounds, 1)
    game:Step(10)
    SettleAndReveal(game)
    assert(Item(game, 1).id == "banana", "第1回合结算后未腐烂")
    assert(game:Skip() and game:Start())
    Close(Item(game, 1).bottleRounds, 2)
    game:Step(10)
    SettleAndReveal(game)
    assert(Item(game, 1).id == "banana", "第2回合结算后未腐烂")
    assert(game:Skip() and game:Start())
    Close(Item(game, 1).bottleRounds, 3)
    local events = game:Step(10)
    assert(game.phase == "settle")
    events = SettleAndReveal(game)
    assert(Item(game, 1).id == "rotten_banana", "第3回合结算后腐烂")
    assert(#Events(events, "transform", 1) == 1)
    Close(Item(game, 1).bonus, 0)
    Close(game:_Value(Item(game, 1)), 0, "腐烂香蕉价值0")
    -- 牌库中未入瓶的香蕉不计数。
    local deckGame = Fixture({ "banana", "banana" }, 1)
    assert(deckGame:Start())
    Close(Item(deckGame, 1).bottleRounds, 1)
    Close(Item(deckGame, 2).bottleRounds, 0, "未入瓶不记录回合")
end)

Test("香蕉被消耗变为香蕉皮并留在瓶中", function()
    local game = Fixture({ "banana" })
    assert(game:Start())
    local events = game:Consume(1)
    assert(Item(game, 1).id == "banana_peel", "被消耗变为香蕉皮")
    assert(Item(game, 1).location == "bottle", "香蕉皮留在瓶中不进弃牌堆")
    assert(#game.discard == 0 and #Events(events, "transform", 1) == 1)
    Close(game:_Value(Item(game, 1)), 1, "香蕉皮基础价值1")
    IdentityInvariant(game)
    -- 非运行/结算阶段拒绝消耗。
    local idle = Fixture({ "banana" })
    assert(#idle:Consume(1) == 0 and Item(idle, 1).id == "banana")
end)

Test("消耗进弃牌堆且消耗不等于移除", function()
    local game = Fixture({ "apple", "orange" })
    assert(game:Start())
    local events = game:Consume(1)
    assert(Item(game, 1).location == "discard" and #game.discard == 1)
    assert(#Events(events, "remove", 1) == 1)
    assert(game:Get(1) ~= nil, "消耗的实例仍可查询")
    game:Step(10, { bottom = { [2] = true } })
    assert(game.phase == "settle", "10秒后进入结算阶段")
    game:SettleStep(1, { bottom = { [2] = true } })
    assert(game.phase == "settle", "下落1秒后仍在结算阶段")
    game:SettleStep(1, { bottom = { [2] = true } })
    -- 永久消耗不进下一回合。
    assert(game.phase == "reveal")
    FinishReveal(game)
    assert(game.phase == "draft")
    assert(game:Get(1) == nil or Item(game, 1).location == "discard", "回合末仍在弃牌")
    assert(game:Skip())
    assert(game:Get(1) == nil, "永久消耗下回合清空")
    assert(#game.deck == 1 and Item(game, 2).location ~= "consumed")
    IdentityInvariant(game)
end)

Test("三选一按考核阶段概率且候选不重复", function()
    local game = Fixture({ "apple" })
    assert(game:Start())
    game:Step(10)
    SettleAndReveal(game)
    assert(game.phase == "draft")
    assert(#game.options >= 1 and #game.options <= 3)
    ---@type table<string, boolean>
    local seen = {}
    for _, id in ipairs(game.options) do
        assert(not seen[id], "候选类型不重复")
        seen[id] = true
        local def = Items.byId[id]
        assert(def.pool and def.implemented, "候选必须已实装并进卡池")
        assert(def.rarity == 1, "首次考核前非考核回合只出普通")
    end
    -- 首次考核前的非考核回合仍按100%普通；第5回合考核候选排除普通。
    for seed = 1, 30 do
        local g = Game.New(seed)
        for round = 1, 5 do
            assert(g:Start())
            g:Step(10)
            SettleAndReveal(g)
            if g.phase == "over" then break end
            for _, id in ipairs(g.options) do
                local rarity = Items.byId[id].rarity
                assert((round < 5 and rarity == 1) or (round == 5 and rarity > 1),
                    "普通概率及考核排除规则：" .. id)
            end
            if not g:Skip() then break end
        end
    end
end)

Test("考核5概率表按可用稀有度回退且候选稳定", function()
    -- 当前卡池只有已实装的4件普通物品；stage5 权重必须回退到可用稀有度，
    -- 候选不为空、全部合法。高稀有度实装后同一机制自然出高稀有度。
    local snapshot = Game.New(3):Snapshot()
    snapshot.phase = "draft"
    snapshot.round = 21
    snapshot.stage = 5
    snapshot.target = Game.GetTarget(5)
    snapshot.score = 100
    snapshot.options = {}
    snapshot.drawn = {}
    for _, instance in ipairs(snapshot.instances) do instance.location = "deck" end
    local game = Game.Restore(snapshot)
    assert(game:DraftRefresh(), "可以刷新")
    assert(#game.options >= 1, "stage5 卡池回退后仍有候选")
    ---@type table<string, boolean>
    local seen = {}
    for _, id in ipairs(game.options) do
        local def = Items.byId[id]
        assert(def.pool and def.implemented, "候选必须已实装")
        assert(not seen[id], "候选不重复")
        seen[id] = true
    end
    assert(not game:DraftRefresh(), "刷新只能用一次")
    -- 概率表行数为5，超出沿用最后一行；权重合计恒为10000。
    assert(#Items.draftWeights == 5)
end)

Test("三选一选择与跳过进入下一回合", function()
    local game = Fixture({ "apple" })
    assert(game:Start())
    game:Step(10)
    SettleAndReveal(game)
    assert(game.phase == "draft" and #game.options > 0)
    local chosen = game.options[1]
    assert(game:Choose(1))
    assert(game.phase == "prepare" and game.round == 2)
    assert(#game.deck == 2, "选择后牌库+1")
    local found = false
    for _, item in ipairs(game.deck) do
        if item.id == chosen then found = true end
    end
    assert(found, "选择的物品加入牌库")
    assert(not game:Choose(1), "prepare 阶段不能再选择")
    assert(not game:Skip(), "prepare 阶段不能跳过")
    -- 跳过不加牌。
    local skipGame = Fixture({ "apple" })
    assert(skipGame:Start())
    skipGame:Step(10)
    SettleAndReveal(skipGame)
    assert(skipGame:Skip() and #skipGame.deck == 1 and skipGame.round == 2)
    IdentityInvariant(skipGame)
end)

Test("每5回合考核扣款与不足终局", function()
    local game = Fixture({ "apple" })
    -- 手工推进4个回合到第5回合考核。
    for round = 1, 5 do
        assert(game:Start(), "第" .. round .. "回合开始")
        local firstUid = assert(game.drawn[1], "缺少抽取实例")
        Item(game, firstUid).permBonus = 100 -- 保证余额充足
        game:Step(10)
        SettleAndReveal(game)
        if round < 5 then
            assert(game.phase == "draft")
            assert(game:Skip())
        end
    end
    assert(game.phase == "draft", "第5回合达标后进入三选一")
    assert(game.stage == 2 and game.target == 80, "考核后进入阶段2目标80")
    Close(game.score, 5 * 102 - 40, "5回合各得102，扣除40")
    -- 余额不足：终局。
    local poor = Fixture({ "apple" })
    for round = 1, 4 do
        assert(poor:Start())
        poor:Step(10)
        SettleAndReveal(poor)
        assert(poor:Skip())
    end
    assert(poor:Start())
    poor:Step(10)
    SettleAndReveal(poor)
    assert(poor.phase == "over", "余额不足考核目标则结束")
    Close(poor.score, 5 * 2, "终局不扣款")
    assert(#poor.options == 0, "终局不进入三选一")
    assert(poor.lastResult:find("考核") ~= nil)
    IdentityInvariant(poor)
end)

Test("考核回合提前Finish跳过下落直接结算", function()
    local game = Fixture({ "apple", "orange" })
    assert(game:Start())
    game:Step(4, { bottom = { [2] = true } })
    assert(game.phase == "running")
    local events = game:Finish({ bottom = { [2] = true } })
    assert(game.phase == "reveal", "Finish后进入结算展示")
    FinishReveal(game)
    assert(game.phase == "draft", "第5回合外直接进三选一")
    Close(game.roundScore, 2 + 4, "苹果2+橘子(2+2)=6")
    assert(#Events(events, "score") == 2)
    -- 重复 Finish 无副作用。
    assert(#game:Finish() == 0)
end)

Test("运行中快照回滚保护", function()
    local game = Fixture({ "ball" })
    assert(game:Start())
    local before = game:Snapshot()
    assert(before.phase == "prepare" and #before.drawn == 1, "运行中返回回合前快照")
    game:Step(5, { wall = { [1] = true } })
    local mid = game:Snapshot()
    assert(Equal(before, mid), "摇晃中快照稳定回退到回合前")
    game:Step(5, { wall = { [1] = true } })
    assert(game.phase == "settle")
    local settleSnapshot = game:Snapshot()
    assert(Equal(before, settleSnapshot), "结算中同样回退到回合前")
    SettleAndReveal(game)
    assert(game.phase == "draft")
    local draft = game:Snapshot()
    assert(draft.phase == "draft" and draft.score > 0, "draft 保存真实进度")
end)

Test("存档校验拒绝损坏数据", function()
    local snapshot = Game.New(1):Snapshot()
    assert(snapshot.version == 2)
    -- v1 旧档不兼容。
    local legacy = Game.New(1):Snapshot() --[[@as any]]
    legacy.version = 1
    assert(not pcall(function() Game.Restore(legacy) end), "旧档必须被拒绝")
    local malformed = Game.New(1):Snapshot() --[[@as any]]
    malformed.instances[1].id = "unknown_item"
    assert(not pcall(function() Game.Restore(malformed) end))
    malformed = Game.New(1):Snapshot() --[[@as any]]
    malformed.instances[1].bonus = 3
    assert(not pcall(function() Game.Restore(malformed) end), "持久化阶段不得残留临时价值")
    malformed = Game.New(1):Snapshot() --[[@as any]]
    malformed.instances[1].mult = 2
    assert(not pcall(function() Game.Restore(malformed) end))
    malformed = Game.New(1):Snapshot() --[[@as any]]
    malformed.stage = 3
    assert(not pcall(function() Game.Restore(malformed) end), "阶段与回合必须一致")
    malformed = Game.New(1):Snapshot() --[[@as any]]
    malformed.drawn = {}
    assert(not pcall(function() Game.Restore(malformed) end), "prepare 瓶中实例必须列入抽取")
    -- 合法快照可以恢复并继续。
    local restored = Game.Restore(Game.New(42):Snapshot())
    assert(#restored.deck == 4 and restored:Start())
end)

Test("GM添加按实装状态过滤", function()
    local game = Game.New(5)
    local ok = game:GmAddItem("apple")
    assert(ok and #game.deck == 5)
    ok = game:GmAddItem(48) -- 小球（V0.4 70件表中位于 #48）
    assert(ok and #game.deck == 6)
    ok = game:GmAddItem("ninja")
    assert(not ok, "旧物品 id 已不存在")
    ok = game:GmAddItem("cherry")
    assert(ok and #game.deck == 7, "樱桃 V0.4 已实装，允许添加")
    ok = game:GmAddItem("gambler")
    assert(ok and #game.deck == 8, "赌徒当前已实装，允许添加")
    ok = game:GmAddItem(34) -- 赌徒
    assert(ok and #game.deck == 9, "已实装数字编号允许添加")
    game:Start()
    ok = game:GmAddItem("apple")
    assert(not ok, "摇晃中拒绝GM")
    game:Step(10)
    ok = game:GmAddItem("apple")
    assert(not ok, "结算中拒绝GM")
end)

Test("瓶中上限100件", function()
    assert(Items.Settings.bottleLimit == 100)
    -- 上限在运行中由生成效果逼近（抽取一次最多20件），直接测 _EnterBottle 边界。
    local game = Fixture({ "apple" })
    assert(game:Start())
    for _ = 2, 100 do game:_Create("apple") end
    for uid = 2, 100 do game:_EnterBottle(Item(game, uid)) end
    assert(#game:BottleItems() == 100, "恰好达到上限")
    game:_Create("apple")
    assert(not pcall(function() game:_EnterBottle(Item(game, 101)) end),
        "第101件入瓶必须被拒绝")
end)

Test("物理fixture导出全部内壁/底/顶且引用计数独立", function()
    -- 仅调用 Contact/Contacts/_ForgetContacts；不调用 Physics.New，不启动引擎。
    local world = {}
    local itemA, itemB = {name = "item_1", rotation2D = 0}, {name = "item_2", rotation2D = 0}
    local walls = {}
    for _, name in ipairs({"floor", "top", "wall_left", "wall_right",
        "shoulder_left", "shoulder_right", "neck_left", "neck_right"}) do
        walls[#walls + 1] = {name = name}
    end
    local physics = setmetatable({
        world = world, bodies = {[1] = {uid=1,node = itemA}, [2] = {uid=2,node = itemB}},
        _walls = walls, _pairs = {}, _bottom = {}, _top = {}, _wall = {}, _side = {},
        expansion = require("Bottle.ExpansionPhysics").New(), _disposed = false,
        _impactContacts = {}, _impacts = {}, clock = 0,
    }, Physics) --[[@as any]]
    local function contact(a, b, begin, eventWorld)
        local function pointer(value)
            return {GetPtr = function() return value end}
        end
        physics:Contact({World = pointer(eventWorld or world), NodeA = pointer(a), NodeB = pointer(b)}, begin)
    end
    for _, wall in ipairs(walls) do
        contact(itemA, wall, true)
        contact(wall, itemA, true) -- 第二个fixture接触
        local state = physics:Contacts()
        assert(state.wall[1] == true and not state.wall[2] and #state.pairs == 0)
        assert((state.bottom[1] == true) == (wall.name == "floor"))
        assert((state.top[1] == true) == (wall.name == "top"))
        contact(itemA, wall, false)
        assert(physics:Contacts().wall[1] == true, "结束一个fixture不能清掉另一个")
        contact(wall, itemA, false)
        state = physics:Contacts()
        assert(not state.wall[1] and not state.bottom[1] and not state.top[1])
    end
    local floor, top, side = walls[1], walls[2], walls[3]
    contact(itemA, floor, true); contact(itemA, top, true); contact(itemA, side, true)
    contact(itemA, floor, false)
    assert(not physics:Contacts().bottom[1] and physics:Contacts().top[1] and physics:Contacts().wall[1])
    contact(itemA, top, false)
    assert(not physics:Contacts().top[1] and physics:Contacts().wall[1])
    contact(itemA, side, false)
    contact(itemA, itemB, true); contact(itemB, itemA, true)
    local state = physics:Contacts()
    assert(#state.pairs == 1 and state.pairs[1][1] == 1 and state.pairs[1][2] == 2 and not state.wall[1])
    contact(itemA, itemB, false)
    assert(#physics:Contacts().pairs == 1)
    contact(itemB, itemA, false)
    assert(#physics:Contacts().pairs == 0)
    contact(itemA, top, true, {}) -- 外部world事件忽略
    contact(itemA, {name = "top"}, true) -- 同名非瓶内壁忽略
    assert(not physics:Contacts().wall[1])
    contact(itemA, top, true); contact(itemA, itemB, true)
    physics:_ForgetContacts(1)
    assert(not physics:Contacts().wall[1] and not physics:Contacts().top[1] and #physics:Contacts().pairs == 0)
    local replacement = {name = "item_1", rotation2D = 0}
    physics.bodies[1].node = replacement
    contact(replacement, top, true)
    contact(itemA, top, false) -- 旧uid节点的迟到End不能清掉新节点接触
    assert(physics:Contacts().top[1])
end)

Test("物理二启动反向惯性/保持静止/换向/松手回中", function()
    local motion = ShakeMotion.New()
    motion:Move(.3, .2)
    Close(motion.targetX, 0) -- 未抓住瓶子时不会响应。
    motion:Begin()
    motion:Move(.3, .2)
    local ix, iy = motion:Step(1 / 60)
    assert(ix < 0 and iy < 0 and motion.x > 0 and motion.y > 0)
    Close(ix, -motion.vx * 1.8)
    for _ = 1, 90 do motion:Step(1 / 60) end
    Close(motion.x, .3)
    Close(motion.vx, 0)
    ix, iy = motion:Step(1 / 60)
    assert(math.abs(ix) + math.abs(iy) < 1e-7, "按住静止不会持续灌入能量")
    motion:Move(-.6, -.4)
    ix, iy = motion:Step(1 / 60)
    assert(ix > 0 and iy > 0, "左右/上下换向产生相反惯性")
    motion:End()
    for _ = 1, 90 do motion:Step(1 / 60) end
    Close(motion.x, 0)
    Close(motion.y, 0)
    Close(motion.vx, 0)
    motion:Begin()
    motion:Move(.2, 0)
    motion:Step(1 / 60)
    motion:End()
    local heldX, heldVx = motion.x, motion.vx
    motion:Begin()
    Close(motion.x, heldX); Close(motion.vx, heldVx)
    motion:Reset()
    ix, iy = motion:Step(1 / 60)
    Close(ix, 0)
    Close(iy, 0)
end)

Test("物理二输入合并/固定步一致和位移边界", function()
    local single, multiple = ShakeMotion.New(), ShakeMotion.New()
    single:Begin(); multiple:Begin()
    for i = 1, 180 do
        local delta = i <= 30 and .012 or (i <= 60 and -.024 or .002)
        single:Move(delta, delta * .5)
        for _ = 1, 8 do multiple:Move(delta / 8, delta / 16) end
        local ax, ay = single:Step(1 / 60)
        local bx, by = multiple:Step(1 / 60)
        Close(single.x, multiple.x); Close(single.y, multiple.y)
        Close(ax, bx); Close(ay, by)
        assert(math.abs(single.x) <= .53 and math.abs(single.y) <= .37)
    end
    single:Reset()
    single:Begin()
    single:Move(100, -100)
    Close(single.targetX, .52); Close(single.targetY, -.36)
    single:Move(-.3, .1)
    Close(single.targetX, .22); Close(single.targetY, -.26)
    single:Step(0)
    Close(single.x, 0)
    single:Move(0 / 0, 1)
    single:Move(math.huge, 1)
    Close(single.targetX, .22)
    for _ = 1, 120 do single:Step(1 / 30) end
    Close(single.x, .22); Close(single.y, -.26)
end)

Test("物理二非有限输入不改变手势/步进/体感状态", function()
    local motion = ShakeMotion.New()
    motion:Begin()
    motion:Move(.2, -.1)
    motion:Step(1 / 60)
    motion:Sensor(.2, -.4, 1 / 60)
    motion:Sensor(.3, -.2, 1 / 60)
    local function Snapshot()
        -- 用字符串快照，避免运行时错误的 NaN 比较让断言假通过。
        local values = {}
        for _, key in ipairs({ "targetX", "targetY", "x", "y", "vx", "vy",
            "sensorBaseX", "sensorBaseY", "sensorX", "sensorY", "holding", "sensorReady" }) do
            values[#values + 1] = tostring(motion[key])
        end
        return table.concat(values, ",")
    end
    local before = Snapshot()
    for _, invalid in ipairs({ 0 / 0, math.huge, -math.huge }) do
        motion:Move(invalid, 1)
        assert(Snapshot() == before)
        motion:Move(1, invalid)
        assert(Snapshot() == before)
        local x, y = motion:Step(invalid)
        assert(tostring(x) == tostring(0) and tostring(y) == tostring(0))
        assert(Snapshot() == before)
        motion:Sensor(invalid, 1, 1 / 60)
        assert(Snapshot() == before)
        motion:Sensor(1, invalid, 1 / 60)
        assert(Snapshot() == before)
    end
end)

Test("物理二体感滤除静态倾斜/摇晃有惯性/重置无残留", function()
    local motion = ShakeMotion.New()
    for _ = 1, 120 do motion:Sensor(.2, -.4, 1 / 60) end
    local x, y = motion:SensorImpulse(1 / 60)
    Close(x, 0); Close(y, 0)
    motion:Sensor(.8, -.4, 1 / 60)
    x, y = motion:SensorImpulse(1 / 60)
    assert(x < 0 and y == 0)
    for _ = 1, 300 do motion:Sensor(.8, -.4, 1 / 60) end
    x, y = motion:SensorImpulse(1 / 60)
    Close(x, 0); Close(y, 0)
    motion:Reset()
    x, y = motion:SensorImpulse(1 / 60)
    Close(x, 0); Close(y, 0)
end)

Test("体感断开/校准只清传感器，不打断手势", function()
    local motion = ShakeMotion.New()
    motion:Begin()
    motion:Move(.3, -.2)
    motion:Step(1 / 60)
    motion:Sensor(0, 0, 1 / 60)
    motion:Sensor(.8, .2, 1 / 60)
    local ix, iy = motion:SensorImpulse(1 / 60)
    assert(ix ~= 0 and iy ~= 0)
    local x, y, vx, vy = motion.x, motion.y, motion.vx, motion.vy
    motion:ResetSensor()
    ix, iy = motion:SensorImpulse(1 / 60)
    Close(ix, 0); Close(iy, 0)
    assert(not motion.sensorReady and motion.holding)
    Close(motion.targetX, .3); Close(motion.targetY, -.2)
    Close(motion.x, x); Close(motion.y, y)
    Close(motion.vx, vx); Close(motion.vy, vy)
    motion:Sensor(-.4, .3, 1 / 60)
    ix, iy = motion:SensorImpulse(1 / 60)
    Close(ix, 0); Close(iy, 0) -- 重新接通首样本只建立新基线。
end)

---@class BottleTestJsonCodec
---@field encode fun(value: table): string
---@field decode fun(value: string): BottleSnapshot

---------------------------------------------------------------- V0.4 效果与遗物

Test("合成优先：拖鞋合成水果忍者、鸡蛋西红柿合成炒蛋", function()
    -- 左右拖鞋接触合成水果忍者（在材料中点，产 merge 事件）。
    local game = Fixture({ "slipper_left", "slipper_right" })
    assert(game:Start())
    local events = game:Step(1, { pairs = { { 1, 2 } }, positions = {
        [1] = { x = -1, y = 1 }, [2] = { x = 1, y = 1 } } })
    local merges = Events(events, "merge")
    assert(#merges == 1, "生成一个合成事件")
    assert(merges[1].a and merges[1].b, "合成事件保留材料 uid")
    Close(merges[1].x, 0, "产物在两材料中点")
    local ninjaUid = merges[1].uid
    assert(Item(game, ninjaUid).id == "fruit_ninja", "产物是水果忍者")
    assert(Item(game, 1).location == "discard" and Item(game, 2).location == "discard",
        "两份材料被消耗")
    IdentityInvariant(game)
    -- 鸡蛋 + 西红柿合成西红柿炒蛋。
    local dish = Fixture({ "egg", "tomato" })
    assert(dish:Start())
    events = dish:Step(1, { pairs = { { 1, 2 } } })
    assert(#Events(events, "merge") == 1)
    local eggUid = Events(events, "merge")[1].uid
    assert(Item(dish, eggUid).id == "tomato_egg", "产物是西红柿炒蛋")
end)

Test("切割：小刀切水果、厨师产物+3、水果忍者永久+价值", function()
    -- 小刀：相邻完整水果切两份（源转化半份 + 新生一个半份）。
    local game = Fixture({ "knife", "apple" })
    assert(game:Start())
    game:Step(5, { pairs = { { 1, 2 } } })
    assert(Item(game, 2).id == "apple_half", "源苹果被切成半份")
    assert(Item(game, 3) and Item(game, 3).id == "apple_half", "新生第二个半份")
    assert(#game:BottleItems() == 3, "小刀仍在瓶中")
    -- 厨师：切割产物价值各永久+3。
    local chef = Fixture({ "chef", "apple" })
    assert(chef:Start())
    chef:Step(5, { pairs = { { 1, 2 } } })
    assert(Item(chef, 2).id == "apple_half" and Item(chef, 2).permBonus == 3, "源产物+3")
    assert(Item(chef, 3) and Item(chef, 3).permBonus == 3, "新生产物+3")
    -- 水果忍者：切全部相邻完整水果，自身永久+被切水果价值。
    local ninja = Fixture({ "fruit_ninja", "apple", "orange" })
    assert(ninja:Start())
    ninja:Step(5, { pairs = { { 1, 2 }, { 1, 3 } } })
    Close(Item(ninja, 1).permBonus, 2 + 2, "水果忍者永久+苹果2+橘子2")
    assert(Item(ninja, 2).id == "apple_half" and Item(ninja, 3).id == "orange_half")
end)

Test("消灭：警察×4、杀手×7、警察不被杀手消灭", function()
    local game = Fixture({ "police", "thief" })
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 2 } } })
    Close(game.roundScore, 1 * 4, "警察消灭小偷(价值1)得×4金币")
    assert(Item(game, 2).location == "discard", "小偷被消灭进弃牌")
    -- 杀手消灭相邻人类（学生）×7。
    local killer = Fixture({ "killer", "student" })
    assert(killer:Start())
    killer:Step(1, { pairs = { { 1, 2 } } })
    Close(killer.roundScore, 2 * 7, "杀手消灭学生(价值2)得×7金币")
    -- 杀手不消灭警察；相邻时反被警察消灭（警察消灭杀手得价值×4）。
    local safe = Fixture({ "killer", "police" })
    assert(safe:Start())
    safe:Step(1, { pairs = { { 1, 2 } } })
    Close(safe.roundScore, 4 * 4, "警察消灭杀手(价值4)得×4金币")
    assert(Item(safe, 2).location == "bottle", "警察不会被杀手消灭")
    assert(Item(safe, 1).location == "discard", "杀手被警察消灭")
end)

Test("小偷偷取相邻人类1点价值", function()
    local game = Fixture({ "thief", "student" })
    assert(game:Start())
    game:Step(0, { pairs = { { 1, 2 } } })
    Close(Item(game, 2).permBonus, -1, "被偷方永久-1")
    Close(Item(game, 1).permBonus, 1, "小偷永久+1")
    Close(game:_Value(Item(game, 2)), 1, "学生价值 2-1=1")
end)

Test("老师催熟相邻学生且不出负面职业", function()
    local game = Fixture({ "teacher", "student" })
    assert(game:Start())
    game:Step(1, { pairs = { { 1, 2 } } })
    local grown = Item(game, 2)
    assert(grown.id ~= "student", "学生已成长")
    assert(grown.id ~= "thief" and grown.id ~= "killer" and grown.id ~= "gambler",
        "老师催熟不出负面职业")
    Close(grown.permBonus, 2, "成长叠加当前价值2")
    Close(grown.settleCount, 0, "成长后结算计数清零")
end)

Test("垃圾桶/大胃王/食客消耗相邻物品", function()
    -- 垃圾桶消耗相邻垃圾，自身永久+1。
    local can = Fixture({ "trash_can", "banana_peel" })
    assert(can:Start())
    can:Step(2, { pairs = { { 1, 2 } } })
    Close(Item(can, 1).permBonus, 1, "垃圾桶永久+1")
    assert(Item(can, 2).location == "discard", "香蕉皮被消耗")
    -- 大胃王消耗食物，永久+1且体积+10%。
    local glutton = Fixture({ "glutton", "apple" })
    assert(glutton:Start())
    glutton:Step(1, { pairs = { { 1, 2 } } })
    Close(Item(glutton, 1).permBonus, 1, "大胃王永久+1")
    Close(Item(glutton, 1).scale, 1.1, "体积+10%")
    -- 食客消耗食物给×2金币，满5个自毁。
    local diner = Fixture({ "diner", "apple" })
    assert(diner:Start())
    diner:Step(1, { pairs = { { 1, 2 } } })
    Close(diner.roundScore, 2 * 2, "食客给苹果价值×2金币")
    Close(Item(diner, 1).counter, 1, "食客计数+1")
    -- 计数达5自毁。
    local full = Fixture({ "diner", "apple" })
    Item(full, 1).counter = 4
    assert(full:Start())
    full:Step(1, { pairs = { { 1, 2 } } })
    Close(Item(full, 1).counter, 5)
    assert(Item(full, 1).location == "discard", "食客吃满5个自毁")
end)

Test("结算效果：种子变植物、气球爆炸、学生成长、桂冠、樱桃、信用卡", function()
    -- 气球：体积达200%爆炸，其他物品价值×2。
    local pop = Fixture({ "balloon", "apple" })
    Item(pop, 1).scale = 1.95
    assert(pop:Start())
    pop:Step(10)
    SettleAndReveal(pop)
    assert(Item(pop, 1).location == "discard", "气球爆炸自毁")
    Close(pop.lastRoundScore, 2 * 2, "苹果被爆炸翻倍产4金币")
    -- 学生：结算5次后成长。
    local stu = Fixture({ "student" })
    Item(stu, 1).settleCount = 4
    assert(stu:Start())
    stu:Step(10)
    SettleAndReveal(stu)
    assert(Item(stu, 1).id ~= "student", "结算5次后成长")
    Close(Item(stu, 1).permBonus, 2, "成长叠加价值2")
    -- 桂冠：唯一最高价值×1.5，≥20再×1.5。
    local laurel = Fixture({ "laurel", "apple" })
    Item(laurel, 2).permBonus = 20 -- 苹果价值22为唯一最高
    assert(laurel:Start())
    laurel:Step(10)
    SettleAndReveal(laurel)
    Close(laurel.lastRoundScore, 50 + 8, "苹果22×2.25向上取整为50 + 桂冠8")
    -- 樱桃：结算再结算一次（共2次）。
    local cherry = Fixture({ "cherry" })
    assert(cherry:Start())
    cherry:Step(10)
    SettleAndReveal(cherry)
    Close(cherry.lastRoundScore, 3 * 2, "樱桃价值3结算2次")
    -- 信用卡：结算后价值永久-1。
    local card = Fixture({ "credit_card" })
    assert(card:Start())
    card:Step(10)
    SettleAndReveal(card)
    Close(card.lastRoundScore, 10, "信用卡首次结算产10")
    Close(Item(card, 1).permBonus, -1, "结算后永久-1")
    Close(card:_Value(Item(card, 1)), 9, "下次价值9")
    -- 种子：结算时50%变植物；跑多个种子确认转化会发生且只变为植物。
    local transformed = 0
    for seed = 1, 24 do
        local g = Fixture({ "seed" }, nil, seed)
        assert(g:Start())
        g:Step(10)
        SettleAndReveal(g)
        local id = Item(g, 1).id
        if id ~= "seed" then
            transformed = transformed + 1
            assert(Items.HasTag(id, "植物"), "种子只能变为植物：" .. id)
        end
    end
    assert(transformed > 0, "24次结算应至少发生一次种子转化")
end)

Test("重生与消耗钩子：西红柿炒蛋5次、金针菇重生、幽灵即结算", function()
    -- 西红柿炒蛋：被消耗瓶顶重生，第5次消失。
    local dish = Fixture({ "tomato_egg" })
    assert(dish:Start())
    ---@type GameEvent[]
    local ev = {}
    for i = 1, 4 do
        ev = {}
        assert(dish:_Destroy(1, false, ev), "第" .. i .. "次消耗")
        assert(Item(dish, 1).location == "bottle", "重生留在瓶中")
        assert(#Events(ev, "respawn", 1) == 1, "产生重生事件")
        Close(Item(dish, 1).counter, i)
    end
    ev = {}
    assert(dish:_Destroy(1, false, ev))
    assert(Item(dish, 1).location == "discard", "第5次消失")
    assert(#Events(ev, "remove", 1) == 1)
    -- 金针菇：每次被消耗都重生（无次数限制）。
    local enoki = Fixture({ "enoki" })
    assert(enoki:Start())
    for _ = 1, 6 do
        enoki:_Destroy(1, false, {})
        assert(Item(enoki, 1).location == "bottle", "金针菇总是重生")
    end
    -- 幽灵：被消耗时立即结算一次。
    local ghost = Fixture({ "ghost" })
    assert(ghost:Start())
    ev = {}
    ghost:_Destroy(1, false, ev)
    assert(Item(ghost, 1).location == "discard", "幽灵进弃牌")
    assert(#Events(ev, "score", 1) == 1, "幽灵被消耗即结算")
    Close(ghost.roundScore, 2, "幽灵价值2入账")
end)

Test("遗物三选一：考核达标后追加、刷新、跳过、选择", function()
    local game = Fixture({ "apple" })
    for round = 1, 5 do
        assert(game:Start())
        Item(game, game.drawn[1]).permBonus = 100
        game:Step(10)
        SettleAndReveal(game)
        if round < 5 then assert(game:Skip()) end
    end
    -- 第5回合考核达标：先进物品三选一，pendingRelicDraft 置位。
    assert(game.phase == "draft" and not game.relicDraft, "先进物品三选一")
    assert(game.pendingRelicDraft, "标记待追加遗物三选一")
    assert(#game.options >= 1 and #game.options <= 3)
    for _, id in ipairs(game.options) do assert(Items.byId[id], "物品候选是物品 id") end
    -- 跳过物品三选一 → 进入遗物三选一。
    assert(game:Skip())
    assert(game.phase == "draft" and game.relicDraft, "追加遗物三选一")
    assert(#game.options >= 1, "遗物候选非空")
    for _, id in ipairs(game.options) do assert(Relics.byId[id], "候选是遗物 id") end
    -- 五回合累计的3次物品刷新保留；遗物每组独立免费刷新一次。
    Close(game.refreshes, 3)
    assert(game:DraftRefresh() and game.relicDraft)
    Close(game.refreshes, 3)
    assert(not game:DraftRefresh(), "遗物免费刷新用完后拒绝，不借用物品余额")
    -- 选择遗物后加入 relics 并推进回合。
    local chosen = game.options[1]
    assert(game:Choose(1))
    assert(game.relics[chosen] == true, "选中遗物已拥有")
    assert(game.phase == "prepare" and game.round == 6, "推进到第6回合")
    assert(not game.relicDraft and not game.pendingRelicDraft, "遗物三选一结束")
    IdentityInvariant(game)
end)

Test("遗物效果：积少成多/西红柿首富/最后一秒/车厘子/贷款额度/seeYouTomorrow", function()
    -- 积少成多：每次添加物品+1金币。
    local savings = Fixture({})
    savings.relics.small_savings = true
    Close(savings.score, 0)
    savings:_Create("apple")
    Close(savings.score, 1, "添加物品+1金币")
    savings:_Create("banana")
    Close(savings.score, 2)
    -- 西红柿首富：西红柿价值×2。
    local tycoon = Fixture({ "tomato" })
    Close(tycoon:_Value(Item(tycoon, 1)), 3, "无遗物价值3")
    tycoon.relics.tomato_tycoon = true
    Close(tycoon:_Value(Item(tycoon, 1)), 6, "有遗物价值×2")
    -- 最后一秒：摇晃时长+1。
    local last = Fixture({})
    Close(last:Duration(), 10)
    last.relics.last_second = true
    Close(last:Duration(), 11, "摇晃延长到11秒")
    -- 贷款额度：后续信用卡初始价值25（permBonus+15）。
    local credit = Fixture({})
    credit.relics.credit_line = true
    local card = credit:_Create("credit_card")
    Close(card.permBonus, 15, "信用卡初始永久+15")
    Close(credit:_Value(card), 25, "信用卡初始价值25")
    -- 车厘子：樱桃结算多2次（共3次）。
    local ch = Fixture({ "cherry" })
    ch.relics.cherry_plus = true
    assert(ch:Start())
    ch:Step(10)
    SettleAndReveal(ch)
    Close(ch.lastRoundScore, 3 * 3, "车厘子使樱桃结算3次")
    -- seeYouTomorrow：金针菇每次被消耗永久+1。
    local enoki = Fixture({ "enoki" })
    enoki.relics.see_you_tomorrow = true
    assert(enoki:Start())
    enoki:_Destroy(1, false, {})
    Close(Item(enoki, 1).permBonus, 1, "金针菇被消耗永久+1")
    enoki:_Destroy(1, false, {})
    Close(Item(enoki, 1).permBonus, 2)
end)

Test("遗物效果二：小偷手册/有教无类/金盘洗手/精进刀法/厨师帽/转基因水果", function()
    -- 小偷手册：小偷冷却-1秒（下限1秒）。
    local hb = Fixture({})
    Close(hb:CooldownOf("thief"), 6)
    hb.relics.thief_handbook = true
    Close(hb:CooldownOf("thief"), 5, "小偷手册冷却-1")
    Close(hb:CooldownOf("apple"), 0, "其他物品不受影响")
    -- 有教无类：老师把相邻杀手/赌徒/小偷转变为学生；杀手不消灭老师。
    local teach = Fixture({ "teacher", "killer" })
    teach.relics.teach_all = true
    assert(teach:Start())
    teach:Step(1, { pairs = { { 1, 2 } } })
    assert(Item(teach, 2).id == "student", "杀手被转变为学生")
    Close(Item(teach, 2).permBonus, 4, "学生叠加杀手价值4")
    assert(Item(teach, 1).location == "bottle", "老师存活")
    -- 金盘洗手：小偷不偷取，双方共同+1。
    local wash = Fixture({ "thief", "student" })
    wash.relics.wash_hands = true
    assert(wash:Start())
    wash:Step(0, { pairs = { { 1, 2 } } })
    Close(Item(wash, 1).permBonus, 1, "小偷共同+1")
    Close(Item(wash, 2).permBonus, 1, "对方共同+1而非被偷")
    -- 厨师帽：厨师消耗相邻小刀，产物额外永久+1。
    local hat = Fixture({ "chef", "knife", "apple" })
    hat.relics.chef_hat = true
    assert(hat:Start())
    hat:Step(5, { pairs = { { 1, 2 }, { 1, 3 } } })
    assert(Item(hat, 2).location == "discard", "小刀被消耗")
    Close(Item(hat, 3).permBonus, 4, "产物+3(厨师)+1(厨师帽)")
    -- 转基因水果：水果被消耗时10%瓶顶生成完整水果（多次采样验证钩子存在）。
    local gm = Fixture({ "apple" })
    gm.relics.gm_fruit = true
    assert(gm:Start())
    local spawned = 0
    for _ = 1, 200 do
        local apple = gm:_Create("apple")
        apple.location = "bottle"
        local ev = {}
        gm:_Destroy(apple.uid, false, ev)
        for _, e in ipairs(ev) do
            if e.kind == "spawn" then spawned = spawned + 1 end
        end
    end
    assert(spawned >= 5 and spawned <= 60, "10%概率生成完整水果，200次采样落在合理区间：" .. spawned)
    -- 精进刀法：切割时50%额外半份（多次采样验证钩子存在）。
    local skill = Fixture({ "knife", "apple" })
    skill.relics.knife_skill = true
    assert(skill:Start())
    skill:Step(5, { pairs = { { 1, 2 } } })
    local halves = 0
    for _, it in ipairs(skill:AllInstances()) do
        if it.id == "apple_half" and it.location == "bottle" then halves = halves + 1 end
    end
    assert(halves == 2 or halves == 3, "精进刀法产出2或3份半份：" .. halves)
end)

Test("存档往返保留遗物与跨回合实例状态", function()
    local game = Fixture({ "tomato_egg", "student" }, nil, 4242)
    game.relics.small_savings = true
    game.relics.cherry_plus = true
    Item(game, 1).counter = 3
    Item(game, 2).settleCount = 2
    Item(game, 2).permBonus = 7
    local snapshot = game:Snapshot()
    local restored = Game.Restore(snapshot)
    assert(restored.relics.small_savings and restored.relics.cherry_plus, "遗物随存档恢复")
    Close(Item(restored, 1).counter, 3, "西红柿炒蛋消耗计数保留")
    Close(Item(restored, 2).settleCount, 2, "学生结算计数保留")
    Close(Item(restored, 2).permBonus, 7, "永久增益保留")
    -- 旧档（无 relics 字段）可缺省恢复。
    ---@type any
    local legacy = Game.New(9):Snapshot()
    legacy.relics, legacy.relicDraft, legacy.pendingRelicDraft = nil, nil, nil
    local old = Game.Restore(legacy)
    assert(next(old.relics) == nil and not old.relicDraft, "旧档缺省无遗物")
end)

Test("金币逐笔向上取整且事件余额累计回合一致", function()
    local cherry = Fixture({ "cherry" })
    Item(cherry, 1).permBonus = -1.8
    Close(cherry:_Value(Item(cherry, 1)), 1.2, "物品价值保留计算精度")
    assert(cherry:Start())
    cherry:Step(10)
    local events = SettleAndReveal(cherry)
    local scores = Events(events, "score", 1)
    assert(#scores == 2, "樱桃仍然逐笔结算两次")
    Close(scores[1].value, 2); Close(scores[2].value, 2)
    Close(cherry.score, 4, "两笔1.2各取整为2，共4金币")
    Close(cherry.totalScore, 4); Close(cherry.roundScore, 4)
    Close(cherry.lastRoundScore, 4); Close(cherry.bestRoundScore, 4)

    local card = Fixture({ "credit_card" })
    Item(card, 1).permBonus = -11.2
    assert(card:Start())
    card:Step(10)
    events = SettleAndReveal(card)
    Close(Events(events, "score", 1)[1].value, -1, "-1.2向上取整为-1")
    Close(card.score, -1); Close(card.totalScore, -1)
    Close(card.roundScore, -1); Close(card.lastRoundScore, -1)
end)

Test("金币在最终奖励取整且不提前截断物品价值和倍率", function()
    local game = Fixture({ "police", "thief" })
    Item(game, 2).permBonus, Item(game, 2).permMult = 4, 1.5
    Close(game:_Value(Item(game, 2)), 7.5, "消灭前目标有效价值仍为7.5")
    assert(game:Start())
    local events = game:Step(0, { pairs = { { 1, 2 } } })
    local scores = Events(events, "score", 1)
    assert(#scores == 1 and Item(game, 2).location == "discard")
    Close(scores[1].value, 30, "7.5×4最终为30，不能提前取整成8×4")
    Close(game.score, 30); Close(game.totalScore, 30); Close(game.roundScore, 30)
end)

Test("旧存档小数金币迁移为整数但物品与榨汁保留精度", function()
    local game = Fixture({ "apple" })
    assert(game:Start())
    game:Step(10)
    SettleAndReveal(game)
    local snapshot = game:Snapshot()
    snapshot.score, snapshot.totalScore, snapshot.roundScore = 12.2, 24.2, 3.2
    snapshot.lastRoundScore, snapshot.bestRoundScore = 3.2, 6.2
    snapshot.instances[1].permBonus, snapshot.instances[1].permMult = .25, 1.5
    snapshot.juicerValue = 7.5
    snapshot.lastResult = "第1回合获得3.2金币"
    local restored = Game.Restore(snapshot)
    Close(restored.score, 13); Close(restored.totalScore, 25); Close(restored.roundScore, 4)
    Close(restored.lastRoundScore, 4); Close(restored.bestRoundScore, 7)
    Close(Item(restored, 1).permBonus, .25); Close(Item(restored, 1).permMult, 1.5)
    Close(restored:_Value(Item(restored, 1)), 3.375)
    Close(restored.juicerValue, 7.5)
    assert(restored.lastResult == "第1回合获得4金币", "旧结果文案同步整数金额")
    local migrated = restored:Snapshot()
    for _, field in ipairs({"score", "totalScore", "roundScore", "lastRoundScore", "bestRoundScore"}) do
        assert(migrated[field] == math.ceil(migrated[field]), "迁移后金币字段必须为整数：" .. field)
    end
    Close(snapshot.score, 12.2, "恢复不改写源快照")
    assert(Equal(migrated, Game.Restore(migrated):Snapshot()), "整数迁移幂等")
end)

Test("可选cjson往返保持prepare/rollback/draft和RNG", function()
    ---@type BottleTestJsonCodec?
    local json = rawget(_G, "cjson")
    if not json then return end -- 标准Lua无cjson也可跑其余全部纯规则测试。
    Tests.jsonRoundtripRan = true
    local game = Fixture({ "apple", "banana", "ball", "orange" }, nil, 9876)
    game.refreshes = 3 -- 物品候选刷新池；准备重抽不消耗此余额。
    assert(game:Reroll())
    local prepare = game:Snapshot()
    local restored = Game.Restore(json.decode(json.encode(prepare)) --[[@as BottleSnapshot]])
    assert(Equal(prepare, restored:Snapshot()) and restored.refreshes == 3)
    assert(game:Start() and restored:Start())
    game:Step(5, { wall = { [3] = true } })
    assert(Equal(prepare, Game.Restore(json.decode(json.encode(game:Snapshot())) --[[@as BottleSnapshot]]):Snapshot()))
    game:Step(5, { wall = { [3] = true } })
    restored:Step(10, { wall = { [3] = true } })
    SettleAndReveal(restored)
    SettleAndReveal(game)
    local draft = game:Snapshot()
    local copy = Game.Restore(json.decode(json.encode(draft)) --[[@as BottleSnapshot]])
    assert(Equal(draft, copy:Snapshot()))
    assert(game:DraftRefresh() and copy:DraftRefresh() and Equal(game.options, copy.options))
    local refreshed = Game.Restore(json.decode(json.encode(game:Snapshot())) --[[@as BottleSnapshot]])
    assert(refreshed.refreshUsed and refreshed.refreshes == 2, "draft已用标记不重置物品余额")
    assert(game:Choose(1) and refreshed:Choose(1))
    assert(Equal(game:Snapshot(), refreshed:Snapshot()))
    assert(game:Reroll() and refreshed:Reroll() and Equal(game:Snapshot(), refreshed:Snapshot()))
    assert(game.refreshes == 2 and refreshed.refreshes == 2)
    assert(not game:Reroll() and not refreshed:Reroll(), "独立重抽每回合限一次")
    IdentityInvariant(refreshed)
end)

---@return integer passed 失败时抛出带测试名称的 assert
function Tests.Run()
    Tests.jsonRoundtripRan = false
    local passed = 0
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.Tests [" .. case.name .. "] " .. tostring(err))
        passed = passed + 1
    end
    return passed + require("Bottle.ExtraTests").Run() + require("Bottle.RelicTests").Run()
        + require("Bottle.RepairTests").Run() + require("Bottle.CoreUpdateTests").Run()
        + require("Bottle.ExpansionTests").Run() + require("Bottle.NewRelicTests").Run()
        + require("Bottle.TriggerFeedbackTests").Run()
        + require("Bottle.ConsumeFlashTests").Run()
end

return Tests
