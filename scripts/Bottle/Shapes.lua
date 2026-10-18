-- 按现有 16×16 像素图案简化的碰撞轮廓，坐标在创建时转换为米。
-- 屏幕局部 Y 向下，Box2D 局部 Y 向上；右拖鞋需同时镜像 X。
--
-- 香蕉：    \        /       三个凸片沿弯月排列，保留中央透明凹口。
--            \____/         左 8 点 + 中 5 点 + 右 6 点，不用整片凸包填凹口。
-- 拖鞋：    <======>        一个八边形，鞋头/鞋跟削角，不填充画布上下留白。
-- 云朵：     /‾‾\          云冠 + 八边形云底，两个凸片保留连续的平直下缘。
--           <____>
-- 刮削：    [刀面] /柄      两个凸片；爪击用一个凸包，不模拟细爪之间的像素缝。
-- 采石场：  /‾‾‾‾\        岩顶 + 左右矿洞支柱，3片；洞口留空但支柱接缝重合。
--           |    |          小物品可擦过洞口，中央暗色背景不是整块实体。
-- 采石工：   [帽脸] /镐     身体凸包 + 镐头凸片；细柄不单独建 fixture。
-- 石/钻石： <岩石> /\      岩石八边凸包；钻石宽冠尖底六边凸包。
-- 火星：      /\            单片火焰，飞溅装饰点不触发实体接触。
-- 幽灵：    /幽灵\          冠部与尾摆单凸包；无重力但不穿透，Physics:Step 驱动。
-- 灵魂罐：  [盖][罐]        两个相交凸片，不把收肩空白填成大方框。
-- 棺材：    / 木棺 \        一个八边形，宽肩窄底；不扩大横向留白。
-- 墓碑：    /石碑\ ___      碑身 + 底座两个凸片，保留平直底缘。
-- 方盒：    [炸弹/计数器]   共用削角八边框；导线/按钮是装饰，主体接触触发。
--
-- 检测目的：轮廓接触物品/瓶壁 -> 真实 Box2D 接触，沿用 fixture 引用计数。
-- 擦边由 Box2D 判定；分片交界无可穿过的缝；包络包含全部偏移/旋转形状。
-- 新表补齐：骰4为三角、骰6削角方；树冠+干根、兔身+双耳、猴身+双耳。
-- 星形为中心五边形+5个三角尖，保留5个凹角；水滴为单8点凸片。
-- 培根不在此制造刚体轮廓，真正多段关节物理由 Bottle.SoftBacon 负责。
-- 每个刚体凸片最多 8 顶点；只在生成时建，不逐帧拟合。
-- 图案微细装饰（猴尾、树叶像素、数码按钮）不扩成额外接触区。

---@class BottleCollisionCircle
---@field x number 像素网格圆心
---@field y number
---@field radius number 像素网格半径

---@class BottleCollisionProfile
---@field polygons number[][]? 每个凸片为 x,y 交替排列，屏幕顺时针
---@field circles BottleCollisionCircle[]?
---@field envelope number? 归一化旋转包络，由模块初始化计算

