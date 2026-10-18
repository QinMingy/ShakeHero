-- Presentation adapter. All widgets, callbacks, phase transitions, inspection,
-- gestures and footer contents come from the upstream Bottle.View unchanged.
local UI=require("urhox-libs/UI")
local P=require("Machine.Parts")
local Cabinet=require("Machine.Cabinet")
local Screen=require("Machine.Screen")
local Keys=require("Machine.Keys")
local Atmosphere=require("Machine.Atmosphere")
local Storage=require("Bottle.Storage")
local Money=require("Bottle.Money")
local Skin={}

local function Place(widget,x,y,w,h,style)
    widget:SetStyle(P.Rect(x,y,w,h))
    widget:SetStyle({flexGrow=0,flexShrink=0,flexBasis="auto",margin=0})
    widget.machineFontScale=P.FontScale(y+h*.5)
    if style then widget:SetStyle(style) end
    if style and style.fontSize then widget:SetStyle({fontSize=style.fontSize*widget.machineFontScale}) end
end

local function KeyStyle(button,size)
    button:SetStyle({fontSize=size*P.Scale()*(button.machineFontScale or P.FontScale(780)),paddingHorizontal=2,paddingVertical=0,
        backgroundColor={0,0,0,0},hoverBackgroundColor={220,223,134,25},
        pressedBackgroundColor={0,0,0,35},textColor=P.text,
        disabledTextColor=P.muted,disabledBackgroundColor={0,0,0,40},
        borderWidth=0,borderRadius=0,boxShadow=false,hoverBoxShadow=false,pressedBoxShadow=false})
end

local function BindCabinetKey(view,button,name)
    if button.machineKey == name then return end
    local cabinet=view.machineSkin.cabinet
    local down,up,cancel,click=button.OnPointerDown,button.OnPointerUp,
        button.OnPointerCancel,button.OnClick
    button.machineKey=name
    button.Render=function() end -- text and face now live on the 3D key plane
    button.OnPointerDown=function(b,event)
        if not b.props.disabled and event and event:IsPrimaryAction() then cabinet:Press(name,true) end
        return down(b,event)
    end
    button.OnPointerUp=function(b,event)
        cabinet:Press(name,false)
        return up(b,event)
    end
    button.OnPointerCancel=function(b,event)
        cabinet:Press(name,false)
        return cancel(b,event)
    end
    button.OnClick=function(b,event)
        if not b.props.disabled then cabinet:Activate(name) end
        return click(b,event)
    end
end

function Skin.Apply(view,title,help,save,gm)
    local old=view.container
    local safe=old.parent
    local cabinet=Cabinet.New()
    cabinet.keyFaces=Keys.New(cabinet)
    local scale=P.Scale()
    local container=UI.Panel{width=420*scale,height=840*scale,alignSelf="center"}
    local background=Cabinet.Background{cabinet=cabinet,position="absolute",
        top=0,left=0,right=0,bottom=0,pointerEvents="none"}
    container:AddChild(background)
    view.machineSkin={cabinet=cabinet,scale=scale,help=help,save=save,gm=gm}
    -- Secondary metal keys give a smaller camera response than the two
    -- bottom mechanical actions, without touching their existing callbacks.
    for _,button in ipairs({help,save,gm,view.deckButton}) do
        local click=button.OnClick
        button.OnClick=function(b,event)
            if not b.props.disabled then cabinet:CameraImpact("small") end
            return click(b,event)
        end
    end
    -- Reparent retained upstream widgets, including all popup layers.
    for _,widget in ipairs({title,help,save,gm,view.scoreLabel,view.goalLabel,
        view.roundLabel,view.progress,view.badgeLabel,
        view.statusLabel,view.timer,view.deckButton,view.board,view.footer,
        view.detail,view.draft,view.modal}) do container:AddChild(widget) end
    -- Preserve the existing summary hit area/id used by UI regression checks.
    local summary=UI.Panel{id="scoreSummary",pointerEvents="none"}
    Place(summary,42,78,336,79)
    container:AddChild(summary)
    -- Both headings and numeral strips now live on 3D glass planes.
    view.scoreLabel:Hide()
    view.goalLabel:Hide()
    view.roundLabel:Hide()
    view.progress:Hide()
    view.timer:Hide()
    view.badgeLabel:Hide()
    view.deckButton.Render=function() end -- retain its click target on the cabinet plaque
    -- Result prose belongs to the choice/game-over panels, not the permanent HUD.
    title:Hide()
    view.statusLabel:Hide()
    help.Render=function() end
    save.Render=function() end
    gm.Render=function() end
    -- The clock is drawn directly on the recessed 3D timer glass.
    view.container=container
    safe:SetStyle({justifyContent="center",alignItems="center"})
    safe:AddChild(container)
    old:Destroy()
    Skin.Layout(view)
    cabinet.screen=Screen.New(view,cabinet)
end

function Skin.Layout(view)
    local m=view.machineSkin
    if not m then return end
    local s=P.Scale()
    m.scale=s
    view.container:SetStyle({width=420*s,height=840*s})
    Place(m.help,263,31,54,28);KeyStyle(m.help,14)
    Place(m.save,328,31,54,28);KeyStyle(m.save,14)
    Place(m.gm,351,62,30,15);KeyStyle(m.gm,10)
    Place(view.scoreLabel,47,89,148,42,{fontSize=34*s,fontFamily="display",fontColor=P.text,textAlign="center",
        verticalAlign="middle"})
    Place(view.goalLabel,225,89,148,42,{fontSize=34*s,fontFamily="display",fontColor=P.text,
        textAlign="center",verticalAlign="middle"})
    Place(view.roundLabel,40,31,204,27,{fontSize=15*s,fontColor=P.text,textAlign="center",
        verticalAlign="middle"})
    Place(view.progress,55,168,310,12,{borderWidth=0,backgroundColor={28,35,19,255},fillColor=P.text})
    Place(view.badgeLabel,223,706,151,11,{fontSize=9*s,fontColor=P.muted,textAlign="right"})
    Place(view.timer,196,679,174,9,{borderWidth=0,backgroundColor={28,35,19,255},fillColor=P.text})
    Place(view.deckButton,304,719,74,23);KeyStyle(view.deckButton,11)
    Place(view.board,42,210,336,448,{minHeight=0,backgroundColor={13,31,17,255}})
    Place(view.footer,38,752,344,68,{gap=0,padding=0})
    view.draft:SetStyle({padding=8})
    view.modal:SetStyle({padding=10})
    Skin.Footer(view)
