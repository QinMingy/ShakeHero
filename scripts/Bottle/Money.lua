-- 金额仅做显示格式化，不改变账本或逐笔收益的精度。
local Money = {}

---@param value number
---@return string
function Money.Format(value)
    return string.format("%g", value)
end

return Money
