-- 体积/重量统一规则。纯 Lua；范围只读 Items 定义，绝不读取实例/存档自带 override。
-- scale 沿既有语义直接乘半径；weight 是相同尺寸下原 fixture 质量的相对倍率。
-- 不用平方根/立方根换算体积，也不按 scale 补偿密度：weight=1 保留原物理。
local Items = require("Bottle.Items")
local PhysicalState = {}

---@param value any
---@return boolean
local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param id string
---@param field 'scale'|'weight'
---@return number minimum
---@return number maximum
---@return number default
function PhysicalState.Range(id, field)
    local def = assert(Items.byId[id], "未知物品物理定义: " .. tostring(id))
    local settings = Items.Settings
    local minimum = field == "scale" and (def.scaleMin or settings.minScale)
        or (def.weightMin or settings.minWeight)
    local maximum = field == "scale" and (def.scaleMax or settings.maxScale)
        or (def.weightMax or settings.maxWeight)
    local default = field == "scale" and settings.defaultScale or settings.defaultWeight
    assert(finite(minimum) and finite(maximum) and minimum > 0 and maximum >= minimum,
        "无效物理范围定义: " .. id .. "." .. field)
    assert(finite(default) and default >= minimum and default <= maximum,
        "物理默认值不在定义范围内: " .. id .. "." .. field)
    return minimum, maximum, default
end

---运行时缺省/非有限值回默认，有限值钳制；持久化读取使用严格 Read，不静默修档。
---@param id string
---@param field 'scale'|'weight'
---@param value any
---@return number
function PhysicalState.Clamp(id, field, value)
    local minimum, maximum, default = PhysicalState.Range(id, field)
    if not finite(value) then return default end
    return math.max(minimum, math.min(maximum, value))
end

---读取旧 version=2 档时两个字段均允许缺省；显式非法值（含 NaN/Inf）拒绝。
---@param id string
---@param saved table
---@return number scale
---@return number weight
function PhysicalState.Read(id, saved)
    local function read(field)
        local minimum, maximum, default = PhysicalState.Range(id, field)
        local value = saved[field]
        if value == nil then return default end
        assert(finite(value) and value >= minimum and value <= maximum,
            "无效" .. (field == "scale" and "体积" or "重量") .. "倍率")
        return value
    end
    return read("scale"), read("weight")
end

---@param item ItemInstance
function PhysicalState.Init(item)
    local _, _, scale = PhysicalState.Range(item.id, "scale")
    local _, _, weight = PhysicalState.Range(item.id, "weight")
    item.scale, item.weight = scale, weight
end

---@param item ItemInstance
function PhysicalState.Normalize(item)
    item.scale = PhysicalState.Clamp(item.id, "scale", item.scale)
    item.weight = PhysicalState.Clamp(item.id, "weight", item.weight)
end

---resize 保持既有事件契约；weight 只作附带状态，不冒充体积 event.value。
---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
function PhysicalState.Apply(game, item, events)
    PhysicalState.Normalize(item)
    events[#events + 1] = {kind = "resize", uid = item.uid, id = item.id,
        value = item.scale, weight = item.weight}
    game.revision = game.revision + 1
end

return PhysicalState
