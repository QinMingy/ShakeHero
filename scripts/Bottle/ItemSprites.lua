-- 既有物品像素原稿：只拆模块，所有行、色板、镜像与饰件原样保留。
-- Sprite 工厂与 INK 由 Art 注入，避免重复定义/循环引用。
---@param Sprite fun(rows:string[], palette:table<string,number[]>, mirror?:boolean):BottlePixelSprite
---@param INK number[]
---@return table<string,BottlePixelSprite>
return function(Sprite, INK)
---@type table<string,BottlePixelSprite>
local SPRITES = {}

-- 苹果：双瓣轮廓、棕色果梗、绿叶与两级红色，左上保留大块高光。
SPRITES.apple = Sprite({
    ".......ss.......",
    ".......soooo....",
    "......soggggo...",
    "......sogggo....",
    "...ooooosooo....",
    "..ohhhbobbboo...",
    ".ohhhbbbbbbbbo..",
    ".ohhbbbbbbbbbo..",
    "obbbbbbbbbbbbdo.",
    "obbbbbbbbbbbbdo.",
    "obbbbbbbbbbbddo.",
    ".obbbbbbbbbddo..",
    ".obbbbbbbbdddo..",
    "..obbbbbbdddo...",
    "...obbodddoo....",
    "....oo.ooo......",
}, {
    o = INK, s = { 151, 91, 49, 255 }, g = { 80, 200, 120, 255 },
    b = { 255, 71, 87, 255 }, d = { 180, 41, 70, 255 }, h = { 255, 184, 157, 255 },
})

-- 香蕉：横向弯月剪影；深色端点与连续黄色脊线避免小尺寸时变成圆果。
SPRITES.banana = Sprite({
    "................",
    "................",
    "................",
    "oo............oo",
    "osoo.........oso",
    "obhho.......ohbo",
    "obhhho.....ohhbo",
    ".obhhho...ohhbdo",
    ".obhhhhooohhbdo.",
    "..obhhhhhhhbdo..",
    "..odbbbbbbbdo...",
    "...odbbbbbdo....",
    "....odddddo.....",
    ".....ooooo......",
    "................",
    "................",
}, {
    o = INK, s = { 151, 91, 49, 255 }, b = { 255, 217, 61, 255 },
    h = { 255, 244, 156, 255 }, d = { 210, 145, 40, 255 },
})

-- 橘子：台阶果皮、单片绿叶和稀疏深橙像素，区别于有凹口的苹果。
SPRITES.orange = Sprite({
    ".......ss.......",
    "......osgggo....",
    ".....ooggggo....",
    "...oobboooooo...",
    "..ohhhbbbbbbdo..",
    ".ohhhhbbbbbbddo.",
    ".ohhhbbbbbbbddo.",
    "ohhbbbbbbbbbbddo",
    "obbbbbdbbbbbbddo",
    "obbbbbbbbbbbbddo",
    "obbbdbbbbbdbdddo",
    ".obbbbbbbbbbddo.",
    ".obbbbbdbbbdddo.",
    "..obbbbbbddddo..",
    "...oddddddddo...",
    "....oooooooo....",
}, {
    o = INK, s = { 125, 93, 44, 255 }, g = { 80, 200, 120, 255 },
    b = { 255, 150, 48, 255 }, h = { 255, 220, 112, 255 }, d = { 196, 87, 31, 255 },
})

-- 小球：天蓝弹力球，左上大块高光和一条弧形缝线；和橘子/苹果明确区分。
SPRITES.ball = Sprite({
    ".....oooooo.....",
    "...oohhhhhbbo...",
    "..ohhhhhhhbbbo..",
    ".ohhhwwhhhhbbbo.",
    ".ohhwwhhhhhhhbo.",
    "ohhhhhhhhhhhhbbo",
    "ohhhwwwwwwhhhhbo",
    "obbbhwwwwwhhbbdo",
    "obbbhhwwwhhhbbdo",
    "obbbbhhhhhhhbbdo",
    "obbbbbhhhhhhhddo",
    ".obbbbbhhhhhddo.",
    ".obbbbddddddddo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
}, {
    o = INK, h = { 122, 190, 255, 255 }, w = { 226, 244, 255, 255 },
    b = { 74, 138, 210, 255 }, d = { 42, 86, 150, 255 },
})

-- 腐烂的香蕉：同香蕉弯月剪影，褐黑斑与暗黄色，整体下沉一档明度。
SPRITES.rotten_banana = Sprite({
    "................",
    "................",
    "................",
    "oo............oo",
    "osoo.........oso",
    "obddo.......odbo",
    "obdddd.....odddo",
    ".obddd...oddddo.",
    ".obddddoooddddo.",
    "..obdddddddddo..",
    "..odbbdbbbdbo...",
    "...oddbbbddo....",
    "....oddddddo....",
    ".....ooooo......",
    "................",
    "................",
}, {
    o = INK, s = { 96, 74, 38, 255 }, b = { 122, 96, 48, 255 },
    d = { 74, 56, 30, 255 },
})

-- 香蕉皮：摊开的扁平皮，两端翘起，内面白黄、外面暗黄。
SPRITES.banana_peel = Sprite({
    "................",
    "................",
    "................",
    "................",
    "..oo........oo..",
    ".ohho......ohho.",
    ".ohhho....ohhho.",
    ".ohhhho..ohhhho.",
    "obhhhhhoohhhhhbo",
    "obhhhhhhhhhhhhbo",
    ".obbbbbbbbbbbbo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
    "................",
    "................",
}, {
    o = INK, h = { 244, 232, 158, 255 }, b = { 214, 182, 70, 255 },
    d = { 148, 118, 42, 255 },
})

-- 拖鞋：横向鞋底、叉形鞋带、金色扣点；右鞋镜像并使用独立紫色板。
local SLIPPER_ROWS = {
    "................",
    "................",
    "................",
    "................",
    "..oooooooooo....",
    ".ohhhhhhhhhhoo..",
    "ohhbbssbbbsbbbo.",
    "ohhbbbssbssbbbo.",
    "ohhbbbbsssbbbbdo",
    "ohhbbbbbkybbbbdo",
    ".obbbbbbbbbbbdo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
    "................",
    "................",
}
SPRITES.slipper_left = Sprite(SLIPPER_ROWS, {
    o = INK, b = { 33, 189, 174, 255 }, h = { 136, 242, 221, 255 },
    d = { 20, 114, 119, 255 }, s = { 33, 61, 90, 255 },
    k = { 255, 217, 61, 255 }, y = { 255, 245, 178, 255 },
})
SPRITES.slipper_right = Sprite(SLIPPER_ROWS, {
    o = INK, b = { 108, 92, 231, 255 }, h = { 193, 170, 255, 255 },
    d = { 70, 48, 143, 255 }, s = { 46, 29, 79, 255 },
    k = { 255, 217, 61, 255 }, y = { 255, 245, 178, 255 },
}, true)

