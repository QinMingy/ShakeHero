-- A live seven-segment display mapped onto the inset timer glass.
-- The clock is part of the cabinet scene, so its digits share the camera's
-- perspective instead of floating in the screen-space UI.
local Orientation=require("Machine.RenderOrientation")

---@type any
local Clock={}
Clock.__index=Clock

local segments={
    a={{18,5},{75,5},{67,17},{26,17}},
    b={{78,8},{88,16},{88,48},{78,55},{70,47},{70,19}},
    c={{78,58},{88,65},{88,97},{78,105},{70,94},{70,66}},
    d={{26,96},{67,96},{75,108},{18,108}},
    e={{10,65},{20,58},{28,66},{28,94},{20,105},{10,97}},
    f={{10,16},{20,8},{28,19},{28,47},{20,55},{10,48}},
    g={{26,51},{67,51},{76,57},{67,63},{26,63},{17,57}},
}
local digits={
    [0]="abcdef",[1]="bc",[2]="abged",[3]="abgcd",[4]="fgbc",
    [5]="afgcd",[6]="afgecd",[7]="abc",[8]="abcdefg",[9]="abfgcd",
}

function Clock.Centiseconds(phase,elapsed,settleElapsed,duration)
    local seconds=duration or 10
    if phase=="prepare" then return math.floor(seconds*100+.5) end
    -- 结算与结算展示阶段不显示倒计时：间隔期间由时钟红色闪动提示（用户要求）。
    if phase~="running" then return 0 end
    -- Ceil keeps 00.00 exclusive to the actual end, including duration relics.
    return math.max(0,math.ceil((seconds-(elapsed or 0))*100-0.000001))
end

function Clock.Format(centis)
    return string.format("%02d.%02d",math.floor(centis/100),centis%100)
end

local function polygon(vg,points,x,y,color)
    nvgBeginPath(vg)
    nvgMoveTo(vg,x+points[1][1],y+points[1][2])
    for i=2,#points do nvgLineTo(vg,x+points[i][1],y+points[i][2]) end
    nvgClosePath(vg)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255))
    nvgFill(vg)
end

local function digit(vg,value,x,active,off)
    local lit=digits[value]
    for name,points in pairs(segments) do
        polygon(vg,points,x,4,lit:find(name,1,true) and active or off)
    end
end

function Clock.New(cabinet)
    local self=setmetatable({cabinet=cabinet,phase="prepare",centis=1000,
        flashElapsed=-1,visible=true,dirty=true},Clock)
    self.texture=Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(560,124,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_NEAREST)
    self.vg=nvgCreate(1)
    nvgSetRenderTarget(self.vg,self.texture)
    nvgSetRenderOrder(self.vg,-90)

    self.node=cabinet.scene:CreateChild("LiveSevenSegmentClock")
    local geometry=self.node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((110+(uv[1]-.5)*138-210)/100,
            (420-690-(uv[2]-.5)*30)/100,-.256))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2()
        tc.x,tc.y=uv[1],uv[2]
        geometry:DefineTexCoord(tc)
    end
    geometry:Commit()
    self.material=Material:new()
    assert(self.material:SetSurfaceShader("Shaders/BLGL/MachineKey.shader"))
    assert(self.material:SetSurfaceTexture("label_map",self.texture))
    self.material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    self.material:SetShaderParameter("pulse",Variant(0.0))
    geometry:SetMaterial(self.material)
    geometry.castShadows=false
    return self
end

function Clock:SetState(phase,elapsed,settleElapsed)
    if phase~=self.phase then
        if self.phase=="running" and phase=="settle" then
            -- 摇晃结束进入结算间隔：开始红色闪动，不再显示倒计时（用户要求）。
            self.flashElapsed=0
        elseif phase=="running" or phase=="prepare" or phase=="draft" or phase=="over" then
            self.flashElapsed=-1
            self.visible=true
        end
        self.phase=phase
        self.dirty=true
    end
    local centis=Clock.Centiseconds(phase,elapsed,settleElapsed)
    if centis~=self.centis then self.centis=centis; self.dirty=true end
end

function Clock:Tick(dt)
    if self.flashElapsed<0 then return end
    -- 红色闪动持续到阶段切换（SetState 复位），不再固定时长后自停。
    self.flashElapsed=self.flashElapsed+math.max(0,dt or 0)
    local visible=math.floor(self.flashElapsed/.14)%2==0
    if visible~=self.visible then self.visible=visible; self.dirty=true end
end

function Clock:Render()
    if not self.dirty then return end
    local vg=self.vg
    nvgBeginFrame(vg,560,124,1)
    nvgBeginPath(vg);nvgRect(vg,0,0,560,124)
    nvgFillColor(vg,nvgRGBA(0,0,0,255));nvgFill(vg)
    -- Warm amber is the regular machine signal; coral is reserved for the
    -- stopped three-flash warning. The time format and phase rules stay put.
    local off={28,34,21}
    local active=(self.phase=="running" or self.phase=="prepare")
        and {235,207,106} or {219,82,64}
    if not self.visible then active=off end
    local number=self.centis
    digit(vg,math.floor(number/1000)%10,33,active,off)
    digit(vg,math.floor(number/100)%10,143,active,off)
    digit(vg,math.floor(number/10)%10,305,active,off)
    digit(vg,number%10,415,active,off)
    polygon(vg,{{0,0},{16,0},{16,16},{0,16}},278,97,
        self.visible and active or off)
    nvgEndFrame(vg)
    self.dirty=false
    self.cabinet.surface:QueueUpdate()
end

function Clock:Dispose()
    self.node:Remove()
    nvgDelete(self.vg)
    self.texture:Dispose()
end

return Clock
