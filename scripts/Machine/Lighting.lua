-- Three practical accents light the cabinet and the surrounding workbench.
-- Positions and directions are in the cabinet's Y-up, front-negative-Z space.
local Lighting={}
---@param scene Scene
function Lighting.Build(scene)
    local zone=scene:CreateChild("CabinetAmbient"):CreateComponent("Zone")
    zone.boundingBox=BoundingBox(Vector3(-30,-30,-30),Vector3(30,30,30))
    zone.ambientSource=AMBIENT_COLOR
    zone.ambientColor=Color(.21,.205,.18,1)
    zone.fogStart,zone.fogEnd=25,30
    zone.autoExposureEnabled=false

    local keyNode=scene:CreateChild("WarmUpperLeftKey")
    keyNode.direction=Vector3(2.6,-7,5)
    local key=keyNode:CreateComponent("Light")
    key.lightType=LIGHT_DIRECTIONAL
    key.color=Color(1,.88,.66,1)
    key.brightness=2.2
    key.castShadows=true
    key.shadowBias=BiasParameters(.00015,.35)
    key.shadowCascade=CascadeParameters(20,0,0,0,.8)
    key.shadowIntensity=.28

    -- Local falloff emphasizes the lit upper-left edge instead of washing
    -- the entire face with the same brightness. Only the key casts shadows.
    local lampNode=scene:CreateChild("UpperLeftFalloff")
    lampNode.position=Vector3(-2.8,5,-3.2)
    local lamp=lampNode:CreateComponent("Light")
    lamp.lightType=LIGHT_POINT
    lamp.color=Color(1,.86,.62,1)
    lamp.brightness=12
    lamp.range=10
    lamp.castShadows=false
    -- A cool desk lamp separates the right edge from the warm upper-left key.
    -- The lower amber bounce is shorter range, so the button area gains depth
    -- without turning the whole workbench into a flat bright backdrop.
    local coolNode=scene:CreateChild("CoolDeskLamp")
    coolNode.position=Vector3(2.3,3.2,-2.2)
    local cool=coolNode:CreateComponent("Light")
    cool.lightType=LIGHT_POINT
    cool.color=Color(.48,.72,.78,1)
    cool.brightness=8
    cool.range=8
    cool.castShadows=false

    local bounceNode=scene:CreateChild("LowerAmberBounce")
    bounceNode.position=Vector3(-3.2,-4.9,-2.2)
    local bounce=bounceNode:CreateComponent("Light")
    bounce.lightType=LIGHT_POINT
    bounce.color=Color(1,.58,.30,1)
    bounce.brightness=3.7
    bounce.range=6
    bounce.castShadows=false

    -- A slow, localized sweep changes the light received by the actual
    -- geometry. The shadow-casting key remains fixed so small contact
    -- shadows do not wobble under the buttons and desk props.
    local sweepNode=scene:CreateChild("MovingDeskSpot")
    sweepNode.position=Vector3(-2.2,4.0,-3.1)
    sweepNode:LookAt(Vector3(-.8,2.4,0),Vector3.UP)
    local sweep=sweepNode:CreateComponent("Light")
    sweep.lightType=LIGHT_SPOT
    sweep.color=Color(1,.82,.57,1)
    sweep.brightness=40
    sweep.range=8
    sweep.fov=48
    sweep.castShadows=false
    renderer.drawShadows=true
    print("[Machine.Lighting] 工作台环境光、左上暖光与冷暖点光已启用")
    return {zone=zone,key=key,lamp=lamp,cool=cool,bounce=bounce,
        sweep=sweep,sweepNode=sweepNode,sweepTime=0,sweepPower=40}
end

function Lighting.Apply(rig,style)
    local function rgb(c) return Color(c[1],c[2],c[3],1) end
    rig.zone.ambientColor=rgb(style.ambient)
    rig.key.color=rgb(style.key)
    rig.lamp.color=rgb(style.lamp)
    rig.cool.color=rgb(style.cool)
    rig.bounce.color=rgb(style.bounce)
    rig.key.brightness=style.keyPower
    rig.lamp.brightness=style.lampPower
    rig.cool.brightness=style.coolPower
    rig.bounce.brightness=style.bouncePower
    rig.sweep.color=rgb(style.lamp)
    rig.sweepPower=style.lampPower*3.4
end

function Lighting.Tick(rig,dt)
    rig.sweepTime=rig.sweepTime+math.min(math.max(dt or 0,0),.1)
    local t=rig.sweepTime
    local x=-2.2+.35*math.sin(t*.28)
    local y=4.0
    local z=-3.1
    local targetX=-.75+1.15*math.sin(t*.42)
    local targetY=2.45+.37*math.sin(t*.33+1)
    rig.sweepNode.position=Vector3(x,y,z)
    rig.sweepNode:LookAt(Vector3(targetX,targetY,0),Vector3.UP)
    rig.sweep.brightness=rig.sweepPower*(.86+.14*math.sin(t*.46+.7))
end
return Lighting
