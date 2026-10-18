-- 收银便签：UI 管理渲染与缩放，纸张和金额都用离散像素绘制。
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local Reels=require("Machine.FlatReelState")
---@type any
local Note={rise=.7,hold=5,fall=2.6}
Note.__index=Note

local glyphs={
    ["0"]={14,17,19,21,25,17,14},["1"]={4,12,4,4,4,4,14},
    ["2"]={14,17,1,2,4,8,31},["3"]={30,1,1,14,1,1,30},
    ["4"]={2,6,10,18,31,2,2},["5"]={31,16,16,30,1,1,30},
    ["6"]={14,16,16,30,17,17,14},["7"]={31,1,2,4,8,8,8},
    ["8"]={14,17,17,14,17,17,14},["9"]={14,17,17,15,1,1,14},
    ["-"]={0,0,0,31,0,0,0},["."]={0,0,0,0,0,6,6},
    ["+"]={0,4,4,31,4,4,0},["e"]={0,0,14,17,31,16,14},
}
local function rect(vg,x,y,w,h,c)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(c[1],c[2],c[3],c[4] or 255));nvgFill(vg)
end
local function smooth(t)
    t=math.max(0,math.min(1,t))
    return t*t*(3-2*t)
end

function Note.New()
    return setmetatable({active=false,elapsed=0,amount=0,text=""},Note)
end
function Note:Reset()
    self.active=false;self.elapsed=0;self.amount=0;self.text=""
end
function Note:Show(amount)
    if not (type(amount)=="number" and amount>0 and amount<math.huge) then return end
    self.amount=amount
    self.text="-"..Reels.Literal(amount)
    self.elapsed=0;self.active=true
end
function Note:Tick(dt)
    if not self.active then return end
    self.elapsed=math.min(Note.rise+Note.hold+Note.fall,self.elapsed+math.max(0,dt))
    if self.elapsed>=Note.rise+Note.hold+Note.fall then self.active=false end
end
function Note:Pose()
    local t=self.elapsed
    if t<Note.rise then
        return {y=62*(1-smooth(t/Note.rise)),x=0,alpha=1}
    end
    if t<=Note.rise+Note.hold then return {y=0,x=0,alpha=1} end
    local k=math.min(1,(t-Note.rise-Note.hold)/Note.fall)
    return {y=68*smooth(k),x=3*math.sin(k*math.pi*2)*math.sin(k*math.pi),
        alpha=1-smooth((k-.8)/.2)}
end

-- 不规则阶梯纸边，短折线用暗面与亮面成对表现褶皱。
local function paper(vg,w)
    rect(vg,4,6,w-2,48,{20,16,12,110})
    rect(vg,2,3,w-4,46,{120,92,54})
    rect(vg,0,9,w,32,{120,92,54})
    rect(vg,4,1,w-10,48,{168,139,86})
    rect(vg,4,4,w-8,44,{238,218,160})
    rect(vg,2,11,w-4,27,{238,218,160})
    rect(vg,6,2,w-14,3,{255,238,192})
    rect(vg,6,5,w-14,6,{220,194,129})
    rect(vg,8,6,w-18,2,{230,206,149})
    rect(vg,6,43,w-15,4,{215,187,122})
    -- 左侧内折、右侧卷边及底边的细小缺口。
    rect(vg,2,17,4,9,{184,154,96})
    rect(vg,6,19,2,8,{255,235,180})
    rect(vg,w-8,12,4,8,{197,165,103})
    rect(vg,w-6,20,4,9,{175,141,82})
    rect(vg,w-10,29,4,8,{255,232,172})
    rect(vg,w-12,39,6,6,{187,152,91})
    rect(vg,w-14,37,4,6,{255,234,177})
    rect(vg,12,44,8,2,{168,134,76})
    rect(vg,20,46,7,2,{247,228,177})
    rect(vg,w-31,44,11,2,{185,151,89})
    rect(vg,w-29,42,9,2,{252,231,177})
end

function Note:Draw(vg,b,s)
    if not self.active then return end
    local pose=self:Pose()
    local w=math.min(248,math.max(116,(#self.text*6-1)*3+28))
    -- 对齐顶部“规则 / GM”区域（402设计坐标的中心 x=248）。
    local x=L.score[1]+L.score[3]/2+70-w/2+pose.x
    local y=L.score[2]-57+pose.y
    nvgSave(vg)
    -- 纸从滚轮上沿后方升起，回落时再次收进机台，始终不遮住余额。
    nvgIntersectScissor(vg,b.x,b.y,b.w,(L.score[2]+1)*s)
    nvgTranslate(vg,b.x+x*s,b.y+y*s);nvgScale(vg,s,s)
    nvgShapeAntiAlias(vg,0);nvgGlobalAlpha(vg,pose.alpha)
    paper(vg,w)
    local p=math.min(3,(w-28)/(#self.text*6-1))
    local left=(w-(#self.text*6-1)*p)/2
    for i=1,#self.text do
        for row,bits in ipairs(glyphs[self.text:sub(i,i)] or glyphs["-"]) do
            for col=0,4 do
                if bits&(1<<(4-col))~=0 then
                    local gx,gy=left+((i-1)*6+col)*p,16+(row-1)*p
                    rect(vg,gx,gy+1,p,p,{117,38,33})
                    rect(vg,gx,gy,p,p,{218,47,49})
                end
            end
        end
    end
    nvgRestore(vg)
end

function Note.Attach(view)
    local m=view.machineSkin
    m.deductionNote=Note.New()
    local widget=UI.Widget{id="deductionNote",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=7} --[[@as any]]
    function widget:Render(vg)
        if view.startScreen and view.startScreen:IsActive() then return end
        m.deductionNote:Draw(vg,self:GetAbsoluteLayout(),m.scale)
    end
    view.container:AddChild(widget)
end
return Note
