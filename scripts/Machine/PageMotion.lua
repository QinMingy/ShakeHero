-- 页面按钮的拉出／收回独立于悬停和选中。旧业务立即失效，视觉延迟释放。
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local Hover=require("Bottle.ButtonMotion")
local Text=require("Bottle.TextMotion")
---@type any
local Motion={}
Motion.__index=Motion

local function spring(value,velocity,target,dt)
    local damping,frequency=8,18
    local wave=math.sqrt(frequency*frequency-damping*damping)
    local delta=value-target
    local c,s,decay=math.cos(wave*dt),math.sin(wave*dt),math.exp(-damping*dt)
    return target+decay*(delta*c+(velocity+damping*delta)/wave*s),
        decay*(velocity*c-(damping*velocity+frequency*frequency*delta)/wave*s)
end

function Motion.New(view)
    local layer=UI.Panel{id="pageExitLayer",position="absolute",left=0,top=0,
        width="100%",height="100%",padding=0,pointerEvents="none",zIndex=8}
    view.container:AddChild(layer)
    return setmetatable({view=view,layer=layer,entries={},serial=0},Motion)
end

local function hiddenY(e)
    if e.route=="screen" then return 670-e.rect[2]-e.rect[4]-20 end
    return L.height-e.rect[2]+e.rect[4]+24
end

function Motion:Park(e)
    if e.parked then return end
    e.parent=e.widget.parent
    e.presses={}
    e.inputVersion=(e.inputVersion or 0)+1
    self.layer:AddChild(e.widget)
    e.widget:SetStyle(L.Style(e.rect,self.view.machineSkin.scale))
    e.parked=true
end

function Motion:Clear(section)
    -- 必须在业务容器 Destroy/ClearChildren 之前，把需要退场的控件移到独立层。
    for _,e in pairs(self.entries) do
        if e.section==section and not e.retired then
            self:Park(e)
            e.retired=true
            e.parent=nil
            e.resumeInteractive=e.interactive
            e.interactive=false
            if e.widget.state then e.widget.state.pressed=false end
        end
    end
end

