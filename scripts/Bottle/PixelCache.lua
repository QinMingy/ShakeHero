-- Load the baked source pixels through NanoVG's explicit nearest-image path.
-- One atlas per context; no video-texture import or runtime image uploads.
---@type any
local Cache={}
local Atlas=require("Bottle.PixelAtlasData")
---@type table<any,integer>
local contexts={}
---@type table<BottlePixelSprite,any>
local regions={}

-- Also used by art-source/bottle/build_pixel_atlas.py. Sort groups because
-- palette pairs() order varies between Lua processes. Changed art falls back
-- to rectangles until its atlas is rebuilt.
---@param sprite BottlePixelSprite
---@return string
function Cache.Fingerprint(sprite)
    local groups={}
    for _,group in ipairs(sprite.groups) do
        if #group.rects>0 then
            local c=group.color
            groups[#groups+1]=table.concat({c[1],c[2],c[3],c[4] or 255},",")
                ..":"..table.concat(group.rects,",")
        end
    end
    table.sort(groups)
    local source=sprite.width.."x"..sprite.height..":"..table.concat(groups,";")
    local hash=2166136261
    for i=1,#source do hash=((hash ~ source:byte(i))*16777619) & 0xffffffff end
    return string.format("%08x",hash)
end

---@return boolean drawn Falls back if the atlas is missing, stale or unsupported.
---@param vg NVGContextWrapper
---@param sprite BottlePixelSprite
---@param x number
---@param y number
---@param width number
---@param height number
---@param cooling boolean?
function Cache.Draw(vg,sprite,x,y,width,height,cooling)
    if width<=0 or height<=0 then return true end
    local region=regions[sprite]
    if region==nil then
        region=Atlas.regions[Cache.Fingerprint(sprite)] or false
        regions[sprite]=region
    end
    if not region then return false end
    local handle=contexts[vg]
    if handle==nil then
        -- Do not substitute a default filter if this backend lacks the flag.
        if type(NVG_IMAGE_NEAREST)=="number" then
            handle=nvgCreateImage(vg,Atlas.path,NVG_IMAGE_NEAREST)
            if handle>0 then
                local w,h=nvgImageSize(vg,handle)
                if w~=Atlas.width or h~=Atlas.height then
                    nvgDeleteImage(vg,handle);handle=0
                end
            else handle=0 end
        else handle=0 end
        contexts[vg]=handle
        if handle==0 then print("[像素缓存] 最近邻图集不可用，沿用矩形绘制") end
    end
    if handle==0 then return false end
    local sx,sy=width/region[3],height/region[4]
    local ox,oy=region[1],region[2]
    if cooling then ox,oy=region[5],region[6] end
    nvgBeginPath(vg);nvgRect(vg,x,y,width,height)
    nvgFillPaint(vg,nvgImagePattern(vg,x-ox*sx,y-oy*sy,
        Atlas.width*sx,Atlas.height*sy,0,handle,1))
    nvgFill(vg)
    return true
end

---@param vg NVGContextWrapper
function Cache.Release(vg)
    local handle=contexts[vg]
    if handle and handle>0 then nvgDeleteImage(vg,handle) end
    contexts[vg]=nil
end

return Cache
