-- 扩展22件独立16×16像素图案；沿用INK硬描边、左上高光和右下阴影。
-- 只注册新ID，既有果汁和所有旧图案完全不覆盖；同类便便也有独立切面/彩虹纹。
---@param Sprite fun(rows:string[],palette:table<string,number[]>,mirror?:boolean):BottlePixelSprite
---@param INK number[]
---@param sprites table<string,BottlePixelSprite>
return function(Sprite, INK, sprites)
local function add(id, rows, colors)
    assert(not sprites[id], "扩展图案不得覆盖已有图案: " .. id)
    colors.o = INK
    sprites[id] = Sprite(rows, colors)
end

-- 小鸡：三瓣红冠、短翅与橙色三趾脚。
add("chick", {
    "................", "......o.oo......", ".....ororro.....", "....ooyyyyoo....",
    "...oyhhyyyyyo...", "..oyhhyyyyyyyo..", "..oyhyyoyyoyyo..", "..oyyyyyaayyyyo.",
    ".oyhyyyyayyyddo.", ".oyhhyhyyyyyddo.", "..oyhhyyyyyddo..", "...oyyyyyyddo...",
    "....ooooooo.....", ".....oa.oa......", "....oaa.aaao....", "................",
}, {h={255,244,160,255},y={255,217,61,255},d={214,143,40,255},a={244,139,53,255},r={255,71,87,255}})

-- 小羊：云团羊毛包围深色脸，四只短蹄。
add("sheep", {
    "................", "....ooo..ooo....", "..oohhhoohhhoo..", ".ohhhhhhhhhhhho.",
    ".ohhwhhhhhwhhho.", "ohhwhhhhhhwwhhho", "ohhhhhddddhhhhho", "ohhhhddllddhhhdo",
    ".ohhhdolldohhdo.", ".ohhhdllllldhdo.", "..ohhdlmmllddo..", "...ohdddddddo...",
    "....oddoooddo...", "....oddo.oddo...", "....oooo.oooo...", "................",
}, {h={245,242,224,255},w={255,255,248,255},d={97,101,124,255},l={160,155,157,255},m={242,157,172,255}})

-- 零羊毛露出窄身和长腿，五份以上为满幅胖羊；公开scale/weight不随库存改变。
add("sheep_0", {
    "................", "................", "...oo.....oo....", "...ohdooodho....",
    "....ohhhhho.....", "....odolodo.....", "....odllldo.....", ".....ommmo......",
    "....ohlllho.....", "...ohhlllddo....", "...ohllllldo....", "....ohllldo.....",
    "....odddddd.....", "....oddo.ddo....", "....oddo.ddo....", "....oooo.ooo....",
}, {h={218,213,197,255},d={97,101,124,255},l={160,155,157,255},m={242,157,172,255}})
add("sheep_5", {
    "...ooo....ooo...", ".oohhhoooohhhoo.", "ohhwwhhhhhhwwhho", "ohhwhhhhhhhhwhho",
    "ohhhhhhhhhhhhhho", "ohhwhhhhhhwwhhho", "ohhhhddddddhhhho", "ohhhddllllddhhdo",
    "ohhhdollllodhhdo", "ohhhdlllllldhhdo", "ohhhdllmmlldhhdo", "ohhhhddddddhhhdo",
    "ohhhhhhhhhhhhddo", ".ohhhhhhhhddddo.", "..ooddooodddoo..", "...oooo..oooo...",
}, {h={245,242,224,255},w={255,255,248,255},d={97,101,124,255},l={160,155,157,255},m={242,157,172,255}})

-- 小猪：分开的尖耳、粉红圆鼻与卷尾，不能复用人类圆头。
add("pig", {
    "................", "..ooo.....ooo...", "..ophho..ohhpo..", "..ophhhoohhhpo..",
    "..ohhhhhhhhhho..", ".ohhhhhhhhhhhho.", ".ohhhohhhhhohho.", "ohhhhhhpphhhhho.",
    "ohhhhhpoppohhhdo", "ohhhhhpppphhdddo", ".ohhhhhhhhhdddo.", "..ohhhhhhhdddo..",
    "...opppppdddo...", "...oppooopppo...", "...ooo...ooo....", "................",
}, {h={255,177,189,255},p={233,113,150,255},d={172,72,113,255}})

