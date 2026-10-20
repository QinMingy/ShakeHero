-- 卡通消灭：目标原色轻抖、快速退场，硬边像素烟团在原位置展开并消散。
-- 使用固定烟团模板，不使用玩法 RNG。烟不追随攻击者，不持有物理对象。
local Smoke = {LIFETIME=.42, HIT=.09, FADE=.1}
local Draw = require("Bottle.ItemFeedbackDraw")
local PUFFS = {{-1,.2,1.0},{-.55,1.0,.8},{.2,1.25,1.05},{.95,.65,.85},{.85,-.4,.7},{-.35,-.65,.65}}

---@param pose BottleConsumedPose
---@return number x, number y, number scale, number alpha
function Smoke.VisualPose(pose)
    local t = math.min(1, pose.age / Smoke.HIT)
    local shake = math.sin(t * math.pi * 5) * (1 - t) * .055
    local fade = math.max(0, math.min(1, (pose.age - Smoke.HIT) / Smoke.FADE))
    return pose.x + shake, pose.y, 1 + .07 * math.sin(t * math.pi), 1 - fade
end

---@param vg NVGContextWrapper
---@param pose BottleConsumedPose
---@param x number
---@param y number
---@param ppu number
local function KillerSlash(vg, pose, x, y, ppu)
    -- 刀光盖在灰烟前面，起手保持明亮、末段迅速淡出。
    if pose.consumerId == "killer" and pose.age < .24 then
        local cut = math.max(0, math.min(1, pose.age/.24))
        local reach = math.max(.22, math.min(.5, pose.radius))*ppu*(.65+cut*.6)
        local cx, cy = x+pose.x*ppu, y-pose.y*ppu
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        for side = -1, 1, 2 do
            Draw.PixelLine(vg, cx-reach, cy-side*reach*.7, cx+reach, cy+side*reach*.7,
                math.max(2,ppu*.055), {235,55,65}, 245*math.min(1,(1-cut)/.35))
        end
        nvgRestore(vg)
    end
end

---@param vg NVGContextWrapper
---@param pose BottleConsumedPose
---@param x number
---@param y number
---@param ppu number
function Smoke.Render(vg, pose, x, y, ppu)
    local t = math.max(0, math.min(1, (pose.age - Smoke.HIT) / (Smoke.LIFETIME - Smoke.HIT)))
    if t <= 0 or t >= 1 then KillerSlash(vg, pose, x, y, ppu); return end
    local radius = math.max(.2, math.min(.6, pose.radius)) * ppu
    local cx, cy = x + pose.x * ppu, y - pose.y * ppu - t * radius * .65
    local alpha = math.floor(230 * math.min(1, t / .16) * (1 - t) ^ .7)
    local spread = .2 + t * .95
    local pixel = math.max(1, math.floor(ppu * .025))
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    for index, puff in ipairs(PUFFS) do
        if pose.emphasis or index % 2 == 1 then
            local size = math.max(pixel, math.floor(radius * puff[3] * (.38 + t * .25) / pixel) * pixel)
            local px = math.floor((cx + puff[1] * radius * spread - size / 2) / pixel) * pixel
            local py = math.floor((cy - puff[2] * radius * spread - size / 2) / pixel) * pixel
            nvgBeginPath(vg)
            nvgRect(vg, px - pixel, py, size + pixel * 2, size)
            nvgRect(vg, px, py - pixel, size, size + pixel * 2)
            nvgFillColor(vg, nvgRGBA(39, 49, 46, alpha))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, size, size)
            local light = index % 2 == 0 and 183 or 153
            nvgFillColor(vg, nvgRGBA(light, light + 9, light + 5, alpha))
            nvgFill(vg)
        end
    end
    nvgRestore(vg)
    KillerSlash(vg, pose, x, y, ppu)
end

return Smoke
