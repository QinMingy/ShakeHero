-- A painted, perspective-correct cabinet face. Live controls and CRT remain
-- separate layers in front; the heavy 3D back shell still gives side depth.
local BodySprite={}

local function createPlane(scene,name,filename,depth)
    local texture=assert(cache:GetResource("Texture2D","image/"..filename))
    texture:SetFilterMode(FILTER_NEAREST)
    local node=scene:CreateChild(name)
    local geometry=node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((uv[1]-.5)*4.2,(.5-uv[2])*8.4,depth))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2();tc.x,tc.y=uv[1],uv[2]
        geometry:DefineTexCoord(tc)
    end
    geometry:Commit()
    local material=Material:new()
    assert(material:SetSurfaceShader("Shaders/BLGL/MachineBodySprite.shader"))
    assert(material:SetSurfaceTexture("body_map",texture))
    geometry:SetMaterial(material)
    geometry.castShadows=false
    return node,material
end

function BodySprite.New(scene)
    local base,baseMaterial=createPlane(scene,"PaintedCabinetBase",
        "machine-body-2d.png",-.225)
    local ink,inkMaterial=createPlane(scene,"PaintedCabinetInk",
        "machine-ink-2d.png",-.315)
    return {base=base,ink=ink,materials={baseMaterial,inkMaterial}}
end

function BodySprite.SetAtmosphere(body,style)
    local c=style.bodyTint
    for _,material in ipairs(body.materials) do
        material:SetShaderParameter("mood_tint",Variant(Color(c[1],c[2],c[3],1)))
    end
end

return BodySprite
