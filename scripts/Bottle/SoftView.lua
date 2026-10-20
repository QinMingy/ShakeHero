-- 软体物品的显示、拾取与结算残留统一读取真实分段姿态。
local Art = require("Bottle.Art")
---@class BottleSoftView
local SoftView = {}
-- Rendering and hit bounds consume a pose synchronously. Event/residue callers
-- still use Physics:GetSoftPose without a target and retain isolated snapshots.
---@type table<table,BottleSoftPose[]>
local renderPoses = setmetatable({}, {__mode = "k"})

---@param physics BottlePhysics
---@param uid number
---@return BottleSoftPose[]?
local function RenderPose(physics, uid)
    local target = renderPoses[physics]
    if not target then target = {}; renderPoses[physics] = target end
    return physics:GetSoftPose(uid, target)
end

---@param vg NVGContextWrapper
---@param poses BottleSoftPose[]
---@param x number 瓶底屏幕原点
---@param y number
---@param ppu number 米到UI逻辑像素
---@param cooling boolean?
---@param whiteFlash boolean?
function SoftView.Draw(vg, poses, x, y, ppu, cooling, whiteFlash)
    for _, pose in ipairs(poses) do
        Art.BaconSegment(vg, x + pose.x * ppu, y - pose.y * ppu, -pose.angle,
            pose.halfLength * ppu, pose.halfWidth * ppu, pose.u0, pose.u1, cooling, whiteFlash)
    end
end

---@param physics BottlePhysics
---@param uid integer
---@param x number
---@param y number
---@param ppu number
---@return {x:number,y:number,w:number,h:number}?
function SoftView.Bounds(physics, uid, x, y, ppu)
    local poses = RenderPose(physics, uid)
    if not poses then return nil end
    return SoftView.PoseBounds(poses, x, y, ppu)
end

-- 已释放刚体的结算残留仍使用保存的真实软段，不向物理查询默认原点。
---@param poses BottleSoftPose[]
---@param x number
---@param y number
---@param ppu number
---@return {x:number,y:number,w:number,h:number}
function SoftView.PoseBounds(poses, x, y, ppu)
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
    local poses = RenderPose(physics, item.uid)
    if poses then SoftView.Draw(vg, poses, x, y, ppu, cooling)
    else
        local px, py, angle, radius = physics:GetPose(item.uid)
        Art.Item(vg, item.id, x + px * ppu, y - py * ppu, radius * ppu, -angle,
            cooling, item.rollValue, item.woolCount)
    end
end

-- 与软体实时拾取同口径：逐段逆旋转命中矩形，弯曲缝隙不当成实体。
---@param poses BottleSoftPose[]
---@param x number 瓶内米制坐标
---@param y number
---@return boolean
function SoftView.HitPose(poses, x, y)
    for _, pose in ipairs(poses) do
        local dx, dy = x - pose.x, y - pose.y
        local cosine, sine = math.cos(pose.angle), math.sin(pose.angle)
        if math.abs(dx * cosine + dy * sine) <= pose.halfLength
            and math.abs(-dx * sine + dy * cosine) <= pose.halfWidth then return true end
    end
    return false
end

return SoftView
