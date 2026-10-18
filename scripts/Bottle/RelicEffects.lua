-- 遗物规则与首次正常获取附赠。纯 Lua，仅依赖 Bottle 数据模块与 Game 的规则接口。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")

---@class RelicEffects
local RelicEffects = {}

local TOKEN_THRESHOLD = 50
local HUNT_NONE = 0

local HALF_FRUIT = { apple_half = true, banana_half = true, orange_half = true, cherry_half = true }

-- 源表“立即获得”仅由正常遗物三选一成功获取路径调用，不在维护或读档时补发。
---@type table<string, string[]>
local ACQUISITION_GRANTS = {
    coin_rain = { "cloud" },
    in_groups = { "rabbit" },
    cheat_dice = { "die_d6" },
    upgrade_coin_machine = { "coin_machine" },
    tomato_tycoon = { "tomato" },
    scramble_recipe = { "egg", "tomato" },
    see_you_tomorrow = { "enoki" },
    teach_all = { "teacher" },
    jungle_hunt = { "killer" },
    cherry_plus = { "cherry" },
    wash_hands = { "thief" },
    chef_hat = { "chef" },
    credit_line = { "credit_card" },
    bacon_network = { "bacon" },
    ghost_sport = { "ghost" },
    lucky_roulette = { "roulette" },
}

---@param item ItemInstance
---@return boolean
local function IsHalfFruit(item)
    return HALF_FRUIT[item.id] == true
end

---@param game BottleGame
---@param item ItemInstance
---@return boolean
local function IsHuntCandidate(game, item)
    if item.location ~= "deck" and item.location ~= "bottle" then return false end
    if not Items.HasTag(item.id, "人类") then return false end
    if item.id == "police" or item.id == "killer" then return false end
    if item.id == "teacher" and Relics.Has(game, "teach_all") then return false end
    return true
end

