local R=require("Machine.FlatReelState")
local L=require("Machine.LayeredLayout")
local total=0
local function check(value,message) assert(value,message);total=total+1 end
local function settle(r) for _=1,600 do r:Tick(1/60) end end
check(R.Format(12)=="00000012","leading zeroes")
check(R.Format(12.5)=="00000012.5","fraction is preserved")
check(R.Format(-3)=="-00000003","sign is preserved")
check(R.Format(123456789)=="123456789","score outgrows eight places")
local r=R.New();r:SetValue(9);r:SetValue(10)
check(r.digits[1].target==10 and r.digits[2].target==1,"carry across two slots")
r:Tick(1/60)
local position,velocity=r.digits[1].position,r.digits[1].velocity
r:SetValue(12)
check(r.digits[1].position==position and r.digits[1].velocity==velocity,"mid-spin retarget keeps motion")
settle(r)
check(r.digits[1].position%10==2 and r.digits[2].position%10==1,"retarget settles correctly")
r:SetValue(3);settle(r)
check(r.digits[1].position%10==3 and r.digits[2].position%10==0,"score decrease settles correctly")
r:SetValue(1.25);settle(r)
check(r.text=="00000001.25","fractional score stays literal")
r:SetValue(1e20);settle(r)
check(r.text:find('e',1,true)~=nil,"large score scientific notation")
for _,s in ipairs({.55,1,1.65}) do
    for _,name in ipairs({"board","score","round","target","deck","reroll","start"}) do
        local rect=L[name];local p=L.Style(rect,s)
        check(p.left>=0 and p.top>=0 and p.left+p.width<=L.width*s+.01
            and p.top+p.height<=L.height*s+.01,name.." fits safe design area")
    end
end
check(L.reroll[2]+L.reroll[4]~=L.start[2]+L.start[4],"buttons do not align along bottom")
check(L.clock[2]<L.screen[2]+L.screen[4] and L.clock[2]+L.clock[4]>L.screen[2]+L.screen[4],"timer overlaps screen edge")
check(L.target[1]<L.score[1]+L.score[3] and L.target[2]<L.score[2]+L.score[4],"target overlaps score")
return total
