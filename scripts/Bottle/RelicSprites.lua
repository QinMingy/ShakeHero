-- 遗物独立16×16像素原稿；新增图案不改变既有原色/像素/接口。
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

-- seeYouTomorrow：16×16乳白菇束与绿色循环箭头，和金针菇统一像素密度。
RELIC_SPRITES["see_you_tomorrow"] = Sprite({
    ".........oooo...",
    "........ogggGo..",
    "..........ooGGo.",
    "......oo....oGo.",
    ".....ohyo..oggo.",
    ".....oddo..ogggg",
    "...oo.owo...oogo",
    "..ohyowoo.oo.ooo",
    "..oddowooohyo...",
    "...owowowoddo...",
    "..oowowwwowo....",
    ".ogowwwwwwoo....",
    ".oGo.owwwoo.....",
    ".oGGoogoo.......",
    "..ogggggo.......",
    "...ooogoo.......",
}, {
    o = { 10, 10, 25, 255 }, h = { 255, 248, 224, 255 },
    w = { 242, 231, 199, 255 }, y = { 255, 219, 117, 255 },
    d = { 224, 189, 127, 255 }, g = { 73, 185, 112, 255 },
    G = { 37, 118, 77, 255 },
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

-- 名师团队：三位教师与共同的金色课本。
RELIC_SPRITES.teacher_team = Sprite({
    "................", "..ooo..ooo..ooo.", "..oso..oso..oso.", "..ooo..ooo..ooo.",
    ".obbb.obbb.obbb.", ".obbb.obbb.obbb.", "..oooooooooooo..", "..offffofffffo..",
    "..offffofffffo..", "..offffofffffo..", "..offffofffffo..", "..oooooooooooo..",
    "...bbb..bbb.....", "...obo..obo.....", "...ooo..ooo.....", "................",
}, {o=INK,s={227,184,145,255},b={85,119,161,255},f={233,207,132,255}})

-- 加速器：青色推进环与两道向右的箭头。
RELIC_SPRITES.accelerator = Sprite({
    "................", "....oooooo......", "..ooccccccoo....", ".occhhhhhccco...",
    ".occhhcccccoco..", "occhcccccccoco..", "occch..y...occo.", "occc...yy..occo.",
    "occcyyyyyy.occco", "occc...yy..occo.", "occch..y...occo.", ".occchhhhccco...",
    "..occcccccco....", "...oooooooo.....", "................", "................",
}, {o=INK,c={66,157,178,255},h={156,230,225,255},y={245,201,94,255}})

-- 幽灵便便：半透明蓝绿便便与星点。
RELIC_SPRITES.ghost_poop = Sprite({
    "................", "..h......h......", ".......ooo......", "......occco.....",
    ".....occccco....", "....occcccco....", "....occcchcco...", "...occcccccco...",
    "..occcmccmccco..", ".occcccccccccco.", ".occchccccccccco", "occcccccccccccco",
    "occchcccccccccdo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {o={45,58,67,153},c={110,205,182,153},h={224,255,232,190},m={50,70,76,200},d={74,146,151,153}})

-- 优质小草：扎金带的嫩绿草束。
RELIC_SPRITES.premium_grass = Sprite({
    "................", "...h.......h....", "....g..g........", "..g.gg.gg..g....",
    "..ggggggg.gg....", "...gggggggg.....", "...gghggggg.....", "....gggggg......",
    "....gggggg......", "....yyyyyy......", "...oyyyyyo......", "....gggggg......",
    "....gggggg......", ".....gggg.......", "......oo........", "................",
}, {o=INK,g={102,187,105,255},h={202,235,155,255},y={233,191,74,255}})

-- 吃了不烧心：粉色胃袋配清凉薄荷十字。
RELIC_SPRITES.food_comfort = Sprite({
    "......ooo.......", "......opo.......", "......opo.......", ".....oppo.......",
    "....opppo.......", "...oppppooo.....", "..oppppppppo....", ".oppphppppppo...",
    ".oppphpppppppo..", ".opppppppppppo..", "..opppppppppo...", "...opppppppo....",
    "....ooooooo..g..", "............ggg.", ".............g..", "................",
}, {o=INK,p={215,132,151,255},h={246,188,185,255},g={116,209,172,255}})

-- 培根是对的：培根结点连起三个蓝色节点。
RELIC_SPRITES.bacon_network = Sprite({
    "................", "..ooo......ooo..", "..oco......oco..", "..ooo......ooo..",
    "....c......c....", ".....c....c.....", "...oooooooooo...", "..opprpprppppo..",
    "..orppprppprpo..", "..opprpprppppo..", "...oooooooooo...", "........c.......",
    "........c.......", ".......ooo......", ".......oco......", ".......ooo......",
}, {o=INK,p={224,153,141,255},r={168,79,89,255},c={112,179,201,255}})

-- 幽灵运动：白幽灵系着红头带、脚边运动鞋。
RELIC_SPRITES.ghost_sport = Sprite({
    "................", ".....oooooo.....", "....ohhhhhho....", "...orrrrrrrro...",
    "...ohhhhhhhho...", "..ohhmhhmhhhho..", "..ohhhhhhhhhho..", "..ohhhhhhhhhho..",
    "...ohhhhhhhho...", "...ohhhhhhhho...", "....ohhhohho....", ".....oo..oo.....",
    "..rrrr....rrrr..", ".orrrro..orrrro.", "..oooo....oooo..", "................",
}, {o=INK,h={212,228,235,255},m={66,76,96,255},r={202,94,100,255}})

-- 转圈圈：环形金箭头围着青色旋钮。
RELIC_SPRITES.spin_reward = Sprite({
    "................", ".....yyyyyy.....", "...yy......yy...", "..yy........yy..",
    ".yy.....y....yy.", ".y.....yyy....y.", ".y....yyyyy...y.", ".y.....ooo....y.",
    ".y....occco...y.", ".y....occco...y.", ".yy....ooo...yy.", "..yy........yy..",
    "...yy......yy...", ".....yyyyyy.....", "................", "................",
}, {o=INK,y={225,190,87,255},c={114,177,185,255}})

-- 羊毛集市：毛线球与1元金币摆在木摊上。
RELIC_SPRITES.wool_market = Sprite({
    "................", "..oooooooooooo..", ".orryyrryyrryyo.", ".orryyrryyrryyo.",
    "..oooooooooooo..", "..o..........o..", "..o..hhh..yy.o..", "..o.hhhho.yyo...",
    "..ohhhhhhoymyo..", "..ohhhhho.yyo...", "..o.hhh...yy.o..", "..oooooooooooo..",
    "..obbbbbbbbbbo..", "..obbbbbbbbbbo..", "..oo........oo..", "................",
}, {o=INK,r={181,90,96,255},y={235,193,84,255},h={229,224,202,255},m={133,97,44,255},b={131,101,76,255}})

-- 羊毛回收：奶白纤维球置于青绿回转箭头内，区别于木摊羊毛集市。
RELIC_SPRITES.wool_recycle = Sprite({
    "................", "....oooooooo....", "...ohggggggdo...", "..ohggoooogddo..",
    ".ohggo....ogddo.", ".ohgo.oooo.oooo.", ".ooo.ohhhho..o..", "....ohwwhhho....",
    "..o.ohhllhdo.oo.", ".ooooohhlhdoogdo", ".ohgo.ohhdo.ogdo", ".ohggo.ooo.ogddo",
    "..ohggooooggddo.", "...ohgggggdddo..", "....oooooooo....", "................",
}, {o=INK,h={239,232,208,255},w={255,255,244,255},l={194,177,165,255},g={68,181,141,255},d={42,116,108,255}})

-- 骰号大奖：三尖金冠下的五点白骰，底部红绶带，不复用作弊骰子。
RELIC_SPRITES.dice_jackpot = Sprite({
    "..oo...oo...oo..", "..oyo.ohyo.oyo..", "..oyyoyhyyoyyo..", "...oyyyyyyyyo...",
    "...oddddddddo...", "..oooooooooooo..", ".ohhhhhhhhhhhdo.", ".ohwoowwwoowwdo.",
    ".ohwoowwwoowwdo.", ".ohwwwwoowwwwdo.", ".ohwwwwoowwwwdo.", ".ohwoowwwoowwdo.",
    ".ohwoowwwoowwdo.", "..oddddddddddo..", "...orrr..rrro...", "...orro..orro...",
}, {o=INK,h={255,249,201,255},y={247,196,74,255},w={235,240,235,255},d={144,127,96,255},r={210,76,99,255}})

-- 牛来！：向右冲刺的斑纹小牛、前伸黄角和左侧速度条，与正脸小牛区分。
RELIC_SPRITES.calf_rush = Sprite({
    "................", "...........oo...", "..........oyyo..", ".........oowwoo.",
    "..ooo..oowwwwwdo", ".ohho.ohhwwowwdo", "..oo.ohwwddwwwdo", ".oooohwwwddwpppo",
    "ohhwwwwwwwwwpmmo", ".oowwwddwwwwpppo", "..owwwddwwwddoo.", "..owwwwwwwddo...",
    "...ooddoooodo...", "..ohdo.....oddo.", ".oooo.......ooo.", "................",
}, {o=INK,h={255,255,241,255},w={226,233,216,255},d={68,75,96,255},p={235,157,166,255},m={177,97,126,255},y={251,205,100,255}})

-- 幸运转盘：金紫小轮配右上四叶草与绿底座，轮廓不复用物品转盘。
RELIC_SPRITES.lucky_roulette = Sprite({
    "..........oo.oo.", ".........ohgoggo", "....ooooo.ogggo.", "..oohhhhoohgoggo",
    ".ohyyyyyo.oo.oo.", "ohyyyoyypppdo...", "ohyyyooypppdo...", "ohyyohoopppdo...",
    "ohppoooyyyydo...", "ohpppoyyyyydo...", ".odppyyyyddo....", "..odddddddo.....",
    "....ooooo.......", "...ohgggdo......", "..ohgggggdo.....", "..ooooooooo.....",
}, {o=INK,h={255,242,181,255},y={241,192,72,255},p={152,103,181,255},g={75,177,127,255},d={139,98,65,255}})

-- 老八秘制：酱红小罐与金色封签。
RELIC_SPRITES.secret_recipe = Sprite({
    "................", ".....oooooo.....", "....oyyyyyyo....", "....oooooooo....",
    ".....orrrro.....", "....orrrrrro....", "...orrrrrrrro...", "...orhrrrrrro...",
    "...orhyyyrrro...", "...orrymyrrro...", "...orryyyrrro...", "...orrrrrrrro...",
    "...oddddddddo...", "....oooooooo....", "................", "................",
}, {o=INK,r={162,65,57,255},y={239,194,95,255},h={219,119,88,255},m={96,63,51,255},d={108,53,52,255}})

-- 流星雨：三条斜落的蓝色星迹。
RELIC_SPRITES.meteor_shower = Sprite({
    ".............c..", "............cc..", "...........ch...", "..........ch....",
    "....c....ch.....", "...cc...ch......", "..ch...hyh......", ".ch...hyyyh.....",
    "ch.....hyh......", "hyh.....h....c..", "yyyh........cc..", "hyh........ch...",
    ".h........hyh...", ".........hyyyh..", "..........hyh...", "...........h....",
}, {c={78,138,203,255},h={166,219,245,255},y={255,224,134,255}})

return RELIC_SPRITES
end
