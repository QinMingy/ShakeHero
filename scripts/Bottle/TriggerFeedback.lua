-- 触发收益的表现事件；不计分、不改实例，也不把 buff 的总量/计数当作增量。
local Money = require("Bottle.Money")
local Relics = require("Bottle.Relics")
local Feedback = {}

-- 仅由已成功的离散效果调用；随原事件批次发布，不改规则或额外抽随机数。
---@param game BottleGame
---@param events GameEvent[]?
---@param id string
---@return boolean added
function Feedback.Relic(game, events, id)
    if not events or game.phase ~= "running" or not Relics.byId[id]
        or not Relics.Has(game, id) then return false end
    for _, event in ipairs(events) do
        if event.kind == "relicTrigger" and event.id == id then return false end
    end
    events[#events + 1] = {kind = "relicTrigger", uid = 0, id = id}
    return true
end

-- 刷新次数的获得独立于金币与价值，不进入结算队列、不占用玩法随机数。
---@param events GameEvent[]
---@param item ItemInstance?
---@param position {x:number,y:number}?
function Feedback.Refresh(events, item, position)
    events[#events + 1] = {kind = "refreshGain", uid = item and item.uid or 0,
        id = item and item.id, value = 1,
        x = position and position.x, y = position and position.y}
end

---@param events GameEvent[]
---@param item ItemInstance
---@param amount number
---@param rewardKind 'value'|'permanent'|'size'
---@param trigger 'move'|'rotate'|'distance'|'collision'
---@param position {x:number,y:number}?
---@param cause GameEvent?
function Feedback.Reward(events, item, amount, rewardKind, trigger, position, cause)
    if rewardKind ~= "size" then amount = Money.Round(amount) end
    if math.abs(amount) < 1e-9 then return end
    events[#events + 1] = {
        kind = "triggerReward", uid = item.uid, id = item.id, value = amount,
        rewardKind = rewardKind, trigger = trigger,
        x = position and position.x, y = position and position.y,
        reason = cause and cause.reason, consumerId = cause and cause.consumerId,
    }
end

-- 使用同一份完整价值算法比较倍率前后，避免从取整后的结果逆算出小数或浮点噪声。
---@param game BottleGame
---@param item ItemInstance
---@param permanent number
---@param mult number
---@return number
local function ValueAt(game, item, permanent, mult)
    local sample = {} --[[@as ItemInstance]]
    for key, value in pairs(item) do sample[key] = value end
    sample.permMult, sample.mult = permanent, mult
    return game:_Value(sample)
end

---@param events GameEvent[]
---@param first integer
---@param trigger 'move'|'rotate'|'distance'|'collision'
function Feedback.TagScores(events, first, trigger)
    for index = first, #events do
        local event = events[index]
        if event.kind == "score" and not event.trigger then event.trigger = trigger end
    end
end

---@class TriggerValueState
---@field id string
---@field bonus number
---@field permBonus number
---@field mult number
---@field permMult number
---@field valueBase number?

-- 仅在离散接触真正进入处理时快照；没有逐帧扫描永久变化，也不写入存档。
---@param game BottleGame
---@return table<number,TriggerValueState>
function Feedback.Capture(game)
    local before = {}
    for _, item in ipairs(game:BottleItems()) do
        before[item.uid] = {id = item.id, bonus = item.bonus, permBonus = item.permBonus,
            mult = item.mult, permMult = item.permMult or 1, valueBase = item.valueBase}
    end
    return before
end

---@param game BottleGame
---@param before table<number,TriggerValueState>
---@param events GameEvent[]
---@param first integer
---@param trigger 'move'|'rotate'|'distance'|'collision'
---@param contacts BottleStepContacts
function Feedback.Finish(game, before, events, first, trigger, contacts)
    Feedback.TagScores(events, first, trigger)
    -- 只取本次效果处理范围内、成功消耗的明确消费者；不从碰撞或附近物品猜来源。
    ---@type table<number,GameEvent>
    local causes = {}
    for index = first, #events do
        local event = events[index]
        if event.kind == "consume" and event.consumerUid
            and (event.reason == "consume" or event.reason == "eliminate") then
            causes[event.consumerUid] = event
        end
    end
    local items = game:BottleItems()
    local included = {}
    for _, item in ipairs(items) do included[item.uid] = true end
    -- 本次触发后离场的旧物品仍可能有收益（如草堆最后一次永久-1）。
    -- 只补快照里的旧实例，不扫描尚未入场的排队产物。
    local departed = {}
    for uid in pairs(before) do
        if not included[uid] then departed[#departed + 1] = uid end
    end
    table.sort(departed)
    for _, uid in ipairs(departed) do
        local item = game:Get(uid)
        if item then items[#items + 1] = item end
    end
    for _, item in ipairs(items) do
        local old = before[item.uid]
        -- 转化/新产物以零加成为起点，基础价值变化不冒充额外奖励。
        local same = old and old.id == item.id
        -- 分裂把原加成/倍率折入 valueBase；字段归零属于价值重编码，不能弹成永久扣除。
        local normalized = same and old.valueBase ~= item.valueBase
        if not normalized then
            local position = contacts.positions[item.uid]
            local cause = causes[item.uid]
            if not position then
                for index = first, #events do
                    local event = events[index]
                    if event.uid == item.uid and event.x ~= nil and event.y ~= nil then
                        position = {x = event.x, y = event.y}
                        break
                    end
                end
            end
            Feedback.Reward(events, item, item.permBonus - (same and old.permBonus or 0),
                "permanent", trigger, position, cause)
            Feedback.Reward(events, item, item.bonus - (same and old.bonus or 0),
                "value", trigger, position, cause)
            local permanent = item.permMult or 1
            local oldPermanent = same and old.permMult or 1
            local oldMult = same and old.mult or 1
            if permanent ~= oldPermanent and permanent > 0 then
                Feedback.Reward(events, item, ValueAt(game, item, permanent, oldMult)
                    - ValueAt(game, item, oldPermanent, oldMult),
                    "permanent", trigger, position, cause)
            end
            if item.mult ~= oldMult and item.mult > 0 then
                Feedback.Reward(events, item, game:_Value(item) - ValueAt(game, item, permanent, oldMult),
                    "value", trigger, position, cause)
            end
        end
    end
end

local LABELS = {move = "移动：", rotate = "旋转：", distance = "位移", collision = "碰撞"}

-- 图标由表现层绘制在 prefix 和 amount 之间；金币沿用 +n，无额外货币字样。
---@param value number
---@param trigger string?
---@param rewardKind string?
---@param label string? 来源明确时覆盖通用触发文案
---@return string prefix
---@return string amount
---@return boolean valueIcon
function Feedback.Content(value, trigger, rewardKind, label)
    local prefix = label or LABELS[trigger] or ""
    if rewardKind == "size" then prefix = prefix .. "体积" end
    -- 金币与价值使用同一整数规则；体积百分比继续保留实际精度。
    if rewardKind ~= "size" then value = Money.Round(value) end
    local number = rewardKind == "size" and string.format("%.10g", value) or Money.Format(value)
    local amount = (value >= 0 and "+" or "") .. number
    -- 永久是价值的修饰，放在图标后、数字前；金币不加价值图标。
    if rewardKind == "permanent" then amount = "永久" .. amount end
    if rewardKind == "size" then amount = amount .. "%" end
    return prefix, amount, rewardKind == "value" or rewardKind == "permanent"
end

return Feedback
