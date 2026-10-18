-- 仅由官方 runtime 的 -validate-test 加载，测试真实 Box2D、UI 和新回合流程
-- （V0.3：抽20/摇10秒/结算2秒/三选一）。
local V = _G["V"]
local api
local startY = 0
local uid = 0
local totalBefore = 0
local UI = require("urhox-libs/UI")
local CoreUI = require("urhox-libs.UI.Core.UI")
local PointerEvent = require("urhox-libs.UI.Core.PointerEvent")
local Art = require("Bottle.Art")
local Items = require("Bottle.Items")
local GameAudio = require("Bottle.Audio")

local function Click(x, y, touch)
    local data = {x = x * UI.GetScale(), y = y * UI.GetScale(), button = MOUSEB_LEFT,
        pointerType = touch and "touch" or "mouse", pointerId = touch and 1 or 0}
    CoreUI.HandlePointerDown(PointerEvent.new("PointerDown", data))
    CoreUI.HandlePointerUp(PointerEvent.new("PointerUp", data))
    CoreUI.Layout()
end

-- 瓶顶随机散布可能把物品送到物理按钮/菜单/详情卡底下；CoreUI 命中最上层 Widget，
-- 点击会被浮层拦截，污染后续断言。测试点击必须避开可见浮层区。
local function ExclusionRects(view)
    local rects = {}
    for _, widget in ipairs({view.physicsButton, view.physicsMenu, view.detail}) do
        if widget and widget:IsVisible() then
            local l = widget:GetAbsoluteLayout()
            if l.w > 0 and l.h > 0 then
                rects[#rects + 1] = {x = l.x - 4, y = l.y - 4, w = l.w + 8, h = l.h + 8}
            end
        end
    end
    return rects
end

local function ItemPoint(view, itemUid)
    local bounds = view.board:GetItemBounds(itemUid)
    local rects = ExclusionRects(view)
    local function hits(px, py)
        for _, rect in ipairs(rects) do
            if px >= rect.x and px <= rect.x + rect.w and py >= rect.y and py <= rect.y + rect.h then
                return false
            end
        end
        return view.board:PickItem(px, py) == itemUid
    end
    for row = 1, 12 do
        for col = 1, 12 do
            local x, y = bounds.x + bounds.w * col / 13, bounds.y + bounds.h * row / 13
            -- CoreUI 的 screen→widget-local 逆变换含约 1px 取整偏差，
            -- 命中点必须对 ±2px 偏移稳健，否则边缘像素在真实点击时会脱靶。
            if hits(x, y) and hits(x - 2, y) and hits(x + 2, y)
                and hits(x, y - 2) and hits(x, y + 2) then
                return x, y
            end
        end
    end
    error("找不到物品可点击像素：" .. itemUid)
end

-- 从瓶中挑一个存在“不被按钮遮挡的可点击像素”的物品。
local function PickTestItem(view, game)
    for _, candidate in ipairs(game:BottleItems()) do
        local ok = pcall(ItemPoint, view, candidate.uid)
        if ok then return candidate end
    end
    return nil
end

-- 留一帧用于真实截图查看就近弹出的效果卡片。
V.atFrame(120, function()
    api = assert(_G["BottleValidationGet"](), "验收接口未初始化")
    api.NewRun()
    CoreUI.Layout()
    local view = api.GetView()
    local game = api.GetGame()
    -- 点击小羊（按 id 查找，不依赖入瓶顺序）。
    local sheep
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "sheep" then sheep = item end
    end
    V.assert(sheep ~= nil, "初始牌库包含小羊")
    local x, y = ItemPoint(view, sheep.uid)
    Click(x, y)
    V.assert(view.selectedUid == sheep.uid and view.detail:IsVisible(), "点击小羊高亮并打开详情")
    V.assert(view.detailEffect:GetText():find("剧烈摇晃时", 1, true) ~= nil, "详情显示对应物品的具体效果")
end)

V.atFrame(130, function()
    api = assert(_G["BottleValidationGet"](), "验收接口未初始化")
    api.NewRun()
    local game = api.GetGame()
    local view = api.GetView()
    local physics = api.GetPhysics()
    V.assert(game.phase == "prepare", "初始进入准备阶段")
    V.assert(#game.deck == 4 and #game:BottleItems() == 4, "初始牌库为小羊小草苹果小球各1件")
    local starterIds = { "sheep", "grass", "apple", "ball" }
    for i, id in ipairs(starterIds) do
        V.assert(game.deck[i].id == id, "初始牌库第" .. i .. "件为" .. Items.byId[id].name)
    end
    local bottle = view.board:GetAbsoluteLayout()
    V.assert(bottle.w > 100 and bottle.h > 100, "瓶子区域有可用布局空间")
    local item = PickTestItem(view, game)
    V.assert(item ~= nil, "至少一件物品存在不被按钮遮挡的可点击像素")
    uid = item.uid
    local _, y = physics:GetPose(uid)
    startY = y
    V.assert(y > 0 and y < 6.4, "物品初始位于瓶内")
    -- 出现动效：新局4件物品逐件错峰弹跳出现，激活时迸发受重力粒子并播放占位音。
    -- 手动推进 Board:Update 只影响表现时钟，不触碰规则与物理。
    local popSaw, burstSaw, maxScale = 0, 0, 0
    local soundBefore = GameAudio.popCount
    local sampleVy, sampleAfterVy
    for _ = 1, 90 do
        view.board:Update(1 / 60)
        popSaw = math.max(popSaw, #view.board.pops)
        burstSaw = math.max(burstSaw, #view.board.bursts)
        for _, pop in ipairs(view.board.pops) do maxScale = math.max(maxScale, pop.scale) end
        if sampleVy == nil and view.board.bursts[1] then
            sampleVy = view.board.bursts[1].vy
            view.board:Update(1 / 60)
            sampleAfterVy = view.board.bursts[1].vy
        end
    end
    V.assert(popSaw == 4, "初始抽取的4件物品逐件生成出现动效")
    V.assert(maxScale > 1.05, "弹跳动效有过冲回摆")
    V.assert(burstSaw > 0, "出现动效迸发像素粒子")
    V.assert(sampleVy ~= nil and sampleAfterVy < sampleVy, "出现粒子受重力下落")
    V.assert(GameAudio.popCount > soundBefore, "物品出现时播放占位音效")
    -- 每批出现音调都从最低档起逐件升高（4件 → 阶梯走到第4档）。
    V.assert(GameAudio.popPitchStep == 4, "每批出现音调从最低开始并逐件升高")
    -- 重抽：即使抽回同一批 uid，也重新逐件错峰弹跳出现（用户要求）。
    V.assert(game:Reroll(), "准备阶段允许一次重抽")
    view:Update(true)
    view.board:Update(1 / 60)
    V.assert(#view.board.pops == #game:BottleItems(), "重抽后重新触发出现动效")
    V.assert(GameAudio.popPitchStep == 1, "重抽批次音调重新从最低开始")
    local redrawn = PickTestItem(view, game)
    V.assert(redrawn ~= nil, "重抽后仍有可点击物品")
    item, uid = redrawn, redrawn.uid
    startY = select(2, physics:GetPose(uid))
    CoreUI.Layout()
    local board = view.board
    -- 点击点须避开可见浮层，且对 CoreUI 逆变换约 1px 的取整偏差稳健。
    local x, clickY = ItemPoint(view, uid)
    V.assert(CoreUI.FindWidgetAt(x, clickY) == board, "命中点落在 Board 上")
    Click(x, clickY, true)
    V.assert(view.selectedUid == uid and board.selectedUid == uid and view.detail:IsVisible(), "触摸选中实例并高亮")
    local detail = view.detail:GetAbsoluteLayout()
    local container = view.container:GetAbsoluteLayout()
    V.assert(detail.x >= container.x and detail.x + detail.w <= container.x + container.w + 1
        and detail.y >= container.y and detail.y + detail.h <= container.y + container.h + 1,
        "详情锚定在物品附近且不越出安全区域")
    Click(detail.x + detail.w / 2, detail.y + detail.h / 2)
    V.assert(view.detail:IsVisible() and view.selectedUid == uid, "点击详情内部保持展开")
    view:CloseItemDetail()
    local ball
    for _, candidate in ipairs(game:BottleItems()) do
        if candidate.id == "ball" then ball = candidate end
    end
    V.assert(ball ~= nil, "初始牌库包含小球")
    Click(x, clickY)
    -- 详情卡打开后再取球的可点击像素：排除区此时含详情卡，保证点击落在 Board 上。
    local ballX, ballY = ItemPoint(view, ball.uid)
    V.assert(CoreUI.FindWidgetAt(ballX, ballY) == board, "球的命中点不被详情卡遮挡")
    Click(ballX, ballY)
    V.assert(view.selectedUid == ball.uid, "直接点击另一物品切换详情")
    V.assert(view.detailEffect:GetText():find("碰撞瓶子", 1, true) ~= nil, "切换后效果与实例一致")
    Click(bottle.x + 4, bottle.y + bottle.h - 4)
    V.assert(not view.detail:IsVisible() and board.selectedUid == 0, "点击瓶内空白关闭详情和高亮")
    Click(x, clickY)
    Click(container.x + 2, container.y + 2)
    V.assert(not view.detail:IsVisible() and view.selectedUid == 0, "点击瓶外空白关闭详情")
    Click(x, clickY)
    local summary = assert(view.container:FindById("scoreSummary")):GetAbsoluteLayout()
    Click(summary.x + 5, summary.y + summary.h / 2)
    V.assert(not view.detail:IsVisible() and view.selectedUid == 0, "点击分数展示卡片空白也关闭详情")
    local dragX, dragY = x * UI.GetScale(), clickY * UI.GetScale()
    CoreUI.HandlePointerDown(PointerEvent.new("PointerDown", {x = dragX, y = dragY, button = MOUSEB_LEFT}))
    CoreUI.HandlePointerMove(PointerEvent.new("PointerMove",
        {x = dragX + 10 * UI.GetScale(), y = dragY, button = MOUSEB_LEFT}))
    CoreUI.HandlePointerUp(PointerEvent.new("PointerUp", {x = dragX, y = dragY, button = MOUSEB_LEFT}))
    V.assert(not view.detail:IsVisible(), "拖动后松手不误触选中")
    local position = physics.bodies[uid].node.position2D
    local second = game:BottleItems()[2]
    local secondPosition = physics.bodies[second.uid].node.position2D
    physics.bodies[second.uid].node:SetPosition2D(position)
    local overlapX, overlapY = ItemPoint(view, second.uid)
    V.assert(board:PickItem(overlapX, overlapY) == second.uid, "重叠物品优先拾取最后绘制的实例")
    physics.bodies[second.uid].node:SetPosition2D(secondPosition)
    V.assert(not Art.HitItem("apple", -20, -20, 20, 0), "透明角落属于空白")
    V.assert(Art.HitItem("banana", 0, 0, 20, math.pi / 2), "旋转物品按绘制坐标拾取")
    V.assert(Art.HitItem("ball", 0, 0, 20, 0), "小球图案可命中")
    V.assert(Art.HitItem("banana_peel", 0, 2, 20, 0), "香蕉皮图案可命中")
    Click(x, clickY)
    game.revision = game.revision + 1
    view:Update(true)
    V.assert(not view.detail:IsVisible() and board.selectedUid == 0, "重抽或状态修订关闭旧选中")
    Click(x, clickY)
    physics:SetMode(1)
    view:UpdatePhysicsMode()
    local startButton
    for _, row in ipairs(view.footer:GetChildren()) do
        for _, child in ipairs(row:GetChildren()) do
            if child.props.text == "开始摇晃" then startButton = child end
        end
    end
    assert(startButton, "开始按钮不存在")
    -- PageMotion 弹簧入场：按钮落位前 pointerEvents=none（防误触），
    -- 真实玩家要等动画结束才能点到；验收在同一帧内推进 Tick 至可交互。
    local pageMotion = view.machineSkin and view.machineSkin.pageMotion
    V.assert(pageMotion ~= nil, "机台皮肤带 PageMotion 入场动画")
    local guard = 0
    while startButton.props.pointerEvents ~= "auto" do
        guard = guard + 1
        V.assert(guard < 600, "开始按钮弹簧动画必须在10秒内落位并可交互")
        pageMotion:Tick(1 / 60)
    end
    CoreUI.Layout()
    local slHit = startButton:GetAbsoluteLayoutForHitTest()
    V.assert(CoreUI.FindWidgetAt(slHit.x + slHit.w / 2, slHit.y + slHit.h / 2) == startButton,
        "落位后的开始按钮可被 UI 命中")
    local px, py = (slHit.x + slHit.w / 2) * UI.GetScale(), (slHit.y + slHit.h / 2) * UI.GetScale()
    CoreUI.HandlePointerDown(PointerEvent.new("PointerDown", {x = px, y = py}))
    CoreUI.HandlePointerUp(PointerEvent.new("PointerUp", {x = px, y = py}))
    V.assert(game.phase == "running", "点击真实UI按钮进入摇晃阶段")
    V.assert(not view.detail:IsVisible() and view.selectedUid == 0, "开始摇晃自动关闭详情")
    -- 阶段切换（prepare→running）只清表现残留，不把原有瓶内物品误判为新出现。
    view.board:Update(1 / 60)
    V.assert(#view.board.pops == 0, "进入摇晃不重复触发出现动效")
    Click(x, clickY)
    V.assert(not view.detail:IsVisible() and board:PickItem(x, clickY) == 0, "摇晃期间禁止选中物品")
end)

V.atFrame(230, function()
    local game, physics = api.GetGame(), api.GetPhysics()
    local _, y = physics:GetPose(uid)
    V.assert(y < startY - .05, "物品在真实重力下下落")
    V.assert(game.elapsed > 0, "固定步长计时推进")
    local body = physics.bodies[uid].body
    local previous = body.linearVelocity.y
    physics:Shake(0, .3)
    V.assert(body.linearVelocity.y > previous + 1, "拖动摇晃施加真实向上冲量")
    local GestureEvent = require("urhox-libs.UI.Core.GestureEvent")
    local board = api.GetView().board
    local l = board:GetAbsoluteLayout()
    local px, py = (l.x + l.w / 2) * UI.GetScale(), (l.y + l.h / 2) * UI.GetScale()
    local beforeDrag = body.linearVelocity.x
    CoreUI.HandlePointerDown(PointerEvent.new("PointerDown", {x = px, y = py, button = MOUSEB_LEFT}))
    CoreUI.HandleGestureEvent(GestureEvent.new(GestureEvent.Types.PanStart,
        {x = px, y = py, target = board}))
    CoreUI.HandleGestureEvent(GestureEvent.new(GestureEvent.Types.PanMove,
        {x = px + 20, y = py, target = board, deltaX = 20, deltaY = 0}))
    V.assert(body.linearVelocity.x > beforeDrag + .5, "UI拖动事件真实传递到物理冲量")
    CoreUI.HandleGestureEvent(GestureEvent.new(GestureEvent.Types.PanEnd,
        {x = px + 20, y = py, target = board}))
    V.assert(board.state.dragging == false, "拖动结束清除手势状态")
    local saved = game:Snapshot()
    V.assert(saved.phase == "prepare" and saved.score == 0, "摇晃中存档回退回合开始前")
end)

V.atFrame(330, function()
    local game, physics, view = api.GetGame(), api.GetPhysics(), api.GetView()
    -- 模拟剩余固定物理步跑完摇晃10秒，验收进入结算阶段。
    while game.phase == "running" do
        local dt = math.min(1 / 60, 10 - game.elapsed)
        physics:Step(dt)
        local events = game:Step(dt, physics:Contacts())
        physics:RememberEvents(events)
        view.board:Effects(events)
        physics:Sync(game:BottleItems())
    end
    V.assert(game.phase == "settle", "摇晃10秒后进入结算阶段")
    V.assert(game.roundScore == 0, "摇晃阶段不产金币")
    view:Update(true)
    -- 小草可能已被小羊消耗，便便/羊毛也可能入瓶；按实际结算事件验收浮字数量。
    local settlementItems = #game:BottleItems()
    local settlementScores = 0
    -- 结算下落2秒：物体自然下落，随后一次性结算。
    local guard = 0
    while game.phase == "settle" do
        guard = guard + 1
        V.assert(guard < 300, "结算阶段必须在有限步内完成")
        local dt = math.min(1 / 60, 2 - game.settleElapsed)
        physics:Step(dt)
        local events = game:SettleStep(dt, physics:Contacts())
        for _, event in ipairs(events) do
            if event.kind == "score" and (event.value or 0) > 0 then settlementScores = settlementScores + 1 end
        end
        physics:RememberEvents(events)
        view.board:Effects(events)
        physics:Sync(game:BottleItems())
    end
    -- 结算展示：分数逐个弹出（逐个结算浮字），队列播完后再停约2秒进入三选一。
    local revealGuard = 0
    local floatsSeen, sequentialSaw = 0, false
    local soundBeforeReveal = GameAudio.popCount
    local stagedStart, stagedEnd, lastPopFrame
    while game.phase == "reveal" do
        revealGuard = revealGuard + 1
        V.assert(revealGuard < 300, "结算展示必须在有限步内完成")
        game:RevealStep(1 / 60)
        -- 画布随帧推进：队列中的结算浮字按间隔逐个释放。
        view.board:Update(1 / 60)
        floatsSeen = math.max(floatsSeen, #view.board.particles)
        if #view.board.particles >= 1 and #view.board.scoreQueue >= 1 then
            sequentialSaw = true
        end
        if view.board.displayScore ~= nil then
            stagedStart = stagedStart or view.board.displayScore
            stagedEnd = view.board.displayScore
        end
        if lastPopFrame == nil and #view.board.scoreQueue == 0 then lastPopFrame = revealGuard end
    end
    view:Update(true)
    V.assert(game.phase == "draft", "结算完成进入三选一")
    V.assert(game.totalScore >= 6 and settlementScores >= 3, "小羊苹果小球按价值结算至少得6金币")
    V.assert(floatsSeen >= settlementScores and sequentialSaw, "结算浮字逐个弹出而非一次性全部出现")
    V.assert(GameAudio.popCount >= soundBeforeReveal + settlementScores, "逐件结算浮字播放出现音效")
    -- 顶部滚轮随逐件结算递增，并在队列结束时到达最终余额。
    V.assert(stagedStart ~= nil and stagedStart < game.score and stagedEnd == game.score,
        "顶部滚轮随逐件结算逐步增加并在队列结束前到位")
    -- 队列播完后还要停留约2秒（120帧）才进入三选一。
    V.assert(lastPopFrame ~= nil and revealGuard - lastPopFrame >= 116,
        "浮字队列结束后再停留约2秒才进入三选一")
    -- 结算表现：物品回牌库后画布保留最终姿态残留，不再瞬间消失。
    local residueCount = 0
    for _ in pairs(view.board.residue) do residueCount = residueCount + 1 end
    V.assert(residueCount >= settlementItems, "结算后保留瓶中物品残留姿态")
    V.assert(#game.options >= 1 and #game.options <= 3, "三选一生成候选物品")
    V.assert(not view.draft:IsVisible(), "倒计时闪烁期间三选一面板暂缓显示")
    view.machineSkin.cabinet.clock:Tick(.84)
    view:Update()
    V.assert(view.draft:IsVisible(), "三次闪烁后展示三选一面板")
    totalBefore = game.totalScore
end)

V.atFrame(370, function()
    local game, physics, view = api.GetGame(), api.GetPhysics(), api.GetView()
    V.assert(game:DraftRefresh(), "本回合允许一次刷新")
    V.assert(not game:DraftRefresh(), "第二次刷新被拒绝")
    V.assert(#game.options >= 1, "考核1阶段必有候选")
    V.assert(game:Choose(1), "可以选择一个物品")
    physics:Sync(game:BottleItems(), true, game.revision)
    view:Update(true)
    V.assert(game.round == 2, "选取后进入下一回合")
    V.assert(game.totalScore == totalBefore, "切换回合不重复结算")
    view:OpenInventory()
    V.assert(view.modal:IsVisible(), "准备阶段可以查看牌库")
    -- 牌库改为物理沙盒：全部持有实例从顶部落下，底部操作区只留返回。
    local sim = view.deckSim
    local board = view.deckBoard
    V.assert(sim ~= nil and board ~= nil, "牌库以物理沙盒展示")
    V.assert(#sim.order == #game.deck, "沙盒包含全部牌库实例")
    V.assert(not view.footer:IsVisible(), "牌库页收起底部操作按钮")
    V.assert(view.deckBackButton ~= nil, "牌库页提供底部返回按钮")
    -- 重力：推进沙盒时钟后至少一件物品明显下落。
    local fallingUid = sim.order[1].uid
    local startFallY = select(2, sim:GetPose(fallingUid))
    for _ = 1, 60 do board:Update(1 / 60) end
    local fallY = select(2, sim:GetPose(fallingUid))
    V.assert(fallY < startFallY - .05, "物品在牌库沙盒中受重力下落")
    -- 继续推进到停稳：所有物品都被容器底部接住，不会掉出屏幕。
    for _ = 1, 300 do board:Update(1 / 60) end
    CoreUI.Layout()
    local resting = true
    for _, record in ipairs(sim.order) do
        local _, y = sim:GetPose(record.uid)
        if y < -0.02 then resting = false end
    end
    V.assert(resting, "物品停在沙盒容器内")
    -- 点击沙盒中的物品进入详情；优先选择不被其他物品遮住的实例。
    local function DeckPoint(uid)
        local bounds = board:GetItemBounds(uid)
        for row = 1, 12 do
            for col = 1, 12 do
                local x, y = bounds.x + bounds.w * col / 13, bounds.y + bounds.h * row / 13
                if board:PickItem(x, y) == uid and board:PickItem(x - 2, y) == uid
                    and board:PickItem(x + 2, y) == uid and board:PickItem(x, y - 2) == uid
                    and board:PickItem(x, y + 2) == uid then return x, y end
            end
        end
    end
    local clickUid, clickX, clickY
    for _, record in ipairs(sim.order) do
        local x, y = DeckPoint(record.uid)
        if x then clickUid, clickX, clickY = record.uid, x, y break end
    end
    V.assert(clickUid ~= nil, "至少一件沙盒物品可点击")
    Click(clickX, clickY)
    V.assert(view.deckDetailUid == clickUid, "点击沙盒物品进入物品详情")
    V.assert(view.deckBoard == nil and view.deckSim == sim, "物品详情替换沙盒且保留物理状态")
    local clickedItem = assert(game:Get(clickUid))
    local deckProse = view.deckBody:FindById("deckDescription")
    V.assert(deckProse ~= nil and deckProse:GetText():find(Items.byId[clickedItem.id].effect, 1, true) ~= nil,
        "详情显示该实例的完整效果说明")
    local pageMotion = view.machineSkin and view.machineSkin.pageMotion
    V.assert(pageMotion ~= nil, "牌库返回按钮带页面弹簧动画")
    local back = view.deckBackButton
    local guard = 0
    while back.props.pointerEvents ~= "auto" do
        guard = guard + 1
        V.assert(guard < 600, "返回按钮弹簧动画必须在10秒内落位")
        pageMotion:Tick(1 / 60)
    end
    CoreUI.Layout()
    local backBox = back:GetAbsoluteLayoutForHitTest()
    V.assert(CoreUI.FindWidgetAt(backBox.x + backBox.w / 2, backBox.y + backBox.h / 2) == back,
        "返回按钮真实可点击")
    Click(backBox.x + backBox.w / 2, backBox.y + backBox.h / 2)
    V.assert(view.deckDetailUid == 0 and view.deckBoard ~= nil and view.deckSim == sim,
        "详情页返回牌库沙盒并保持物理状态")
    backBox = back:GetAbsoluteLayoutForHitTest()
    Click(backBox.x + backBox.w / 2, backBox.y + backBox.h / 2)
    V.assert(not view.modal:IsVisible() and not view.inventoryOpen, "牌库沙盒返回原页面")
    V.assert(view.deckSim == nil, "退出牌库释放沙盒物理世界")
    view:Update(true)
    V.assert(view.footer:IsVisible(), "退出牌库后底部按钮恢复")
end)

V.atFrame(410, function()
    api.GetView().modal:Hide()
    api.GetView():OpenSave()
    V.assert(api.GetView().modal:IsVisible(), "存档码面板可打开")
    V.finish()
end)
