-- 完整 UI 合成后进行泛光、纹理与暗角处理；不再执行景深模糊。
-- Uses public NanoVG RTT and SurfaceShader APIs; no engine library modifications.
local UI=require('urhox-libs/UI')
local Art=require('Bottle.Art')
---@type any
local Post={};Post.__index=Post
function Post.New()
    local self=setmetatable({enabled=true,bloom=true,edges=true},Post)
    self.scene=Scene();self.scene:CreateComponent('Octree')
    local cn=self.scene:CreateChild('PostCamera');cn.position=Vector3(0,0,-1)
    local c=cn:CreateComponent('Camera');c.orthographic=true;c.orthoSize=2
    c.autoAspectRatio=false;c.aspectRatio=1;c.nearClip=.01;c.farClip=3
    self.material=Material:new()
    assert(self.material:SetSurfaceShader('Shaders/BLGL/LayeredCinematic.shader'))
    assert(self.material:SetSurfaceTexture('noise_map',cache:GetResource('Texture2D','image/machine-structure-noise-v1.png')))
    local g=self.scene:CreateChild('PostQuad'):CreateComponent('CustomGeometry')
    g:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        g:DefineVertex(Vector3(uv[1]*2-1,1-uv[2]*2,0));g:DefineNormal(Vector3(0,0,-1))
        g:DefineTexCoord(Vector2(uv[1],uv[2]))
    end
    g:Commit();g:SetMaterial(self.material)
    self.viewport=Viewport:new(self.scene,c)
    local path=self.viewport:GetRenderPath():Clone()
    path:Load(assert(cache:GetResource('XMLFile','RenderPaths/Forward.xml')))
    self.viewport:SetRenderPath(path)
    self.vg=nvgCreate(0);nvgSetRenderOrder(self.vg,999995)
    self.uiContext=UI.GetNVGContext()
    self:Resize()
    -- 由入口 PostUpdate 调用 PrepareFrame，不能在 Widget.Render 中换 capture。
    SubscribeToEvent(self.vg,'NanoVGRender',function() self:Draw() end)
    return self
end
function Post:PrepareFrame()
    if self.disposed then return end
    self:Resize()
    if self.layers then self.layers:Resize(self.w,self.h) end
    if self.lampMask then self.lampMask:Resize(self.w,self.h) end
end
function Post:Resize()
    local w,h=graphics:GetWidth(),graphics:GetHeight()
    if w<=0 or h<=0 or (w==self.w and h==self.h) then return end
    local capture=Texture2D:new();capture:SetNumLevels(1)
    assert(capture:SetSize(w,h,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    capture:SetFilterMode(FILTER_BILINEAR)
    local output=Texture2D:new();output:SetNumLevels(1)
    assert(output:SetSize(w,h,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    output:SetFilterMode(FILTER_NEAREST)
    local surface=output:GetRenderSurface()
    surface:SetViewport(0,self.viewport);surface:SetUpdateMode(SURFACE_MANUALUPDATE)
    local image=nvgCreateVideo(self.vg,output)
    assert(image~=0,'Post render target unavailable')
    -- 新目标就绪后再改绑、释放旧目标；整个切换发生在渲染前。
    nvgSetRenderTarget(self.uiContext,capture)
    Art.SetOffscreenContext(self.uiContext,true)
    assert(self.material:SetSurfaceTexture('source_map',capture))
    if self.output then
        nvgDeleteVideo(self.vg,self.image)
        self.surface:SetNumViewports(0)
        self.output:Dispose();self.capture:Dispose()
    end
    self.w,self.h=w,h
    self.capture,self.output,self.surface,self.image=capture,output,surface,image
    self.material:SetShaderParameter('pixel_size',Variant(Vector2(1/w,1/h)))
end
function Post:Present(bounds)
    -- UI 的 BeginFrame 已经执行，这里只能提交参数，禁止替换其正在使用的 RTT。
    if self.disposed or not self.surface then return end
    -- 保留UI左上原点；shader用同帧mask原点标记转换RTT采样坐标。
    -- bounds已包含SafeArea胶囊避让与等比居中，不能按整屏再次居中或扣边距。
    self.material:SetShaderParameter('game_rect',Variant(Vector4(bounds.x/UI.GetWidth(),bounds.y/UI.GetHeight(),
        bounds.w/UI.GetWidth(),bounds.h/UI.GetHeight())))
    self.material:SetShaderParameter('effects',Variant(Vector4(self.bloom and 1 or 0,0,
        self.edges and 1 or 0,self.enabled and 1 or 0)))
    self.material:SetShaderParameter('noise_enabled',Variant(self.noiseEnabled and 1 or 0))
    self.surface:QueueUpdate()
end
function Post:Draw()
    -- 仅在自身事件中提交，不能在 UI 尚未结束的帧里嵌套另一 context。
    -- 屏幕呈现使用当前背缓冲尺寸，不把缓存 RTT 尺寸当作屏幕尺寸。
    local w,h=graphics:GetWidth(),graphics:GetHeight()
    if self.disposed or not self.image or w<=0 or h<=0 then return end
    nvgBeginFrame(self.vg,w,h,1)
    nvgBeginPath(self.vg);nvgRect(self.vg,0,0,w,h)
    nvgFillPaint(self.vg,nvgImagePattern(self.vg,0,0,w,h,0,self.image,1));nvgFill(self.vg)
    if self.drawDeveloperUi then self.drawDeveloperUi(self.vg) end
    nvgEndFrame(self.vg)
end
function Post:Toggle(which)
    self[which]=not self[which]
    print('[Machine.Cinematic] '..which..'='..tostring(self[which]))
end
function Post:Dispose()
    if self.disposed then return end
    self.disposed=true
    if self.layers then self.layers:Dispose() end
    UnsubscribeFromEvent(self.vg,'NanoVGRender')
    Art.SetOffscreenContext(self.uiContext,false)
    nvgSetRenderTarget(self.uiContext,nil)
    if self.image then nvgDeleteVideo(self.vg,self.image) end
    nvgDelete(self.vg)
    if self.surface then self.surface:SetNumViewports(0) end
    if self.output then self.output:Dispose() end
    if self.capture then self.capture:Dispose() end
    self.scene:Dispose()
end
return Post
