-- Discrete score-progress bulbs mapped onto the cabinet's long round glass.
-- The existing game score/target remains the sole source of progress.
local Orientation=require("Machine.RenderOrientation")

---@class ProgressLamps
---@field cabinet any
---@field lit integer
---@field dirty boolean
---@field texture Texture2D
---@field vg NVGContextWrapper
---@field node Node
---@field material Material
local Lamps={}
Lamps.__index=Lamps
local COUNT=20
local WIDTH,HEIGHT=1024,96

local function circle(vg,x,y,r,color)
    nvgBeginPath(vg);nvgCircle(vg,x,y,r)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],color[4] or 255));nvgFill(vg)
end

function Lamps.New(cabinet)
    ---@type ProgressLamps
    local self=setmetatable({cabinet=cabinet,lit=0,dirty=true},Lamps)
    self.texture=Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(WIDTH,HEIGHT,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_BILINEAR)
    self.vg=nvgCreate(1)
    nvgSetRenderOrder(self.vg,-93)

    self.node=cabinet.scene:CreateChild("LiveProgressLamps")
    local geometry=self.node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3(((uv[1]-.5)*326)/100,
            (420-174-(uv[2]-.5)*28)/100,-.243))
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

function Lamps:SetProgress(score,target)
    local progress=target>0 and math.max(0,math.min(1,score/target)) or 0
    local lit=math.floor(progress*COUNT+0.000001)
    if lit~=self.lit then self.lit=lit;self.dirty=true end
end

function Lamps:Render()
    if not self.dirty then return end
    local vg=self.vg
    nvgSetRenderTarget(vg,self.texture)
    nvgBeginFrame(vg,WIDTH,HEIGHT,1)
    nvgBeginPath(vg);nvgRect(vg,0,0,WIDTH,HEIGHT)
    nvgFillColor(vg,nvgRGBA(4,5,3,255));nvgFill(vg)
    local signal={235,207,106}
    for i=1,COUNT do
        local x=26+(i-.5)*(WIDTH-52)/COUNT
        circle(vg,x,HEIGHT/2,24,{38,26,11})
        circle(vg,x,HEIGHT/2,19,{119,85,36})
        circle(vg,x,HEIGHT/2,15,{13,13,8})
        if i<=self.lit then
            circle(vg,x,HEIGHT/2,23,{246,171,48,44})
            circle(vg,x,HEIGHT/2,14,{signal[1],signal[2],signal[3],230})
            circle(vg,x-4,HEIGHT/2-5,5,{255,235,164,235})
        else
            circle(vg,x-4,HEIGHT/2-5,4,{75,62,37})
        end
    end
    nvgEndFrame(vg)
    self.dirty=false
    self.cabinet.surface:QueueUpdate()
end

function Lamps:Dispose()
    self.node:Remove()
    self.texture:Dispose()
    nvgDelete(self.vg)
end

return Lamps
