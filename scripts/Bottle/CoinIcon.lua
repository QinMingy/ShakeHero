-- 独立金币贴图：标题、摇晃计数与飞币共用同一张透明像素图。
local UI = require("urhox-libs/UI")
local Coin = {}
---@type table<any, integer>
local images = {}

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param radius number
---@param turn number?
function Coin.Draw(vg, x, y, radius, turn)
    if radius <= 0 then return end
    local handle = images[vg]
    if not handle then
        handle = nvgCreateImage(vg, "image/bottle/round-coin.png", NVG_IMAGE_NEAREST)
        assert(handle > 0, "Missing coin: image/bottle/round-coin.png")
        images[vg] = handle
    end
    nvgSave(vg)
    nvgTranslate(vg, x, y)
    if turn then nvgScale(vg, .65 + .35 * math.abs(math.cos(turn)), 1) end
    nvgBeginPath(vg)
    nvgRect(vg, -radius, -radius, radius * 2, radius * 2)
    nvgFillPaint(vg, nvgImagePattern(vg, -radius, -radius, radius * 2, radius * 2, 0, handle, 1))
    nvgFill(vg)
    nvgRestore(vg)
end

---@param vg NVGContextWrapper
function Coin.Release(vg)
    local handle = images[vg]
    if handle then nvgDeleteImage(vg, handle) end
    images[vg] = nil
end

---@class BottleCoinIcon : Widget
---@overload fun(props:WidgetProps): BottleCoinIcon
local Icon = UI.Widget:Extend("BottleCoinIcon") --[[@as BottleCoinIcon]]
function Icon:Render(vg)
    local b = self:GetAbsoluteLayout()
    Coin.Draw(vg, b.x + b.w / 2, b.y + b.h / 2, math.min(b.w, b.h) / 2)
end
Coin.Widget = Icon
return Coin
