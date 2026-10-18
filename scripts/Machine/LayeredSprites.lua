-- 独立九宫格贴图：四角保护螺丝，边条和底纹按同一像素密度平铺。
---@type any
local Sprites={}
Sprites.__index=Sprites
-- 切片与原图严格对应；12px 边距完整包住角部装饰，不能切回旧的 8px。
local panels={
    green={width=118,height=49,inset=12},
    metal={width=118,height=49,inset=12},
    gold={width=118,height=49,inset=12},
    wood={width=117,height=49,inset=12},
    felt={width=117,height=114,inset=12},
    screen={width=116,height=114,inset=12},
}
function Sprites.New()
    return setmetatable({contexts={}},Sprites)
end
-- 底纹周期使用源像素尺寸，不再用横纵倍率不同的硬编码周期。
function Sprites:CenterTile(kind,scale)
    local p=assert(panels[kind],"未知九宫格材质："..tostring(kind))
    return (p.width-2*p.inset)*scale,(p.height-2*p.inset)*scale
end
function Sprites:Image(vg,name)
    local images=self.contexts[vg]
    if not images then images={};self.contexts[vg]=images end
    if not images[name] then
        local handle=nvgCreateImage(vg,"image/machine-layered/"..name..".png",
            NVG_IMAGE_NEAREST|NVG_IMAGE_REPEATX|NVG_IMAGE_REPEATY)
        assert(handle>0,"Missing layered sprite: "..name)
        images[name]=handle
    end
    return images[name]
end
function Sprites:Draw(vg,name,x,y,w,h,tileW,tileH,transform)
    if w<=0 or h<=0 then return end
    if self.scene then self.scene:Quad(name,x,y,w,h,tileW,tileH,transform);return end
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillPaint(vg,nvgImagePattern(vg,x,y,tileW or w,tileH or h,0,self:Image(vg,name),1))
    nvgFill(vg)
end
function Sprites:Panel(vg,kind,x,y,w,h,scale,frameOnly,elevation,transform)
    if w<=0 or h<=0 then return end
    local p=assert(panels[kind],"未知九宫格材质："..tostring(kind))
    if self.scene then self.scene:Layer(elevation or (frameOnly and -.095 or -.09)) end
    -- 小控件也只等比缩小四角，不拉长螺丝、不让相邻角块重叠。
    local pixel=math.min(scale,w/(2*p.inset),h/(2*p.inset))
    local c=p.inset*pixel
    local xs,ys={x,x+c,x+w-c},{y,y+c,y+h-c}
    local ws,hs={c,w-2*c,c},{c,h-2*c,c}
    local sourceW,sourceH={p.inset,p.width-2*p.inset,p.inset},
        {p.inset,p.height-2*p.inset,p.inset}
    for row=1,3 do for col=1,3 do
        local i=(row-1)*3+col
        if not frameOnly or i~=5 then
            -- 横边仅沿 X 平铺，竖边仅沿 Y 平铺，中心双轴平铺，四角完整保留。
            self:Draw(vg,kind.."-"..i,xs[col],ys[row],ws[col],hs[row],
                sourceW[col]*pixel,sourceH[row]*pixel,transform)
        end
    end end
end
function Sprites:Dispose()
    for vg,images in pairs(self.contexts) do
        for _,handle in pairs(images) do nvgDeleteImage(vg,handle) end
    end
    self.contexts={}
end
return Sprites
