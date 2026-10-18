-- 共享刷新池的只读UI文案；不使用rerollUsed/refreshUsed决定可用性。
local RefreshUI = {}

---@param game BottleGame
---@return integer
function RefreshUI.Count(game)
    return math.max(0, math.floor(game.refreshes or 0))
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
    return "共享刷新剩余 " .. RefreshUI.Count(game) .. " 次 · 每完成2回合+1"
end

return RefreshUI
