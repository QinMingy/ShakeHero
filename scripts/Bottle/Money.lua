-- 金币在每笔交易完成时向上取整；物品价值、倍率和物理参数仍按原精度计算。
local Money = {}

---@param value number
---@return number
function Money.Round(value)
    return math.ceil(value)
end

---@param value number
---@return string
function Money.Format(value)
    return string.format("%.0f", Money.Round(value))
end

return Money
