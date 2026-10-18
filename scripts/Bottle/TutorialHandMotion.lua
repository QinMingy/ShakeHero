-- Presentation only. The tutorial checkpoint never waits for or serializes this motion.
---@class BottleTutorialHandMotion
---@field current table?
---@field desired table?
---@field phase string
---@field time number
---@field outFrom number
---@field clock number
local Motion={}
Motion.__index=Motion
Motion.ENTER=.32
Motion.EXIT=.22

local function clamp(value,low,high) return math.max(low,math.min(value,high)) end
local function ease(t) t=clamp(t,0,1);return 1-(1-t)^3 end

function Motion.New()
    local self=setmetatable({},Motion)
    self:Reset()
    return self
end
function Motion:Reset()
    self.current=nil;self.desired=nil;self.phase="hidden";self.time=0;self.outFrom=1;self.clock=0
end
function Motion:Progress()
    if self.phase=="in" then return ease(self.time/Motion.ENTER) end
    if self.phase=="out" then return self.outFrom*(1-ease(self.time/Motion.EXIT)) end
    return self.phase=="idle" and 1 or 0
end
function Motion:Exit()
    if not self.current or self.phase=="out" then return end
    self.outFrom=self:Progress();self.phase="out";self.time=0
end
function Motion:Request(key,spec)
    self.desired={key=key,spec=spec}
    if not self.current then
        self.current=self.desired;self.current.born=self.clock;self.phase="in";self.time=0
    elseif self.current.key~=key then self:Exit()
    elseif self.phase~="out" then self.current.spec=spec end
end
function Motion:Hide()
    self.desired=nil;self:Exit()
end
---@param dt number
function Motion:Update(dt)
    ---@type number
    local remaining=math.max(0,dt)
    self.clock=self.clock+remaining
    -- At most an old exit and a new entrance can finish in one update.
    for _=1,3 do
        if self.phase=="idle" or self.phase=="hidden" then break end
        local duration=self.phase=="in" and Motion.ENTER or Motion.EXIT
        local consumed=math.min(remaining,math.max(0,duration-self.time))
        self.time=self.time+consumed;remaining=remaining-consumed
        if self.time<duration then break end
        if self.phase=="in" then self.phase="idle";self.time=0
        else
            self.current=self.desired;self.time=0
            if self.current then self.current.born=self.clock-remaining end
            self.phase=self.current and "in" or "hidden"
        end
    end
end

-- Coordinates are screen base pixels. Only the sleeve is permitted to cross the
-- portrait border; rendering always scissors the complete sprite to this border.
---@param spec table
---@param bounds {x:number,y:number,w:number,h:number}
---@param anchor {x:number,y:number,w:number,h:number}
---@param scale number?
---@return table
function Motion.Layout(spec,bounds,anchor,scale)
    local s=scale or 1
    if spec.hand=="heart" then
        local w,h=160*s,240*s
        local u,v=.455,.145
        local x=bounds.x+bounds.w/2-u*w
        local y=bounds.y+bounds.h-h+32*s
        return {asset=spec.hand,edge="bottom",x=x,y=y,w=w,h=h,flipX=1,angle=0,
            tipX=x+u*w,tipY=y+v*h,offX=0,offY=bounds.y+bounds.h+2*s-y}
    end
    if spec.hand=="nails" then
        local w,h=240*s,120*s
        local x=bounds.x+bounds.w-w+12*s
        local y=bounds.y+bounds.h-190*s
        return {asset="nails",edge="right",x=x,y=y,w=w,h=h,flipX=1,angle=0,
            tipX=x+.15*w,tipY=y+.42*h,offX=bounds.x+bounds.w+2*s-x,offY=0}
    end
    local px=anchor.x+anchor.w/2
    ---@type number
    local py=anchor.y+anchor.h/2
    local left=px-bounds.x;local right=bounds.x+bounds.w-px
    local edge=spec.handEdge or (left<right and "left" or "right")
    local distance=edge=="left" and left or right
    local angle=math.rad(spec.handAngle or 0)
    local ca,sa=math.cos(angle),math.sin(angle)
    -- The reference's actual sleeve reaches u=.985, while the fingertip is at .125.
    -- Extend that sleeve past the edge, even for targets near the center of the screen.
    -- A circular demonstration keeps a fixed arm length through the whole orbit.
    if spec.circle then
        distance=(edge=="left" and spec.circle.cx or bounds.w/s-spec.circle.cx)+spec.circle.rx
        distance=distance*s
    end
    local w=math.max(160*s,(distance+12*s)/((.985-.125)*math.max(.25,ca)))
    local h=w*.5;local tipX,tipY=w*.125,h*.327
    if angle==0 then py=clamp(py,bounds.y+tipY+2*s,bounds.y+bounds.h-(h-tipY)-2*s) end
    local flip=edge=="left" and -1 or 1
    local x,y=px-(ca*tipX*flip-sa*tipY),py-(sa*tipX*flip+ca*tipY)
    local minX,maxX=math.huge,-math.huge
    for _,corner in ipairs({{0,0},{w,0},{0,h},{w,h}}) do
        local cx=x+ca*corner[1]*flip-sa*corner[2]
        minX=math.min(minX,cx);maxX=math.max(maxX,cx)
    end
    local offX=edge=="left" and (bounds.x-2*s-maxX) or (bounds.x+bounds.w+2*s-minX)
    return {asset="point",edge=edge,x=x,y=y,w=w,h=h,flipX=flip,angle=angle,
        tipX=px,tipY=py,offX=offX,offY=0,
        sleeveX=x+ca*w*.985*flip-sa*tipY,sleeveY=y+sa*w*.985*flip+ca*tipY}
end

function Motion:Pose(bounds,anchor,scale)
    if not self.current then return nil end
    local spec=self.current.spec
    local circle=spec.circle
    if circle then
        local s=scale or 1
        local theta=(self.clock-self.current.born)*2*math.pi/(circle.period or 2.2)
        anchor={x=bounds.x+(circle.cx+circle.rx*math.cos(theta))*s,
            y=bounds.y+(circle.cy+circle.ry*math.sin(theta))*s,w=0,h=0}
    end
    local pose=Motion.Layout(spec,bounds,anchor,scale)
    local progress=self:Progress()
    pose.x=pose.x+pose.offX*(1-progress)
    pose.y=pose.y+pose.offY*(1-progress)
    pose.tipX=pose.tipX+pose.offX*(1-progress)
    pose.tipY=pose.tipY+pose.offY*(1-progress)
    pose.progress=progress;pose.phase=self.phase;pose.key=self.current.key
    return pose
end

return Motion
