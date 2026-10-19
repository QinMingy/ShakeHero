-- Static pixel lettering and ornament. Geometry is baked at load, never per frame.
-- Glyph masks come from Fusion Pixel at its native 12 px size.
---@type any
local Logo = {TEXT = "实习造物主", SUBTITLE = "APPRENTICE CREATOR", DURATION = 1.2}
local WIDTH, HEIGHT = 402, 120
local GLYPHS = {
    ["实"] = {
        "............",
        ".....##.....",
        "############",
        "#..........#",
        "#.###..#...#",
        ".####..#....",
        ".##....#....",
        "..#....#....",
        "############",
        "...####.##..",
        "######..####",
        "####.....###",
    },
    ["习"] = {
        "............",
        "###########.",
        "..##......#.",
        "..###.....#.",
        "...###....#.",
        "....##....#.",
        "......###.#.",
        "....#####.#.",
        "..#####...#.",
        "#####.....#.",
        "###....####.",
        ".......###..",
    },
    ["造"] = {
        "............",
        "###..#####..",
        ".#########..",
        "...##...#...",
        "........#...",
        "############",
        ".##.........",
        ".##.#######.",
        ".##.#.....#.",
        "###########.",
        "############",
        "##.#########",
    },
    ["物"] = {
        "............",
        "..#..#......",
        "#.#..#......",
        "####.######.",
        "#.#.###.#.#.",
        "..#...#.#.#.",
        "####.##.#.#.",
        "###..####.#.",
        "..#.#####.#.",
        "..#.#####.#.",
        "..#..######.",
        "..#..##.###.",
    },
    ["主"] = {
        "............",
        "....###.....",
        ".....##.....",
        "############",
        ".....##.....",
        ".....##.....",
        ".....##.....",
        ".##########.",
        ".....##.....",
        ".....##.....",
        ".....##.....",
        "############",
    },
}
local WORD = {"实", "习", "造", "物", "主"}

-- Dark silhouettes stay dark during the white entrance flash.
local PALETTE = {
    shadow = {8, 12, 13, 220},
    outline = {47, 37, 26, 255},
    depth = {124, 91, 50, 255},
    depthLight = {162, 123, 66, 255},
    frame = {172, 145, 90, 255},
    frameLight = {235, 216, 167, 255},
    faceTop = {246, 229, 185, 255},
    faceMid = {230, 207, 153, 255},
    faceLow = {210, 180, 117, 255},
    bevelLight = {255, 246, 213, 255},
    bevelDark = {180, 141, 77, 255},
}
local ORDER = {"shadow", "outline", "depth", "depthLight", "frame", "frameLight",
    "faceTop", "faceMid", "faceLow", "bevelLight", "bevelDark"}
local DARK = {shadow = true, outline = true}

---@param value number
---@return number
local function clamp(value)
    return math.max(0, math.min(1, value))
end

---@param progress number
---@param color number[]
---@return integer r
---@return integer g
---@return integer b
local function tint(progress, color)
    local t = clamp(progress)
    return math.floor(255 + (color[1] - 255) * t + .5),
        math.floor(255 + (color[2] - 255) * t + .5),
        math.floor(255 + (color[3] - 255) * t + .5)
end

---@param progress number
---@return number[]
function Logo.Color(progress)
    local r, g, b = tint(progress, PALETTE.faceMid)
    return {r, g, b, 255}
end

---@param elapsed number
---@return {offsetY:number,colorProgress:number,settled:boolean}
function Logo.Pose(elapsed)
    local age = math.max(0, elapsed)
    if age >= Logo.DURATION then return {offsetY = 0, colorProgress = 1, settled = true} end
    ---@type number
    local offset = 0
    if age <= .95 then
        local t = clamp(age / .95)
        offset = -380 * (1 - t) ^ 3
    else
        local t = clamp((age - .95) / .25)
        offset = -5 * math.sin(math.pi * t) ^ 2
    end
    local color = clamp(age / Logo.DURATION)
    return {offsetY = offset, colorProgress = color * color * (3 - 2 * color), settled = false}
end

-- The final pixel canvas is flattened before merging runs; overlap never depends
-- on compound-path stencil support in the offscreen UI target.
---@type table<number,table<number,string>>
local canvas = {}
local function dot(x, y, key)
    if x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT then return end
    canvas[y] = canvas[y] or {}
    canvas[y][x] = key
end
local function rect(x, y, w, h, key)
    for py = y, y + h - 1 do
        for px = x, x + w - 1 do dot(px, py, key) end
    end
end
local function star(cx, cy, radius)
    for d = -radius, radius do
        local half = math.max(0, math.floor((radius - math.abs(d)) / 3))
        rect(cx - half + 1, cy + d + 1, half * 2 + 1, 1, "outline")
        rect(cx - half, cy + d, half * 2 + 1, 1, "frame")
    end
    rect(cx - radius, cy, radius * 2 + 1, 1, "frameLight")
    rect(cx, cy - radius, 1, radius * 2 + 1, "frameLight")
    rect(cx - 1, cy - 1, 3, 3, "bevelLight")
end

