-- First-run teaching is a separate player record; its checkpoint follows the game rollback.
local Storage=require("Bottle.Storage")
local State=require("Bottle.TutorialState")
local Overlay=require("Bottle.TutorialOverlay")
local L=require("Machine.LayeredLayout")
local Skin=require("Machine.LayeredSkin")
---@type any
local Tutorial={}
Tutorial.__index=Tutorial

local specs={
    welcome={text="欢迎入职，上帝实习生！\n这只烧杯，就是你的第一个小世界。能不能转正，就看你的表现了！",
        button="开始学习",holes={L.board},hand="heart",y=335},
    goal={text="每5回合，都要进行一次考核。\n第一次需要攒够40金币！\n达标会扣除目标金币，剩余的留到以后；金币不够，本次实习就结束啦。",
        holes={L.score,L.target,L.round,L.targetProgress},point={86,177,18,8},
        handEdge="left",handAngle=-32,y=295},
    start={text="杯里的物品，能帮你赚金币。\n准备好就点击「开始摇晃」！",
        button=false,holes={L.board,L.start},windows={L.start},point={276,696,8,8},
        handEdge="right",handAngle=35,y=390},
    shakeIntro={text="按住烧杯来回拖动，让物品移动、碰撞！支持体感时，也能直接摇动手机。\n看，小球碰到杯壁就能增加价值，每3秒可以触发一次。准备好后，开始这10秒吧！",
        button="准备好了",holes={L.board},point={90,365,70,50},y=650,compact=true},
    running={text="来回摇晃，让物品发挥本领！",button=false,holes={L.board,L.start,L.reroll},
        windows={L.board},handEdge="left",circle={cx=190,cy=420,rx=55,ry=60,period=2.2},
        y=755,compact=true},
    result={text="时间到！物品落稳后，会按各自当前的价值结算金币。价值越高，赚得越多！\n普通的价值加成只管这一回合，写着「永久」的才能留到以后。",
        holes={L.score},point=L.score,y=340},
    choose={text="切换候选，查看物品效果。\n看好后，点击「下一步」。",
        button="下一步",holes={L.screen,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
        windows={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
        point=L.draftSlots[2],y=24,compact=true},
    refresh={text="再教你一招：准备重抽和物品刷新共用次数！\n新局有1次，每完成2回合增加1次，没用完会保留；有次数就能继续重抽或刷新。\n遗物每组三选一另有1次独立免费刷新，每次重置。",
        button="试试刷新",holes={L.draftRefresh},point=L.draftRefresh,y=250},
    reroll={text="不满意这三个候选？点击「刷新」，花1次刷新机会，重抽一组！",
        button=false,holes={L.draftRefresh},windows={L.draftRefresh},point=L.draftRefresh,y=350,compact=true},
    confirm={text="切换看效果，再点「选择此物品」。\n每回合从牌库随机抽最多20件入杯，不足就全部上场。",
        button=false,holes={L.screen,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3],L.draftConfirm},
        windows={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3],L.draftConfirm},point=L.draftConfirm,y=24,compact=true},
    finish={text="记住：搭配物品赚金币，在考核前攒够目标！\n加油吧，实习生——你的第一个小世界，交给你了！",
        button="继续实习",holes={L.board,L.target},hand="nails",y=335},
    exam={heading="上帝的考核提醒",text="这回合结束就要考核啦！\n攒够目标金币才能继续，考核会扣除对应金币，剩余的保留。先看看目标，再开始摇晃吧。",
        button="明白了",holes={L.score,L.target,L.round},point=L.target,y=330},
    relic={heading="上帝的遗物奖励",text="考核通过！选完物品，还能再挑一件遗物。\n遗物不用放进烧杯，就能为这局游戏持续提供加成。看看效果，选一件吧！",
        button="挑选遗物",holes={L.board,L.draftSlots[1],L.draftSlots[2],L.draftSlots[3]},
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
    elseif step~="start" and step~="choose" and step~="running" and step~="reroll" and step~="confirm" then
        self:SetState(State.Advance(Storage.tutorial,"continue",game))
    end
    self:Present()
end
function Tutorial:Present()
    if not self:Active() then self.overlay:Hide();return end
    local key=self.milestone~="" and self.milestone or Storage.tutorial.step
    local source=specs[key=="review" and "choose" or key]
    if not source then self.overlay:Hide();return end
    local spec={};for k,v in pairs(source) do spec[k]=v end;spec.key=key
    if key=="running" and self.view.game.phase~="running" then
        spec.key="settling";spec.text="时间到！等物品落稳，看看这一回合赚了多少金币。"
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
