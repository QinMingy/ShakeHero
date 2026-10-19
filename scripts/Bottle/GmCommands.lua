-- 物品 GM 独立执行入口：发布权限在任何参数解析、创建实例或修改候选之前检查。
local Items = require("Bottle.Items")
local PublishConfig = require("PublishConfig")
local Commands = {}

function Commands.Install(Game, OwnedTypes, DraftEligible)
    ---按数字编号或字符串 id 添加一件已实装物品，仅开发模式可用。
    ---运行／结算阶段拒绝，避免新增物品被回合前快照回滚。
    ---@param self BottleGame
    ---@param id string|integer
    ---@return boolean ok
    ---@return string message
    function Game.GmAddItem(self, id)
        -- 执行层兜底：隐藏按钮或修改 G 键显隐状态都不能绕过发布权限。
        if PublishConfig.PUBLISH_MODE ~= false then return false, "发布模式已禁用 GM" end
        if self.phase == "running" or self.phase == "settle" or self.phase == "reveal" then
            return false, "摇晃或结算进行中不能添加物品，请等本回合结束"
        end
        local numberId = type(id) == "number" and id or tonumber(id)
        local def = numberId and (Items.byNumber --[[@as table<number,ItemDef>]])[numberId] or Items.byId[id]
        if not def then return false, "未知物品 id：" .. tostring(id) end
        if not def.implemented then
            return false, string.format("%s（#%d）尚未实装，暂不能添加", def.name, def.numberId)
        end
        local item = self:_Create(def.id)
        if self.phase == "draft" and not self.relicDraft then
            -- 只移除失效物品候选；不补抽、不消耗随机数，不改遗物候选。
            local owned = OwnedTypes(self.deck)
            ---@type string[]
            local options = {}
            for _, option in ipairs(self.options) do
                if DraftEligible(Items.byId[option], owned) then options[#options + 1] = option end
            end
            self.options = options
        end
        self.revision = self.revision + 1
        return true, string.format("已添加 %s（#%d）到牌库，当前牌库 %d 件", def.name, item.uid, #self.deck)
    end
end

return Commands
