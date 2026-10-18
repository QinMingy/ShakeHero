-- 真实main隔离移除UI验收入口及-validate-test脚本；不读取或写入玩家存档。
---@type table<string, any>
local Storage = require("Bottle.Storage")
local V = _G["V"]
if not V then
    Storage.Load = function() return nil end
    Storage.Save = function(game)
        Storage.removalSaved = game:Snapshot()
        Storage.status = "主动移除专项内存存档"
        return true
    end
    Storage.removalIsolated = true
    require("main")
    return
end
local UI = require("urhox-libs/UI")
local Game = require("Bottle.Game")
---@type any
local view = {}
---@type any
local game = {}
---@type any
local physics = {}
---@type any
local oldConfirm = nil
---@type any
local oldConfirmButton = nil
local removedUid, survivorUid = 0, 0
local function Check(condition, message) V.assert(condition,message) end
local function Guard(frame, callback)
    V.atFrame(frame,function()
        local ok, err = pcall(callback)
        Check(ok,"RemovalUI frame" .. frame .. (ok and "完成" or " | " .. tostring(err)))
    end)
end
local function Button(id)
    return assert(view.modal:FindById(id),"缺少按钮" .. id) --[[@as Button]]
end
local function Press(id)
    for _=1,180 do view.machineSkin.pageMotion:Tick(1/60) end
    local button = Button(id)
    assert(not button:IsDisabled(),"按钮禁用" .. id)
    button.props.onClick(button,nil)
