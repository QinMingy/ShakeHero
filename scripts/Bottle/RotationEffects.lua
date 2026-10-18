-- #94-97 旋转物品的纯 Lua 规则；所有角度均为弧度，不持有物理对象。
-- 调度契约：Game先推进remaining/elapsed，再调用Step，随后才做端点_Resolve。
-- 本模块四类Touches始终false，避免_Resolve把齿轮的1秒回放错误重置成4秒冷却。
-- 接触设计： [固定batch A] --真实/派生相邻--> [齿轮] <-- [固定batch B]
-- 只在标记瞬间读_Adjacents；4秒内相邻变化不改batch，反转算角路程，离场不再采样。
-- 冷却结束给齿轮和仍在场batch各发同一个总角；回放1秒后才重新标记完整4秒。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
---@class BottleRotationSample
---@field initialized boolean?
---@field travel number?
---@field angle number?
---@field forced number?

---@class BottleRotationBatchEntry
---@field uid integer
---@field sample BottleRotationSample
---@field travel number

---@class BottleRotationItem : ItemInstance
---@field rotationProgress number?
---@field rotationSamples table<string,BottleRotationSample>?
---@field gearBatch BottleRotationBatchEntry[]?
---@field gearPlayback number?

local Rotation = {}
local TURN = math.pi * 2
local EPSILON = 1e-9
local GEAR_COOLDOWN, REPLAY_DURATION = 4, 1
local PRODUCTS = { "droplet", "wool", "grass" }
---@type table<string,boolean>
local HANDLED = { spinning_top = true, windmill = true, gear = true, roulette = true }

---@param value any
---@return boolean
local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

---@param sample any
---@param uid number
---@param state any
local function Prime(sample, uid, state)
    local travel = state.angularTravel and state.angularTravel[uid]
    local angle = state.angles and state.angles[uid]
    local forced = state.rotateOffsets and state.rotateOffsets[uid]
    sample.travel = Finite(travel) and travel >= 0 and travel or nil
    sample.angle = Finite(angle) and angle or nil
    sample.forced = Finite(forced) and forced or 0
    sample.initialized = true
end

---@param sample any
---@param uid number
---@param state any
---@return number
local function NaturalDelta(sample, uid, state)
    local travel = state.angularTravel and state.angularTravel[uid]
    local angle = state.angles and state.angles[uid]
    local forced = state.rotateOffsets and state.rotateOffsets[uid] or 0
    local validTravel = Finite(travel) and travel >= 0
    local validAngle = Finite(angle)
    -- 缺一拍数据不清已知基线；尤其Start后的空接触不能吞掉首个累计物理步。
    if not validTravel and not validAngle then return 0 end
    if not Finite(forced) then forced = 0 end
    ---@type number
    local delta = 0
    if validTravel and sample.travel ~= nil then
        -- 正式Physics必须在重建时保留单调累计；兼容旧输入归零时只重建基线。
        delta = math.max(0, travel - sample.travel)
    elseif validTravel and not sample.initialized then
        -- 本回合Physics从0起采样；首个累计值可能已包含第一物理步的转动。
        delta = travel
    elseif validAngle and sample.angle ~= nil then
        -- fallback只能恢复相邻采样间最短角差；高速多圈必须使用angularTravel。
        local change = angle - sample.angle - (forced - (sample.forced or 0))
        delta = math.abs((change + math.pi) % TURN - math.pi)
    end
    Prime(sample, uid, state)
    return delta
end

---共用自然角采样。不同消费者用不同channel，彼此不消费/重置对方的进度。
---推荐compass/spin_reward也调用本函数；Physics.angularTravel已排除全部强制旋转。
---首次累计从0计；新标记batch使用Prime而非把标记前历史算入4秒窗口。
---@param item any
---@param state any
---@param channel string?
---@return number
function Rotation.SampleNatural(item, state, channel)
    local samples = item.rotationSamples or {}
    item.rotationSamples = samples
    local key = channel or "item"
    local sample = samples[key] or {}
    samples[key] = sample
    return NaturalDelta(sample, item.uid, state)
end

---@param item any
function Rotation.ResetRound(item)
    item.rotationProgress, item.gearPlayback = 0, 0
    item.rotationSamples, item.gearBatch = nil, nil
    -- 不改permBonus、bonus或真实物理角；清临时价值仍由Game统一执行。
end

---@param game BottleGame
---@param item any
---@param state any
---@return boolean?
function Rotation.Touches(game, item, state)
    if HANDLED[item.id] then return false end
    return nil
end

---全部由Step调度；保留分派入口，不能让Game._Resolve接管齿轮周期。
---@param game BottleGame
---@param item any
---@param state any
---@param events GameEvent[]
---@return boolean
function Rotation.Apply(game, item, state, events)
    return false
end

