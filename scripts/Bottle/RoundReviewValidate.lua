-- 独立原生验收：真实UI、物理和回合详情，不加载主程序或玩家存档。
local UI = require("urhox-libs/UI")
local Core = require("urhox-libs.UI.Core.UI")
local T = require("Bottle.RepairTests")
local Tests = require("Bottle.RoundReviewTests")
local Physics = require("Bottle.Physics")
local View = require("Bottle.View")
local Skin = require("Machine.LayeredSkin")
local Money = require("Bottle.Money")
---@type any
local view = nil
local frame, checks = 0, 0
local expected = 0
local function Check(value, message)
    assert(value, "[回合回看原生] " .. message)
    checks = checks + 1
end
local function Layout() Skin.Layout(view); Core.Layout() end
local function HiddenDraft()
    view.machineSkin.clock.flashElapsed = -1
    Skin.SetDraftOpen(view, false)
    Layout()
end
function Start()
    input.mouseMode = MM_ABSOLUTE
    UI.Init({theme=require("Bottle.Theme"), scale=UI.Scale.DEFAULT})
    require("Machine.Palette").Init()
    require("Bottle.ButtonMotion").Init()
    Tests.Run()
    local game = T.Fixture({"ball", "credit_card", "die_d6", "bacon"})
    local physics = Physics.New()
    physics:Sync(game:BottleItems(), true, 17)
    local function noop() end
    view = View.New(game, physics, {shake=noop,start=noop,reroll=noop,refresh=noop,choose=noop,
        skip=noop,newrun=noop,import=noop,sensor=noop,sensorGain=noop,sensorLab=noop,
        atmosphere=noop,remove=noop,gmadd=noop,juicer=noop})
    view.machineSkin.litScene:ToggleCameraMotion()
    SubscribeToEvent("Update", "HandleRoundReviewValidationUpdate")
    SubscribeToEvent("PostUpdate", "HandleRoundReviewValidationPrepare")
    print("[回合回看原生] 独立内存场景启动，不读写玩家存档")
end
function HandleRoundReviewValidationUpdate()
    frame = frame + 1
    if frame == 2 then
        Check(view.game:Start(), "真实回合开始")
        assert(view.game:Get(1)).bonus = 11
        assert(view.game:Get(3)).rollValue = 6
        expected = view.game:_Value(assert(view.game:Get(1)))
        local events = view.game:Finish(view.physics:Contacts())
        view.physics:RememberEvents(events)
        view.board:Effects(events)
        view.physics:Sync(view.game:BottleItems())
        view.game:RevealStep(100)
        view:Update(true)
        HiddenDraft()
        Check(view.board:IsVisible() and not view.draft:IsVisible(), "收起候选回瓶子")
        Check(view.board.roundScore.shakeRoot:IsVisible(), "左上回合小计可见")
        Check(view.board.roundScore.shakeTotal == view.game.lastRoundScore, "小计读最终回合收益")
        local x, y = Tests.Point(view.board, 1)
        Check(view.board:PickItem(x, y) == 1, "真实残留可拾取")
        -- 通过原Board指针处理走到View，不直接调用详情构造。
        local board = view.board
        local event = {x=x,y=y,target=board,pointerId=1,isPrimary=true,
            IsPrimaryButton=function() return true end,StopPropagation=function() end}
        board:OnPointerDown(event); board:OnPointerUp(event); board:OnClick(event)
        Check(view.detailOverlay:IsVisible() and view.detailSource == "round", "原点击打开共用详情纸条")
        Check(view.detailGold:GetText() == Money.Format(expected), "显示清理前最终价值")
        Check(view.game:_Value(assert(view.game:Get(1))) ~= expected, "未误用牌库当前值")
        Check(not view.itemNote.action:IsVisible(), "回合回看只读不新增移除入口")
    elseif frame == 3 then
        view:Update()
        Check(view.detailOverlay:IsVisible() and view.board.selectedUid == 1, "详情跨帧保留和白边")
        Check(view:InspectDefinition("ball"), "共用引用图鉴入口可打开")
        view:CloseDefinition()
        Check(view.detailOverlay:IsVisible(), "关闭引用后保留原详情")
        local stopped = false
        view.detailOverlay.props.onClick(view.detailOverlay,
            {target=view.detailOverlay,IsPrimaryButton=function() return true end,
                StopPropagation=function() stopped=true end})
        Check(stopped and not view.detailOverlay:IsVisible() and view.board.selectedUid == 0,
            "共用空白遮罩消费点击并关闭，不穿透物品")
        view:InspectItem(4)
        Check(view.detailOverlay:IsVisible() and view.detailIcon.itemId == "bacon", "真实软体残留可开详情")
        local soft = assert(view.board.residue[4].soft)
        local x, y, ppu = view.board:GetBottleTransform()
        local p = soft[1]
        Check(view.board:PickItem(x+p.x*ppu,y-p.y*ppu) == 4, "真实保存分段可拾取")
        view:CloseItemDetail()
        Check(not view.detailOverlay:IsVisible() and view.board.selectedUid == 0, "共用关闭清选择")
        view:InspectItem(3)
        Check(view.detailIcon.rollValue == 6, "骰面回看保留最终点数")
        Skin.SetDraftOpen(view, true)
        Check(not view.detailOverlay:IsVisible() and not view.board:IsVisible(), "重开候选关闭详情且隐藏小计父层")
        HiddenDraft()
        view:OpenInventory()
        Check(not view.board:IsVisible(), "牌库页面不透出分数板")
        view:CloseInventory(); HiddenDraft()
        Check(view.board:IsVisible() and view.board.roundScore.shakeRoot:IsVisible(), "牌库返回恢复小计")
        view:InspectItem(1)
    elseif frame == 4 then
        view:Update()
        Check(view.detailOverlay:IsVisible(), "牌库返回后详情仍可打开")
        local score, rng = view.game.score, view.game._rngState
        for _ = 1, 3 do Skin.SetDraftOpen(view,true); HiddenDraft() end
        Check(view.game.score == score and view.game._rngState == rng, "反复收起不改余额和随机数")
        view:InspectItem(1)
    elseif frame == 9 then
        view:Update()
        Check(view.detailOverlay:IsVisible() and view.itemNote.card:IsVisible(), "稳定帧共用纸条可见")
        Check(view.itemNote.status:GetText() == "本回合最终价值", "明确标识回合价值来源")
        Check(view.detailGold:GetText() == Money.Format(expected), "稳定帧最终价值不被牌库值覆盖")
        local card = view.itemNote.card:GetAbsoluteLayout()
        Check(card.w > 100 and card.h > 60, "详情纸条有有效测量范围")
        print("[回合回看原生] PASS 断言=" .. checks)
    end
end
function HandleRoundReviewValidationPrepare()
    if view then view.machineSkin.litScene.post:PrepareFrame() end
end
function Stop()
    if view then UI.SetRoot(nil); view.root:Destroy(); view.physics:Clear() end
    UI.Shutdown()
end
