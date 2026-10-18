-- Retained UI overlay: the cutouts and their input windows share screen coordinates.
-- It stays in the regular UI capture, so the hand and speech obey the cabinet light.
local UI=require("urhox-libs/UI")
local Audio=require("Bottle.Audio")
local L=require("Machine.LayeredLayout")
local HandMotion=require("Bottle.TutorialHandMotion")
---@type any
local Overlay={}
Overlay.__index=Overlay
local clear={0,0,0,0}
local ink={43,48,35,255}
local paper={226,220,191,255}
local handPaths={point="image/tutorial/god-arm-point.png",heart="image/tutorial/god-arm-heart.png",
    nails="image/tutorial/god-arm-nails.png"}

local function contains(r,x,y)
    return x>=r.x and y>=r.y and x<=r.x+r.w and y<=r.y+r.h
end
local function fill(vg,r,color)
    if r.w<=0 or r.h<=0 then return end
    nvgBeginPath(vg);nvgRect(vg,r.x,r.y,r.w,r.h)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],color[4]));nvgFill(vg)
end

-- Subtraction also supports overlapping cutouts without double-darkening any pixel.
function Overlay.Subtract(rects,hole)
    local result={}
    for _,r in ipairs(rects) do
        local x1,y1=math.max(r.x,hole.x),math.max(r.y,hole.y)
        local x2,y2=math.min(r.x+r.w,hole.x+hole.w),math.min(r.y+r.h,hole.y+hole.h)
        if x2<=x1 or y2<=y1 then result[#result+1]=r
        else
            for _,part in ipairs({{r.x,r.y,r.w,y1-r.y},{r.x,y2,r.w,r.y+r.h-y2},
                {r.x,y1,x1-r.x,y2-y1},{x2,y1,r.x+r.w-x2,y2-y1}}) do
                if part[3]>0 and part[4]>0 then
                    result[#result+1]={x=part[1],y=part[2],w=part[3],h=part[4]}
                end
            end
        end
    end
    return result
end

function Overlay.New(view,onContinue)
    local self=setmetatable({},Overlay)
    self:Init(view,onContinue)
    return self
end

function Overlay:Init(view,onContinue)
    self.view=view;self.elapsed=0;self.key="";self.holes={};self.windows={}
    self.handMotion=HandMotion.New();self.closing=false;self.closeTime=0;self.maskAlpha=166
    self.layer=UI.Panel{id="tutorialOverlay",position="absolute",left=0,top=0,
        width="100%",height="100%",backgroundColor=clear,pointerEvents="box-none",
        visible=false,zIndex=100,padding=0}
    self.blocker=UI.Widget{id="tutorialDimmer",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="box-only",zIndex=0,
        onPointerDown=function(event) event:StopPropagation();event:PreventDefault() end,
        onClick=function(_,event) if event then event:StopPropagation() end end} --[[@as any]]
    local owner=self
    function self.blocker:HitTest(x,y)
        for _,r in ipairs(owner.windows) do if contains(r,x,y) then return false end end
        return true
    end
    function self.blocker:Render(vg)
        local pieces={{x=0,y=0,w=UI.GetWidth(),h=UI.GetHeight()}}
        for _,hole in ipairs(owner.holes) do pieces=Overlay.Subtract(pieces,hole) end
        for _,r in ipairs(pieces) do fill(vg,r,{0,0,0,owner.maskAlpha}) end
    end
    self.layer:AddChild(self.blocker)
    self.hand=UI.Widget{id="tutorialGodHand",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=2} --[[@as any]]
    self.handImages={}
    function self.hand:Render(vg)
        local pose,clip=owner.handPose,owner.handClip
        if not pose or not clip or clip.w<=0 or clip.h<=0 then return end
        local images=owner.handImages[vg]
        if not images then images={};owner.handImages[vg]=images end
        local path=assert(handPaths[pose.asset],"Unknown tutorial hand: "..tostring(pose.asset))
        local handle=images[path]
        if not handle then
            handle=nvgCreateImage(vg,path,NVG_IMAGE_NEAREST)
            assert(handle>0,"Tutorial arm unavailable: "..path)
            images[path]=handle
        end
        -- Scissor before the sprite transform: no hand can bleed into letterbox margins.
        nvgSave(vg);nvgIntersectScissor(vg,clip.x,clip.y,clip.w,clip.h)
        nvgTranslate(vg,pose.x,pose.y);nvgRotate(vg,pose.angle or 0);nvgScale(vg,pose.flipX,1)
        nvgBeginPath(vg);nvgRect(vg,0,0,pose.w,pose.h)
        nvgFillPaint(vg,nvgImagePattern(vg,0,0,pose.w,pose.h,0,handle,1));nvgFill(vg)
        nvgRestore(vg)
    end
    local destroy=self.hand.Destroy
    function self.hand:Destroy()
        for vg,images in pairs(owner.handImages) do
            for _,handle in pairs(images) do nvgDeleteImage(vg,handle) end
        end
        owner.handImages={};destroy(self)
    end
    self.layer:AddChild(self.hand)
    self.heading=UI.Label{id="tutorialHeading",text="上帝的入职指导",fontFamily="sans",
        fontColor={102,111,76,255},fontSize=14,textMotionDisabled=true,pointerEvents="none"}
    self.text=UI.Label{id="tutorialText",text="",fontFamily="sans",fontColor=ink,
        fontSize=19,whiteSpace="normal",width="100%",flexShrink=0,textMotionDisabled=true,
        lineHeight=1.35,pointerEvents="none"}
    self.button=Audio.Button{id="tutorialContinue",text="继续",fontFamily="sans",
        textMotionDisabled=true,height=42,width=116,alignSelf="flex-end",fontSize=17,
        backgroundColor={106,123,85,255},hoverBackgroundColor={126,143,99,255},
        pressedBackgroundColor={86,105,69,255},textColor={244,237,209,255},
        disabledBackgroundColor={80,90,67,255},disabledTextColor={190,185,160,255},
        borderColor={48,57,40,255},borderWidth=2,boxShadow=false,
        onClick=function(_,event)
            if event then event:StopPropagation() end
            if owner.elapsed>=.28 then onContinue() end
        end}
    self.card=UI.Panel{id="tutorialBubble",position="absolute",width=346,padding=16,gap=10,
        backgroundColor=clear,pointerEvents="auto",zIndex=3,transformOrigin="center",
        onClick=function(_,event) if event then event:StopPropagation() end end,
        children={self.heading,self.text,self.button}} --[[@as any]]
    function self.card:Render(vg)
        local b=self:GetAbsoluteLayout();local s=owner.scale or 1
        local p=2*s
        nvgSave(vg);nvgShapeAntiAlias(vg,0)
        fill(vg,{x=b.x+4*s,y=b.y+5*s,w=b.w,h=b.h},{8,13,10,120})
        fill(vg,b,{42,48,35,255})
        fill(vg,{x=b.x+p,y=b.y+p,w=b.w-2*p,h=b.h-2*p},paper)
        fill(vg,{x=b.x+5*s,y=b.y+5*s,w=b.w-10*s,h=2*s},{247,242,215,255})
        -- A small stepped speech tail, kept away from the readable text.
        local x=b.x+b.w*.74
        fill(vg,{x=x,y=b.y+b.h,w=18*s,h=4*s},{42,48,35,255})
        fill(vg,{x=x+3*s,y=b.y+b.h+4*s,w=12*s,h=4*s},{42,48,35,255})
        fill(vg,{x=x+6*s,y=b.y+b.h+8*s,w=6*s,h=4*s},{42,48,35,255})
        fill(vg,{x=x+3*s,y=b.y+b.h-p,w=12*s,h=5*s},paper)
        nvgRestore(vg)
    end
    self.layer:AddChild(self.card)
    view.root:AddChild(self.layer)
end

function Overlay:Show(spec)
    self.closing=false;self.closeTime=0;self.maskAlpha=166
    if self.key~=spec.key then
        self.key=spec.key;self.elapsed=0
        self.heading:SetText(spec.heading or "上帝的入职指导")
        self.text:SetText(spec.text)
        self.button:SetText(spec.button or "继续")
        self.button:SetVisible(spec.button~=false)
    end
    -- Reviewing candidates keeps the same bubble and entrance animation.
    self.button:SetDisabled(spec.buttonDisabled==true)
    self.spec=spec
    self.handMotion:Request(spec.key,spec)
    self.layer:Show()
end

function Overlay:Hide(immediate)
    if immediate or not self.layer:IsVisible() then
        self.layer:Hide();self.key="";self.spec=nil;self.holes={};self.windows={}
        self.handMotion:Reset();self.handPose=nil;self.handClip=nil;self.closing=false
        return
    end
    if not self.closing then self.closeTime=0;self.closing=true end
    self.windows={};self.handMotion:Hide()
end

function Overlay:ScreenRect(rect,padding)
    local b=UI.GetVisualRect(self.view.container)
    local s=self.view.machineSkin.scale
    local p=padding or 0
    return {x=b.x+(rect[1]-p)*s,
        y=b.y+(rect[2]-p)*s,
        w=(rect[3]+2*p)*s,h=(rect[4]+2*p)*s}
end

function Overlay:Update(dt)
    if not self.layer:IsVisible() or not self.spec then return end
    self.elapsed=self.elapsed+math.max(0,dt)
    local spec=self.spec
    local s=self.view.machineSkin.scale;self.scale=s
    self.handMotion:Update(dt)
    local bounds=self.view.container:GetAbsoluteLayout()
    local current=self.handMotion.current
    local anchor=current and self:ScreenRect(current.spec.point or L.board) or bounds
    self.handPose=self.handMotion:Pose(bounds,anchor,s)
    local x1,y1=math.max(0,bounds.x),math.max(0,bounds.y)
    self.handClip={x=x1,y=y1,w=math.max(0,math.min(UI.GetWidth(),bounds.x+bounds.w)-x1),
        h=math.max(0,math.min(UI.GetHeight(),bounds.y+bounds.h)-y1)}
    if self.closing then
        self.closeTime=self.closeTime+math.max(0,dt)
        local fade=math.max(0,1-self.closeTime/HandMotion.EXIT)
        self.maskAlpha=math.floor(166*fade)
        self.card:SetStyle({opacity=fade})
        if self.handMotion.phase=="hidden" then self:Hide(true) end
        return
    end
    self.holes={};self.windows={}
    for _,rect in ipairs(spec.holes or {}) do self.holes[#self.holes+1]=self:ScreenRect(rect,4) end
    for _,rect in ipairs(spec.windows or {}) do self.windows[#self.windows+1]=self:ScreenRect(rect) end
    local width=math.min(346*s,bounds.w-32*s)
    self.card:SetStyle({width=width,padding=16*s,gap=10*s})
    self.heading:SetStyle({fontSize=14*s})
    self.text:SetStyle({fontSize=(spec.compact and 16 or 19)*s})
    self.button:SetStyle({height=42*s,width=116*s,fontSize=17*s})
    -- Measure on content/scale changes, not on every animation frame.
    if self.layoutKey~=self.key or self.layoutScale~=s or self.layoutWidth~=width
        or self.fontVersion~=UI.GetFontVersion() then
        UI.Layout()
        self.cardHeight=self.card:GetAbsoluteLayout().h
        self.layoutKey,self.layoutScale,self.layoutWidth=self.key,s,width
        self.fontVersion=UI.GetFontVersion()
    end
    -- Label wrapping can finish in the following UI pass. Keep the cached height
    -- in sync without forcing another Yoga pass on every animation frame.
    local actualHeight=self.card:GetAbsoluteLayout().h
    if actualHeight>0 then self.cardHeight=actualHeight end
    local height=self.cardHeight or 180*s
    local y=bounds.y+(spec.y or 330)*s
    y=math.max(bounds.y+16*s,math.min(y,bounds.y+bounds.h-height-24*s))
    local x=bounds.x+(bounds.w-width)/2
    local t=self.elapsed
    local pop=1-math.exp(-9*t)*(math.cos(15*t)+.35*math.sin(15*t))
    local sway=math.sin(t*2.3)*.65*(1-math.exp(-t*4))
    self.card:SetStyle({left=x,top=y,scale=.86+.14*pop,rotate=sway,
        translateY=math.sin(t*2.0)*1.5*s,opacity=math.min(1,t*8)})
end

return Overlay
