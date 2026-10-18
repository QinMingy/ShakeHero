-- Shared anchored paper note. UI owns layout, scrolling, pointer routing and DPR.
local UI=require("urhox-libs/UI")
local Description=require("Bottle.Description")
local Audio=require("Bottle.Audio")
local Sprites=require("Machine.LayeredSprites")
---@type any
local Note={}
Note.__index=Note
local ink={237,224,187,255}
local secondary={209,188,149,255}

-- Prefer the space above the inspected object, then below; keep the note in bounds.
function Note.Position(anchor,limit,width,height,gap)
    local inset=gap*.8
    local x=anchor.x+anchor.w/2-width/2
    local y=anchor.y-height-gap
    if y<limit.y+inset then y=anchor.y+anchor.h+gap end
    return math.max(limit.x+inset,math.min(x,limit.x+limit.w-width-inset)),
        math.max(limit.y+inset,math.min(y,limit.y+limit.h-height-inset))
end

local function paper(card)
    local sprites=Sprites.New()
    function card:Render(vg)
        local b=self:GetAbsoluteLayout()
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        sprites:Panel(vg,"wood",b.x,b.y,b.w,b.h,self.paperScale or 1)
        nvgRestore(vg)
    end
    local destroy=card.Destroy
    function card:Destroy()
        sprites:Dispose();destroy(self)
    end
end

