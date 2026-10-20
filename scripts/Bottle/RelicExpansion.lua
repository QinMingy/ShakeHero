-- 最新37件遗物补齐：只处理纯 Lua 规则，不持有物理对象、不修改共享定义。
-- 速度／幽灵便便由 Physics 与 Items.IsPiercing 查询；这里负责值、合成、邻接和里程。
local Items = require("Bottle.Items")
local FrameBudget = require("Bottle.FrameBudget")
local BudgetSort = require("Bottle.BudgetSort")
local Relics = require("Bottle.Relics")
local TriggerFeedback = require("Bottle.TriggerFeedback")
local RelicExpansion = {}
local TURN = math.pi * 2
local EPSILON = 1e-9
local GHOST_SPORT_DISTANCE = 30
-- Only explicitly registered private rule snapshots borrow these containers.
-- External snapshots retain the existing independent-publication contract.
---@type table<table,table>
local graphBuffers = setmetatable({}, {__mode = "k"})
local EMPTY = {}
local function Clear(values)
    for key in pairs(values) do values[key] = nil end
end
local function PairLess(a,b) return a[1] == b[1] and a[2] < b[2] or a[1] < b[1] end
local function NumberLess(a,b) return a < b end
local function NewGraphBuffer()
    return {raw={},rawRows={},seen={},adjacent={},neighborRows={},neighbors={},
        derived={{items={},rows={}},{items={},rows={}}},
        indexes={{items={},rows={}},{items={},rows={}}}}
end

-- Read/write rows are separate from the array ordering changed by Sort/remove.
local function PairRow(rows,index,a,b)
    local row=rows[index]
    if not row then row={};rows[index]=row end
    row[1],row[2]=a,b
    return row
end

local function NeighborRow(map,rows,uid,index)
    local row=map[uid]
    if row then return row,index end
    index=index+1
    row=rows[index]
    if not row then row={};rows[index]=row else Clear(row) end
    map[uid]=row
    return row,index
end

---@param item any
function RelicExpansion.ResetRound(item)
    item.ghostTravel, item.spinProgress, item.jackpotBonus = 0, 0, 0
    item.spinTravel, item.spinAngle, item.spinForced = nil, nil, nil
end