-- 小牛：奶白脸、两只黄角、黑斑和宽鼻。
add("calf", {
    "...oo......oo...", "..oyyo....oyyo..", "..oywooooowyo...", ".oowwwwwwwwwwoo.",
    "ohhwwddwwwwhhho.", "ohhwwdddwwwdhho.", ".owwwoddwwowwo..", ".owwwwwwwwwwdo..",
    "..owpppppppwdo..", "..owpommmopwdo..", "..owpppppppwdo..", "...owwwwwwddo...",
    "...owddwwwddo...", "...oddooodddo...", "...ooo...oooo...", "................",
}, {h={255,255,246,255},w={229,234,221,255},d={69,73,95,255},p={237,158,166,255},m={190,103,132,255},y={255,217,116,255}})

-- 小草：三束尖叶，中央窄叶与两侧斜叶之间留透明凹口。
add("grass", {
    "................", ".......oo.......", ".......oho......", "...oo..ohgo.....",
    "...oho.ohgo..oo.", "....ohgohgo.ogo.", ".oo.ohgohgoohgo.", ".ohgohgohgohgo..",
    "..ohgohghgohgo..", "..ohghghgghgo...", "...ohhgggghgo...", "...ohggggggo....",
    "....oggggdo.....", "....oddddo......", ".....oooo.......", "................",
}, {h={165,242,123,255},g={80,180,90,255},d={38,109,71,255}})

