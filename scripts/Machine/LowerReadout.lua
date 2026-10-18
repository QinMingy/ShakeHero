-- Two compact stamped readouts on the lower cabinet. The invisible upstream
-- inventory button still owns its original click and disabled behavior.
local Orientation=require("Machine.RenderOrientation")

---@class LowerReadout
---@field cabinet any
---@field vg NVGContextWrapper
---@field entries table<string,any>
local Readout={}
Readout.__index=Readout

local specs={
    claw={x=239,y=730,w=104,h=24,tw=312,th=72,z=-.250},
    deck={x=340,y=730,w=80,h=22,tw=240,th=66,z=-.250},
}

local function rect(vg,x,y,w,h,color)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255));nvgFill(vg)
end

local function plane(scene,name,spec,texture)
    local node=scene:CreateChild("LowerReadout_"..name)
    local geometry=node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((spec.x+(uv[1]-.5)*spec.w-210)/100,
            (420-spec.y-(uv[2]-.5)*spec.h)/100,spec.z))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2();tc.x,tc.y=uv[1],uv[2]
        geometry:DefineTexCoord(tc)
    end
    geometry:Commit()
    local material=Material:new()
    assert(material:SetSurfaceShader("Shaders/BLGL/MachinePanel.shader"))
    assert(material:SetSurfaceTexture("label_map",texture))
    material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    geometry:SetMaterial(material)
    geometry.castShadows=false
    return node
end

function Readout.New(cabinet)
    ---@type LowerReadout
    local self=setmetatable({cabinet=cabinet,entries={}},Readout)
    self.vg=nvgCreate(1)
    nvgSetRenderOrder(self.vg,-91)
    assert(nvgCreateFont(self.vg,"lower-stamp","Fonts/SmileySans-Oblique.ttf")~=-1)
    for name,spec in pairs(specs) do
        local texture=Texture2D:new()
        texture:SetNumLevels(1)
        assert(texture:SetSize(spec.tw,spec.th,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
        texture:SetFilterMode(FILTER_BILINEAR)
        self.entries[name]={spec=spec,texture=texture,
            node=plane(cabinet.scene,name,spec,texture),text="",enabled=true,dirty=true}
    end
    return self
end

function Readout:SetValues(claw,deck,deckEnabled)
    local values={claw="爪击 +"..tostring(claw),deck="牌库 "..tostring(deck)}
    for name,entry in pairs(self.entries) do
        local enabled=name~="deck" or deckEnabled
        if entry.text~=values[name] or entry.enabled~=enabled then
            entry.text,entry.enabled,entry.dirty=values[name],enabled,true
        end
    end
end

function Readout:Render()
    local changed=false
    for _,entry in pairs(self.entries) do
        if entry.dirty then
            local spec=entry.spec
            local vg,w,h=self.vg,spec.tw,spec.th
            nvgSetRenderTarget(vg,entry.texture)
            nvgBeginFrame(vg,w,h,1)
            rect(vg,0,0,w,h,{0,0,0})
            rect(vg,2,2,w-4,h-4,{78,65,39})
            rect(vg,5,5,w-10,h-10,{21,25,17})
            rect(vg,8,8,w-16,2,{119,99,56})
            rect(vg,8,h-10,w-16,2,{52,48,33})
            nvgFontFace(vg,"lower-stamp")
            nvgFontSize(vg,33)
            nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            nvgFillColor(vg,nvgRGBA(27,25,17,255))
            nvgText(vg,w*.5+1,h*.52+2,entry.text)
            nvgFillColor(vg,entry.enabled and nvgRGBA(221,202,137,255)
                or nvgRGBA(114,111,85,255))
            nvgText(vg,w*.5,h*.5,entry.text)
            nvgEndFrame(vg)
            entry.dirty=false
            changed=true
        end
    end
    if changed then self.cabinet.surface:QueueUpdate() end
end

function Readout:Dispose()
    for _,entry in pairs(self.entries) do
        entry.node:Remove()
        entry.texture:Dispose()
    end
    nvgDelete(self.vg)
end

return Readout