local function textWidth(widget,text)
    local p=widget.props
    local font=UI.Theme.FontSize(p.fontSize or 18)
    local face=UI.Theme.FontFace(p.fontFamily or "sans",p.fontWeight or "normal")
    local widest=0
    for line in ((text or p.text or "").."\n"):gmatch("(.-)\n") do
        local width=UI.MeasureTextWidth(line,font,face,0)
        if width<=0 and line~="" then width=(utf8.len(line) or #line)*font*.75 end
        widest=math.max(widest,width)
    end
    return widest
end

local function inlineWidth(widget)
    if not widget:IsVisible() then return 0 end
    if widget.props.text~=nil then return textWidth(widget) end
    local width,count=0,0
    for _,child in ipairs(widget:GetChildren()) do
        if child:IsVisible() then
            width=width+((#child:GetChildren()==0 and child.props.text==nil and child.props.width)
                or inlineWidth(child) or 0)
            count=count+1
        end
    end
    return width+math.max(0,count-1)*(widget.props.gap or 0)
end

function Note:PreferredWidth(limit)
    local s=self.scale
    local bodyWidth,line=0,0
    local font=UI.Theme.FontSize(self.effect.props.fontSize)
    for _,token in ipairs(self.effect:GetSegments()) do
        if token.kind=="break" then bodyWidth=math.max(bodyWidth,line);line=0
        elseif token.kind=="item" then line=line+math.max(32,math.ceil(font*1.5))
        elseif token.kind=="gain" then line=line+math.max(24,math.ceil(font*1.3))
        else line=line+textWidth(self.effect,token.text) end
    end
    bodyWidth=math.max(bodyWidth,line)
    local heading=52*s+8*s+textWidth(self.title)
        +(self.gain:IsVisible() and (8*s+inlineWidth(self.gain)) or 0)
    local tags=52*s+8*s+inlineWidth(self.stats)
    local header=textWidth(self.meta)+48*s
    local content=math.max(heading,tags,header,bodyWidth,
        self.status:IsVisible() and textWidth(self.status) or 0,
        self.action:IsVisible() and (textWidth(self.action)+(self.actionDanger and 48 or 24)*s) or 0)
    return math.min(346*s,math.max(1,limit.w-16*s),math.max(220*s,math.ceil(content+28*s)))
end

function Note.New(props)
    local self=setmetatable({scale=1,dirty=true,elapsed=1,onClose=props.onClose,scaleProvider=props.scale},Note)
    self.icon,self.stats=props.icon,props.stats
    self.gain=self.stats:GetChildren()[1]
    self.title=UI.Label{id=props.prefix.."Title",text="",flexGrow=1,flexBasis=0,flexShrink=1,minWidth=0,whiteSpace="normal",
        fontWeight="bold",fontColor=ink,textMotionDisabled=true}
    self.meta=UI.Label{text="",fontColor=secondary,textMotionDisabled=true,
        width="100%",whiteSpace="normal"}
    self.status=UI.Label{text="",fontColor=secondary,visible=false,
        width="100%",whiteSpace="normal",textMotionDisabled=true}
    self.effect=Description{id=props.prefix.."Description",text="",fontColor=ink,
        textMotionDisabled=true,onInspect=props.onInspect}
    self.action=Audio.Button{id=props.prefix.."Action",text="",visible=false,width="100%",
        boxShadow=false,hoverBoxShadow=false,pressedBoxShadow=false,disabledBoxShadow=false,
        backgroundColor={67,77,52,255},textColor=ink,borderWidth=1,textMotionDisabled=true,
        onClick=function() if self.actionHandler then self.actionHandler() end end}
    local note=self
    local renderAction=self.action.Render
    function self.action:Render(vg)
        renderAction(self,vg)
        if not note.actionDanger then return end
        local b=self:GetAbsoluteLayout();local p=math.max(1,math.floor(3*note.scale+.5))
        local x=math.floor(b.x+b.w/2+5*note.scale-textWidth(self)/2-5*p)
        local y=math.floor(b.y+(b.h-5*p)/2)
        local color=self.props.disabled and {155,90,80,255} or {244,112,98,255}
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],color[4]))
        for row=0,4 do for col=0,4 do
            if row==col or row+col==4 then
                nvgBeginPath(vg);nvgRect(vg,x+col*p,y+row*p,p,p);nvgFill(vg)
            end
        end end
        nvgRestore(vg)
    end
    self.heading=UI.Panel{width="100%",flexDirection="row",alignItems="center",children={self.title,self.gain}}
    self.hero=UI.Panel{width="100%",flexDirection="row",alignItems="center",children={
        self.icon,UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,gap=4,children={self.heading,self.stats}}}}
    self.body=UI.Panel{width="100%",flexShrink=0,children={self.hero,self.status,self.effect,self.action}}
    self.scroll=UI.ScrollView{id=props.prefix.."Scroll",width="100%",height=64,
        flexShrink=0,bounces=false,padding=0,children={self.body}}
    self.close=Audio.Button{id=props.prefix.."Close",text="",width=40,height=40,minWidth=40,maxWidth=40,
        padding=0,flexShrink=0,textMotionDisabled=true,
        borderWidth=0,boxShadow=false,hoverBoxShadow=false,pressedBoxShadow=false,
        backgroundColor={0,0,0,0},hoverBackgroundColor={70,86,51,24},pressedBackgroundColor={70,86,51,40},
        onClick=function(_,event)
            if event then event:StopPropagation() end
            props.onClose()
        end}
    function self.close:Render(vg)
        local b=self:GetAbsoluteLayout();local p=math.max(1,math.floor(3*note.scale+.5))
        local x,y=math.floor(b.x+(b.w-5*p)/2),math.floor(b.y+(b.h-5*p)/2)
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        -- Draw the pixel X directly on the button; each square is a separate filled path.
        -- The icon and its 40px click target share the same measured button bounds.
        if self.state and (self.state.hovered or self.state.pressed) then
            nvgBeginPath(vg);nvgRect(vg,b.x,b.y,b.w,b.h)
            nvgFillColor(vg,nvgRGBA(ink[1],ink[2],ink[3],self.state.pressed and 48 or 24));nvgFill(vg)
        end
        nvgFillColor(vg,nvgRGBA(ink[1],ink[2],ink[3],255))
        for row=0,4 do for col=0,4 do
            if row==col or row+col==4 then
                nvgBeginPath(vg);nvgRect(vg,x+col*p,y+row*p,p,p);nvgFill(vg)
            end
        end end
        nvgRestore(vg)
    end
    self.head=UI.Panel{width="100%",flexDirection="row",alignItems="center",children={
        UI.Panel{flexGrow=1,flexBasis=0,minWidth=0,children={self.meta}},self.close}}
    self.card=UI.Panel{id=props.prefix.."Card",position="absolute",visible=false,
        width=340,padding=16,gap=10,boxShadow=false,pointerEvents="auto",textMotionDisabled=true,
        onClick=function(_,event) if event then event:StopPropagation() end end,
        children={self.head,self.scroll}} --[[@as any]]
    paper(self.card)
    self.overlay=UI.Panel{id=props.prefix.."Overlay",position="absolute",left=0,top=0,
        width="100%",height="100%",visible=false,zIndex=props.zIndex or 32,
        backgroundColor={0,0,0,0},pointerEvents="auto",children={self.card},
        onPointerDown=function(event) event:StopPropagation() end,
        onClick=function(widget,event)
            if event then event:StopPropagation() end
            if not event or (event.target==widget and event:IsPrimaryButton()) then props.onClose() end
        end}
    local update=self.card.Update
    self.card.Update=function(w,dt)
        if update then update(w,dt) end
        if not self.overlay:IsVisible() then return end
        self:Place()
        self.elapsed=math.min(.14,self.elapsed+math.max(0,dt))
        local t=1-(1-self.elapsed/.14)^3
        if t~=self.lastT then
            w:SetStyle({opacity=t});self.lastT=t
        end
    end
    return self
