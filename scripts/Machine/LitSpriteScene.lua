-- Scene scaffold + scene-to-nanovg recipe. Original PNG slices become individual
-- alpha-cutout, lit planes with depth; UI still owns text and interaction.
-- Reference mechanism: EVIDENCE.md / sharedassets0:50,210 / level0:5318.
-- Does NOT claim to recover the proprietary Sprite With Depth graph.
local L=require("Machine.LayeredLayout")
local Dust=require("Machine.DustField")
local Post=require("Machine.CinematicPost")
local Motion=require("Machine.AmbientMotion")
local Orientation=require("Machine.SpriteOrientation")
local SceneLayers=require("Machine.SceneLayers")
---@type any
local SceneSkin={}
SceneSkin.__index=SceneSkin
function SceneSkin.New()
    local self=setmetatable({parts={},materials={},count=0,depth=0,time=0,noiseEnabled=true,
        cameraMotionEnabled=true,dustEnabled=true,motionX=0,motionY=0,
        shakeX=0,shakeY=0,shakeVX=0,shakeVY=0,
        presentX=0,presentY=0,frameStats={count=0,elapsed=0,maxDt=0,slow=0}},SceneSkin)
    self.scene=Scene();self.scene:CreateComponent("Octree")
    local zone=self.scene:CreateChild("SpriteAmbient"):CreateComponent("Zone")
    zone.boundingBox=BoundingBox(Vector3(-20,-20,-20),Vector3(20,20,20))
    zone.ambientSource=AMBIENT_COLOR
    zone.ambientColor=Color(.22,.24,.21,1)
    zone.fogStart,zone.fogEnd=25,30
    zone.autoExposureEnabled=false
    self.zone=zone
    local ln=self.scene:CreateChild("SpriteDirectionalKey")
    ln.direction=Vector3(.75,-.9,1)
    local light=ln:CreateComponent("Light")
    -- 主光保持白色；暖黄／黄绿色来自材质、调色及带色Bloom。
    light.lightType=LIGHT_DIRECTIONAL;light.color=Color(1,1,1,1);light.brightness=2.76
    light.castShadows=true
    light.shadowBias=BiasParameters(.0001,.2)
    light.shadowCascade=CascadeParameters(20,0,0,0,.8)
    light.shadowIntensity=.18
    self.light=light
    -- 数据遮罩按线性R通道读取，全机台与浮尘共用同一张纹理。
    local cookie=assert(cache:GetResource("Texture2D","image/machine-light-cookie-wide.png"))
    cookie:SetSRGB(false)
    cookie:SetFilterMode(FILTER_BILINEAR)
    cookie:SetAddressMode(COORD_U,ADDRESS_WRAP)
    cookie:SetAddressMode(COORD_V,ADDRESS_WRAP)
    self.cookieTexture=cookie
    self.previousDrawShadows=renderer.drawShadows
    self.previousShadowQuality=renderer.shadowQuality
    self.previousShadowSoftness=renderer.shadowSoftness
    renderer.drawShadows=true
    renderer.shadowQuality=SHADOWQUALITY_SIMPLE_24BIT
    renderer.shadowSoftness=0
    local cn=self.scene:CreateChild("SpritePerspectiveCamera")
    self.distance=(L.height/200)/math.tan(math.rad(38/2))
    cn.position=Vector3(0,0,-self.distance)
    self.cameraNode=cn
    local camera=cn:CreateComponent("Camera")
    -- Two source samples per design pixel, plus a small guard for fractional
    -- presentation offsets. Source sprite textures remain nearest-filtered.
    self.renderGuard=2
    local renderW,renderH=L.width+self.renderGuard*2,L.height+self.renderGuard*2
    camera.orthographic=false
    camera.fov=math.deg(2*math.atan(math.tan(math.rad(38/2))*renderH/L.height))
    camera.autoAspectRatio=false;camera.aspectRatio=renderW/renderH
    camera.nearClip,camera.farClip=.1,30
    camera.viewMask=1
    self.texture=Texture2D:new();self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(renderW*2,renderH*2,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    -- Interpolate the final subpixel translation, not the source pixel art.
    self.texture:SetFilterMode(FILTER_BILINEAR)
    self.viewport=Viewport:new(self.scene,camera)
    local renderPath=self.viewport:GetRenderPath():Clone()
    renderPath:Load(assert(cache:GetResource("XMLFile","RenderPaths/Forward.xml")))
    self.viewport:SetRenderPath(renderPath)
    local path=self.viewport:GetRenderPath()
    for i=0,path:GetNumCommands()-1 do
        local command=path:GetCommand(i)
        if command.type==CMD_CLEAR then command.useFogColor=false;command.clearColor=Color(.02,.03,.025,1) end
    end
    self.surface=self.texture:GetRenderSurface()
    self.surface:SetViewport(0,self.viewport);self.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    self.post=Post.New()
    self.dust=Dust.New(self.scene,self.cookieTexture)
    self.dust.set.viewMask=2
    -- Dust lives in front of the machine, including the UI display content.
    -- Render the same world/camera/light to a transparent layer, then composite
    -- its already-lit RGB additively. No screen-space particle simulation.
    local fn=self.scene:CreateChild("DustCamera")
    self.dustCameraNode=fn
    fn.position=cn.position
    local fc=fn:CreateComponent("Camera")
    fc.fov=38;fc.autoAspectRatio=false;fc.aspectRatio=L.width/L.height
    fc.nearClip=.1;fc.farClip=30;fc.viewMask=2
    self.fxTexture=Texture2D:new();self.fxTexture:SetNumLevels(1)
    assert(self.fxTexture:SetSize(804,1748,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.fxTexture:SetFilterMode(FILTER_NEAREST)
    self.fxViewport=Viewport:new(self.scene,fc)
    local fp=path:Clone()
    for i=0,fp:GetNumCommands()-1 do
        local c=fp:GetCommand(i)
        if c.type==CMD_CLEAR then c.useFogColor=false;c.clearColor=Color(0,0,0,0) end
    end
    self.fxViewport:SetRenderPath(fp)
    self.fxSurface=self.fxTexture:GetRenderSurface()
    self.fxSurface:SetViewport(0,self.fxViewport);self.fxSurface:SetUpdateMode(SURFACE_MANUALUPDATE)
    self.orientation=Orientation.New(path)
    self.post.layers=SceneLayers.New(self,self.post)
    assert(self.post.material:SetSurfaceTexture("cookie_map",self.cookieTexture))
    print(string.format("[Machine.Render] source=%dx%d subpixel=on max_fps=%d inactive_fps=%d timestep_smoothing=%d",
        renderW*2,renderH*2,engine:GetMaxFps(),engine:GetMaxInactiveFps(),engine:GetTimeStepSmoothing()))
    print("[Machine.LitSprites] independent alpha-cutout planes / PBR matte / directional shadows / perspective 38deg")
    return self
end
function SceneSkin:Tick(dt)
    self.orientation:Tick()
    self.time=self.time+dt
    if self.cameraMotionEnabled then self.motionX,self.motionY=Motion.Sample(self.time)
    else self.motionX,self.motionY=0,0 end
    -- 屏幕震动弹簧：回零速度略快，避免连续加分数时抖动累积。
    if dt>0 then
        local stiffness,damping=220,16
        self.shakeVX=self.shakeVX+(-stiffness*self.shakeX-damping*self.shakeVX)*dt
        self.shakeX=self.shakeX+self.shakeVX*dt
        self.shakeVY=self.shakeVY+(-stiffness*self.shakeY-damping*self.shakeVY)*dt
        self.shakeY=self.shakeY+self.shakeVY*dt
        if math.abs(self.shakeX)<.01 and math.abs(self.shakeVX)<.01 then self.shakeX,self.shakeVX=0,0 end
        if math.abs(self.shakeY)<.01 and math.abs(self.shakeVY)<.01 then self.shakeY,self.shakeVY=0,0 end
    end
    local rasterX,rasterY
    rasterX,self.presentX=Motion.Split(self.motionX)
    rasterY,self.presentY=Motion.Split(self.motionY)
    self.cameraNode.position=Vector3(-(rasterX+self.shakeX)/100,(rasterY+self.shakeY)/100,-self.distance)
    -- Dust is already rendered independently at 2x and keeps continuous motion.
    self.dustCameraNode.position=Vector3(-(self.motionX+self.shakeX)/100,(self.motionY+self.shakeY)/100,-self.distance)
    local stats=self.frameStats
    if dt>0 then
        stats.count=stats.count+1;stats.elapsed=stats.elapsed+dt
        stats.maxDt=math.max(stats.maxDt,dt)
        if dt>1/30 then stats.slow=stats.slow+1 end
    end
    for name,material in pairs(self.materials) do
        if name:find("foliage",1,true) then
            material:SetShaderParameter("wind_time",Variant(self.time))
        end
        if name~="structure-noise" then
            material:SetShaderParameter("cookie_time",Variant(self.time))
        end
    end
    if self.dustEnabled then self.dust:Tick(dt,self.time) end
    if math.floor(self.time/8)~=math.floor((self.time-dt)/8) then
        print(string.format("[Machine.Motion] time=%.2f camera_px=(%.3f,%.3f) residual_px=(%.3f,%.3f) update_fps=%.1f max_frame_ms=%.2f over_33ms=%d",
            self.time,self.motionX,self.motionY,self.presentX,self.presentY,
            stats.count/math.max(stats.elapsed,.0001),stats.maxDt*1000,stats.slow))
        stats.count=0;stats.elapsed=0;stats.maxDt=0;stats.slow=0
    end
end
function SceneSkin:Begin(vg,b,s)
    self.bounds=b;self.scale=s;self.count=0;self.depth=0
    -- 3D is composed separately; UI capture now contains only UI pixels.
end
-- Elevation describes the physical stack, never accumulated draw-call order.
function SceneSkin:Layer(elevation) self.depth=elevation or -.09 end
function SceneSkin:ToggleCameraMotion()
    self.cameraMotionEnabled=not self.cameraMotionEnabled
    -- 统一刷新相机和参考平面；不冻结风、光纹、灰尘的共享时间。
    self:Tick(0)
    print("[表现GM] 镜头动画="..tostring(self.cameraMotionEnabled))
end
function SceneSkin:ToggleDust()
    self.dustEnabled=not self.dustEnabled
    self.dust.node.enabled=self.dustEnabled
    print("[表现GM] 浮尘="..tostring(self.dustEnabled))
end
function SceneSkin:ToggleNoise()
    self.noiseEnabled=not self.noiseEnabled
    print("[Machine.LitSprites] structure noise enabled="..tostring(self.noiseEnabled))
end
-- 屏幕震动：叠加一个短暂位移冲量，由 Tick 内的弹簧回零。
-- 单位是设计像素；场景相机与 UI 参考平面共用同一偏移，保持贴合。
function SceneSkin:AddShake(x,y)
    self.shakeX=math.max(-8,math.min(8,self.shakeX+(x or 0)))
    self.shakeY=math.max(-8,math.min(8,self.shakeY+(y or 0)))
end
-- 将经过整卡变换的四边形裁到机台拉出窗口，再插值回源UV。
-- 裁剪同时用于彩色与真实阴影，不在CRT正文上残留已收回的底板。
local function clippedUV(x,y,w,h,t)
    if not t or not t.clipTop then return nil end
    local c,a=math.cos(t.angle),math.sin(t.angle)
    local zoom=t.scale or 1
    local polygon={}
    local inside=true
    for _,uv in ipairs({{0,0},{1,0},{1,1},{0,1}}) do
        local dx,dy=x+uv[1]*w-t.cx,y+uv[2]*h-t.cy
        local px=t.cx+zoom*(c*dx-a*dy)+(t.x or 0)
        local py=t.cy+zoom*(a*dx+c*dy)+(t.y or 0)
        polygon[#polygon+1]={px,py,uv[1],uv[2]}
        if px<t.clipLeft or px>t.clipRight or py<t.clipTop or py>t.clipBottom then inside=false end
    end
    if inside then return nil end
    for _,edge in ipairs({{1,t.clipLeft,1},{1,t.clipRight,-1},{2,t.clipTop,1},{2,t.clipBottom,-1}}) do
        local output={}
        if #polygon==0 then break end
        local previous=polygon[#polygon]
        local pd=(previous[edge[1]]-edge[2])*edge[3]
        for _,point in ipairs(polygon) do
            local d=(point[edge[1]]-edge[2])*edge[3]
            if (d>=0)~=(pd>=0) then
                local fraction=pd/(pd-d)
                local hit={}
                for i=1,4 do hit[i]=previous[i]+(point[i]-previous[i])*fraction end
                output[#output+1]=hit
            end
            if d>=0 then output[#output+1]=point end
            previous=point;pd=d
        end
        polygon=output
    end
    local vertices={}
    for i=2,#polygon-1 do
        for _,point in ipairs({polygon[1],polygon[i],polygon[i+1]}) do
            vertices[#vertices+1]={point[3],point[4]}
        end
    end
    return vertices
end
function SceneSkin:Quad(name,x,y,w,h,tileW,tileH,transform)
    self.count=self.count+1
    local index=self.count
    local p=self.parts[index]
    if not p then
        local node=self.scene:CreateChild("PixelSlice_"..index)
        p={node=node,geometry=node:CreateComponent("CustomGeometry")};self.parts[index]=p
        p.geometry.viewMask=1
    end
    p.node.enabled=true
    local s,b=self.scale,self.bounds
    local dx,dy,dw,dh=(x-b.x)/s,(y-b.y)/s,w/s,h/s
    local tw,th=(tileW or w)/s,(tileH or h)/s
    local depth=name=="desk" and 2.0 or self.depth
    -- 九宫格九块共用整卡枢轴；节点变换同时驱动彩色与真实阴影，
    -- 动画不重建网格／材质，也不改 UI 的固定命中框。
    if transform then
        local perspective=(self.distance+depth)/self.distance
        local pivot=Vector3(((transform.cx-b.x)/s-L.width/2)/100*perspective,
            (L.height/2-(transform.cy-b.y)/s)/100*perspective,0)
        local rotation=Quaternion(-math.deg(transform.angle),Vector3.FORWARD)
        local zoom=transform.scale or 1
        p.node.scale=Vector3(zoom,zoom,1)
        p.node.rotation=rotation
        p.node.position=pivot-rotation*(pivot*zoom)
            +Vector3((transform.x or 0)/s/100*perspective,-transform.y/s/100*perspective,0)
    else
        p.node.scale=Vector3.ONE
        p.node.position=Vector3.ZERO
        p.node.rotation=Quaternion(0,Vector3.FORWARD)
    end
    local clipped=clippedUV(x,y,w,h,transform)
    if clipped and #clipped==0 then p.node.enabled=false;return end
    local signature=table.concat({name,dx,dy,dw,dh,tw,th,depth},":")
    if clipped then
        local values={signature}
        for _,uv in ipairs(clipped) do values[#values+1]=uv[1];values[#values+1]=uv[2] end
        signature=table.concat(values,":")
    end
    if p.signature==signature then return end
    p.signature=signature
    p.foliage=name:find("foliage",1,true)~=nil
    local material=self.materials[name]
    if not material then
        if name=="target-progress" then
            material=Material:new()
            assert(material:SetSurfaceShader("Shaders/BLGL/TargetProgress.shader"))
        elseif name=="structure-noise" then
            material=Material:new()
            assert(material:SetSurfaceShader("Shaders/BLGL/LayeredStructureNoise.shader"))
            assert(material:SetSurfaceTexture("noise_map",cache:GetResource("Texture2D","image/machine-structure-noise-v1.png")))
            material.renderOrder=240
        else
        local foliage=name:find("foliage",1,true)~=nil
        local texture=assert(cache:GetResource("Texture2D",foliage and "image/machine-foreground-leaf-pixel.png" or "image/machine-layered/"..name..".png"))
        texture:SetFilterMode(FILTER_NEAREST)
        -- 彩色、阴影与深度共用此纹理；显式 repeat，避免超出 0..1 的平铺 UV 被钳制。
        if not foliage then
            texture:SetAddressMode(COORD_U,ADDRESS_WRAP)
            texture:SetAddressMode(COORD_V,ADDRESS_WRAP)
        end
        material=Material:new()
        local bulb=name=="crt-bulb-a" or name=="crt-bulb-b"
        assert(material:SetSurfaceShader(foliage and "Shaders/BLGL/LayeredFoliage.shader"
            or bulb and "Shaders/BLGL/LayeredBulbLit.shader" or "Shaders/BLGL/LayeredSpriteLit.shader"))
        assert(material:SetSurfaceTexture("sprite_map",texture))
        if foliage then
            material.renderOrder=225
            material:SetShaderParameter("wind_time",Variant(self.time))
        end
        end
        if name~="structure-noise" then
            assert(material:SetSurfaceTexture("cookie_map",self.cookieTexture))
            material:SetShaderParameter("cookie_time",Variant(self.time))
        end
        self.materials[name]=material
    end
    local geometry=p.geometry
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    -- Compensate small depth offsets to retain approved pixel layout and hit boxes.
    local perspective=(self.distance+depth)/self.distance
    local vertices=clipped or {}
    local columns,rows=p.foliage and 3 or 1,p.foliage and 8 or 1
    if not clipped then
        for row=0,rows-1 do for column=0,columns-1 do
            for _,corner in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
                vertices[#vertices+1]={(column+corner[1])/columns,(row+corner[2])/rows}
            end
        end end
    end
    for _,uv in ipairs(vertices) do
        local pos=Vector3((dx+uv[1]*dw-L.width/2)/100*perspective,
            (L.height/2-dy-uv[2]*dh)/100*perspective,depth)
        local u,v=uv[1]*dw/tw,uv[2]*dh/th
        if name=="foliage-2" or name=="foliage-4" then u=1-u end
        if name=="foliage-1" or name=="foliage-2" then v=1-v end
        geometry:DefineVertex(pos);geometry:DefineNormal(Vector3(0,0,-1));geometry:DefineTexCoord(Vector2(u,v))
    end
    geometry:Commit();geometry:SetMaterial(material)
    geometry.castShadows=name~="screen-5" and name~="structure-noise" and name~="target-progress"
        and not name:find("foliage",1,true) and name:sub(1,5)~="felt-"
end
function SceneSkin:Finish(vg)
    local b=self.bounds
    self.depth=-2.5
    -- The original noise plane covers the composed Unity scene. Here UI is a
    -- separate renderer, so apply its multiply algebra after the UI capture.
    self.post.noiseEnabled=self.noiseEnabled
    if self.post.edges then
        self.depth=-3.6
        local s=self.scale
        self:Quad("foliage-1",b.x-90*s,b.y-78*s,150*s,235*s)
        self:Quad("foliage-2",b.x+b.w-40*s,b.y-68*s,140*s,205*s)
        self:Quad("foliage-3",b.x-105*s,b.y+b.h-155*s,150*s,235*s)
        self:Quad("foliage-4",b.x+b.w-40*s,b.y+b.h-136*s,145*s,204*s)
    end
    for i=self.count+1,#self.parts do self.parts[i].node.enabled=false end
    self.surface:QueueUpdate()
    if self.dustEnabled then
        self.fxSurface:QueueUpdate()
    end
    self.post.material:SetShaderParameter("cookie_time",Variant(self.time))
    self.post.material:SetShaderParameter("ui_camera_offset",Variant(Vector2(-self.motionX/100,self.motionY/100)))
    self.post:Present(b)
end
function SceneSkin:Dispose()
    self.orientation:Dispose()
    self.post:Dispose()
    renderer.drawShadows=self.previousDrawShadows
    renderer.shadowQuality=self.previousShadowQuality
    renderer.shadowSoftness=self.previousShadowSoftness
    if self.image then nvgDeleteVideo(self.context,self.image) end
    if self.fxImage then nvgDeleteVideo(self.context,self.fxImage) end
    self.fxSurface:SetNumViewports(0);self.fxTexture:Dispose()
    self.surface:SetNumViewports(0);self.texture:Dispose();self.scene:Dispose()
end
return SceneSkin
