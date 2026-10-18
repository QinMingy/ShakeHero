-- 剩余物品的独立规则模块。只依赖纯 Lua 数据表，不引用引擎、物理或全局随机数。
-- 接线约定：
--   Start           Game:Start 中，回合计数/冷却初始化后调用一次。
--   Touches/Apply   Game 的冷却调度调用；Apply 失败也由调度重置完整冷却。
--   Crop            主动执行一次农作物判定，不改变其周期 remaining。
--   BeforeSettle    持续光环同步完毕、统一产金币前调用一次。
--   AfterSettle     统一产金币后、回合清理前调用一次。
--   ResetRound      回合清理及准备时调用；不清永久收益。
-- 接触设计（这里只消费真接触，不构造距离碰撞）：
--   [赌徒]--pair--[骰子]      每位赌徒对每颗骰子分别记次数。
--   [水珠]--pair--[农作物]    全部相邻农作物各判一次，之后才消耗水珠。
--   [灵魂石]--pair--[幽灵]    逐件消耗，每件分别结算幽灵与灵魂石。
--   ===== bottom =====       星星仅触底传送；灵魂罐可触任意内壁。
-- 空接触/错误目标不触发；合法目标但概率失败、额度用完、瓶满等仍进入冷却。
-- 位移（健身教练/兔子）、计数器持续加成、水果商人光环由 Game/Effects 维护。

local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicEffects = require("Bottle.RelicEffects")

---@class ExtraEffects
local Extra = {}

---@type table<string, integer?>
local DIE_SIDES = { die_d4 = 4, die_d6 = 6 }
---@type string[]
local FULL_FRUIT = { "apple", "banana", "orange", "cherry" }
---@type string[]
local COINS = { "coin_1", "coin_2" }
---@type string[]
local UPGRADED_COINS = { "coin_1", "coin_2", "coin_4" }
-- 本模块负责的 id：无离散触发的物品也显式返回 false，不能落回旧通用 touch 分派。
---@type table<string, boolean>
local HANDLED = {
    die_d4 = true, die_d6 = true, gambler = true, gambling_god = true,
    fitness_coach = true, fruit_tree = true, farmer = true, fruit_merchant = true,
    counter = true, droplet = true, cloud = true, monkey = true, lucky_coin = true,
    rabbit = true, necromancer = true, bacon = true,
    soul_jar = true, coffin = true, tombstone = true, soul_stone = true,
    coin_machine = true, star = true,
}

---@param a ItemInstance
---@param b ItemInstance
---@return boolean
local function ByUid(a, b)
    return a.uid < b.uid
end