end

function Note:SetMeta(text)
    self.meta:SetText(text);self.dirty=true
end
function Note:SetStatus(text)
    self.status:SetText(text or "");self.status:SetVisible(text~=nil and text~="");self.dirty=true
end
function Note:SetAction(text,callback,options)
    local danger=options and options.danger==true or false
    self.actionDanger=danger;self.actionHandler=callback
    -- This slot is shared by item removal and the juicer; reset every state when its role changes.
    self.action:SetStyle({
        backgroundColor=danger and {72,32,29,255} or {67,77,52,255},
        hoverBackgroundColor=danger and {99,40,34,255} or {88,100,62,255},
        pressedBackgroundColor=danger and {50,22,20,255} or {48,57,38,255},
        disabledBackgroundColor=danger and {42,30,27,255} or {39,46,33,255},
        textColor=danger and {244,112,98,255} or ink,
        disabledTextColor=danger and {155,90,80,255} or secondary,
        borderColor=danger and {160,66,56,255} or {94,96,97,255},
        paddingLeft=(danger and 32 or 12)*self.scale,paddingRight=12*self.scale,
    })
    self.action:SetDisabled(options and options.disabled==true or false)
    self.action:SetText(text or "");self.action:SetVisible(callback~=nil);self.dirty=true
end
function Note:SetStatsVisible(visible)
    self.stats:SetVisible(visible);self.gain:SetVisible(visible);self.dirty=true
end

function Note:Open(anchor,bounds,scale)
    self.bounds=bounds
    local limit=type(bounds)=="function" and bounds() or bounds
    local point=type(anchor)=="function" and anchor() or anchor
    if not point or not limit then return end
    local camera=self.overlay.parent.props
    -- Capture the physical object once. Solver jitter must never move an open note.
    self.pin={x=(point.x+(camera.translateX or 0)-limit.x)/limit.w,
        y=(point.y+(camera.translateY or 0)-limit.y)/limit.h,w=point.w/limit.w,h=point.h/limit.h}
    self.anchor=point
    self.scale=scale or 1;self.dirty=true;self.elapsed=0;self.lastT=nil
    self.overlay:Show();self.card:Show();self.scroll:ScrollToTop()
    self.card:SetStyle({opacity=0,translateY=0})
    self:Place()
end
function Note:Close()
    self.overlay:Hide();self.card:Hide();self.anchor=nil;self.pin=nil
end

