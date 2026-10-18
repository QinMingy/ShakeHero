-- 物品像素图案库（V0.4，70件表）：手绘16×16整数像素，色板索引字符。
-- 从 Art.lua 拆出（规则#13 文件行数上限）；Art.lua 只保留绘制/命中函数。
-- 点号=透明；其他字符是色板索引。行宽必须一致，加载时合并连续同色像素。
-- 人类职业共用 HUMAN_ROWS 基体，用色板+饰件 Detail 区分；
-- 硬币十档共用 COIN_ROWS，用色板+压印条数区分；
-- 半份水果由完整水果图案程序化取左半并加切面生成。

-- BottlePixelGroup / BottlePixelSprite 统一由 Art.lua 声明，避免重复且不一致的宽高类型。

local INK = { 10, 10, 26, 255 }
local Sprites = {}
---@type table<string, BottlePixelSprite>
Sprites.SPRITES = {}
Sprites.INK = INK

---@param rows string[]
---@param palette table<string, number[]>
---@param mirror? boolean
---@return BottlePixelSprite
function Sprites.Make(rows, palette, mirror)
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

---叠层饰件：一次缓存，不逐帧生成。
---@param sprite BottlePixelSprite
---@param color number[]
---@param rects number[]
---@return BottlePixelSprite
function Sprites.Detail(sprite, color, rects)
    sprite.groups[#sprite.groups + 1] = { color = color, rects = rects }
    return sprite
end

---从完整水果图案生成半份：保留左半（x<8）像素，切面处叠浅色竖带。
---@param sprite BottlePixelSprite
---@param cutColor number[]
---@return BottlePixelSprite
function Sprites.LeftHalf(sprite, cutColor)
    ---@type BottlePixelSprite
    local half = { width = sprite.width, height = sprite.height, groups = {}, mirror = false }
    for _, group in ipairs(sprite.groups) do
        local rects = {}
        local src = group.rects
        for i = 1, #src, 4 do
            local x, y, w, h = src[i], src[i + 1], src[i + 2], src[i + 3]
            if x < 8 then
                rects[#rects + 1] = x
                rects[#rects + 1] = y
                rects[#rects + 1] = math.min(w, 8 - x)
                rects[#rects + 1] = h
            end
        end
        if #rects > 0 then
            half.groups[#half.groups + 1] = { color = group.color, rects = rects }
        end
    end
    -- 切面竖带：沿 x=7 列描一条浅色，只在原图案有像素的行。
    local cut = {}
    for _, group in ipairs(half.groups) do
        local rects = group.rects
        for i = 1, #rects, 4 do
            local x, y, w, h = rects[i], rects[i + 1], rects[i + 2], rects[i + 3]
            if x + w == 8 then
                cut[#cut + 1] = 7
                cut[#cut + 1] = y
                cut[#cut + 1] = 1
                cut[#cut + 1] = h
            end
        end
    end
    if #cut > 0 then
        half.groups[#half.groups + 1] = { color = cutColor, rects = cut }
    end
    return half
end

return Sprites
