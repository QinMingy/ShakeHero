-- First-run teaching is a separate player record; its checkpoint follows the game rollback.
local Storage=require("Bottle.Storage")
local State=require("Bottle.TutorialState")
local Overlay=require("Bottle.TutorialOverlay")
local Text=require("Bottle.TutorialText")
local L=require("Machine.LayeredLayout")
local Skin=require("Machine.LayeredSkin")
---@type any
local Tutorial={}
Tutorial.__index=Tutorial

local specs={
    welcome={holes={L.board},hand="heart",y=335},
    goal={holes={L.score,L.target,L.round,L.targetProgress},point={86,177,18,8},
        handEdge="left",handAngle=-32,y=295},
    start={button=false,holes={L.board,L.start},windows={L.start},point={276,696,8,8},
        handEdge="right",handAngle=35,y=390},
    inspectBall={button=false,holes={L.board},windows={},point=L.board,y=24,compact=true},
    ballEffect={holes={L.board},windows={L.board},hideHand=true,y=24,compact=true},
    shakeIntro={holes={L.board},point={90,365,70,50},y=650,compact=true},
    running={button=false,holes={L.board,L.start,L.reroll},
        windows={L.board},handEdge="left",circle={cx=190,cy=420,rx=55,ry=60,period=2.2},
        y=755,compact=true},
    result={holes={L.score},point=L.score,y=340},
    choose={holes={L.screen,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
        windows={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
        point=L.draftSlots[2],y=24,compact=true},
    refresh={holes={L.draftRefresh},point=L.draftRefresh,y=250},
    reroll={button=false,holes={L.draftRefresh},windows={L.draftRefresh},point=L.draftRefresh,y=350,compact=true},
    confirm={button=false,holes={L.screen,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3],L.draftConfirm},
        windows={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3],L.draftConfirm},point=L.draftConfirm,y=24,compact=true},
    finish={holes={L.board,L.target},hand="nails",y=335},
    exam={holes={L.score,L.target,L.round},point=L.target,y=330},
    relic={holes={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
        point=L.draftSlots[2],y=27,compact=true},
}

function Tutorial.New(view,callbacks)
    local self=setmetatable({},Tutorial)
    self:Init(view,callbacks)
    return self
end
function Tutorial:Init(view,callbacks)
    self.view=view;self.callbacks=callbacks;self.launching=false;self.milestone=""
    self.overlay=Overlay.New(view,function() self:Continue() end)
end
function Tutorial:SetState(value)
    Storage.SetTutorial(value)
    self.callbacks.save()
end
function Tutorial:Active()
    return Storage.tutorial.status=="active" or self.milestone~=""
end
function Tutorial:IsPaused()
    return self:Active() and (self.milestone~="" or Storage.tutorial.step~="running")
end
function Tutorial:Allows(action)
    -- 首次教学要实际刷新候选，尚未开始教学时也不能先花掉共享池的唯一一次。
    if Storage.tutorial.status == "new" and action == "reroll" then return false end
    if not self:Active() then return true end
    local step=Storage.tutorial.step
    return self.milestone=="" and ((action=="switch" and (step=="choose" or step=="review" or step=="confirm"))
        or (action=="refresh" and step=="reroll") or (action=="choose" and step=="confirm")
        or (action=="shake" and step=="running"))
end
function Tutorial:AllowsInspection(item,source)
    if not self:Active() then return true end
    local step=Storage.tutorial.step
    return self.milestone=="" and (step=="inspectBall" or step=="ballEffect")
        and self.view.game.phase=="prepare" and source=="bottle" and item and item.location=="bottle"
        and self.view.board:IsItemReadyForInspection(item.uid)
end
function Tutorial:OnInspected(item,source)
    if Storage.tutorial.status~="active" or not self:AllowsInspection(item,source)
        or not self.view.detailOverlay:IsVisible() or self.view.detailSource~=source
        or self.view.selectedUid~=item.uid then return end
    if Storage.tutorial.step=="inspectBall" then
        self:SetState(State.Advance(Storage.tutorial,"inspectedItem",self.view.game))
    end
    self:Present()
end
function Tutorial:OnItemDetailClosed(item,source)
    -- 收起纸条只回到自由查看气泡，下一步必须由玩家手动点击。
    if Storage.tutorial.status=="active" and Storage.tutorial.step=="ballEffect" then self:Present() end
end

-- 优先指向小球；它尚未入场时可先看其他已就绪物品，不依赖固定摆放位置。
function Tutorial:BallTarget()
    local container=self.view.container:GetAbsoluteLayout()
    local s=self.view.machineSkin.scale
    if not (s>0 and container.w>0 and container.h>0) then return end
    ---@type number[]?
    local fallback
    for _,item in ipairs(self.view.game:BottleItems()) do
        if self.view.board:IsItemReadyForInspection(item.uid) then
            local b=self.view.board:GetItemBounds(item.uid)
            if b.w>0 and b.h>0 then
                local w,h=math.max(44,b.w/s+12),math.max(44,b.h/s+12)
                local target={(b.x+b.w/2-container.x)/s-w/2,(b.y+b.h/2-container.y)/s-h/2,w,h}
                if item.id=="ball" then return target end
                fallback=fallback or target
            end
        end
    end
    return fallback
end
function Tutorial:OnStartRequested()
    if self.launching then self.launching=false;return true end
    if Storage.tutorial.status=="new" then
        self:SetState(State.Begin(Storage.tutorial,self.view.game));self:Present();return false
    end
    if not self:Active() then return true end
    if self.milestone=="" and Storage.tutorial.step=="start" then
        self:SetState(State.Advance(Storage.tutorial,"start",self.view.game))
        self:Present()
    end
    return false
end
function Tutorial:OnStarted()
    if Storage.tutorial.status=="active" then
        self:SetState(State.Advance(Storage.tutorial,"started",self.view.game))
        self:Present()
    end
end
function Tutorial:OnChosen()
    if Storage.tutorial.status=="active" then
        self:SetState(State.Advance(Storage.tutorial,"chosen",self.view.game))
    end
end
function Tutorial:OnSwitched()
    if Storage.tutorial.status=="active" and Storage.tutorial.step=="choose" then
        self:SetState(State.Advance(Storage.tutorial,"switched",self.view.game))
        self:Present()
    end
end
function Tutorial:OnRefreshed()
    if Storage.tutorial.status=="active" and Storage.tutorial.step=="reroll" then
        self:SetState(State.Advance(Storage.tutorial,"refreshed",self.view.game))
        self:Present()
    end
end
function Tutorial:Rebind(imported)
    self.milestone="";self.launching=false
    if imported then Storage.MarkImported()
    else Storage.SetTutorial(State.Reconcile(Storage.tutorial,self.view.game)) end
    self.overlay:Hide(true)
end
function Tutorial:Continue()
    local game=self.view.game
    if self.milestone~="" then
        self:SetState(State.MarkSeen(Storage.tutorial,self.milestone))
        self.milestone="";self:Present();return
    end
    local step=Storage.tutorial.step
    if step=="shakeIntro" then
        self.launching=true;self.callbacks.start()
    elseif step=="ballEffect" then
        if game.phase=="prepare" then
            self:SetState(State.Advance(Storage.tutorial,"continue",game))
            self.view:CloseDefinition();self.view:CloseItemDetail()
        end
    elseif step~="start" and step~="choose" and step~="running" and step~="reroll" and step~="confirm" then
        self:SetState(State.Advance(Storage.tutorial,"continue",game))
    end
    self:Present()
end
function Tutorial:Present()
    if not self:Active() then self.overlay:Hide();return end
    local key=self.milestone~="" and self.milestone or Storage.tutorial.step
    -- 真实纸条打开时收起气泡；物品及关联图鉴都关闭后再显示手动下一步。
    if key=="ballEffect" and (self.view.detailOverlay:IsVisible() or self.view.definitionModal:IsVisible()) then
        self.overlay:Hide();return
    end
    local layoutKey=key=="review" and "choose" or key
    local source=specs[layoutKey]
    if not source then self.overlay:Hide();return end
    local spec={};for k,v in pairs(source) do spec[k]=v end;spec.key=key
    local words=Text[layoutKey]
    if type(words)=="table" then
        for k,v in pairs(words) do spec[k]=v end
    end
    if key=="inspectBall" then
        local target=self:BallTarget()
        if target then spec.windows={L.board};spec.point=target
        else
            spec.key="inspectBallLoading";spec.text=Text.inspectBallLoading.text;spec.hideHand=true
        end
    end
    if key=="running" and self.view.game.phase~="running" then
        spec.key="settling";spec.text=Text.settling.text
        spec.windows={};spec.circle=nil
    end
    if key=="choose" or key=="review" then
        spec.key="choose";spec.buttonDisabled=key=="choose"
    end
    -- Keep the candidate page open; the current step controls its action windows.
    if key=="result" or key=="choose" or key=="review" or key=="refresh" or key=="reroll" or key=="confirm" or key=="relic" then
        if self.view.choiceHidden then Skin.SetDraftOpen(self.view,true) end
        local skip=self.view.draft:FindById("draftSkip")
        if key~="relic" and skip then skip:Hide() end
    end
    self.overlay:Show(spec)
end
function Tutorial:Update(dt)
    local game=self.view.game
    if self.view.startScreen and self.view.startScreen:IsActive() then self.overlay:Hide(true);return end
    if Storage.tutorial.status=="new" then
        self:SetState(State.Begin(Storage.tutorial,game))
    end
    if Storage.tutorial.status=="active" and Storage.tutorial.step=="running" and game.phase=="draft" then
        self:SetState(State.Advance(Storage.tutorial,"settled",game))
    end
    if Storage.tutorial.status=="complete" and self.milestone=="" then
        if not Storage.tutorial.examSeen and game.round==5 and game.phase=="prepare" then self.milestone="exam"
        elseif not Storage.tutorial.relicSeen and game.phase=="draft" and game.relicDraft then self.milestone="relic" end
    end
    self:Present()
    self.overlay:Update(dt)
end

return Tutorial