-- 草堆：金色梯形干草捆、双绳扎带，与绿色尖草独立。
add("hay", {
    "................", ".....oooooo.....", "....oyhyyyyo....", "...oyhyyyyyyo...",
    "..oyhybyybyyyo..", ".oyhyybyybyyyyo.", ".oyhyybyybyyydo.", "oyhyyybyybyyyddo",
    "oyhyyybyybyyyddo", "oyhyhhbhhbhhyddo", "oyhyyybyybyyyddo", "oyyyyybyybyydddo",
    "oyyyyybyybyydddo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {h={255,234,143,255},y={218,171,74,255},d={155,104,44,255},b={112,75,47,255}})

-- 普通便便：三层棕色卷堆与独立弯尖。
add("poop", {
    "................", ".......oo.......", "......ohdo......", ".....ohbdo......",
    "....ohbbddo.....", "....ohbbbdo.....", "...ohbbbbddo....", "..ohhbbbbdddo...",
    "..ohbbbbbbddo...", ".ohhbbbbbbbddo..", "ohhhbbbbbbbbddo.", "ohhbbbbbbbbbdddo",
    "ohbbbbbbbbbbdddo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {h={196,140,82,255},b={151,91,49,255},d={96,60,38,255}})

-- 黄金便便：亮金卷堆与浮雕双高光。
add("golden_poop", {
    "................", ".......oo.......", "......ohdo......", ".....ohydo......",
    "....ohyyddo.....", "....ohyhydo.....", "...ohhyyyhdo....", "..ohhyyyydddo...",
    "..ohyyyyyyddo...", ".ohhyyhyyyyddo..", "ohhhyyhhyyyyddo.", "ohhyyyyyyyyydddo",
    "ohyyyyyyyyyydddo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {h={255,250,190,255},y={255,217,61,255},d={184,122,35,255}})

-- 钻石便便：冰蓝切面以折线表达，底部保留原卷堆形。
add("diamond_poop", {
    "................", ".......oo.......", "......ohdo......", ".....ohbdo......",
    "....ohhbddo.....", "....ohbbhdo.....", "...ohbbhhbdo....", "..ohhbddbbddo...",
    "..ohbbhbbbbdo...", ".ohhbbhbbbhhdo..", "ohhhbbhbbhhbddo.", "ohbbddhhbbbbbddo",
    "ohhhbbhbbbbddhdo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {h={232,255,255,255},b={100,214,241,255},d={67,123,203,255}})

-- 彩虹便便：红橙黄绿蓝紫横层，不用仅换单一色板冒充。
add("rainbow_poop", {
    "................", ".......oo.......", "......ohro......", ".....ohrro......",
    "....ohaaado.....", "....ohyyydo.....", "...ohyyyyydo....", "..ohhggggggdo...",
    "..ohgggggggdo...", ".ohhbbbbbbbbdo..", "ohhhbbbbbbbbbdo.", "ohhpppppppppppdo",
    "ohpppppppppppddo", ".oddddddddddddo.", "..oooooooooooo..", "................",
}, {h={255,250,235,255},r={255,99,122,255},a={255,162,72,255},y={255,227,85,255},g={80,218,151,255},b={87,175,244,255},p={179,114,231,255},d={99,63,149,255}})

-- 壁虎：四个张开的脚掌、长身和弯尾；凹口不并成方块。
add("gecko", {
    "...oo....oo.....", "..ohgo..ohgo....", "...ohgoohgo.....", "....ohhhhgo.....",
    "....ohogogo.....", ".....ohgggo.....", "..oo.ohggo.oo...", ".ohgohhgggohggo.",
    "..oohhgggggoo...", ".....ohgggo.....", "....ohgggo......", "....ohggo.......",
    ".....ohgo.......", "......ohgo..oo..", ".......ohgoogo..", "........ooooo...",
}, {h={172,239,134,255},g={69,169,96,255}})

-- 仙人掌：主体与两侧上举枝，刺为像素装饰不扩大碰撞区域。
add("cactus", {
    "......oooo......", ".....ohgggo.....", ".....ohggho.....", "..oo.ohgggo.....",
    ".ohgoohgggo..oo.", ".ohggohghgo.oggo", ".ohggohgggo.oggo", ".ohgggggggohgggo",
    "..ooggggggohggo.", "....oohggggggo..", ".....ohgggooo...", ".....ohghgo.....",
    ".....ohgggo.....", "....oddddddo....", "....oddddddo....", ".....oooooo.....",
}, {h={165,242,160,255},g={53,157,104,255},d={155,91,59,255}})

-- 算盘：红木外框、五杆双色珠，不使用文字数字。
add("abacus", {
    "................", ".oooooooooooooo.", ".ohhhhhhhhhhddo.", ".ohlylylylylddo.",
    ".ohyyyyyyyyyddo.", ".ohlylylylylddo.", ".ohdddddddddddo.", ".ohlylylylylddo.",
    ".ohlrlrlrlrlddo.", ".ohrrrrrrrrrddo.", ".ohlrlrlrlrlddo.", ".ohrrrrrrrrrddo.",
    ".ohlylylylylddo.", ".oddddddddddddo.", ".oooooooooooooo.", "................",
}, {h={207,133,86,255},d={106,59,56,255},l={233,201,139,255},y={255,217,61,255},r={224,87,99,255}})

-- 保镖：方肩深蓝西服、墨镜和耳麦，金色领结。
add("bodyguard", {
    ".....oooooo.....", "....oddddddo....", "...oddddddddo...", "...ollllllllo...",
    "...ollolllolo...", "...olooooollo...", "...ollllmlldo...", "....ollllldo....",
    "...ooollllooo...", "..odddwyywdddo..", ".oddddwwwwddddo.", "oddddddwdddddddo",
    "odhhdddwdddddldo", "oddddddwdddddddo", ".oddddddddddddo.", "..oooooooooooo..",
}, {d={49,63,93,255},l={222,166,135,255},m={151,88,91,255},w={242,243,232,255},y={255,217,61,255},h={89,107,138,255}})

-- 养鸡人：草帽、红背带裤，怀抱白蛋。
add("chicken_keeper", {
    ".....oooooo.....", "....ohhhhhho....", "...ohhyyyyhho...", "..ooyyyyyyyyoo..",
    ".oyyyyyyyyyyyyo.", "...ollllllllo...", "...olowllowlo...", "...oloblloblo...",
    "....olmmmllo....", "..ooorllroooo...", ".ollrrrrrrrllo..", "olllrrowworrllo.",
    ".ollrohhhhorlo..", "..orrhwwwwhro...", "..oddohhhhoddo..", "...oooooooooo...",
}, {h={255,241,192,255},y={207,158,76,255},l={240,186,147,255},w={245,253,255,255},b={50,47,67,255},m={151,88,91,255},r={203,75,86,255},d={105,68,65,255}})

-- 分裂器：双塔金属门与中间紫色切分光，不挖空主机架。
add("splitter", {
    "................", "..oooo....oooo..", ".ohhhdo..ohhhdo.", ".ohbbdo..ohbbdo.",
    ".ohbgdo..ohbgdo.", ".ohbbdo..ohbbdo.", ".ohbbdo..ohbbdo.", ".ohbbdoppohbbdo.",
    ".ohbbdoppohbbdo.", ".ohbbdo..ohbbdo.", ".ohbbdo..ohbbdo.", ".ohbgdo..ohbgdo.",
    ".ohbbdo..ohbbdo.", ".ohbbbbbbbbbbdo.", "..oddddddddddo..", "...oooooooooo...",
}, {h={222,236,246,255},b={124,155,184,255},d={58,77,116,255},g={33,189,174,255},p={198,142,255,255}})

-- 飞盘运动员：青绿运动衫、红头带与横握橙盘，不复用教练。
add("discus_athlete", {
    ".....oooooo.....", "....oddddddo....", "...oddddddddo...", "...orrrrrrrro...",
    "...ollllllllo...", "...olowllowlo...", "...oloblloblo...", "....ollllmmlo...",
    "...ooollllooo...", "..oggwgggggggo..", ".olggwggggglllo.", "ollggwgggllllllo",
    ".ollgggggoyyyo..", "..ogggggoyhhyyyo", "..odddddooyyyoo.", "...ooooooo......",
}, {d={61,62,84,255},r={235,83,103,255},l={238,183,145,255},w={248,249,238,255},b={40,40,60,255},m={151,88,91,255},g={33,189,174,255},h={255,234,141,255},y={250,171,54,255}})

-- 飞盘：俯斜薄盘，双亮环与窄厚边；碰撞是匹配椭圆的八边凸片。
add("discus", {
    "................", "................", "................", "................",
    ".....oooooo.....", "..ooohhhhhhooo..", ".ohhyyyyyyyyhho.", "ohyyhhyyyyhhyyyo",
    "ohyyhyyyyyyhyydo", ".oyyyyyyyyyyddo.", "..ooddddddddoo..", ".....oooooo.....",
    "................", "................", "................", "................",
}, {h={255,243,167,255},y={255,181,65,255},d={209,113,46,255}})

-- 指南针：金属八边圆壳、红白针与青绿刻度。
add("compass", {
    ".....oooooo.....", "...oohhhhhhoo...", "..ohhbbbbbbhho..", ".ohbbbgobbbbbho.",
    ".ohbbbrobbbbbdo.", "ohbbbrrrobbbbbdo", "ohbbrrrrobbbbbdo", "ohbrrrrrobbbbbdo",
    "ohbbbooowwbbbbdo", "ohbbbbowwwbbbbdo", "ohbbbbowwbbbbbdo", ".ohbbbowbbbbddo.",
    ".ohbbbgobbbbddo.", "..odbbbbbbbddo..", "...oddddddddo...", ".....oooooo.....",
}, {h={230,234,225,255},b={70,91,111,255},d={41,53,79,255},r={255,91,115,255},w={245,253,255,255},g={66,215,190,255}})

-- 果冻：圆顶布丁形、半透明亮面色块，笑脸不增碰撞。
add("jelly", {
    "................", "................", ".....oooooo.....", "...oohhhpppoo...",
    "..ohhhhhpppppo..", "..ohhwwppppppo..", ".ohhhwpppppppdo.", ".ohhhppppppppdo.",
    ".ohhppopppoppdo.", "ohhhpppppppppddo", "ohhppppmmmpppddo", "ohpppppppppppddo",
    ".opppppppppdddo.", "..oddddddddddo..", "...oooooooooo...", "................",
}, {h={198,165,248,255},p={143,109,222,255},d={87,64,159,255},w={244,226,255,255},m={242,164,207,255}})

-- 羊毛：蓬松卷团与三条旋转纤维纹，不复用小羊。
add("wool", {
    "................", "....ooo..ooo....", "..oohhhoohhhoo..", ".ohhhhhhhhhhhho.",
    ".ohhwwwhhhhwhho.", "ohhwhllhhhhwwhho", "ohhhllhhlhhhhhho", ".ohhlhhhlhhhhdo.",
    "ohhhhhhllhhhwhdo", "ohhwhhhhhhhlhhdo", ".ohhwwhhhllhhdo.", ".ohhhhhhhhhhhdo.",
    "..ohhhhhhhdddo..", "...ooddddddoo...", ".....oooooo.....", "................",
}, {h={241,235,213,255},w={255,255,245,255},l={197,184,174,255},d={157,148,155,255}})

-- 羊毛衫：V领、长袖与横向针织纹，袖下透明凹口不填充。
add("sweater", {
    "................", "...ooo....ooo...", "..ohhroooorhho..", ".ohhhrwrrwrhhho.",
    "ohhhhrwwwwrhhhro", "ohhhhrwrrwrhhhro", "ohhhrrrrrrrrhhro", "ohrorhhhhhhrobro",
    "ohr.orrrrrro.bro", "ohr.orhhhhro.bro", "ooo.orrrrrro.ooo", "....orhhhhro....",
    "....orrrrrro....", "....oddddddo....", "....oooooooo....", "................",
}, {h={255,151,151,255},r={207,77,102,255},d={144,54,86,255},w={255,231,206,255},b={175,61,88,255}})
end
