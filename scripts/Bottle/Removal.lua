-- 玩家主动移除：永久注销一个拥有实例，不经过消耗/销毁效果链。
-- UI负责独立二次确认；所有调用入口仍统一经过CanRemoveOwned的实时校验。
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
---@return integer
function Removal.Count(game)
    return game.removals
end

---@param game BottleGame
---@param uid integer
---@return boolean ok
---@return string message
function Removal.CanRemoveOwned(game, uid)
    if game.phase ~= "prepare" and game.phase ~= "draft" then
        return false, "仅准备或三选一阶段可移除物品"
    end
    if type(game.removals) ~= "number" or game.removals ~= game.removals
        or game.removals == math.huge or game.removals < 1
        or game.removals ~= math.floor(game.removals) then
        return false, "没有可用移除次数，每次考核达标后获得1次"
    end
    if type(uid) ~= "number" or uid ~= uid or uid == math.huge
        or uid < 1 or uid ~= math.floor(uid) then
        return false, "请选择当前拥有的一件物品"
    end
    local item = game:Get(uid)
    if item and (item.location == "deck" or item.location == "bottle") then
        for _, owned in ipairs(game.deck) do
            if owned == item then return true, "" end
        end
    end
    return false, "该物品已不在拥有牌库中"
end

--- 永久注销UID；同名其他实例、抽取顺序、候选与刷新池保持不变。
--- 不调用_Draw/_Prepare补位，不触发被消费重生／收益／保护或消耗者奖励。
--- 保留本地Removal.Remove/Game.RemoveItem入口，与远端RemoveOwned共用同一实现。
---@param game BottleGame
---@param uid integer
---@return boolean ok
---@return string message
function Removal.Remove(game, uid)
    local ok, message = Removal.CanRemoveOwned(game, uid)
    if not ok then
        print(string.format("[移除] 拒绝 uid=%s phase=%s：%s", tostring(uid), game.phase, message))
        return false, message
    end
    local item = assert(game:Get(uid))
    local def = assert(Items.byId[item.id])
    RemoveInstance(game.deck, uid)
    RemoveInstance(game.discard, uid)
    RemoveUid(game.drawn, uid)
    RemoveUid(game.spawnQueue, uid)
    game._instances[uid] = nil
    game._lastPositions[uid] = nil
    game._queueOrigins[uid] = nil
    item.location = "removed"
    game.removals = game.removals - 1
    game.revision = game.revision + 1
    -- 只维护被移除的追杀目标；不冒领奖励、不运行其他遗物维护。
    if game.huntTargetUid == uid then RelicEffects.MaintainHuntTarget(game) end
    print(string.format("[移除] 永久移除 %s #%d，剩余%d次，牌库%d件", def.name, uid,
        game.removals, #game.deck))
    return true, string.format("已永久移除 %s #%d · 剩余%d次", def.name, uid, game.removals)
end

---@param Game table
function Removal.Install(Game)
    Game.CanRemoveOwned = Removal.CanRemoveOwned
    Game.RemoveOwned = Removal.Remove
    Game.RemoveItem = Removal.Remove
end

return Removal
