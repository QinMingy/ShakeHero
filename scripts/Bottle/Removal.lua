-- 主动移除只处理当前拥有的单个物品实例；不是消费，不复用_Destroy或效果钩子。
local Items = require("Bottle.Items")
local RelicEffects = require("Bottle.RelicEffects")
local Removal = {}

---@param game BottleGame
---@return integer
function Removal.Count(game)
    return game.removals
end

---@param Game table
function Removal.Install(Game)
    ---@param uid integer
    ---@return boolean ok
    ---@return string message
    function Game:CanRemoveOwned(uid)
        if self.phase ~= "prepare" and self.phase ~= "draft" then
            return false, "仅准备或三选一阶段可移除物品"
        end
        if type(self.removals) ~= "number" or self.removals ~= self.removals
            or self.removals == math.huge or self.removals < 1
            or self.removals ~= math.floor(self.removals) then
            return false, "没有可用移除次数，每次考核达标后获得1次"
        end
        if type(uid) ~= "number" or uid ~= uid or uid == math.huge
            or uid < 1 or uid ~= math.floor(uid) then
            return false, "请选择当前拥有的一件物品"
        end
        local item = self:Get(uid)
        if item and (item.location == "deck" or item.location == "bottle") then
            for _, owned in ipairs(self.deck) do
                if owned == item then return true, "" end
            end
        end
        return false, "该物品已不在拥有牌库中"
    end

    --- 永久注销UID；同名其他实例、抽取顺序、候选与刷新池保持不变。
    --- 不调用_Draw/_Prepare补位，不触发被消费重生／收益／保护或消耗者奖励。
    ---@param uid integer
    ---@return boolean ok
    ---@return string message
    function Game:RemoveOwned(uid)
        local ok, message = self:CanRemoveOwned(uid)
        if not ok then
            print(string.format("[移除] 拒绝 uid=%s phase=%s：%s", tostring(uid), self.phase, message))
            return false, message
        end
        local item = assert(self:Get(uid))
        local def = assert(Items.byId[item.id])
        for index = #self.deck, 1, -1 do
            if self.deck[index] == item then table.remove(self.deck, index) end
        end
        for index = #self.drawn, 1, -1 do
            if self.drawn[index] == uid then table.remove(self.drawn, index) end
        end
        self._instances[uid] = nil
        self._lastPositions[uid] = nil
        self._queueOrigins[uid] = nil
        item.location = "removed"
        self.removals = self.removals - 1
        self.revision = self.revision + 1
        -- 移除既有追杀目标只维护目标引用，绝不冒领奖励或运行其它遗物维护。
        if self.huntTargetUid == uid then RelicEffects.MaintainHuntTarget(self) end
        print(string.format("[移除] 永久移除 %s #%d，剩余%d次，牌库%d件", def.name, uid,
            self.removals, #self.deck))
        return true, string.format("已永久移除 %s #%d · 剩余%d次", def.name, uid, self.removals)
    end
end

return Removal
