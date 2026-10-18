-- The existing directional, interruptible numeral-belt behavior without scene geometry.
local Money=require("Bottle.Money")
---@type any
local Reels={}
Reels.__index=Reels
function Reels.Literal(value)
    return Money.Format(tonumber(value) or 0)
end
function Reels.Format(value)
    local literal=Reels.Literal(value)
    local sign,integer,suffix=literal:match("^([+-]?)(%d+)(.*)$")
    if not integer then return literal end
    return sign..string.rep("0",math.max(0,8-#integer))..integer..suffix
end
function Reels.New()
    return setmetatable({text="",digits={},value=0},Reels)
end
function Reels:SetValue(value)
    local text=Reels.Format(value)
    local previous,old=self.text,self.value
    self.value=value
    if text==previous then return end
    self.text=text
    local direction=value>=old and 1 or -1
    for place=1,#text do
        local char=text:sub(#text-place+1,#text-place+1)
        local numeral=tonumber(char)
        if numeral then
            local digit=self.digits[place]
            local previousChar=previous:sub(#previous-place+1,#previous-place+1)
            if not digit or not previousChar:match("%d") then
                self.digits[place]={position=numeral,target=numeral,velocity=0}
            elseif previousChar~=char then
                local destination=math.floor(digit.position/10)*10+numeral
                if direction>0 then
                    while destination<=digit.position+.05 do destination=destination+10 end
                else
                    while destination>=digit.position-.05 do destination=destination-10 end
                end
                digit.target=destination
            end
        else self.digits[place]=nil end
    end
    for place in pairs(self.digits) do if place>#text then self.digits[place]=nil end end
end
function Reels:Tick(dt)
    dt=math.min(math.max(dt or 0,0),1/30)
    for _,digit in pairs(self.digits) do
        local distance=digit.target-digit.position
        if math.abs(distance)>.003 or math.abs(digit.velocity)>.015 then
            digit.velocity=(digit.velocity+distance*145*dt)*math.exp(-19*dt)
            digit.position=digit.position+digit.velocity*dt
        else digit.position=digit.target;digit.velocity=0 end
    end
end
-- 有任意一位仍在滚动（位移或速度超过阈值）即为旋转中，用于转轮音效起停。
function Reels:Spinning()
    for _,digit in pairs(self.digits) do
        if math.abs(digit.target-digit.position)>.05 or math.abs(digit.velocity)>.05 then
            return true
        end
    end
    return false
end
return Reels