---@param game BottleGame
---@param item any
---@param events GameEvent[]
---@param value number
---@param permanent boolean
local function Buff(game, item, events, value, permanent)
    if permanent then item.permBonus = (item.permBonus or 0) + value
    else item.bonus = (item.bonus or 0) + value end
    events[#events + 1] = { kind = "buff", uid = item.uid, id = item.id, value = value }
    game.revision = game.revision + 1
end

---@param game BottleGame
---@param item any
---@param state any
---@param events GameEvent[]
local function RewardTurn(game, item, state, events)
    if item.id == "spinning_top" then
        Buff(game, item, events, 1, false)
    elseif item.id == "windmill" then
        local product = assert(PRODUCTS[game:_RandomInt(#PRODUCTS)])
        local origin = state.positions and state.positions[item.uid]
            or (game._lastPositions and game._lastPositions[item.uid])
        -- 近源、临时生命周期和满瓶FIFO全部复用公共生成，不另造队列或瓶顶随机数。
        game:_Spawn(product, events, true, origin)
    elseif item.id == "roulette" then
        -- 幸运转盘5%大奖是互斥分支，不再叠加基础奖；概率统一由遗物模块维护。
        local delta, permanent = require("Bottle.RelicExpansion").RollWheel(game)
        Buff(game, item, events, delta, permanent)
    end
end

---@param game BottleGame
---@param item any
---@return boolean
local function Upright(game, item)
    return item.id == "ghost" or (Relics.Has(game, "ghost_poop") and Items.IsPoop(item.id))
end

---@param game BottleGame
---@param gear any
---@param state any
---@return boolean
local function MarkBatch(game, gear, state)
    local batch, seen = {}, {}
    for _, other in ipairs(game:_Adjacents(gear.uid, state)) do
        if other.uid ~= gear.uid and other.location == "bottle" and not seen[other.uid] then
            local sample = {}
            Prime(sample, other.uid, state)
            batch[#batch + 1] = { uid = other.uid, sample = sample, travel = 0 }
            seen[other.uid] = true
        end
    end
    if #batch == 0 then return false end
    gear.gearBatch, gear.remaining = batch, GEAR_COOLDOWN
    game.revision = game.revision + 1
    return true
end

---@param game BottleGame
---@param gear any
---@param state any
local function TrackBatch(game, gear, state)
    for _, entry in ipairs(gear.gearBatch) do
        local other = game:Get(entry.uid)
        if other and other.location == "bottle" then
            entry.travel = entry.travel + NaturalDelta(entry.sample, entry.uid, state)
        else
            -- 离场前已经累计的贡献保留；以后重新入瓶不能补记离场期间的转动。
            Prime(entry.sample, entry.uid, {})
        end
    end
end

---@param game BottleGame
---@param gear any
---@param events GameEvent[]
local function Replay(game, gear, events)
    local total = 0
    for _, entry in ipairs(gear.gearBatch) do total = total + entry.travel end
    local function Rotate(item)
        if item.location ~= "bottle" or Upright(game, item) then return end
        events[#events + 1] = { kind = "rotate", uid = item.uid, delta = -total,
            duration = REPLAY_DURATION, excludeCompass = true }
    end
    Rotate(gear)
    for _, entry in ipairs(gear.gearBatch) do
        local other = game:Get(entry.uid)
        if other then Rotate(other) end
    end
    gear.gearBatch, gear.gearPlayback, gear.remaining = nil, REPLAY_DURATION, 0
    game.revision = game.revision + 1
end

---在Game推进冷却/elapsed之后调用一次，dt为本步真实有效时长，不能按加速倍率放大。
---不在settle/reveal推进；回放的永久姿态和强制角排除由ExpansionPhysics处理。
---@param game BottleGame
---@param dt number
---@param state any
---@param events GameEvent[]
function Rotation.Step(game, dt, state, events)
    if game.phase ~= "running" then return end
    ---@type BottleRotationItem[]
    local present = game:BottleItems()
    for _, item in ipairs(present) do
        if item.id == "spinning_top" or item.id == "windmill" or item.id == "roulette" then
            item.rotationProgress = (item.rotationProgress or 0) + Rotation.SampleNatural(item, state)
            while item.rotationProgress >= TURN - EPSILON do
                item.rotationProgress = math.max(0, item.rotationProgress - TURN)
                RewardTurn(game, item, state, events)
            end
        end
    end
    for _, gear in ipairs(present) do
        if gear.id == "gear" and gear.location == "bottle" then
            local playback = gear.gearPlayback or 0
            if playback > 0 then
                gear.gearPlayback = math.max(0, playback - dt)
                if gear.gearPlayback <= EPSILON then
                    gear.gearPlayback = 0
                    MarkBatch(game, gear, state)
                end
            elseif gear.gearBatch then
                TrackBatch(game, gear, state)
                if gear.remaining <= EPSILON then Replay(game, gear, events) end
            else
                -- 无batch不应显示空转冷却；首次真实接触时才完整开始4秒。
                gear.remaining = 0
                MarkBatch(game, gear, state)
            end
        end
    end
end

return Rotation