---@param game BottleGame
---@return ItemInstance[]
local function HuntCandidates(game)
    ---@type ItemInstance[]
    local candidates = {}
    for _, item in ipairs(game:AllInstances()) do
        if IsHuntCandidate(game, item) then candidates[#candidates + 1] = item end
    end
    table.sort(candidates, function(a, b) return a.uid < b.uid end)
    return candidates
end

--- 维护江湖追杀的稳定目标。候选按 UID 排序后用对局自有 RNG 抽选。
---@param game BottleGame
---@return integer
function RelicEffects.MaintainHuntTarget(game)
    if not Relics.Has(game, "jungle_hunt") then
        game.huntTargetUid = HUNT_NONE
        return HUNT_NONE
    end
    local current = game.huntTargetUid or HUNT_NONE
    if current > HUNT_NONE then
        local item = game:Get(current)
        if item and IsHuntCandidate(game, item) then return current end
    end
    local candidates = HuntCandidates(game)
    local nextTarget = HUNT_NONE
    if #candidates > 0 then nextTarget = candidates[game:_RandomInt(#candidates)].uid end
    if current ~= nextTarget then game.revision = game.revision + 1 end
    game.huntTargetUid = nextTarget
    return nextTarget
end

---@param game BottleGame
---@return integer
function RelicEffects.HuntTarget(game)
    return game.huntTargetUid or HUNT_NONE
end

--- 赌神令牌判定：只在一次旧效果完成后调用。
--- 达到阈值后无论成功/失败都记一次尝试；价值严格为0时才刷新标记。
---@param game BottleGame
---@param item ItemInstance
---@param events GameEvent[]
---@return boolean transformed
function RelicEffects.CheckGamblingToken(game, item, events)
    if not Relics.Has(game, "gambling_token") or item.id ~= "gambler" then return false end
    local value = game:_Value(item)
    if value == 0 then
        if item.tokenAttempted then
            item.tokenAttempted = false
            game.revision = game.revision + 1
        end
        return false
    end
    if value < TOKEN_THRESHOLD or item.tokenAttempted then return false end
    -- 先落尝试标记，再做概率判定，失败后直到严格归零都不重试。
    item.tokenAttempted = true
    game.revision = game.revision + 1
    if game:_RandomInt(4) ~= 1 then return false end

    -- _Transform 会清理遗物状态，但会为 gambler→gambling_god 保留 rerolled 配额。
    game:_Transform(item, "gambling_god", events)
    -- 当前有效价值作为赌神的额外永久加值；UID与物理身份由 _Transform 保留。
    item.permBonus = value
    item.tokenAttempted = false
    events[#events + 1] = {
        kind = "buff", uid = item.uid, id = item.id, value = value,
    }
    game.revision = game.revision + 1
    return true
end

--- 外部价值修改完成后统一维护令牌与追杀目标。
---@param game BottleGame
---@param events GameEvent[]?
---@return boolean transformed
function RelicEffects.Maintain(game, events)
    local transformed = false
    if Relics.Has(game, "gambling_token") then
        for _, item in ipairs(game:AllInstances()) do
            if (item.location == "deck" or item.location == "bottle")
                and item.id == "gambler" and RelicEffects.CheckGamblingToken(game, item, events or {}) then
                transformed = true
            end
        end
    end
    if Relics.Has(game, "jungle_hunt") then RelicEffects.MaintainHuntTarget(game) end
    return transformed
end

--- 遗物获得时立即建立稳定目标；幸运符本身由价值变更钩子实时生效。
---@param game BottleGame
---@param id string
function RelicEffects.OnAcquire(game, id)
    if id == "jungle_hunt" or id == "teach_all" then RelicEffects.MaintainHuntTarget(game) end
    if id == "gambling_token" then RelicEffects.Maintain(game) end
end

--- 仅供Game:Choose成功获得新遗物时调用一次，调用方已先将relics[id]设为true。
--- 新物品永久加入牌库，不直接入当前瓶、不走生成FIFO；随后才维护原有遗物状态。
--- 一次性由Choose拒绝已拥有候选保证，不新增存档标记，Restore/GM/Maintain不调用。
---@param game BottleGame
---@param id string
function RelicEffects.OnAcquired(game, id)
    if not Relics.Has(game, id) then return end
    for _, itemId in ipairs(ACQUISITION_GRANTS[id] or {}) do game:_Create(itemId) end
    RelicEffects.OnAcquire(game, id)
end

--- 消灭完成后奖励：使用消灭前锁定的目标 UID，避免 _Destroy 刷新后误判。
---@param game BottleGame
---@param target ItemInstance
---@param by ItemInstance
---@param targetUid integer
---@param events GameEvent[]
function RelicEffects.OnEliminate(game, target, by, targetUid, events)
    if not Relics.Has(game, "jungle_hunt") or by.id ~= "killer"
        or target.uid ~= targetUid or not Items.HasTag(target.id, "人类")
        or target.id == "killer" or target.id == "police"
        or (target.id == "teacher" and Relics.Has(game, "teach_all")) then return end
    by.permMult = (by.permMult or 1) * 1.5
    events[#events + 1] = { kind = "buff", uid = by.uid, id = by.id, value = by.permMult }
    game.revision = game.revision + 1
end

---@param game BottleGame
---@return integer
function RelicEffects.TomatoEggLimit(game)
    return Relics.Has(game, "scramble_recipe") and 10 or 5
end

--- 回合末（统一结算与死灵返还之后）消耗瓶内半份水果，累计其有效价值。
--- 时序是沿既有阶段的默认实现约定，不追加取消已产生金币的规则。
---@param game BottleGame
---@param events GameEvent[]
---@return number consumedValue
function RelicEffects.AfterSettle(game, events)
    if not Relics.Has(game, "juicer") then return 0 end
    local total = 0
    local candidates = {}
    for _, item in ipairs(game:BottleItems()) do
        if IsHalfFruit(item) then candidates[#candidates + 1] = item end
    end
    table.sort(candidates, function(a, b) return a.uid < b.uid end)
    for _, item in ipairs(candidates) do
        if item.location == "bottle" then
            total = total + game:_Value(item)
            -- _Destroy 保留 discard 与 gm_fruit 语义；本钩子之后不再统一结算/返还。
            -- 遗物不是物品实例；保留消费原因，不伪造缺少实例字段的消耗者。
            game:_Destroy(item.uid, false, events, nil, "consume")
        end
    end
    if total ~= 0 then
        game.juicerValue = game.juicerValue + total
        game.revision = game.revision + 1
    end
    return total
end

---@param game BottleGame
---@return number
function RelicEffects.JuicerValue(game)
    return game.juicerValue or 0
end

--- 在允许交互的阶段生成一件进入牌库的果汁；失败不清累计值。
---@param game BottleGame
---@return boolean ok
---@return string message
---@return ItemInstance? item
function RelicEffects.UseJuicer(game)
    if not Relics.Has(game, "juicer") then return false, "尚未拥有榨汁机", nil end
    if game.phase == "running" or game.phase == "settle" or game.phase == "reveal" then
        return false, "摇晃或结算进行中不能榨汁", nil
    end
    local value = game.juicerValue or 0
    if value <= 0 or value ~= value or value == math.huge then
        return false, "榨汁机没有可生成的果汁", nil
    end
    if not Items.byId.juice or not Items.byId.juice.implemented or game._nextUid >= 2147483647 then
        return false, "当前无法生成果汁", nil
    end
    local item = game:_Create("juice")
    item.valueBase, item.permBonus = value, 0
    game.juicerValue = 0
    game.revision = game.revision + 1
    RelicEffects.Maintain(game)
    return true, "已生成果汁并加入牌库", item
end

return RelicEffects