end
Guard(2,function()
    local api = assert(_G["BottleValidationGet"]())
    view, game, physics = api.GetView(), api.GetGame(), api.GetPhysics()
    view.startScreen:Close(); view.startScreen:Update(.41)
    Check(Storage.removalIsolated,"启动前隔离存档")
    Check(game.removals == 0,"新局移除0次")
    removedUid, survivorUid = game.deck[1].uid, game.deck[2].uid
    view:OpenInventory(); view:ShowDeckItem(removedUid)
    Check(Button("deckRemove"):IsDisabled(),"无次数详情按钮禁用")
    view:CloseInventory()
    game.removals = 2
    view:Update(true); view:OpenInventory(); view:ShowDeckItem(removedUid)
    Check(view.inventoryTitle.props.text:find("移除 2 次",1,true),"牌库清晰显示次数")
    Press("deckRemove")
    Check(view.removalConfirmUid == removedUid and view.modal:FindById("removalConfirm"),"逐实例选择后二次确认")
    local targetText = assert(Button("removalTarget").props.text)
    Check(targetText:find(string.format("#%d",removedUid),1,true),"确认内容含精确UID")
    Press("removalCancel")
    Check(game.removals == 2 and game:Get(removedUid),"取消不扣不删")
    Press("deckRemove")
    oldConfirmButton = Button("removalConfirm")
    oldConfirm = oldConfirmButton.props.onClick
    local survivorBody = physics.bodies[survivorUid]
    local px, py, pa = physics:GetPose(survivorUid)
    local sandbox = view.deckSim
    local survivorRecord = sandbox.records[survivorUid]
    Press("removalConfirm")
    Check(game.removals == 1 and not game:Get(removedUid) and #game.discard == 0,"成功只扣1且不入弃牌")
    Check(not physics.bodies[removedUid] and physics.bodies[survivorUid] == survivorBody,"差量物理只退休目标UID")
    local x, y, angle = physics:GetPose(survivorUid)
    Check(x == px and y == py and angle == pa,"剩余瓶内姿态不重排")
    Check(view.deckSim == sandbox and not sandbox.records[removedUid]
        and sandbox.records[survivorUid] == survivorRecord,"牌库沙盒仅退休目标不整体重建")
    Check(Storage.removalSaved.removals == 1 and not Game.Restore(Storage.removalSaved):Get(removedUid),
        "成功经main action自动保存次数及UID注销")
    oldConfirm(oldConfirmButton,nil)
    Check(game.removals == 1,"旧确认回调不能重复扣次数")
    view:CloseInventory(); view:OpenInventory()
    Check(not view.deckSim.records[removedUid] and view.removalConfirmUid == 0,"重开不带旧UID或旧确认")
end)
Guard(4,function()
    view:CloseInventory()
    -- 两种draft均走原牌库入口，候选不因移除重抽。
    game:Start(); game:Finish(); game:RevealStep(100)
    for _, relicDraft in ipairs({false,true}) do
        if relicDraft then
            game.round,game.stage,game.target=5,2,Game.GetTarget(2)
            game.pendingRelicDraft=true
            game.refreshes=0
            Check(game:Skip() and game.relicDraft and game.relicRefreshes==1,
                "移除验收正常进入遗物draft获独立免费1次")
        else
            game.relicDraft=false;game.options=game:_DraftOptions()
        end
        game.removals = 2
        view:Update(true)
        if relicDraft then
            local refresh=assert(view.draft:FindById("draftRefresh")) --[[@as Button]]
            local hint=assert(view.draft:FindById("refreshPoolHint")) --[[@as Label]]
            Check(not refresh:IsDisabled() and refresh.props.text=="刷新 · 1 次"
                and hint:GetText():find("独立",1,true)~=nil and hint:GetText():find("免费1次",1,true)~=nil,
                "普通共享0时真实main遗物刷新按钮仍可用且明确免费")
            for _=1,180 do view.machineSkin.pageMotion:Tick(1/60) end
            assert(refresh.props.onClick)(refresh,nil)
            Check(game.refreshes==0 and game.relicRefreshes==0,
                "真实main刷新action只耗遗物池不扣普通余额")
            local spent=assert(view.draft:FindById("draftRefresh")) --[[@as Button]]
            Check(spent:IsDisabled(),"真实main第二次遗物刷新按钮禁用")
            local saved=Game.Restore(Storage.removalSaved)
            Check(Storage.removalSaved.relicRefreshes==0 and saved.relicRefreshes==0 and saved.refreshes==0,
                "main自动Save并Restore耗尽遗物次数为0、不补发")
            Check(not saved:DraftRefresh() and saved.refreshes==0,
                "恢复后的遗物draft也不可第二次免费刷新")
        end
        local uid = game.deck[1].uid
        local choices = table.concat(game.options,",")
        view:OpenInventory(); view:ShowDeckItem(uid)
        Press("deckRemove"); Press("removalConfirm")
        Check(not game:Get(uid) and game.removals == 1 and table.concat(game.options,",") == choices,
            (relicDraft and "遗物" or "物品") .. "draft可移除且候选保持")
        if relicDraft then
            local saved=Game.Restore(Storage.removalSaved)
            Check(game.relicRefreshes==0 and saved.relicRefreshes==0 and saved.removals==1,
                "遗物draft移除自动存档不重置已用尽的免费刷新次数")
            Check(table.concat(saved.options,",")==choices,"移除后的遗物候选存档保序不补抽")
        end
        view:CloseInventory()
    end
    Check(game:Skip() and game.round==6 and game.relicRefreshes==0,
        "移除和独立刷新验收后正常离开遗物draft，不携带免费余额")
    view:Update(true)
    Check(Storage.removalIsolated,"全程内存存档隔离")
end)
Guard(6,function()
    -- 最终真实截图停在确认页，展示对象编号、次数、确认/取消两按钮。
    game.phase, game.relicDraft = "prepare", false
    game.relicRefreshes,game.pendingRelicDraft=0,false
    view:Update(true); view:OpenInventory()
    local item = assert(game.deck[1])
    game.removals = 1
    view:ShowDeckItem(item.uid); Press("deckRemove")
    UI.Layout()
    local confirm, cancel = Button("removalConfirm"), Button("removalCancel")
    Check(confirm:GetAbsoluteLayout().h > 0 and cancel:GetAbsoluteLayout().h > 0,"确认取消实际布局可见")
end)
Guard(12,function() V.finish() end)
