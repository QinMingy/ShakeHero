-- V0.4 效果引擎：#1-31 与 #68-70 物品效果 + 已接线遗物钩子。规则保持纯 Lua，物理只提供接触与位置。
-- 三类效果：
--   Touch（摇晃阶段相邻触发，trigger="touch"）：
--     垃圾桶/大胃王/水果忍者/警察/小偷/老师/小刀/果农/食客/厨师切果。
--     一次触发作用全部相邻合法目标并逐个计数（默认约定，待用户确认）。
--     消灭/消耗类金币即时入账（“立刻产生的效果”；默认约定，待用户确认）。
--   Aura（持续光环，Continuous 每步同步）：
--     橘子贴底+2；厨师相邻食物×2；水果商人钩子已留（实装时生效）。
--     光环重算前置 mult=1，不叠事件倍率（摇晃期无事件倍率可安全重置）。
--   Settle（结算阶段，SettleEffects 于产金币前、SettleItem 产金币、PostSettle 产金币后）：
--     种子50%变植物、气球膨胀/爆炸、学生计数成长、桂冠锁定最高价值、
--     樱桃/半个樱桃再结算、信用卡永久-1。
-- 合成（Merge，摇晃阶段接触对，合成优先于一切触发）：
--     左拖鞋+右拖鞋→水果忍者；鸡蛋+西红柿→西红柿炒蛋（Items.recipes 登记）。
-- 触发条件（trigger）：wall 任意内壁 / bottom 瓶底 / top 瓶顶 / touch 与物品接触 / none。
-- 价值语义：bonus 临时（回合末清零）；permBonus 永久；mult 临时倍率。

local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Extra = require("Bottle.ExtraEffects")
local Expansion = require("Bottle.ExpansionEffects")
local TriggerFeedback = require("Bottle.TriggerFeedback")

---@class Effects
local Effects = {}

-- 完整水果 → 两份半份（切割效果产物；源表「完整水果」指可切的整个水果）。
local FULL_FRUIT = {
    apple = "apple_half", banana = "banana_half", orange = "orange_half",
    cherry = "cherry_half",
}