-- 忍者：靛蓝头罩、红色横向头带及飘带，米黄眼窗和黑色双眼。
SPRITES.ninja = Sprite({
    ".....oooooo.....",
    "...oohhbbbboo...",
    "..ohhbbbbbbbbo..",
    ".ohhbbbbbbbbboo.",
    ".orrrrrrrrrrrrro",
    "orhhhhrrrrrrrrro",
    "orrrrrrrrrrrrroo",
    "obllllllllllboor",
    "oblloolloollboor",
    "oblloolloollbo..",
    "obbbbbbbbbbbbdo.",
    ".obbbbbbbbbbdo..",
    ".odbbbbbbbbddo..",
    "..odbbbbbbddo...",
    "...odddddddo....",
    "....ooooooo.....",
}, {
    o = INK, b = { 63, 67, 111, 255 }, d = { 36, 36, 69, 255 },
    h = { 121, 126, 179, 255 }, r = { 255, 71, 87, 255 }, l = { 255, 218, 157, 255 },
})

-- 爪击不是圆润肉垫：三道粉白尖爪沿对角线切下，尾部为深紫残影。
SPRITES.claw = Sprite({
    "..........oo....",
    ".......oo.oho...",
    "....oo.ohobho...",
    "....ohobhobho...",
    "...obhobhobho...",
    "...obhobhobho...",
    "..obhobhobho....",
    "..obhobhobho....",
    ".obhobhobho.....",
    ".obdobdobdo.....",
    "obdobdobdo......",
    "odoodoodo.......",
    "oo.oo.oo........",
    "................",
    "................",
    "................",
}, {
    o = INK, b = { 255, 107, 170, 255 }, h = { 255, 224, 238, 255 },
    d = { 144, 55, 140, 255 },
})

-- 万物一心：青绿回转环配清晰箭头，中心金色心形由整数像素组成。
SPRITES.returner = Sprite({
    ".....oooooo.....",
    "...oohhhhhboo...",
    "..ohhhhhbbbbo...",
    ".ohhhooooobbbo..",
    "ohhhho....obbbo.",
    ".ohhho.....obbo.",
    "..ohoo.yy.yyobo.",
    "...oo.oyyyyoobo.",
    ".obo...oyyo.obo.",
    ".obbo...oo..oho.",
    ".obbo.....ohhho.",
    ".obbbo....ohhhho",
    "..obbboooohhho..",
    "...obbbbhhhho...",
    "...oobhhhhoo....",
    ".....oooooo.....",
}, {
    o = INK, b = { 33, 189, 174, 255 }, h = { 165, 255, 222, 255 },
    y = { 255, 217, 61, 255 },
})

-- 刮削：宽银色刮刀、倾斜刀口和紫色短柄，刀面高光为硬矩形。
SPRITES.scraper = Sprite({
    "................",
    "...oooooooooo...",
    "..ohhhhhhhhllo..",
    "..ohlllllllbo...",
    "..olllllllbbo...",
    ".ohllllllbbbo...",
    ".ollllllbbbbo...",
    "ohlllllbbbbdo...",
    "olllllbbbddo....",
    "obbbbddddoo.....",
    ".oddddooo.......",
    "..oooosso.......",
    ".....oshso......",
    "......osbso.....",
    ".......oddo.....",
    "........oo......",
}, {
    o = INK, h = { 242, 252, 255, 255 }, l = { 181, 222, 233, 255 },
    b = { 117, 158, 183, 255 }, d = { 58, 77, 116, 255 },
    s = { 108, 92, 231, 255 },
})

-- 硬币共用台阶轮廓和压印边；铜、银、金、紫四级色板及一到四根压印区分面额。
local COIN_ROWS = {
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhbbbbbbhho..",
    ".ohbbddddddbbho.",
    ".ohbdbbbbbbdbho.",
    "ohbdbbbbbbbbdbho",
    "ohbdbbbbbbbbdbdo",
    "ohbdbbbbbbbbdbdo",
    "ohbdbbbbbbbbdbdo",
    "ohbdbbbbbbbbdbdo",
    "ohbdbbbbbbbbdbdo",
    ".obdbbbbbbbbdbo.",
    ".obbddddddbbddo.",
    "..odbbbbbbdddo..",
    "...oddddddddo...",
    ".....oooooo.....",
}

