-- 源表 #71-93 的纯 Lua 规则；不引用引擎，不修改共享定义，不使用全局随机数。
-- 接触只消费 Physics 的真实 pairs/side/flightHits；此模块不推测物理碰撞。
-- 冷却由 Game 调度，运动子状态由 Step 推进；所有消费统一走 _Destroy，不能绕开护盾。
local Items = require("Bottle.Items")
local FrameBudget = require("Bottle.FrameBudget")
local TriggerFeedback = require("Bottle.TriggerFeedback")
local Relics = require("Bottle.Relics")
local RelicExpansion = require("Bottle.RelicExpansion")
local Rotation = require("Bottle.RotationEffects")
local Expansion = {}
local EPSILON = 1e-9
local TURN = math.pi * 2
local DASH_DURATION = 0.35 -- 短冲刺表现参数，不是额外玩法冷却。
local JELLY_PUSH_SPEED = 6 -- 弹开速度增量（米/秒），不改变接触范围或2.5秒冷却。
local VIOLENT_SHAKE = 4 -- 输入速度增量阈值（米/秒），表现实现参数。

local HANDLED = {
    chick = true, sheep = true, pig = true, calf = true, grass = true, hay = true,
    poop = true, golden_poop = true, diamond_poop = true, rainbow_poop = true,
    gecko = true, cactus = true, abacus = true, bodyguard = true, chicken_keeper = true,
    splitter = true, juice = true, discus_athlete = true, discus = true, compass = true,
    jelly = true, wool = true, sweater = true,
}
local PIG_FOOD = {
    apple = true, orange = true, enoki = true, tomato_egg = true,
    banana = true, banana_peel = true,
}

---@param item any
function Expansion.ResetRound(item)
    item.woolExtraEntry = nil
    item.shielded, item.anchored = false, false
    item.abacusMerges, item.calfDashRemaining = 0, 0
    item.discusWait, item.compassProgress = 0, 0
    item.calfDashHits, item.pendingConsumerUid = nil, nil
    item.discusOwnerUid, item.discusTargetUid, item.discusState = nil, nil, nil
    item.discusHolderUid = nil
    item.compassAngle, item.compassTravel, item.compassForced = nil, nil, nil
    item.cactusScale, item.cactusBonus = nil, 0
    Rotation.ResetRound(item)
    item.geckoContactTime = 0
    item.eventMult = 1
    RelicExpansion.ResetRound(item)
end

--- 仅新建/转化时调用；恢复存档不能调用本函数覆盖永久数据。
---@param item any
function Expansion.InitItem(item)
    item.valueBase = nil
    item.refreshCount = 0
    item.woolCount = 0
    Expansion.ResetRound(item)
end

