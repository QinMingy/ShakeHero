-- 五件遗物共享的持久化状态辅助。纯 Lua，不依赖引擎或 UI。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Money = require("Bottle.Money")
local RelicState = {}

local MAX_UID = 2147483646

---@param value any
---@return boolean
local function Finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

---@param value any
---@return boolean
local function Integer(value)
    return Finite(value) and value == math.floor(value)
end

--- 初始化对局级遗物状态；不清理运行中的回滚模式。
---@param game BottleGame
function RelicState.InitGame(game)
    game.juicerValue = 0
    game.huntTargetUid = 0
end

--- 初始化实例级遗物状态。
---@param item ItemInstance
function RelicState.InitItem(item)
    item.permMult = 1
    item.tokenAttempted = false
    item.chefBoost = 0
end

--- 读取旧 version=2 存档的可选对局字段。缺省字段只补本模块状态。
---@param snapshot table
---@return number juicerValue
---@return integer huntTargetUid
function RelicState.ReadGame(snapshot)
    local juicerValue = snapshot.juicerValue == nil and 0 or snapshot.juicerValue
    local huntTargetUid = snapshot.huntTargetUid == nil and 0 or snapshot.huntTargetUid
    assert(Finite(juicerValue), "无效榨汁机累计价值")
    assert(Integer(huntTargetUid) and huntTargetUid >= 0 and huntTargetUid <= MAX_UID,
        "无效江湖追杀目标 UID")
    return Money.Round(juicerValue), math.floor(huntTargetUid)
end

--- 验证并读取实例级遗物字段。旧 version=2 字段缺省为默认值。
---@param saved table
---@return number permMult
---@return boolean tokenAttempted
function RelicState.ReadItem(saved)
    local permMult = saved.permMult == nil and 1 or saved.permMult
    local tokenAttempted = saved.tokenAttempted
    if tokenAttempted == nil then tokenAttempted = false end
    assert(Finite(permMult) and permMult >= 1, "无效永久倍率")
    assert(type(tokenAttempted) == "boolean", "无效赌神令牌尝试标记")
    return permMult, tokenAttempted
end

--- 完成实例/牌库恢复后严格验证非零目标引用；不消耗 RNG、不随机重选。
---@param game BottleGame
function RelicState.ValidateTarget(game)
    local uid = game.huntTargetUid
    if uid == 0 then return end
    ---@type ItemInstance
    local item = assert(game:Get(uid), "江湖追杀目标不存在")
    assert(Relics.Has(game, "jungle_hunt") and (item.location == "deck" or item.location == "bottle"),
        "江湖追杀目标不属于拥有牌库")
    assert(Items.HasTag(item.id, "人类") and item.id ~= "police" and item.id ~= "killer"
        and not (item.id == "teacher" and Relics.Has(game, "teach_all")), "无效江湖追杀目标")
end

return RelicState