---@param palette table<string, number[]>
---@param bars number
---@return BottlePixelSprite
local function Coin(palette, bars)
    local sprite = Sprite(COIN_ROWS, palette)
    -- 压印最后叠在币面上；四级币改用单像素细条，所有条纹均留在内环之内。
    local rects = {}
    local barWidth = bars == 4 and 1 or 2
    local step = barWidth + 1
    local startX = math.floor((16 - (bars * step - 1)) / 2)
    for i = 1, bars do
        rects[#rects + 1] = startX + (i - 1) * step
        rects[#rects + 1] = 6
        rects[#rects + 1] = barWidth
        rects[#rects + 1] = 5
    end
    sprite.groups[#sprite.groups + 1] = { color = palette.d, rects = rects }
    return sprite
end

SPRITES.coin_quarter = Coin({
    o = INK, h = { 250, 209, 156, 255 }, b = { 201, 139, 81, 255 }, d = { 113, 64, 47, 255 },
}, 1)
SPRITES.coin_half = Coin({
    o = INK, h = { 245, 253, 255, 255 }, b = { 167, 197, 214, 255 }, d = { 76, 105, 141, 255 },
}, 2)
SPRITES.coin_one = Coin({
    o = INK, h = { 255, 244, 160, 255 }, b = { 255, 217, 61, 255 }, d = { 166, 110, 33, 255 },
}, 3)
SPRITES.coin_two = Coin({
    o = INK, h = { 228, 205, 255, 255 }, b = { 151, 113, 238, 255 }, d = { 78, 43, 145, 255 },
}, 4)

-- 云朵：三段阶梯云冠、青蓝下缘和两枚深色像素眼，不使用椭圆或圆角。
SPRITES.cloud = Sprite({
    "................",
    "................",
    ".......oooo.....",
    "......ohhhho....",
    "...oooohhhhho...",
    "..ohhhhhhhhhho..",
    ".ohhhhhhhhhhhho.",
    ".ohhhhhhhhhhhho.",
    "ohhhhhhllllllhho",
    "ohhlloolloollllo",
    "ohllloolloollllo",
    "obllllllllllllbo",
    ".obbbbbbbbbbbbo.",
    "..oooooooooooo..",
    "................",
    "................",
}, {
    o = { 46, 66, 114, 255 }, h = { 245, 253, 255, 255 },
    l = { 193, 230, 245, 255 }, b = { 94, 159, 206, 255 },
})

-- 篮球：橙色球面配黑色十字缝及弧形纵缝，和橘子的果梗/叶片明确区分。
SPRITES.basketball = Sprite({
    ".....oooooo.....",
    "...oohhohbboo...",
    "..ohhhoohbbbo...",
    ".ohhbohobhbbbo..",
    ".ohhbohobhbbbbo.",
    "ohhbbohobhbbbbdo",
    "ohhbbohobhbbbbdo",
    "oooooooooooooooo",
    "obbbbohobhbbbbdo",
    "obbbbohobhbbbddo",
    "obbbbohobhbbbddo",
    ".obbbohobhbbddo.",
    ".obbbboohbdddo..",
    "..obbbdobdddo...",
    "...odddoddoo....",
    ".....oooooo.....",
}, {
    o = INK, b = { 242, 137, 48, 255 }, h = { 255, 211, 112, 255 },
    d = { 173, 74, 36, 255 },
})

-- 采石场：灰岩拱顶、深色矿洞、横向木支架和两段钢轨，不是普通石块。
SPRITES.quarry = Sprite({
    "................",
    ".....oooooo.....",
    "....ohhhhbbbo...",
    "...ohhhhbbbbbo..",
    "..ohhbbbbbbbddo.",
    ".ohhboooooobbddo",
    "ohhboowwwwobdddo",
    "ohbbowhhhwwobbdo",
    "obbbowooooowbbdo",
    "obbbowo..owbbddo",
    "obddowo..owbbddo",
    "odddowo..owbdddo",
    "oddowo....owdddo",
    "odddwrrrrrrwdddo",
    ".oddrdrrrrdrddo.",
    "..oooooooooooo..",
}, {
    o = INK, h = { 210, 222, 230, 255 }, b = { 146, 153, 177, 255 },
    d = { 76, 80, 112, 255 }, w = { 151, 91, 49, 255 }, r = { 122, 174, 188, 255 },
})

-- 采石工人：金色矿灯安全帽、脸部、青绿工装；右侧小镐与矿洞区分。
SPRITES.miner = Sprite({
    ".....oooooo.....",
    "....oyyyybyo....",
    "...oyyhhhhbyo...",
    "...oyhhllhbbo...",
    "..oyyyyhhyyyyo..",
    "..oooooooooooo..",
    "...ossssssso....",
    "...oshossoso....",
    "...oshsssbso.ooo",
    "....ossssbo.ohdo",
    "..oooggggoooddo.",
    ".oghhggbggsodo..",
    ".ogbbggbggso....",
    ".ogbbggbggso....",
    "..oddboobddo....",
    "...ooo..ooo.....",
}, {
    o = INK, y = { 242, 192, 72, 255 }, h = { 255, 238, 163, 255 },
    b = { 171, 113, 49, 255 }, l = { 245, 253, 255, 255 },
    s = { 237, 177, 128, 255 }, g = { 33, 189, 174, 255 }, d = { 75, 103, 137, 255 },
})

-- 石块保留共同八边岩石剪影；大石头多裂缝，中石头整面，小石子圆滑分层。
local ROCK_ROWS = {
    "................",
    ".....oooooo.....",
    "...oohhhhhboo...",
    "..ohhhhhbbbbbo..",
    ".ohhhbbbbbbbbbo.",
    ".ohhbbbbbbbbbbdo",
    "ohhbbbbbbbbbbbdo",
    "ohbbbbbbbbbbbbdo",
    "obbbbbbbbbbbbbdo",
    "obbbbbbdbbbbbddo",
    "obbbbbbbbbbbdddo",
    ".obbbbbbbbbdddo.",
    ".obbbbbbddddddo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
}
local ROCK_PALETTE = {
    o = INK, h = { 210, 222, 230, 255 }, b = { 151, 158, 181, 255 },
    d = { 81, 86, 120, 255 },
}

-- 矿脉和裂纹仍是手绘整数像素；叠层一次缓存，不在每帧生成图案。
---@param sprite BottlePixelSprite
---@param color number[]
---@param rects number[]
---@return BottlePixelSprite
local function Detail(sprite, color, rects)
    sprite.groups[#sprite.groups + 1] = { color = color, rects = rects }
    return sprite
end

SPRITES.boulder = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), ROCK_PALETTE.d, {
    6,3,1,3, 7,5,1,2, 8,6,1,3, 6,8,2,1, 8,9,3,1, 11,10,1,3,
    2,10,3,1, 4,11,1,2,
})
SPRITES.stone = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), ROCK_PALETTE.d, {
    10,5,1,2, 9,7,1,2, 10,9,2,1,
})
SPRITES.pebble = Sprite({
    "................",
    "................",
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhhhhhhhboo..",
    ".ohhhbbbbbbbbbo.",
    ".ohhbbbbbbbbbbdo",
    "ohhbbbbbbbbbbbdo",
    "obbbbbbbbbbbbbdo",
    "obbbbbbbbbbbbbdo",
    ".obbbbbbbbbbbdo.",
    ".odbbbbbbbbdddo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
    "................",
}, {
    o = INK, h = { 226, 237, 241, 255 }, b = { 168, 178, 193, 255 },
    d = { 105, 117, 146, 255 },
})

-- 铜为团块、铁为竖脉、银为斜脉、金为双大矿簇；不仅改变岩石颜色。
SPRITES.copper_ore = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), { 185, 96, 55, 255 }, {
    3,5,4,3, 4,8,3,2, 9,8,4,3, 10,11,2,2,
})
Detail(SPRITES.copper_ore, { 255, 187, 117, 255 }, { 3,5,3,1, 4,6,1,1, 9,8,3,1, 10,9,1,1 })
SPRITES.iron_ore = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), { 76, 105, 141, 255 }, {
    4,4,3,7, 9,6,3,6,
})
Detail(SPRITES.iron_ore, { 174, 216, 231, 255 }, { 4,4,2,5, 9,6,2,4, 5,10,1,1 })
SPRITES.silver_ore = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), { 146, 166, 207, 255 }, {
    3,8,3,3, 5,6,3,3, 7,4,3,3, 9,9,3,3,
})
Detail(SPRITES.silver_ore, { 245, 253, 255, 255 }, { 3,8,2,1, 5,6,2,1, 7,4,2,1, 9,9,2,1, 11,11,1,1 })
SPRITES.gold_ore = Detail(Sprite(ROCK_ROWS, ROCK_PALETTE), { 196, 128, 33, 255 }, {
    3,4,5,5, 8,8,5,4, 5,10,2,2,
})
Detail(SPRITES.gold_ore, { 255, 217, 61, 255 }, { 3,4,4,3, 4,7,3,1, 8,8,4,3, 5,10,1,1 })
Detail(SPRITES.gold_ore, { 255, 246, 178, 255 }, { 3,4,3,1, 3,5,1,1, 8,8,3,1, 8,9,1,1 })

