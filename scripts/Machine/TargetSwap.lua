-- 与现有像素切片共用受光、真实投影和402×874设计坐标。
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local State=require("Machine.TargetSwapState")
---@type any
local Swap={}
-- 整只手下移8设计像素；铭牌遮住指尖下缘，形成从后方抓住牌边的接触。
local anchorX,anchorY=L.target[1]+84,L.target[2]+12

function Swap.Value(view)
    local state=view.machineSkin and view.machineSkin.targetSwap
    return state and state:Pose().value or view.game.target
end

function Swap.Sync(view)
    local state=view.machineSkin.targetSwap
    if state then
        state:Sync(view.game,view.startScreen and view.startScreen:IsActive())
    end
end

local function transform(view,b,p)
    local s=view.machineSkin.scale
    return {cx=b.x+(L.target[1]+L.target[3]/2)*s,
        cy=b.y+(L.target[2]+L.target[4]/2)*s,
        x=p.x*s,y=p.y*s,angle=p.angle,scale=1}
end

local function moveLabel(view,label)
    local render=label.Render
    -- 一张实体牌上的字不再单独漂浮；整牌取放拥有同一个枢轴。
    label.props.textMotionDisabled=true
    label.textMotionDisabled=true
    function label:Render(vg)
        local p=view.machineSkin.targetSwap:Pose()
        if not p.visible then return end
        local b=view.container:GetAbsoluteLayout()
        local tr=transform(view,b,p)
        nvgSave(vg)
        nvgTranslate(vg,tr.cx+tr.x,tr.cy+tr.y)
        nvgRotate(vg,tr.angle)
        nvgTranslate(vg,-tr.cx,-tr.cy)
        render(self,vg)
        nvgRestore(vg)
    end
end

function Swap.Attach(view)
    local m=view.machineSkin
    m.targetSwap=State.New(view.game)
    local plaque=UI.Widget{id="targetPlaque",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=3} --[[@as any]]
    function plaque:Render(vg)
        local p=m.targetSwap:Pose()
        if not p.visible then return end
        local b=self:GetAbsoluteLayout();local s=m.scale
        m.sprites:Panel(vg,"wood",b.x+L.target[1]*s,b.y+L.target[2]*s,
            L.target[3]*s,L.target[4]*s,s,false,p.depth,
            transform(view,b,p))
    end
    view.container:AddChild(plaque)
    local arm=UI.Widget{id="targetMerchantArm",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=6} --[[@as any]]
    function arm:Render(vg)
        local p=m.targetSwap:Pose()
        if not p.arm then return end
        local b=self:GetAbsoluteLayout();local s=m.scale
        local cx,cy=L.target[1]+L.target[3]/2,L.target[2]+L.target[4]/2
        local c,a=math.cos(p.angle),math.sin(p.angle)
        local dx,dy=anchorX-cx,anchorY-cy
        local x=b.x+(cx+c*dx-a*dy+p.x+p.armX)*s
        local y=b.y+(cy+a*dx+c*dy+p.y+p.armY)*s
        -- 取走与放回时跟随牌的深度，始终留在牌背后。
        m.litScene:Layer(p.depth+.02)
        m.sprites:Draw(vg,p.grip and "target-arm-grip" or "target-arm-open",
            x-25*s,y-36*s,160*s,80*s,nil,nil,
            {cx=x,cy=y,x=0,y=0,angle=-.70+p.angle,scale=1})
    end
    view.container:AddChild(arm)
    moveLabel(view,view.goalLabel)
    moveLabel(view,m.targetCaption)
end

return Swap