end

function Skin.Footer(view)
    if not view.machineSkin then return end
    local s=P.Scale()
    local children=view.footer:GetChildren()
    local faces=view.machineSkin.cabinet.keyFaces
    local lettering=view.machineSkin.cabinet.labels
    local phase=view.game.phase
    lettering:SetHint(phase=="prepare" and (view.physics.mode==2
        and "来回摇手机或拖动 · 菜单校准体感" or "拖动瓶身 · 物理菜单切换模式")
        or phase=="running" and "摇晃中 · 碰撞计分" or "")
    local footerTop,footerHeight=phase=="over" and 718 or 752,phase=="over" and 92 or 68
    Place(view.footer,38,footerTop,344,footerHeight,{gap=0,padding=0})
    for i,child in ipairs(children) do
        local top,height=0,54
        if phase=="prepare" then
            top,height=i==1 and 0 or 56,i==1 and 54 or 12
        elseif phase=="running" then
            top,height=i==1 and 0 or 56,i==1 and 52 or 12
        elseif phase=="draft" then top,height=0,54
        else top,height=i==1 and 0 or i==2 and 34 or 89,i==1 and 24 or i==2 and 52 or 10 end
        child:SetStyle({position="absolute",left=0,top=top/footerHeight*100 .."%",width="100%",
            height=height/footerHeight*100 .."%",minHeight=0,margin=0,padding=0,gap=4*s})
        if child.props.text then child:SetStyle({fontSize=(i==1 and 12 or 9)*s,whiteSpace="normal",textAlign="center"}) end
        if (phase=="prepare" or phase=="running") and i==2 then
            child.Render=function() end -- readable hint is inked onto the lower casing
        end
        if phase=="prepare" and i==1 then
            local actions=child:GetChildren()
            for j,button in ipairs(actions) do
                button:SetStyle({position="absolute",top=0,left=j==1 and "0%" or "35.46%",
                    width=j==1 and "32.55%" or "64.54%",height="100%",flexGrow=0,flexBasis="auto"})
                KeyStyle(button,j==1 and 14 or 18)
                if j==1 then button:SetStyle({textColor=P.text,disabledTextColor=P.muted}) end
            end
        elseif child.props.onClick then
            child:SetStyle({left="35.46%",width="64.54%"});KeyStyle(child,15)
        end
    end
    if phase=="prepare" and children[1] then
        local actions=children[1]:GetChildren()
        local reroll,start=actions[1],actions[2]
        if reroll and start then
            BindCabinetKey(view,reroll,"reroll")
            BindCabinetKey(view,start,"shake")
            faces:SetAction("reroll",reroll.props.text,not reroll.props.disabled)
            faces:SetAction("shake",start.props.text,not start.props.disabled)
        end
    else
        faces:SetAction("reroll","",false)
        if phase=="running" and children[1] then
            children[1].Render=function() end -- status now engraved on the inactive 3D key
        end
        local action=phase=="draft" and children[1]
            or phase=="over" and children[2]
            or phase~="running" and children[2]
        if action and action.props.onClick then
            BindCabinetKey(view,action,"shake")
            faces:SetAction("shake",action.props.text,not action.props.disabled)
        else
            faces:SetAction("shake",phase=="running" and "正在摇晃" or "",false)
        end
    end
end

function Skin.FitNumbers(view)
    local m=view.machineSkin
    if not m then return end
    local s=P.Scale()*P.FontScale(110)
    for _,entry in ipairs({{view.scoreLabel,view.game.score,"scoreWidth"},
        {view.goalLabel,view.game.target,"goalWidth"}}) do
        local width=#Money.Format(entry[2])
        if m[entry[3]]~=width then
            m[entry[3]]=width
            entry[1]:SetStyle({fontSize=math.max(16,math.min(34,170/width))*s})
        end
    end
end

function Skin.Update(view)
    if view.machineSkin and view.machineSkin.scale~=P.Scale() then Skin.Layout(view) end
    if view.machineSkin then
        local cabinet=view.machineSkin.cabinet
        local id=Atmosphere.Resolve(Storage.atmosphereMode)
        if view.machineSkin.appliedAtmosphere~=id then
            cabinet:SetAtmosphere(id)
            view.machineSkin.appliedAtmosphere=id
        end
        cabinet.scoreReels:SetValues(view.game.score,view.game.target)
        cabinet.progressLamps:SetProgress(view.game.score,view.game.target)
        local clock=cabinet.clock
        clock:SetState(view.game.phase,view.game.elapsed)
        cabinet.timeMeter:SetState(view.game.phase,view.game.elapsed)
        cabinet.lowerReadout:SetValues(view.game.clawStacks,
            #view.game.deck,view.game.phase~="running")
        cabinet.labels:SetRound(view.game.round)
        if view.game.phase=="draft" and view.currentPhase=="draft"
            and clock.flashElapsed<0 and not view.choiceHidden and not view.draft:IsVisible() then
            view.draft:Show()
        end
    end
end
return Skin
