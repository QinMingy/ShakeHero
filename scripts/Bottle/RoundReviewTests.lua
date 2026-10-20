-- 结算回看专项：执行真实规则、Board拾取与计分组件；不读写玩家存档。
local T = require("Bottle.RepairTests")
local Effects = require("Bottle.Effects")
local Board = require("Bottle.Board")
local Score = require("Bottle.RoundScore")
local SoftView = require("Bottle.SoftView")
local Game = require("Bottle.Game")
local Stage = require("Bottle.BoardEventStage")
local Budget = require("Bottle.FrameBudget")
local Audio = require("Bottle.Audio")
local Money = require("Bottle.Money")
local Tests = {}

---@param condition any
---@param message string
local function Check(condition, message) assert(condition, "[回合回看] " .. message) end

---@param board BottleBoard
---@param uid integer
local function Point(board, uid)
    local x, y, ppu = board:GetBottleTransform()
    local res = assert(board.residue[uid])
    return x + res.x * ppu, y - res.y * ppu
end
Tests.Point = Point

-- 这里只替代物理读数；命中、残留事件处理、分帧事务和UI组件均使用生产方法。
---@param game BottleGame
---@return any
---@return any
local function Fixture(game)
    local poses, bodies = {}, {}
    for index, item in ipairs(game:BottleItems()) do
        poses[item.uid] = {x=(index - 2) * .9, y=3, angle=.2, radius=.3}
        bodies[item.uid] = true
    end
    local physics = {bodies=bodies}
    function physics:GetPose(uid)
        local p = assert(poses[uid])
        return p.x, p.y, p.angle, p.radius
    end
    function physics:GetSoftPose() return nil end
    local board = Board {game=game, physics=physics, inspect=function() end, shake=function() end,
        width=370, height=458}
    board.GetAbsoluteLayout = function() return {x=0,y=0,w=370,h=458} end
    return board, poses
end
Tests.Fixture = Fixture

