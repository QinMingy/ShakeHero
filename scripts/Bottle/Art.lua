-- 瓶中像素美术：只绘制图形，复用调用方上下文、坐标和米到屏幕的缩放。
-- 配色遵循 PixelForge：深蓝紫底、青绿主色、紫色辅色与硬边高光。
local Art = {}
local Palette = require("Machine.Palette")
local SoftBacon = require("Bottle.SoftBacon")
local PixelCache = require("Bottle.PixelCache")
local GainIcon = require("Bottle.GainIcon")
local Shapes = require("Bottle.Shapes")
-- Native NanoVG RTT has no usable compound-path stencil. Draw the identical
-- cached sprite rectangles separately only in registered offscreen contexts.
local offscreenContexts = setmetatable({}, {__mode = "k"})
---@param vg NVGContextWrapper
---@param enabled boolean
function Art.SetOffscreenContext(vg, enabled)
    offscreenContexts[vg] = enabled or nil
end

function Art.ReleaseContext(vg)
    PixelCache.Release(vg)
    GainIcon.Release(vg)
    offscreenContexts[vg]=nil
end
local INK = { 10, 10, 26, 255 }

---@class BottlePixelGroup
---@field color number[]
---@field rects number[] 整数网格矩形，按 x、y、宽、高连续存储

---@class BottlePixelSprite
---@field width integer
---@field height integer
---@field groups BottlePixelGroup[]
---@field mirror boolean

---@param color number[]
---@param cooling? boolean
local function Color(color, cooling)
    if cooling then
        -- 每种颜色独立转为亮度灰阶后压暗，保留透明度及高光、主体、阴影层次。
        local gray = math.floor((color[1] * .2126 + color[2] * .7152 + color[3] * .0722) * .78)
        return nvgRGBA(gray, gray, gray, color[4] or 255)
    end
    return nvgRGBA(color[1], color[2], color[3], color[4] or 255)
end

---@param vg NVGContextWrapper
---@param color number[]
---@param cooling? boolean
---@param original? boolean 仅物品像素绕过UI调色
local function Fill(vg, color, cooling, original)
    local value = Color(color, cooling)
    if original then Palette.FillItem(vg, value) else nvgFillColor(vg, value) end
    nvgFill(vg)
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param color number[]
local function Rect(vg, x, y, w, h, color)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    Fill(vg, color)
end

