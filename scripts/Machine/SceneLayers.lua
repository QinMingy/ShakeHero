-- Keep the already-lit 3D image and dust separate from the transparent UI capture.
-- Both canvases use the same NanoVG orientation contract as the UI capture.
local UI=require("urhox-libs/UI")
---@type any
local Layers={};Layers.__index=Layers
function Layers.New(scene,post)
    local self=setmetatable({scene=scene,post=post,passes={}},Layers)
    for index,spec in ipairs({{"scene_map",scene.texture},{"dust_map",scene.fxTexture}}) do
        local pass={name=spec[1],vg=nvgCreate(0),dust=index==2}
        nvgSetRenderOrder(pass.vg,999987+index)
        pass.image=nvgCreateVideo(pass.vg,spec[2])
        assert(pass.image~=0,"Scene layer import failed")
        self.passes[#self.passes+1]=pass
        SubscribeToEvent(pass.vg,"NanoVGRender",function() self:Render(pass) end)
    end
    self:Resize(post.w,post.h)
    return self
end
function Layers:Resize(w,h)
    if self.disposed or not w or not h or (w==self.w and h==self.h) then return end
    for _,pass in ipairs(self.passes) do
        local texture=Texture2D:new();texture:SetNumLevels(1)
        assert(texture:SetSize(w,h,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
        texture:SetFilterMode(FILTER_BILINEAR)
        nvgSetRenderTarget(pass.vg,texture)
        assert(self.post.material:SetSurfaceTexture(pass.name,texture))
        if pass.texture then pass.texture:Dispose() end
        pass.texture=texture
    end
    self.w,self.h=w,h
end
function Layers:Render(pass)
    if self.disposed then return end
    local vg=pass.vg
    nvgBeginFrame(vg,self.w,self.h,1)
    nvgScale(vg,UI.GetScale(),UI.GetScale())
    -- Opaque dark backing for the scene, black for the additive dust layer.
    nvgBeginPath(vg);nvgRect(vg,0,0,UI.GetWidth(),UI.GetHeight())
    nvgFillColor(vg,pass.dust and nvgRGBA(0,0,0,255) or nvgRGBA(15,21,18,255));nvgFill(vg)
    local b=self.scene.bounds
    if b and self.scene.orientation.ready and (not pass.dust or self.scene.dustEnabled) then
        nvgSave(vg)
        -- The dust RTT already contains premultiplied additive RGB. Source-over
        -- would multiply alpha a second time and nearly erase the particles.
        if pass.dust then nvgGlobalCompositeBlendFunc(vg,NVG_ONE,NVG_ONE) end
        local source=b
        if not pass.dust then
            local s=self.scene.scale
            local guard=self.scene.renderGuard*s
            source={x=b.x-guard+self.scene.presentX*s,y=b.y-guard+self.scene.presentY*s,
                w=b.w+guard*2,h=b.h+guard*2}
        end
        nvgBeginPath(vg);nvgRect(vg,b.x,b.y,b.w,b.h)
        nvgFillPaint(vg,self.scene.orientation:Pattern(vg,source,pass.image));nvgFill(vg)
        nvgRestore(vg)
    end
    nvgEndFrame(vg)
end
function Layers:Dispose()
    if self.disposed then return end
    self.disposed=true
    for _,pass in ipairs(self.passes) do
        UnsubscribeFromEvent(pass.vg,"NanoVGRender")
        nvgDeleteVideo(pass.vg,pass.image);nvgSetRenderTarget(pass.vg,nil);nvgDelete(pass.vg)
        pass.texture:Dispose()
    end
end
return Layers
