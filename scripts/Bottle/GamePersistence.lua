-- 可持久化阶段的快照与严格恢复。运行/结算/展示始终返回回合前快照，不存半回合现场。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicState = require("Bottle.RelicState")
local PhysicalState = require("Bottle.PhysicalState")
local Money = require("Bottle.Money")
local GamePersistence = {}

-- 与 Game 的规则常量保持一致；持久化校验不依赖可变运行状态。
local DURATION = 10
local DRAW_LIMIT = 20
local MAX_COUNTER = 2147483647
local MAX_STAGE = 1000
local RNG_MODULUS = 2147483647
local RULES_VERSION = 8

---@class GamePersistenceHelpers
---@field Copy fun(value:any):any
---@field IsFinite fun(value:any):boolean
---@field IsInteger fun(value:any):boolean
---@field OwnedTypes fun(deck:ItemInstance[]):table<string,boolean>
---@field DraftEligible fun(def:ItemDef?,owned:table<string,boolean>):boolean

---@param Game table
---@param helpers GamePersistenceHelpers
---@return fun(self:BottleGame):BottleSnapshot snapshotImpl
---@return fun(snapshot:BottleSnapshot):BottleGame restoreImpl
function GamePersistence.Install(Game, helpers)
    local Copy = assert(helpers.Copy)
    local IsFinite = assert(helpers.IsFinite)
    local IsInteger = assert(helpers.IsInteger)
    local OwnedTypes = assert(helpers.OwnedTypes)
    local DraftEligible = assert(helpers.DraftEligible)

    -- 只迁移游戏生成的完整结果句式；未知自定义文本保持原样。
    ---@param text string
    ---@return string
    local function RoundLastResult(text)
        local round, income, suffix = text:match("^第(%d+)回合获得([%+%-%.%deE]+)金币(.*)$")
        local amount = income and tonumber(income)
        if not round or not amount or not suffix or not IsFinite(amount) then return text end
        if suffix ~= "" then
            local balance, target = suffix:match("^，余额([%+%-%.%deE]+)未达到考核目标([%+%-%.%deE]+)$")
            if balance then
                local balanceValue, targetValue = tonumber(balance), tonumber(target)
                if not balanceValue or not targetValue or not IsFinite(balanceValue)
                    or not IsFinite(targetValue) then return text end
                if Money.Round(balanceValue) >= Money.Round(targetValue) then
                    -- 旧档失败结果不重新判关；向上取整跨过阈值时避免出现“40未达到40”。
                    suffix = "，考核未通过，考核目标" .. Money.Format(targetValue)
                else
                    suffix = "，余额" .. Money.Format(balanceValue) .. "未达到考核目标" .. Money.Format(targetValue)
                end
            else
                local paid, nextTarget = suffix:match("^，考核达标扣除([%+%-%.%deE]+)，下一目标([%+%-%.%deE]+)$")
                local paidValue, nextValue = tonumber(paid), tonumber(nextTarget)
                if not paidValue or not nextValue or not IsFinite(paidValue)
                    or not IsFinite(nextValue) then return text end
                suffix = "，考核达标扣除" .. Money.Format(paidValue) .. "，下一目标" .. Money.Format(nextValue)
            end
        end
        return "第" .. round .. "回合获得" .. Money.Format(amount) .. "金币" .. suffix
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

    --- 扩展实例字段只读取永久白名单；临时字段不得携带半回合状态。
    ---@param saved table
    ---@param item ItemInstance
    local function ReadExpansionItem(saved, item)
        assert(saved.valueBase == nil or IsFinite(saved.valueBase), "无效基础价值覆盖")
        assert(saved.eventMult == nil or (IsFinite(saved.eventMult) and saved.eventMult == 1),
            "可持久化阶段残留事件倍率")
        assert(saved.generatedTemporary == nil or saved.generatedTemporary == false,
            "可持久化阶段残留临时生成物")
        assert(saved.shielded == nil or saved.shielded == false, "可持久化阶段残留护盾")
        local refreshCount = saved.refreshCount == nil and 0 or saved.refreshCount
        local woolCount = saved.woolCount == nil and 0 or saved.woolCount
        assert(IsInteger(woolCount) and woolCount >= 0 and woolCount <= MAX_COUNTER, "无效羊毛库存")
        assert(saved.woolExtraEntry == nil or type(saved.woolExtraEntry) == "boolean", "无效羊毛额外入场标记")
        assert(saved.woolReadyRound == nil or (IsInteger(saved.woolReadyRound)
            and saved.woolReadyRound >= 1 and saved.woolReadyRound <= MAX_COUNTER), "无效羊毛可入场回合")
        assert(IsInteger(refreshCount) and refreshCount >= 0 and refreshCount <= 4,
            "无效养鸡人刷新计数")
        if item.id == "bodyguard" then
            assert(item.counter <= 3, "无效保镖保护计数")
        end
        -- 扩展运行态只接受 ResetRound 清理后的缺省/零值，不把额外表导入实例。
        for _, key in ipairs({"abacusMerges", "calfDashRemaining", "discusWait", "compassProgress",
            "ghostTravel", "spinProgress", "geckoContactTime", "cactusBonus", "jackpotBonus",
            "rotationProgress", "gearPlayback"}) do
            -- 原生运行时的NaN与整数零比较可能误判，必须先验证有限数再接受零值。
            assert(saved[key] == nil or (IsFinite(saved[key]) and saved[key] == 0),
                "可持久化阶段残留扩展状态: " .. key)
        end
        assert(saved.anchored == nil or saved.anchored == false, "可持久化阶段残留锚定状态")
        for _, key in ipairs({"pendingConsumerUid", "calfDashHits", "discusOwnerUid", "discusTargetUid",
            "discusHolderUid", "discusState", "compassAngle", "compassTravel", "compassForced", "cactusScale",
            "spinTravel", "spinAngle", "spinForced", "rotationSamples", "gearBatch"}) do
            assert(saved[key] == nil, "可持久化阶段残留扩展状态: " .. key)
        end
        item.valueBase = saved.valueBase
        item.eventMult = 1
        item.generatedTemporary = false
        item.shielded, item.anchored = false, false
        item.abacusMerges, item.calfDashRemaining = 0, 0
        item.discusWait, item.compassProgress = 0, 0
        item.ghostTravel, item.spinProgress, item.geckoContactTime = 0, 0, 0
        item.cactusBonus, item.jackpotBonus = 0, 0
        item.rotationProgress, item.gearPlayback = 0, 0
        item.refreshCount = math.floor(refreshCount)
        item.woolCount, item.woolExtraEntry = math.floor(woolCount), saved.woolExtraEntry
        item.woolReadyRound = saved.woolReadyRound
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
            version = 2, rulesVersion = RULES_VERSION,
            phase = self.phase, round = self.round, stage = self.stage,
            score = self.score, totalScore = self.totalScore, roundScore = self.roundScore,
            elapsed = self.elapsed, target = self.target,
            bestRound = self.bestRound, bestRoundScore = self.bestRoundScore,
            lastRoundScore = self.lastRoundScore, lastResult = self.lastResult,
            drawn = Copy(self.drawn), options = Copy(self.options),
            rerollUsed = self.rerollUsed, refreshUsed = self.refreshUsed, refreshes = self.refreshes,
            relicRefreshes = self.relicRefreshes, removals = self.removals,
            revision = self.revision, rngState = self._rngState, nextUid = self._nextUid,
            instances = Copy(self:AllInstances()), deck = deck, discard = discard,
            relics = Copy(self.relics), relicDraft = self.relicDraft,
            pendingRelicDraft = self.pendingRelicDraft,
            juicerValue = self.juicerValue, huntTargetUid = self.huntTargetUid,
        }
    end

    ---@param snapshot BottleSnapshot
    ---@return BottleGame
    function Game.Restore(snapshot)
        assert(type(snapshot) == "table" and getmetatable(snapshot) == nil and snapshot.version == 2,
            "存档版本不兼容（V0.3 新表需要 version=2；旧档作废）")
        local legacyPre7 = snapshot.rulesVersion == nil or snapshot.rulesVersion == 5 or snapshot.rulesVersion == 6
        assert(legacyPre7 or snapshot.rulesVersion == 7 or snapshot.rulesVersion == RULES_VERSION,
            "存档规则版本不兼容")
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
        local refreshes = snapshot.refreshes
        if refreshes == nil then
            assert(snapshot.rulesVersion == nil, "新规则存档缺少刷新次数")
            -- 旧档只迁移当前可用的一次，不按已完成回合追溯补发。
            local used = (snapshot.phase == "prepare" and snapshot.rerollUsed)
                or (snapshot.phase == "draft" and snapshot.refreshUsed)
            refreshes = used and 0 or 1
        end
        assert(IsInteger(refreshes) and refreshes >= 0, "无效刷新次数")
        local inRelicDraft = snapshot.phase == "draft" and snapshot.relicDraft == true
        local relicRefreshes = snapshot.relicRefreshes
        if relicRefreshes == nil then
            assert(snapshot.rulesVersion ~= RULES_VERSION, "新规则存档缺少遗物刷新次数")
            -- 旧档只迁移当前遗物环节尚未用过的一次，避免重读重复发放。
            relicRefreshes = inRelicDraft and not snapshot.refreshUsed and 1 or 0
        end
        assert(IsInteger(relicRefreshes) and relicRefreshes >= 0 and relicRefreshes <= 1,
            "无效遗物刷新次数")
        assert(relicRefreshes == (inRelicDraft and not snapshot.refreshUsed and 1 or 0),
            "遗物刷新次数与阶段或已用状态不一致")
        local removals = snapshot.removals
        if removals == nil then
            assert(legacyPre7, "新规则存档缺少移除次数")
            -- nil/5/6旧档仅补0，不按旧考核回合追溯补发。
            removals = 0
        end
        assert(IsInteger(removals) and removals >= 0, "无效移除次数")
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
        ---@type BottleGame
        local self = setmetatable({}, Game)
        self:_Init(1) -- 只初始化字段，不抽取，不消耗随机状态。
        self.phase, self.round, self.stage = snapshot.phase, math.floor(snapshot.round), math.floor(snapshot.stage)
        -- 先保留原值完成全部严格校验，末尾才迁移合法存档的金额字段。
        self.score, self.totalScore, self.roundScore = snapshot.score, snapshot.totalScore, snapshot.roundScore
        self.elapsed, self.target = snapshot.elapsed, snapshot.target
        self.bestRound, self.bestRoundScore = snapshot.bestRound, snapshot.bestRoundScore
        self.lastRoundScore, self.lastResult = snapshot.lastRoundScore, snapshot.lastResult
        self.rerollUsed, self.refreshUsed, self.revision = snapshot.rerollUsed, snapshot.refreshUsed, snapshot.revision
        self.refreshes = math.floor(refreshes)
        self.relicRefreshes = math.floor(relicRefreshes)
        self.removals = math.floor(removals)
        self.spawnQueue = {} -- 队列属运行态；永远不从存档导入。
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
            -- 体积/重量按可信定义严格校验；旧 version=2 缺省为100%。
            local savedScale, savedWeight = PhysicalState.Read(saved.id, saved)
            local savedCounter = saved.counter == nil and 0 or saved.counter
            local savedSettleCount = saved.settleCount == nil and 0 or saved.settleCount
            assert(IsInteger(savedCounter) and savedCounter >= 0, "无效计数器")
            assert(IsInteger(savedSettleCount) and savedSettleCount >= 0, "无效结算计数")
            assert(saved.location == "deck" or (self.phase == "prepare" and saved.location == "bottle")
                or (self.phase ~= "prepare" and saved.location == "discard"), "可持久化阶段实例位置不合法")
            local permMult, tokenAttempted = RelicState.ReadItem(saved)
            -- 白名单字段拷贝：不把损坏存档的额外 table/function 导入运行状态。
            ---@type ItemInstance
            local item = {
                uid = math.floor(saved.uid), id = saved.id, bonus = 0, permBonus = saved.permBonus,
                mult = 1, remaining = saved.remaining, bottleRounds = math.floor(saved.bottleRounds),
                location = saved.location, temporary = false,
                scale = savedScale, weight = savedWeight, counter = savedCounter, settleCount = savedSettleCount,
                distance = 0, permMult = permMult, tokenAttempted = tokenAttempted,
            }
            ReadExpansionItem(saved, item)
            -- 旧果汁的累计价值存于 permBonus，不能因定义基础0→3而多出3点。
            if snapshot.rulesVersion == nil and saved.id == "juice" then item.valueBase = 0 end
            self._instances[saved.uid] = item
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
            ---@type ItemInstance
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
            ---@type ItemInstance
            local item = assert(self:Get(uid), "抽取实例不存在")
            assert(not drawnSeen[uid] and item.location == "bottle", "抽取实例重复或不在瓶中")
            drawnSeen[uid] = true
            self.drawn[#self.drawn + 1] = uid
        end
        local bottleCount = 0
        for _, item in ipairs(self.deck) do
            if item.woolExtraEntry then
                assert(self.phase == "prepare" and item.id == "wool"
                    and (item.location == "deck" or item.location == "bottle")
                    -- 此处校验原始羊毛价值，不能让向上取整把损坏的0.x放行为1。
                    and ((item.valueBase or Items.byId.wool.base) + item.permBonus) * item.permMult == 1
                    and not drawnSeen[item.uid]
                    and (item.woolReadyRound == nil or item.woolReadyRound <= self.round),
                    "无效羊毛额外入场状态")
            end
            assert(item.location ~= "bottle" or drawnSeen[item.uid] or item.woolExtraEntry,
                "瓶中实例未列入抽取列表")
            if item.location == "bottle" then bottleCount = bottleCount + 1 end
        end
        for _, item in ipairs(self.discard) do
            assert(not item.woolExtraEntry, "弃牌不能保留羊毛额外入场标记")
        end
        assert(bottleCount <= Items.Settings.bottleLimit, "瓶中物品超过上限")
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
            local definition = self.relicDraft and Relics.byId[id] or Items.byId[id]
            local excludedCommon = not self.relicDraft and self.round % 5 == 0 and definition.rarity == 1
            if excludedCommon then
                -- nil/5/6旧档先完整校验，再只过滤考核普通物品；遗物原样保留，不重抽。
                assert(legacyPre7, "考核三选一不能包含普通品质")
            else
                self.options[#self.options + 1] = id
            end
        end
        RelicState.ValidateTarget(self)
        -- 旧账户金额向上取整；实例保留原始因子，在完整有效价值计算后统一取整。
        self.score, self.totalScore, self.roundScore = Money.Round(self.score), Money.Round(self.totalScore),
            Money.Round(self.roundScore)
        self.bestRoundScore, self.lastRoundScore = Money.Round(self.bestRoundScore), Money.Round(self.lastRoundScore)
        self.lastResult = RoundLastResult(self.lastResult)
        return self
    end
    return Game.Snapshot, Game.Restore
end

return GamePersistence
