-- Approved v5 composition: independent lit sprite planes, UI text and hit targets.
-- UI owns DPR, hit testing and gestures. No thick cabinet mesh.
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local Sprites=require("Machine.LayeredSprites")
local Reels=require("Machine.FlatReelState")
local LitScene=require("Machine.LitSpriteScene")
local Clock=require("Machine.Clock")
local Items=require("Bottle.Items")
local Money=require("Bottle.Money")
local ItemText=require("Bottle.ItemText")
local ItemDetail=require("Bottle.ItemDetail")
local RefreshUI=require("Bottle.RefreshUI")
local Art=require("Bottle.Art")
local Atmosphere=require("Machine.Atmosphere")
local Storage=require("Bottle.Storage")
local ButtonMotion=require("Bottle.ButtonMotion")
local ScreenAssembly=require("Machine.ScreenAssembly")
local PageMotion=require("Machine.PageMotion")
local TargetProgress=require("Machine.TargetProgress")
local TargetSwap=require("Machine.TargetSwap")
local GameAudio=require("Bottle.Audio")
local RelicView=require("Bottle.RelicView")
local DeductionNote=require("Machine.DeductionNote")
local DeveloperOverlay=require("Machine.DeveloperOverlay")
local RulesUI=require("Bottle.RulesUI")
---@type any
local Skin={}
local ink={226,214,174,255}
local muted={133,145,122,255}
local clear={0,0,0,0}
local selectedInk={39,29,12,255}
-- 品质是物品元数据；选中黄底统一使用，不能被误认作传说品质。
local qualityColors={{224,224,211,255},{80,200,120,255},{69,170,242,255},
    {167,122,245,255},{255,205,74,255}}

-- 欠阻尼弹簧的解析步进：低帧率／大 dt 也不靠逐帧累积爆振。
local function spring(value,velocity,target,dt)
    local damping,frequency=8,20
    local wave=math.sqrt(frequency*frequency-damping*damping)
    local delta=value-target
    local c,s=math.cos(wave*dt),math.sin(wave*dt)
    local decay=math.exp(-damping*dt)
    return target+decay*(delta*c+(velocity+damping*delta)/wave*s),
        decay*(velocity*c-(damping*velocity+frequency*frequency*delta)/wave*s)
end
local function syncDraftVisual(view,index,pose)
    local visual=view.machineSkin.draftVisuals and view.machineSkin.draftVisuals[index]
    if not visual then return end
    local pressed=visual.button.state.pressed and not visual.button.props.disabled
    visual.motion:SetStyle({translateY=(pose.y+(pressed and 2 or 0))*view.machineSkin.scale})
    visual.tilt:SetStyle({rotate=math.deg(pose.angle+pose.hover.angle),scale=pose.hover.scale})
end
function Skin.TickDraft(view,dt)
    local m=view.machineSkin
    if not m or not m.draftMotion then return end
    local paused=view.game.phase~="draft" or not view.draft:IsVisible()
        or view.modal:IsVisible() or view.definitionModal:IsVisible()
    for index,pose in ipairs(m.draftMotion) do
        local visual=m.draftVisuals and m.draftVisuals[index]
        if paused then
            ButtonMotion.Reset(pose.hover)
        else
            local target=index==view.draftSelected and -12 or 0
            pose.y,pose.velocity=spring(pose.y,pose.velocity,target,math.max(0,dt))
            pose.angle,pose.angularVelocity=spring(pose.angle,pose.angularVelocity,0,math.max(0,dt))
            if math.abs(pose.y-target)<.005 and math.abs(pose.velocity)<.02 then pose.y=target;pose.velocity=0 end
            if math.abs(pose.angle)<.0001 and math.abs(pose.angularVelocity)<.001 then pose.angle=0;pose.angularVelocity=0 end
            local page=visual and visual.button.pageEntry
            local selectionBusy=index==view.draftSelected or math.abs(pose.y)>.005 or math.abs(pose.angle)>.0001
                or (page and (math.abs(page.pose.y)>.05 or math.abs(page.pose.angle)>.0002))
            ButtonMotion.Step(pose.hover,visual and ButtonMotion.IsHovered(visual.button) or false,selectionBusy==true,dt)
        end
        syncDraftVisual(view,index,pose)
    end
end
local function clearDraftMotion(m)
    m.draftVisuals=nil
    m.draftMotionKey=nil;m.draftMotion=nil;m.draftMotionByItem=nil
    m.draftMotionOptions=nil;m.draftMotionSelected=nil
