-- 金币与价值统一数学向上取整；倍率、物理参数及时间不经过此模块。
local Money = {}

---@param value number
---@return number
function Money.Round(value)
    assert(type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge, "金额必须为有限数字")
    return math.ceil(value)
end

---@param value number
---@return string
function Money.Format(value)
    return string.format("%.0f", Money.Round(value))
end

return Money
