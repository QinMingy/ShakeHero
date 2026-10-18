-- 24件遗物像素原稿，拆分不改变原色/像素/接口。
---@param Sprite fun(rows:string[], palette:table<string,number[]>, mirror?:boolean):BottlePixelSprite
---@param INK number[]
---@return table<string,BottlePixelSprite>
return function(Sprite, INK)
---@type table<string,BottlePixelSprite>
local RELIC_SPRITES = {}

-- 赌神令牌：金色圆牌刻骰子五点。
RELIC_SPRITES["gambling_token"] = Sprite({
    ".....oooooo.....",
    "...ooffffffoo...",
    "..offgggfffffo..",
    ".offgfffffgfffo.",
    "offgffmffmfffffo",
    "offffffmfffffffo",
    "offffmmmmmfffffo",
    "offffffmfffffffo",
    "offgffmffmfffffo",
    ".offgfffffgfffo.",
    "..offgggfffffo..",
    "...ooffffffoo...",
    ".....oooooo.....",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 255, 200, 60, 255 },
    g = { 255, 240, 160, 255 }, m = { 120, 40, 20, 255 },
})

-- 再来一把：一张红心扑克牌。
RELIC_SPRITES["one_more_round"] = Sprite({
    "................",
    "....ooooo.......",
    "...offfffo......",
    "..offmmffo......",
    "..offmmfffo.....",
    "..offfffmfo.....",
    "..offmmfffo.....",
    "..offmmfffo.....",
    "..offfffmfo.....",
    "..offmmfffo.....",
    "..offffffo......",
    "...oooooo.......",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 240, 240, 250, 255 },
    m = { 210, 50, 60, 255 },
})

-- 积少成多：三枚金币叠成小塔。
RELIC_SPRITES["small_savings"] = Sprite({
    "................",
    ".....oooo.......",
    "....offffo......",
    ".....oooo.......",
    "....oooooo......",
    "...offffffo.....",
    "....oooooo......",
    "..oooooooooo....",
    ".offffffffffo...",
    "oooooooooooo....",
    "................",
    "................",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 255, 217, 61, 255 },
})

-- 硬币雨：云朵落下金币雨滴。
RELIC_SPRITES["coin_rain"] = Sprite({
    "................",
    "....oooooo......",
    "..oofffffffoo...",
    ".offffffffffo...",
    ".offffffffffo...",
    "..offffffffo....",
    "...oooooooo.....",
    ".....o..o.......",
    "....ofo..o......",
    ".....o..fo......",
    "........o.......",
    ".......fo.......",
    "........o.......",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 255, 217, 61, 255 },
})

-- 成群结队：一群白兔的长耳剪影。
RELIC_SPRITES["in_groups"] = Sprite({
    "..o..o....o..o..",
    "..o..o....o..o..",
    ".ooffoo..ooffoo.",
    ".offffo..offffo.",
    "..oooo....oooo..",
    "...oo......oo...",
    "................",
    "....o......o....",
    "...offo..offo...",
    "...offfo.offfo..",
    "....ooo..ooo....",
    "................",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 230, 220, 235, 255 },
})

-- 灵魂共振：紫色墓碑荡开共振波纹。
RELIC_SPRITES["soul_resonance"] = Sprite({
    "................",
    "..o...oooo...o..",
    ".o.o.offfo.o.o..",
    "o..o.offfo.o..o.",
    "...offffffffo...",
    "..offffffffffo..",
    "..offfmffmfffo..",
    "..offfffffffmo..",
    "..offffffffffo..",
    "..offffffffffo..",
    "..ooooooooooooo.",
    "................",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 162, 120, 231, 255 },
    m = { 240, 230, 255, 255 },
})

-- 合成2048：数字合成砖的四宫格。
RELIC_SPRITES["merge_2048"] = Sprite({
    "................",
    "..oooooooooooo..",
    ".offmfffffmffo..",
    ".offmfffffmffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offmmmmmffffo..",
    ".offmmmmmffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offffffmmmmfo..",
    ".offffffmmmmfo..",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 240, 210, 140, 255 },
    m = { 90, 55, 25, 255 },
})

