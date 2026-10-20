-- 体感测试倍率：1倍对应原来的1.2米/g，限幅仍交给拖动的瓶身摆幅。
-- 改默认强度时递增 SAVE_REVISION；旧版测试倍率仅迁移一次，之后继续保留 GM 调整。
local Tuning = {MIN = .25, MAX = 20, STEP = .25, DEFAULT = 6, SAVE_REVISION = 1,
    INVERT_X = true, INVERT_Y = true}

-- 原生手机输入先在 main 转为世界坐标，再应用方向设置；Wi-Fi 方向由实验台设置处理。
---@param ax number
---@param ay number
---@return number
---@return number
function Tuning.ApplyAxes(ax, ay)
    return Tuning.INVERT_X and -ax or ax, Tuning.INVERT_Y and -ay or ay
end

---@param value any
---@return number?
function Tuning.Normalize(value)
    if type(value) ~= "number" or tostring(value):lower():find("nan", 1, true)
        or math.abs(value) >= math.huge then return nil end
    local bounded = math.max(Tuning.MIN, math.min(Tuning.MAX, value))
    return math.floor(bounded / Tuning.STEP + .5) * Tuning.STEP
end

return Tuning
