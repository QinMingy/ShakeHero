-- Painted lettering on the cabinet's existing plates. The retained UI widgets
-- still own their click regions; these planes only change presentation.
local Orientation=require("Machine.RenderOrientation")

---@type any
local Labels={}
Labels.__index=Labels

local specs={
    round={x=142,y=45,w=196,h=27,z=-.245,tw=588,th=81,font=60,
        face=Color(.77,.65,.37,1),recess=Color(.08,.07,.04,1)},
    help={x=290,y=44,w=50,h=24,z=-.282,tw=150,th=72,font=51,
        face=Color(.16,.13,.07,1),recess=Color(.78,.64,.36,1)},
    save={x=355,y=44,w=50,h=24,z=-.282,tw=150,th=72,font=51,
        face=Color(.16,.13,.07,1),recess=Color(.78,.64,.36,1)},
    gm={x=355,y=69,w=36,h=13,z=-.245,tw=108,th=39,font=31,
        face=Color(.63,.55,.34,1),recess=Color(.06,.06,.04,1)},
    hint={x=210,y=822,w=315,h=18,z=-.045,tw=945,th=54,font=51,
        face=Color(.67,.60,.38,1),recess=Color(.06,.06,.04,1)},
}

local function createPlane(scene,name,spec,texture)
    local node=scene:CreateChild("CabinetLettering_"..name)
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
    assert(material:SetSurfaceShader("Shaders/BLGL/MachineEngraving.shader"))
    assert(material:SetSurfaceTexture("label_map",texture))
    material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    material:SetShaderParameter("face_color",Variant(spec.face))
    material:SetShaderParameter("recess_color",Variant(spec.recess))
    geometry:SetMaterial(material)
    geometry.castShadows=false
    return node
end

function Labels.New(cabinet)
    local self=setmetatable({cabinet=cabinet,entries={}},Labels)
    self.vg=nvgCreate(1)
    nvgSetRenderOrder(self.vg,-89)
    assert(nvgCreateFont(self.vg,"engraved","Fonts/SmileySans-Oblique.ttf")~=-1)
    for name,spec in pairs(specs) do
        local texture=Texture2D:new()
        texture:SetNumLevels(1)
        assert(texture:SetSize(spec.tw,spec.th,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
        texture:SetFilterMode(FILTER_BILINEAR)
        self.entries[name]={spec=spec,texture=texture,
            node=createPlane(cabinet.scene,name,spec,texture),text="",dirty=true}
    end
    self:SetText("help","规则")
    self:SetText("save","存档")
    self:SetText("gm","GM")
    return self
end

function Labels:SetText(name,text)
    local entry=assert(self.entries[name])
    if entry.text==text then return end
    entry.text,entry.dirty=text,true
end

function Labels:SetRound(round)
    self:SetText("round","回合 "..tostring(((round-1)%5)+1).."/5")
end

function Labels:SetHint(text)
    self:SetText("hint",text)
end

function Labels:Render()
    local changed=false
    local vg=self.vg
    for _,entry in pairs(self.entries) do
        if entry.dirty then
            local spec=entry.spec
            nvgSetRenderTarget(vg,entry.texture)
            nvgBeginFrame(vg,spec.tw,spec.th,1)
            nvgBeginPath(vg);nvgRect(vg,0,0,spec.tw,spec.th)
            nvgFillColor(vg,nvgRGBA(0,0,0,255));nvgFill(vg)
            nvgFontFace(vg,"engraved")
            nvgFontSize(vg,spec.font)
            nvgTextAlign(vg,NVG_ALIGN_CENTER+NVG_ALIGN_MIDDLE)
            -- Red and green encode a shallow recess and its painted upper lip.
            -- MachineEngraving.shader converts them to restrained stamped ink.
            nvgFillColor(vg,nvgRGBA(255,0,0,255))
            nvgText(vg,spec.tw*.5+1,spec.th*.51+2,entry.text)
            nvgFillColor(vg,nvgRGBA(0,255,0,255))
            nvgText(vg,spec.tw*.5,spec.th*.5,entry.text)
            nvgEndFrame(vg)
            entry.dirty=false
            changed=true
        end
    end
    if changed then self.cabinet.surface:QueueUpdate() end
end

function Labels:Dispose()
    for _,entry in pairs(self.entries) do
        entry.node:Remove()
        entry.texture:Dispose()
    end
    nvgDelete(self.vg)
end

return Labels
