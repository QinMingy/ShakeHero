-- Blender mesh bridge. Based on scaffold-3d-scene + scene-to-nanovg recipe.
-- A retained 3D scene owns the editable parts; UI only supplies live text / hit areas.
local UI = require("urhox-libs/UI")
local Projection=require("Machine.Projection")
local Lighting=require("Machine.Lighting")
local PaperSway=require("Machine.PaperSway")
local BodySprite=require("Machine.BodySprite")
local Atmosphere=require("Machine.Atmosphere")
local Orientation=require("Machine.RenderOrientation")
local Clock=require("Machine.Clock")
local ScoreReels=require("Machine.ScoreReels")
local ProgressLamps=require("Machine.ProgressLamps")
local TimeMeter=require("Machine.TimeMeter")
local LowerReadout=require("Machine.LowerReadout")
local EngravedLabels=require("Machine.EngravedLabels")
---@type {name:string,module:string,material:string,textured:integer,emissive:integer,groups:{color:number[],vertices:number[]}[]}[]
local meshes = require("Machine.MeshData")
-- The triangle wave keeps the same cycle count as the old sine wave, but its
-- velocity reverses abruptly at each endpoint instead of easing through it.
local function TriangleWave(phase)
    return (2/math.pi)*math.asin(math.sin(phase))
end
local function ImpactOffset(age)
    local fade=(1-age)*math.exp(-4.2*age)
    return fade*TriangleWave(10.5*age),fade*TriangleWave(11.5*age)
end
---@class MachineCabinet
---@field scene Scene
---@field nodes table<string,Node>
---@field press table<string,boolean>
---@field materials table<string,Material>
---@field moodLampMaterials Material[]
---@field lightRig any
---@field paperSway {pivot:Node,time:number,parts:integer}
---@field bodySprite any
---@field atmosphereId string?
---@field atmosphere any
---@field moving table<string,Node[]>
---@field surface RenderSurface
---@field texture Texture2D
---@field viewport Viewport
---@field camera Camera
---@field cameraNode Node
---@field cameraBase Vector3
---@field cameraHitCount integer
---@field image integer?
---@field context NVGContextWrapper?
---@field warmupFrames_ integer
---@field screen any
---@field keyFaces any
---@field labels any
---@field keyMotion table<string,{position:number,velocity:number,pulse:number,strike:number}>
---@field cameraImpulses {age:number,amplitude:number,direction:number}[]
local Cabinet = {}
Cabinet.__index = Cabinet

