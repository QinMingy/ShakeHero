-- 引导状态和真实对局快照的恢复边界回归；不创建窗口、不读写玩家文件。
local TutorialState = require("Bottle.TutorialState")
local Game = require("Bottle.Game")
local Tests = {}

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name = name, run = run} end

---@param game BottleGame
---@return BottleTutorialState
local function AtShakeIntro(game)
    local state = TutorialState.Begin(TutorialState.New(false), game)
    state = TutorialState.Advance(state, "continue", game)
    state = TutorialState.Advance(state, "continue", game)
    return TutorialState.Advance(state, "start", game)
end

Test("首次玩家只在开始游戏激活，启动页存档不误判旧玩家", function()
    local game = Game.New(1)
    local fresh = TutorialState.New(false)
    local saved = TutorialState.ForSnapshot(fresh, game:Snapshot())
    assert(saved.status == "new" and fresh.status == "new")
    local loaded = TutorialState.FromSaved(saved, true)
    assert(loaded.status == "new")
    assert(TutorialState.Begin(loaded, game).status == "active")
    assert(TutorialState.Begin(loaded, {phase = "draft", round = 1}).status == "new")
end)

Test("无标记旧存档与导入存档均不强制教程", function()
    local game = Game.New(1)
    for _, value in ipairs({false, {version = 0}, {version = 1, status = "bad"}}) do
        local legacy = TutorialState.FromSaved(value, true)
        assert(legacy.status == "legacy" and legacy.examSeen and legacy.relicSeen)
        assert(TutorialState.Begin(legacy, game).status == "legacy")
    end
    assert(TutorialState.MarkImported(TutorialState.New(false)).status == "legacy")
    assert(TutorialState.MarkImported(AtShakeIntro(game)).status == "legacy")
end)

Test("严格动作推进且所有转换保持输入对象不变", function()
    local game = Game.New(1)
    local welcome = TutorialState.Begin(TutorialState.New(false), game)
    local nextState = TutorialState.Advance(welcome, "continue", game)
    assert(welcome.step == "welcome" and nextState.step == "goal")
    assert(TutorialState.Advance(welcome, "chosen", game).step == "welcome")
    local intro = AtShakeIntro(game)
    assert(intro.step == "shakeIntro")
    assert(TutorialState.Advance(intro, "continue", game).step == "shakeIntro")
    assert(TutorialState.Advance(intro, "started", game).step == "shakeIntro")
    assert(game:Start())
    assert(TutorialState.Advance(intro, "started", game).step == "running")
    assert(intro.step == "shakeIntro")
end)

Test("运行结算展示退出都随同回合前快照恢复摇晃说明", function()
    local game = Game.New(2)
    local state = AtShakeIntro(game)
    assert(game:Start())
    state = TutorialState.Advance(state, "started", game)
    for _, phase in ipairs({"running", "settle", "reveal"}) do
        if phase == "settle" then game:Step(10)
        elseif phase == "reveal" then game:Finish() end
        assert(game.phase == phase)
        local snapshot = game:Snapshot()
        assert(snapshot.phase == "prepare")
        local saved = TutorialState.ForSnapshot(state, snapshot)
        assert(saved.step == "shakeIntro" and state.step == "running")
        assert(TutorialState.Begin(saved, Game.Restore(snapshot)).step == "shakeIntro")
    end
end)

Test("正在运行的内存状态不因规范化重新打开教程", function()
    local game = Game.New(3)
    local state = AtShakeIntro(game)
    assert(game:Start())
    state = TutorialState.Advance(state, "started", game)
    assert(TutorialState.Reconcile(state, game).step == "running")
    assert(TutorialState.Begin(state, game).step == "running")
end)

