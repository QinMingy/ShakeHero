-- 用户提供的透明 PNG；原图保留不变，仅在绘制时避开四周透明留白。
local Icon = {}
---@type table<any, integer>
local images = {}
local SOURCE_SIZE = 1254
-- 主体 alpha >= 128 的边界外保留 8px，完整容纳手、金币和闪光。
local LEFT, TOP, WIDTH, HEIGHT = 144, 139, 910, 994

---@param vg NVGContextWrapper
---@param x number 图标中心
---@param y number 图标中心
---@param radius number 图标方框半宽，沿用 Art.StatIcon 的尺寸契约
function Icon.Draw(vg, x, y, radius)
    if radius <= 0 then return end
    local handle = images[vg]
    if not handle then
        handle = nvgCreateImage(vg, "image/bottle/gain-hand-coin.png", NVG_IMAGE_NEAREST)
        assert(handle > 0, "Missing gain icon: image/bottle/gain-hand-coin.png")
        images[vg] = handle
    end
    local scale = radius * 2 / math.max(WIDTH, HEIGHT)
    local width, height = WIDTH * scale, HEIGHT * scale
    local left, top = x - width / 2, y - height / 2
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgBeginPath(vg)
    nvgRect(vg, left, top, width, height)
    nvgFillPaint(vg, nvgImagePattern(vg, left - LEFT * scale, top - TOP * scale,
        SOURCE_SIZE * scale, SOURCE_SIZE * scale, 0, handle, 1))
    nvgFill(vg)
    nvgRestore(vg)
end

---@param vg NVGContextWrapper
function Icon.Release(vg)
    local handle = images[vg]
    if handle then nvgDeleteImage(vg, handle) end
    images[vg] = nil
end

return Icon
