-- 按当前阶段选择刷新池；遗物免费次数独立于准备/物品共享池。
local RefreshUI = {}

---@param game BottleGame
---@return integer
function RefreshUI.Count(game)
    local balance = game.refreshes
    if game.phase == "draft" and game.relicDraft then balance = game.relicRefreshes end
    return math.max(0, math.floor(balance or 0))
end

---@param game BottleGame
---@param verb string?
---@return string
function RefreshUI.ButtonText(game, verb)
    return (verb or "刷新") .. " · " .. RefreshUI.Count(game) .. " 次"
end

---@param game BottleGame
---@return string
function RefreshUI.Hint(game)
    if game.phase == "draft" and game.relicDraft then
        return "遗物独立刷新剩余 " .. RefreshUI.Count(game) .. " 次 · 本次免费1次，不累计"
    end
    return "准备/物品共享刷新剩余 " .. RefreshUI.Count(game) .. " 次 · 每完成2回合+1"
end

return RefreshUI