---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
---@param value number
local function Buff(game, item, events, value)
    events[#events + 1] = { kind = "buff", uid = item.uid, id = item.id, value = value }
    game.revision = game.revision + 1
end

---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
---@param value number
local function Permanent(game, item, events, value)
    item.permBonus = item.permBonus + value
    Buff(game, item, events, value)
end

--- 合法目标判定与执行分开：额度用完的骰子仍是骰子，判定失败照样消耗触发冷却。
---@param sourceId string
---@param other ItemInstance
---@return boolean
local function LegalTarget(sourceId, other)
    if other.location ~= "bottle" then return false end
    if sourceId == "gambler" or sourceId == "gambling_god" then
        return DIE_SIDES[other.id] ~= nil and Items.HasTag(other.id, "骰子")
    end
    if sourceId == "farmer" then return other.id == "fruit_tree" end
    if sourceId == "droplet" then return Items.HasTag(other.id, "农作物") end
    if sourceId == "monkey" then return other.id == "banana" end
    if sourceId == "coffin" or sourceId == "tombstone" or sourceId == "soul_stone" then
        return other.id == "ghost"
    end
    if sourceId == "coin_machine" then return Items.HasTag(other.id, "人类") end
    return false
end

--- 返回 nil 表示不是本模块负责的 id；false 表示本模块负责但当前不满足触发条件。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@return boolean?
function Extra.Touches(game, item, contacts)
    if not HANDLED[item.id] then return nil end
    if item.location ~= "bottle" then return false end
    if item.id == "fruit_tree" or item.id == "cloud" or item.id == "lucky_coin" then
        return true -- 周期到点即判定，不要求与任何物品/瓶壁接触。
    end
    if item.id == "star" then return contacts.bottom[item.uid] == true end
    if item.id == "soul_jar" then
        return contacts.wall[item.uid] == true or contacts.bottom[item.uid] == true
            or contacts.top[item.uid] == true
    end
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and LegalTarget(item.id, other) then return true end
    end
    return false
end

--- 骰子只更新实例点数，不修改共享 Items.base。每次掷完本体立即结算一次。
--- 不在这里调用赌徒，以免骰子→赌徒→骰子的递归翻滚。
---@param game BottleGame
---@param die ItemInstance
---@param contacts BottleStepContacts?
---@param events GameEvent[]
---@return integer
local function Roll(game, die, contacts, events)
    local maximum = assert(DIE_SIDES[die.id], "不是已支持的骰子")
    local minimum = Relics.Has(game, "cheat_dice") and 2 or 1
    local point = game:_RandomInt(maximum - minimum + 1) + minimum - 1
    die.rollValue = point
    Buff(game, die, events, point)
    game:_Score(events, die, game:_Value(die), contacts and contacts.positions[die.uid] or nil)
    return point
end

--- 赌徒归零既移除临时加值也清掉永久本体，防止下回合恢复此前永久增长。
--- mult 属于外部持续光环，不在此移除；零本体乘任意倍率仍是零。
---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
local function ZeroGambler(game, item, events)
    item.bonus = 0
    item.permBonus = -Items.byId[item.id].base
    item.tokenAttempted = false
    Buff(game, item, events, 0)
end

--- 单次调度内按相邻骰子的 uid 顺序逐颗重投；遗物额外次数是连续循环，不递归。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Gambler(game, item, contacts, events)
    local counts = item.rerolled or {}
    item.rerolled = counts
    local hit = false
    for _, die in ipairs(game:_Adjacents(item.uid, contacts)) do
        if LegalTarget(item.id, die) then
            local limit = item.id == "gambler" and Relics.Has(game, "one_more_round") and 2 or 1
            while die.location == "bottle" and (counts[die.uid] or 0) < limit do
                -- 先记次数，再掷/结算；后续效果不得让同一次投掷再次进入处理。
                counts[die.uid] = (counts[die.uid] or 0) + 1
                local point = Roll(game, die, contacts, events)
                local isGambler = item.id == "gambler"
                Permanent(game, item, events, isGambler and 1 or point)
                if item.id == "gambler" and point == 1 then
                    game:_Score(events, item, game:_Value(item), contacts.positions[item.uid])
                    ZeroGambler(game, item, events)
                elseif point == DIE_SIDES[die.id] then
                    game:_Score(events, item, game:_Value(item), contacts.positions[item.uid])
                end
                hit = true
                -- 本次加值/特殊点数结算/投1归零全部完成后才检查令牌。
                -- 转化后结束原赌徒批次，不能立即按赌神规则继续处理。
                if RelicEffects.CheckGamblingToken(game, item, events) then return true end
            end
        end
    end
    return hit
end

--- 与旧种子规则一致：按数据录入顺序筛已实装、植物 tag、非半份的完整植物。
---@return string[]
local function PlantPool()
    ---@type string[]
    local pool = {}
    for _, def in ipairs(Items.list) do
        if def.implemented and not def.id:match("_half$") and Items.HasTag(def.id, "植物") then
            pool[#pool + 1] = def.id
        end
    end
    return pool
end

--- 执行一次农作物本身的效果；返回 true 表示已判定，概率失败不等于没有触发。
--- 水珠不重置果树周期 remaining；种子转成新类型则使用 _Transform 的完整冷却。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean attempted
function Extra.Crop(game, item, contacts, events)
    if item.location ~= "bottle" then return false end
    if item.id == "seed" then
        if game:_RandomInt(2) == 1 then
            local pool = PlantPool()
            if #pool > 0 then
                game:_Transform(item, assert(pool[game:_RandomInt(#pool)]), events)
            end
        end
        return true
    end
    if item.id ~= "fruit_tree" then return false end
    local blessed = item.treeBlessed == true
    item.treeBlessed = false -- 下一次判定即消费，不叠加，也不会因瓶满保留。
    if blessed then
        -- 先保证基础一件，再独立50%额外一件，每件独立抽完整水果种类。
        game:_Spawn(assert(FULL_FRUIT[game:_RandomInt(#FULL_FRUIT)]), events, false,
            contacts.positions[item.uid])
        if game:_RandomInt(2) == 1 then
            game:_Spawn(assert(FULL_FRUIT[game:_RandomInt(#FULL_FRUIT)]), events, false,
                contacts.positions[item.uid])
        end
    elseif game:_RandomInt(2) == 1 then
        game:_Spawn(assert(FULL_FRUIT[game:_RandomInt(#FULL_FRUIT)]), events, false,
            contacts.positions[item.uid])
    end
    game.revision = game.revision + 1
    return true
end

---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Farmer(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.id == "fruit_tree" and other.location == "bottle" then
            if not other.treeBlessed then
                other.treeBlessed = true
                Buff(game, other, events, 1)
            end
            hit = true -- 已带祝福也算触碰，不叠层，农民仍进入1秒冷却。
        end
    end
    return hit
end

---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Droplet(game, item, contacts, events)
    local attempted = false
    -- 快照只含触发前已有的相邻对象；生成的水果不追加进本次相邻集合。
    for _, crop in ipairs(game:_Adjacents(item.uid, contacts)) do
        if crop.location == "bottle" and Items.HasTag(crop.id, "农作物") then
            if Extra.Crop(game, crop, contacts, events) then attempted = true end
        end
    end
    if attempted then game:_Destroy(item.uid, false, events) end
    return attempted
end

---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Monkey(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.id == "banana" and game:_Destroy(other.uid, false, events, item) then
            -- 固定7金币/香蕉，与香蕉当前价值、猴子当前价值及倍率无关。
            game:_Score(events, item, 7, contacts.positions[item.uid])
            hit = true
        end
    end
    return hit
end

-- 原有瓶体几何（docs/game-design.md §5.1 / Physics）：只用于选随机生成原点。
--      y=6.4   | 颈半宽1.15 |
--      y=6.05  +           +
--               /         \\
--      y=5.5  +             +  半宽2.4
--      y=0    +-------------+
-- 原点保证位于瓶体轮廓内；实体半径、旋转包络和净空仍由 Physics:_NearPosition 修正。
---@param game BottleGame
---@return {x:number,y:number}
local function RandomBottlePosition(game)
    local y = (game:_RandomInt(6401) - 1) / 1000
    local halfWidth = 2.4
    if y >= 6.05 then
        halfWidth = 1.15
    elseif y > 5.5 then
        halfWidth = 2.4 - (y - 5.5) * (2.4 - 1.15) / (6.05 - 5.5)
    end
    local x = ((game:_RandomInt(10001) - 1) / 10000 * 2 - 1) * halfWidth
    return { x = x, y = y }
end

---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
---@return boolean
local function SoulJar(game, item, events)
    if not game:_Destroy(item.uid, false, events) then return false end
    local count = game:_RandomInt(3)
    for _ = 1, count do
        game:_Spawn("ghost", events, false, RandomBottlePosition(game))
    end
    return true
end

---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function SoulStone(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.id == "ghost" and game:_Destroy(other.uid, false, events, item) then
            -- 幽灵自身的被消耗结算由 Game:_Destroy 完成，这里只结算灵魂石。
            game:_Score(events, item, game:_Value(item), contacts.positions[item.uid])
            hit = true
        end
    end
    return hit
end

---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function CoinMachine(game, item, contacts, events)
    local count = 0
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if Items.HasTag(other.id, "人类") then count = count + 1 end
    end
    local pool = Relics.Has(game, "upgrade_coin_machine") and UPGRADED_COINS or COINS
    local hit = false
    for _ = 1, count do
        -- 两种/三种硬币均匀抽签；总生成数是相邻人类数，不是每种各生成该数。
        local id = assert(pool[game:_RandomInt(#pool)])
        if game:_SpawnTop(id, events, false) then hit = true end
    end
    return hit
end

--- 回合开始只投本回合入瓶骰子，不通知赌徒，不给未入瓶骰子产生收益。
---@param game BottleGame
---@param events GameEvent[]
function Extra.Start(game, events)
    for _, item in ipairs(game:BottleItems()) do
        if DIE_SIDES[item.id] then Roll(game, item, nil, events) end
    end
end

--- 摇晃期间离散效果；冷却重置由 Game 完成，这里不检查/扣减 remaining。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
function Extra.Apply(game, item, contacts, events)
    if Extra.Touches(game, item, contacts) ~= true then return false end
    local id = item.id
    if id == "gambler" or id == "gambling_god" then
        return Gambler(game, item, contacts, events)
    elseif id == "fruit_tree" then
        return Extra.Crop(game, item, contacts, events)
    elseif id == "farmer" then
        return Farmer(game, item, contacts, events)
    elseif id == "droplet" then
        return Droplet(game, item, contacts, events)
    elseif id == "cloud" then
        local spawnId = Relics.Has(game, "coin_rain") and "coin_1" or "droplet"
        local spawned = game:_Spawn(spawnId, events, false, contacts.positions[item.uid]) ~= nil
        -- 每周期保底永久一件，独立20%瓶顶追加六件临时；硬币雨只换类型。
        if game:_RandomInt(5) == 1 then
            for _ = 1, 6 do
                if game:_SpawnTop(spawnId, events, true) then spawned = true end
            end
        end
        return spawned
    elseif id == "monkey" then
        return Monkey(game, item, contacts, events)
    elseif id == "lucky_coin" then
        if game:_RandomInt(2) ~= 1 then return false end
        game:_Score(events, item, game:_Value(item), contacts.positions[item.uid])
        return true
    elseif id == "soul_jar" then
        return SoulJar(game, item, events)
    elseif id == "coffin" then
        -- 一次触发只生成一件，不能按相邻幽灵数放大。
        return game:_Spawn("ghost", events, false, contacts.positions[item.uid]) ~= nil
    elseif id == "tombstone" then
        Permanent(game, item, events, 1) -- 一次触发仅+1，不按相邻幽灵数叠加。
        return true
    elseif id == "soul_stone" then
        return SoulStone(game, item, contacts, events)
    elseif id == "coin_machine" then
        return CoinMachine(game, item, contacts, events)
    elseif id == "star" then
        item.bonus = item.bonus + 1
        Buff(game, item, events, 1)
        game:_TeleportTop(item, events)
        return true
    end
    return false
end

--- 培根倍率仅在统一结算前计算一次，乘现有光环/爆炸倍率，不覆盖外部 mult。
---@param game BottleGame
---@param contacts BottleStepContacts
---@param events GameEvent[]
function Extra.BeforeSettle(game, contacts, events)
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "bacon" then
            local count = 0
            for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
                if other.uid ~= item.uid and Items.HasTag(other.id, "食物") then
                    count = count + 1
                end
            end
            if count > 0 then
                item.mult = item.mult * (1.5 ^ count)
                Buff(game, item, events, item.mult)
            end
        end
    end
end

--- 每位死灵术士按 uid 序随机返还一张当前弃牌。每次重新收集剩余候选，避免重复返还。
--- 返还只回拥有牌库，不入瓶、不产生 spawn，不进入已完成的统一结算循环。
---@param game BottleGame
---@param events GameEvent[]
function Extra.AfterSettle(game, events)
    for _, caster in ipairs(game:BottleItems()) do
        if caster.id == "necromancer" then
            ---@type ItemInstance[]
            local candidates = {}
            for _, other in ipairs(game.discard) do
                if other.location == "discard" then candidates[#candidates + 1] = other end
            end
            table.sort(candidates, ByUid)
            if #candidates > 0 then
                local returned = assert(candidates[game:_RandomInt(#candidates)])
                game:_ReturnToDeck(returned)
                if returned.location == "deck" then Buff(game, caster, events, 1) end
            end
        end
    end
end

--- 位移已经由 Game 按真实物理差分累积；这里只消费10米阈值，不再重复采样。
--- 健身教练各自使缩幅×2，气球没有缩小效果，不在这里新增气球规则。
---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
function Extra.TrackDistance(game, item, events)
    if item.location ~= "bottle" then return end
    if item.id == "glutton" then
        local coaches = 0
        for _, other in ipairs(game:BottleItems()) do
            if other.id == "fitness_coach" then coaches = coaches + 1 end
        end
        local shrink = 0.1 * (2 ^ coaches)
        while item.distance >= 10 and item.scale > 1 do
            item.distance = item.distance - 10
            item.scale = math.max(1, item.scale - shrink)
            game:ApplyScale(item, events)
        end
        if item.distance >= 10 and item.scale <= 1 then item.distance = 0 end
    elseif item.id == "rabbit" then
        while item.distance >= 10 do
            item.distance = item.distance - 10
            if Relics.Has(game, "in_groups") then
                for _, other in ipairs(game:BottleItems()) do
                    if other.id == "rabbit" then Permanent(game, other, events, 1) end
                end
            else
                Permanent(game, item, events, 1)
            end
        end
    end
end

--- 只清本模块的回合状态；永久 permBonus/scale/counter 等必须保留。
---@param item ItemInstance
function Extra.ResetRound(item)
    item.rollValue = nil
    item.rerolled = nil
    item.treeBlessed = nil
    item.distance = 0
end

return Extra
