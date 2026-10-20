-- 物品语义音效的有界调度：同帧同类合并、跨帧短窗限流，丢弃的声音不补播。
-- 只读玩法事件，不使用玩法随机数，也不更改事件或实例。
local ConsumeStyles = require("Bottle.ConsumeStyles")
local FrameBudget = require("Bottle.FrameBudget")
---@class BottleItemSoundProfile
---@field file string
---@field priority number
---@field gap number
---@field gain number
---@field duration number

---@class BottleItemSoundVoice
---@field untilTime number
---@field priority number

---@class BottleItemSoundPlay
---@field action string
---@field slot number
---@field gain number

---@class BottleItemSoundState
---@field time number
---@field pending table<string,boolean>
---@field last table<string,number>
---@field starts number[]
---@field voices BottleItemSoundVoice[]
---@field durations table<string,number>
---@field enabled table<string,boolean>
local State = {}
State.__index = State
State.POOL_SIZE = 3
State.PER_FRAME = 2
State.WINDOW = .12
State.PER_WINDOW = 3

---@type table<string,BottleItemSoundProfile>
State.profiles = {
    killer = {file="item_killer_play.wav", priority=8, gap=.14, gain=.31, duration=.24},
    grow = {file="item_grow_play.wav", priority=7, gap=.22, gain=.24, duration=.38},
    merge = {file="item_merge_play.wav", priority=6, gap=.10, gain=.34, duration=.56},
    cut = {file="item_cut_play.wav", priority=5, gap=.12, gain=.32, duration=.43},
    steal = {file="item_steal_thin_play.wav", priority=4, gap=.45, gain=.30, duration=.26},
    jelly = {file="item_jelly_play.wav", priority=3, gap=.14, gain=.29, duration=.44},
    eat = {file="item_eat_play.wav", priority=2, gap=.20, gain=.29, duration=.40},
    produce = {file="item_produce_play.wav", priority=2, gap=.12, gain=.28, duration=.35},
}
local ORDER = {"killer", "grow", "merge", "cut", "steal", "jelly", "eat", "produce"}

-- 小牛每次成功消费会启动冲刺，Audio.Calf已播专属牛叫，不再叠默认咀嚼声。
local VOICED_EATERS = {calf=true}

---@return BottleItemSoundState
function State.New()
    local self = setmetatable({}, State)
    self:Reset()
    return self
end

function State:Reset()
    self.time, self.pending, self.last, self.starts = 0, {}, {}, {}
    self.voices, self.durations, self.enabled = {}, {}, {}
    for index = 1, State.POOL_SIZE do self.voices[index] = {untilTime=0, priority=0} end
    for action, profile in pairs(State.profiles) do
        self.durations[action], self.enabled[action] = profile.duration, true
    end
end

---@param action string
---@param duration number? nil 表示资源未加载，不占用声音配额
function State:SetDuration(action, duration)
    self.enabled[action] = duration ~= nil and duration > 0
    if duration and duration > 0 then self.durations[action] = duration end
end

---@param event GameEvent
---@return string?
function State.Action(event)
    -- 全部成功合成共用现有音效；材料consume不单独播放，避免双材料叠三声。
    if event.kind == "merge" then return "merge" end
    if event.kind == "consume" and event.reason == "eliminate" and event.consumerId == "killer" then
        return "killer"
    end
    if event.kind == "consume" and ConsumeStyles.Resolve(event) == "eat"
        and not VOICED_EATERS[event.consumerId] then return "eat" end
    if event.kind ~= "itemFeedback" then return nil end
    local action = event.action
    if not action or not State.profiles[action] or action == "killer" or action == "merge"
        or action == "eat" then return nil end
    -- 偷到实际价值才偷笑；受遗物影响变为赠送的正收益不能误报为偷窃。
    if action == "steal" and not ((event.value or 0) < 0) then return nil end
    if action == "produce" and (event.count or 1) <= 0 then return nil end
    return action
end

---@param events GameEvent[]
function State:Collect(events)
    local pending = {}
    for _, event in ipairs(events) do
        FrameBudget.Checkpoint()
        local action = State.Action(event)
        if action then pending[action] = true end
    end
    -- 分片期间Audio.Update仍可播放旧批，只有完整收集后才发布本批声音。
    for action in pairs(pending) do self.pending[action] = true end
end

---@param dt number
function State:Advance(dt)
    self.time = self.time + math.max(0, dt)
    for index = #self.starts, 1, -1 do
        if self.time - self.starts[index] >= State.WINDOW then table.remove(self.starts, index) end
    end
end

---@param priority number
---@return number?
function State:AvailableVoice(priority)
    local weakest = 1
    for index, voice in ipairs(self.voices) do
        if voice.untilTime <= self.time then return index end
        if voice.priority < self.voices[weakest].priority then weakest = index end
    end
    -- 满池时仅允许较重要的反馈抢占；相同或较低优先级直接丢弃。
    if priority > self.voices[weakest].priority then return weakest end
    return nil
end

---@return BottleItemSoundPlay[]
function State:Flush()
    ---@type BottleItemSoundPlay[]
    local plays = {}
    for _, action in ipairs(ORDER) do
        local profile = State.profiles[action]
        local last = self.last[action]
        if self.pending[action] and self.enabled[action]
            and (not last or self.time - last >= profile.gap)
            and #plays < State.PER_FRAME and #self.starts < State.PER_WINDOW then
            local slot = self:AvailableVoice(profile.priority)
            if slot then
                self.voices[slot] = {untilTime=self.time + self.durations[action], priority=profile.priority}
                self.last[action] = self.time
                self.starts[#self.starts + 1] = self.time
                plays[#plays + 1] = {action=action, slot=slot, gain=profile.gain}
            end
        end
    end
    self.pending = {}
    return plays
end

return State