function Tests.Run()
    local checks = 0
    local function Case(name, work)
        work()
        checks = checks + 1
        print("[回合回看规则] PASS " .. name)
    end
    Case("结算快照保留临时与永久增益、不引用真实实例", function()
        local game = T.Fixture({"ball"})
        local item = assert(game:Get(1))
        item.bonus, item.permBonus, item.mult, item.permMult = 5, 2, 1.5, 2
        local expected, events = game:_Value(item), {}
        Effects.SettleItem(game, item, events)
        local event = assert(events[1])
        local frozen = assert(event.finalItem)
        Check(event.value == expected and frozen ~= item, "冻结的是当次单件价值")
        game:_CleanupRound()
        Check(frozen.bonus == 5 and frozen.mult == 1.5 and item.bonus == 0 and item.mult == 1,
            "清理真实实例不污染详情")
        Check(game:_Value(frozen) == expected and game:_Value(item) ~= expected, "两种价值来源分离")
    end)
    Case("樱桃额外结算保留单次价值、不是累计收益", function()
        local game = T.Fixture({"cherry"})
        local item = assert(game:Get(1))
        item.bonus = 4
        local value, events = game:_Value(item), {}
        Effects.SettleItem(game, item, events)
        Check(#events == 2 and game.roundScore == 2 * value, "仍按原规则结算两次")
        Check(events[1].value == value and events[2].finalItem == events[1].finalItem, "共用同一只读快照")
    end)
    Case("信用卡详情值早于尾声永久减值", function()
        local game = T.Fixture({"credit_card"})
        local item, events = assert(game:Get(1)), {}
        local value = game:_Value(item)
        Effects.SettleItem(game, item, events)
        Effects.PostSettle(game, events)
        Check(game:_Value(item) == value - 1, "原尾声扣值照常")
        Check(events[1].value == value and game:_Value(assert(events[1].finalItem)) == value,
            "回看不会显示扣值后的金额")
    end)
    Case("骰子点数和0／负价值快照", function()
        for _, value in ipairs({0, -7, 19}) do
            local game = T.Fixture({"die_d6"})
            local item, events = assert(game:Get(1)), {}
            item.rollValue, item.bonus = 6, value - 6
            Effects.SettleItem(game, item, events)
            game:_CleanupRound()
            Check(events[1].value == value and assert(events[1].finalItem).rollValue == 6,
                "冻结点数与最终值")
        end
    end)
    Case("真实Finish清理后仍可捕获详情且不写入存档", function()
        local game = T.Fixture({"ball", "credit_card", "die_d6"})
        local board = Fixture(game)
        Check(game:Start(), "开始对局")
        assert(game:Get(1)).bonus = 8
        assert(game:Get(3)).rollValue = 5
        local expected = game:_Value(assert(game:Get(1)))
        local events = game:Finish()
        board:ApplyEffects(events)
        game:RevealStep(100)
        Check(board:GetRoundResidue(1).finalValue == expected, "保留结算时值")
        Check(assert(game:Get(1)).bonus == 0, "真实牌库已清理")
        for _, item in ipairs(game:Snapshot().instances) do
            local fields = item --[[@as table<string,any>]]
            Check(fields["finalItem"] == nil and fields["finalValue"] == nil, "快照不进入存档实例")
        end
        local restored = Game.Restore(game:Snapshot())
        Check(restored.lastRoundScore == game.lastRoundScore, "读档不改变本回合总分")
        board:ResetEffects()
        Check(board:GetRoundResidue(1) == nil, "重置清空回看")
        board:Destroy()
    end)
    Case("香蕉成熟后详情身份跟随残留、价值保留实际结算", function()
        local game = T.Fixture({"banana"})
        local board = Fixture(game)
        assert(game:Get(1)).bottleRounds = 2
        Check(game:Start(), "开始香蕉回合")
        local value = game:_Value(assert(game:Get(1)))
        local events = game:Finish()
        board:ApplyEffects(events)
        game:RevealStep(100)
        local residue = assert(board:GetRoundResidue(1))
        Check(residue.id == "rotten_banana" and residue.finalItem.id == residue.id, "详情与瓶内最终图案一致")
        Check(residue.finalValue == value, "不误用腐烂香蕉新基础值")
        local scored = T.Events(events, "score", 1)
        Check(assert(scored[1].finalItem).id == "banana", "表现转化不改原结算事件")
        board:Destroy()
    end)
    Case("实际残留拾取、旋转／重叠／边界与移除", function()
        local game = T.Fixture({"ball", "ball"})
        local board, poses = Fixture(game)
        poses[2].x, poses[2].y = poses[1].x, poses[1].y
        Check(game:Start(), "开始")
        local events = game:Finish()
        board:ApplyEffects(events)
        game:RevealStep(100)
        local x, y = Point(board, 1)
        Check(board:PickItem(x, y) == 2, "同位置按最后绘制的UID拾取")
        Check(board:PickItem(-1, y) == 0, "画布外不拾取")
        local bounds = board:GetItemBounds(2)
        Check(x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h,
            "详情锚点包围冻结姿态")
        assert(game:Get(2)).location = "consumed"
        Check(board:PickItem(x, y) == 1 and board:GetRoundResidue(2) == nil, "已移除不复活")
        game.phase = "reveal"
        Check(board:PickItem(x, y) == 0, "展示阶段仍禁止拾取")
        board:Destroy()
    end)
    Case("冻结培根分段拾取和包围范围", function()
        ---@type BottleSoftPose[]
        local poses = {{x=0,y=2,angle=math.pi/4,halfLength=.3,halfWidth=.1,u0=0,u1=.5},
            {x=.8,y=2,angle=0,halfLength=.3,halfWidth=.1,u0=.5,u1=1}}
        Check(SoftView.HitPose(poses, 0, 2) and SoftView.HitPose(poses, .8, 2), "各段中心命中")
        Check(not SoftView.HitPose(poses, .4, 2) and not SoftView.HitPose(poses, 0, 2.4), "缝隙和段外不命中")
        local bounds = SoftView.PoseBounds(poses, 100, 200, 50)
        Check(bounds.w > 60 and bounds.h > 25, "冻结包围范围包含弯折段")
    end)
    Case("0／负／正回合小计在draft持续显示且不触发转账", function()
        local score = Score.New()
        for _, value in ipairs({0, -7, 1234}) do
            score:Sync("reveal", value, 0, 0)
            Check(score:Sync("draft", value, 0, 0) == nil, "进入draft不发起转账")
            for _ = 1, 10 do score:Update(.1, 370) end
            Check(score.shakeRoot:IsVisible() and not score.root:IsVisible(), "只显示左上小计")
            Check(score.shakeNumber:GetText() == "×" .. Money.Format(value), "小计真实最终值")
            Check(not score:StepTransfer(10, true), "draft不会重复发币")
        end
        score:Sync("prepare", 0, 0, 0)
        Check(not score.shakeRoot:IsVisible(), "下一回合不残留小计")
        score.shakeRoot:Destroy(); score.root:Destroy()
    end)
    Case("壁虎多次结算与考核扣款不改变回看口径", function()
        local game = T.Fixture({"gecko", "gecko"})
        local events = {}
        local first = assert(game:Get(1))
        first.bonus = 3
        local value = game:_Value(first)
        Effects.SettleItem(game, first, events, nil,
            {pairs={{1,2}},rawPairs={{1,2}}} --[[@as BottleStepContacts]])
        Check(#events == 2 and events[1].value == value and events[2].value == value,
            "直接相邻壁虎按两次收益但保留单次价值")
        local assessed = T.Fixture({"ball"})
        assessed.round, assessed.score = 5, 1000
        local board = Fixture(assessed)
        Check(assessed:Start(), "考核回合开始")
        local finish = assessed:Finish()
        board:ApplyEffects(finish)
        local total, balance = assessed.lastRoundScore, assessed.score
        assessed:RevealStep(100)
        Check(assessed.score < balance and assessed.lastRoundScore == total, "考核只扣余额")
        board.roundScore:Sync("draft", assessed.lastRoundScore, 0, 0)
        Check(board.roundScore.shakeTotal == total, "小计不是扣款后的余额差")
        Check(assessed:Skip() and assessed.relicDraft, "进入额外遗物候选")
        Check(board:GetRoundResidue(1) ~= nil, "同回合遗物候选保留残留")
        Check(assessed:Skip() and assessed.phase == "prepare", "进入下一回合")
        Check(board:GetRoundResidue(1) == nil, "下一回合不再开放旧回看")
        board:Destroy()
    end)
    Case("分帧表现挂起不泄漏快照、提交后不被记录池回收", function()
        local game = T.Fixture({"ball"})
        local board = Fixture(game)
        Check(game:Start(), "开始")
        local events = game:Finish()
        local budget = Budget.New(4, function() return 0 end, 1)
        budget:Start(function()
            Stage.Apply(board, function(staged) staged:ApplyEffects(events) end)
        end)
        local frames = 0
        repeat
            frames = frames + 1
            Check(frames < 2048, "分帧有进展")
            budget:BeginFrame()
            if not budget:Resume() then Check(next(board.residue) == nil, "提交前不泄漏") end
        until not budget:Busy()
        game:RevealStep(100)
        Check(frames > 1 and board:GetRoundResidue(1).finalItem.id == "ball", "提交后快照完整")
        local frozen = board:GetRoundResidue(1).finalItem
        board:ResetEffects()
        Check(frozen.id == "ball", "清表现池不清普通快照")
        board:Destroy()
    end)
    print("[回合回看规则] PASS 用例=" .. checks)
    return checks
end

return Tests