-- 小偷手册：黑皮手册封面一只白手套印。
RELIC_SPRITES["thief_handbook"] = Sprite({
    "................",
    "..oooooooooooo..",
    ".ommmmmmmmmmgo..",
    ".ommfffmmmmfgo..",
    ".ommffffffmfgo..",
    ".ommfffmmmmfgo..",
    ".ommmmmmmmmmgo..",
    ".ommmmmmmmmmgo..",
    ".ommmmmmmmmmgo..",
    ".ommmmmmmmmmgo..",
    ".ommmmmmmmmmgo..",
    ".ogggggggggggo..",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
}, {
    o = INK, m = { 40, 40, 55, 255 },
    f = { 230, 230, 240, 255 }, g = { 120, 120, 140, 255 },
})

-- 作弊骰子：灌铅骰子永远六点朝上。
RELIC_SPRITES["cheat_dice"] = Sprite({
    "................",
    "..oooooooooooo..",
    ".offfffffffffo..",
    ".offmffmffmffo..",
    ".offfffffffffo..",
    ".offmffmffmffo..",
    ".offfffffffffo..",
    ".offmffmffmffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".odddddddddddo..",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 245, 245, 250, 255 },
    d = { 190, 190, 205, 255 }, m = { 30, 30, 40, 255 },
})

-- 升级硬币机：投币机吐出更大的硬币。
RELIC_SPRITES["upgrade_coin_machine"] = Sprite({
    "..oooooooooooo..",
    ".offfffffffffo..",
    ".offffffffmmfo..",
    ".offffffffmmfo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".ooddddddddddo..",
    "....oooffoooo...",
    "....offfffo.....",
    ".....ooooo......",
    "................",
    "................",
}, {
    o = INK, f = { 150, 160, 175, 255 },
    d = { 95, 105, 120, 255 }, m = { 255, 217, 61, 255 },
})

-- 转基因水果：绿苹果上缠绕一段红色基因链。
RELIC_SPRITES["gm_fruit"] = Sprite({
    ".......o........",
    "......ogo.......",
    "...oooooooo.....",
    "..offffffffo....",
    ".offfmmmfffffo..",
    ".offmfmfmfffffo.",
    ".offmfmfmfffffo.",
    "offffmfmfffffffo",
    "offfffmffffffddo",
    "offfffffffffddo.",
    ".offfffffffddo..",
    ".offffffffddo...",
    "..offffffddo....",
    "...oooooooo.....",
    "................",
    "................",
}, {
    o = INK, f = { 120, 220, 120, 255 },
    m = { 230, 60, 90, 255 }, g = { 80, 180, 90, 255 },
    d = { 60, 150, 80, 255 },
})

-- 西红柿首富：金币铸成的番茄，价值翻倍。
RELIC_SPRITES["tomato_tycoon"] = Sprite({
    "...o.o...o.o....",
    "...oooooooo.....",
    "..offffffffffo..",
    ".offffffffffffo.",
    ".offffffffffffo.",
    "offffffffffffffo",
    "offfffmmmmfffffo",
    "offffffffffffffo",
    "offffffffffffffo",
    ".offffffffffffo.",
    ".offffffffffffo.",
    "..offffffffffo..",
    "...oddddddddo...",
    "....oooooooo....",
    "................",
    "................",
}, {
    o = INK, f = { 255, 217, 61, 255 },
    m = { 220, 60, 50, 255 }, d = { 190, 140, 30, 255 },
})

-- 幸运符：四叶草护符带来反转的好运。
RELIC_SPRITES["lucky_charm"] = Sprite({
    "................",
    "....oo....oo....",
    "...offo..offo...",
    "..offffooffffo..",
    "..offfffoffffo..",
    "...offffffffo...",
    "....offfffo.....",
    "....offfffo.....",
    "...offffffffo...",
    "..offfffoffffo..",
    "..offffo..offo..",
    "...offo....oo...",
    "....oo......s...",
    "..........os....",
    ".........os.....",
    "................",
}, {
    o = INK, f = { 90, 200, 110, 255 },
    s = { 110, 80, 45, 255 },
})