function Cabinet.New()
    ---@type MachineCabinet
    local self = setmetatable({}, Cabinet)
    self.scene = Scene()
    self.scene:CreateComponent("Octree")
    self.lightRig=Lighting.Build(self.scene)
    self.nodes, self.press, self.materials = {}, {}, {}
    self.moodLampMaterials={}
    self.keyMotion={reroll={position=0,velocity=0,pulse=0,strike=0},
        shake={position=0,velocity=0,pulse=0,strike=0}}
    self.warmupFrames_=180
    self.moving={reroll={},shake={}}
    local metalTexture=assert(cache:GetResource("Texture2D","model/machine/metal-patina.png"))
    metalTexture:SetFilterMode(FILTER_NEAREST)
    local lightCookie=assert(cache:GetResource("Texture2D","image/machine-light-cookie.png"))
    lightCookie:SetFilterMode(FILTER_BILINEAR)
    for _, part in ipairs(meshes) do
        local node = self.scene:CreateChild(part.name)
        self.nodes[part.name] = node
        if self.moving[part.module] and
            (part.name==part.module.."_key" or part.name==part.module.."_highlight"
                or part.name:find("^"..part.module.."_cap_")
                or part.name:find("^"..part.module.."_trim_")
                or part.name:find("^"..part.module.."_screw")) then
            table.insert(self.moving[part.module],node)
        end
        local geometry = node:CreateComponent("CustomGeometry")
        geometry.castShadows = part.emissive~=1
        geometry:SetNumGeometries(#part.groups)
        for index, group in ipairs(part.groups) do
            geometry:BeginGeometry(index - 1, TRIANGLE_LIST)
            local vertices = group.vertices
            for i = 1, #vertices, 8 do
                geometry:DefineVertex(Vector3(vertices[i], vertices[i+1], vertices[i+2]))
                local normal=Vector3()
                normal.x,normal.y,normal.z=assert(vertices[i+5]),assert(vertices[i+6]),assert(vertices[i+7])
                geometry:DefineNormal(normal)
                local uv=Vector2()
                uv.x,uv.y=assert(vertices[i+3]),assert(vertices[i+4])
                geometry:DefineTexCoord(uv)
            end
        end
        geometry:Commit()
        for index, group in ipairs(part.groups) do
            local c = group.color
            local key = part.material..":"..table.concat(c, ",")..":"..part.textured..":"..part.emissive
            local mat = self.materials[key]
            if not mat then
                mat = Material:new()
                if part.textured==1 then
                    assert(mat:SetSurfaceShader("Shaders/BLGL/MachineMetal.shader"))
                    assert(mat:SetSurfaceTexture("patina_map",metalTexture))
                    assert(mat:SetSurfaceTexture("light_cookie",lightCookie))
                    mat:SetShaderParameter("metal_tint",Variant(Color(c[1]/255,c[2]/255,c[3]/255,1)))
                else
                    local technique=part.emissive==1 and "Techniques/NoTextureUnlit.xml"
                        or "Techniques/PBR/PBRNoTexture.xml"
                    mat:SetTechnique(0, assert(cache:GetResource("Technique",technique)))
                    mat:SetShaderParameter("MatDiffColor", Variant(Color(c[1]/255,c[2]/255,c[3]/255,1)))
                    mat:SetShaderParameter("Roughness",Variant(.78))
                    mat:SetShaderParameter("Metallic",Variant(0.0))
                end
                self.materials[key] = mat
                if part.material=="cool_lamp" then
                    self.moodLampMaterials[#self.moodLampMaterials+1]=mat
                end
            end
            geometry:SetMaterial(index - 1, mat)
        end
    end
    self.bodySprite=BodySprite.New(self.scene)
    self.paperSway=PaperSway.New(self.scene,self.nodes)
    local cameraNode = self.scene:CreateChild("PortraitCamera")
    -- View from the near end of the machine, exposing its lower return edges.
    self.cameraBase=Vector3(0,-Projection.distance*Projection.sin,-Projection.distance*Projection.cos)
    cameraNode.position = self.cameraBase
    cameraNode:LookAt(Vector3.ZERO,Vector3.UP)
    self.camera = cameraNode:CreateComponent("Camera")
    self.cameraNode=cameraNode
    self.breathTime=0
    self.cameraImpulses={}
    self.cameraHitCount=0
    self.camera.orthographic = false
    self.camera.fov = Projection.fovDegrees
    self.camera.autoAspectRatio = false
    self.camera.aspectRatio = 420/840
    self.camera.nearClip, self.camera.farClip = .1, 30
    self.texture = Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(420,840,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_NEAREST)
    self.viewport = Viewport:new(self.scene, self.camera)
    -- XMLFile overload is present at runtime; load explicitly for unambiguous LSP typing.
    local renderPath=self.viewport:GetRenderPath():Clone()
    renderPath:Load(assert(cache:GetResource("XMLFile", "RenderPaths/Forward.xml")))
    self.viewport:SetRenderPath(renderPath)
    local path = self.viewport:GetRenderPath()
    for i = 0,path:GetNumCommands()-1 do
        local command = path:GetCommand(i)
        if command.type == CMD_CLEAR then
            command.useFogColor = false
            command.clearColor = Color(.035,.038,.028,1)
        end
    end
    self.surface = self.texture:GetRenderSurface()
    self.surface:SetViewport(0,self.viewport)
    self.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    self.surface:QueueUpdate()
    self.clock=Clock.New(self)
    self.scoreReels=ScoreReels.New(self)
    self.progressLamps=ProgressLamps.New(self)
    self.timeMeter=TimeMeter.New(self)
    self.lowerReadout=LowerReadout.New(self)
    self.labels=EngravedLabels.New(self)
    self:SetAtmosphere("brass")
    print("[Machine] Blender机台已加载：" .. #meshes .. "个独立零件")
    return self
end

function Cabinet:SetAtmosphere(id)
    if self.atmosphereId==id then return end
    local style=assert(Atmosphere.styles[id])
    self.atmosphereId=id
    self.atmosphere=style
    for _,material in ipairs(self.moodLampMaterials) do
        local c=style.beacon
        material:SetShaderParameter("MatDiffColor",Variant(Color(c[1],c[2],c[3],1)))
    end
    Lighting.Apply(self.lightRig,style)
    BodySprite.SetAtmosphere(self.bodySprite,style)
    if self.screen then self.screen:SetAtmosphere(style) end
    self.surface:QueueUpdate()
end

function Cabinet:Press(name, pressed)
    if not self.keyMotion[name] then return end
    if self.press[name] == pressed then return end
    self.press[name] = pressed
    if pressed then self.keyMotion[name].pulse=math.max(self.keyMotion[name].pulse,.7) end
    self.surface:QueueUpdate()
end

function Cabinet:Activate(name)
    local motion=self.keyMotion[name]
    if not motion then return end
    motion.pulse=1
    -- A quick tap still completes the full mechanical stroke before release.
    motion.strike=.12
    self:CameraImpact(name)
    self.surface:QueueUpdate()
end

function Cabinet:CameraImpact(name)
    self.cameraHitCount=self.cameraHitCount+1
    if #self.cameraImpulses>=3 then table.remove(self.cameraImpulses,1) end
    self.cameraImpulses[#self.cameraImpulses+1]={
        age=0,
        amplitude=name=="shake" and .073 or name=="reroll" and .053 or .027,
        direction=self.cameraHitCount%2==0 and 1 or -1,
    }
end

function Cabinet:Tick(dt)
    local changed=false
    Lighting.Tick(self.lightRig,dt)
    PaperSway.Tick(self.paperSway,dt)
    if self.clock then self.clock:Tick(dt) end
    if self.scoreReels then self.scoreReels:Tick(dt) end
    local cameraDt=math.min(math.max(dt or 0,0),.1)
    -- Keep the camera's initial rotation fixed. Breathing and button impacts
    -- translate the camera in X/Y only; the cabinet itself does not move.
    self.breathTime=self.breathTime+cameraDt
    local t=self.breathTime
    local shakeX,shakeY=0,0
    for i=#self.cameraImpulses,1,-1 do
        local impulse=self.cameraImpulses[i]
        impulse.age=impulse.age+cameraDt
        if impulse.age>1 then
            table.remove(self.cameraImpulses,i)
        else
            local kickX,kickY=ImpactOffset(impulse.age)
            shakeX=shakeX+impulse.amplitude*kickX*impulse.direction
            shakeY=shakeY+impulse.amplitude*.8*kickY
        end
    end
    local base=self.cameraBase
    local offsetX=math.max(-.15,math.min(.15,
        .045*math.sin(.65*t)+.014*math.sin(1.31*t)+shakeX))
    local offsetY=math.max(-.11,math.min(.11,
        .033*math.sin(.53*t)+.012*math.sin(1.17*t)+shakeY))
    self.cameraNode.position=Vector3(
        base.x+offsetX,
        base.y+offsetY,
        base.z)
    local position=self.cameraNode.position
    -- Move the projection target by the same offset, preserving the original
    -- forward vector for CRT input mapping without rotating the camera.
    Projection.SetCameraPose(position.x,position.y,position.z,offsetX,offsetY,0)
    changed=true
    dt=math.min(math.max(dt or 0,0),1/30)
    for name,motion in pairs(self.keyMotion) do
        local target=(self.press[name] or motion.strike>0) and .118 or 0
        if math.abs(motion.position-target)>.0001 or math.abs(motion.velocity)>.0001
            or motion.pulse>0 or motion.strike>0 then
            motion.velocity=motion.velocity+(target-motion.position)*480*dt
            motion.velocity=motion.velocity*math.exp(-17*dt)
            motion.position=math.max(-.018,math.min(.13,motion.position+motion.velocity*dt))
            motion.strike=math.max(0,motion.strike-dt)
            motion.pulse=math.max(0,motion.pulse-dt*3.1)
            for _,node in ipairs(self.moving[name]) do
                node.position=Vector3(0,0,motion.position)
            end
            if self.keyFaces then self.keyFaces:SetMotion(name,motion.position,motion.pulse) end
            changed=true
        end
    end
    if changed then self.surface:QueueUpdate() end
end

function Cabinet:Draw(vg,l)
    -- Local preview streams materials after scene creation. Refresh the target
    -- during initial frames so the cabinet does not wait for the first click.
    if self.warmupFrames_>0 then
        self.surface:QueueUpdate()
        self.warmupFrames_=self.warmupFrames_-1
    end
    if not self.image then
        self.image = nvgCreateVideo(vg,self.texture)
        self.context = vg
        assert(self.image ~= 0,"Machine render target unavailable")
    end
    -- nvgCreateVideo already corrects the Web RTT origin. Android retains
    -- its compatibility flip, shared with the live screen and key textures.
    nvgSave(vg)
    if Orientation.Current() then
        nvgTranslate(vg,l.x,l.y+l.h)
        nvgScale(vg,1,-1)
    else
        nvgTranslate(vg,l.x,l.y)
    end
    nvgBeginPath(vg)
    nvgRect(vg,0,0,l.w,l.h)
    nvgFillPaint(vg,nvgImagePattern(vg,0,0,l.w,l.h,0,self.image,1))
    nvgFill(vg)
    nvgRestore(vg)
end

function Cabinet:Dispose()
    if self.labels then self.labels:Dispose(); self.labels=nil end
    if self.lowerReadout then self.lowerReadout:Dispose(); self.lowerReadout=nil end
    if self.timeMeter then self.timeMeter:Dispose(); self.timeMeter=nil end
    if self.progressLamps then self.progressLamps:Dispose(); self.progressLamps=nil end
    if self.scoreReels then self.scoreReels:Dispose(); self.scoreReels=nil end
    if self.clock then self.clock:Dispose(); self.clock=nil end
    if self.keyFaces then self.keyFaces:Dispose(); self.keyFaces=nil end
    if self.screen then self.screen:Dispose(); self.screen=nil end
    if self.image then nvgDeleteVideo(self.context,self.image); self.image=nil end
    self.surface:SetNumViewports(0)
    self.texture:Dispose()
    self.scene:Dispose()
end

---@class MachineBackground : Widget
---@field cabinet any
---@overload fun(props:WidgetProps): MachineBackground
local Background = UI.Widget:Extend("MachineBackground") --[[@as MachineBackground]]
function Background:Init(props)
    UI.Widget.Init(self,props)
    self.cabinet=props.cabinet
end
function Background:Render(vg)
    if self.cabinet.keyFaces then self.cabinet.keyFaces:Render() end
    if self.cabinet.clock then self.cabinet.clock:Render() end
    if self.cabinet.scoreReels then self.cabinet.scoreReels:Render() end
    if self.cabinet.progressLamps then self.cabinet.progressLamps:Render() end
    if self.cabinet.timeMeter then self.cabinet.timeMeter:Render() end
    if self.cabinet.lowerReadout then self.cabinet.lowerReadout:Render() end
    if self.cabinet.labels then self.cabinet.labels:Render() end
    local bounds=self:GetAbsoluteLayout()
    self.cabinet:Draw(vg,bounds)
    -- The reference treats light as part of a layered illustration. Add a
    -- restrained moving wash over the header/desk, while the 3D spot still
    -- shapes the real bevels. Keep it off the active board and lower controls.
    local lightTime=self.cabinet.breathTime or 0
    nvgSave(vg)
    nvgScissor(vg,bounds.x,bounds.y,bounds.w,bounds.h*.30)
    local lightX=bounds.x+bounds.w*(.36+.33*math.sin(lightTime*.42))
    local lightY=bounds.y+bounds.h*(.15+.025*math.sin(lightTime*.33+1))
    local lightRadius=bounds.w*.34
    nvgBeginPath(vg)
    nvgRect(vg,bounds.x,bounds.y,bounds.w,bounds.h*.30)
    nvgFillPaint(vg,nvgRadialGradient(vg,lightX,lightY,
        lightRadius*.08,lightRadius,
        nvgRGBA(245,209,143,83),nvgRGBA(245,209,143,0)))
    nvgFill(vg)
    nvgRestore(vg)
    -- A restrained rectangular vignette frames the scene. Draw it behind
    -- widgets so score and action labels retain their full contrast.
    nvgSave(vg)
    nvgBeginPath(vg)
    nvgRect(vg,bounds.x,bounds.y,bounds.w,bounds.h)
    nvgFillPaint(vg,nvgBoxGradient(vg,
        bounds.x+bounds.w*.105,bounds.y+bounds.h*.07,
        bounds.w*.79,bounds.h*.86,0,bounds.w*.18,
        nvgRGBA(0,0,0,0),nvgRGBA(0,0,0,70)))
    nvgFill(vg)
    -- Out-of-focus desk shadows soften the corners without darkening the
    -- physical readouts at the centre of the machine.
    nvgScissor(vg,bounds.x,bounds.y,bounds.w,bounds.h)
    for index,spot in ipairs({
        {-.05,.025,.14,74},{.075,-.01,.105,63},{.19,.005,.075,43},
        {.97,.015,.16,78},{1.07,.08,.11,64},{.87,-.025,.08,41},
        {-.04,.96,.11,36},{1.04,1.02,.13,42},
    }) do
        local radius=spot[3]*bounds.w
        local driftX=.025*math.sin(lightTime*.26+index*1.7)
        local driftY=.013*math.sin(lightTime*.20+index*.9)
        local cx=bounds.x+(spot[1]+driftX)*bounds.w
        local cy=bounds.y+(spot[2]+driftY)*bounds.h
        nvgBeginPath(vg)
        nvgCircle(vg,cx,cy,radius)
        nvgFillPaint(vg,nvgRadialGradient(vg,cx,cy,radius*.15,radius,
            nvgRGBA(0,0,0,spot[4]),nvgRGBA(0,0,0,0)))
        nvgFill(vg)
    end
    nvgRestore(vg)
end
function Background:Update(dt)
    self.cabinet:Tick(dt)
end
function Background:Destroy()
    self.cabinet:Dispose()
    UI.Widget.Destroy(self)
end
Cabinet.Background = Background
return Cabinet
