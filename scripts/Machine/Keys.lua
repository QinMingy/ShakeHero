-- Two textured faces sit on the existing Blender keys. Original UI widgets
-- remain the hit targets and keep every upstream callback/disabled rule.
local Orientation=require("Machine.RenderOrientation")
---@type any
local Keys={}
Keys.__index=Keys

local slots={
    reroll={x=94,y=780,w=101,h=39,tw=242,th=94},
    shake={x=271,y=780,w=207,h=39,tw=480,th=94},
}

local function rectangle(vg,x,y,w,h,color)
    nvgBeginPath(vg)
    nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],255))
    nvgFill(vg)
end

local function face(scene,name,slot,texture)
    local node=scene:CreateChild("LiveKeyFace_"..name)
    local geometry=node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((slot.x+(uv[1]-.5)*slot.w-210)/100,
            (420-slot.y-(uv[2]-.5)*slot.h)/100,-.524))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2()
        tc.x,tc.y=uv[1],uv[2]
        geometry:DefineTexCoord(tc)
    end
    geometry:Commit()
    local material=Material:new()
    assert(material:SetSurfaceShader("Shaders/BLGL/MachineKey.shader"))
    assert(material:SetSurfaceTexture("label_map",texture))
    material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    material:SetShaderParameter("pulse",Variant(0.0))
    geometry:SetMaterial(material)
    geometry.castShadows=false
    return node,material
end

function Keys.New(cabinet)
    local self=setmetatable({cabinet=cabinet,slots={}},Keys)
    for name,config in pairs(slots) do
        local texture=Texture2D:new()
        texture:SetNumLevels(1)
        assert(texture:SetSize(config.tw,config.th,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
        texture:SetFilterMode(FILTER_BILINEAR)
        local vg=nvgCreate(1)
        nvgSetRenderTarget(vg,texture)
        nvgSetRenderOrder(vg,-90)
        nvgCreateFont(vg,"key-face","Fonts/SmileySans-Oblique.ttf")
        local node,material=face(cabinet.scene,name,config,texture)
        self.slots[name]={config=config,texture=texture,vg=vg,node=node,material=material,
            label="",enabled=false,dirty=true}
    end
    return self
end

function Keys:SetAction(name,label,enabled)
    local slot=assert(self.slots[name])
    if slot.label==label and slot.enabled==enabled then return end
    slot.label,slot.enabled,slot.dirty=label,enabled,true
    self.cabinet.surface:QueueUpdate()
end

function Keys:SetMotion(name,travel,pulse)
    local slot=self.slots[name]
    if not slot then return end
    slot.node.position=Vector3(0,0,travel)
    slot.material:SetShaderParameter("pulse",Variant(pulse))
end

function Keys:Render()
    local changed=false
    for name,slot in pairs(self.slots) do
        if slot.dirty then
            local vg,w,h=slot.vg,slot.config.tw,slot.config.th
            local live=slot.enabled
            nvgBeginFrame(vg,w,h,1)
            -- Keep the cap a single patinated metal surface; only its legend
            -- is painted, while the screws and bevel are physical parts.
            rectangle(vg,0,0,w,h,{0,0,0})
            nvgFontFace(vg,"key-face")
            nvgFontSize(vg,name=="shake" and 39 or 29)
            nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            local ink=name=="reroll" and (live and {48,43,28} or {73,67,47})
                or (live and {228,211,161} or {146,140,105})
            nvgFillColor(vg,nvgRGBA(ink[1],ink[2],ink[3],255))
            nvgText(vg,w*.5,h*.52,slot.label)
            nvgEndFrame(vg)
            slot.dirty=false
            changed=true
        end
    end
    if changed then self.cabinet.surface:QueueUpdate() end
end

function Keys:Dispose()
    for _,slot in pairs(self.slots) do
        slot.node:Remove()
        nvgDelete(slot.vg)
        slot.texture:Dispose()
    end
end

return Keys
