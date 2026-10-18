-- A recessed row of discrete countdown bulbs on the lower status plate.
-- It uses the same game time as the seven-segment clock, without adding mesh
-- parts or leaving a screen-space progress bar above the perspective scene.
local Orientation=require("Machine.RenderOrientation")

---@class TimeMeter
---@field cabinet any
---@field phase string
---@field lit integer
---@field dirty boolean
---@field texture Texture2D
---@field vg NVGContextWrapper
---@field node Node
---@field material Material
local Meter={}
Meter.__index=Meter
local WIDTH,HEIGHT=720,120
local COUNT=20

local function rect(vg,x,y,w,h,color)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255));nvgFill(vg)
end

local function bulb(vg,x,y,r,color)
    nvgBeginPath(vg);nvgCircle(vg,x,y,r)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255));nvgFill(vg)
end

function Meter.New(cabinet)
    ---@type TimeMeter
    local self=setmetatable({cabinet=cabinet,phase="prepare",lit=COUNT,dirty=true},Meter)
    self.texture=Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(WIDTH,HEIGHT,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_NEAREST)
    self.vg=nvgCreate(1)
    nvgSetRenderTarget(self.vg,self.texture)
    nvgSetRenderOrder(self.vg,-92)

    self.node=cabinet.scene:CreateChild("LiveCountdownShutters")
    local geometry=self.node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((281+(uv[1]-.5)*180-210)/100,
            (420-690-(uv[2]-.5)*30)/100,-.18))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2();tc.x,tc.y=uv[1],uv[2]
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

function Meter:SetState(phase,elapsed)
    local lit=phase=="prepare" and COUNT or 0
    if phase=="running" then
        lit=math.max(0,math.min(COUNT,math.ceil((10-(elapsed or 0))*COUNT/10-0.000001)))
    elseif phase=="settle" then
        -- 结算缓冲阶段灯全灭：摇晃计时已经结束，统一结算前不显示进度。
        lit=0
    end
    if lit~=self.lit or phase~=self.phase then
        self.lit,self.phase,self.dirty=lit,phase,true
    end
end

function Meter:Render()
    if not self.dirty then return end
    local vg=self.vg
    nvgBeginFrame(vg,WIDTH,HEIGHT,1)
    rect(vg,0,0,WIDTH,HEIGHT,{0,0,0})
    -- Use the same round signal language as the score-progress lamps.
    rect(vg,8,9,704,102,{43,40,28})
    rect(vg,13,14,694,92,{103,94,57})
    rect(vg,18,19,684,82,{9,12,9})
    rect(vg,20,21,680,3,{85,77,46})
    rect(vg,20,97,680,3,{54,48,29})
    local signal={235,207,106}
    for i=1,COUNT do
        local x=36+(i-1)*34
        local live=i<=self.lit
        bulb(vg,x,59,16,{48,39,24})
        bulb(vg,x,59,13,{116,87,42})
        bulb(vg,x,59,10,{14,17,11})
        if live then
            bulb(vg,x,59,9,signal)
            bulb(vg,x-3,56,3,{255,239,172})
        else
            bulb(vg,x-3,56,2,{72,64,40})
        end
    end
    nvgEndFrame(vg)
    self.dirty=false
    self.cabinet.surface:QueueUpdate()
end

function Meter:Dispose()
    self.node:Remove()
    nvgDelete(self.vg)
    self.texture:Dispose()
end

return Meter
