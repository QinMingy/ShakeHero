-- 消耗表现策略表：只描述交互语义，不改规则、金币、随机数或实例。
local Items = require("Bottle.Items")
local Styles = {}

---@class BottleConsumeStyle
---@field animation 'absorb'|'smoke'|'flash'
---@field label string
---@field rebound boolean
---@field popup boolean

---@type table<string,BottleConsumeStyle>
Styles.profiles = {
    eat = {animation="absorb", label="吞食", rebound=true, popup=false},
    recycle = {animation="absorb", label="回收", rebound=false, popup=false},
    absorb = {animation="absorb", label="吸收", rebound=false, popup=false},
    use = {animation="absorb", label="使用", rebound=false, popup=false},
    collect = {animation="absorb", label="收取", rebound=false, popup=false},
    eliminate = {animation="smoke", label="消灭", rebound=false, popup=false},
    merge = {animation="flash", label="合成", rebound=false, popup=true},
    burst = {animation="flash", label="爆裂", rebound=false, popup=false},
    remove = {animation="flash", label="移除", rebound=false, popup=true},
    consume = {animation="flash", label="消耗", rebound=false, popup=true},
}

-- 指定物品的特殊语义；其他动物走吞食，未知对象保留通用消耗。
Styles.byConsumer = {
    glutton="eat", diner="eat", trash_can="recycle", chef="use",
    soul_stone="absorb", cactus="absorb", chicken_keeper="collect", sweater="collect",
}
local BY_REASON = {eliminate="eliminate", merge_checked="merge", merge="merge",
    burst="burst", remove="remove"}

---@param event GameEvent
---@return string
function Styles.Resolve(event)
    local special = event.reason and BY_REASON[event.reason]
    if special then return special end
    if event.reason == "consume" and event.consumerId then
        local id = event.consumerId
        if Styles.byConsumer[id] then return Styles.byConsumer[id] end
        if Items.byId[id] and Items.HasTag(id, "动物") then return "eat" end
    end
    return "consume"
end

---@param event GameEvent
---@return string? label
function Styles.RewardLabel(event)
    if event.reason ~= "consume" and event.reason ~= "eliminate" then return nil end
    return Styles.profiles[Styles.Resolve(event)].label
end

return Styles
