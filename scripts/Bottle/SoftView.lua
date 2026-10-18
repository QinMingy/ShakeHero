-- 软体物品的显示、拾取与结算残留统一读取真实分段姿态。
local Art = require("Bottle.Art")
local SoftView = {}

---@param vg NVGContextWrapper
---@param poses BottleSoftPose[]
---@param x number 瓶底屏幕原点
---@param y number
---@param ppu number 米到UI逻辑像素
---@param cooling boolean?
function SoftView.Draw(vg, poses, x, y, ppu, cooling)
    for _, pose in ipairs(poses) do
        Art.BaconSegment(vg, x + pose.x * ppu, y - pose.y * ppu, -pose.angle,
            pose.halfLength * ppu, pose.halfWidth * ppu, pose.u0, pose.u1, cooling)
    end
end

---@param physics BottlePhysics
---@param uid integer
---@param x number
---@param y number
---@param ppu number
---@return {x:number,y:number,w:number,h:number}?
function SoftView.Bounds(physics, uid, x, y, ppu)
    local poses = physics:GetSoftPose(uid)
    if not poses then return nil end
    local minX, minY, maxX, maxY = math.huge, math.huge, -math.huge, -math.huge
    for _, pose in ipairs(poses) do
        local cosine, sine = math.abs(math.cos(pose.angle)), math.abs(math.sin(pose.angle))
        local ex = cosine * pose.halfLength + sine * pose.halfWidth
        local ey = sine * pose.halfLength + cosine * pose.halfWidth
        minX, maxX = math.min(minX, pose.x - ex), math.max(maxX, pose.x + ex)
        minY, maxY = math.min(minY, pose.y - ey), math.max(maxY, pose.y + ey)
    end
    return {x = x + minX * ppu - 4, y = y - maxY * ppu - 4,
        w = (maxX - minX) * ppu + 8, h = (maxY - minY) * ppu + 8}
end

---@param vg NVGContextWrapper
---@param physics BottlePhysics
---@param item ItemInstance
---@param x number
---@param y number
---@param ppu number
---@param cooling boolean?
function SoftView.Item(vg, physics, item, x, y, ppu, cooling)
    local poses = physics:GetSoftPose(item.uid)
    if poses then SoftView.Draw(vg, poses, x, y, ppu, cooling)
    else
        local px, py, angle, radius = physics:GetPose(item.uid)
        Art.Item(vg, item.id, x + px * ppu, y - py * ppu, radius * ppu, -angle, cooling, item.rollValue)
    end
end

return SoftView