-- 炒蛋秘籍：写着配方的旧菜谱卷轴。
RELIC_SPRITES["scramble_recipe"] = Sprite({
    "................",
    "..oooooooooooo..",
    ".offfffffffffo..",
    ".offmmmmmmmmfo..",
    ".offfffffffffo..",
    ".offmmmmmmfo....",
    ".offfffffffffo..",
    ".offmmmmmmmmfo..",
    ".offfffffffffo..",
    ".offmmmmmmfo....",
    ".offfffffffffo..",
    ".offmmmmmmmmfo..",
    ".odddddddddddo..",
    "..oooooooooooo..",
    "................",
    "................",
}, {
    o = INK, f = { 245, 235, 205, 255 },
    m = { 120, 90, 50, 255 }, d = { 200, 185, 150, 255 },
})

-- seeYouTomorrow：金针菇与循环箭头，明日再见。
RELIC_SPRITES["see_you_tomorrow"] = Sprite({
    ".......ooo......",
    "......offfo.....",
    ".....offfffo..o.",
    "....offfffffo.o.",
    "....offfffffoo..",
    ".....offfffo....",
    ".....offfffo....",
    ".....offfffo....",
    ".....offfffo....",
    ".....offfffo....",
    ".....offfffo....",
    "....offffffo....",
    "...ooofffffo....",
    "..o...ooooo.....",
    "..o.............",
    "...oo...........",
}, {
    o = INK, f = { 240, 235, 210, 255 },
})

-- 有教无类：一本向所有人敞开的蓝色典籍。
RELIC_SPRITES["teach_all"] = Sprite({
    "......oooo......",
    ".....offffo.....",
    "....o......o....",
    "..oooooooooooo..",
    ".offfmmmmffffo..",
    ".offmmmmmmffo...",
    ".offfffffffo....",
    ".offmmmmmmfo....",
    ".offfffffffo....",
    ".offmmmmmmfo....",
    ".offffffffffo...",
    ".odddddddddddo..",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 120, 170, 230, 255 },
    m = { 40, 70, 130, 255 }, d = { 70, 110, 180, 255 },
})

-- 江湖追杀：通缉令上一道血色刀痕。
RELIC_SPRITES["jungle_hunt"] = Sprite({
    "..oooooooooooo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offfffffffffo..",
    ".offmmmffffffo..",
    ".offmmmmfffffo..",
    ".offmmmmfffffo..",
    ".offmmmffffffo..",
    ".offfffffffffo..",
    ".offmfffffmffo..",
    ".offfffffffffo..",
    ".odddddddddddo..",
    "..oooooooooooo..",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 235, 220, 180, 255 },
    m = { 150, 40, 40, 255 }, d = { 180, 160, 120, 255 },
})

-- 榨汁机：玻璃杯中半满的橙色果汁。
RELIC_SPRITES["juicer"] = Sprite({
    "................",
    ".....oooooo.....",
    "....offffffo....",
    "...offffffffo...",
    "..offffffffffo..",
    ".offffffffffffo.",
    ".offffffffffffo.",
    ".offmmmmmmmmffo.",
    ".offmmmmmmmmffo.",
    ".offmmmmmmmmffo.",
    ".offmmmmmmmmffo.",
    ".odmmmmmmmmdddo.",
    ".odddddddddddo..",
    "..oooooooooo....",
    "................",
    "................",
}, {
    o = INK, f = { 230, 240, 245, 255 },
    m = { 250, 140, 60, 255 }, d = { 180, 190, 200, 255 },
})