-- 钻石：宽冠、切角、中央折面和向下尖底，区别于带矿脉的圆石。
SPRITES.diamond = Sprite({
    "................",
    "...oooooooooo...",
    "..ohhhhohhhbbbo.",
    ".ohhhhohhbbbdbbo",
    "ohhhhohhbbbbbddo",
    "oooooooooooooooo",
    ".ohhhohhhhobddo.",
    "..ohhhohhobddo..",
    "...ohhohobbdo...",
    "....ohhobbdo....",
    ".....ohobdo.....",
    "......ohdo......",
    ".......oo.......",
    "................",
    "................",
    "................",
}, {
    o = { 30, 80, 115, 255 }, h = { 223, 255, 252, 255 },
    b = { 93, 224, 231, 255 }, d = { 52, 145, 191, 255 },
})

-- 打火石：深靛蓝锐角碎石、银白断面和一处橙色敲击痕，不带矿石色脉。
SPRITES.flint = Sprite({
    "................",
    "..........oo....",
    "........oohho...",
    "......oohhhbbo..",
    "....oohhhhbbbbo.",
    "..oohhhhbbbbbbdo",
    ".ohhhhhbbbbbbbdo",
    "ohhhhhhbbbbbbbdo",
    "ohhhbbbbbbbbdddo",
    ".ohbbbbbbbbbddo.",
    ".obbbbbbdbbdddo.",
    "..obbbbddddddo..",
    "...obyydddddo...",
    "....oyhddddo....",
    ".....oooooo.....",
    "................",
}, {
    o = INK, h = { 177, 201, 220, 255 }, b = { 91, 101, 138, 255 },
    d = { 49, 50, 83, 255 }, y = { 255, 172, 65, 255 },
})

-- 火星：四向飞溅点和上窄下宽的明黄火焰，不用光晕或平滑圆。
SPRITES.spark = Sprite({
    "................",
    ".......oo.......",
    ".......oho......",
    "......ohho......",
    "...oo.ohhbo.oo..",
    "...oyoohhbooyo..",
    "....oohhhbboo...",
    "...ohhhllhbbo...",
    "..ohhhlllhlbbo..",
    "..ohhlllllhbdo..",
    "...ohllllhbdo...",
    "...obhhhbbdo....",
    "....obbbbdo.....",
    ".....ooooo......",
    "...oo.....oo....",
    "...yo.....oy....",
}, {
    o = { 121, 49, 62, 255 }, h = { 255, 225, 96, 255 }, l = { 255, 253, 195, 255 },
    b = { 255, 172, 65, 255 }, d = { 242, 103, 59, 255 }, y = { 255, 217, 61, 255 },
})

-- 炸弹：紫黑方盒、黄色导线和红色警戒带，中间白色叉形标记。
SPRITES.bomb = Sprite({
    "..........yy....",
    ".........yhy....",
    ".......ooo......",
    ".......owo......",
    "..oooooooooooo..",
    ".ohhhhhbbbbbddo.",
    ".ohhbbbbbbbbddo.",
    ".obbbbbbbbbbddo.",
    ".orrrrrrrrrrrro.",
    ".orrllrrrllrrro.",
    ".orrrlllllrrrro.",
    ".orrrrlllrrrrro.",
    ".orrrlllllrrrro.",
    ".orrllrrrllrrro.",
    ".oddddddddddddo.",
    "..oooooooooooo..",
}, {
    o = INK, h = { 164, 145, 197, 255 }, b = { 96, 80, 133, 255 },
    d = { 49, 42, 76, 255 }, r = { 217, 69, 92, 255 },
    l = { 255, 236, 211, 255 }, w = { 161, 124, 66, 255 }, y = { 255, 217, 61, 255 },
})

-- 矿石商人：带金色帽带的紫礼帽、圆脸与两撇胡须，保持 circle 物理语义。
SPRITES.ore_merchant = Sprite({
    ".....oooooo.....",
    "....ohhhhhbbo...",
    "....ohhbbbddo...",
    "....obbbbbddo...",
    "....oyyyyyyyo...",
    "..oooooooooooo..",
    ".ohhhhhhhhhhbbo.",
    ".ossssssssssbbo.",
    "oshssssssssssbbo",
    "ossssoossoossbbo",
    "ossssoossoossbbo",
    "ossssboobssssbbo",
    ".ossobbbbossbbo.",
    "..ossbbbbssbbo..",
    "...ossssssboo...",
    ".....oooooo.....",
}, {
    o = INK, h = { 198, 165, 248, 255 }, b = { 130, 85, 185, 255 },
    d = { 69, 43, 109, 255 }, s = { 246, 197, 153, 255 }, y = { 255, 217, 61, 255 },
})

-- 计数器：青绿方壳、暗屏银色数码格、右上按键和下方机械滚轮。
SPRITES.counter = Sprite({
    "................",
    "..........oo....",
    ".........ohho...",
    "..oooooooooooo..",
    ".ohhhhhhhhhbbbo.",
    ".ohboooooooobbo.",
    ".obolllollolobo.",
    ".obololoololobo.",
    ".obolololoolobo.",
    ".obolllollllobdo",
    ".obooooooooobddo",
    ".obbbbbbbbbbdddo",
    ".obbossoossbdddo",
    ".oddddddddddddo.",
    "..oooooooooooo..",
    "................",
}, {
    o = INK, h = { 165, 255, 222, 255 }, b = { 80, 183, 172, 255 },
    d = { 25, 106, 114, 255 }, l = { 221, 248, 216, 255 }, s = { 141, 160, 179, 255 },
})

