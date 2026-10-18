-- 与 UI capture 同尺寸、同方向的灯面遮罩，供后处理提取实际亮部。
local UI=require("urhox-libs/UI")
local Core=require("urhox-libs.UI.Core.UI")
---@type any
local Mask={};Mask.__index=Mask
function Mask.New(view,display,post)
    local self=setmetatable({view=view,display=display,post=post},Mask)
    self.vg=nvgCreate(0);nvgSetRenderOrder(self.vg,999989)
    self:Resize(post.w,post.h)
    post.lampMask=self
    SubscribeToEvent(self.vg,"NanoVGRender",function() self:Render() end)
    return self
end
function Mask:Resize(w,h)
    if self.disposed or not w or not h or w<=0 or h<=0 or (w==self.w and h==self.h) then return end
    local texture=Texture2D:new();texture:SetNumLevels(1)
    assert(texture:SetSize(w,h,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    texture:SetFilterMode(FILTER_BILINEAR)
    nvgSetRenderTarget(self.vg,texture)
    assert(self.post.material:SetSurfaceTexture("lamp_mask",texture))
    if self.texture then self.texture:Dispose() end
    self.w,self.h=w,h
    self.texture=texture
end
function Mask:Render()
    if self.disposed or not self.texture then return end
    local vg=self.vg;local scale=UI.GetScale()
    -- 固定用实际 RTT 物理尺寸开帧，再缩放绘图；避免 UI 缓存尺寸或浮点往返扩大 scissor。
    nvgBeginFrame(vg,self.w,self.h,1)
    nvgScale(vg,scale,scale)
    nvgBeginPath(vg);nvgRect(vg,0,0,self.w/scale,self.h/scale)
    nvgFillColor(vg,nvgRGBA(0,0,0,255));nvgFill(vg)
    -- G通道的左上角标记只供后效识别NanoVG RTT原点，不参与红通道灯面mask。
    -- 放在整屏原点，不跟随机台／胶囊移动；与source_map使用同一绘图契约。
    nvgBeginPath(vg);nvgRect(vg,0,0,4/scale,4/scale)
    nvgFillColor(vg,nvgRGBA(0,255,0,255));nvgFill(vg)
    local view=self.view
    local active=view.game.phase=="running" and not view.modal:IsVisible() and not view.definitionModal:IsVisible()
    self.post.material:SetShaderParameter("lamp_bloom_active",Variant(active and 1 or 0))
    if active then
        local bounds=Core.GetVisualRect(view.machineSkin.screenAssembly.lamps)
        local scene=view.machineSkin.litScene
        local s=view.machineSkin.scale
        -- UI跟随参考平面，灯面位于更近的3D深度，补齐透视微动差。
        local perspective=(scene.distance+self.display.bulbDepth)/scene.distance
        local offsetX=scene.motionX*s*(1/perspective-1)
        local offsetY=scene.motionY*s*(1/perspective-1)
        nvgShapeAntiAlias(vg,0)
        for i,lamp in ipairs(self.display.lamps) do
            if self.display.LampLevel(i,view.game.phase,view.game.elapsed)>.5 then
                nvgBeginPath(vg);nvgRect(vg,bounds.x+offsetX+(lamp.x-3)*s,bounds.y+offsetY+(lamp.y-3)*s,6*s,6*s)
                nvgFillColor(vg,nvgRGBA(255,255,255,255));nvgFill(vg)
            end
        end
    end
    nvgEndFrame(vg)
end
function Mask:Dispose()
    if self.disposed then return end
    self.disposed=true
    if self.post.lampMask==self then self.post.lampMask=nil end
    UnsubscribeFromEvent(self.vg,"NanoVGRender")
    nvgDelete(self.vg)
    if self.texture then self.texture:Dispose() end
end
return Mask
