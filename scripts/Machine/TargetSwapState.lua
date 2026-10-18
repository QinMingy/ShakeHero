-- 纯表现时间轴：玩法目标立即生效，旧牌上的数字留到手把它拿走。
---@type any
local Swap={duration=2.72}
Swap.__index=Swap

---@param t number
local function smooth(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
end

---@param game BottleGame
function Swap.New(game)
    local self=setmetatable({},Swap)
    self:Reset(game)
    return self
end

---@param game BottleGame
function Swap:Reset(game)
    self.game=game
    self.shown=game.target
    self.wanted=game.target
    self.old=game.target
    self.new=game.target
    self.elapsed=0
    self.active=false
end

---@param game BottleGame
---@param covered boolean?
function Swap:Sync(game,covered)
    if self.game~=game or covered or game.target<self.wanted then
        self:Reset(game)
        return
    end
    self.wanted=game.target
    if not self.active and self.wanted>self.shown then
        self.old,self.new=self.shown,self.wanted
        self.elapsed=0
        self.active=true
    end
end

---@param dt number
function Swap:Tick(dt)
    if not self.active then return end
    self.elapsed=math.min(Swap.duration,self.elapsed+math.max(0,dt))
    if self.elapsed>=Swap.duration then
        self.shown=self.new
        self.active=false
    end
end

function Swap:Pose()
    local t=self.elapsed
    ---@type any
    local p={x=0,y=0,angle=0,depth=-.11,visible=true,value=self.shown,
        arm=false,armX=0,armY=0,grip=false}
    if not self.active then return p end
    p.value=t<1.32 and self.old or self.new
    p.arm=true
    if t<.48 then
        local k=1-smooth(t/.48)
        p.armX,p.armY=150*k,-135*k
    elseif t<.66 then
        p.grip=true
        local k=smooth((t-.48)/.18)
        p.y=-3*k
        p.depth=-.11-.29*k
    elseif t<1.14 then
        local k=smooth((t-.66)/.48)
        p.x,p.y,p.angle=190*k,-3-147*k,-.12*k
        p.depth=-.40
        p.grip=true
    elseif t<1.32 then
        p.visible,p.arm=false,false
    elseif t<1.98 then
        local k=1-smooth((t-1.32)/.66)
        p.x,p.y,p.angle=190*k,-150*k,.10*k
        p.depth=-.40
        p.grip=true
    elseif t<2.18 then
        local k=(t-1.98)/.20
        p.y=3*math.sin(k*math.pi)
        p.angle=-.018*math.sin(k*math.pi)
        p.depth=-.40+.29*smooth(k)
        p.grip=true
    else
        local k=smooth((t-2.18)/(.54))
        p.armX,p.armY=150*k,-135*k
    end
    return p
end

return Swap