Test("切换候选后可继续查看，下一步讲刷新再实际刷新确认物品", function()
    local game = Game.New(4)
    local state = AtShakeIntro(game)
    assert(game:Start())
    state = TutorialState.Advance(state, "started", game)
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "draft")
    state = TutorialState.Advance(state, "settled", game)
    assert(state.step == "result")
    assert(TutorialState.ForSnapshot(state, game:Snapshot()).step == "result")
    state = TutorialState.Advance(state, "continue", game)
    assert(state.step == "choose")
    assert(TutorialState.ForSnapshot(state, game:Snapshot()).step == "choose")
    assert(TutorialState.Advance(state, "chosen", game).step == "choose")
    assert(TutorialState.Advance(state, "continue", game).step == "choose")
    -- 候选切换是界面状态，不会领取物品或改变对局候选。
    assert(#game.options >= 2)
    local first, second = game.options[1], game.options[2]
    local selected, deckCount, refreshes = 1, #game.deck, game.refreshes
    selected = 2
    assert(selected == 2 and game.options[selected] ~= first)
    state = TutorialState.Advance(state, "switched", game)
    assert(state.step == "review" and #game.deck == deckCount and game.refreshes == refreshes)
    selected = 1
    state = TutorialState.Advance(state, "switched", game)
    assert(state.step == "review" and game.options[selected] == first)
    assert(TutorialState.ForSnapshot(state, game:Snapshot()).step == "review")
    state = TutorialState.Advance(state, "continue", game)
    assert(state.step == "refresh" and #game.deck == deckCount and game.refreshes == refreshes)
    assert(game.options[1] == first and game.options[2] == second)
    assert(TutorialState.ForSnapshot(state, game:Snapshot()).step == "refresh")
    state = TutorialState.Advance(state, "continue", game)
    assert(state.step == "reroll")
    assert(TutorialState.Advance(state, "continue", game).step == "reroll")
    assert(TutorialState.Advance(state, "chosen", game).step == "reroll")
    assert(game:DraftRefresh() and game.refreshes == refreshes - 1)
    state = TutorialState.Advance(state, "refreshed", game)
    assert(state.step == "confirm")
    assert(TutorialState.ForSnapshot(state, game:Snapshot()).step == "confirm")
    assert(game:Choose(1) and game.round == 2 and game.phase == "prepare")
    state = TutorialState.Advance(state, "chosen", game)
    assert(state.step == "finish" and TutorialState.ForSnapshot(state, game:Snapshot()).step == "finish")
    assert(#game.deck == deckCount + 1 and game.refreshes == refreshes - 1)
    state = TutorialState.Advance(state, "continue", game)
    assert(state.status == "complete" and state.step == "complete")
    assert(TutorialState.Begin(state, Game.New(5)).status == "complete")
end)

Test("未完成重开从欢迎恢复，跨节点状态不锁死三选一", function()
    local game = Game.New(6)
    local state = TutorialState.Begin(TutorialState.New(false), game)
    state.step = "finish"
    assert(TutorialState.Reconcile(state, game).step == "welcome")
    state.step = "choose"
    assert(TutorialState.Reconcile(state, game).step == "shakeIntro")
    state.step = "running"
    assert(TutorialState.Reconcile(state, {phase = "draft", round = 1}).step == "result")
    assert(TutorialState.Reconcile(state, {phase = "prepare", round = 2}).step == "finish")
end)

Test("三选一各教学断点恢复不重扣刷新或提前领取物品", function()
    local game = Game.New(8)
    assert(game:Start())
    game:Finish()
    game:RevealStep(100)
    assert(game.phase == "draft")
    local deckCount, refreshes = #game.deck, game.refreshes
    for _, step in ipairs({"result", "choose", "review", "refresh", "reroll"}) do
        local state = TutorialState.FromSaved({version = 1, status = "active", step = step}, true)
        local snapshot = game:Snapshot()
        local saved = TutorialState.ForSnapshot(state, snapshot)
        local restored = Game.Restore(snapshot)
        assert(TutorialState.Begin(saved, restored).step == step)
        assert(restored.refreshes == refreshes and #restored.deck == deckCount)
    end
    assert(game:DraftRefresh())
    local confirm = TutorialState.FromSaved({version = 1, status = "active", step = "confirm"}, true)
    local snapshot = game:Snapshot()
    local restored = Game.Restore(snapshot)
    assert(TutorialState.Begin(TutorialState.ForSnapshot(confirm, snapshot), restored).step == "confirm")
    assert(restored.refreshes == refreshes - 1 and #restored.deck == deckCount)
    assert(restored:Choose(2))
    local finish = TutorialState.Advance(confirm, "chosen", restored)
    assert(finish.step == "finish" and #restored.deck == deckCount + 1)
    assert(TutorialState.Begin(TutorialState.ForSnapshot(finish, restored:Snapshot()), restored).step == "finish")
end)

Test("prepare回滚与旧版第二回合引导迁移不会返回候选", function()
    for _, step in ipairs({"running", "result", "choose", "review", "refresh", "reroll", "confirm"}) do
        local state = TutorialState.FromSaved({version = 1, status = "active", step = step}, true)
        assert(TutorialState.Reconcile(state, {phase = "prepare", round = 1}).step == "shakeIntro")
    end
    for _, step in ipairs({"welcome", "goal", "start", "shakeIntro", "running", "result",
        "choose", "review", "refresh", "reroll", "confirm", "finish"}) do
        local state = TutorialState.FromSaved({version = 1, status = "active", step = step}, true)
        local restored = TutorialState.Reconcile(state, {phase = "prepare", round = 2})
        assert(restored.step == "finish" and restored.status == "active")
        assert(TutorialState.Advance(restored, "continue", {phase = "prepare", round = 2}).status == "complete")
    end
end)

Test("切换刷新确认事件受阶段约束且不能直接跳过候选教学", function()
    local choose = TutorialState.FromSaved({version = 1, status = "active", step = "choose"}, true)
    assert(TutorialState.Advance(choose, "chosen", {phase = "prepare", round = 2}).step == "choose")
    assert(TutorialState.Advance(choose, "switched", {phase = "prepare", round = 1}).step == "choose")
    assert(TutorialState.Advance(choose, "refreshed", {phase = "draft", round = 1}).step == "choose")
    local review = TutorialState.Advance(choose, "switched", {phase = "draft", round = 1})
    assert(review.step == "review")
    assert(TutorialState.Advance(review, "continue", {phase = "prepare", round = 1}).step == "review")
    assert(TutorialState.Advance(review, "chosen", {phase = "prepare", round = 2}).step == "review")
    local refresh = TutorialState.Advance(review, "continue", {phase = "draft", round = 1})
    assert(TutorialState.Advance(refresh, "continue", {phase = "prepare", round = 1}).step == "refresh")
    local reroll = TutorialState.Advance(refresh, "continue", {phase = "draft", round = 1})
    assert(TutorialState.Advance(reroll, "refreshed", {phase = "running", round = 1}).step == "reroll")
    local confirm = TutorialState.Advance(reroll, "refreshed", {phase = "draft", round = 1})
    assert(TutorialState.Advance(confirm, "continue", {phase = "draft", round = 1}).step == "confirm")
    assert(TutorialState.Advance(confirm, "chosen", {phase = "draft", round = 1}).step == "confirm")
    assert(TutorialState.Advance(confirm, "chosen", {phase = "prepare", round = 1}).step == "confirm")
end)

Test("候选查看节点反复切换保持断点并需下一步推进", function()
    local game = Game.New(9)
    assert(game:Start())
    game:Finish()
    game:RevealStep(100)
    local choose = TutorialState.FromSaved({version = 1, status = "active", step = "choose"}, true)
    assert(TutorialState.Advance(choose, "continue", game).step == "choose")
    local review = TutorialState.Advance(choose, "switched", game)
    local count, refreshes = #game.deck, game.refreshes
    for _ = 1, 3 do
        local nextState = TutorialState.Advance(review, "switched", game)
        assert(nextState ~= review and nextState.step == "review")
        review = nextState
    end
    local snapshot = game:Snapshot()
    local restored = Game.Restore(snapshot)
    local saved = TutorialState.FromSaved(TutorialState.ForSnapshot(review, snapshot), true)
    assert(saved.step == "review" and TutorialState.Begin(saved, restored).step == "review")
    assert(#restored.deck == count and restored.refreshes == refreshes)
    assert(TutorialState.Advance(saved, "continue", restored).step == "refresh")
    assert(saved.step == "review" and choose.step == "choose")
end)

Test("完成标记不会被导入或新局清除，补充提示独立只记一次", function()
    local state = TutorialState.FromSaved({version = 1, status = "complete"}, true)
    assert(not state.examSeen and not state.relicSeen)
    assert(TutorialState.MarkImported(state).status == "complete")
    local seen = TutorialState.MarkSeen(state, "exam")
    assert(seen.examSeen and not seen.relicSeen and not state.examSeen)
    seen = TutorialState.MarkSeen(seen, "relic")
    assert(seen.examSeen and seen.relicSeen)
    assert(TutorialState.Reconcile(seen, Game.New(7)).status == "complete")
end)

Test("旧玩家及已完成玩家不因新增候选刷新事件重新激活", function()
    for _, status in ipairs({"legacy", "complete"}) do
        local state = TutorialState.FromSaved({version = 1, status = status}, true)
        for _, event in ipairs({"continue", "switched", "refreshed", "chosen"}) do
            assert(TutorialState.Advance(state, event, {phase = "draft", round = 1}).status == status)
        end
        assert(TutorialState.Reconcile(state, {phase = "prepare", round = 2}).status == status)
    end
end)

Test("反序列化仅保留已知字段且损坏步骤从欢迎修复", function()
    local state = TutorialState.FromSaved({version = 1, status = "active", step = "bad",
        examSeen = "true", relicSeen = true, arbitrary = {}}, true)
    assert(state.step == "welcome" and not state.examSeen and state.relicSeen)
    assert((state --[[@as any]]).arbitrary == nil)
end)

---@return integer
function Tests.Run()
    local passed = 0
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.TutorialStateTests [" .. case.name .. "] " .. tostring(err))
        passed = passed + 1
    end
    return passed
end

return Tests