local Shapes = {}
---@type table<string, BottleCollisionProfile>
Shapes.profiles = {
    banana = {polygons = {
        {0,3, 2,3, 4,4, 6,6, 6,14, 5,14, 2,11, 0,7},
        {6,7, 7,7, 10,8, 10,14, 6,14},
        {10,7, 14,3, 16,3, 16,8, 11,13, 10,13},
    }},
    -- 香蕉皮：摊开的扁平宽片，顶缘微拱；7顶点凸片，不模拟像素缝。
    peel = {polygons = {
        {1,7, 8,5, 15,7, 16,10, 13,14, 3,14, 0,10},
    }},
    slipper = {polygons = {
        {0,6, 2,4, 12,4, 16,6, 16,10, 13,13, 3,13, 0,10},
    }},
    cloud = {polygons = {
        {3,4, 7,2, 11,2, 15,6, 1,6},
        {0,8, 1,6, 15,6, 16,8, 16,12, 14,14, 2,14, 0,12},
    }},
    scraper = {polygons = {
        {0,7, 3,1, 13,1, 14,2, 13,8, 8,12, 2,12, 0,10},
        {5,11, 9,11, 11,13, 11,15, 10,16, 8,16, 5,12},
    }},
    claw = {polygons = {
        {0,10, 4,2, 10,0, 13,0, 13,6, 11,10, 8,13, 0,13},
    }},
    mine = {polygons = {
        {1,6, 3,3, 6,1, 11,1, 14,3, 16,6},
        {1,5, 5,5, 5,15, 2,15, 0,12, 0,7},
        {11,5, 15,5, 16,7, 16,12, 14,15, 11,15},
    }},
    miner = {polygons = {
        {5,0, 11,0, 13,5, 13,13, 11,16, 3,16, 1,12, 2,5},
        {13,8, 16,8, 16,10, 12,12, 11,11},
    }},
    rock = {polygons = {
        {5,1, 11,1, 16,5, 16,11, 13,15, 3,15, 0,11, 0,6},
    }},
    diamond = {polygons = {
        {3,1, 13,1, 16,5, 9,13, 7,13, 0,5},
    }},
    spark = {polygons = {
        {7,1, 9,1, 14,8, 13,11, 10,14, 5,14, 2,10, 3,7},
    }},
    box = {polygons = {
        {2,4, 14,4, 15,5, 15,15, 14,16, 2,16, 1,15, 1,5},
    }},
    ghost = {polygons = {
        {5,0, 11,0, 15,3, 16,5, 16,15, 0,15, 0,5, 1,3},
    }},
    jar = {polygons = {
        {4,0, 12,0, 12,4, 4,4},
        {5,3, 11,3, 15,6, 15,14, 13,16, 3,16, 1,14, 1,6},
    }},
    coffin = {polygons = {
        {5,0, 11,0, 15,4, 15,9, 11,16, 5,16, 1,9, 1,4},
    }},
    die_d4 = {polygons = {
        {8,0, 16,16, 0,16},
    }},
    die_d6 = {polygons = {
        {3,1, 13,1, 15,3, 15,13, 13,15, 3,15, 1,13, 1,3},
    }},
    tree = {polygons = {
        {5,0, 11,0, 15,4, 15,8, 12,11, 4,11, 1,8, 1,4},
        {6,9, 10,9, 10,15, 6,15},
        {3,14, 13,14, 13,16, 3,16},
    }},
    droplet = {polygons = {
        {8,0, 13,7, 14,11, 12,15, 8,16, 4,15, 2,11, 3,7},
    }},
    rabbit = {polygons = {
        {5,6, 11,6, 14,10, 14,14, 12,16, 4,16, 2,14, 2,10},
        {3,0, 6,0, 6,7, 3,7},
        {10,0, 13,0, 13,7, 10,7},
    }},
    monkey = {polygons = {
        {5,2, 11,2, 13,4, 13,9, 11,11, 5,11, 3,9, 3,4},
        {4,9, 12,9, 12,16, 4,16},
        {0,5, 4,5, 4,10, 0,10},
        {12,5, 16,5, 16,10, 12,10},
    }},
    coin_machine = {polygons = {
        {2,0, 14,0, 14,15, 2,15},
        {1,14, 15,14, 15,16, 1,16},
    }},
    star = {polygons = {
        -- 中心五边形与五个尖共享边，无间隙；不能将10点凹多边形直接交给Box2D。
        {10,5, 12,10, 8,13, 4,10, 6,5},
        {6,5, 8,0, 10,5},
        {10,5, 16,6, 12,10},
        {12,10, 13,16, 8,13},
        {8,13, 3,16, 4,10},
        {4,10, 0,6, 6,5},
    }},
    -- 仅供尺寸查询；Physics 对 bacon 使用 SoftBacon，不会创建此刚性替代。
    bacon = {polygons = {{0,5, 16,5, 16,11, 0,11}}},
    tombstone = {polygons = {
        {5,0, 11,0, 15,3, 15,14, 1,14, 1,3},
        {0,13, 16,13, 16,16, 0,16},
    }},
}

for _, profile in pairs(Shapes.profiles) do
    local envelope = 0
    for _, polygon in ipairs(profile.polygons or {}) do
        assert(#polygon >= 6 and #polygon <= 16, "碰撞凸片需有3到8个顶点")
        for i = 1, #polygon, 2 do
            local x, y = (polygon[i] - 8) / 8, (8 - polygon[i + 1]) / 8
            envelope = math.max(envelope, math.sqrt(x * x + y * y))
        end
    end
    for _, circle in ipairs(profile.circles or {}) do
        local x, y = (circle.x - 8) / 8, (8 - circle.y) / 8
        envelope = math.max(envelope, math.sqrt(x * x + y * y) + circle.radius / 8)
    end
    profile.envelope = envelope
end

---@param shape string
---@param radius number
---@return number
function Shapes.Envelope(shape, radius)
    local profile = Shapes.profiles[shape]
    if profile then return radius * (profile.envelope or 1) end
    return shape == "capsule" and radius * 1.15 or radius
end

return Shapes