-- 幽灵：浅蓝圆冠、黑色长眼和三条错开的尾摆；整体60%不透明，不绘制实体阴影。
SPRITES.ghost = Sprite({
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhhhhhhhllo..",
    ".ohhhhhhhhhlllo.",
    ".ohhhhhhllllllo.",
    "ohhhoolloolllllo",
    "ohhhoolloolllllo",
    "ohhhoolloolllllo",
    "ohhhhhlllllllbbo",
    "ohhhhlloollllbbo",
    "ohhhlllllllllbbo",
    "ohhlllllllllbbbo",
    "ohlollllllollbbo",
    "olo.ollollo.olbo",
    "oo...oo.oo...oo.",
    "................",
}, {
    o = { 46, 66, 114, 153 }, h = { 245, 253, 255, 153 },
    l = { 193, 231, 242, 153 }, b = { 115, 169, 204, 153 },
})

-- 灵魂罐：金属短盖、收肩玻璃罐、罐内白蓝魂脸；与幽灵自由尾摆区分。
SPRITES.soul_jar = Sprite({
    "....oooooooo....",
    "....ohhhhhbo....",
    "....obbbbbbo....",
    ".....owwwwo.....",
    "...oohhhhlloo...",
    "..ohhhllllllbo..",
    ".ohhllllllllbbo.",
    ".ohhlooooollbbo.",
    ".ohlolssslolbbo.",
    ".ohlololosolbbo.",
    ".oblolssslolbbo.",
    ".obllolllollbbo.",
    ".oblllooolllbbo.",
    ".obbbbbbbbbbbbo.",
    "..oddddddddddo..",
    "...oooooooooo...",
}, {
    o = INK, h = { 189, 247, 224, 255 }, l = { 86, 162, 162, 255 },
    b = { 43, 123, 136, 255 }, d = { 38, 71, 100, 255 },
    w = { 188, 147, 85, 255 }, s = { 224, 247, 249, 255 },
})

-- 棺材：上窄肩宽的六角木棺、硬边金色饰钉与正中十字，纵向剪影明确。
SPRITES.coffin = Sprite({
    ".....oooooo.....",
    "....ohhhhhbo....",
    "...ohhbbbbddo...",
    "..ohhbbbbbbddo..",
    ".ohhbbbbbbbbddo.",
    ".ohbbbyybbbbddo.",
    ".ohbbbyybbbbddo.",
    ".ohbyyyyyybbddo.",
    ".ohbyyyyyybbddo.",
    "..ohbbyybbbddo..",
    "..ohbbyybbbddo..",
    "..ohbbyybbbddo..",
    "...ohbbbbdddo...",
    "...ohbbbbdddo...",
    "....oddddddo....",
    ".....oooooo.....",
}, {
    o = INK, h = { 219, 148, 100, 255 }, b = { 157, 93, 69, 255 },
    d = { 87, 51, 58, 255 }, y = { 225, 190, 113, 255 },
})

-- 墓碑：弧形碑冠、石刻十字和青绿苔藓底座；与木棺的斜侧边明确区分。
SPRITES.tombstone = Sprite({
    ".....oooooo.....",
    "...oohhhhhboo...",
    "..ohhhhhbbbddo..",
    ".ohhhhbbbbbdddo.",
    ".ohbbboobbbdddo.",
    ".ohbbboobbbdddo.",
    ".ohboooooobdddo.",
    ".ohbbboobbbdddo.",
    ".ohbbboobbbdddo.",
    ".ohbbbbbbbbdddo.",
    ".obbbbbbbbbdddo.",
    ".obbbddddbbdddo.",
    ".obggbbbggbdddo.",
    "oohggggggggbddoo",
    "ohbbbbbbbbbbbbdo",
    "oooooooooooooooo",
}, {
    o = INK, h = { 217, 223, 235, 255 }, b = { 149, 155, 188, 255 },
    d = { 78, 83, 122, 255 }, g = { 52, 163, 134, 255 },
})

-- 灵魂石：紫色岩面上单独的青绿魂形符文，不加矿石标签或复用普通矿脉。
SPRITES.soul_stone = Detail(Sprite(ROCK_ROWS, {
    o = INK, h = { 210, 184, 255, 255 }, b = { 162, 120, 231, 255 },
    d = { 83, 62, 144, 255 },
}), { 33, 189, 174, 255 }, { 6,4,4,1, 5,5,6,5, 6,10,1,2, 9,10,1,2 })
Detail(SPRITES.soul_stone, { 222, 255, 240, 255 }, { 6,5,4,1, 6,6,1,2, 9,6,1,2, 7,9,2,1 })

------------------------------------------------------- V0.4 新图标

-- 种子：棕色种壳与一段绿芽，结算时可能长成任一植物。
SPRITES.seed = Sprite({
    "................",
    "................",
    "......g.........",
    ".....ggo........",
    "....ggo.........",
    ".....o..........",
    "....obbbo.......",
    "...obhhhbo......",
    "...obhhhbo......",
    "..obhhhhbbo.....",
    "..obhhhhbbo.....",
    "..obbbbbbbo.....",
    "...oddddoo......",
    "....oooo........",
    "................",
    "................",
}, {
    g = { 80, 200, 120, 255 }, o = INK,
    b = { 151, 91, 49, 255 }, h = { 196, 140, 82, 255 },
    d = { 96, 60, 30, 255 },
})

-- 垃圾桶：带盖金属桶，桶身竖向加强筋；吞噬相邻垃圾。
SPRITES.trash_can = Sprite({
    "................",
    ".....oooooo.....",
    "....ohhhhhhho...",
    "...oooooooooo...",
    "...obbbbbbbbo...",
    "..obbbbbbbbbbo..",
    "..obbdbbddbbbo..",
    "..obbdbbddbbbo..",
    "..obbdbbddbbbo..",
    "..obbdbbddbbbo..",
    "..obbdbbddbbbo..",
    "..obbdbbddbbbo..",
    "..obbbbbbbbbbo..",
    "...oddddddddo...",
    "....oooooooo....",
    "................",
}, {
    o = INK, h = { 168, 182, 196, 255 },
    b = { 100, 120, 140, 255 }, d = { 62, 78, 96, 255 },
})