-- 最后一秒：沙漏只余最后一撮金沙。
RELIC_SPRITES["last_second"] = Sprite({
    "..oooooooooooo..",
    ".offffffffffffo.",
    ".offfffffffffo..",
    "..offfffffffo...",
    "...offfffffo....",
    "....offfffo.....",
    ".....offfo......",
    "......ofo.......",
    ".....offfo......",
    "....offfffo.....",
    "...offfmmfo.....",
    "..offfmmmmfo....",
    ".offmmmmmmmfo...",
    ".offffffffffo...",
    "..oooooooooo....",
    "................",
}, {
    o = INK, f = { 230, 225, 210, 255 },
    m = { 220, 170, 60, 255 },
})

-- 车厘子：一对进口大樱桃与加号角标。
RELIC_SPRITES["cherry_plus"] = Sprite({
    ".......o........",
    "......ogo.......",
    ".....o..o.......",
    "..o.o....o......",
    ".ooo......ooo...",
    "ohhrro..ohhrro..",
    "ohhrro..ohhrro..",
    "ohrrro..ohrrro..",
    "orrrro..orrrro..",
    "orddro..orddro..",
    ".oddo....oddo...",
    "..oo......oo..+.",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, g = { 80, 200, 120, 255 },
    r = { 200, 40, 60, 255 }, h = { 255, 140, 150, 255 },
    d = { 130, 20, 35, 255 }, ["+"] = { 255, 217, 61, 255 },
})

-- 精进刀法：交叉的双刀出鞘。
RELIC_SPRITES["knife_skill"] = Sprite({
    ".o..........o...",
    ".ho........oh...",
    ".hho......ohh...",
    "..hho....ohh....",
    "...hho..ohh.....",
    "....hhoohh......",
    ".....ohho.......",
    "....ohhhho......",
    "...ohh..hho.....",
    "..ohh....hho....",
    "..hh......hh....",
    ".kk........kk...",
    ".k..........k...",
    "................",
    "................",
    "................",
}, {
    o = INK, h = { 210, 220, 230, 255 },
    k = { 120, 80, 50, 255 },
})

-- 金盘洗手：金盆盛水，从此金盆洗手。
RELIC_SPRITES["wash_hands"] = Sprite({
    "................",
    "................",
    "....m..m..m.....",
    ".....m.m.m......",
    "..oooooooooooo..",
    ".offfffffffffo..",
    "offfffffffffffo.",
    "offfffffffffffo.",
    "offfffffffffffo.",
    ".offfffffffffo..",
    "..offfffffffo...",
    "...odddddddo....",
    "....oooooooo....",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 255, 217, 61, 255 },
    d = { 190, 140, 30, 255 }, m = { 130, 200, 255, 255 },
})

-- 厨师帽：蓬起的白色高帽。
RELIC_SPRITES["chef_hat"] = Sprite({
    "..o.o....o.o....",
    ".ohooh..oohoh...",
    ".ohhhhoohhhho...",
    "..ohhhhhhhhho...",
    "...ooooooooo....",
    "...offffffffo...",
    "...offffffffo...",
    "...offffffffo...",
    "...offffffffo...",
    "...offffffffo...",
    "...oddddddddo...",
    "...ooooooooo....",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, h = { 255, 255, 255, 255 },
    f = { 240, 240, 245, 255 }, d = { 195, 195, 205, 255 },
})

-- 贷款额度：一纸贷款合同与签字笔。
RELIC_SPRITES["credit_line"] = Sprite({
    "..oooooooooo.o..",
    ".offfffffffo.o..",
    ".offmmmmmffofo..",
    ".offfffffffofo..",
    ".offmmmmffofo...",
    ".offfffffffo....",
    ".offmmmmmffo....",
    ".offfffffffo....",
    ".offmmmmfffo....",
    ".offfffffffo....",
    ".odddddddddo....",
    "..oooooooooo....",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, f = { 245, 240, 225, 255 },
    m = { 110, 110, 130, 255 }, d = { 195, 185, 160, 255 },
})

return RELIC_SPRITES
end
