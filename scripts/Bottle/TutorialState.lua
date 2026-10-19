-- 新手引导的纯状态机。玩家标记独立于单局，但与对局快照写入同一个存档槽。
local TutorialState = {}

---@class BottleTutorialState
---@field version integer
---@field status 'new'|'active'|'complete'|'legacy'
---@field step string
---@field examSeen boolean
---@field relicSeen boolean

local STEPS = {
    welcome = true, goal = true, start = true, inspectBall = true, ballEffect = true, shakeIntro = true,
    running = true, result = true, choose = true, review = true, refresh = true,
    reroll = true, confirm = true, finish = true,
}

---@param existingSave boolean?
---@return BottleTutorialState
function TutorialState.New(existingSave)
    return {
        version = 1, status = existingSave and "legacy" or "new", step = "welcome",
        examSeen = existingSave == true, relicSeen = existingSave == true,
    }
end

--- 只接受已知字段；旧存档没有引导标记时不强制启动新手教程。
---@param value any
---@param existingSave boolean?
---@return BottleTutorialState
function TutorialState.FromSaved(value, existingSave)
    if type(value) ~= "table" or value.version ~= 1 then return TutorialState.New(existingSave) end
    local status = value.status
    if status ~= "new" and status ~= "active" and status ~= "complete" and status ~= "legacy" then
        return TutorialState.New(existingSave)
    end
    local state = TutorialState.New(status == "legacy")
    state.status = status
    state.step = status == "complete" and "complete" or (STEPS[value.step] and value.step or "welcome")
    state.examSeen = status == "legacy" or value.examSeen == true
    state.relicSeen = status == "legacy" or value.relicSeen == true
    return state
end

--- 对齐可恢复的对局节点。实际摇晃中的 game 不回退；prepare 快照才回到摇晃讲解。
---@param value any
---@param game table?
---@return BottleTutorialState
function TutorialState.Reconcile(value, game)
    local state = TutorialState.FromSaved(value, false)
    if state.status ~= "active" or type(game) ~= "table" then return state end
    local round = tonumber(game.round) or 1
    if round >= 2 then
        -- 第二回合说明物品已经选定；旧版 refresh 也不重新发候选或要求再刷新。
        state.step = "finish"
    elseif game.phase == "prepare" then
        if state.step == "running" or state.step == "result" or state.step == "choose" or state.step == "review"
            or state.step == "refresh" or state.step == "reroll" or state.step == "confirm" then
            state.step = "shakeIntro"
        elseif state.step == "finish" then
            -- 引导未完成又重新开了一局：从欢迎开始，不把第二回合讲解套在第一回合。
            state.step = "welcome"
        end
    elseif game.phase == "draft" then
        if state.step ~= "result" and state.step ~= "choose" and state.step ~= "review" and state.step ~= "refresh"
            and state.step ~= "reroll" and state.step ~= "confirm" then state.step = "result" end
    end
    return state
end

--- 玩家第一次真正进入游戏才激活；启动页上的预先存档仍保留 new。
---@param value any
---@param game table?
---@return BottleTutorialState
function TutorialState.Begin(value, game)
    local state = TutorialState.Reconcile(value, game)
    if state.status == "new" and type(game) == "table" and game.phase == "prepare" and game.round == 1 then
        state.status, state.step = "active", "welcome"
    end
    return state
end

--- 事件必须来自相应动作成功后的游戏状态，不能靠重复点击越过操作步骤。
---@param value any
---@param event string
---@param game table?
---@return BottleTutorialState
function TutorialState.Advance(value, event, game)
    local state = TutorialState.FromSaved(value, false)
    if state.status ~= "active" then return state end
    local phase = type(game) == "table" and game.phase or nil
    if event == "continue" then
        if state.step == "welcome" then state.step = "goal"
        elseif state.step == "goal" then state.step = "start"
        elseif state.step == "ballEffect" and phase == "prepare" then state.step = "shakeIntro"
        elseif state.step == "result" and phase == "draft" then state.step = "choose"
        elseif state.step == "review" and phase == "draft" then state.step = "refresh"
        elseif state.step == "refresh" and phase == "draft" then state.step = "reroll"
        elseif state.step == "finish" then state.status, state.step = "complete", "complete"
        end
    elseif event == "start" and state.step == "start" and phase == "prepare" then
        state.step = "inspectBall"
    elseif event == "inspectedItem" and state.step == "inspectBall" and phase == "prepare" then
        state.step = "ballEffect"
    elseif event == "started" and state.step == "shakeIntro" and phase == "running" then
        state.step = "running"
    elseif event == "settled" and state.step == "running" and phase == "draft" then
        state.step = "result"
    elseif event == "switched" and state.step == "choose" and phase == "draft" then
        state.step = "review"
    elseif event == "refreshed" and state.step == "reroll" and phase == "draft" then
        state.step = "confirm"
    elseif event == "chosen" and state.step == "confirm" and phase == "prepare"
        and type(game.round) == "number" and game.round >= 2 then
        state.step = "finish"
    end
    return state
end

---@param value any
---@param snapshot table
---@return BottleTutorialState
function TutorialState.ForSnapshot(value, snapshot)
    return TutorialState.Reconcile(value, snapshot)
end

--- 存档码只导入对局，不重新激活本地玩家的引导，也不能覆盖完成标记。
---@param value any
---@return BottleTutorialState
function TutorialState.MarkImported(value)
    local state = TutorialState.FromSaved(value, false)
    if state.status == "complete" or state.status == "legacy" then return state end
    return TutorialState.New(true)
end

---@param value any
---@param kind 'exam'|'relic'
---@return BottleTutorialState
function TutorialState.MarkSeen(value, kind)
    local state = TutorialState.FromSaved(value, false)
    if state.status == "legacy" or state.status == "new" then return state end
    if kind == "exam" then state.examSeen = true
    elseif kind == "relic" then state.relicSeen = true end
    return state
end

return TutorialState