-- 大胃王：粉色圆胖身体与一张占满下半身的巨口。
SPRITES.glutton = Sprite({
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhhhhhhhho...",
    ".ohhhhhhhhhho...",
    ".ohwoohhwoohho..",
    ".ohwoohhwoohho..",
    ".ohhhhhhhhhho...",
    ".ohhoooooohho...",
    ".ohowwwwwwoho...",
    "..ohowwwwwoho...",
    "..ohhooooohho...",
    "...ohhhhhhho....",
    "....ohhhhho.....",
    ".....ooooo......",
    "................",
    "................",
}, {
    o = INK, h = { 220, 120, 140, 255 },
    w = { 255, 240, 240, 255 },
})

-- 半根苹果：保留左半果皮高光，右侧为浅色切面。
SPRITES.apple_half = Sprite({
    ".......ss.......",
    "......sooo......",
    ".....sogo.......",
    "....ooooo.......",
    "..oooocco.......",
    ".ohhbbccco......",
    ".ohhbbbcco......",
    "ohhbbbbcco......",
    "ohhbbbbcco......",
    "ohbbbbbbco......",
    "obbbbbbbco......",
    ".obbbbbbco......",
    ".obbbbddco......",
    "..obbdddco......",
    "...ooddco.......",
    "....oooo........",
}, {
    o = INK, s = { 151, 91, 49, 255 },
    g = { 80, 200, 120, 255 }, b = { 255, 71, 87, 255 },
    h = { 255, 184, 157, 255 }, d = { 180, 41, 70, 255 },
    c = { 255, 238, 200, 255 },
})

-- 半根香蕉：短果段，两端切口为浅色果肉。
SPRITES.banana_half = Sprite({
    "................",
    "................",
    "................",
    "................",
    "..oo.........oo.",
    ".ohho.......oho.",
    ".ohhho.....ohho.",
    "..ohhho...ohho..",
    "..ohhhhoohhho...",
    "...ohhhhhho.....",
    "...occcccco.....",
    "....occcco......",
    ".....oooo.......",
    "................",
    "................",
    "................",
}, {
    o = INK, h = { 255, 244, 156, 255 },
    c = { 250, 235, 190, 255 },
})

-- 半块橘子：圆形切面，放射状橘瓣与浅色筋膜。
SPRITES.orange_half = Sprite({
    "................",
    "................",
    "....oooooooo....",
    "..ooccccccccho..",
    ".occcccccccccho.",
    "occbooccccobcco.",
    "occbbooccbbocco.",
    "occbbboobbbocco.",
    "occbbboobbbocco.",
    "occbbooccbbocco.",
    "occbooccccobcco.",
    ".occcccccccccho.",
    "..ooccccccccho..",
    "....ooddddoo....",
    "................",
    "................",
}, {
    o = INK, c = { 255, 205, 130, 255 },
    b = { 247, 148, 60, 255 }, d = { 196, 87, 31, 255 },
    h = { 255, 170, 80, 255 },
})

-- 警察：大檐警帽、金色胸徽与深蓝制服。
SPRITES.police = Sprite({
    ".....oooooo.....",
    "...oobbbbbboo...",
    "..obbhhhhhhbbo..",
    "..obbbbbbbbbo...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".oobbbbbbbbboo..",
    "obhbbbbkbbbbbbo.",
    "obhbbbbbbbbbbdo.",
    ".obbbbbbbbbddo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, b = { 60, 100, 200, 255 },
    h = { 130, 165, 240, 255 }, l = { 255, 218, 170, 255 },
    w = { 255, 255, 255, 255 }, m = { 150, 80, 70, 255 },
    k = { 255, 217, 61, 255 }, d = { 30, 55, 130, 255 },
})

-- 小偷：黑色头套只露双眼，黑白条纹衫。
SPRITES.thief = Sprite({
    ".....oooooo.....",
    "...oobbbbbboo...",
    "..obbbbbbbbbo...",
    "..obbbbbbbbbo...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..obbbbbbbbbo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".ooboboboboboo..",
    "obhbobobobobbbo.",
    "obhbobobobobbdo.",
    ".obobobobobddo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, b = { 50, 50, 60, 255 },
    h = { 96, 96, 112, 255 }, l = { 230, 190, 150, 255 },
    w = { 255, 255, 255, 255 }, m = { 120, 70, 60, 255 },
    d = { 24, 24, 32, 255 },
})

-- 学生：齐刘海、白校服与红领巾；结算5次后成长为职业。
SPRITES.student = Sprite({
    ".....oooooo.....",
    "...oodddddoo....",
    "..oddddddddho...",
    "..odddddddhho...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollrroo.....",
    ".oowwwrrwwwwoo..",
    "owhhwwrrrwwhwo..",
    "owhhwwwwwwwwwo..",
    ".owwwwwwwwwwdo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, d = { 70, 50, 35, 255 },
    h = { 110, 80, 55, 255 }, l = { 255, 222, 180, 255 },
    w = { 255, 255, 255, 255 }, b = { 40, 40, 60, 255 },
    r = { 230, 60, 60, 255 }, m = { 150, 80, 70, 255 },
})

-- 老师：圆框眼镜、绿色西装，手边一册书本。
SPRITES.teacher = Sprite({
    ".....oooooo.....",
    "...oodddddoo....",
    "..oddddddddho...",
    "..odddddddhho...",
    "..oollllllloo...",
    "..olowwollwlo...",
    "..olobbolobbo...",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".oogggggggggo...",
    "oghgggggggggo...",
    "oghggggggggoo...",
    ".ogggggggo.ko...",
    "..oddddddo.ko...",
    "...ooooooooko...",
}, {
    o = INK, d = { 60, 45, 30, 255 },
    h = { 95, 70, 50, 255 }, l = { 255, 222, 180, 255 },
    w = { 220, 240, 255, 255 }, b = { 40, 40, 60, 255 },
    g = { 80, 160, 100, 255 }, m = { 150, 80, 70, 255 },
    k = { 180, 120, 60, 255 },
})

-- 气球：红色球体带高光，下系波浪细线；结算时膨胀。
SPRITES.balloon = Sprite({
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhhhhhhhho...",
    ".ohhwwhhhhhho...",
    ".ohwwwhhhhhho...",
    "ohhwhhhhhhhhho..",
    "ohhhhhhhhhhhho..",
    "ohhhhhhhhhhhhdo.",
    "ohhhhhhhhhhhddo.",
    ".ohhhhhhhhdddo..",
    "..ohhhhhhhddo...",
    "...ooddddoo.....",
    ".......oo.......",
    "......o.o.......",
    ".......o........",
    "................",
}, {
    o = INK, h = { 240, 100, 120, 255 },
    w = { 255, 200, 210, 255 }, d = { 180, 50, 80, 255 },
})