-- Stepped fine frame, broken around the center star and side ornaments.
rect(30, 24, 155, 1, "outline"); rect(217, 24, 155, 1, "outline")
rect(30, 22, 155, 1, "frameLight"); rect(217, 22, 155, 1, "frameLight")
rect(30, 102, 342, 1, "outline"); rect(30, 100, 342, 1, "frame")
rect(30, 104, 342, 1, "frameLight")
for _, left in ipairs({true, false}) do
    local x = left and 20 or 381
    rect(x, 31, 1, 24, "frame"); rect(x, 73, 1, 19, "frame")
    for i = 0, 3 do
        local px = left and 22 + i * 2 or 378 - i * 2
        rect(px, 28 - i * 2, 2, 2, "frameLight")
        rect(px, 94 + i * 2, 2, 2, "frame")
    end
    local inner = left and 25 or 376
    rect(inner, 34, 1, 17, "frameLight"); rect(inner, 77, 1, 12, "frameLight")
end
star(201, 22, 7)
star(24, 64, 4); star(377, 64, 4)
rect(187, 21, 2, 2, "frame"); rect(214, 21, 2, 2, "frame")
rect(196, 103, 11, 1, "outline"); rect(200, 102, 3, 3, "bevelLight")

---@type table<number,table<number,boolean>>
local mask = {}
local function mark(x, y)
    mask[y] = mask[y] or {}
    mask[y][x] = true
end
local function has(x, y)
    return mask[y] and mask[y][x] == true
end
local pixel, top, gap = 5, 31, 8
local contentWidth = #WORD * 12 * pixel + (#WORD - 1) * gap
local left = math.floor((WIDTH - contentWidth) / 2)
for index, character in ipairs(WORD) do
    local glyph = GLYPHS[character]
    for row, line in ipairs(glyph) do
        for column = 1, #line do
            if line:sub(column, column) == "#" then
                local gx = left + (index - 1) * (12 * pixel + gap) + (column - 1) * pixel
                local gy = top + (row - 1) * pixel
                for dy = 0, pixel - 1 do
                    for dx = 0, pixel - 1 do mark(gx + dx, gy + dy) end
                end
            end
        end
    end
end
-- Shadow and a dark outer contour around the complete extrusion silhouette.
for y, row in pairs(mask) do
    for x in pairs(row) do rect(x + 4, y + 8, 2, 2, "shadow") end
end
for depth = 6, 0, -1 do
    local dx = math.floor(depth * .7)
    for y, row in pairs(mask) do
        for x in pairs(row) do
            rect(x + dx - 1, y + depth - 1, 3, 3, "outline")
        end
    end
end
for depth = 6, 1, -1 do
    local dx = math.floor(depth * .7)
    for y, row in pairs(mask) do
        for x in pairs(row) do dot(x + dx, y + depth, depth > 3 and "depth" or "depthLight") end
    end
end
for y, row in pairs(mask) do
    for x in pairs(row) do
        local key = y < top + 22 and "faceTop" or (y < top + 43 and "faceMid" or "faceLow")
        if not has(x - 1, y - 1) or not has(x - 2, y - 2) then key = "bevelLight"
        elseif not has(x + 1, y + 1) or not has(x + 2, y + 2) then key = "bevelDark" end
        dot(x, y, key)
    end
end

---@type table<string,number[][]>
local runs = {}
for _, key in ipairs(ORDER) do runs[key] = {} end
---@type table<string,number[]>
local previous = {}
for y = 0, HEIGHT - 1 do
    local current = {}
    local row, x = canvas[y] or {}, 0
    while x < WIDTH do
        local key = row[x]
        if key then
            local start = x
            repeat x = x + 1 until x >= WIDTH or row[x] ~= key
            local width = x - start
            local signature = key .. ":" .. start .. ":" .. width
            local prior = previous[signature]
            if prior then prior[4] = prior[4] + 1; current[signature] = prior
            else
                local run = {start, y, width, 1}
                runs[key][#runs[key] + 1] = run; current[signature] = run
            end
        else x = x + 1 end
    end
    previous = current
end
canvas, mask = {}, {}

---@param vg NVGContextWrapper
---@param bounds table UI layout containing x/y/w/h
---@param colorProgress number
function Logo.Draw(vg, bounds, colorProgress)
    if bounds.w <= 0 or bounds.h <= 0 then return end
    local scale = math.min(bounds.w / WIDTH, bounds.h / HEIGHT)
    local ox, oy = bounds.x + (bounds.w - WIDTH * scale) / 2,
        bounds.y + (bounds.h - HEIGHT * scale) / 2
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgTranslate(vg, ox, oy)
    nvgScale(vg, scale, scale)
    for _, key in ipairs(ORDER) do
        local color = PALETTE[key]
        local r, g, b = color[1], color[2], color[3]
        if not DARK[key] then r, g, b = tint(colorProgress, color) end
        nvgFillColor(vg, nvgRGBA(r, g, b, color[4]))
        for _, run in ipairs(runs[key]) do
            nvgBeginPath(vg)
            nvgRect(vg, run[1], run[2], run[3], run[4])
            nvgFill(vg)
        end
    end
    nvgRestore(vg)
end

return Logo