end
local function prepareDraftMotion(view,DraftValue)
    local m=view.machineSkin
    -- 回合／刷新决定组生命周期；GM 过滤旧组选项不等于重抽。
    -- 同一回合内物品组会切到遗物组，必须区分两种候选的动画生命周期。
    local key=tostring(view.game.round)..":"..tostring(view.game.relicDraft==true)
        ..":"..tostring(RefreshUI.Count(view.game))..":"..tostring(view.game.refreshUsed)
    if m.draftMotionKey~=key then
        m.draftMotionKey=key;m.draftMotionByItem={};m.draftMotionSelected=nil
        m.draftMotionOptions=nil
    end
    local keys={}
    for _,option in ipairs(view.game.options) do
        local id=DraftValue(view.game,option)
        keys[#keys+1]=id..":"..tostring(type(option)=="table" and option.uid or "new")
    end
    local optionsKey=table.concat(keys,"|")
    if m.draftMotionOptions~=optionsKey then
        local poses,byItem={},{}
        for _,itemKey in ipairs(keys) do
            local pose=m.draftMotionByItem[itemKey]
                or {y=0,velocity=0,angle=0,angularVelocity=0,hover=ButtonMotion.NewPose()}
            poses[#poses+1]=pose;byItem[itemKey]=pose
        end
        m.draftMotion=poses;m.draftMotionByItem=byItem
        m.draftMotionOptions=optionsKey
    end
    local selectedKey=keys[view.draftSelected]
    if m.draftMotionSelected~=selectedKey then
        local pose=m.draftMotion[view.draftSelected]
        pose.hover.angle=0;pose.hover.angularVelocity=0
        pose.velocity=-45
        pose.angularVelocity=(view.draftSelected%2==0 and 1 or -1)*2.2
        m.draftMotionSelected=selectedKey
    end
end
local function animateDraftIcon(view,icon,pose,large)
    local render=icon.Render
    icon.draftPose=pose
    function icon:Render(vg)
        local b=self:GetAbsoluteLayout()
        local factor=math.max(0,math.min(1.3,-pose.y/12))
        local cx,cy=b.x+b.w/2,b.y+b.h/2
        nvgSave(vg)
        nvgTranslate(vg,cx,cy+(large and pose.y*view.machineSkin.scale*.65 or 0))
        if large then nvgRotate(vg,pose.angle*.6) end
        local zoom=1+.16*factor
        nvgScale(vg,zoom,zoom);nvgTranslate(vg,-cx,-cy)
        render(self,vg)
        nvgRestore(vg)
    end
end
local function qualityLabel(rarity,size,s,id)
    return UI.Label{id=id,text=Items.rarityNames[rarity],fontSize=size*s,
        fontColor=qualityColors[rarity],backgroundColor={20,24,24,245},
        textMotionDisabled=true,textAlign="center",verticalAlign="middle",
        padding=0,pointerEvents="none"}
end

-- 父容器已合并系统安全区与TapTap胶囊；直接读取Yoga样式，不能用滞后的props／布局结果。
local function contentArea(safe)
    local left=YGNodeStyleGetPadding(safe.node,YGEdgeLeft).value
    local top=YGNodeStyleGetPadding(safe.node,YGEdgeTop).value
    local right=YGNodeStyleGetPadding(safe.node,YGEdgeRight).value
    local bottom=YGNodeStyleGetPadding(safe.node,YGEdgeBottom).value
    return UI.GetWidth()-left-right,UI.GetHeight()-top-bottom,left,top,right,bottom
end
local function scale(safe)
    local w,h=contentArea(safe)
    return math.max(.01,math.min(w/L.width,h/L.height,1.65))
end
local function place(widget,rect,s)
    widget:SetStyle(L.Style(rect,s))
end
local function fill(vg,x,y,w,h,c)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(c[1],c[2],c[3],c[4] or 255));nvgFill(vg)
end
-- Five by seven glyphs are genuinely discrete pixels, including decimal/sign/exponent.
local glyphs={
    ["0"]={14,17,19,21,25,17,14},["1"]={4,12,4,4,4,4,14},
    ["2"]={14,17,1,2,4,8,31},["3"]={30,1,1,14,1,1,30},
    ["4"]={2,6,10,18,31,2,2},["5"]={31,16,16,30,1,1,30},
    ["6"]={14,16,16,30,17,17,14},["7"]={31,1,2,4,8,8,8},
    ["8"]={14,17,17,14,17,17,14},["9"]={14,17,17,15,1,1,14},
    ["."]={0,0,0,0,0,6,6},["-"]={0,0,0,31,0,0,0},
    ["+"]={0,4,4,31,4,4,0},["e"]={0,0,14,17,31,16,14},
}
local function glyph(vg,char,x,y,p,c)
    for row,bits in ipairs(glyphs[char] or glyphs["-"]) do
        for col=0,4 do
            if bits&(1<<(4-col))~=0 then fill(vg,x+col*p,y+(row-1)*p,p,p,c) end
        end
    end
end
local function panel(view,kind,rect,z,frameOnly)
    local m=view.machineSkin
    local widget=UI.Widget{pointerEvents="none",zIndex=z or 1} --[[@as any]]
    function widget:Render(vg)
        local b=self:GetAbsoluteLayout()
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        local elevation=kind=="felt" and -.03 or -.02-.03*(z or 1)
        m.sprites:Panel(vg,kind,b.x,b.y,b.w,b.h,m.scale,frameOnly,elevation)
        nvgRestore(vg)
    end
    m.placements[#m.placements+1]={widget=widget,rect=rect}
    view.container:AddChild(widget)
    return widget
end
local function labelStyle(widget,size,s)
    widget:SetStyle({fontSize=size*s,fontColor=ink,textAlign="center",verticalAlign="middle",
        textShadow=false,pointerEvents="none",padding=0})
end
local function buttonStyle(button,size,s)
    button:SetStyle({fontSize=size*s,paddingHorizontal=6*s,paddingVertical=0,
        backgroundColor=clear,hoverBackgroundColor={210,220,190,15},pressedBackgroundColor={0,0,0,35},
        disabledBackgroundColor={0,0,0,65},textColor=ink,disabledTextColor=muted,
        borderWidth=0,borderRadius=0,boxShadow=false,hoverBoxShadow=false,
        pressedBoxShadow=false,disabledBoxShadow=false})
end
-- decor 返回 true 表示它自绘了整块底图：跳过九宫格底板，避免叠在下面露出边角。
local function spriteButton(view,button,kind,size,decor,elevation)
    buttonStyle(button,size,view.machineSkin.scale)
    if button.layeredFace then return end
    button.layeredFace=true
    local render=button.Render
    button.Render=function(b,vg)
        local l=b:GetAbsoluteLayout()
        local s=view.machineSkin.scale
        nvgSave(vg)
        local pressed=b.state.pressed and not b.props.disabled
        local offset=pressed and 2*s or 0
        local replaces=decor and decor(b,vg,l,s,true) or false
        if not replaces then
            view.machineSkin.sprites:Panel(vg,kind,l.x,l.y,l.w,l.h,s,nil,elevation,
                PageMotion.Transform(b,l,ButtonMotion.Transform(b,l,offset)))
        end
        if pressed then nvgTranslate(vg,0,offset) end
        -- 底图先画，文字后画；两者同在按下偏移内，共用同一仿射变换与裁剪窗。
        if decor then decor(b,vg,l,s,false) end
        render(b,vg)
        nvgRestore(vg)
    end
end

-- 与右侧状态牌共用页面动效；准备阶段由同位置的重抽按钮接替。
local function phaseClock(view)
    local clock=UI.Widget{id="phaseClock",pointerEvents="none"} --[[@as any]]
    function clock:Render(vg)
        local m=view.machineSkin
        local b=self:GetAbsoluteLayout();local s=m.scale
        m.sprites:Panel(vg,"metal",b.x,b.y,b.w,b.h,s,nil,-.23,
            PageMotion.Transform(self,b,{cx=b.x+b.w/2,cy=b.y+b.h/2,y=0,angle=0,scale=1}))
        if not m.clock.visible then return end
        local text=Clock.Format(m.clock.centis)
        local p=math.min(22*s/7,(b.w-28*s)/(#text*6-1))
        local x=b.x+(b.w-(#text*6-1)*p)/2
        local y=b.y+(b.h-7*p)/2
        local color=m.clock.phase=="running" and ink or {205,103,83}
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        for i=1,#text do glyph(vg,text:sub(i,i),x+(i-1)*6*p,y,p,color) end
        nvgRestore(vg)
    end
    return clock
end

-- 牌库入口：袋子取代木底板，文字直接写在袋身上。
-- 纵向略微内收，避免束口顶端被按钮上沿切掉。
local function deckButtonDecor(b,vg,l,s,probe)
    if probe then return true end
    local inset=2*s
    Art.DeckPlate(vg,l.x,l.y+inset,l.w,l.h-inset,b.props.disabled)
end

-- 收藏切换复用机台九宫格、受光与页面/悬停的同源变换。
local function inventoryTabDecor(button,vg,b,s,probe)
    if probe then return true end
    local selected=button.inventoryTabKey==button.inventoryView.inventoryTab
    local pressed=button.state.pressed and not button.props.disabled
    button.inventoryView.machineSkin.sprites:Panel(vg,selected and "green" or "wood",
        b.x,b.y,b.w,b.h,s,nil,-.12,
        PageMotion.Transform(button,b,ButtonMotion.Transform(button,b,pressed and 2*s or 0)))
end

function Skin.AttachInventoryTabs(view)
    local m=view.machineSkin
    m.inventoryButtons={}
    for _,entry in ipairs({{"items","inventoryItems",L.inventoryItems,.08},
        {"relics","inventoryRelics",L.inventoryRelics,.14}}) do
        local key=entry[1]
        local button=GameAudio.Button{id=entry[2],text="",textMotionDisabled=true,
            zIndex=9,onClick=function() view:SwitchInventoryTab(key) end} --[[@as any]]
        button.inventoryTabKey=key;button.inventoryView=view
        place(button,entry[3],m.scale)
        spriteButton(view,button,"wood",18,inventoryTabDecor)
        view.container:AddChild(button)
        m.inventoryButtons[key]=button
        m.pageMotion:Attach(button,"inventory-"..key,"deckpage",entry[3],"bottom",entry[4])
    end
end

function Skin.InventoryTabs(view)
    local m=view.machineSkin
    if not m or not m.inventoryButtons then return end
    local deckOpen=view.inventoryOpen and view.modal:IsVisible()
    local changed=deckOpen and m.inventoryActive~=nil and m.inventoryActive~=view.inventoryTab
    local resized=m.inventoryButtonsScale~=m.scale
    local counts={items=#view.game.deck,relics=#RelicView.Entries(view.game)}
    for _,entry in ipairs({{"items","物品",L.inventoryItems},{"relics","遗物",L.inventoryRelics}}) do
        local key=entry[1]
        local button=m.inventoryButtons[key]
        if resized then
            place(button,entry[3],m.scale)
            buttonStyle(button,18,m.scale)
        end
        local text=entry[2].." · "..counts[key]
        if button.props.text~=text then button:SetText(text) end
        -- 只在实际切换时补一次选中回弹；持久按钮保留悬停/页面弹簧与指针门控。
        if changed and key==view.inventoryTab and button.hoverPose then
            local pose=button.hoverPose
            pose.scale=.94;pose.velocity=1.8
            pose.angularVelocity=key=="items" and -1.5 or 1.5
        end
    end
    m.inventoryButtonsScale=m.scale
    m.inventoryActive=deckOpen and view.inventoryTab or nil
end

function Skin.Apply(view,title,help,save,gm)
    RulesUI.Attach(view,help)
    local old=view.container
    local safe=old.parent
    ---@type any
    local m={safe=safe,scale=scale(safe),sprites=Sprites.New(),reels=Reels.New(),placements={},
        clock={phase="prepare",centis=1000,flashElapsed=-1,visible=true},help=help,save=save,gm=gm}
    view.machineSkin=m
    -- 复用SafeAreaView的差量更新；原生同尺寸下也检查延迟出现／消失的胶囊。
    safe.pollInterval_=0.5
    local updateSafe=safe.Update
    safe.Update=function(self,dt)
        updateSafe(self,dt)
        Skin.Resize(view)
    end
    m.litScene=LitScene.New()
    m.sprites.scene=m.litScene
    -- Compatibility with the existing end-of-round flash gate; no scene is constructed.
    m.cabinet={clock=m.clock}
    function m.clock:Tick(dt)
        if self.flashElapsed<0 then return end
        -- 红色闪动持续到阶段切换（draft/over 时由 Update 复位），不再固定时长后自停。
        self.flashElapsed=self.flashElapsed+math.max(dt,0)
        self.visible=math.floor(self.flashElapsed/.14)%2==0
    end
    view.container=UI.Panel{width=L.width*m.scale,height=L.height*m.scale,alignSelf="center"}
    m.pageMotion=PageMotion.New(view)
    -- 牌库页的返回按钮：与底部操作按钮共用同一弹簧拉出／收回。
    view.deckBackButton=GameAudio.Button{id="deckBack",text="返回",onClick=function()
        view:DeckBack()
    end}
    place(view.deckBackButton,L.deckBack,m.scale)
    view.deckBackButton:SetStyle({zIndex=9})
    spriteButton(view,view.deckBackButton,"wood",18)
    view.container:AddChild(view.deckBackButton)
    m.pageMotion:Attach(view.deckBackButton,"deck-back","deckpage",L.deckBack,"bottom",.03)
    Skin.AttachInventoryTabs(view)
    -- 左上角返回主菜单：与牌库/重抽同一套 wood 九宫格按钮风格。
    view.mainMenuButton=GameAudio.Button{id="mainMenu",text="主菜单",onClick=function()
        if view.startScreen and view.startScreen.Open then view.startScreen:Open() end
    end}
    view.mainMenuButton:SetStyle({zIndex=9})
    spriteButton(view,view.mainMenuButton,"wood",15)
    view.container:AddChild(view.mainMenuButton)
    local bg=UI.Widget{position="absolute",left=0,top=0,width="100%",height="100%",pointerEvents="none"} --[[@as any]]
    function bg:Render(vg)
        local b=self:GetAbsoluteLayout()
        m.litScene:Begin(vg,b,m.scale)
        m.sprites:Draw(vg,"desk",b.x,b.y,b.w,b.h,228*m.scale,220*m.scale)
    end
    bg.Update=function(_,dt)
        m.reels:Tick(dt)
        m.clock:Tick(dt)
        m.litScene:Tick(dt)
        TargetProgress.Update(view,dt)
        TargetSwap.Sync(view)
        m.targetSwap:Tick(dt)
        m.deductionNote:Tick(dt)
        -- UI与玩法Update的订阅次序不同也不能让换牌时的数字落后一帧。
        view.goalLabel:SetText(Money.Format(TargetSwap.Value(view)))
        Skin.FitNumbers(view)
        Skin.TickDraft(view,dt)
        m.pageMotion:Tick(dt)
        -- UI applies the same reference-plane movement, including inverse hit tests.
        view.container:SetStyle({translateX=(m.litScene.motionX+m.litScene.shakeX)*m.scale,
            translateY=(m.litScene.motionY+m.litScene.shakeY)*m.scale})
    end
    local destroy=bg.Destroy
    bg.Destroy=function(w) m.pageMotion.entries={};m.sprites:Dispose();m.litScene:Dispose();destroy(w) end
    view.container:AddChild(bg)
    panel(view,"felt",L.felt,1)
    panel(view,"wood",L.round,1)
    m.targetBase=panel(view,"metal",L.lamps,1)
    m.targetBase.id="targetProgressBase"
    local score=panel(view,"metal",L.score,2)
    score.id="scoreSummary"
    local scoreFace=score.Render
    function score:Render(vg)
        scoreFace(self,vg)
        local b=self:GetAbsoluteLayout()
        local s=m.scale
        local text=m.reels.text
        if #text==0 then return end
        local cell=(b.w-32*s)/#text
        local p=math.min(4*s,cell/7)
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        for column=1,#text do
            local x=b.x+16*s+(column-1)*cell
            local top=b.y+18*s
            fill(vg,x,top,cell-2*s,40*s,{11,19,16})
            fill(vg,x,top,cell-2*s,s,{105,115,94})
            nvgSave(vg);nvgIntersectScissor(vg,x+2*s,top+2*s,cell-6*s,36*s)
            local char=text:sub(column,column)
            local digit=m.reels.digits[#text-column+1]
            local cx=x+(cell-2*s-5*p)/2
            local cy=top+(40*s-7*p)/2
            if tonumber(char) and digit then
                local base=math.floor(digit.position)
                for offset=-1,2 do
                    glyph(vg,tostring((base+offset)%10),cx,cy+(offset-(digit.position-base))*40*s,p,ink)
                end
            else glyph(vg,char,cx,cy,p,ink) end
            nvgRestore(vg)
        end
        nvgRestore(vg)
    end
    TargetProgress.Attach(view)
    panel(view,"screen",L.screen,2)
    for _,w in ipairs({view.board,view.roundLabel,view.goalLabel,view.deckButton,view.footer,
        view.detailOverlay,view.definitionModal,view.draft,view.modal,help,save,gm,view.physicsButton,view.physicsMenu}) do
        view.container:AddChild(w)
    end
    -- Hidden retained controls remain valid for Bottle.View's updates and assertions.
    for _,w in ipairs({view.scoreLabel,view.progress,view.timer,view.badgeLabel,view.statusLabel,title}) do
        view.container:AddChild(w);w:Hide()
    end
    view.board.layered=true
    view.board:SetStyle({zIndex=3})
    view.board.RenderFullBackground=function(b,vg)
        local r=b:GetAbsoluteLayout()
        local tileW,tileH=m.sprites:CenterTile("screen",m.scale)
        m.sprites:Draw(vg,"screen-5",r.x,r.y,r.w,r.h,tileW,tileH)
        -- Atmosphere selection remains available, restricted to glass instead of recoloring metal.
        local mood=Atmosphere.Resolve(Storage.atmosphereMode)
        if mood=="slate" then fill(vg,r.x,r.y,r.w,r.h,{39,75,100,28})
        elseif mood=="ember" then fill(vg,r.x,r.y,r.w,r.h,{92,42,27,22}) end
    end
    panel(view,"screen",L.screen,4,true)
    ScreenAssembly.Attach(view)
    -- 数字倒计时仅随进行中的底部状态牌显示，计时灯条不再绘制。
    view.roundLabel:SetStyle({zIndex=2})
    view.goalLabel:SetStyle({zIndex=4})
    m.targetCaption=UI.Label{text="目标",pointerEvents="none",zIndex=4,fontColor={190,160,106,255}}
    view.container:AddChild(m.targetCaption)
    TargetSwap.Attach(view)
    DeductionNote.Attach(view)
    view.deckButton:SetStyle({zIndex=8})
    view.footer:SetStyle({zIndex=8,pointerEvents="box-none"})
    for _,b in ipairs({help,save,gm,view.physicsButton}) do b:SetStyle({zIndex=40}) end
    -- 表现开关集中在小型列表中，展开时仍可直接观察机台。
    m.presentationMenu=UI.Panel{id="presentationGmMenu",position="absolute",left=0,top=0,
        width="100%",height="100%",visible=false,zIndex=42,backgroundColor=clear,
        onPointerDown=function(event,widget)
            if event.target==widget then
                widget:Hide();event:StopPropagation();event:PreventDefault()
            end
        end}
    m.presentationPanel=UI.Panel{position="absolute",padding=8,gap=6,
        backgroundColor={18,25,22,250},borderWidth=1,borderColor={94,96,97,255}}
    m.presentationPanel:AddChild(UI.Label{text="表现GM · 即时开关",fontSize=12,fontColor=ink,
        textMotionDisabled=true,pointerEvents="none"})
    m.presentationToggles={}
    for _,entry in ipairs({{"noise","纹理噪点"},{"bloom","泛光"},
        {"edges","前景／暗角"},{"camera","镜头动画"},{"dust","浮尘"}}) do
        local key,caption=entry[1],entry[2]
        local function enabled()
            if key=="noise" then return m.litScene.noiseEnabled end
            if key=="camera" then return m.litScene.cameraMotionEnabled end
            if key=="dust" then return m.litScene.dustEnabled end
            return m.litScene.post[key]
        end
        local button=GameAudio.Button{id="presentationGm_"..key,textMotionDisabled=true,
            height=40,flexShrink=0,onClick=function(b)
                if key=="noise" then m.litScene:ToggleNoise()
                elseif key=="camera" then m.litScene:ToggleCameraMotion()
                elseif key=="dust" then m.litScene:ToggleDust()
                else m.litScene.post:Toggle(key) end
                local button=b --[[@as Button]]
                button:SetText(caption..(enabled() and "：开启" or "：关闭"))
                view.container:SetStyle({translateX=(m.litScene.motionX+m.litScene.shakeX)*m.scale,
                    translateY=(m.litScene.motionY+m.litScene.shakeY)*m.scale})
            end}
        button:SetText(caption..(enabled() and "：开启" or "：关闭"))
        m.presentationToggles[#m.presentationToggles+1]=button
        m.presentationPanel:AddChild(button)
    end
    m.presentationMenu:AddChild(m.presentationPanel)
    view.container:AddChild(m.presentationMenu)
    m.presentationButton=GameAudio.Button{id="presentationGm",text="表现GM",textMotionDisabled=true,
        zIndex=43,onClick=function()
            view.board:ResetShake()
            view:CloseItemDetail()
            view.physicsMenu:Hide()
            m.presentationMenu:SetVisible(not m.presentationMenu:IsVisible())
        end}
    view.container:AddChild(m.presentationButton)
    -- 机台在宽屏中央留白时，屏幕空白也应收起列表。
    view.root:OnEvent("pointerdown",function(event)
        if not m.presentationMenu:IsVisible() then return end
        local target=event.target
        while target do
            if target==m.presentationMenu or target==m.presentationButton then return end
            target=target.parent
        end
        m.presentationMenu:Hide();event:StopPropagation();event:PreventDefault()
    end)
    view.physicsMenu:SetStyle({zIndex=41})
    -- Finish collecting visible scene slices after the UI traversal; no fake FX overlay.
    local optics=UI.Widget{id="machineOptics",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=35} --[[@as any]]
    function optics:Render(vg)
        m.litScene:Finish(vg)
    end
    view.container:AddChild(optics)
    RelicView.Attach(view)
    safe:SetStyle({justifyContent="center",alignItems="center"})
    safe:AddChild(view.container)
    old:Destroy()
    Skin.Layout(view)
    -- Leave the scene visible behind transparent, independently lit UI pixels.
    view.root:SetStyle({backgroundColor=clear})
    -- NanoVG RTT preserves previous pixels: explicitly replace with transparent
    -- pixels before traversal, otherwise moving text accumulates frame trails.
    function view.root:Render(vg)
        nvgSave(vg)
        nvgGlobalCompositeOperation(vg,NVG_COPY)
        nvgBeginPath(vg);nvgRect(vg,0,0,UI.GetWidth(),UI.GetHeight())
        nvgFillColor(vg,nvgRGBA(0,0,0,0));nvgFill(vg)
        nvgRestore(vg)
    end
    DeveloperOverlay.Attach(view,gm)
    print("[Machine.Layered] 402x874 / independent sprite slices / flat animated slot reels")
end

function Skin.Layout(view)
    local m=view.machineSkin
    if not m then return end
    local s=scale(m.safe);m.scale=s
    view.container:SetStyle({width=L.width*s,height=L.height*s})
    for _,entry in ipairs(m.placements) do place(entry.widget,entry.rect,s) end
    place(view.board,L.board,s)
    view.board:SetStyle({minHeight=0,backgroundColor=clear})
    place(view.roundLabel,{102,34,74,32},s);labelStyle(view.roundLabel,14,s)
    place(view.mainMenuButton,{20,32,76,36},s)
    view.mainMenuButton:SetStyle({fontSize=15*s})
    place(m.targetCaption,{270,144,44,26},s);labelStyle(m.targetCaption,16,s)
    place(view.goalLabel,{316,142,62,30},s);labelStyle(view.goalLabel,22,s)
    place(view.deckButton,L.deck,s);spriteButton(view,view.deckButton,"wood",15,deckButtonDecor)
    -- 文字写在浅色袋身上：改用深色墨迹，并略下移落到袋腹。
    view.deckButton:SetStyle({paddingLeft=6*s,paddingRight=6*s,
        textColor=selectedInk,textShadow=false,paddingTop=8*s})
    place(view.deckBackButton,L.deckBack,s)
    view.deckBackButton:SetStyle({fontSize=18*s})
    Skin.InventoryTabs(view)
    -- Development tools are ordinary UI, deliberately separate from the painted machine.
    for i,b in ipairs({m.gm,m.save,view.physicsButton}) do
        place(b,{213+(i-1)*45,26,43,32},s)
        b:SetStyle({fontSize=11*s,padding=0,borderWidth=1,boxShadow=false,
            backgroundColor={24,30,27,235},textColor=ink,borderColor={94,96,97,255}})
    end
    RulesUI.Layout(view,m.help)
    view.physicsButton:SetText("物理")
    place(m.presentationButton,{308,74,84,30},s)
    m.presentationButton:SetStyle({fontSize=11*s,padding=0,borderWidth=1,boxShadow=false,
        backgroundColor={24,30,27,235},textColor=ink,borderColor={94,96,97,255}})
    place(m.presentationPanel,{190,100,202,272},s)
    m.presentationPanel:SetStyle({padding=8*s,gap=6*s})
    m.presentationPanel:GetChildren()[1]:SetStyle({fontSize=12*s,height=22*s})
    for _,b in ipairs(m.presentationToggles) do
        b:SetStyle({width="100%",height=40*s,fontSize=12*s,padding=0,borderWidth=1,
            boxShadow=false,backgroundColor={24,30,27,235},textColor=ink,borderColor={94,96,97,255}})
    end
    place(view.physicsMenu,{202,60,190,234},s)
    view.physicsMenu:SetStyle({padding=8*s,gap=6*s})
    for _,child in ipairs(view.physicsMenu:GetChildren()) do
        child:SetStyle({width="100%",fontSize=11*s})
        if child.props.onClick then child:SetStyle({height=42*s,paddingHorizontal=4*s}) end
    end
    -- Keep developer modals full-screen; inventory is confined to the shared CRT below.
    view.modal:SetStyle({padding=12*s})
    RelicView.Layout(view)
    Skin.Footer(view)
    if view.startScreen then view.startScreen:Layout() end
end

function Skin.Footer(view)
    local m=view.machineSkin
    if not m then return end
    local s=m.scale
    place(view.footer,{0,0,402,874},s)
    view.footer:SetStyle({padding=0,gap=0})
    local children=view.footer:GetChildren()
    local phase=view.game.phase
    if phase=="prepare" and children[1] then
        place(children[1],{0,0,402,874},s)
        children[1]:SetStyle({pointerEvents="box-none",padding=0,gap=0})
        local buttons=children[1]:GetChildren()
        if buttons[1] then
            place(buttons[1],L.reroll,s);spriteButton(view,buttons[1],"wood",14,nil,-.23)
            m.pageMotion:Attach(buttons[1],"prepare-reroll","footer",L.reroll,"bottom",.11)
        end
        if buttons[2] then
            -- 操作带叠在CRT下沿前方，沿用原计时铭牌的深度，避免顶边被屏框遮挡。
            place(buttons[2],L.start,s);spriteButton(view,buttons[2],"green",18,nil,-.23)
            m.pageMotion:Attach(buttons[2],"prepare-start","footer",L.start,"bottom",.03)
        end
        if children[2] then
            place(children[2],{20,844,362,22},s)
            labelStyle(children[2],11,s)
        end
    elseif (phase=="running" or phase=="settle" or phase=="reveal") and children[1] then
        place(children[1],L.start,s);labelStyle(children[1],16,s)
        if not children[1].layeredStatus then
            local render=children[1].Render
            children[1].Render=function(w,vg)
                local b=w:GetAbsoluteLayout()
                m.sprites:Panel(vg,"green",b.x,b.y,b.w,b.h,m.scale,nil,-.23,
                    PageMotion.Transform(w,b,{cx=b.x+b.w/2,cy=b.y+b.h/2,y=0,angle=0,scale=1}))
                render(w,vg)
            end
            children[1].layeredStatus=true
        end
        m.pageMotion:Attach(children[1],phase=="running" and "running-status" or "settle-status",
            "footer",L.start,"bottom",.17)
        local clock=view.footer:FindById("phaseClock")
        if not clock then
            clock=phaseClock(view)
            view.footer:AddChild(clock)
        end
        place(clock,L.reroll,s)
        m.pageMotion:Attach(clock,"phase-clock","footer",L.reroll,"bottom",.11)
    elseif phase=="draft" and children[1] then
        local rect={26,662,354,52}
        place(children[1],rect,s);spriteButton(view,children[1],"green",18,nil,-.23)
        m.pageMotion:Attach(children[1],"draft-show","footer",rect,"bottom",.06)
    elseif phase=="over" then
        if children[1] then place(children[1],{28,744,348,28},s);labelStyle(children[1],12,s) end
        if children[2] then
            local rect={196,780,190,60}
            place(children[2],rect,s);spriteButton(view,children[2],"green",20)
            m.pageMotion:Attach(children[2],"over-restart","footer",rect,"bottom",.08)
        end
    end
    Skin.SyncPages(view)
end

-- Visibility is driven by the displayed page, not just the round phase.
-- A hidden footer also loses its hit targets; the old wide action cannot sit
-- behind the three independent draft slots and intercept their empty spaces.
function Skin.SyncPages(view)
    local m=view.machineSkin
    if not m then return end
    local deckOpen=view.inventoryOpen and view.modal:IsVisible()
    Skin.InventoryTabs(view)
    -- 三选一页本身处于展示状态；牌库页打开时暂时接管屏幕与底部操作区。
    local draftPage=view.game.phase=="draft" and (view.draft:IsVisible() or view.deckDraftWasOpen)
    local drafting=draftPage and not deckOpen
    if deckOpen and view.draft:IsVisible() then view.draft:Hide() end
    local deckRect=draftPage and L.draftDeck or L.deck
    local deck=m.pageMotion.entries.deck
    if deck then
        if deck.rect[2]~=deckRect[2] then
            deck.pose.y=deck.pose.y+deck.rect[2]-deckRect[2]
            deck.interactive=false
            deck.settled=false
            -- 跨页换位也要作废旧按下，不能等动画停稳后触发上页点击／音效。
            deck.presses={};deck.inputVersion=deck.inputVersion+1
            if deck.widget.state then deck.widget.state.pressed=false end
        end
        deck.rect=deckRect
    end
    view.footer:SetVisible(not draftPage and not deckOpen)
    view.board:SetVisible(not draftPage)
    RelicView.SetVisible(view,not draftPage and not deckOpen and view.game.phase~="over")
    local props=view.deckButton.props
    if props.left~=deckRect[1]*m.scale or props.top~=deckRect[2]*m.scale
        or props.width~=deckRect[3]*m.scale or props.height~=deckRect[4]*m.scale then
        place(view.deckButton,deckRect,m.scale)
    end
    m.pageMotion:Attach(view.deckButton,"deck","deck",deckRect,"screen",.02)
    m.pageMotion:Targets(drafting,deckOpen)
end
function Skin.SetDraftOpen(view,open)
    view.choiceHidden=not open
    view.draft:SetVisible(open and view.machineSkin.clock.flashElapsed<0)
    Skin.SyncPages(view)
end

function Skin.FitNumbers(view)
    local size=math.min(22,92/math.max(2,#Reels.Literal(TargetSwap.Value(view))))*view.machineSkin.scale
    if view.goalLabel.props.fontSize~=size then view.goalLabel:SetStyle({fontSize=size}) end
end

function Skin.TargetValue(view) return TargetSwap.Value(view) end

-- The three choices are separate trays below the CRT; the selected description
-- and all scrollable prose occupy the same screen used by the bottle/inventory.
function Skin.BuildDraft(view,Icon,Description,DraftValue,ItemStats)
    local m=view.machineSkin
    local s=m.scale
    m.pageMotion:Clear("draft")
    local old=view.draft:GetChildren()
    m.draftVisuals={}
    for i=#old,1,-1 do old[i]:Destroy() end
    view.draft:ClearChildren()
    view.draft:SetStyle({backgroundColor=clear,pointerEvents="box-none",padding=0})
    place(view.draft,{0,0,402,874},s)
    local selected=math.max(1,math.min(view.draftSelected or 1,#view.game.options))
    view.draftSelected=selected
    local option=view.game.options[selected]
    if not option then clearDraftMotion(m);view.draft:Hide();return end
    local id,gold,def=DraftValue(view.game,option)
    local relicDraft=view.game.relicDraft==true
    prepareDraftMotion(view,DraftValue)
    local screen=UI.Panel{id="draftDisplay",padding=0,backgroundColor={12,32,25,255},overflow="hidden"}
    place(screen,L.board,s)
    local icon=Icon{id="draftPreviewIcon",itemId=id,isRelic=relicDraft,
        rollValue=type(option)=="table" and option.rollValue or nil,
        woolCount=type(option)=="table" and option.woolCount or nil,
        width=88*s,height=88*s,pointerEvents="none"}
    animateDraftIcon(view,icon,m.draftMotion[selected],true)
    local detail=ItemDetail.Create{prefix="draft",scale=s,def=def,isRelic=relicDraft,icon=icon,
        caption=relicDraft and "挑选下一件遗物" or "挑选下一件物品",
        meta="候选 "..selected.." / "..#view.game.options,
        valueCaption=type(option)=="table" and "当前收益" or "初始收益",
        gold=gold,
        descriptionId="draftDescription_"..selected,
        effect=relicDraft and def.effect or ItemText.Effect(view.game,id,
            type(option)=="table" and option or nil),
        onInspect=function(itemId) view:InspectDefinition(itemId) end}
    detail:SetStyle({height="auto",flexGrow=1,flexBasis=0})
    screen:AddChild(detail)
    local refreshHint=UI.Label{id="refreshPoolHint",text=RefreshUI.Hint(view.game),
        textMotionDisabled=true,fontSize=11*s,fontColor=muted,pointerEvents="none"}
    refreshHint:SetStyle({width="100%",paddingHorizontal=16*s,paddingBottom=8*s})
    screen:AddChild(refreshHint)
    view.draft:AddChild(screen)
    for index,choice in ipairs(view.game.options) do
        local itemId,_,itemDef=DraftValue(view.game,choice)
        local button=GameAudio.Button{id="draftSlot_"..index,text="",onClick=function()
            if view.inventoryOpen or view.draftSelected==index then return end
            if view.tutorial and not view.tutorial:Allows("switch") then return end
            view.draftSelected=index;view:BuildDraft()
            if view.tutorial then view.tutorial:OnSwitched() end
        end}
        place(button,L.draftSlots[index],s)
        local isSelected=index==selected
        button.draftSelected=isSelected
        button.draftMaterial=isSelected and "gold" or "metal"
        buttonStyle(button,12,s)
        -- Button 只保留固定命中区；视觉子树整块抬升和回摆。
        button:SetStyle({hoverBackgroundColor=clear,pressedBackgroundColor=clear})
        local motion=UI.Panel{id="draftMotion_"..index,position="absolute",left=0,top=0,
            width="100%",height="100%",padding=0,backgroundColor=clear,pointerEvents="none"}
        local face=UI.Panel{id="draftFace_"..index,width="100%",height="100%",padding=0,
            backgroundColor=clear,transformOrigin="center",pointerEvents="none"} --[[@as any]]
        local pose=m.draftMotion[index]
        ButtonMotion.Attach(button,pose.hover,true)
        button.hoverBlocked=function() return view.inventoryOpen or view.modal:IsVisible()
            or view.definitionModal:IsVisible() end
        face.draftPose=pose
        m.draftVisuals[index]={button=button,motion=motion,tilt=face}
        motion:AddChild(face);button:AddChild(motion)
        syncDraftVisual(view,index,pose)
        function face:Render(vg)
            local b=self:GetAbsoluteLayout()
            local transform={cx=b.x+b.w/2,cy=b.y+b.h/2,
                y=motion.props.translateY or 0,angle=math.rad(self.props.rotate or 0),scale=self.props.scale or 1}
            m.sprites:Panel(vg,button.draftMaterial,b.x,b.y,b.w,b.h,m.scale,nil,nil,
                PageMotion.Transform(button,b,transform))
        end
        local width=L.draftSlots[index][3]
        local shadow=UI.Widget{position="absolute",left=0,top=0,width="100%",height="100%",
            pointerEvents="none"} --[[@as any]]
        function shadow:Render(vg)
            local b=self:GetAbsoluteLayout()
            fill(vg,b.x+b.w/2-11*s,b.y+37*s,22*s,4*s,{24,24,16,115})
        end
        face:AddChild(shadow)
        local itemIcon=Icon{id="draftIcon_"..index,itemId=itemId,isRelic=relicDraft,
            rollValue=type(choice)=="table" and choice.rollValue or nil,
            woolCount=type(choice)=="table" and choice.woolCount or nil,position="absolute",zIndex=1,
            left=(width-36)*.5*s,top=9*s,width=36*s,height=36*s,pointerEvents="none"}
        animateDraftIcon(view,itemIcon,m.draftMotion[index],false)
        face:AddChild(itemIcon)
        face:AddChild(UI.Label{text=itemDef.name,id="draftName_"..index,position="absolute",left=8*s,top=41*s,
            width=(width-16)*s,height=22*s,fontSize=10*s,fontColor=isSelected and selectedInk or ink,
            textAlign="center",verticalAlign="middle",pointerEvents="none"})
        local badge=qualityLabel(itemDef.rarity,9,s,"draftQuality_"..index)
        place(badge,{(width-46)/2,64,46,17},s);face:AddChild(badge)
        view.draft:AddChild(button)
        local pageKey="slot:"..m.draftMotionKey..":"..itemId..":"
            ..tostring(type(choice)=="table" and choice.uid or "new")
        m.pageMotion:Attach(button,pageKey,"draft",L.draftSlots[index],"screen",.04+(index-1)*.065)
    end
    local function action(id,text,rect,kind,size,callback)
        local button=GameAudio.Button{id=id,text=text,onClick=function()
            if not view.inventoryOpen then callback() end
        end}
        button.hoverBlocked=function() return view.inventoryOpen or view.modal:IsVisible()
            or view.definitionModal:IsVisible() end
        place(button,rect,s);spriteButton(view,button,kind,size)
        view.draft:AddChild(button)
        local delays={draftHide=.01,draftRefresh=.22,draftSkip=.285,draftConfirm=.35}
        m.pageMotion:Attach(button,id,"draft",rect,id=="draftHide" and "screen" or "bottom",delays[id])
        return button
    end
    action("draftHide","收起候选",L.draftHide,"wood",12,function() Skin.SetDraftOpen(view,false) end)
    action("draftConfirm",relicDraft and "选择此遗物" or "选择此物品",L.draftConfirm,"green",17,
        function() view.actions.choose(selected) end)
    local refresh=action("draftRefresh",RefreshUI.ButtonText(view.game),
        L.draftRefresh,"wood",12,function() view.actions.refresh() end)
    refresh:SetDisabled(RefreshUI.Count(view.game)<=0)
    action("draftSkip","跳过",L.draftSkip,"metal",11,function() view.actions.skip() end)
    view.draft:SetVisible(not view.choiceHidden and m.clock.flashElapsed<0)
    Skin.SyncPages(view)
end

function Skin.Modal(view,panel,inScreen)
    local s=view.machineSkin.scale
    DeveloperOverlay.ApplyOpacity(view)
    view.machineSkin.modalPanel=panel
    view.machineSkin.modalInScreen=inScreen
    if inScreen then
        place(view.modal,L.board,s)
        view.modal:SetStyle({right="auto",bottom="auto",padding=0,backgroundColor={12,32,25,255}})
        -- 牌库沙盒铺满中部区域：面板本身不再内缩，文字页各自留内边距。
        panel:SetStyle({height="100%",padding=0,gap=0,borderWidth=0,boxShadow=false,
            backgroundColor={12,32,25,255}})
    else
        place(view.modal,{0,0,402,874},s)
        view.modal:SetStyle({right="auto",bottom="auto",padding=12*s,backgroundColor={9,13,11,220}})
    end
end
function Skin.Resize(view)
    local m=view.machineSkin
    if not m then return end
    local w,h,left,top,right,bottom=contentArea(m.safe)
    if m.contentW==w and m.contentH==h and m.safeLeft==left and m.safeTop==top
        and m.safeRight==right and m.safeBottom==bottom then return end
    m.contentW,m.contentH=w,h
    m.safeLeft,m.safeTop,m.safeRight,m.safeBottom=left,top,right,bottom
    -- 只有padding改变也必须标脏：SafeAreaView直接写Yoga，不会通知UI层。
    UI.MarkLayoutDirty()
    if math.abs(m.scale-scale(m.safe))>0.000001 then
        Skin.Layout(view)
        if view.game.phase=="draft" then view:BuildDraft() end
        if view.modal:IsVisible() and m.modalPanel then Skin.Modal(view,m.modalPanel,m.modalInScreen) end
        if view.inventoryOpen and view.modal:IsVisible() then view:BuildDeckPage() end
    end
    print(string.format("[Machine.SafeArea] content=%.2fx%.2f padding=%.2f,%.2f,%.2f,%.2f scale=%.4f",
        w,h,left,top,right,bottom,m.scale))
end
function Skin.Update(view)
    local m=view.machineSkin
    if not m then return end
    TargetSwap.Sync(view)
    RelicView.Update(view)
    if view.game.phase~="draft" then
        m.pageMotion:Clear("draft")
        clearDraftMotion(m)
    end
    if view.physicsButton.props.text~="物理" then view.physicsButton:SetText("物理") end
    -- 结算展示期间滚轮跟随逐件弹出的收益递增（board.displayScore）；
    -- 其余阶段直接显示真实余额。
    local phase=view.game.phase
    local showingIncome=phase=="running" or phase=="settle" or phase=="reveal"
    m.reels:SetValue(showingIncome and view.board.displayScore or view.game.score)
    -- 转轮音：只有分数滚轮实际滚动时起循环，停稳后收尾；开始页不响。
    local reelsSpinning = m.reels:Spinning()
    if view.startScreen and view.startScreen:IsActive() then reelsSpinning = false end
    GameAudio.SetReels(reelsSpinning)
    local c=m.clock
    if c.phase~=view.game.phase then
        if c.phase=="running" and view.game.phase=="settle" then
            -- 摇晃结束进入结算间隔：开始红色闪动，不再显示倒计时（用户要求）。
            c.flashElapsed=0
        elseif view.game.phase=="prepare" or view.game.phase=="running"
            or view.game.phase=="draft" or view.game.phase=="over" then
            -- 回到准备/摇晃或进入三选一/结束：停止闪动，恢复常亮。
            c.flashElapsed=-1;c.visible=true
        end
        c.phase=view.game.phase
    end
    c.centis=Clock.Centiseconds(view.game.phase,view.game.elapsed,view.game.settleElapsed,view.game:Duration())
    if view.game.phase=="draft" and view.currentPhase=="draft" and c.flashElapsed<0
        and not view.choiceHidden and not view.inventoryOpen
        and not view.draft:IsVisible() then view.draft:Show() end
end
return Skin