-- 杀手：暗红兜帽阴影下的冷眼，手中一柄短刀。
SPRITES.killer = Sprite({
    ".....oooooo.....",
    "...oorrrrrroo...",
    "..orrrrrrrrro...",
    ".orrrrrrrrrro...",
    ".orrlolllolrro..",
    ".orrlolllolrro..",
    ".orrrlllllrro...",
    "..orrrmmrrro....",
    "...orrrrrro.....",
    "..oorrrrrroo....",
    ".orrrrrrrrrko...",
    "orhrrrrrrrkko...",
    "orhrrrrrrrko....",
    ".orrrrrrrko.....",
    "..oddddddo......",
    "...oooooooo.....",
}, {
    o = INK, r = { 160, 40, 40, 255 },
    h = { 220, 90, 80, 255 }, l = { 200, 200, 220, 255 },
    m = { 90, 30, 30, 255 }, k = { 200, 210, 220, 255 },
    d = { 90, 20, 25, 255 },
})

-- 樱桃：一对深红果实共用一段果梗与绿叶；结算时再结算一次。
SPRITES.cherry = Sprite({
    ".......oo.......",
    "......sgo.......",
    ".....sg.o.......",
    "....o..o.o......",
    "...o....o.o.....",
    "..o......oo.....",
    ".ooo.....ooo....",
    "ohhrro..ohhrro..",
    "ohhrro..ohhrro..",
    "ohrrro..ohrrro..",
    "orrrro..orrrro..",
    "orddro..orddro..",
    ".oddo....oddo...",
    "..oo......oo....",
    "................",
    "................",
}, {
    o = INK, s = { 125, 93, 44, 255 },
    g = { 80, 200, 120, 255 }, r = { 200, 40, 60, 255 },
    h = { 255, 140, 150, 255 }, d = { 130, 20, 35, 255 },
})

-- 半个樱桃：单侧果皮带高光，切面露出浅色果肉与果核。
SPRITES.cherry_half = Sprite({
    "................",
    "................",
    ".......o........",
    "......so........",
    ".....o..........",
    "....ooo.........",
    "..oohccco.......",
    ".ohhccccco......",
    ".ohcccccbo......",
    ".occckccbo......",
    ".occckccbo......",
    "..occccbbo......",
    "..ooocbbo.......",
    "....ooo.........",
    "................",
    "................",
}, {
    o = INK, s = { 125, 93, 44, 255 },
    h = { 255, 150, 160, 255 }, c = { 230, 80, 95, 255 },
    b = { 140, 25, 40, 255 }, k = { 90, 50, 30, 255 },
})

-- 信用卡：蓝色卡面、金色芯片与白色卡号条；每次结算后价值永久-1。
SPRITES.credit_card = Sprite({
    "................",
    "..oooooooooooo..",
    ".ohhhhhhhhhhhdo.",
    ".obbbbbbbbbbbdo.",
    ".obbbbbbbbbbbdo.",
    ".okkbbbbbbbbbo..",
    ".okkbbbbbbbbbo..",
    ".obbbbbbbbbbbdo.",
    ".obwwwwwwwbbbdo.",
    ".obbbbbbbbbbbdo.",
    ".oddddddddddddo.",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, h = { 130, 180, 225, 255 },
    b = { 70, 130, 180, 255 }, d = { 35, 75, 120, 255 },
    k = { 255, 217, 61, 255 }, w = { 230, 240, 250, 255 },
})

-- 小刀：斜置银色刀身与深棕短柄，刃口一道高光。
SPRITES.knife = Sprite({
    "..............o.",
    ".............oho",
    "............ohho",
    "...o.......ohhho",
    "..oho.....ohhho.",
    "..ohho...ohhho..",
    "..ohhho.ohhho...",
    "...ohhhohhho....",
    "....ohhhhho.....",
    ".....khhho......",
    "....kkkoo.......",
    "...kkko.........",
    "..kkko..........",
    "...oo...........",
    "................",
    "................",
}, {
    o = INK, h = { 200, 212, 225, 255 },
    k = { 120, 80, 50, 255 },
})

-- 果农：宽檐草帽与背带工装；把相邻水果立刻卖出。
SPRITES.fruit_farmer = Sprite({
    "..oooooooooooo..",
    ".ohhhhhhhhhhhho.",
    "..ooooddddooo...",
    "....ooddddoo....",
    "....ollllllo....",
    "....olwllwlo....",
    "....olbllblo....",
    "....ollllllo....",
    ".....olmmlo.....",
    "..oooolllloooo..",
    ".obbgbbbbbggbo..",
    "obhbgbbbbbggbdo.",
    "obhbgbbbbbggbdo.",
    ".obbgbbbbbggbo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, h = { 235, 205, 130, 255 },
    d = { 160, 120, 50, 255 }, l = { 235, 190, 140, 255 },
    w = { 255, 255, 255, 255 }, b = { 150, 110, 70, 255 },
    g = { 110, 80, 45, 255 }, m = { 150, 80, 70, 255 },
})

-- 食客：白衬衫红领结，左右手各持一副刀叉。
SPRITES.diner = Sprite({
    ".....oooooo.....",
    "...oodddddoo....",
    "..oddddddddho...",
    "..odddddddhho...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".oowwkwwwwwkoo..",
    "owhhkwwwwwwkhwo.",
    "owhhkwwwwwwkhwo.",
    ".owwkwwwwwkko...",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, d = { 120, 80, 40, 255 },
    h = { 170, 120, 70, 255 }, l = { 255, 222, 180, 255 },
    w = { 250, 250, 250, 255 }, b = { 40, 40, 60, 255 },
    k = { 200, 60, 60, 255 }, m = { 150, 80, 70, 255 },
})

-- 西红柿：圆润红果配绿色星形萼片。
SPRITES.tomato = Sprite({
    ".......o........",
    "......sgo.......",
    "...o..g..o......",
    "..ogo.g.ogo.....",
    "..ogggggggo.....",
    ".ohhbbbbbbbo....",
    "ohhhbbbbbbbbo...",
    "ohhbbbbbbbbbo...",
    "ohbbbbbbbbbbdo..",
    "ohbbbbbbbbbbdo..",
    ".obbbbbbbbbdo...",
    ".obbbbbbbbddo...",
    "..obbbbbbddo....",
    "...oddddddo.....",
    "....oooooo......",
    "................",
}, {
    o = INK, s = { 125, 93, 44, 255 },
    g = { 80, 180, 90, 255 }, b = { 220, 60, 50, 255 },
    h = { 255, 150, 130, 255 }, d = { 150, 30, 30, 255 },
})

