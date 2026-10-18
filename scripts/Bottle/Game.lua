-- Bottle 纯 Lua 规则核心（V0.3 新结算模型）；不依赖引擎、文件系统或全局 math.random。
-- 主流程（docs/游戏流程.txt）：
--   prepare  回合开始：从牌库抽最多20件入瓶，可重抽1次
--   running  摇晃阶段：10秒，物品按 trigger 实时执行效果（只改价值/状态，不产金币）
--   settle   结算阶段：禁止摇晃，物体自然下落2秒，不执行非结算效果；
--            2秒后全体物品按当前价值一次性结算金币
--   考核      每5回合扣除阶段目标（40/80/140…×1.3），余额不足则 over
--   draft    三选一：按考核次数查 docs/概率.txt 稀有度权重，刷新1次/可跳过
-- 基础设定（docs/基础设定.txt）：
--   价值增益默认临时（bonus，结算后回合末清零）；“永久+N”写入 permBonus。
--   冷却下限1秒、每回合重置、不跨回合。瓶中物品上限100。消耗≠移除：进弃牌堆。
-- 接触契约（只消费 Box2D 真接触，不以包围盒推测）：
--       [ A ] <接触> [ B ]      pairs = {{A.uid, B.uid}, ...}
--       ===== 瓶底 =====        bottom[uid] = 当前接触瓶底
--       ===== 瓶顶 =====        top[uid] = 当前接触横向封口
--       | 瓶内壁 |             wall[uid] = 当前接触任意静态内壁（含底/顶）
-- 接触仅属于 Step 开始时的瓶内实例；销毁/新产物不继承旧接触。

local Items = require("Bottle.Items")
local Effects = require("Bottle.Effects")
local Relics = require("Bottle.Relics")
local ExtraEffects = require("Bottle.ExtraEffects")
local RelicEffects = require("Bottle.RelicEffects")
local RelicState = require("Bottle.RelicState")
local DURATION = 10
local SETTLE_DELAY = 2
-- 结算展示：先逐个弹出收益浮字（队列），队列结束后再停留 REVEAL_DELAY 秒进入考核/三选一。
local REVEAL_DELAY = 2
-- 结算浮字队列节拍（与 View 共享，保证规则等待时长与逐件弹出同步）：
-- 默认每件间隔约0.24秒；物品多时按1.55秒总预算压缩，最少0.07秒。
local REVEAL_SCORE_INTERVAL = .24
local REVEAL_SCORE_MIN_INTERVAL = .07
local REVEAL_SCORE_BUDGET = 1.55
local DRAW_LIMIT = 20
local BOTTLE_LIMIT = Items.Settings.bottleLimit
local EPSILON = 1e-9
local RNG_MODULUS = 2147483647
local RNG_DOMAIN = RNG_MODULUS - 1
local TARGETS = { 40, 80, 140, 220, 320, 450, 600, 780 }
-- 不提供任意精度数：超过可精确表达的整十分范围时明确拒绝，不静默封顶目标。
local MAX_STAGE = 1000
local MAX_TARGET = 9007199254740990
local MAX_COUNTER = 2147483647

---@alias BottlePhase 'prepare'|'running'|'settle'|'reveal'|'draft'|'over'
---@alias ItemLocation 'deck'|'bottle'|'discard'|'consumed'

---@class ItemInstance
---@field uid integer
---@field id string
---@field bonus number 临时价值增益；结算后、新回合开始时清零（基础设定：价值默认临时）
---@field permBonus number 永久价值增益；描述明确“永久+N”才写入
---@field permMult number 永久倍率；回合清理与持续光环均不清除
---@field tokenAttempted boolean 赌神令牌本次归零周期是否已尝试
---@field mult number 临时倍率；回合末重置为1
---@field remaining number 秒；0 表示就绪；每回合重置，不跨回合
---@field bottleRounds integer 入瓶回合计数；香蕉“3回合后”以此为准
---@field location ItemLocation
---@field temporary boolean 临时消耗或临时产物
---@field scale number 体积倍率（大胃王/气球）；1=100%，物理与显示同步缩放
---@field counter integer 通用计数器（食客吃掉的food数/西红柿炒蛋被消耗次数）
---@field settleCount integer 结算次数计数（学生成长5次）
---@field distance number 本回合累计物理位移米数（大胃王/兔子）
---@field rollValue number? 骰子本回合点数；替代基础价值，不覆盖永久加成
---@field rerolled table<number,number>? 每位赌徒对各骰子的本回合重投次数
---@field treeBlessed boolean? 果树下一次判定的农民祝福

---@class GameEvent
---@field kind 'spawn'|'remove'|'score'|'merge'|'buff'|'transform'|'respawn'|'resize'|'burst'
---@field uid integer
---@field id string?
---@field value number?
---@field rollValue number? 骰子score时的点数，仅用于结算残影显示
---@field a integer? 合成材料 uid（merge 事件保留）
---@field b integer? 合成材料 uid
---@field x number? 事件位置，瓶内局部米制坐标
---@field y number?

---@class BottleContacts
---@field pairs number[][]?
---@field bottom table<number, boolean>?
---@field top table<number, boolean>?
---@field wall table<number, boolean>? 任意静态内壁，包含瓶底和瓶顶
---@field positions table<number, {x:number,y:number}>? 当前物理位置

---@class BottleStepContacts : BottleContacts
---@field pairs number[][]
---@field bottom table<number, boolean>
---@field top table<number, boolean>
---@field wall table<number, boolean>
---@field positions table<number, {x:number,y:number}>

---@class BottleSnapshot
---@field version integer 固定 2（V0.3 新表；v1 旧档不兼容）
---@field phase BottlePhase 只保存 prepare/draft/over
---@field round integer
---@field stage integer
---@field score number 余额
---@field totalScore number 累计获得分数，不扣目标
---@field roundScore number 当前或刚结束的回合收益
---@field elapsed number
---@field target number
---@field bestRound number 最高已完成回合数
---@field bestRoundScore number 最高单回合收益
---@field lastRoundScore number
---@field lastResult string 中文回合/达标结果
---@field drawn number[]
---@field options string[]
---@field rerollUsed boolean
---@field refreshUsed boolean
---@field revision number
---@field rngState integer 自有 PRNG 状态
---@field nextUid integer
---@field instances ItemInstance[] 每个 uid 恰好一份数据
---@field deck number[] uid 索引，非实例副本
---@field discard number[] uid 索引，非实例副本
---@field juicerValue number 榨汁机跨回合累计价值
---@field huntTargetUid integer 江湖追杀稳定目标，0为无目标
---@field relics table<string, boolean> 已拥有遗物 id 集合（V0.4 新增；旧档缺省为空）
---@field relicDraft boolean 当前三选一是否为遗物三选一（V0.4 新增）
---@field pendingRelicDraft boolean 考核达标后待追加的遗物三选一（V0.4 新增）

---@class BottleGame
---@field phase BottlePhase
---@field round integer
---@field stage integer
---@field score number
---@field totalScore number
---@field roundScore number
---@field elapsed number running 已运行秒
---@field settleElapsed number settle 已下落秒
---@field revealElapsed number reveal 结算展示已停留秒
---@field target number
---@field bestRound number
---@field bestRoundScore number
---@field lastRoundScore number
---@field lastResult string
---@field deck ItemInstance[] 包含未入瓶、瓶内、临时弃牌；不复制实例
---@field discard ItemInstance[] 当前弃牌，与 deck/注册表中的对象共享身份
---@field drawn number[] 准备阶段的抽取 uid
---@field options string[]
---@field rerollUsed boolean
---@field refreshUsed boolean
---@field revision number
---@field juicerValue number 榨汁机跨回合累计价值
---@field huntTargetUid integer 江湖追杀稳定目标，0为无目标
---@field relics table<string, boolean> 已拥有遗物 id 集合
---@field relicDraft boolean 当前三选一是否为遗物三选一
---@field pendingRelicDraft boolean 物品三选一结束后是否追加遗物三选一
---@field _rngState integer
---@field _nextUid integer
---@field _instances table<number, ItemInstance>
---@field _lastPositions table<number, {x:number,y:number}> 位移累计用的上次采样位置
---@field _rollback BottleSnapshot?
---@field startEvents GameEvent[] 回合开始掷骰的待显示事件，不持久化
local Game = {}
Game.__index = Game

