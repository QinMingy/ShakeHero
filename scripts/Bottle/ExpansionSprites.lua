-- 扩展物品独立16×16像素图案；沿用INK硬描边、左上高光和右下阴影。
-- 只注册新ID，既有果汁和所有旧图案完全不覆盖；同类便便也有独立切面/彩虹纹。
---@param Sprite fun(rows:string[],palette:table<string,number[]>,mirror?:boolean):BottlePixelSprite
---@param INK number[]
---@param sprites table<string,BottlePixelSprite>
return function(Sprite, INK, sprites)
local function add(id, rows, colors)
    assert(not sprites[id], "扩展图案不得覆盖已有图案: " .. id)
    colors.o = colors.o or INK
    sprites[id] = Sprite(rows, colors)
end

-- 小鸡：三瓣红冠、短翅与橙色三趾脚。
add("chick", {
    "................", "......o.oo......", ".....ororro.....", "....ooyyyyoo....",
    "...oyhhyyyyyo...", "..oyhhyyyyyyyo..", "..oyhyyoyyoyyo..", "..oyyyyyaayyyyo.",
    ".oyhyyyyayyyddo.", ".oyhhyhyyyyyddo.", "..oyhhyyyyyddo..", "...oyyyyyyddo...",
    "....ooooooo.....", ".....oa.oa......", "....oaa.aaao....", "................",
}, {h={255,244,160,255},y={255,217,61,255},d={214,143,40,255},a={244,139,53,255},r={255,71,87,255}})

-- 奶白毛绵羊侧身：按用户选定参考图恢复深灰脸腿、粉耳鼻与近黑硬描边。
-- 库存0仍保留贴身奶白短绒，1–4为蓬起的卷绒，5以上为圆鼓鼓的厚毛。
local sheepColors = {
    h={245,242,224,255}, w={255,255,248,255}, s={205,201,186,255},
    d={69,73,87,255}, l={102,106,119,255}, e={213,151,157,255}, m={164,109,119,255},
    o={10,10,26,255},
}
add("sheep_0", {
    "................", "................", "................", "................",
    "..........oooo..", ".........odlldo.", "...ooooo.oddddoo", "..ohwhhhhodowdde",
    ".ohhhshhhoddddo.", ".ohhhhhsssodddo.", "..ohhhssssoddmo.", "...ohsssssoooo..",
    "....odooddo.....", "....od..odo.....", "....oo..ooo.....", "................",
}, sheepColors)
add("sheep", {
    "................", "................", "................", "....ooo.ooo.....",
    "..oohhhohhhoo...", ".ohwwhhhhhhhooo.", ".ohwhshhhodlldoo", "ohhhhhhhhodowdde",
    "ohhshhhhsoddddo.", ".ohhhshhhsodddo.", ".ohhhhhsssoddmo.", "..ohhsssssoooo..",
    "...oodooddoo....", "....od..odo.....", "....oo..ooo.....", "................",
}, sheepColors)
add("sheep_5", {
    "................", "....ooo.ooo.....", "..oohhhohhhoo...", ".ohwwhhhhhhhhoo.",
    ".ohwhhshhhhhhhho", "ohhhshhhhshhooo.", "ohhhhhhhhodlldoo", "ohhshhhshodowdde",
    "ohhhhhhhhshodddo", "ohhshhshhhsodddo", ".ohhhhhshssoddmo", ".ohhshhhhsssoooo",
    "..ohhhsssssso...", "...oodooddoo....", "....oo..ooo.....", "................",
}, sheepColors)

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

-- 陀螺：直立短轴、宽红金盘身与收尖锥底，区别于扁飞盘。
add("spinning_top", {
    ".......oo.......", "......ohyo......", "......ohyo......", ".....ooyyoo.....",
    "...oohhhhhhoo...", "..ohhyyyyyyhho..", ".ohhrrrrrrrrhdo.", "ohhrryyyyyyrrddo",
    ".oyyyrrrrrryydo.", "..orrrrrrrrrdo..", "...orrrrrrddo...", "....orrrrddo....",
    ".....oyyddo.....", "......oydo......", ".......oo.......", "................",
}, {h={255,243,177,255},y={245,191,71,255},r={223,85,98,255},d={153,57,83,255}})

-- 风车：红黄蓝绿四折叶、金色轴心与细木柄，叶间保留透明凹口。
add("windmill", {
    "......oooo......", "......ohro......", "..ooo.ohrro.....", ".ohhyo.orrro....",
    ".ohyyyoorrro....", "..oyyyyorrroooo.", "...oyyyooybbhho.", "....ooyhybbbhho.",
    ".ooooggoybbbo...", ".ohggggoobbo....", ".ohggggoooo.....", "..oggggoho......",
    "...ogg.oho......", "....oo.oho......", ".......odo......", ".......ooo......",
}, {h={255,244,193,255},r={230,91,112,255},y={247,204,84,255},b={95,169,216,255},g={86,181,133,255},d={139,95,67,255}})

-- 齿轮：八向凸齿、冷钢亮边与贯通方轴孔，空心不画成硬币。
add("gear", {
    "......oooo......", ".....ohhhdo.....", "..oooohbbdoooo..", ".ohhhbbbbbbdddo.",
    ".ohbbbbbbbbbbdo.", "..ohbbboobbbdo..", "ooohbbo..obbdooo", "ohbbbbo..obbbbdo",
    "ohbbbbo..obbbbdo", "ooodbbo..obbdooo", "..odbbboobbbdo..", ".ohbbbbbbbbbbdo.",
    ".oddbbbbbbbdddo.", "..oooodbbdoooo..", ".....oddddo.....", "......oooo......",
}, {h={226,240,246,255},b={134,170,192,255},d={65,91,121,255}})

-- 转盘：独立红青扇区圆盘、金属亮边和上端红指针；不复用指南针。
add("roulette", {
    ".......oo.......", "......orro......", ".....oorroo.....", "...oohhrrhhoo...",
    "..ohhrrryyhddo..", ".ohrrrroyyybbdo.", ".ohrrrroyybbbdo.", "ohrrrrroobbbbbdo",
    "ohyyyyohoobbbbdo", "ohyyyyooogggggdo", ".ohyybbogggggdo.", ".ohbbbboggggddo.",
    "..odbbbggggddo..", "...oddddddddo...", ".....oooooo.....", "................",
}, {h={255,240,179,255},r={220,86,105,255},y={242,197,73,255},b={89,143,193,255},g={67,174,151,255},d={139,98,60,255}})

-- 移除币：青绿硬币、浅金轮缘与中央减号，区别于面额合成币。
add("removal_coin", {
    "................", ".....oooooo.....", "...oohhhhhoo....", "..ohhyyyyyhho...",
    ".ohyygggggyyho..", ".ohygggggggyho..", "ohygggggggggydo.", "ohygghhhhgggydo.",
    "ohygghhhhgggydo.", "ohygggggggggydo.", ".oyggggggggyddo.", ".oyyggggggyydo..",
    "..odyyyyyyddo...", "...odddddddo....", ".....oooooo.....", "................",
}, {h={246,245,193,255},y={217,187,102,255},g={91,194,166,255},d={45,110,105,255}})
end
