-- 原生运行包的3D RTT导入方向可能不同；用同一离屏图内的相对色序校准。
-- 不采样用户画面，不写存档；Web沿用已正常的nvgCreateVideo契约。
local Platform=require("urhox-libs/Platform/PlatformUtils")
local Legacy=require("Machine.RenderOrientation")
---@type any
local Orientation={}
Orientation.__index=Orientation
local function colorSign(c)
    if c.r>.65 and c.g<.25 and c.b<.25 then return 1 end
    if c.b>.65 and c.g<.25 and c.r<.25 then return -1 end
    return 0
end
local function compare(image)
    if not image or image:GetWidth()~=32 or image:GetHeight()~=16 then return nil end
    local result
    for _,y in ipairs({3,4,11,12}) do
        local sampled=colorSign(image:GetPixel(8,y))
        local reference=colorSign(image:GetPixel(24,y))
        if sampled==0 or reference==0 then return nil end
        local flipped=sampled~=reference
        if result~=nil and result~=flipped then return nil end
        result=flipped
    end
    if colorSign(image:GetPixel(24,4))==colorSign(image:GetPixel(24,12)) then return nil end
    return result
end
function Orientation.New(renderPath)
    local self=setmetatable({ready=Platform.IsWebPlatform(),flipY=false,renders=0,
        attempts=0,lastRead=0,matches=0,materials={}},Orientation)
    if self.ready then return self end
    self.scene=Scene();self.scene:CreateComponent("Octree")
    local node=self.scene:CreateChild("OrientationCamera");node.position=Vector3(0,0,-1)
    local camera=node:CreateComponent("Camera")
    camera.orthographic=true;camera.orthoSize=2;camera.autoAspectRatio=false;camera.aspectRatio=1
    camera.nearClip=.01;camera.farClip=3
    for index,entry in ipairs({{1,Color(1,0,0,1)},{0,Color(0,0,1,1)}}) do
        local material=Material:new()
        material:SetTechnique(0,assert(cache:GetResource("Technique","Techniques/NoTextureUnlit.xml")))
        material:SetShaderParameter("MatDiffColor",Variant(entry[2]))
        material.cullMode=CULL_NONE
        self.materials[#self.materials+1]=material
        local geometry=self.scene:CreateChild("OrientationMarker"..index):CreateComponent("CustomGeometry")
        geometry:BeginGeometry(0,TRIANGLE_LIST)
        for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
            geometry:DefineVertex(Vector3(uv[1]*2-1,entry[1]-uv[2],0))
            geometry:DefineNormal(Vector3(0,0,-1))
        end
        geometry:Commit();geometry:SetMaterial(material)
    end
    self.source=Texture2D:new();self.source:SetNumLevels(1)
    assert(self.source:SetSize(16,16,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.source:SetFilterMode(FILTER_NEAREST)
    self.viewport=Viewport:new(self.scene,camera);self.viewport:SetRenderPath(renderPath:Clone())
    self.surface=self.source:GetRenderSurface()
    self.surface:SetViewport(0,self.viewport);self.surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    self.output=Texture2D:new();self.output:SetNumLevels(1)
    assert(self.output:SetSize(32,16,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.vg=nvgCreate(0);nvgSetRenderTarget(self.vg,self.output)
    self.image=nvgCreateVideo(self.vg,self.source)
    assert(self.image~=0,"Sprite orientation render target unavailable")
    SubscribeToEvent(self.vg,"NanoVGRender",function() self:Render() end)
    return self
end
function Orientation:Render()
    if self.ready or self.disposed then return end
    self.surface:QueueUpdate()
    nvgBeginFrame(self.vg,32,16,1)
    nvgBeginPath(self.vg);nvgRect(self.vg,0,0,16,16)
    nvgFillPaint(self.vg,nvgImagePattern(self.vg,0,0,16,16,0,self.image,1));nvgFill(self.vg)
    for index,c in ipairs({nvgRGBA(255,0,0,255),nvgRGBA(0,0,255,255)}) do
        nvgBeginPath(self.vg);nvgRect(self.vg,16,(index-1)*8,16,8)
        nvgFillColor(self.vg,c);nvgFill(self.vg)
    end
    nvgEndFrame(self.vg)
    self.renders=self.renders+1
end
function Orientation:Tick()
    if self.ready or self.disposed or self.renders-self.lastRead<4 then return end
    self.lastRead=self.renders;self.attempts=self.attempts+1
    -- 延至后续Update读回，必须识别出有效红蓝且连续两次一致；黑帧不能当作同向。
    local ok,image=pcall(self.output.GetImage,self.output)
    local result
    if ok and image then
        local valid,value=pcall(compare,image)
        image:Dispose()
        if valid then result=value end
    end
    if result~=nil then
        self.matches=self.candidate==result and self.matches+1 or 1
        self.candidate=result
        if self.matches>=2 then self.flipY=result;self.ready=true end
    else self.matches=0 end
    if not self.ready and self.attempts>=4 then
        self.flipY=Legacy.Current();self.ready=true
        print("[Sprite方向] 校准未知，使用旧兼容值；平台="..Platform.GetPlatform()
            .." API="..graphics:GetApiName().." flipY="..tostring(self.flipY))
    elseif self.ready then
        print("[Sprite方向] 实测校准；平台="..Platform.GetPlatform().." API="..graphics:GetApiName()
            .." binary="..tostring(GetBinaryVersion()).." flipY="..tostring(self.flipY))
    end
    if self.ready then self:ReleaseProbe() end
end
function Orientation:Pattern(vg,b,image)
    -- 只改变源图采样，不移动目标矩形或普通UI的布局／点击坐标。
    return nvgImagePattern(vg,b.x,self.flipY and b.y+b.h or b.y,b.w,
        self.flipY and -b.h or b.h,0,image,1)
end
function Orientation:ReleaseProbe()
    if not self.vg or self.probeReleased then return end
    self.probeReleased=true
    UnsubscribeFromEvent(self.vg,"NanoVGRender")
    nvgSetRenderTarget(self.vg,nil)
    nvgDeleteVideo(self.vg,self.image);nvgDelete(self.vg)
    self.surface:SetNumViewports(0)
    -- Retain the tiny 16x16/32x16 probe ownership graph for the scene lifetime.
    -- On this runtime, explicitly disposing source while its RenderSurface Lua
    -- wrapper survives causes a later __gc -> RenderSurface destructor to use
    -- the freed parent texture (reproduced native access violation).
    -- Rendering and subscriptions are stopped; these resources no longer work.
    self.vg=nil
end
function Orientation:Dispose()
    if self.disposed then return end
    self.disposed=true;self:ReleaseProbe()
end
return Orientation
