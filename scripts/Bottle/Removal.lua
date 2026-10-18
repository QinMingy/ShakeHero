-- 玩家主动移除：永久删掉所选实例，不经过消耗/销毁效果链。
local Items = require("Bottle.Items")
local RelicEffects = require("Bottle.RelicEffects")
local Removal = {}

---@param entries ItemInstance[]
---@param uid integer
local function RemoveInstance(entries, uid)
    for index = #entries, 1, -1 do
        if entries[index].uid == uid then table.remove(entries, index) end
    end
end

---@param entries number[]
---@param uid integer
local function RemoveUid(entries, uid)
    for index = #entries, 1, -1 do
        if entries[index] == uid then table.remove(entries, index) end
    end
end

---@param game BottleGame
---@param uid integer
---@return boolean, string
function Removal.Remove(game, uid)
    if game.phase ~= "prepare" and game.phase ~= "draft" and game.phase ~= "over" then
        return false, "请等待本回合结束后移除"
    end
    if (game.removals or 0) <= 0 then return false, "移除机会不足" end
    if type(uid) ~= "number" or uid ~= uid or uid <= 0 or uid == math.huge
        or uid % 1 ~= 0 then return false, "物品不存在" end
    local item = game:Get(uid)
    if not item or (item.location ~= "deck" and item.location ~= "bottle") then
        return false, "物品已不在牌库中"
    end
    local owned = false
    for _, entry in ipairs(game.deck) do
        if entry == item then owned = true; break end
    end
    if not owned then return false, "物品已不在牌库中" end

    RemoveInstance(game.deck, uid)
    RemoveInstance(game.discard, uid)
    RemoveUid(game.drawn, uid)
    RemoveUid(game.spawnQueue, uid)
    game._queueOrigins[uid] = nil
    game._lastPositions[uid] = nil
    game._instances[uid] = nil
    game.removals = game.removals - 1
    game.revision = game.revision + 1
    -- 追杀引用需要保持可存档；玩家移除不会发放追杀奖励。
    RelicEffects.MaintainHuntTarget(game)
    return true, "已移除" .. Items.byId[item.id].name
end

return Removal
