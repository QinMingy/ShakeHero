-- 跨帧规则执行期间供 UI 读取的展示副本；不是存档，也不是另一局可推进的规则状态。
-- 调用方只读使用：不得对副本调用 Step/Consume 等写方法，尤其不得修改共享嵌套表。
local FrameBudget = require("Bottle.FrameBudget")
local PresentationState = {}

--- 只复制一层；实例复杂回合状态及回滚快照刻意保留原引用。
---@generic T
---@param source T
---@param target T?
---@return T
local function ShallowCopy(source, target)
    local copy = target or {}
    for key in pairs(copy) do if source[key] == nil then copy[key] = nil end end
    for key, value in pairs(source) do copy[key] = value end
    return copy --[[@as T]]
end

--- 牌库和弃牌只复制容器，实例统一取自副本注册表，保持同 uid 同对象。
---@param source ItemInstance[]
---@param instances table<number, ItemInstance>
---@param target ItemInstance[]?
---@return ItemInstance[]
local function CopyReferences(source, instances, target)
    ---@type ItemInstance[]
    local copy = target or {}
    for index = #copy, #source + 1, -1 do copy[index] = nil end
    for index, item in ipairs(source) do
        if index % 128 == 0 then FrameBudget.Checkpoint() end
        copy[index] = assert(instances[item.uid], "展示副本缺少实例 uid=" .. item.uid)
    end
    return copy
end

--- 冻结 UI 所需的顶层值和实例属性，不触碰原局、不抽随机数、不走 Snapshot/Restore。
--- 保留原 Game metatable，Get/BottleItems/_Value 等只读查询仍使用副本自身的数据。
--- _rollback、位置采样、事件及实例内部复杂嵌套状态仅共享只读，不做递归深拷贝。
---@param game BottleGame
---@param reusable BottleGame? 仅在旧批已提交、不再渲染该副本时复用
---@return BottleGame
function PresentationState.Capture(game, reusable)
    local copy = reusable or {} --[[@as BottleGame]]
    local deck, discard = copy.deck, copy.discard
    local drawn, options = copy.drawn, copy.options
    local spawnQueue, relics = copy.spawnQueue, copy.relics
    ---@type table<number, ItemInstance>
    local instances = copy._instances or {}
    ShallowCopy(game, copy)
    for uid in pairs(instances) do if not game._instances[uid] then instances[uid] = nil end end
    local count = 0
    for uid, item in pairs(game._instances) do
        instances[uid] = ShallowCopy(item, instances[uid])
        count = count + 1
        if count % 32 == 0 then FrameBudget.Checkpoint() end
    end
    copy._instances = instances
    copy.deck = CopyReferences(game.deck, instances, deck)
    copy.discard = CopyReferences(game.discard, instances, discard)
    copy.drawn = ShallowCopy(game.drawn, drawn)
    copy.options = ShallowCopy(game.options, options)
    copy.spawnQueue = ShallowCopy(game.spawnQueue, spawnQueue)
    copy.relics = ShallowCopy(game.relics, relics)
    return setmetatable(copy, getmetatable(game))
end

return PresentationState