-- 结算“变为任一植物”的候选：动态收集已实装且带植物tag的完整植物（排除半份）。
---@return string[]
local function PlantPool()
    ---@type string[]
    local pool = {}
    for _, def in ipairs(Items.list) do
        if def.implemented and not def.id:match("_half$") then
            for _, tag in ipairs(def.tags or {}) do
                if tag == "植物" then
                    pool[#pool + 1] = def.id
                    break
                end
            end
        end
    end
    return pool
end

-- 学生正面/负面成长目标（item.txt #17；医生/士兵已入表）。
local STUDENT_GOOD = { "police", "chef", "teacher", "doctor", "soldier" }
local STUDENT_BAD = { "thief", "killer", "gambler" }
-- 警察消灭目标（#15：赌徒、小偷、杀手）。
local POLICE_TARGETS = { gambler = true, thief = true, killer = true }

-- 接触条件：trigger=touch 的物品需与至少一个其他物品接触才进入调度；
-- 效果内部再过滤合法目标（无合法目标也算触发失败，按基础设定进入冷却）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@return boolean
function Effects.Touches(game, item, contacts)
    local expansion = Expansion.Touches(game, item, contacts)
    if expansion ~= nil then return expansion end
    local extra = Extra.Touches(game, item, contacts)
    if extra ~= nil then return extra end
    local trigger = Items.byId[item.id].trigger
    if trigger == "wall" then
        return contacts.wall[item.uid] == true or contacts.bottom[item.uid] == true
            or contacts.top[item.uid] == true
    end
    if trigger == "bottom" then return contacts.bottom[item.uid] == true end
    if trigger == "top" then return contacts.top[item.uid] == true end
    if trigger == "touch" then
        for _, pair in ipairs(contacts.pairs) do
            if pair[1] == item.uid or pair[2] == item.uid then return true end
        end
        return false
    end
    return false
end

------------------------------------------------------------------ 摇晃阶段：合成

--- 合成检查：遍历接触对查 Items.recipes；一对材料只合成一次（目标只能消耗一次）。
--- 在触发效果之前执行（设计约定：合成优先）。
---@param game BottleGame
---@param contacts BottleStepContacts
---@param events GameEvent[]
function Effects.Merge(game, contacts, events)
    for _, pair in ipairs(contacts.pairs) do
        local a = game:Get(pair[1])
        local b = game:Get(pair[2])
        if a and b and a.location == "bottle" and b.location == "bottle" then
            local special = Expansion.TryMerge(game, a, b, contacts, events)
            local resultId = special == nil and Items.Recipe(a.id, b.id) or nil
            -- 用户确认：默认最高64元；遗物解锁后才允许64→128及更高配方。
            local coinValue = tonumber(a.id:match("^coin_(%d+)$"))
            if coinValue and coinValue >= 64 and not Relics.Has(game, "merge_2048") then
                resultId = nil
            end
            if resultId then
                game:_Merge(a, b, resultId, contacts, events)
            end
        end
    end
end

------------------------------------------------------------------ 摇晃阶段：切割与学生成长

--- 切水果公共实现：源实例原地转化为半份（保留uid），并在源位置旁生成另一份。
--- chefBonus=true（厨师#29）：两份产物价值各永久+3；extraBonus 再叠加（遗物厨师帽）。
--- 遗物 knife_skill（精进刀法）：50%概率额外再产一份半份。
---@param game BottleGame
---@param fruit ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@param chefBonus boolean
---@param extraBonus number?
---@return boolean
local function CutFruit(game, fruit, contacts, events, chefBonus, extraBonus)
    local halfId = FULL_FRUIT[fruit.id]
    if not halfId then return false end
    local position = contacts.positions[fruit.uid]
    local bonus = (chefBonus and 3 or 0) + (extraBonus or 0)
    game:_Transform(fruit, halfId, events)
    if bonus > 0 then fruit.permBonus = fruit.permBonus + bonus end
    local extra = game:_Spawn(halfId, events, false, position)
    if extra and bonus > 0 then extra.permBonus = extra.permBonus + bonus end
    if extra and Relics.Has(game, "knife_skill") and game:_RandomInt(2) == 1 then
        local third = game:_Spawn(halfId, events, false, position)
        if third and bonus > 0 then third.permBonus = third.permBonus + bonus end
    end
    return true
end

--- 学生#17成长：随机变为职业；叠加当前自身价值（permBonus += 当前有效价值）。
--- noNegative=true（老师催熟/遗物有教无类）时不出负面职业。
---@param game BottleGame
---@param student ItemInstance
---@param events GameEvent[]
---@param noNegative boolean
function Effects.GrowStudent(game, student, events, noNegative)
    local current = game:_Value(student)
    ---@type string[]
    local pool = STUDENT_GOOD
    if not noNegative and not Relics.Has(game, "teach_all")
        and game:_RandomInt(10) == 1 then pool = STUDENT_BAD end
    local target = pool[game:_RandomInt(#pool)]
    game:_Transform(student, target, events)
    student.permBonus = student.permBonus + current
    student.settleCount = 0
    events[#events + 1] = {
        kind = "buff", uid = student.uid, id = student.id, value = current,
    }
end

------------------------------------------------------------------ 摇晃阶段：TOUCH 效果

-- 垃圾桶#7：消耗相邻的垃圾和临时物品，每个使其价值永久+1（冷却2秒）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function TrashCan(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and (Items.HasTag(other.id, "垃圾") or other.temporary) then
            if game:_Destroy(other.uid, other.temporary, events, item) then
                item.permBonus = item.permBonus + 1
                hit = true
            end
        end
    end
    return hit
end

-- 大胃王#8：消耗相邻食物，每个使其价值永久+1、体积+10%（上限200%）。
-- 体积达上限时无法再消耗（触发失败）。位移缩体积由 Physics 累计 distance 驱动。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Glutton(game, item, contacts, events)
    if item.scale >= 2 then return false end
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and Items.HasTag(other.id, "食物") then
            if game:_Destroy(other.uid, other.temporary, events, item) then
                item.permBonus = item.permBonus + 1
                item.scale = math.min(2, item.scale + 0.1)
                game:ApplyScale(item, events)
                hit = true
                if item.scale >= 2 then break end
            end
        end
    end
    return hit
end

-- 水果忍者#12：将相邻完整水果劈成两份，自身永久+该水果价值（冷却5秒）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function FruitNinja(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and FULL_FRUIT[other.id] then
            local value = game:_Value(other)
            if CutFruit(game, other, contacts, events, false) then
                item.permBonus = item.permBonus + value
                events[#events + 1] = {
                    kind = "buff", uid = item.uid, id = item.id, value = value,
                }
                hit = true
            end
        end
    end
    return hit
end

-- 警察#15：消灭相邻的赌徒、小偷、杀手；获得其价值×4的金币（即时）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Police(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if POLICE_TARGETS[other.id]
            and not (other.id == "thief" and Relics.Has(game, "wash_hands")) then
            if game:_Eliminate(other, item, 4, contacts, events) then hit = true end
        end
    end
    return hit
end

-- 杀手#20：消灭相邻的人类（警察与杀手除外），获得该人类价值×7的金币（即时）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Killer(game, item, contacts, events)
    local hit = false
    -- 遗物 teach_all（有教无类）：老师不会被杀手杀害。
    local teacherSafe = Relics.Has(game, "teach_all")
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and Items.HasTag(other.id, "人类")
            and other.id ~= "police" and other.id ~= "killer"
            and not (teacherSafe and other.id == "teacher") then
            if game:_Eliminate(other, item, 7, contacts, events) then hit = true end
        end
    end
    return hit
end

-- 小偷#16：永久偷取相邻人类、硬币、信用卡的1点价值（冷却6秒；遗物小偷手册-1秒）。
-- 具体实现（item.txt 备注）：被偷方价值永久-1；价值≤0不可被偷；同时与多个相邻则同时偷取。
-- 遗物 wash_hands（金盘洗手）：不再偷取，而是和对方共同增加价值。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Thief(game, item, contacts, events)
    local washHands = Relics.Has(game, "wash_hands")
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        local isCoin = other.id:match("^coin_%d+$") ~= nil
        if other.uid ~= item.uid
            and (Items.HasTag(other.id, "人类") or isCoin or other.id == "credit_card") then
            if washHands then
                other.permBonus = other.permBonus + 1
                item.permBonus = item.permBonus + 1
                events[#events + 1] = {
                    kind = "buff", uid = other.uid, id = other.id, value = 1,
                }
                events[#events + 1] = {
                    kind = "buff", uid = item.uid, id = item.id, value = 1,
                }
                hit = true
            elseif game:_Value(other) > 0 then
                local delta = Relics.Has(game, "lucky_charm") and 1 or -1
                other.permBonus = other.permBonus + delta
                item.permBonus = item.permBonus + 1
                events[#events + 1] = {
                    kind = "buff", uid = other.uid, id = other.id, value = delta,
                }
                events[#events + 1] = {
                    kind = "buff", uid = item.uid, id = item.id, value = 1,
                }
                hit = true
            end
        end
    end
    return hit
end

-- 老师#18：相邻学生立刻执行成长效果，且不会成长为负面职业。
-- 遗物 teach_all（有教无类）：相邻杀手/赌徒/小偷也转化为学生（默认约定，待用户确认）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Teacher(game, item, contacts, events)
    local hit = false
    local convertAll = Relics.Has(game, "teach_all")
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid then
            if other.id == "student" then
                Effects.GrowStudent(game, other, events, true)
                item.permBonus = item.permBonus + 3
                events[#events + 1] = {kind="buff", uid=item.uid, id=item.id, value=3}
                hit = true
            elseif convertAll and (other.id == "killer" or other.id == "gambler"
                or (other.id == "thief" and not Relics.Has(game, "wash_hands"))) then
                local value = game:_Value(other)
                game:_Transform(other, "student", events)
                other.permBonus = other.permBonus + value
                other.settleCount = 0
                hit = true
            end
        end
    end
    return hit
end

-- 小刀#24：将相邻的水果切成两份（冷却5秒）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Knife(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and FULL_FRUIT[other.id] then
            if CutFruit(game, other, contacts, events, false) then hit = true end
        elseif other.id == "sheep" and Expansion.ShedWool(game, other, events) then
            hit = true
        end
    end
    return hit
end

-- 果农#25：结算一次相邻水果（立即按其当前价值产金币；冷却8秒）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function FruitFarmer(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and Items.HasTag(other.id, "水果") then
            game:_Score(events, other, game:_Value(other), contacts.positions[other.uid])
            hit = true
        end
    end
    return hit
end

-- 食客#26：消耗相邻食物，给予对应价值×2的金币（即时）；消耗5个食物后消耗自身。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Diner(game, item, contacts, events)
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and Items.HasTag(other.id, "食物") then
            local value = game:_Value(other)
            if game:_Destroy(other.uid, other.temporary, events, item) then
                game:_Score(events, item, value * 2, contacts.positions[item.uid])
                item.counter = item.counter + 1
                hit = true
                -- 最新备注：最后一次按整批相邻食物处理，可超过五件后再自耗。
            end
        end
    end
    if item.counter >= 5 and item.location == "bottle" then
        game:_Destroy(item.uid, false, events)
    end
    return hit
end

-- 厨师#29：将相邻完整水果切成两份并使产物价值永久+3（光环×2在 Continuous）。
-- 遗物 chef_hat（厨师帽）：可消耗相邻小刀，为产物额外永久+1。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
local function Chef(game, item, contacts, events)
    local extra = 0
    if Relics.Has(game, "chef_hat") then
        for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
            if other.id == "knife" and game:_Destroy(other.uid, false, events, item) then
                extra = extra + 1
            end
        end
    end
    local hit = false
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.uid ~= item.uid and FULL_FRUIT[other.id] then
            if CutFruit(game, other, contacts, events, true, extra) then hit = true end
        end
    end
    return hit
end

-- 相邻触发效果分派表（trigger="touch" 的物品）。
---@type table<string, fun(game:BottleGame, item:ItemInstance, contacts:BottleStepContacts, events:GameEvent[]):boolean>
local TOUCH = {
    trash_can = TrashCan,
    glutton = Glutton,
    fruit_ninja = FruitNinja,
    police = Police,
    thief = Thief,
    teacher = Teacher,
    knife = Knife,
    fruit_farmer = FruitFarmer,
    diner = Diner,
    chef = Chef,
    killer = Killer,
}

--- 摇晃阶段执行一件已就绪且接触条件满足的物品。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean handled
function Effects.Apply(game, item, contacts, events)
    if item.id == "ball" then
        -- 每次碰撞瓶子：价值+1（临时），进入冷却。
        item.bonus = item.bonus + 1
        events[#events + 1] = { kind = "buff", uid = item.uid, id = item.id, value = 1 }
        return true
    end
    local handler = TOUCH[item.id]
    if handler then return handler(game, item, contacts, events) end
    if Expansion.Touches(game, item, contacts) ~= nil then
        return Expansion.Apply(game, item, contacts, events)
    end
    return Extra.Apply(game, item, contacts, events)
end

------------------------------------------------------------------ 持续型状态与光环

--- 光环倍率：相邻厨师的食物×2（#29）；相邻水果商人的水果×2（#39，钩子已留）。
---@param game BottleGame
---@param item ItemInstance
---@param contacts BottleStepContacts
---@return number
local function AuraMult(game, item, contacts)
    local mult = 1
    local isFood = Items.HasTag(item.id, "食物")
    local isFruit = Items.HasTag(item.id, "水果")
    if not isFood and not isFruit then return mult end
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        if other.id == "chef" and isFood then
            mult = mult * 2
        elseif other.id == "fruit_merchant" and isFruit then
            mult = mult * 2
        end
    end
    return mult
end

--- 持续型接触效果：每个物理步同步状态，不消耗冷却。
--- 橘子/半块橘子贴底+2；光环每步重算（重算前置 mult=1，摇晃期无事件倍率可安全重置）。
---@param game BottleGame
---@param contacts BottleStepContacts
---@param events GameEvent[]
function Effects.Continuous(game, contacts, events)
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "orange" or item.id == "orange_half" then
            local touching = contacts.bottom[item.uid] == true
            local wanted = touching and 2 or 0
            if item.bonus ~= wanted then
                item.bonus = wanted
                events[#events + 1] = {
                    kind = "buff", uid = item.uid, id = item.id, value = wanted,
                }
                -- 贴底是持续状态，接触切换只同步价值，不作为离散收益跳字。
            end
        elseif item.id == "counter" then
            item.bonus = math.floor(#game:BottleItems() / 3)
        end
        local aura = AuraMult(game, item, contacts) * (item.eventMult or 1)
        if item.mult ~= aura then
            local previous = item.mult
            item.mult = aura
            events[#events + 1] = {
                kind = "buff", uid = item.uid, id = item.id, value = aura,
            }
            if aura > previous and aura > 0 and game.phase == "running" then
                TriggerFeedback.Reward(events, item, game:_Value(item) * (1 - previous / aura),
                    "value", "collision", contacts.positions[item.uid])
            end
        end
    end
end

------------------------------------------------------------------ 结算阶段

--- 结算前奏（产金币前，按uid序）：种子转化、气球膨胀/爆炸、学生计数成长、桂冠锁定。
--- 气球爆炸使所有物品 mult×2（事件倍率直接写入 mult，回合末清零）。
---@param game BottleGame
---@param events GameEvent[]
function Effects.SettleEffects(game, events)
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "seed" then
            -- 结算时：50%概率变为任一植物（转化后按新物品价值产金币）。
            if game:_RandomInt(2) == 1 then
                local pool = PlantPool()
                if #pool > 0 then
                    game:_Transform(item, pool[game:_RandomInt(#pool)], events)
                end
            end
        elseif item.id == "balloon" then
            item.scale = math.min(2, item.scale + 0.1)
            if item.scale >= 2 - 1e-9 then
                item.scale = 2
                Expansion.BurstBalloon(game, item, events, nil)
            else
                game:ApplyScale(item, events)
            end
        end
    end
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "student" then
            item.settleCount = item.settleCount + 1
            if item.settleCount >= 5 then
                Effects.GrowStudent(game, item, events, false)
            end
        end
    end
    -- 桂冠#31（结算时生效，产金币前）：场上唯一价值最高的物品价值×1.5；
    -- 若其价值至少为20，再×1.5。桂冠自身也是场上物品，参与评选。
    -- mult 为临时倍率：本轮产金币生效，回合末清零。
    for _, laurel in ipairs(game:BottleItems()) do
        if laurel.id == "laurel" then
            ---@type ItemInstance?
            local best = nil
            local bestValue, tie = -math.huge, false
            for _, item in ipairs(game:BottleItems()) do
                local value = game:_Value(item)
                if value > bestValue then
                    best, bestValue, tie = item, value, false
                elseif value == bestValue then
                    tie = true
                end
            end
            if best and not tie then
                best.mult = best.mult * 1.5
                if bestValue >= 20 then best.mult = best.mult * 1.5 end
                events[#events + 1] = {
                    kind = "buff", uid = best.uid, id = best.id, value = best.mult,
                }
            end
            break
        end
    end
end

--- 结算产金币：樱桃/半个樱桃再结算一次（遗物车厘子：樱桃改为多2次）。
---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
---@param position {x:number,y:number}?
---@param contacts BottleStepContacts?
function Effects.SettleItem(game, item, events, position, contacts)
    local value = game:_Value(item)
    local times = 1
    if item.id == "cherry" then
        times = times + (Relics.Has(game, "cherry_plus") and 2 or 1)
    elseif item.id == "cherry_half" then
        times = times + 1
    elseif item.id == "gecko" and contacts then
        -- 每个真实直接连接的壁虎额外一次；不数培根虚拟相邻或连通分量。
        local seen = {}
        for _, pair in ipairs(contacts.rawPairs or contacts.pairs) do
            local uid = pair[1] == item.uid and pair[2] or pair[2] == item.uid and pair[1] or nil
            local other = uid and game:Get(uid)
            if other and other.uid ~= item.uid and other.id == "gecko"
                and other.location == "bottle" and not seen[other.uid] then
                seen[other.uid] = true
                times = times + 1
            end
        end
    end
    for _ = 1, times do
        game:_Score(events, item, value, position)
    end
end

--- 结算尾声（全体产金币后）：信用卡#23 每次结算后价值永久-1。
---@param game BottleGame
---@param events GameEvent[]
function Effects.PostSettle(game, events)
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "credit_card" then
            local delta = Relics.Has(game, "lucky_charm") and 1 or -1
            item.permBonus = item.permBonus + delta
            events[#events + 1] = {
                kind = "buff", uid = item.uid, id = item.id, value = delta,
            }
        end
    end
end

return Effects
