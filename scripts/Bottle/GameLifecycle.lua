-- 物品生成、排队与消耗生命周期。规则保持纯 Lua；所有接触/运动仍由物理层提供。
-- 满瓶只延后入场，不吞掉产物；队列在一次效果批次结束后补位，避免抢占合成名额。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicEffects = require("Bottle.RelicEffects")
local Expansion = require("Bottle.ExpansionEffects")
local Lifecycle = {}

local function RemoveReference(array, uid)
    for i = #array, 1, -1 do
        if array[i].uid == uid then table.remove(array, i) end
    end
end

local function AddReference(array, item)
    for _, other in ipairs(array) do if other.uid == item.uid then return end end
    array[#array + 1] = item
end

---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
local function FruitHook(game, item, events)
    if Relics.Has(game, "gm_fruit") and Items.HasTag(item.id, "水果")
        and game:_RandomInt(10) == 1 then
        local pool = { "apple", "banana", "orange", "cherry" }
        game:_SpawnTop(pool[game:_RandomInt(#pool)], events)
    end
end

---@param game BottleGame
---@param id string
---@param events GameEvent[]
---@param temporary boolean?
---@param origin {x:number,y:number}?
---@return ItemInstance
function Lifecycle.Spawn(game, id, events, temporary, origin)
    local item = game:_Create(id, temporary)
    item.generatedTemporary = temporary == true
    if #game:BottleItems() >= Items.Settings.bottleLimit or #game.spawnQueue > 0 then
        item.location = "queued"
        game.spawnQueue[#game.spawnQueue + 1] = item.uid
        if origin then game._queueOrigins[item.uid] = {x=origin.x, y=origin.y} end
        game.revision = game.revision + 1
    else
        game:_EnterBottle(item, events)
        local event = events[#events]
        if origin and event and event.kind == "spawn" then event.x, event.y = origin.x, origin.y end
    end
    return item
end

---@param game BottleGame
---@param events GameEvent[]
function Lifecycle.DrainQueue(game, events)
    if game._drainingQueue or game.phase ~= "running" then return end
    game._drainingQueue = true
    while #game.spawnQueue > 0 and #game:BottleItems() < Items.Settings.bottleLimit do
        local uid = table.remove(game.spawnQueue, 1)
        local item = game:Get(uid)
        local origin = game._queueOrigins[uid]
        game._queueOrigins[uid] = nil
        if item and item.location == "queued" then
            game:_EnterBottle(item, events)
            local event = events[#events]
            if origin and event and event.kind == "spawn" then event.x, event.y = origin.x, origin.y end
            if Expansion.OnEnter then Expansion.OnEnter(game, item, events) end
        end
    end
    game._drainingQueue = false
end

---consumer 是真正执行消耗的实例；nil 表示自耗/系统移除，不猜测最近接触对象。
---临时消耗 temporary 与临时生成 generatedTemporary 分开，避免回合末错误返还产物。
---@param game BottleGame
---@param uid integer
---@param temporary boolean
---@param events GameEvent[]
---@param consumer ItemInstance?
---@param reason string?
---@return boolean
function Lifecycle.Destroy(game, uid, temporary, events, consumer, reason)
    local item = game:Get(uid)
    if not item or item.location ~= "bottle" then return false end
    local cause = reason or (consumer and "consume" or "self")
    if cause ~= "exhausted" and cause ~= "merge_checked"
        and not Expansion.BeforeDestroy(game, item, consumer, events, cause) then return false end
    local value = game:_Value(item)
    local originalId = item.id
    local function Complete()
        Expansion.OnConsumed(game, item, consumer, events,
            cause == "merge_checked" and "merge" or cause, value)
        game.revision = game.revision + 1
        RelicEffects.MaintainHuntTarget(game)
        return true
    end
    if originalId == "banana" then
        -- 转化前执行水果钩子，避免将香蕉皮误当水果；香蕉皮本身不入弃牌堆。
        FruitHook(game, item, events)
        game:_Transform(item, "banana_peel", events)
        return Complete()
    end
    if originalId == "tomato_egg" then
        item.counter = item.counter + 1
        if item.counter < RelicEffects.TomatoEggLimit(game) then
            game:_RespawnTop(item, events)
        else
            item.location = "discard"
            RemoveReference(game.deck, uid)
            AddReference(game.discard, item)
            events[#events + 1] = {kind="remove",uid=uid,id=originalId}
        end
        return Complete()
    end
    if originalId == "enoki" then
        if Relics.Has(game, "see_you_tomorrow") then
            item.permBonus = item.permBonus + 1
            events[#events + 1] = {kind="buff",uid=uid,id=originalId,value=1}
        end
        game:_RespawnTop(item, events)
        return Complete()
    end
    if originalId == "ghost" then
        game:_Score(events, item, value, nil)
    end
    item.location = "discard"
    item.temporary = item.temporary or temporary
    if item.temporary and not item.generatedTemporary then AddReference(game.deck, item)
    else RemoveReference(game.deck, uid) end
    AddReference(game.discard, item)
    events[#events + 1] = {kind="remove",uid=uid,id=originalId}
    FruitHook(game, item, events)
    return Complete()
end

return Lifecycle