-- 手绘行模式在模块加载时合并连续同色像素；每帧只提交缓存的矩形。
-- 点号表示透明，其他字符仅是色板索引，不会绘制成文字。
---@param rows string[]
---@param palette table<string, number[]>
---@param mirror? boolean
---@return BottlePixelSprite
local function Sprite(rows, palette, mirror)
    local width = #rows[1]
    ---@type BottlePixelSprite
    local sprite = { width = width, height = #rows, groups = {}, mirror = mirror or false }
    ---@type table<string, BottlePixelGroup>
    local byKey = {}
    for key, color in pairs(palette) do
        local group = { color = color, rects = {} }
        byKey[key] = group
        sprite.groups[#sprite.groups + 1] = group
    end
    for rowIndex, row in ipairs(rows) do
        assert(#row == width, "像素美术行宽不一致：第" .. rowIndex .. "行")
        local column = 1
        while column <= width do
            local key = row:sub(column, column)
            local nextColumn = column + 1
            while nextColumn <= width and row:sub(nextColumn, nextColumn) == key do
                nextColumn = nextColumn + 1
            end
            if key ~= "." then
                local group = byKey[key]
                assert(group, "像素美术缺少色板：" .. key)
                local rects = group.rects
                rects[#rects + 1] = column - 1
                rects[#rects + 1] = rowIndex - 1
                rects[#rects + 1] = nextColumn - column
                rects[#rects + 1] = 1
            end
            column = nextColumn
        end
    end
    return sprite
end

---@type table<string, BottlePixelSprite>
local SPRITES = {}

local LoadItems = require("Bottle.ItemSprites")
SPRITES = LoadItems(Sprite, INK)
local LoadExtra = require("Bottle.ExtraSprites")
LoadExtra(Sprite, INK, SPRITES)
local LoadExpansion = require("Bottle.ExpansionSprites")
LoadExpansion(Sprite, INK, SPRITES)


---@param vg NVGContextWrapper
---@param sprite BottlePixelSprite
---@param size number 半宽对应尺寸，物品传入原有半径
---@param cooling? boolean
---@param original? boolean
---@param sizeY? number 可选纵向半高；省略时与 size 等比
local function DrawSprite(vg, sprite, size, cooling, original, sizeY)
    local pixel = size * 2 / sprite.width
    local pixelY = pixel
    if sizeY then pixelY = sizeY * 2 / sprite.height end
    local left, top = -sprite.width * pixel / 2, -sprite.height * pixelY / 2
    if sprite.mirror then nvgScale(vg, -1, 1) end
    if original and PixelCache.Draw(vg,sprite,left,top,sprite.width*pixel,sprite.height*pixelY,cooling) then
        return
    end
    for _, group in ipairs(sprite.groups) do
        if #group.rects > 0 then
            local rects = group.rects
            if offscreenContexts[vg] then
                for i = 1, #rects, 4 do
                    nvgBeginPath(vg)
                    nvgRect(vg, left + rects[i] * pixel, top + rects[i + 1] * pixelY,
                        rects[i + 2] * pixel, rects[i + 3] * pixelY)
                    Fill(vg, group.color, cooling, original)
                end
            else
                nvgBeginPath(vg)
                for i = 1, #rects, 4 do
                    nvgRect(vg, left + rects[i] * pixel, top + rects[i + 1] * pixelY,
                        rects[i + 2] * pixel, rects[i + 3] * pixelY)
                end
                Fill(vg, group.color, cooling, original)
            end
        end
    end
end

-- 兼容原 Circle 调用，但用十六行台阶盘代替平滑圆，中心和半径语义不变。
local DISC_SPANS = { 6, 10, 12, 14, 14, 16, 16, 16, 16, 16, 16, 14, 14, 12, 10, 6 }
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param r number
---@param color number[]
---@param cooling? boolean
function Art.Circle(vg, x, y, r, color, cooling)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    local pixel = r / 8
    nvgBeginPath(vg)
    for row, span in ipairs(DISC_SPANS) do
        nvgRect(vg, x - span * pixel / 2, y - r + (row - 1) * pixel, span * pixel, pixel)
    end
    Fill(vg, color, cooling)
    nvgRestore(vg)
end

-- 兼容旧 Box 的参数顺序；圆角参数保留但不再用于绘制。
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param w number
---@param h number
---@param r number
---@param color number[]
---@param cooling? boolean
function Art.Box(vg, x, y, w, h, r, color, cooling)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgBeginPath(vg)
    nvgRect(vg, x, y, w, h)
    Fill(vg, color, cooling)
    nvgRestore(vg)
end

-- 仅规范显示输入，不回写实例、不抽随机，点数与价值加成严格分离。
---@param id string
---@param rollValue number?
---@return integer?
function Art.DiceValue(id, rollValue)
    local maximum = id == "die_d4" and 4 or (id == "die_d6" and 6 or nil)
    if not maximum then return nil end
    if type(rollValue) ~= "number" or rollValue ~= rollValue then return 1 end
    return math.max(1, math.min(maximum, math.floor(rollValue)))
end

-- 保留物品位置、半径、弧度旋转及冷却接口，不量化物理位置或修改碰撞尺寸。
---@param vg NVGContextWrapper
---@param id string
---@param x number
---@param y number
---@param r number
---@param angle? number
---@param cooling? boolean
---@param rollValue? number 骰子实例点数；缺省显示1点，不使用加成后的有效价值
---@param woolCount? number 小羊永久羊毛库存，0/1..4/5以上三档
function Art.Item(vg, id, x, y, r, angle, cooling, rollValue, woolCount)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, angle or 0)
    if id == "bacon" then nvgScale(vg, SoftBacon.LENGTH_SCALE, 1) end
    local diceValue = Art.DiceValue(id, rollValue)
    local spriteId = diceValue and (id .. "_" .. diceValue) or Shapes.Variant(id, woolCount)
    DrawSprite(vg, SPRITES[spriteId] or SPRITES.coin_one, r, cooling, true)
    nvgRestore(vg)
end

-- 测试/调用方可明确检查图案覆盖，不把缺省金币误认为已完成图案。
---@param id string
---@return boolean
function Art.HasSprite(id)
    return SPRITES[id] ~= nil
end

-- 培根软体段：原图x=16*u，原图y5..11映射到段矩形，不绘透明留白。
-- u0/u1为0..1，五段调用0/.2/.4/.6/.8/1；angle已经是UI向下Y坐标弧度。
-- halfLengthPx表示实际绘制半长（有搭接时由View决定），内部不加边线或接缝。
---@param vg NVGContextWrapper
---@param x number UI逻辑像素中心
---@param y number
---@param angle number UI方向弧度，Physics的CCW角度需由View取负
---@param halfLengthPx number
---@param halfWidthPx number
---@param u0 number
---@param u1 number
---@param cooling? boolean
function Art.BaconSegment(vg, x, y, angle, halfLengthPx, halfWidthPx, u0, u1, cooling)
    local startU, endU = math.max(0, math.min(1, u0)), math.max(0, math.min(1, u1))
    if endU <= startU or halfLengthPx <= 0 or halfWidthPx <= 0 then return end
    local sourceLeft, sourceRight = startU * 16, endU * 16
    local scaleX = halfLengthPx * 2 / (sourceRight - sourceLeft)
    local scaleY = halfWidthPx * 2 / 6
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y)
    nvgRotate(vg, angle)
    local sprite = SPRITES.bacon
    for _, group in ipairs(sprite.groups) do
        local rects = group.rects
        local hasPath = false
        for i = 1, #rects, 4 do
            local left = math.max(sourceLeft, rects[i])
            local right = math.min(sourceRight, rects[i] + rects[i + 2])
            local top = math.max(5, rects[i + 1])
            local bottom = math.min(11, rects[i + 1] + rects[i + 3])
            if right > left and bottom > top then
                if offscreenContexts[vg] or not hasPath then nvgBeginPath(vg) end
                nvgRect(vg, -halfLengthPx + (left - sourceLeft) * scaleX,
                    -halfWidthPx + (top - 5) * scaleY,
                    (right - left) * scaleX, (bottom - top) * scaleY)
                hasPath = true
                if offscreenContexts[vg] then Fill(vg, group.color, cooling, true) end
            end
        end
        if hasPath and not offscreenContexts[vg] then Fill(vg, group.color, cooling, true) end
    end
    nvgRestore(vg)
end

-- 篮筐设施：红色硬边篮圈和留空网眼；网向屏幕 Y 正方向延伸。
-- 18列外框中间16列为有效开口，物理判定使用 halfWidth 而非外框宽。
-- 仅左右最外1列的上方2行有实体口沿；中间横线是投影，网不阻挡穿筐。
local HOOP = Sprite({
    "oooooooooooooooooo",
    "obrrrrrrrrrrrrrrbo",
    ".ollllllllllllllo.",
    ".olo..ol..lo..olo.",
    "..olo.ol..lo.olo..",
    "..ollllllllllllo..",
    "...olo.l..l.olo...",
    "...olollllllolo...",
    "....ololllolo.....",
    ".....ooooooo......",
}, {
    o = INK, b = { 165, 59, 53, 255 }, r = { 255, 125, 72, 255 },
    l = { 217, 236, 239, 255 },
})

---@param vg NVGContextWrapper
---@param x number UI逻辑像素，开口横线中心
---@param y number UI逻辑像素，屏幕 Y 向下
---@param halfWidth number 有效开口半宽；建议篮球半径×1.2
---@param pixel? number 像素单元高度；省略时为 halfWidth/8
function Art.Hoop(vg, x, y, halfWidth, pixel)
    if halfWidth <= 0 then return end
    local unit = math.max(pixel or halfWidth / 8, .01)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y + unit * 3.5)
    nvgScale(vg, halfWidth / 8, unit)
    DrawSprite(vg, HOOP, 9)
    nvgRestore(vg)
end

-- 拾取与绘制复用同一像素图案及逆旋转；透明区域不属于物品，不改变物理碰撞体。
---@param id string
---@param dx number 相对物品中心的屏幕偏移
---@param dy number
---@param r number
---@param angle number 绘制角度（弧度）
---@return boolean
---@param woolCount? number
function Art.HitItem(id, dx, dy, r, angle, woolCount)
    if r <= 0 then return false end
    local sprite = SPRITES[Shapes.Variant(id, woolCount)] or SPRITES.coin_one
    local cosine, sine = math.cos(angle), math.sin(angle)
    local localX, localY = dx * cosine + dy * sine, -dx * sine + dy * cosine
    if id == "bacon" then localX = localX / SoftBacon.LENGTH_SCALE end
    if sprite.mirror then localX = -localX end
    local pixel = r * 2 / sprite.width
    local column = localX / pixel + sprite.width / 2
    local row = localY / pixel + sprite.height / 2
    for _, group in ipairs(sprite.groups) do
        local rects = group.rects
        for i = 1, #rects, 4 do
            if column >= rects[i] and column < rects[i] + rects[i + 2]
                and row >= rects[i + 1] and row < rects[i + 1] + rects[i + 3] then
                return true
            end
        end
    end
    return false
end

---@param id string
---@param r number
---@param angle number
---@return number
---@param woolCount? number
function Art.ItemExtent(id, r, angle, woolCount)
    local sprite = SPRITES[Shapes.Variant(id, woolCount)] or SPRITES.coin_one
    local halfWidth = id == "bacon" and r * SoftBacon.LENGTH_SCALE or r
    -- 培根只有原图第5..11行有像素，横向拉长不改变厚度/透明留白。
    local halfHeight = id == "bacon" and r * SoftBacon.HALF_WIDTH_RATIO
        or r * sprite.height / sprite.width
    local cosine, sine = math.abs(math.cos(angle)), math.abs(math.sin(angle))
    return math.max(halfWidth * cosine + halfHeight * sine, halfWidth * sine + halfHeight * cosine)
end

-- 出现粒子的取色来源：物品像素色板中除描边外的颜色，按色板顺序循环使用；
-- 没有独立色板时退回白色，保证任何物品都有可见粒子。
---@param id string
---@return number[][]
function Art.ItemColors(id)
    local sprite = SPRITES[id] or SPRITES.coin_one
    local colors = {}
    for _, group in ipairs(sprite.groups) do
        if group.color ~= INK then colors[#colors + 1] = group.color end
    end
    if #colors == 0 then colors[1] = { 255, 255, 255, 255 } end
    return colors
end

-- 外轮廓完全保留原物理尺寸，肩部保留原直线而非向外扩张的阶梯。
-- 单位为米：左右壁 ±2.4，底部 0，肩高 5.5 到 6.05，颈宽 2.3，顶高 6.4。
local BOTTLE_OUTER = { -2.4, 0, -2.4, -5.5, -1.15, -6.05, -1.15, -6.4,
    1.15, -6.4, 1.15, -6.05, 2.4, -5.5, 2.4, 0 }
local BOTTLE_INNER = { -2.31, -.09, -2.31, -5.44, -1.06, -5.99, -1.06, -6.31,
    1.06, -6.31, 1.06, -5.99, 2.31, -5.44, 2.31, -.09 }
local GLASS_EDGE = { 102, 126, 67, 255 }
local GLASS_DARK = { 16, 39, 21, 255 }
local GLASS_SHADE = { 22, 48, 27, 255 }
local GLASS_LIGHT = { 181, 190, 112, 255 }
local GLASS_DIM = { 62, 83, 43, 255 }
local ACTIVE = { 255, 217, 61, 255 }

---@param vg NVGContextWrapper
---@param points number[]
---@param color number[]
local function Polygon(vg, points, color, step)
    if offscreenContexts[vg] then
        -- RTT has no compound stencil. Rasterize the same polygon into narrow
        -- horizontal strips, retaining the original bottle silhouette.
        local ymin,ymax=math.huge,-math.huge
        for i=2,#points,2 do ymin=math.min(ymin,points[i]);ymax=math.max(ymax,points[i]) end
        local dy=step or .018
        local y=ymin
        while y<ymax do
            local height=math.min(dy,ymax-y)
            local mid=y+height*.5
            local crossings={}
            for i=1,#points,2 do
                local j=i+2;if j>#points then j=1 end
                local ax,ay,bx,by=points[i],points[i+1],points[j],points[j+1]
                if (ay<=mid and by>mid) or (by<=mid and ay>mid) then
                    crossings[#crossings+1]=ax+(mid-ay)*(bx-ax)/(by-ay)
                end
            end
            table.sort(crossings)
            for i=1,#crossings-1,2 do Rect(vg,crossings[i],y,crossings[i+1]-crossings[i],height,color) end
            y=y+height
        end
        return
    end
    nvgBeginPath(vg)
    nvgMoveTo(vg, points[1], points[2])
    for i = 3, #points, 2 do nvgLineTo(vg, points[i], points[i + 1]) end
    nvgClosePath(vg)
    Fill(vg, color)
end

---@param vg NVGContextWrapper
---@param x number
---@param floorY number
---@param ppu number
---@param active boolean
function Art.Bottle(vg, x, floorY, ppu, active)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, floorY)
    nvgScale(vg, ppu, ppu)
    -- 双层实色多边形形成内描边，不用居中描线，避免改变外轮廓尺寸。
    Polygon(vg, BOTTLE_OUTER, GLASS_EDGE,1/ppu)
    Polygon(vg, BOTTLE_INNER, GLASS_DARK,1/ppu)
    Rect(vg, -2.31, -1.1, 4.62, 1.01, GLASS_SHADE)
    Rect(vg, 1.85, -5.1, .22, 4.78, GLASS_SHADE)

    -- 瓶口硬边与分段肩部高光全部位于轮廓内部，不再额外抬高瓶口。
    Rect(vg, -1.15, -6.4, 2.3, .14, GLASS_EDGE)
    Rect(vg, -.98, -6.36, 1.96, .04, GLASS_LIGHT)
    Rect(vg, -1.87, -5.7, .28, .09, GLASS_LIGHT)
    Rect(vg, -1.44, -5.91, .22, .08, GLASS_LIGHT)
    Rect(vg, 1.28, -5.87, .16, .08, GLASS_DIM)

    -- 硬高光以分开的像素条表达，不使用透明柔光或渐变。
    Rect(vg, -2.17, -5.16, .12, 1.28, GLASS_LIGHT)
    Rect(vg, -2.17, -3.66, .12, 1.72, GLASS_EDGE)
    Rect(vg, -2.17, -1.7, .12, .98, GLASS_LIGHT)
    Rect(vg, -1.96, -4.96, .06, .36, GLASS_DIM)
    Rect(vg, 2.13, -4.85, .07, 1.24, GLASS_DIM)
    Rect(vg, 2.13, -3.3, .07, 1.12, GLASS_DIM)
    Rect(vg, 2.13, -1.88, .07, .94, GLASS_DIM)

    -- 八组分段刻度，无数字；长短条和孤立方点便于识别深色瓶内高度。
    for i = 1, 8 do
        local tickY = -.65 * i
        local tickWidth = i % 2 == 0 and .28 or .16
        Rect(vg, 2.01 - tickWidth, tickY, tickWidth, .055, GLASS_EDGE)
        Rect(vg, 2.07, tickY, .055, .055, GLASS_DIM)
    end
    local floorColor = active and ACTIVE or GLASS_EDGE
    Rect(vg, -2.31, -.09, 4.62, .09, floorColor)
    for i = 1, 7 do
        Rect(vg, -2.18 + (i - 1) * .65, -.2, .14, .07, floorColor)
    end
    nvgRestore(vg)
end

local EYE = Sprite({
    "......oooo......",
    "....oohhhhoo....",
    "..oohhhbbhhhoo..",
    ".ohhhhboobhhhho.",
    "ohhhhhboobhhhhho",
    "ohhhhhboobhhhhho",
    ".ohhhhbbbbhhhho.",
    "..oohhhhhhhhoo..",
    "....oohhhhoo....",
    "......oooo......",
}, {
    o = GLASS_EDGE, h = { 224, 247, 249, 255 }, b = { 108, 92, 231, 255 },
})

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param size number
function Art.Eye(vg, x, y, size)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y)
    DrawSprite(vg, EYE, size)
    nvgRestore(vg)
end

-- 收益图标统一使用用户提供的贴图；秒表沿用缓存像素绘制。
local STAT_ICONS = {
    cooldown = Sprite({
        "....................",
        "........oooo........",
        "........ohho........",
        ".........oo...oo....",
        "......ooooooooho....",
        ".....ohhhhhhhhho....",
        "....ohbbblbbbbhho...",
        "...ohbbbblbbbbbdho..",
        "...ohbbbblbbbbbdho..",
        "...ohbbbblbbbbbdho..",
        "...ohbbbbooobbbdho..",
        "...ohbbbbbbobbbdho..",
        "...ohbbbbbbbbbbdho..",
        "...ohbbbbbbbbbbdho..",
        "....ohbbbbbbbbdho...",
        ".....ohdddddddho....",
        "......oooooooo......",
        "....................",
        "....................",
        "....................",
    }, {
        o = INK, h = {165, 255, 222, 255}, b = {33, 189, 174, 255},
        d = {20, 114, 119, 255}, l = {240, 240, 240, 255},
    }),
}

---@param vg NVGContextWrapper
---@param kind string
---@param x number
---@param y number
---@param size number
function Art.StatIcon(vg, kind, x, y, size)
    if kind == "gain" then GainIcon.Draw(vg, x, y, size); return end
    local sprite = STAT_ICONS[kind]
    if not sprite then return end
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y)
    DrawSprite(vg, sprite, size)
    nvgRestore(vg)
end

------------------------------------------------------------- 牌库入口图标

-- 牌库入口底图：横向铺满按钮的布袋轮廓，文字直接写在袋身上。
-- 32×16 整数像素，与物品／遗物共用 INK 黑描边；不含任何货币符号、字母或数字。
local DECK_ICON = Sprite({
    "............ohhhdddo............",
    "............ohhhdddo............",
    "...........ohhhbdddo............",
    "..........ohhhbbbbdddo..........",
    "........ohhhbbbbbbbdddo.........",
    ".......ohhhhbbbbbbbbddddo.......",
    ".....ohhhhhbbbbbbbbbdddddo......",
    "....ohhhhhbbbbbbbbbbbdddddo.....",
    "...ohhhhhhbbbbbbbbbbbddddddo....",
    "...ohhhhhhbbbbbbbbbbbbddddddo...",
    "..ohhhhhhhbbbbbbbbbbbdddddddo...",
    "..ohhhhhhhbbbbbbbbbbbdddddddo...",
    "..ohhhhhhhbbbbbbbbbbbdddddddo...",
    "...ohhhhhhbbbbbbbbbbbbddddddo...",
    "....ohhhhhbbbbbbbbbbbbdddddo....",
    ".....ohhhhbbbbbbbbbbbddddo......",
}, {
    o = INK, h = {238, 214, 166, 255}, b = {196, 163, 110, 255},
    d = {140, 110, 70, 255},
})

--- 牌库入口底图：按给定宽高铺满，非等比拉伸袋身以填满按钮。
---@param vg NVGContextWrapper
---@param x number 左边界
---@param y number 上边界
---@param w number 目标宽度
---@param h number 目标高度
---@param cooling? boolean
function Art.DeckPlate(vg, x, y, w, h, cooling)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x + w / 2, y + h / 2)
    DrawSprite(vg, DECK_ICON, w / 2, cooling, nil, h / 2)
    nvgRestore(vg)
end

------------------------------------------------------------- 遗物徽记（V0.4）

-- 24 件遗物的 16x16 像素徽记；id 与 Bottle.Relics 一致。
---@type table<string, BottlePixelSprite>
local RELIC_SPRITES = {}

local LoadRelics = require("Bottle.RelicSprites")
RELIC_SPRITES = LoadRelics(Sprite, INK)

--- 遗物徽记：三选一卡片与图鉴共用；cooling 时以灰阶压暗。
---@param vg NVGContextWrapper
---@param id string 遗物 id
---@param x number UI逻辑像素，徽记中心
---@param y number
---@param size number 半宽
---@param cooling? boolean
function Art.Relic(vg, id, x, y, size, cooling)
    local sprite = RELIC_SPRITES[id]
    if not sprite then return end
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, x, y)
    DrawSprite(vg, sprite, size, cooling, true)
    nvgRestore(vg)
end

print("[Bottle.Art] 像素美术初始化完成：新表图案、像素眼睛、手托金币/冷却图标、33件遗物徽记及4.8x6.4米实验瓶。")
return Art