---@param game BottleGame
---@param item any
---@param events GameEvent[]
---@param value number
local function Buff(game, item, events, value)
    events[#events + 1] = { kind = "buff", uid = item.uid, id = item.id, value = value }
    game.revision = game.revision + 1
end

---@param game BottleGame
---@param item any
---@param events GameEvent[]
---@param value number
local function Permanent(game, item, events, value)
    item.permBonus = (item.permBonus or 0) + value
    Buff(game, item, events, value)
end

---@param game BottleGame
---@param uid number?
---@param contacts any
---@return any
local function Position(game, uid, contacts)
    if not uid then return nil end
    return (contacts and contacts.positions and contacts.positions[uid])
        or (game._lastPositions and game._lastPositions[uid])
end

---@param game BottleGame
---@param item any
---@param contacts any
---@param predicate fun(other:any):boolean
---@return any
local function FirstAdjacent(game, item, contacts, predicate)
    for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
        FrameBudget.Checkpoint()
        if other.uid ~= item.uid and other.location == "bottle" and predicate(other) then
            return other
        end
    end
    return nil
end

---@param other any
---@return boolean
local function Animal(other) return Items.HasTag(other.id, "动物") end
---@param other any
---@return boolean
local function Plant(other) return Items.HasTag(other.id, "植物") end
---@param contacts any
---@return any
local function RealContacts(contacts)
    return { pairs = contacts.rawPairs or contacts.pairs or {} }
end
---@param game BottleGame
---@param other any
---@return boolean
local function Piercing(game, other)
    return Items.IsPiercing(other.id, game)
end

--- 壁虎只读取真实接触；培根派生的逻辑相邻不能冒充可黏附的物理支撑。
---@param game BottleGame
---@param item any
---@param contacts any
---@return boolean
local function GeckoContact(game, item, contacts)
    if contacts.side and contacts.side[item.uid] == true then return true end
    for _, pair in ipairs(contacts.rawPairs or contacts.pairs or {}) do
        FrameBudget.Checkpoint()
        local uid = pair[1] == item.uid and pair[2] or pair[2] == item.uid and pair[1] or nil
        local other = uid and game:Get(uid)
        if other and other.location == "bottle" and other.id == "gecko" then return true end
    end
    return false
end

--- nil 交旧规则；本模块负责但没有主动触发的类型明确返回 false。
---@param game BottleGame
---@param item any
---@param contacts any
---@return boolean?
function Expansion.Touches(game, item, contacts)
    if not HANDLED[item.id] then return nil end
    if item.location ~= "bottle" then return false end
    local id = item.id
    if id == "chick" then return true end
    if id == "compass" then return (item.compassProgress or 0) >= TURN - EPSILON end
    if id == "gecko" then
        return not item.anchored and (item.geckoContactTime or 0) >= 0.25 - EPSILON
            and GeckoContact(game, item, contacts)
    end
    if id == "grass" or id == "hay" then
        return FirstAdjacent(game, item, contacts, Animal) ~= nil
    end
    if id == "poop" or id == "golden_poop" or id == "diamond_poop" or id == "rainbow_poop" then
        return FirstAdjacent(game, item, contacts, Plant) ~= nil
    end
    if id == "pig" then
        return FirstAdjacent(game, item, contacts, function(other) return PIG_FOOD[other.id] == true end) ~= nil
    end
    if id == "cactus" then
        return FirstAdjacent(game, item, contacts, function(other)
            return other.id == "droplet" or other.id == "balloon"
        end) ~= nil
    end
    if id == "chicken_keeper" then
        return FirstAdjacent(game, item, contacts, function(other) return other.id == "egg" end) ~= nil
    end
    if id == "splitter" then
        return FirstAdjacent(game, item, RealContacts(contacts), function(other) return Piercing(game, other) end) ~= nil
    end
    if id == "jelly" then
        return FirstAdjacent(game, item, RealContacts(contacts), function(other) return not Piercing(game, other) end) ~= nil
    end
    if id == "sweater" then
        return FirstAdjacent(game, item, contacts, function(other) return other.id == "wool" end) ~= nil
    end
    return false
end

--- 公共气球爆炸：先成功消费再翻倍，供结算膨胀与仙人掌共用，避免重复爆炸。
---@param game BottleGame
---@param balloon any
---@param events GameEvent[]
---@param consumer any
---@return boolean
function Expansion.BurstBalloon(game, balloon, events, consumer)
    if balloon.id ~= "balloon" or balloon.location ~= "bottle" then return false end
    local first = #events + 1
    if not game:_Destroy(balloon.uid, false, events, consumer, "burst") then return false end
    for _, other in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        other.eventMult = (other.eventMult or 1) * 2
        other.mult = (other.mult or 1) * 2
    end
    -- 先burst后remove供表现层读取爆点；成功消费确定之后再插入，失败不留伪爆炸。
    table.insert(events, first, { kind = "burst", uid = balloon.uid, id = "balloon", value = 2 })
    game.revision = game.revision + 1
    return true
end

--- 仙人掌实际正向尺寸增幅换成本回合倍率加数，物理尺寸本身仍永久保留。
---@param game BottleGame
---@param item any
---@param events GameEvent[]
local function TrackCactus(game, item, events)
    local scale = item.scale or 1
    local previous = item.cactusScale
    item.cactusScale = scale
    if previous and scale > previous + EPSILON then
        item.cactusBonus = (item.cactusBonus or 0) + (scale - previous)
        Buff(game, item, events, scale - previous)
    end
end

---@param game BottleGame
---@param consumer any
---@param events GameEvent[]
---@param origin any
local function GrassProduct(game, consumer, events, origin)
    -- 优质小草只保证动物产出；剔除空签后按原60份权重重抽，人类仍走原100签。
    local guaranteed = Animal(consumer) and Relics.Has(game, "premium_grass")
    local roll = game:_RandomInt(guaranteed and 60 or 100)
    local threshold = guaranteed and roll + 40 or roll
    local id = threshold <= 40 and "" or threshold <= 80 and "poop"
        or threshold <= 95 and "golden_poop" or threshold <= 99 and "diamond_poop" or "rainbow_poop"
    if id ~= "" then
        local product = game:_Spawn(id, events, false, origin)
        if guaranteed and product then TriggerFeedback.Relic(game, events, "premium_grass") end
    end
end

--- 只有入瓶后才吃草；满瓶的草保留对应动物 uid，排队期间不产生收益。
---@param game BottleGame
---@param grass any
---@param events GameEvent[]
function Expansion.OnEnter(game, grass, events)
    -- 满瓶分裂产生的复制飞盘，实际入场后才恢复它保存的飞行目标。
    if grass.id == "discus" and grass.location == "bottle" and grass.discusState == "flying"
        and grass.discusTargetUid then
        events[#events + 1] = { kind = "flight", uid = grass.uid, ownerUid = grass.discusOwnerUid,
            targetUid = grass.discusTargetUid }
        return
    end
    if grass.id ~= "grass" or not grass.pendingConsumerUid or grass.location ~= "bottle" then return end
    local consumer = game:Get(grass.pendingConsumerUid)
    grass.pendingConsumerUid = nil
    if consumer and consumer.location == "bottle" and Animal(consumer) then
        game:_Destroy(grass.uid, false, events, consumer, "consume")
    end
end

---@param game BottleGame
---@param target any
---@param consumer any
---@param events GameEvent[]
---@param reason string?
---@return boolean allowed
function Expansion.BeforeDestroy(game, target, consumer, events, reason)
    if reason == "exhausted" then return true end
    if target.shielded then return false end
    if not Items.HasTag(target.id, "人类") then return true end
    for _, guard in ipairs(game:BottleItems()) do
        if guard.id == "bodyguard" and guard.uid ~= target.uid and (guard.counter or 0) < 3 then
            target.shielded = true
            guard.counter = (guard.counter or 0) + 1
            Buff(game, target, events, 1)
            Buff(game, guard, events, guard.counter)
            game:_Score(events, target, game:_Value(target), Position(game, target.uid))
            if guard.counter >= 3 then
                -- 耗尽属于直接离场，不允许另一位保镖再次保护它。
                game:_Destroy(guard.uid, false, events, nil, "exhausted")
            end
            return false
        end
    end
    return true
end

--- 成功消费钩子；幽灵的被消耗结算由 GameLifecycle._Destroy 统一处理，羊毛无被耗结算。
--- consumer 可为 nil 或遗物占位对象，只对仍在瓶内的真实实例提供消费收益。
---@param game BottleGame
---@param target any
---@param consumer any
---@param events GameEvent[]
---@param reason string?
---@param value number
function Expansion.OnConsumed(game, target, consumer, events, reason, value)
    RelicExpansion.OnConsumed(game, target, events)
    -- 彩虹返还概率属于被消耗物本身，即使无实体消耗者（例如公共消耗接口）也判定。
    if target.id == "rainbow_poop" and game:_RandomInt(5) == 1 then
        game:_SpawnTop("poop", events, false)
        game:_SpawnTop("golden_poop", events, false)
        game:_SpawnTop("diamond_poop", events, false)
    end
    local alive = consumer and consumer.location == "bottle" and consumer.uid ~= target.uid
    if not alive then return end
    local origin = Position(game, target.uid) or Position(game, consumer.uid)
    if target.id == "grass" and (Animal(consumer) or Items.HasTag(consumer.id, "人类")) then
        GrassProduct(game, consumer, events, origin)
        if consumer.id == "sheep" then
            GrassProduct(game, consumer, events, origin)
            if game:_RandomInt(2) == 1 then
                consumer.woolCount = (consumer.woolCount or 0) + 1
                Buff(game, consumer, events, consumer.woolCount)
            end
        end
    elseif target.id == "poop" or target.id == "golden_poop" then
        local amount = target.id == "poop" and 1 or 3
        Permanent(game, consumer, events, amount)
        if game:_RandomInt(5) == 1 then Permanent(game, consumer, events, amount) end
    elseif target.id == "diamond_poop" then
        consumer.permMult = (consumer.permMult or 1) * 1.2
        Buff(game, consumer, events, 1.2)
    elseif target.id == "rainbow_poop" then
        consumer.eventMult = (consumer.eventMult or 1) * 1.5
        consumer.mult = (consumer.mult or 1) * 1.5
        Buff(game, consumer, events, 1.5)
    elseif target.id == "juice" then
        Permanent(game, consumer, events, value)
    elseif target.id == "droplet" and consumer.id == "cactus" then
        TrackCactus(game, consumer, events)
        local def = Items.byId[consumer.id]
        consumer.scale = math.min(def.scaleMax or Items.Settings.maxScale or 2,
            (consumer.scale or 1) + 0.1)
        TrackCactus(game, consumer, events)
        game:ApplyScale(consumer, events)
    end
    -- 小猪任何成功消费都增长，包含小草，也包含消费后已转化成皮的香蕉。
    if consumer.id == "pig" then
        local def = Items.byId.pig
        local maximum = def.scaleMax or Items.Settings.maxScale or 2
        local scale = math.min(maximum, (consumer.scale or 1) + 0.1)
        local weight = math.min(def.weightMax or Items.Settings.maxWeight or 2, (consumer.weight or 1) + 0.1)
        consumer.scale, consumer.weight = scale, weight
        if scale >= maximum - EPSILON then
            game:_Transform(consumer, "bacon", events)
            -- 物理修改默认永久：转化不撤回猪已长成的体积和重量。
            consumer.scale, consumer.weight = scale, weight
        end
        game:ApplyScale(consumer, events)
    elseif consumer.id == "calf" then
        consumer.calfDashRemaining, consumer.calfDashHits = DASH_DURATION, {}
        RelicExpansion.OnDash(game, consumer, events)
        local from, to = Position(game, consumer.uid), origin
        events[#events + 1] = { kind = "dash", uid = consumer.uid, duration = DASH_DURATION,
            targetUid = target.uid, dx = from and to and to.x - from.x or nil,
            dy = from and to and to.y - from.y or nil }
    end
end

--- 分裂不是消费：原件与新件分别保存当前有效价值的一半（向上取整）。
--- 清数值增益避免二次乘算，但尺寸/重量/临时性及飞盘必要状态保留。
---@param game BottleGame
---@param target any
---@param contacts any
---@param events GameEvent[]
---@return boolean
local function Split(game, target, contacts, events)
    local half = math.ceil(game:_Value(target) / 2)
    local copy = game:_Spawn(target.id, events, target.generatedTemporary == true,
        Position(game, target.uid, contacts))
    if not copy then return false end
    copy.temporary, copy.generatedTemporary = target.temporary, target.generatedTemporary
    copy.scale, copy.weight = target.scale, target.weight
    copy.bottleRounds, copy.counter, copy.settleCount = target.bottleRounds, target.counter, target.settleCount
    for _, item in ipairs({ target, copy }) do
        item.valueBase, item.bonus, item.permBonus = half, 0, 0
        item.permMult, item.eventMult, item.mult = 1, 1, 1
        item.cactusBonus, item.jackpotBonus = 0, 0
        item.rollValue = nil
        Buff(game, item, events, half)
    end
    -- resize 仅同步复制件的物理参数；必须先发出，再发 flight，否则重建会取消飞行。
    if copy.location == "bottle" then game:ApplyScale(copy, events) end
    if target.id == "discus" then
        copy.discusOwnerUid, copy.discusTargetUid = target.discusOwnerUid, target.discusTargetUid
        copy.discusHolderUid = target.discusHolderUid
        copy.discusState, copy.discusWait = target.discusState, target.discusWait
        -- 新盘没有旧盘的已走里程；沿同一目标开始新的受控弧线。
        if copy.location == "bottle" and copy.discusState == "flying" and copy.discusTargetUid then
            local from, to = Position(game, target.uid, contacts), Position(game, copy.discusTargetUid, contacts)
            events[#events + 1] = { kind = "flight", uid = copy.uid, ownerUid = copy.discusOwnerUid,
                targetUid = copy.discusTargetUid, fromX = from and from.x, fromY = from and from.y,
                toX = to and to.x, toY = to and to.y }
        end
    end
    return true
end

---@param game BottleGame
---@param item any
---@param contacts any
---@param events GameEvent[]
---@return boolean
function Expansion.Apply(game, item, contacts, events)
    if Expansion.Touches(game, item, contacts) ~= true then return false end
    local id = item.id
    if id == "chick" then
        -- 周期到点仅判定一次；失败仍由调度器等待下一个完整5秒。
        if game:_RandomInt(100) > 30 then return false end
        local origin = Position(game, item.uid, contacts)
        local egg = game:_Spawn("egg", events, false, origin)
        if egg and egg.location == "bottle" then
            events[#events + 1] = {kind = "itemFeedback", action = "produce", uid = item.uid, id = id,
                x = origin and origin.x, y = origin and origin.y, count = 1, producedUids = {egg.uid}}
        end
        return egg ~= nil
    elseif id == "grass" or id == "poop" or id == "golden_poop"
        or id == "diamond_poop" or id == "rainbow_poop" then
        local consumer = FirstAdjacent(game, item, contacts, id == "grass" and Animal or Plant)
        if not consumer then return false end
        return game:_Destroy(item.uid, false, events, consumer, "consume") == true
    elseif id == "hay" then
        local animals = game:_Adjacents(item.uid, contacts)
        local count = 0
        for _, animal in ipairs(animals) do
            FrameBudget.Checkpoint()
            if animal.location == "bottle" and Animal(animal) then
                local grass = game:_Spawn("grass", events, false, Position(game, animal.uid, contacts))
                if grass then
                    grass.pendingConsumerUid = animal.uid
                    Expansion.OnEnter(game, grass, events)
                    count = count + 1
                end
            end
        end
        if count == 0 then return false end
        local delta = Relics.Has(game, "lucky_charm") and 1 or -1
        Permanent(game, item, events, delta)
        if delta > 0 then TriggerFeedback.Relic(game, events, "lucky_charm") end
        if game:_Value(item) <= 0 then game:_Destroy(item.uid, false, events, nil, "self") end
        return true
    elseif id == "pig" or id == "cactus" or id == "chicken_keeper" or id == "sweater" then
        local hit = false
        for _, other in ipairs(game:_Adjacents(item.uid, contacts)) do
            FrameBudget.Checkpoint()
            if item.id ~= id then break end -- 猪转培根后不能继续执行旧批次。
            local legal = id == "pig" and PIG_FOOD[other.id]
                or id == "cactus" and (other.id == "droplet" or other.id == "balloon")
                or id == "chicken_keeper" and other.id == "egg"
                or id == "sweater" and other.id == "wool"
            if legal then
                local value = game:_Value(other)
                local consumed = false
                if other.id == "balloon" and id == "cactus" then
                    consumed = Expansion.BurstBalloon(game, other, events, item)
                else
                    consumed = game:_Destroy(other.uid, false, events, item, "consume")
                end
                if consumed then
                    hit = true
                    if id == "pig" then
                        -- _Destroy可能已把香蕉转皮、猪长成培根；必须用消费前保存值，
                        -- 且按本次主动消费者身份给钱，不让转化吞掉最后一餐收益。
                        game:_Score(events, item, value * 2, Position(game, item.uid, contacts), "consume", id)
                    elseif id == "chicken_keeper" then
                        game:_Score(events, item, value, Position(game, item.uid, contacts), "consume", id)
                        if game:_RandomInt(2) == 1 then
                            game:_Spawn("chick", events, false, Position(game, item.uid, contacts))
                        end
                    elseif id == "sweater" then Permanent(game, item, events, 1) end
                end
            end
        end
        return hit
    elseif id == "gecko" then
        local position = Position(game, item.uid, contacts)
        item.anchored = true
        events[#events + 1] = { kind = "anchor", uid = item.uid,
            x = position and position.x, y = position and position.y }
        return true
    elseif id == "splitter" then
        local hit = false
        for _, other in ipairs(game:_Adjacents(item.uid, RealContacts(contacts))) do
            FrameBudget.Checkpoint()
            if Piercing(game, other) and Split(game, other, contacts, events) then hit = true end
        end
        return hit
    elseif id == "compass" then
        item.compassProgress = math.max(0, item.compassProgress - TURN)
        for _, other in ipairs(game:BottleItems()) do
            FrameBudget.Checkpoint()
            local ghostLike = other.id == "ghost"
                or (Relics.Has(game, "ghost_poop") and Items.IsPoop(other.id))
            if not ghostLike then
                events[#events + 1] = { kind = "rotate", uid = other.uid,
                    delta = -math.pi / 2, excludeCompass = true }
            end
        end
        return true
    elseif id == "jelly" then
        local hit = false
        local origin = Position(game, item.uid, contacts)
        for _, other in ipairs(game:_Adjacents(item.uid, RealContacts(contacts))) do
            FrameBudget.Checkpoint()
            if not Piercing(game, other) then
                local position = Position(game, other.uid, contacts)
                local dx = origin and position and position.x - origin.x or 0
                local dy = origin and position and position.y - origin.y or 0
                if dx * dx + dy * dy < EPSILON then dx = other.uid > item.uid and 1 or -1 end
                events[#events + 1] = { kind = "impulse", uid = other.uid,
                    sourceUid = item.uid, dx = dx, dy = dy, strength = JELLY_PUSH_SPEED }
                events[#events + 1] = {kind = "itemFeedback", action = "jelly", uid = item.uid, id = id,
                    targetUid = other.uid, targetId = other.id,
                    x = origin and origin.x, y = origin and origin.y,
                    toX = position and position.x, toY = position and position.y}
                hit = true
            end
        end
        return hit
    end
    return false
end

--- 成功合成的结果为硬币才通知算盘；被消费的羊毛不能虚构硬币合成事件。
---@param game BottleGame
---@param a any
---@param b any
---@param result any
---@param contacts any
---@param events GameEvent[]
function Expansion.OnMerge(game, a, b, result, contacts, events)
    if not result or not result.id:match("^coin_%d+$") then return end
    for _, abacus in ipairs(game:BottleItems()) do
        if abacus.id == "abacus" then
            Permanent(game, abacus, events, 1)
            abacus.abacusMerges = (abacus.abacusMerges or 0) + 1
            if abacus.abacusMerges >= 3 then
                abacus.abacusMerges = abacus.abacusMerges - 3
                game:_Score(events, abacus, game:_Value(abacus), Position(game, abacus.uid, contacts))
            end
        end
    end
end

--- 羊毛合成的新件永久存在；有效价值严格大于10才转成羊毛衫。
---@param game BottleGame
---@param a any
---@param b any
---@param contacts any
---@param events GameEvent[]
---@return boolean?
function Expansion.TryMerge(game, a, b, contacts, events)
    local relicMerge = RelicExpansion.TryMerge(game, a, b, contacts, events)
    if relicMerge ~= nil then return relicMerge end
    if a.id ~= "wool" or b.id ~= "wool" then return nil end
    if a.uid == b.uid or a.location ~= "bottle" or b.location ~= "bottle" then return false end
    local value = game:_Value(a) + game:_Value(b)
    local posA, posB = Position(game, a.uid, contacts), Position(game, b.uid, contacts)
    local origin = posA and posB and { x = (posA.x + posB.x) / 2, y = (posA.y + posB.y) / 2 } or nil
    if not Expansion.BeforeDestroy(game, a, nil, events, "merge")
        or not Expansion.BeforeDestroy(game, b, nil, events, "merge") then return false end
    if not game:_Destroy(a.uid, false, events, nil, "merge_checked") then return false end
    if not game:_Destroy(b.uid, false, events, nil, "merge_checked") then return false end
    local result = game:_Spawn(value > 10 and "sweater" or "wool", events, false, origin)
    if not result then return false end
    if result.id == "wool" then result.valueBase = value end
    for index = #events, 1, -1 do
        local event = events[index]
        if event.uid == result.uid and event.kind == "spawn" then
            event.kind, event.a, event.b = "merge", a.uid, b.uid
            break
        end
    end
    return true
end

---@param game BottleGame
function Expansion.OnRefresh(game)
    for _, keeper in ipairs(game:AllInstances()) do
        FrameBudget.Checkpoint()
        if keeper.id == "chicken_keeper" and (keeper.location == "bottle"
            or keeper.location == "deck" or keeper.location == "queued") then
            keeper.refreshCount = (keeper.refreshCount or 0) + 1
            if keeper.refreshCount >= 5 then
                keeper.refreshCount = keeper.refreshCount - 5
                keeper.permBonus = keeper.permBonus + 1
                game.revision = game.revision + 1
            end
        end
    end
end

--- 剧烈摇晃或小刀触碰的公共脱毛；一次脱落全部库存，产物默认永久。
--- 先清库存再生成，满瓶时由公共生成队列承接，不能复制或丢失库存。
---@param game BottleGame
---@param sheep any
---@param events GameEvent[]
---@return boolean
function Expansion.ShedWool(game, sheep, events)
    if sheep.id ~= "sheep" or sheep.location ~= "bottle" or (sheep.woolCount or 0) <= 0 then return false end
    local count = sheep.woolCount
    sheep.woolCount = 0
    Buff(game, sheep, events, 0)
    local product = Relics.Has(game, "wool_market") and "coin_1" or "wool"
    for _ = 1, count do
        FrameBudget.Checkpoint()
        local spawned = game:_SpawnTop(product, events, false)
        if spawned and product == "coin_1" then TriggerFeedback.Relic(game, events, "wool_market") end
    end
    return true
end

--- 回合准备额外入场候选：只返回现有牌库羊毛，保 uid，不创建新物品。
--- Game 负责排除它们的20件抽取名额、顶部入场与 woolExtraEntry 标记。
---@param game BottleGame
---@return ItemInstance[]
function Expansion.ExtraEntrants(game)
    local result = {}
    for _, item in ipairs(game:AllInstances()) do
        FrameBudget.Checkpoint()
        if item.id == "wool" and item.location == "deck"
            and (not item.woolReadyRound or item.woolReadyRound <= game.round)
            and math.abs(game:_Value(item) - 1) < EPSILON then
            result[#result + 1] = item
        end
    end
    return result
end

--- 只维护羊毛阈值，供离散效果与结算前奏后的最终价值同步调用。
--- 不推进运动、概率、飞盘或冷却，不能递归触发全体结算前奏。
---@param game BottleGame
---@param events GameEvent[]
function Expansion.Maintain(game, events)
    for _, item in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if item.id == "wool" and game:_Value(item) > 10 then
            game:_Transform(item, "sweater", events)
        end
    end
end

---@param game BottleGame
---@param contacts any
---@param events GameEvent[]
function Expansion.BeforeSettle(game, contacts, events)
    for _, item in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if item.id == "cactus" then TrackCactus(game, item, events) end
    end
end

---@param game BottleGame
---@param events GameEvent[]
---@param contacts BottleStepContacts?
function Expansion.AfterSettle(game, events, contacts)
    -- 先完成全体收益，移除币才普通自耗：成功才发次数，临时币也按同一口径。
    for _, coin in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if coin.id == "removal_coin" and game:_Destroy(coin.uid, false, events, nil, "self") then
            game.removals = game.removals + 1
            game.revision = game.revision + 1
            print(string.format("[移除币] #%d结算后成功自耗，机会+1，剩余%d", coin.uid, game.removals))
        end
    end
    for _, egg in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if egg.id == "egg" and egg.bottleRounds >= 3 then
            local position = Position(game, egg.uid, contacts)
            if game:_Destroy(egg.uid, false, events, nil, "self") and game:_RandomInt(2) == 1 then
                game.refreshes = (game.refreshes or 0) + 1
                game.revision = game.revision + 1
                TriggerFeedback.Refresh(events, egg, position)
            end
        end
    end
end

---@param game BottleGame
---@param discus any
---@param contacts any
---@param events GameEvent[]
local function ThrowDiscus(game, discus, contacts, events)
    ---@type ItemInstance[]
    local candidates = {}
    for _, other in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if other.uid ~= discus.uid and other.uid ~= discus.discusHolderUid then
            candidates[#candidates + 1] = other
        end
    end
    if #candidates == 0 then
        discus.discusState, discus.discusWait = "owner_wait", 3
        return
    end
    local target = assert(candidates[game:_RandomInt(#candidates)])
    local from, to = Position(game, discus.uid, contacts), Position(game, target.uid, contacts)
    discus.discusTargetUid, discus.discusState, discus.discusWait = target.uid, "flying", 0
    events[#events + 1] = { kind = "flight", uid = discus.uid, ownerUid = discus.discusOwnerUid,
        targetUid = target.uid, fromX = from and from.x, fromY = from and from.y,
        toX = to and to.x, toY = to and to.y }
end

---@param game BottleGame
---@param discus any
---@param contacts any
---@param events GameEvent[]
local function ReturnDiscus(game, discus, contacts, events)
    local owner = game:Get(discus.discusOwnerUid or 0)
    local position = owner and owner.location == "bottle" and Position(game, owner.uid, contacts) or nil
    discus.discusState, discus.discusTargetUid, discus.discusWait = "owner_wait", nil, 3
    discus.discusHolderUid = discus.discusOwnerUid
    if position then
        events[#events + 1] = { kind = "teleport", uid = discus.uid, x = position.x, y = position.y }
        game._lastPositions[discus.uid] = nil -- 闪现的直线距离不产生飞盘收益。
    end
end

---@param game BottleGame
---@param dt number
---@param contacts any
---@param events GameEvent[]
function Expansion.Step(game, dt, contacts, events)
    Expansion.Maintain(game, events)
    if (contacts.shakeStrength or 0) >= VIOLENT_SHAKE then
        for _, sheep in ipairs(game:BottleItems()) do
            FrameBudget.Checkpoint()
            if sheep.id == "sheep" and game:IsSampled(sheep) then Expansion.ShedWool(game, sheep, events) end
        end
    end
    -- 每位运动员至少拥有一枚盘；分裂额外复制的盘也保留独立飞行，不再重复补原盘。
    local owned = {}
    for _, item in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if item.id == "discus" and item.discusOwnerUid then owned[item.discusOwnerUid] = true end
    end
    for _, item in ipairs(game:AllInstances()) do
        FrameBudget.Checkpoint()
        if item.id == "discus" and item.location == "queued" and item.discusOwnerUid then
            owned[item.discusOwnerUid] = true
        end
    end
    for _, athlete in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if athlete.id == "discus_athlete" and game:IsSampled(athlete) and not owned[athlete.uid] then
            local discus = game:_Spawn("discus", events, true, Position(game, athlete.uid, contacts))
            if discus then
                discus.discusOwnerUid, discus.discusState, discus.discusWait = athlete.uid, "owner_wait", 0
                discus.discusHolderUid = athlete.uid
                owned[athlete.uid] = true
            end
        end
    end
    for _, item in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if game:IsSampled(item) then
        if item.id == "gecko" and not item.anchored then
            item.geckoContactTime = GeckoContact(game, item, contacts)
                and (item.geckoContactTime or 0) + dt or 0
        elseif item.id == "cactus" then
            TrackCactus(game, item, events)
        elseif item.id == "calf" and (item.calfDashRemaining or 0) > 0 then
            local hits = item.calfDashHits or {}
            item.calfDashHits = hits
            for _, other in ipairs(game:_Adjacents(item.uid, RealContacts(contacts))) do
                FrameBudget.Checkpoint()
                if not hits[other.uid] then
                    hits[other.uid] = true
                    item.bonus = item.bonus + 1
                    Buff(game, item, events, 1)
                    TriggerFeedback.Reward(events, item, 1, "value", "collision",
                        Position(game, item.uid, contacts))
                end
            end
            item.calfDashRemaining = math.max(0, item.calfDashRemaining - dt)
        elseif item.id == "compass" then
            local angle = contacts.angles and contacts.angles[item.uid]
            local travel = contacts.angularTravel and contacts.angularTravel[item.uid]
            local forced = contacts.rotateOffsets and contacts.rotateOffsets[item.uid] or 0
            if travel then
                local previous = item.compassTravel or 0
                -- 物理重建会把累积值归零；不能把归零误当巨大旋转。
                item.compassProgress = (item.compassProgress or 0) + math.max(0, travel - previous)
                item.compassTravel = travel
            elseif angle then
                if item.compassAngle then
                    local delta = angle - item.compassAngle - (forced - (item.compassForced or 0))
                    delta = (delta + math.pi) % TURN - math.pi
                    item.compassProgress = (item.compassProgress or 0) + math.abs(delta)
                end
            end
            item.compassAngle, item.compassForced = angle, forced
        elseif item.id == "discus" then
            -- 按源表每真实飞行5米结算；闪回清采样基线，不计传送路程。
            while (item.distance or 0) >= 5 - EPSILON do
                FrameBudget.Checkpoint()
                item.distance = math.max(0, item.distance - 5)
                game:_Score(events, item, game:_Value(item), Position(game, item.uid, contacts))
                events[#events].trigger = "move"
            end
            if item.discusState == "flying" then
                local hitUid = contacts.flightHits and contacts.flightHits[item.uid]
                local arrived = contacts.flightArrived and contacts.flightArrived[item.uid]
                if hitUid then
                    local target = game:Get(hitUid)
                    if target and target.location == "bottle" and Items.HasTag(target.id, "人类") then
                        item.discusState, item.discusWait = "human_wait", 0.2
                        item.discusHolderUid = hitUid
                    else ReturnDiscus(game, item, contacts, events) end
                elseif arrived then ReturnDiscus(game, item, contacts, events) end
            else
                item.discusWait = math.max(0, (item.discusWait or 0) - dt)
                if item.discusWait <= EPSILON then ThrowDiscus(game, item, contacts, events) end
            end
        end
    end
    end
end

return Expansion