function Note:Place()
    if not self.pin or not self.overlay:IsVisible() then return end
    local limit=type(self.bounds)=="function" and self.bounds() or self.bounds
    if not limit then return end
    -- Cover the playable portrait area, including space outside the CRT.
    local parent=self.overlay.parent:GetAbsoluteLayout()
    local camera=self.overlay.parent.props
    local cameraX,cameraY=camera.translateX or 0,camera.translateY or 0
    local props=self.overlay.props
    -- Counter the cabinet's camera in rendering/hit testing, without changing Yoga geometry.
    if props.translateX~=-cameraX or props.translateY~=-cameraY then
        self.overlay:SetStyle({translateX=-cameraX,translateY=-cameraY})
    end
    local anchor={x=limit.x+self.pin.x*limit.w,y=limit.y+self.pin.y*limit.h,
        w=self.pin.w*limit.w,h=self.pin.h*limit.h}
    -- Linked definitions receive coordinates before the cabinet's render transform.
    self.anchor={x=anchor.x-cameraX,y=anchor.y-cameraY,w=anchor.w,h=anchor.h}
    local overlayX,overlayY=limit.x-parent.x,limit.y-parent.y
    if props.left~=overlayX or props.top~=overlayY or props.width~=limit.w or props.height~=limit.h then
        self.overlay:SetStyle({left=overlayX,top=overlayY,width=limit.w,height=limit.h})
        self.dirty=true
    end
    local version=UI.GetFontVersion()
    -- Multiline labels finish measuring during Render, after the opening layout.
    -- Refit once their actual height arrives; unchanged notes still avoid reflow.
    local bodyHeight=self.body:GetAbsoluteLayout().h
    if self.measuredBodyHeight and math.abs(bodyHeight-self.measuredBodyHeight)>.5 then self.dirty=true end
    if self.scaleProvider then
        local scale=self.scaleProvider()
        if self.scale~=scale then self.scale=scale;self.dirty=true end
    end
    if self.dirty or not self.lastLimit or limit.w~=self.lastLimit.w or limit.h~=self.lastLimit.h
        or version~=self.fontVersion then
        local s=self.scale
        self.card.paperScale=s
        self.head:SetStyle({gap=8*s})
        self.close:SetStyle({width=40*s,height=40*s,minWidth=40*s,maxWidth=40*s,padding=0})
        self.icon:SetStyle({width=52*s,height=52*s,flexShrink=0})
        self.hero:SetStyle({gap=8*s})
        self.hero:GetChildren()[2]:SetStyle({gap=4*s})
        self.heading:SetStyle({gap=8*s})
        self.gain:SetStyle({flexShrink=0,gap=4*s,minHeight=0})
        self.body:SetStyle({gap=8*s})
        self.title:SetStyle({fontSize=24*s})
        self.meta:SetStyle({fontSize=14*s})
        self.status:SetStyle({fontSize=16*s})
        self.effect:SetStyle({fontSize=18*s,fontColor=ink})
        self.action:SetStyle({fontSize=16*s,height=44*s,
            paddingLeft=(self.actionDanger and 32 or 12)*s,paddingRight=12*s})
        self.stats:SetStyle({width="100%",gap=4*s})
        for _,child in ipairs(self.stats:GetChildren()) do child:SetStyle({marginLeft=0}) end
        local function large(w)
            if w._className=="Label" then
                w:SetStyle({fontSize=w.id=="goldValue" and 24*s or 15*s,fontColor=ink})
            elseif w._className=="BottleStatIcon" then w:SetStyle({width=24*s,height=24*s}) end
            for _,child in ipairs(w:GetChildren()) do large(child) end
        end
        large(self.gain);large(self.stats)
        -- The value uses a larger font here than when its text was assigned.
        -- Reserve its measured width before giving the name the remaining space.
        for _,child in ipairs(self.gain:GetChildren()) do
            if child._className=="Label" then child:SetStyle({width=textWidth(child),flexShrink=0}) end
        end
        self.gain:SetStyle({width=inlineWidth(self.gain),flexShrink=0})
        local width=self:PreferredWidth(limit)
        self.card:SetStyle({width=width,padding=14*s,gap=4*s})
        UI.Layout()
        self.effect:Measure(math.max(1,self.effect:GetLayout().w))
        UI.Layout()
        local chrome=self.card:GetAbsoluteLayout().h-self.scroll:GetAbsoluteLayout().h
        local available=math.max(1,math.min(520*s,limit.h-16*s)-chrome)
        self.scroll:SetHeight(math.max(1,math.min(self.body:GetAbsoluteLayout().h,available)))
        UI.Layout()
        local b=self.card:GetAbsoluteLayout()
        local x,y=Note.Position(anchor,limit,b.w,b.h,10*s)
        self.card:SetStyle({left=math.floor(x-limit.x+.5),top=math.floor(y-limit.y+.5)})
        self.dirty=false;self.fontVersion=version;self.lastLimit=limit
        self.measuredBodyHeight=self.body:GetAbsoluteLayout().h
    end
end

return Note