function Motion:Attach(widget,key,section,rect,route,delay)
    if widget.pageEntry then return end
    local previous=self.entries[key]
    Text.AttachTree(widget)
    if widget._className=="Button" then Hover.Attach(widget,previous and previous.widget.hoverPose) end
    local pose=previous and previous.pose
    local wanted=previous and previous.wanted or false
    local wait=previous and previous.wait or 0
    if previous then previous.widget:Destroy() end
    local oldInteractive=previous and (previous.interactive or previous.resumeInteractive) or false
    local e={widget=widget,key=key,section=section,rect=rect,route=route,delay=delay,
        wanted=wanted,wait=wait,retired=false,parked=false,interactive=oldInteractive,input=widget.props.onClick~=nil}
    e.pose=pose or {y=hiddenY(e),velocity=0,angle=0,angularVelocity=0,scale=.94,scaleVelocity=0}
    if previous and previous.rect[2]~=rect[2] then
        e.pose.y=e.pose.y+previous.rect[2]-rect[2]
    end
    self.entries[key]=e
    widget.pageEntry=e
    local callback=widget.props.onClick
    if callback then
        widget.props.onClick=function(...)
            if e.interactive and not e.retired then return callback(...) end
        end
        -- UI持有独立的pressedWidgets；禁止收回前的旧指针在重开后确认。
        local down,click,cancel=widget.OnPointerDown,widget.OnClick,widget.OnPointerCancel
        e.presses={};e.inputVersion=0
        widget.OnPointerDown=function(w,event)
            if e.interactive and not e.retired then
                e.presses[event.pointerId]=e.inputVersion
                down(w,event)
            end
        end
        widget.OnClick=function(w,event)
            local version=e.presses[event.pointerId]
            e.presses[event.pointerId]=nil
            if version==e.inputVersion and e.interactive and not e.retired then click(w,event) end
        end
        widget.OnPointerCancel=function(w,event)
            e.presses[event.pointerId]=nil
            cancel(w,event)
        end
    end
    local blocked=widget.hoverBlocked
    widget.hoverBlocked=function() return not e.interactive or (blocked and blocked()) end
    -- clip 是固定机台下半区；carrier 平移，tilt 旋转缩放，内层仍归悬停／选中所有。
    local clip=UI.Panel{position="absolute",padding=0,pointerEvents="none",overflow="hidden"}
    local carrier=UI.Panel{position="absolute",padding=0,pointerEvents="none"}
    local tilt=UI.Panel{position="absolute",left=0,top=0,width="100%",height="100%",
        padding=0,pointerEvents="none",transformOrigin="center"}
    local children={}
    for _,child in ipairs(widget:GetChildren()) do children[#children+1]=child end
    if not widget.hoverPose then
        local render=widget.Render
        local face=UI.Panel{position="absolute",left=0,top=0,width="100%",height="100%",
            padding=0,pointerEvents="none"} --[[@as any]]
        face.Render=function(_,vg) render(widget,vg) end
        for _,child in ipairs(children) do face:AddChild(child) end
        widget.Render=function() end
        tilt:AddChild(face)
    else
        for _,child in ipairs(children) do tilt:AddChild(child) end
    end
    carrier:AddChild(tilt);clip:AddChild(carrier);widget:AddChild(clip)
    e.clip,e.carrier,e.tilt=clip,carrier,tilt
    self:Apply(e)
end

function Motion:Apply(e)
    local s=self.view.machineSkin.scale
    local r,p=e.rect,e.pose
    e.widget.pageScale=s
    local top=e.route=="screen" and 670 or 650
    e.clip:SetStyle({left=-r[1]*s,top=(top-r[2])*s,width=L.width*s,height=(L.height-top)*s})
    e.carrier:SetStyle({left=r[1]*s,top=(r[2]-top)*s,width=r[3]*s,height=r[4]*s,translateY=p.y*s})
    e.tilt:SetStyle({rotate=math.deg(p.angle),scale=p.scale})
    if e.parked then e.widget:SetStyle(L.Style(r,s)) end
    e.widget:SetStyle({pointerEvents=e.interactive and "auto" or "none"})
end

function Motion:Targets(drafting, deckOpen)
    local phase=self.view.game.phase
    -- 摇晃、结算与结算展示阶段统称进行中：牌库入口收起，其余阶段恢复。
    local busy=phase=="running" or phase=="settle" or phase=="reveal"
    for _,e in pairs(self.entries) do
        local wanted=not e.retired and (e.section=="draft" and drafting
            or e.section=="footer" and not drafting and not deckOpen
            or e.section=="deck" and not busy and not deckOpen
            or e.section=="deckpage" and deckOpen)
        if wanted~=e.wanted then
            e.wanted=wanted
            self.serial=self.serial+1
            e.wait=wanted and e.delay or e.delay*.55
            -- 快速反向沿用位置和速度；只补一次轻角冲量，不跳回起点。
            e.pose.angularVelocity=e.pose.angularVelocity+(wanted and 1 or -.65)
                *(e.delay<.1 and 1 or -1)
        end
        if wanted then
            if e.parked and e.parent and e.parent.node then
                e.parent:AddChild(e.widget)
                e.widget:SetStyle(L.Style(e.rect,self.view.machineSkin.scale))
                e.parked=false
            end
            e.widget:Show()
        else
            self:Park(e)
            e.interactive=false
            if e.widget.state then e.widget.state.pressed=false end
        end
        self:Apply(e)
    end
end

function Motion:Tick(dt)
    local remove={}
    for key,e in pairs(self.entries) do
        local step=math.max(0,dt)
        local waiting=math.min(e.wait,step)
        e.wait=e.wait-waiting;step=step-waiting
        local p=e.pose
        local target=e.wanted and 0 or hiddenY(e)
        if step>0 then
            p.y,p.velocity=spring(p.y,p.velocity,target,step)
            p.angle,p.angularVelocity=spring(p.angle,p.angularVelocity,0,step)
            p.scale,p.scaleVelocity=spring(p.scale,p.scaleVelocity,e.wanted and 1 or .94,step)
        end
        local settled=math.abs(p.y-target)<.025 and math.abs(p.velocity)<.15
            and math.abs(p.angle)<.0002 and math.abs(p.angularVelocity)<.002
            and math.abs(p.scale-(e.wanted and 1 or .94))<.0002
        if settled and e.wait==0 then
            p.y=target;p.velocity=0;p.angle=0;p.angularVelocity=0
            p.scale=e.wanted and 1 or .94;p.scaleVelocity=0
            if not e.wanted then
                if e.retired then remove[#remove+1]=key else e.widget:Hide() end
            end
        end
        -- 到达原命中框附近后才开放交互；退场立即失效，也取消旧按下状态。
        e.interactive=e.input and e.wanted and e.wait==0 and math.abs(p.y)<8 and math.abs(p.velocity)<120
        self:Apply(e)
    end
    for _,key in ipairs(remove) do
        self.entries[key].widget:Destroy();self.entries[key]=nil
    end
end

function Motion:Reset()
    local keep={}
    for key,e in pairs(self.entries) do
        if e.section=="deck" or e.section=="deckpage" then
            e.pose={y=hiddenY(e),velocity=0,angle=0,angularVelocity=0,scale=.94,scaleVelocity=0}
            e.wanted=false;e.wait=0;e.interactive=false
            e.presses={};e.inputVersion=e.inputVersion+1
            keep[key]=e
        else e.widget:Destroy() end
    end
    self.entries=keep
end

-- UI 与真实受光九宫格使用同一个最终仿射变换和裁剪窗。
-- inner 位移位于页旋转内部；页平移位于所有旋转之外。
function Motion.Transform(widget,rect,inner)
    local e=widget.pageEntry
    if not e then return inner end
    local p=e.pose
    local s=widget.pageScale or 1
    local x,y=inner.x or 0,inner.y or 0
    local c,a=math.cos(p.angle),math.sin(p.angle)
    return {cx=inner.cx,cy=inner.cy,scale=p.scale*(inner.scale or 1),
        angle=p.angle+(inner.angle or 0),x=p.scale*(c*x-a*y),
        y=p.y*s+p.scale*(a*x+c*y),
        clipLeft=rect.x-e.rect[1]*s,clipRight=rect.x+(L.width-e.rect[1])*s,
        clipTop=rect.y+((e.route=="screen" and 670 or 650)-e.rect[2])*s,
        clipBottom=rect.y+(L.height-e.rect[2])*s}
end

return Motion