Game.DURATION = DURATION
Game.SETTLE_DELAY = SETTLE_DELAY
Game.REVEAL_DELAY = REVEAL_DELAY
Game.DRAW_LIMIT = DRAW_LIMIT

---@generic T
---@param value T
---@return T
local function Copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = Copy(child) end
    return result --[[@as T]]
end

---@param value any
---@return boolean
local function IsFinite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

---@param value any
---@return boolean
local function IsInteger(value)
    return IsFinite(value) and value == math.floor(value)
end

---@param array ItemInstance[]
---@param uid integer
local function RemoveReference(array, uid)
    for i = #array, 1, -1 do
        if array[i].uid == uid then table.remove(array, i) end
    end
end

---@param array ItemInstance[]
---@param item ItemInstance
local function AddReference(array, item)
    for _, existing in ipairs(array) do
        if existing.uid == item.uid then return end
    end
    array[#array + 1] = item
end

---@param a ItemInstance
---@param b ItemInstance
---@return boolean
local function ByUid(a, b)
    return a.uid < b.uid
end

---@param events GameEvent[]
---@param kind 'spawn'|'remove'|'score'|'buff'|'transform'
---@param item ItemInstance
---@param value number?
local function Emit(events, kind, item, value)
    events[#events + 1] = { kind = kind, uid = item.uid, id = item.id, value = value }
end

---@param stage integer
---@return number
function Game.GetTarget(stage)
    assert(IsInteger(stage) and stage >= 1 and stage <= MAX_STAGE, "stage 必须是1..1000的整数")
    local target = assert(TARGETS[math.min(stage, #TARGETS)])
    for _ = #TARGETS + 1, stage do
        target = math.ceil(target * 1.3 / 10) * 10
        assert(target <= MAX_TARGET, "阶段目标超过可精确保存的数值范围")
    end
    return target
end

-- 结算浮字队列参数：View 的逐件弹出与 reveal 阶段时长共用这组常量。
Game.REVEAL_SCORE_INTERVAL = REVEAL_SCORE_INTERVAL
Game.REVEAL_SCORE_MIN_INTERVAL = REVEAL_SCORE_MIN_INTERVAL
Game.REVEAL_SCORE_BUDGET = REVEAL_SCORE_BUDGET
Game.REVEAL_DELAY = REVEAL_DELAY

--- 结算浮字队列从第一件弹出到最后一件弹出的时长（第一件立即出现）。
---@param count integer
---@return number
function Game.ScorePopTime(count)
    if count <= 0 then return 0 end
    local interval = math.min(REVEAL_SCORE_INTERVAL,
        math.max(REVEAL_SCORE_MIN_INTERVAL, REVEAL_SCORE_BUDGET / count))
    return (count - 1) * interval
end

---@param seed number?
function Game:_Init(seed)
    local chosenSeed = seed or 1
    assert(IsFinite(chosenSeed), "seed 必须为有限数字")
    self.phase = "prepare"
    self.round = 1
    self.stage = 1
    self.score = 0
    self.totalScore = 0
    self.roundScore = 0
    self.elapsed = 0
    self.settleElapsed = 0
    self.revealElapsed = 0
    self.target = Game.GetTarget(1)
    self.bestRound = 0
    self.bestRoundScore = 0
    self.lastRoundScore = 0
    self.lastResult = "准备第1回合"
    self.deck = {}
    self.discard = {}
    self.drawn = {}
    self.options = {}
    self.rerollUsed = false
    self.refreshUsed = false
    self.revision = 0
    self.relics = {}
    RelicState.InitGame(self)
    self.relicDraft = false
    self.pendingRelicDraft = false
    self._rngState = math.floor(chosenSeed) % RNG_DOMAIN + 1
    self._nextUid = 1
    self._instances = {}
    self._lastPositions = {}
    self._rollback = nil
    self.startEvents = {}
end

-- Park-Miller 48271：所有运算 < 2^53，Lua 5.4 整数与 JSON 数字往返都可精确保存。
-- 拒绝采样避免 modulo bias，候选数组固定 uid/list 顺序，绝不依赖 pairs 顺序抽签。
---@param maximum integer
---@return integer
function Game:_RandomInt(maximum)
    assert(maximum >= 1 and maximum <= RNG_DOMAIN, "随机范围无效")
    local ceiling = math.floor(RNG_DOMAIN / maximum) * maximum
    while true do
        self._rngState = math.floor((self._rngState * 48271) % RNG_MODULUS)
        local sample = self._rngState - 1
        if sample < ceiling then return math.floor(sample % maximum) + 1 end
    end
end

---@param id string
---@param temporary boolean?
---@return ItemInstance
function Game:_Create(id, temporary)
    assert(self._nextUid < MAX_COUNTER, "实例 uid 分配器已达到安全上限")
    local def = assert(Items.byId[id], "未知物品: " .. id)
    ---@type ItemInstance
    local item = {
        uid = self._nextUid, id = id, bonus = 0, permBonus = 0, mult = 1,
        remaining = def.cooldown, bottleRounds = 0, location = "deck",
        temporary = temporary or false,
        scale = 1, counter = 0, settleCount = 0, distance = 0,
        permMult = 1, tokenAttempted = false,
    }
    -- 遗物 credit_line（贷款额度）：后续获取的信用卡初始价值25（即 permBonus +15）。
    if id == "credit_card" and Relics.Has(self, "credit_line") then
        item.permBonus = 15
    end
    self._nextUid = self._nextUid + 1
    self._instances[item.uid] = item
    self.deck[#self.deck + 1] = item
    -- 遗物 small_savings（积少成多）：添加新实例立即获得1金币，不修改物品价值。
    if Relics.Has(self, "small_savings") then
        self.score = self.score + 1
        self.totalScore = self.totalScore + 1
    end
    if Relics.Has(self, "jungle_hunt") then RelicEffects.MaintainHuntTarget(self) end
    return item
end

---@param seed number?
---@return BottleGame
function Game.New(seed)
    local self = setmetatable({}, Game)
    self:_Init(seed)
    -- 初始牌库：苹果、香蕉、小球、橘子各1件（用户确认 2026-10-16）。
    self:_Create("apple")
    self:_Create("banana")
    self:_Create("ball")
    self:_Create("orange")
    self:_Prepare()
    return self
end

---@param uid number
---@return ItemInstance?
function Game:Get(uid)
    return self._instances[uid]
end

--- 返回 uid 排序数组，可 ipairs；实体为实时引用，含本回合 consumed 材料。
---@return ItemInstance[]
function Game:AllInstances()
    ---@type ItemInstance[]
    local result = {}
    for _, item in pairs(self._instances) do result[#result + 1] = item end
    table.sort(result, ByUid)
    return result
end

---@return ItemInstance[]
function Game:BottleItems()
    ---@type ItemInstance[]
    local result = {}
    for _, item in pairs(self._instances) do
        if item.location == "bottle" then result[#result + 1] = item end
    end
    table.sort(result, ByUid)
    return result
end

---@param item ItemInstance
---@param events GameEvent[]?
function Game:_EnterBottle(item, events)
    assert(#self:BottleItems() < BOTTLE_LIMIT, "瓶中物品达到上限" .. BOTTLE_LIMIT)
    RemoveReference(self.discard, item.uid)
    AddReference(self.deck, item)
    item.location = "bottle"
    item.remaining = self:CooldownOf(item.id)
    if events then Emit(events, "spawn", item) end
    self.revision = self.revision + 1
end

function Game:_Draw()
    ---@type ItemInstance[]
    local candidates = {}
    for _, item in ipairs(self.deck) do
        if item.location == "deck" then candidates[#candidates + 1] = item end
    end
    table.sort(candidates, ByUid)
    self.drawn = {}
    for _ = 1, math.min(DRAW_LIMIT, #candidates) do
        local item = table.remove(candidates, self:_RandomInt(#candidates))
        self:_EnterBottle(item)
        self.drawn[#self.drawn + 1] = item.uid
    end
end

function Game:_Prepare()
    -- 弃牌堆保留本回合记录到下一回合开始；永久消耗不会自动回牌。
    for _, item in ipairs(self.discard) do
        if item.location == "discard" then self._instances[item.uid] = nil end
    end
    self.discard = {}
    self.phase = "prepare"
    self.elapsed = 0
    self.settleElapsed = 0
    self.revealElapsed = 0
    self.roundScore = 0
    self.rerollUsed = false
    self.refreshUsed = false
    self.options = {}
    self.relicDraft = false
    self.pendingRelicDraft = false
    self._rollback = nil
    self._lastPositions = {}
    self.startEvents = {}
    for _, item in ipairs(self.deck) do
        item.location = "deck"
        item.remaining = self:CooldownOf(item.id)
        item.temporary = false
        item.distance = 0
    end
    self:_Draw()
    RelicEffects.MaintainHuntTarget(self)
    self.revision = self.revision + 1
end

---@return boolean
function Game:Reroll()
    if self.phase ~= "prepare" or self.rerollUsed then return false end
    for _, item in ipairs(self:BottleItems()) do item.location = "deck" end
    self.rerollUsed = true
    self:_Draw()
    self.revision = self.revision + 1
    return true
end

---@return boolean
function Game:Start()
    if self.phase ~= "prepare" then return false end
    -- 在任何摇晃/结算变更前冻结，包括 drawn、重抽次数与 PRNG。
    self._rollback = self:Snapshot()
    self.phase = "running"
    self.elapsed = 0
    self.settleElapsed = 0
    self.revealElapsed = 0
    self.roundScore = 0
    for _, item in ipairs(self:BottleItems()) do
        -- 冷却不跨回合，每回合重置为完整值（基础设定.txt）。
        item.remaining = self:CooldownOf(item.id)
        -- 入瓶回合计数：香蕉“3回合后”只在瓶中记录（用户确认 2026-10-16）。
        item.bottleRounds = item.bottleRounds + 1
        ExtraEffects.ResetRound(item)
    end
    ExtraEffects.Start(self, self.startEvents)
    self.revision = self.revision + 1
    return true
end

--- 摇晃持续时间：遗物 last_second（最后一秒）+1秒。
---@return number
function Game:Duration()
    return DURATION + (Relics.Has(self, "last_second") and 1 or 0)
end

--- 冷却查表：遗物 thief_handbook（小偷手册）使小偷冷却-1秒（下限1秒）。
---@param id string
---@return number
function Game:CooldownOf(id)
    local cooldown = Items.byId[id].cooldown
    if id == "thief" and Relics.Has(self, "thief_handbook") then
        cooldown = math.max(Items.Settings.minCooldown, cooldown - 1)
    end
    return cooldown
end

---@param item ItemInstance
---@return number 当前有效价值 =（基础 + 临时 + 永久）× 倍率
function Game:_Value(item)
    local base = item.rollValue or Items.byId[item.id].base
    if item.id == "trash_can" and Relics.Has(self, "lucky_charm") then base = 1 end
    -- 灵魂共振先复制墓碑当前最值，再应用灵魂石自身的加成与倍率；不递归查询灵魂石。
    if item.id == "soul_stone" and Relics.Has(self, "soul_resonance") then
        local best = -math.huge
        for _, other in ipairs(self:BottleItems()) do
            if other.id == "tombstone" then best = math.max(best, self:_Value(other)) end
        end
        if best > -math.huge then base = best end
    end
    local value = (base + item.bonus + item.permBonus) * item.mult
    -- 遗物 tomato_tycoon（西红柿首富）：西红柿价值×2。
    if item.id == "tomato" and Relics.Has(self, "tomato_tycoon") then
        value = value * 2
    end
    return value * (item.permMult or 1)
end

---@param events GameEvent[]
---@param item ItemInstance
---@param value number
---@param position {x:number,y:number}?
function Game:_Score(events, item, value, position)
    self.score = self.score + value
    self.totalScore = self.totalScore + value
    self.roundScore = self.roundScore + value
    Emit(events, "score", item, value)
    events[#events].rollValue = item.rollValue
    if position then
        local event = events[#events]
        event.x, event.y = position.x, position.y
    end
    self.revision = self.revision + 1
end

--- 原地转化：香蕉→香蕉皮/腐烂香蕉。保留 uid 与实例身份，重置数值状态。
---@param item ItemInstance
---@param newId string
---@param events GameEvent[]
function Game:_Transform(item, newId, events)
    assert(Items.byId[newId], "未知转化目标: " .. newId)
    local rerolled = item.id == "gambler" and newId == "gambling_god" and item.rerolled or nil
    item.id = newId
    item.bonus, item.permBonus, item.mult = 0, 0, 1
    RelicState.InitItem(item)
    item.remaining = self:CooldownOf(newId)
    item.scale, item.counter, item.settleCount = 1, 0, 0
    ExtraEffects.ResetRound(item)
    item.rerolled = rerolled
    self._lastPositions[item.uid] = nil
    events[#events + 1] = { kind = "transform", uid = item.uid, id = newId }
    self.revision = self.revision + 1
    RelicEffects.MaintainHuntTarget(self)
end

--- 生成新实例并立即入瓶（默认永久生成；temporary=true 为临时生成）。
--- origin 提供近源生成坐标（瓶内局部米制）；缺省时 Physics 搜索净空位置。
---@param id string
---@param events GameEvent[]
---@param temporary? boolean
---@param origin? {x:number,y:number}
---@return ItemInstance?
function Game:_Spawn(id, events, temporary, origin)
    if #self:BottleItems() >= BOTTLE_LIMIT then return nil end
    local item = self:_Create(id, temporary)
    self:_EnterBottle(item, events)
    local event = events[#events]
    if event and event.kind == "spawn" and origin then
        event.x, event.y = origin.x, origin.y
    end
    return item
end

--- 瓶顶生成（西红柿炒蛋/金针菇重生、转基因水果等“在瓶顶重新生成”）。
---@param id string
---@param events GameEvent[]
---@param temporary? boolean
---@return ItemInstance?
function Game:_SpawnTop(id, events, temporary)
    local x = (self:_RandomInt(101) - 51) / 100 * 0.8
    return self:_Spawn(id, events, temporary, { x = x, y = 6.0 })
end

--- 返回与 uid 物理接触的其他瓶内实例（真实 Box2D 接触对，按 uid 排序）。
---@param uid integer
---@param contacts BottleStepContacts
---@return ItemInstance[]
function Game:_Adjacents(uid, contacts)
    ---@type ItemInstance[]
    local result = {}
    ---@type table<number, boolean>
    local seen = {}
    for _, pair in ipairs(contacts.pairs) do
        local other = nil
        if pair[1] == uid then other = pair[2]
        elseif pair[2] == uid then other = pair[1] end
        if other and not seen[other] then
            seen[other] = true
            local item = self:Get(other)
            if item and item.location == "bottle" then result[#result + 1] = item end
        end
    end
    table.sort(result, ByUid)
    return result
end

--- 体积变化广播：大胃王/气球缩放后通知 Physics 重建碰撞体（保持位置）。
---@param item ItemInstance
---@param events GameEvent[]
function Game:ApplyScale(item, events)
    events[#events + 1] = {
        kind = "resize", uid = item.uid, id = item.id, value = item.scale,
    }
    self.revision = self.revision + 1
end

--- 合成：消耗 pair 双方，在两者中点生成产物（merge 事件供 Physics 定位）。
--- 调用方保证 a、b 都仍在瓶中；目标只能消耗一次由 _Destroy 的位置检查兜底。
---@param a ItemInstance
---@param b ItemInstance
---@param resultId string
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
function Game:_Merge(a, b, resultId, contacts, events)
    if a.location ~= "bottle" or b.location ~= "bottle" then return false end
    local posA, posB = contacts.positions[a.uid], contacts.positions[b.uid]
    local origin = (posA and posB)
        and { x = (posA.x + posB.x) * 0.5, y = (posA.y + posB.y) * 0.5 } or nil
    if not self:_Destroy(a.uid, false, events) then return false end
    if not self:_Destroy(b.uid, false, events) then return false end
    local item = self:_Create(resultId)
    self:_EnterBottle(item, events)
    local event = events[#events]
    if event and event.kind == "spawn" then
        event.kind = "merge"
        event.a, event.b = a.uid, b.uid
        if origin then event.x, event.y = origin.x, origin.y end
    end
    return true
end

--- 消灭（警察/杀手专用）：目标进弃牌堆，消灭者立即获得 目标价值×倍数 金币。
--- 金币即时入账（“立刻产生的效果”；默认约定，待用户确认）。
---@param target ItemInstance
---@param by ItemInstance
---@param multiplier number
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@return boolean
function Game:_Eliminate(target, by, multiplier, contacts, events)
    if target.location ~= "bottle" then return false end
    RelicEffects.MaintainHuntTarget(self)
    local huntTargetUid = self.huntTargetUid
    local value = self:_Value(target)
    if not self:_Destroy(target.uid, false, events) then return false end
    local position = contacts.positions[by.uid]
    self:_Score(events, by, value * multiplier, position)
    RelicEffects.OnEliminate(self, target, by, huntTargetUid, events)
    return true
end

--- 瓶顶重生（保留 uid 与实例身份）：西红柿炒蛋/金针菇被消耗后回到瓶顶。
---@param item ItemInstance
---@param events GameEvent[]
function Game:_RespawnTop(item, events)
    local x = (self:_RandomInt(101) - 51) / 100 * 0.8
    item.location = "bottle"
    item.bonus, item.mult = 0, 1
    item.remaining = self:CooldownOf(item.id)
    self._lastPositions[item.uid] = nil
    events[#events + 1] = { kind = "respawn", uid = item.uid, id = item.id, x = x, y = 6.0 }
    self.revision = self.revision + 1
end

--- 传送不是消耗：保留uid、永久/临时价值与体积，只重建物理位置及冷却。
---@param item ItemInstance
---@param events GameEvent[]
function Game:_TeleportTop(item, events)
    local x = (self:_RandomInt(101) - 51) / 100 * 0.8
    item.remaining = self:CooldownOf(item.id)
    self._lastPositions[item.uid] = nil
    events[#events + 1] = { kind = "respawn", uid = item.uid, id = item.id, x = x, y = 6.0 }
    self.revision = self.revision + 1
end

--- 返还只回牌库，不入瓶、不新建实例、不再结算；保留永久加成和跨回合状态。
---@param item ItemInstance
---@return boolean
function Game:_ReturnToDeck(item)
    if item.location ~= "discard" then return false end
    RemoveReference(self.discard, item.uid)
    AddReference(self.deck, item)
    item.location, item.temporary = "deck", false
    item.bonus, item.mult = 0, 1
    item.remaining = self:CooldownOf(item.id)
    ExtraEffects.ResetRound(item)
    self.revision = self.revision + 1
    RelicEffects.MaintainHuntTarget(self)
    return true
end

--- 消耗：进入弃牌堆（消耗≠移除）。
--- 被消耗时钩子（按 item.txt 描述）：
---   banana      → 变为香蕉皮留在瓶中（不进弃牌堆，永久转化）。
---   tomato_egg  → 瓶顶重生；被消耗5次后消失（counter 计数，跨回合保留）。
---   enoki       → 瓶顶重生；遗物 seeYouTomorrow 时每次被消耗永久+1。
---   ghost       → 进行一次结算（立即按当前价值产金币；“立刻产生的效果”）。
--- 遗物 gm_fruit：水果被消耗时10%几率在瓶顶生成一个新的完整水果。
---@param uid integer
---@param temporary boolean
---@param events GameEvent[]
---@return boolean
function Game:_Destroy(uid, temporary, events)
    local item = self:Get(uid)
    if not item or item.location ~= "bottle" then return false end
    if item.id == "banana" then
        -- 香蕉虽然转化为皮留瓶内，仍算水果被消耗，不能漏掉遗物判定。
        self:_Transform(item, "banana_peel", events)
        if Relics.Has(self, "gm_fruit") and self:_RandomInt(10) == 1 then
            local pool = { "apple", "banana", "orange", "cherry" }
            self:_SpawnTop(pool[self:_RandomInt(#pool)], events)
        end
        return true
    end
    if item.id == "tomato_egg" then
        item.counter = item.counter + 1
        if item.counter < RelicEffects.TomatoEggLimit(self) then
            self:_RespawnTop(item, events)
        else
            item.location = "discard"
            RemoveReference(self.deck, uid)
            AddReference(self.discard, item)
            Emit(events, "remove", item)
        end
        self.revision = self.revision + 1
        return true
    end
    if item.id == "enoki" then
        if Relics.Has(self, "see_you_tomorrow") then
            item.permBonus = item.permBonus + 1
            events[#events + 1] = {
                kind = "buff", uid = item.uid, id = item.id, value = 1,
            }
        end
        self:_RespawnTop(item, events)
        return true
    end
    if item.id == "ghost" then
        self:_Score(events, item, self:_Value(item), nil)
    end
    item.location = "discard"
    item.temporary = item.temporary or temporary
    if item.temporary then AddReference(self.deck, item)
    else RemoveReference(self.deck, uid) end
    AddReference(self.discard, item)
    Emit(events, "remove", item)
    -- 遗物 gm_fruit（转基因水果）：水果被消耗时10%几率瓶顶生成完整水果。
    if Relics.Has(self, "gm_fruit") and Items.HasTag(item.id, "水果")
        and self:_RandomInt(10) == 1 then
        local pool = { "apple", "banana", "orange", "cherry" }
        self:_SpawnTop(pool[self:_RandomInt(#pool)], events)
    end
    self.revision = self.revision + 1
    RelicEffects.MaintainHuntTarget(self)
    return true
end

--- 普通消耗永久移出牌库，临时消耗在回合末恢复；均记录在本回合弃牌堆。
--- running/settle 之外拒绝。
---@param uid integer
---@param temporary boolean?
---@return GameEvent[]
function Game:Consume(uid, temporary)
    ---@type GameEvent[]
    local events = {}
    if self.phase == "running" or self.phase == "settle" then
        self:_Destroy(uid, temporary == true, events)
    end
    return events
end

-- 将接触绑定到当前瓶内实例，拒绝外部快照中的未来 uid/已弃牌 uid。
---@param contacts BottleContacts
---@return BottleStepContacts
function Game:_ContactSnapshot(contacts)
    ---@type BottleStepContacts
    local state = { pairs = {}, bottom = {}, top = {}, wall = {}, positions = {} }
    ---@type table<number, boolean>
    local present = {}
    for _, item in ipairs(self:BottleItems()) do
        local uid = item.uid
        present[uid] = true
        state.bottom[uid] = contacts.bottom and contacts.bottom[uid] == true or nil
        state.top[uid] = contacts.top and contacts.top[uid] == true or nil
        state.wall[uid] = contacts.wall and contacts.wall[uid] == true or nil
        local position = contacts.positions and contacts.positions[uid] or nil
        if position and IsFinite(position.x) and IsFinite(position.y) then
            state.positions[uid] = {x = position.x, y = position.y}
        end
    end
    for _, pair in ipairs(contacts.pairs or {}) do
        local a, b = pair[1], pair[2]
        if IsInteger(a) and IsInteger(b) and a ~= b and present[a] and present[b] then
            state.pairs[#state.pairs + 1] = { a, b }
        end
    end
    return state
end

-- fixture 被销毁或重建后，相同 uid 也不能沿用旧接触。
---@param contacts BottleStepContacts
---@param events GameEvent[]
---@param first integer
local function InvalidateContacts(contacts, events, first)
    ---@type table<number, boolean>
    local removed = {}
    for i = first, #events do
        local event = events[i]
        if event.kind == "remove" or event.kind == "spawn" or event.kind == "transform"
            or event.kind == "merge" or event.kind == "respawn" or event.kind == "resize" then
            removed[event.uid] = true
            contacts.bottom[event.uid] = nil
            contacts.top[event.uid] = nil
            contacts.wall[event.uid] = nil
        end
        -- 合成事件同时移除两份材料的接触（材料 uid 记在 a/b）。
        if event.kind == "merge" then
            for _, uid in ipairs({ event.a, event.b }) do
                if uid then
                    removed[uid] = true
                    contacts.bottom[uid] = nil
                    contacts.top[uid] = nil
                    contacts.wall[uid] = nil
                end
            end
        end
    end
    for i = #contacts.pairs, 1, -1 do
        local pair = contacts.pairs[i]
        if removed[pair[1]] or removed[pair[2]] then table.remove(contacts.pairs, i) end
    end
end

--- 位移累计（大胃王#8：位移10m体积-10%，下限100%）。
--- 以物理采样位置差分累计每件的 distance；缩体积经 resize 事件重建 body。
--- ExtraEffects 消费位移阈值，并应用健身教练物品的缩幅加倍与兔子永久增长。
---@param state BottleStepContacts
---@param events GameEvent[]
function Game:_TrackDistances(state, events)
    for _, item in ipairs(self:BottleItems()) do
        local position = state.positions[item.uid]
        local record = self._lastPositions[item.uid]
        if position and record then
            local dx, dy = position.x - record.x, position.y - record.y
            local stepDistance = math.sqrt(dx * dx + dy * dy)
            -- 过滤物理重建/传送造成的跳变（respawn、resize 重建后首帧）。
            if stepDistance < 1.0 then item.distance = item.distance + stepDistance end
        end
        if position then
            self._lastPositions[item.uid] = { x = position.x, y = position.y }
        else
            self._lastPositions[item.uid] = nil
        end
        ExtraEffects.TrackDistance(self, item, events)
    end
end

---@param item ItemInstance
---@param contacts BottleStepContacts
---@return boolean
function Game:_Touches(item, contacts)
    if item.location ~= "bottle" then return false end
    return Effects.Touches(self, item, contacts) == true
end

-- 同一时间点先做合成（设计约定：合成优先于一切触发），再冻结 ready，
-- 按 BottleItems 的 uid 顺序逐件完成效果。
---@param contacts BottleStepContacts
---@param events GameEvent[]
function Game:_Resolve(contacts, events)
    local firstMerge = #events + 1
    Effects.Merge(self, contacts, events)
    if #events >= firstMerge then InvalidateContacts(contacts, events, firstMerge) end
    Effects.Continuous(self, contacts, events)
    ---@type ItemInstance[]
    local ready = {}
    for _, item in ipairs(self:BottleItems()) do
        if item.remaining <= EPSILON then
            item.remaining = 0
            if self:_Touches(item, contacts) then ready[#ready + 1] = item end
        end
    end
    for _, item in ipairs(ready) do
        if item.location == "bottle" and self:_Touches(item, contacts) then
            local firstEvent = #events + 1
            Effects.Apply(self, item, contacts, events)
            RelicEffects.Maintain(self, events)
            if item.location == "bottle" then item.remaining = self:CooldownOf(item.id) end
            InvalidateContacts(contacts, events, firstEvent)
            Effects.Continuous(self, contacts, events)
        end
    end
    local firstRelic = #events + 1
    RelicEffects.Maintain(self, events)
    InvalidateContacts(contacts, events, firstRelic)
end

---@param delta number
function Game:_Advance(delta)
    for _, item in ipairs(self:BottleItems()) do
        item.remaining = math.max(0, item.remaining - delta)
    end
    self.elapsed = self.elapsed + delta
end

--- running 阶段推进：冷却调度实时效果 + 持续型状态（橘子贴底）。
--- dt=0 可即时处理接触。负值/NaN/无穷 dt 明确拒绝。
--- 自动在 10 秒（包含该时间点所有效果）转入 settle 结算阶段。
---@param dt number
---@param contacts BottleContacts?
---@return GameEvent[]
function Game:Step(dt, contacts)
    ---@type GameEvent[]
    local events = {}
    if self.phase ~= "running" then return events end
    assert(IsFinite(dt) and dt >= 0, "dt 必须为非负有限数字")
    local duration = self:Duration()
    local state = self:_ContactSnapshot(contacts or {})
    self:_TrackDistances(state, events)
    InvalidateContacts(state, events, 1)
    local endpoint = math.min(duration, self.elapsed + dt)
    while self.elapsed < endpoint - EPSILON do
        local wait = endpoint - self.elapsed
        for _, item in ipairs(self:BottleItems()) do
            if self:_Touches(item, state) then wait = math.min(wait, item.remaining) end
        end
        if wait >= endpoint - self.elapsed - EPSILON then break end
        self:_Advance(wait)
        self:_Resolve(state, events)
    end
    self:_Advance(math.max(0, endpoint - self.elapsed))
    self.elapsed = endpoint
    -- 端点效果仍结算：dt=0 或恰好到时长时，就绪且接触的物品在此处理。
    self:_Resolve(state, events)
    -- 持续型状态每步同步（贴底加成本质是状态而非离散触发）。
    Effects.Continuous(self, state, events)
    if self.elapsed >= duration - EPSILON then
        self.elapsed = duration
        self.phase = "settle"
        self.settleElapsed = 0
        self.revealElapsed = 0
        self.revision = self.revision + 1
    end
    return events
end

--- settle 阶段推进：自然下落 SETTLE_DELAY 秒后全体一次性结算。
--- 下落期间禁止摇晃（调用方不给 Shake），持续型状态（橘子贴底）继续同步，
--- 离散触发效果（小球碰撞等）不再执行（游戏流程.txt：不再执行非结算效果）。
---@param dt number
---@param contacts BottleContacts?
---@return GameEvent[]
function Game:SettleStep(dt, contacts)
    ---@type GameEvent[]
    local events = {}
    if self.phase ~= "settle" then return events end
    assert(IsFinite(dt) and dt >= 0, "dt 必须为非负有限数字")
    local state = self:_ContactSnapshot(contacts or {})
    local endpoint = math.min(SETTLE_DELAY, self.settleElapsed + dt)
    self.settleElapsed = endpoint
    Effects.Continuous(self, state, events)
    if self.settleElapsed >= SETTLE_DELAY - EPSILON then
        self.settleElapsed = SETTLE_DELAY
        local finished = self:_Settle(state)
        for _, event in ipairs(finished) do events[#events + 1] = event end
    end
    return events
end

--- 全体结算：按 uid 顺序每件物品按当前价值产金币；随后处理香蕉成熟转化与回合清理。
--- 结算完成后进入 reveal 展示阶段（停留 REVEAL_DELAY 秒），展示结束再由 _FinishReveal
--- 执行考核扣款与三选一。重复调用无副作用（阶段已离开 settle）。
---@param state BottleStepContacts
---@return GameEvent[]
function Game:_Settle(state)
    ---@type GameEvent[]
    local events = {}
    if self.phase ~= "settle" then return events end
    -- 结算前奏（产金币前）：种子转化、气球膨胀/爆炸、学生计数成长、桂冠锁定。
    -- 结算前奏的邻接倍率只在最终真实接触上计算一次。
    ExtraEffects.BeforeSettle(self, state, events)
    Effects.SettleEffects(self, events)
    RelicEffects.Maintain(self, events)
    -- 逐个弹出队列的件数：只有正收益物品会产生浮字（View 也只入队正数）。
    local popCount = 0
    for _, item in ipairs(self:BottleItems()) do
        if self:_Value(item) > 0 then popCount = popCount + 1 end
    end
    self._revealPopCount = popCount
    for _, item in ipairs(self:BottleItems()) do
        Effects.SettleItem(self, item, events, state.positions[item.uid])
    end
    -- 结算尾声（全体产金币后）：信用卡永久-1。
    Effects.PostSettle(self, events)
    ExtraEffects.AfterSettle(self, events)
    RelicEffects.AfterSettle(self, events)
    -- 香蕉入瓶满3回合，结算完成后变为腐烂的香蕉（用户确认：入瓶才记录回合）。
    for _, item in ipairs(self:BottleItems()) do
        if item.id == "banana" and item.bottleRounds >= 3 then
            self:_Transform(item, "rotten_banana", events)
        end
    end
    self.lastRoundScore = self.roundScore
    self.bestRound = math.max(self.bestRound, self.round)
    self.bestRoundScore = math.max(self.bestRoundScore, self.roundScore)
    self:_CleanupRound()
    self.options = {}
    self.refreshUsed = false
    self.lastResult = string.format("第%d回合获得%g金币", self.round, self.roundScore)
    -- 分数已弹出，进入结算展示阶段停留，让玩家看清再进入考核/三选一。
    -- 保留 _rollback 到 reveal 结束：展示中退出仍回退到回合开始前。
    self.phase = "reveal"
    self.revealElapsed = 0
    self.revision = self.revision + 1
    return events
end

--- reveal 结算展示阶段推进：逐件弹出收益浮字（队列），队列播完后再停留
--- REVEAL_DELAY 秒执行考核扣款与三选一（用户要求：队列结束之后暂停两秒）。
--- 该阶段不产金币、无物理步进，仅等待玩家看清分数。
---@param dt number
---@return GameEvent[]
function Game:RevealStep(dt)
    ---@type GameEvent[]
    local events = {}
    if self.phase ~= "reveal" then return events end
    assert(IsFinite(dt) and dt >= 0, "dt 必须为非负有限数字")
    local duration = REVEAL_DELAY + Game.ScorePopTime(self._revealPopCount or 0)
    self.revealElapsed = math.min(duration, self.revealElapsed + dt)
    if self.revealElapsed >= duration - EPSILON then
        self.revealElapsed = duration
        self:_FinishReveal()
    end
    return events
end

--- 结算展示结束：执行考核扣款（每5回合）与三选一；余额不足则结束。
--- 考核达标的回合标记 pendingRelicDraft：物品三选一结束后追加遗物三选一
--- （游戏流程：考核后增加一个遗物的三选一；默认约定沿用 draft 交互，待用户确认）。
function Game:_FinishReveal()
    if self.phase ~= "reveal" then return end
    self._rollback = nil
    if self.round % 5 == 0 then
        local paidTarget = self.target
        if self.score < paidTarget then
            self.phase = "over"
            self.lastResult = self.lastResult .. string.format("，余额%g未达到考核目标%g", self.score, paidTarget)
            self.revision = self.revision + 1
            return
        end
        local nextStage = self.stage + 1
        local nextTarget = Game.GetTarget(nextStage)
        self.score = self.score - paidTarget
        self.stage = nextStage
        self.target = nextTarget
        self.lastResult = self.lastResult .. string.format("，考核达标扣除%g，下一目标%g", paidTarget, self.target)
        self.pendingRelicDraft = true
    end
    self.phase = "draft"
    self.relicDraft = false
    self.options = self:_DraftOptions()
    self.revision = self.revision + 1
end

--- 遗物三选一候选：按考核次数概率表抽稀有度，排除已拥有；
--- 所抽稀有度无可用候选时顺延抽其他稀有度（与物品三选一同一机制）。
---@return string[]
function Game:_RelicDraftOptions()
    local weights = Items.DraftWeights(self.stage)
    ---@type table<string, boolean>
    local chosen = {}
    ---@type string[]
    local options = {}
    for _ = 1, 3 do
        ---@type RelicDef[][]
        local buckets = {}
        for rarity = 1, 5 do buckets[rarity] = {} end
        for _, def in ipairs(Relics.list) do
            if def.pool and def.implemented and not self.relics[def.id] and not chosen[def.id] then
                local bucket = buckets[def.rarity]
                bucket[#bucket + 1] = def
            end
        end
        local weight = 0
        for rarity = 1, 5 do
            if #buckets[rarity] > 0 then weight = weight + weights[rarity] end
        end
        if weight == 0 then break end
        local ticket = self:_RandomInt(weight)
        for rarity = 1, 5 do
            if #buckets[rarity] > 0 then
                local chance = weights[rarity]
                if ticket <= chance then
                    local bucket = buckets[rarity]
                    local id = bucket[self:_RandomInt(#bucket)].id
                    options[#options + 1] = id
                    chosen[id] = true
                    break
                end
                ticket = ticket - chance
            end
        end
    end
    return options
end

--- 进入遗物三选一：复用 draft 阶段与刷新/跳过交互；候选为空时直接推进回合。
function Game:_EnterRelicDraft()
    self.pendingRelicDraft = false
    self.relicDraft = true
    self.options = self:_RelicDraftOptions()
    self.refreshUsed = false
    if #self.options == 0 then
        -- 全部遗物已拥有：无候选，直接推进回合。
        self.relicDraft = false
        self:_AdvanceRound()
    else
        self.revision = self.revision + 1
    end
end

--- 物品/遗物三选一结束后推进到下一回合。
function Game:_AdvanceRound()
    if self.round >= MAX_COUNTER then return end
    self.relicDraft = false
    self.round = self.round + 1
    self:_Prepare()
end

-- 所有草稿入口共享资格判断；GM只过滤失效选项，不重抽或补齐候选。
---@param deck ItemInstance[]
---@return table<string, boolean>
local function OwnedTypes(deck)
    ---@type table<string, boolean>
    local owned = {}
    for _, item in ipairs(deck) do
        if item.location ~= "consumed" then owned[item.id] = true end
    end
    return owned
end

---@param def ItemDef?
---@param owned table<string, boolean>
---@return boolean
local function DraftEligible(def, owned)
    if not def or not def.pool or not def.implemented then return false end
    if def.unique and owned[def.id] then return false end
    return true
end

--- 三选一：稀有度权重按考核次数查 docs/概率.txt（Items.DraftWeights）。
--- 每组物品类型不重复；候选不足3件时按可用数量给出。
---@return string[]
function Game:_DraftOptions()
    local owned = OwnedTypes(self.deck)
    local weights = Items.DraftWeights(self.stage)
    ---@type table<string, boolean>
    local chosen = {}
    ---@type string[]
    local options = {}
    for _ = 1, 3 do
        ---@type ItemDef[][]
        local buckets = {}
        for rarity = 1, 5 do buckets[rarity] = {} end
        for _, def in ipairs(Items.list) do
            if not chosen[def.id] and DraftEligible(def, owned) then
                local bucket = buckets[def.rarity]
                bucket[#bucket + 1] = def
            end
        end
        local weight = 0
        for rarity = 1, 5 do
            if #buckets[rarity] > 0 then weight = weight + weights[rarity] end
        end
        if weight == 0 then break end
        local ticket = self:_RandomInt(weight)
        for rarity = 1, 5 do
            if #buckets[rarity] > 0 then
                local chance = weights[rarity]
                if ticket <= chance then
                    local bucket = buckets[rarity]
                    local id = bucket[self:_RandomInt(#bucket)].id
                    options[#options + 1] = id
                    chosen[id] = true
                    break
                end
                ticket = ticket - chance
            end
        end
    end
    return options
end

function Game:_CleanupRound()
    for _, item in ipairs(self:AllInstances()) do
        -- 弃牌也会入档：所有位置统一去掉临时状态，保留永久状态供返还。
        item.bonus, item.mult = 0, 1
        ExtraEffects.ResetRound(item)
        if item.location == "consumed" then
            RemoveReference(self.deck, item.uid)
            RemoveReference(self.discard, item.uid)
            self._instances[item.uid] = nil
        elseif item.location == "discard" and not item.temporary then
            -- 永久消耗仅保留弃牌记录，不再是拥有物品；下一回合开始清空。
            RemoveReference(self.deck, item.uid)
        else
            item.location = "deck"
            item.temporary = false
            -- 临时价值/倍率回合末清零；permBonus 永久保留（基础设定.txt）。
            item.bonus, item.mult = 0, 1
            item.remaining = self:CooldownOf(item.id)
            AddReference(self.deck, item)
            RemoveReference(self.discard, item.uid)
        end
    end
    table.sort(self.deck, ByUid)
    self.drawn = {}
    RelicEffects.Maintain(self)
end

--- 可由 main 提前主动结束摇晃；正常流程由 Step 在恰好 10s 转入 settle。
--- 提前结束时跳过2秒下落，直接以当前接触状态结算。
---@param contacts BottleContacts?
---@return GameEvent[]
function Game:Finish(contacts)
    ---@type GameEvent[]
    local events = {}
    if self.phase ~= "running" and self.phase ~= "settle" then return events end
    self.phase = "settle"
    self.settleElapsed = SETTLE_DELAY
    local state = self:_ContactSnapshot(contacts or {})
    Effects.Continuous(self, state, events)
    local finished = self:_Settle(state)
    for _, event in ipairs(finished) do events[#events + 1] = event end
    return events
end

---@return boolean
function Game:DraftRefresh()
    if self.phase ~= "draft" or self.refreshUsed then return false end
    self.refreshUsed = true
    -- 不排除上一组，允许刷新得到以前的 id。
    self.options = self.relicDraft and self:_RelicDraftOptions() or self:_DraftOptions()
    self.revision = self.revision + 1
    return true
end

--- 物品三选一结束：若本回合考核达标（pendingRelicDraft）则追加遗物三选一，否则推进回合。
function Game:_FinishItemDraft()
    if self.pendingRelicDraft then
        self:_EnterRelicDraft()
    else
        self:_AdvanceRound()
    end
end

---@param index integer
---@return boolean
function Game:Choose(index)
    if self.phase ~= "draft" or not IsInteger(index) or self.round >= MAX_COUNTER then return false end
    local id = self.options[index]
    if not id then return false end
    if self.relicDraft then
        local def = Relics.byId[id]
        if not def or not def.pool or not def.implemented or self.relics[id] then return false end
        self.relics[id] = true
        RelicEffects.OnAcquire(self, id)
        self:_AdvanceRound()
        return true
    end
    if not DraftEligible(Items.byId[id], OwnedTypes(self.deck)) then return false end
    self:_Create(id)
    self:_FinishItemDraft()
    return true
end

---@return boolean
function Game:Skip()
    if self.phase ~= "draft" or self.round >= MAX_COUNTER then return false end
    if self.relicDraft then
        self:_AdvanceRound()
    else
        self:_FinishItemDraft()
    end
    return true
end

--- GM 功能：按物品 id 添加一件已实装物品到牌库。
--- running/settle 阶段拒绝：回合前快照会把新增物品回滚。
---@param id string|integer
---@return boolean ok
---@return string message
function Game:GmAddItem(id)
    if self.phase == "running" or self.phase == "settle" or self.phase == "reveal" then
        return false, "摇晃或结算进行中不能添加物品，请等本回合结束"
    end
    local numberId = type(id) == "number" and id or tonumber(id)
    local def = numberId and (Items.byNumber --[[@as table<number,ItemDef>]])[numberId] or Items.byId[id]
    if not def then return false, "未知物品 id：" .. tostring(id) end
    if not def.implemented then
        return false, string.format("%s（#%d）尚未实装，暂不能添加", def.name, def.numberId)
    end
    local item = self:_Create(def.id)
    if self.phase == "draft" and not self.relicDraft then
        -- 遗物三选一的候选与牌库无关，添加物品不过滤遗物候选。
        local owned = OwnedTypes(self.deck)
        ---@type string[]
        local options = {}
        for _, option in ipairs(self.options) do
            if DraftEligible(Items.byId[option], owned) then options[#options + 1] = option end
        end
        self.options = options
    end
    self.revision = self.revision + 1
    return true, string.format("已添加 %s（#%d）到牌库，当前牌库 %d 件", def.name, item.uid, #self.deck)
end

---@return BottleSnapshot
function Game:Snapshot()
    if self.phase == "running" or self.phase == "settle" or self.phase == "reveal" then
        return Copy(assert(self._rollback, "running/settle/reveal 缺少回合前快照"))
    end
    ---@type number[]
    local deck = {}
    ---@type number[]
    local discard = {}
    for _, item in ipairs(self.deck) do deck[#deck + 1] = item.uid end
    for _, item in ipairs(self.discard) do discard[#discard + 1] = item.uid end
    return {
        version = 2, phase = self.phase, round = self.round, stage = self.stage,
        score = self.score, totalScore = self.totalScore, roundScore = self.roundScore,
        elapsed = self.elapsed, target = self.target,
        bestRound = self.bestRound, bestRoundScore = self.bestRoundScore,
        lastRoundScore = self.lastRoundScore, lastResult = self.lastResult,
        drawn = Copy(self.drawn), options = Copy(self.options),
        rerollUsed = self.rerollUsed, refreshUsed = self.refreshUsed,
        revision = self.revision, rngState = self._rngState, nextUid = self._nextUid,
        instances = Copy(self:AllInstances()), deck = deck, discard = discard,
        relics = Copy(self.relics), relicDraft = self.relicDraft,
        pendingRelicDraft = self.pendingRelicDraft,
        juicerValue = self.juicerValue, huntTargetUid = self.huntTargetUid,
    }
end

-- 存档数组必须是无额外键的连续1-based数组；避免 ipairs 静默丢掉损坏数据。
---@param value any
---@param name string
---@return integer
local function ArrayLength(value, name)
    assert(type(value) == "table" and getmetatable(value) == nil, "无效存档数组: " .. name)
    local count = 0
    for key in pairs(value) do
        assert(IsInteger(key) and key >= 1, "无效存档数组键: " .. name)
        count = count + 1
    end
    assert(count == #value, "存档数组不连续: " .. name)
    for index = 1, count do assert(value[index] ~= nil, "存档数组缺项: " .. name) end
    return count
end

---@param snapshot BottleSnapshot
---@return BottleGame
function Game.Restore(snapshot)
    assert(type(snapshot) == "table" and getmetatable(snapshot) == nil and snapshot.version == 2,
        "存档版本不兼容（V0.3 新表需要 version=2；旧档作废）")
    assert(snapshot.phase == "prepare" or snapshot.phase == "draft" or snapshot.phase == "over",
        "存档必须是 prepare/draft/over；运行/结算中应保存回合前快照")
    assert(IsInteger(snapshot.round) and snapshot.round >= 1 and snapshot.round <= MAX_COUNTER, "无效回合")
    -- 先验上限，再调用 GetTarget；损坏的超大 stage 不会进入长循环。
    assert(IsInteger(snapshot.stage) and snapshot.stage >= 1 and snapshot.stage <= MAX_STAGE, "无效阶段")
    local completed = snapshot.phase == "draft" and snapshot.round or snapshot.round - 1
    local expectedStage = math.floor(completed / 5) + 1
    assert(snapshot.stage == expectedStage, "阶段与回合不符")
    assert(snapshot.phase ~= "over" or snapshot.round % 5 == 0, "终局回合不是考核回合")
    assert(IsInteger(snapshot.rngState) and snapshot.rngState >= 1 and snapshot.rngState < RNG_MODULUS,
        "无效 PRNG 状态")
    assert(IsInteger(snapshot.nextUid) and snapshot.nextUid >= 1 and snapshot.nextUid <= MAX_COUNTER,
        "无效 uid 分配器")
    assert(type(snapshot.rerollUsed) == "boolean" and type(snapshot.refreshUsed) == "boolean", "无效次数状态")
    assert(type(snapshot.lastResult) == "string", "无效回合结果")
    local scalarNames = {
        "score", "totalScore", "roundScore", "elapsed", "target", "bestRound",
        "bestRoundScore", "lastRoundScore", "revision",
    }
    for _, key in ipairs(scalarNames) do assert(IsFinite(snapshot[key]), "无效存档字段: " .. key) end
    assert(snapshot.elapsed >= 0 and snapshot.elapsed <= DURATION + 1, "无效运行时间")
    assert(IsInteger(snapshot.bestRound) and snapshot.bestRound >= 0 and snapshot.bestRound <= snapshot.round,
        "无效最佳回合")
    assert(IsInteger(snapshot.revision) and snapshot.revision >= 0 and snapshot.revision <= 9007199254740991,
        "无效状态版本")
    assert(snapshot.target == Game.GetTarget(snapshot.stage), "目标与阶段不符")
    ArrayLength(snapshot.instances, "instances")
    ArrayLength(snapshot.deck, "deck")
    ArrayLength(snapshot.discard, "discard")
    assert(snapshot.phase ~= "prepare" or #snapshot.discard == 0, "准备阶段弃牌必须为空")
    assert(ArrayLength(snapshot.drawn, "drawn") <= DRAW_LIMIT, "准备抽取超过20个")
    assert(ArrayLength(snapshot.options, "options") <= 3, "三选一数量无效")
    if snapshot.phase == "prepare" then
        assert(snapshot.elapsed == 0 and snapshot.roundScore == 0 and #snapshot.options == 0
            and not snapshot.refreshUsed, "准备阶段数据不一致")
    else
        assert(#snapshot.drawn == 0, "非准备阶段不能残留抽取列表")
        assert(snapshot.phase ~= "over" or #snapshot.options == 0, "终局不能残留三选一")
    end
    local self = setmetatable({}, Game)
    self:_Init(1) -- 只初始化字段，不抽取，不消耗随机状态。
    self.phase, self.round, self.stage = snapshot.phase, math.floor(snapshot.round), math.floor(snapshot.stage)
    self.score, self.totalScore, self.roundScore = snapshot.score, snapshot.totalScore, snapshot.roundScore
    self.elapsed, self.target = snapshot.elapsed, snapshot.target
    self.bestRound, self.bestRoundScore = snapshot.bestRound, snapshot.bestRoundScore
    self.lastRoundScore, self.lastResult = snapshot.lastRoundScore, snapshot.lastResult
    self.rerollUsed, self.refreshUsed, self.revision = snapshot.rerollUsed, snapshot.refreshUsed, snapshot.revision
    self._rngState, self._nextUid = math.floor(snapshot.rngState), math.floor(snapshot.nextUid)
    self.juicerValue, self.huntTargetUid = RelicState.ReadGame(snapshot)
    -- 遗物字段（V0.4 新增；旧档缺省为无遗物）。
    if snapshot.relics ~= nil then
        assert(type(snapshot.relics) == "table" and getmetatable(snapshot.relics) == nil, "无效遗物集合")
        for id, owned in pairs(snapshot.relics) do
            assert(type(id) == "string" and Relics.byId[id], "存档包含未知遗物")
            assert(owned == true, "遗物集合值必须为 true")
            self.relics[id] = true
        end
    end
    self.relicDraft = snapshot.relicDraft == true
    self.pendingRelicDraft = snapshot.pendingRelicDraft == true
    if self.relicDraft then
        assert(self.phase == "draft", "遗物三选一必须处于 draft 阶段")
    end
    for _, saved in ipairs(snapshot.instances) do
        assert(type(saved) == "table" and getmetatable(saved) == nil, "无效存档实例")
        assert(IsInteger(saved.uid) and saved.uid > 0 and saved.uid < self._nextUid, "无效实例 uid")
        assert(not self._instances[saved.uid], "存档实例 uid 重复")
        assert(type(saved.id) == "string" and Items.byId[saved.id], "存档包含未知物品")
        assert(IsFinite(saved.bonus) and IsFinite(saved.permBonus) and IsFinite(saved.mult)
            and IsFinite(saved.remaining) and saved.remaining >= 0
            and saved.temporary == false, "无效实例属性或临时状态残留")
        assert(saved.bonus == 0 and saved.mult == 1, "可持久化阶段残留临时价值或倍率")
        assert(IsInteger(saved.bottleRounds) and saved.bottleRounds >= 0, "无效入瓶回合计数")
        -- 跨回合实例状态（V0.4）：体积倍率/通用计数/结算计数；旧档缺省补默认值。
        local savedScale = saved.scale == nil and 1 or saved.scale
        local savedCounter = saved.counter == nil and 0 or saved.counter
        local savedSettleCount = saved.settleCount == nil and 0 or saved.settleCount
        assert(IsFinite(savedScale) and savedScale >= 1 and savedScale <= 2, "无效体积倍率")
        assert(IsInteger(savedCounter) and savedCounter >= 0, "无效计数器")
        assert(IsInteger(savedSettleCount) and savedSettleCount >= 0, "无效结算计数")
        assert(saved.location == "deck" or (self.phase == "prepare" and saved.location == "bottle")
            or (self.phase ~= "prepare" and saved.location == "discard"), "可持久化阶段实例位置不合法")
        local permMult, tokenAttempted = RelicState.ReadItem(saved)
        -- 白名单字段拷贝：不把损坏存档的额外 table/function 导入运行状态。
        self._instances[saved.uid] = {
            uid = math.floor(saved.uid), id = saved.id, bonus = 0, permBonus = saved.permBonus,
            mult = 1, remaining = saved.remaining, bottleRounds = math.floor(saved.bottleRounds),
            location = saved.location, temporary = false,
            scale = savedScale, counter = savedCounter, settleCount = savedSettleCount,
            distance = 0, permMult = permMult, tokenAttempted = tokenAttempted,
        }
    end
    ---@type table<number, boolean>
    local deckSeen = {}
    for _, uid in ipairs(snapshot.deck) do
        assert(IsInteger(uid) and self:Get(uid), "持有实例索引不存在")
        assert(not deckSeen[uid], "持有实例索引重复")
        assert(assert(self:Get(uid)).location ~= "discard", "弃牌不能同时属于持有牌库")
        deckSeen[uid] = true
        self.deck[#self.deck + 1] = assert(self:Get(uid))
    end
    ---@type table<number, boolean>
    local discardSeen = {}
    for _, uid in ipairs(snapshot.discard) do
        assert(IsInteger(uid), "弃牌 uid 不是整数")
        local item = assert(self:Get(uid), "弃牌索引不存在")
        assert(not discardSeen[uid] and not deckSeen[uid] and item.location == "discard",
            "弃牌重复、位置错误或仍在牌库")
        discardSeen[uid] = true
        self.discard[#self.discard + 1] = item
    end
    assert(#self.deck + #self.discard == #snapshot.instances, "实例必须唯一归属牌库或弃牌堆")
    ---@type table<number, boolean>
    local drawnSeen = {}
    for _, uid in ipairs(snapshot.drawn) do
        assert(IsInteger(uid), "抽取 uid 不是整数")
        local item = assert(self:Get(uid), "抽取实例不存在")
        assert(not drawnSeen[uid] and item.location == "bottle", "抽取实例重复或不在瓶中")
        drawnSeen[uid] = true
        self.drawn[#self.drawn + 1] = uid
    end
    for _, item in ipairs(self.deck) do
        assert(item.location ~= "bottle" or drawnSeen[item.uid], "瓶中实例未列入抽取列表")
    end
    ---@type table<string, boolean>
    local optionSeen = {}
    local owned = OwnedTypes(self.deck)
    for _, id in ipairs(snapshot.options) do
        if self.relicDraft then
            local relic = Relics.byId[id]
            assert(type(id) == "string" and not optionSeen[id]
                and relic and relic.pool and not self.relics[id], "无效或已拥有的遗物三选一选项")
        else
            assert(type(id) == "string" and not optionSeen[id]
                and DraftEligible(Items.byId[id], owned), "无效或已不符合资格的三选一选项")
        end
        optionSeen[id] = true
        self.options[#self.options + 1] = id
    end
    RelicState.ValidateTarget(self)
    return self
end

return Game