-- 西红柿炒蛋：金黄蛋块与番茄红块混炒；被消耗后在瓶顶重生。
SPRITES.tomato_egg = Sprite({
    "................",
    "...oooooo.......",
    "..oyyyhyoo......",
    ".oyyyyyyhoo.....",
    ".oyyrryyhyo.....",
    "..yrRRryyhoo....",
    "..yrRRryyhho....",
    "..yyrryyyyho....",
    ".oyyyyyyhho.....",
    ".oyyryyyyho.....",
    "..yrrRryyho.....",
    "..oyyyhhyo......",
    "...ooooo........",
    "................",
    "................",
    "................",
}, {
    o = INK, y = { 250, 210, 90, 255 },
    h = { 255, 240, 160, 255 }, r = { 220, 70, 55, 255 },
    R = { 170, 35, 30, 255 },
})

-- 厨师：蓬松高帽、红色领巾与白色双排扣厨师服。
SPRITES.chef = Sprite({
    "...o..ooo..o....",
    "..ohhohhhooho...",
    "..ohhhhhhhhho...",
    "..ohhhhhhhhho...",
    "...ooooooooo....",
    "....ollllllo....",
    "....olwllwlo....",
    "....olbllblo....",
    "....ollllllo....",
    ".....olmmlo.....",
    "..oooollllooo...",
    ".owwwwbbwwwwo...",
    "owhhwwwwwwwwdo..",
    "owhhwwwwwwwwo...",
    ".owwwwwwwwwdo...",
    "..odddddddddo...",
}, {
    o = INK, h = { 255, 255, 255, 255 },
    w = { 240, 240, 245, 255 }, l = { 255, 222, 180, 255 },
    b = { 200, 60, 60, 255 }, m = { 150, 80, 70, 255 },
    d = { 190, 190, 200, 255 },
})

-- 金针菇：已确认的16×16成束细柄与错落小菌盖，和其他物品统一像素密度。
SPRITES.enoki = Sprite({
    "................",
    ".......oo.......",
    "......ohyo......",
    "......oddo......",
    "...oo..owo.oo...",
    "..ohyo.owoohyo..",
    "..oddo.owooddo..",
    "...owo.owoowo...",
    "...owo.owoowo...",
    "..oowo.owoowoo..",
    ".ohyowoowowohyo.",
    ".oddoowowoodddo.",
    "..oowowwwwowoo..",
    "....oowwwwoo....",
    "......owwo......",
    ".......oo.......",
}, {
    o = { 10, 10, 25, 255 }, h = { 255, 248, 224, 255 },
    w = { 242, 231, 199, 255 }, y = { 255, 219, 117, 255 },
    d = { 224, 189, 127, 255 },
})

-- 桂冠：金色月桂枝环抱成环；锁定场上唯一最高价值物品并放大。
SPRITES.laurel = Sprite({
    "....o......o....",
    "...ogo....ogo...",
    "..ogggo..ogggo..",
    ".oggggo..oggggo.",
    ".ogggo....ogggo.",
    "ogggo......ogggo",
    "ogggo......ogggo",
    ".ogggo....ogggo.",
    ".oggggo..oggggo.",
    "..oggggo..gggo..",
    "...oggggoogggo..",
    "....ogggggggo...",
    ".....oggggo.....",
    "......oooo......",
    "................",
    "................",
}, {
    o = INK, g = { 212, 175, 55, 255 },
})

-- 士兵：钢盔与橄榄绿军装，胸前一枚弹药袋扣。
SPRITES.soldier = Sprite({
    ".....oooooo.....",
    "...ooggggggoo...",
    "..ogggggggggo...",
    "..oggoooooggo...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".oogggggggggoo..",
    "oghggggggggggo..",
    "oghgggkgggggdo..",
    ".ogggggggggddo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, g = { 110, 130, 90, 255 },
    h = { 150, 170, 120, 255 }, l = { 235, 195, 150, 255 },
    w = { 255, 255, 255, 255 }, b = { 60, 60, 50, 255 },
    m = { 150, 80, 70, 255 }, k = { 70, 85, 55, 255 },
    d = { 60, 75, 50, 255 },
})

-- 医生：额戴反射镜的白大褂，衣襟一枚红十字。
SPRITES.doctor = Sprite({
    ".....oooooo.....",
    "...oodddddoo....",
    "..odddddddkko...",
    "..odddddddkko...",
    "..oollllllloo...",
    "..olllwwllwllo..",
    "..olllbbllbllo..",
    "..olllllllllo...",
    "..oolllmmmoo....",
    "...oollllloo....",
    ".oowwwwwwwwwoo..",
    "owhwwwwrwwwwwo..",
    "owhwwwrrrwwwdo..",
    ".owwwwrwwwwwdo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, d = { 90, 65, 45, 255 },
    k = { 200, 210, 220, 255 }, l = { 255, 222, 180, 255 },
    w = { 250, 250, 252, 255 }, b = { 40, 40, 60, 255 },
    r = { 220, 50, 50, 255 }, m = { 150, 80, 70, 255 },
    h = { 225, 225, 235, 255 },
})

-- 鸡蛋：米白色蛋形，左上一块柔和高光；与西红柿合成西红柿炒蛋。
SPRITES.egg = Sprite({
    "................",
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhhhhhhhho...",
    ".ohhwwhhhhhho...",
    ".ohwwwhhhhhho...",
    "ohhwhhhhhhhhho..",
    "ohhhhhhhhhhhho..",
    "ohhhhhhhhhhhho..",
    "ohhhhhhhhhhhdo..",
    ".ohhhhhhhhddo...",
    ".ohhhhhhdddo....",
    "..ohhhhdddo.....",
    "...oddddddo.....",
    "....oooooo......",
    "................",
}, {
    o = INK, h = { 245, 235, 210, 255 },
    w = { 255, 252, 245, 255 }, d = { 205, 190, 160, 255 },
})

-- 水果忍者：沿用忍者头罩图案（由两只拖鞋合成而来）。
SPRITES.fruit_ninja = SPRITES.ninja

return SPRITES
end