---@param game BottleGame
---@param item any
---@param events GameEvent[]
---@param value number
local function Buff(game, item, events, value)
    events[#events + 1] = {kind = "buff", uid = item.uid, id = item.id, value = value}
    game.revision = game.revision + 1
end

--- 骰号大奖在点数确定后、骰子即时结算前执行；每次6都奖励，包括尺寸封顶后。
--- 奖励对象是此刻瓶内骰子、硬币链、赌徒、赌神；幸运硬币不属于既有硬币分类。
--- 只累计独立临时加数；Game:_Value将(1+jackpotBonus)与其他来源相乘。
---@param game BottleGame
---@param die any
---@param point integer
---@param events GameEvent[]
function RelicExpansion.OnRoll(game, die, point, events)
    if not Relics.Has(game, "dice_jackpot") or die.location ~= "bottle"
        or not Items.HasTag(die.id, "骰子") then return end
    local previous = die.scale or 1
    if point ~= 6 then
        if previous ~= 1 then
            die.scale = 1
            game:ApplyScale(die, events, previous)
        end
        return
    end
    local scale = math.min(3, previous + 0.5)
    die.scale = scale
    if scale ~= previous then game:ApplyScale(die, events, previous) end
    local amount = math.max(0, scale - 1)
    for _, candidate in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        local item = candidate --[[@as ItemInstance]]
        if Items.HasTag(item.id, "骰子") or item.id:match("^coin_%d+$")
            or item.id == "gambler" or item.id == "gambling_god" then
            item.jackpotBonus = (item.jackpotBonus or 0) + amount
            Buff(game, item, events, amount)
            if amount > 0 then TriggerFeedback.Relic(game, events, "dice_jackpot") end
        end
    end
end

--- 由公共成功消费钩子调用；合成的每份羊毛独立判定，临时羊毛没有豁免。
--- 不依赖实体consumer，避免无consumer的合成/自耗漏判；失败消费不得调用。
---@param game BottleGame
---@param target any
---@param events GameEvent[]
function RelicExpansion.OnConsumed(game, target, events)
    if target.id == "wool" and Relics.Has(game, "wool_recycle") and game:_RandomInt(2) == 1 then
        if game:_SpawnTop("wool", events, true) then
            TriggerFeedback.Relic(game, events, "wool_recycle")
        end
    end
end

--- 一次成功消费启动一次冲刺；不是每帧移动、每米或每个碰撞目标触发。
--- 临时+1叠加原冲撞收益；体积默认永久，达到200%永久+2后立即复原100%。
---@param game BottleGame
---@param calf any
---@param events GameEvent[]
function RelicExpansion.OnDash(game, calf, events)
    if calf.id ~= "calf" or calf.location ~= "bottle" or not Relics.Has(game, "calf_rush") then return end
    calf.bonus = (calf.bonus or 0) + 1
    Buff(game, calf, events, 1)
    local maximum = Items.byId.calf.scaleMax or Items.Settings.maxScale
    local previous = calf.scale or 1
    local grown = math.min(maximum, previous + 0.2)
    if grown >= maximum - EPSILON then
        calf.permBonus = (calf.permBonus or 0) + 2
        calf.scale = 1
        Buff(game, calf, events, 2)
    else
        calf.scale = grown
    end
    game:ApplyScale(calf, events, previous)
    TriggerFeedback.Relic(game, events, "calf_rush")
end

--- 转盘一圈只取一个互斥结果：大奖5%，其余95%基础正负各半。
--- 大奖为临时+77；基础正3/负1永久，幸运符只将基础负1改为正1。
--- 无幸运转盘不多抽大奖概率；命中大奖不再抽基础分支。
---@param game BottleGame
---@param events GameEvent[]?
---@return number delta
---@return boolean permanent
function RelicExpansion.RollWheel(game, events)
    if Relics.Has(game, "lucky_roulette") and game:_RandomInt(20) == 1 then
        TriggerFeedback.Relic(game, events, "lucky_roulette")
        return 77, false
    end
    if game:_RandomInt(2) == 1 then return 3, true end
    TriggerFeedback.Relic(game, events, "lucky_charm")
    return Relics.Has(game, "lucky_charm") and 1 or -1, true
end

--- 食物+2只参与当前价值的加法项，不改基础定义、bonus或永久加成。
---@param game BottleGame
---@param item any
---@return number
function RelicExpansion.ValueBonus(game, item)
    return Relics.Has(game, "food_comfort") and Items.HasTag(item.id, "食物") and 2 or 0
end

--- 原始真实接触只复制一次；后续失效处理会删 rawPairs，每次从它重算派生关系。
--- 每根培根仅将自己的真实直接邻居两两相连，不递归传播、不合并连通分量。
---@param game BottleGame
---@param state any
---@param reuse boolean? Only a rule-step-owned snapshot may opt into scratch.
function RelicExpansion.ExpandContacts(game, state, reuse)
    local scratch=graphBuffers[state]
    if reuse and not scratch then scratch=NewGraphBuffer();graphBuffers[state]=scratch end
    if not state.rawPairs then
        local raw=scratch and scratch.raw or {}
        Clear(raw)
        for _, pair in ipairs(state.pairs or {}) do
            FrameBudget.Checkpoint()
            local index=#raw+1
            raw[index]=scratch and PairRow(scratch.rawRows,index,pair[1],pair[2]) or {pair[1],pair[2]}
        end
        state.rawPairs=raw
    end
    local slot=scratch and (scratch.derived[1].items~=state.pairs and scratch.derived[1] or scratch.derived[2])
    ---@type number[][]
    local derived = slot and slot.items or {}
    local seen=scratch and scratch.seen or {}
    local adjacent=scratch and scratch.adjacent or {}
    local rows=slot and slot.rows or nil
    if scratch then
        -- Keep the currently published array intact while a new graph yields.
        Clear(derived)
        Clear(seen);Clear(adjacent)
    end
    local neighborCount=0
    local function Add(a, b)
        if a == b then return end
        local first, second = math.min(a, b), math.max(a, b)
        local key = first .. ":" .. second
        if not seen[key] then
            seen[key] = true
            local index=#derived+1
            derived[index]=scratch and PairRow(rows,index,first,second) or {first,second}
        end
    end
    for _, pair in ipairs(state.rawPairs) do
        FrameBudget.Checkpoint()
        local a, b = game:Get(pair[1]), game:Get(pair[2])
        if a and b and a.location == "bottle" and b.location == "bottle" and a.uid ~= b.uid then
            Add(a.uid, b.uid)
            if scratch then
                ---@type table<number,boolean>
                local rowA
                ---@type table<number,boolean>
                local rowB
                rowA,neighborCount=NeighborRow(adjacent,scratch.neighborRows,a.uid,neighborCount)
                rowB,neighborCount=NeighborRow(adjacent,scratch.neighborRows,b.uid,neighborCount)
                adjacent[a.uid],adjacent[b.uid]=rowA,rowB
            else
                adjacent[a.uid] = adjacent[a.uid] or {}
                adjacent[b.uid] = adjacent[b.uid] or {}
            end
            adjacent[a.uid][b.uid], adjacent[b.uid][a.uid] = true, true
        end
    end
    if Relics.Has(game, "bacon_network") then
        for _, bacon in ipairs(game:BottleItems()) do
            FrameBudget.Checkpoint()
            if bacon.id == "bacon" then
                local neighbors = scratch and scratch.neighbors or {}
                Clear(neighbors)
                for uid in pairs(adjacent[bacon.uid] or EMPTY) do
                    FrameBudget.Checkpoint()
                    neighbors[#neighbors + 1] = uid
                end
                table.sort(neighbors)
                for i = 1, #neighbors do
                    for j = i + 1, #neighbors do
                        FrameBudget.Checkpoint()
                        Add(neighbors[i], neighbors[j])
                    end
                end
            end
        end
    end
    BudgetSort.Sort(derived, PairLess)
    state.pairs = derived
    state._managedGraph = true
    state._adjacencyPairs, state._adjacencyUids = nil, nil
end

-- 核心快照的一张接触图只建一次UID索引；结果始终按UID返回新的实例数组。
-- 外部接触表可能原地修改，未经过ExpandContacts时保留即时扫描契约。
---@param game BottleGame
---@param uid number
---@param contacts BottleStepContacts
---@return ItemInstance[]
function RelicExpansion.Adjacents(game, uid, contacts)
    if contacts._managedGraph and contacts._adjacencyPairs ~= contacts.pairs then
        local scratch=graphBuffers[contacts]
        ---@type table<number,table<number,boolean>>
        local neighbors = scratch and scratch.adjacent or {}
        local neighborCount=0
        if scratch then Clear(neighbors) end
        for _, pair in ipairs(contacts.pairs) do
            FrameBudget.Checkpoint()
            local a, b = pair[1], pair[2]
            local rowA = rawget(neighbors, a) --[[@as table<number,boolean>?]]
            local rowB = rawget(neighbors, b) --[[@as table<number,boolean>?]]
            if scratch then
                rowA,neighborCount=NeighborRow(neighbors,scratch.neighborRows,a,neighborCount)
                rowB,neighborCount=NeighborRow(neighbors,scratch.neighborRows,b,neighborCount)
            else rowA,rowB=rowA or {},rowB or {} end
            neighbors[a], neighbors[b] = rowA, rowB
            rowA[b], rowB[a] = true, true
        end
        local slot=scratch and (scratch.indexes[1].items~=contacts._adjacencyUids and scratch.indexes[1] or scratch.indexes[2])
        ---@type table<number,number[]>
        local ordered = slot and slot.items or {}
        local rows=slot and slot.rows or nil
        if scratch then
            Clear(ordered)
        end
        local orderedCount=0
        for source, others in pairs(neighbors) do
            FrameBudget.Checkpoint()
            orderedCount=orderedCount+1
            local ids=scratch and rows[orderedCount] or nil
            if not ids then ids={};if scratch then rows[orderedCount]=ids end else Clear(ids) end
            for other in pairs(others) do
                ids[#ids + 1] = other
                if #ids % 64 == 0 then FrameBudget.Checkpoint() end
            end
            BudgetSort.Sort(ids, NumberLess)
            ordered[source] = ids
        end
        contacts._adjacencyPairs, contacts._adjacencyUids = contacts.pairs, ordered
    end
    ---@type ItemInstance[]
    local result = {}
    if contacts._managedGraph and contacts._adjacencyUids then
        for _, other in ipairs(contacts._adjacencyUids[uid] or EMPTY) do
            local item = game:Get(other)
            if item and item.location == "bottle" then result[#result + 1] = item end
        end
    else
        local seen = {}
        for _, pair in ipairs(contacts.pairs) do
            local other = pair[1] == uid and pair[2] or pair[2] == uid and pair[1] or nil
            if other and not seen[other] then
                seen[other] = true
                local item = game:Get(other)
                if item and item.location == "bottle" then result[#result + 1] = item end
            end
        end
        table.sort(result, function(a, b) return a.uid < b.uid end)
    end
    return result
end

--- 名师团队：继承加法项之和、永久倍率乘积及事件倍率乘积，不固化邻接光环。
--- _Merge负责双材料护盾原子预检，失败不改材料数值、不生成第三位老师。
---@param game BottleGame
---@param a any
---@param b any
---@param contacts any
---@param events GameEvent[]
---@return boolean?
function RelicExpansion.TryMerge(game, a, b, contacts, events)
    if a.id ~= "teacher" or b.id ~= "teacher" or not Relics.Has(game, "teacher_team") then return nil end
    if a.uid == b.uid or a.location ~= "bottle" or b.location ~= "bottle" then return false end
    local base = (a.valueBase or Items.byId[a.id].base) + (a.bonus or 0) + (a.permBonus or 0)
        + (b.valueBase or Items.byId[b.id].base) + (b.bonus or 0) + (b.permBonus or 0)
    local permanent = (a.permMult or 1) * (b.permMult or 1)
    local eventMult = (a.eventMult or 1) * (b.eventMult or 1)
    local first = #events + 1
    if not game:_Merge(a, b, "teacher", contacts, events) then return false end
    for index = first, #events do
        local event = events[index]
        if event.kind == "merge" and event.a == a.uid and event.b == b.uid then
            local result = game:Get(event.uid)
            if result then
                result.valueBase, result.bonus, result.permBonus = base, 0, 0
                result.permMult, result.eventMult, result.mult = permanent, eventMult, eventMult
                game.revision = game.revision + 1
                TriggerFeedback.Relic(game, events, "teacher_team")
            end
            break
        end
    end
    return true
end

--- Game只传有效的真实物理位移差；不复用兔子／飞盘会消费的distance余程。
---@param game BottleGame
---@param item any
---@param stepDistance number
---@param events GameEvent[]
function RelicExpansion.TrackDistance(game, item, stepDistance, events)
    if item.location ~= "bottle" or item.id ~= "ghost" or not Relics.Has(game, "ghost_sport") then return end
    item.ghostTravel = (item.ghostTravel or 0) + stepDistance
    while item.ghostTravel >= GHOST_SPORT_DISTANCE - EPSILON do
        FrameBudget.Checkpoint()
        item.ghostTravel = math.max(0, item.ghostTravel - GHOST_SPORT_DISTANCE)
        game:_Score(events, item, 1, game._lastPositions[item.uid])
        events[#events].trigger = "move"
        TriggerFeedback.Relic(game, events, "ghost_sport")
    end
end

--- 转圈圈只累计自然角路程；反转仍计，强制指南针旋转通过angularTravel或offset排除。
--- 物理重建累计归零不产生反向奖励；每满三圈独立30%固定+1金币，不按物品价值结算。
---@param game BottleGame
---@param dt number
---@param state any
---@param events GameEvent[]
function RelicExpansion.Step(game, dt, state, events)
    local enabled = Relics.Has(game, "spin_reward")
    for _, item in ipairs(game:BottleItems()) do
        FrameBudget.Checkpoint()
        if game:IsSampled(item) then
        local travel = state.angularTravel and state.angularTravel[item.uid]
        local angle = state.angles and state.angles[item.uid]
        local forced = state.rotateOffsets and state.rotateOffsets[item.uid] or 0
        ---@type number
        local delta = 0
        if travel then
            delta = math.max(0, travel - (item.spinTravel or 0))
        elseif angle and item.spinAngle then
            local change = angle - item.spinAngle - (forced - (item.spinForced or 0))
            delta = math.abs((change + math.pi) % TURN - math.pi)
        end
        item.spinTravel, item.spinAngle, item.spinForced = travel, angle, forced
        if enabled then
            item.spinProgress = (item.spinProgress or 0) + delta
            while item.spinProgress >= TURN * 3 - EPSILON do
                FrameBudget.Checkpoint()
                item.spinProgress = math.max(0, item.spinProgress - TURN * 3)
                if game:_RandomInt(100) <= 30 then
                    game:_Score(events, item, 1, state.positions and state.positions[item.uid])
                    events[#events].trigger = "rotate"
                    TriggerFeedback.Relic(game, events, "spin_reward")
                end
            end
        end
    end
    end
end

return RelicExpansion
