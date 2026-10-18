-- 准备阶段每回合一次重抽、物品累计刷新池、遗物每组一次免费刷新分别显示。
local RefreshUI = {}

---@param game BottleGame
---@return integer
function RefreshUI.Count(game)
    if game.phase == "prepare" then return game.rerollUsed and 0 or 1 end
    if game.relicDraft then return game.refreshUsed and 0 or 1 end
    return math.max(0, math.floor(game.refreshes or 0))
end

---@param game BottleGame
---@param verb string?
---@return string
function RefreshUI.ButtonText(game, verb)
    return (verb or (game.phase == "prepare" and "重新抽取" or game.relicDraft and "免费刷新" or "刷新"))
        .. " · " .. RefreshUI.Count(game) .. " 次"
end

---@param game BottleGame
---@return string
function RefreshUI.Hint(game)
    if game.phase == "prepare" then
        return "重新抽取剩余 " .. RefreshUI.Count(game) .. " 次 · 每回合重置"
    end
    if game.relicDraft then
        return "遗物免费刷新剩余 " .. RefreshUI.Count(game) .. " 次 · 每次遗物三选一重置"
    end
    return "物品刷新剩余 " .. RefreshUI.Count(game) .. " 次 · 每完成2回合+1"
end

return RefreshUI
