-- 新表剩余图案：PixelForge硬边像素；不覆盖原有图案或更换原色。
-- 硬币使用24×24画布容纳完整的1..2048金额；显示半径语义不变。
---@param Sprite fun(rows:string[], palette:table<string,number[]>, mirror?:boolean):BottlePixelSprite
---@param INK number[]
---@param sprites table<string,BottlePixelSprite>
return function(Sprite, INK, sprites)

-- 果汁：透明玻璃杯、橙色果汁与斜吸管，独立于完整／半份水果。
sprites.juice = Sprite({
    "..........oo....",
    ".........oyo....",
    "........oyo.....",
    "...oooooooooo...",
    "..owwwwwwwwwwo..",
    "...owyyyyyywo...",
    "...owyhhyyywo...",
    "...owyhhyyywo...",
    "...owyyyyyywo...",
    "...owyyyyddwo...",
    "....owyyddwo....",
    "....owyyddwo....",
    "....owwwwwwo....",
    ".....oooooo.....",
    "................",
    "................",
}, {
    o = INK, w = {178, 232, 241, 255}, y = {255, 171, 53, 255},
    h = {255, 224, 116, 255}, d = {214, 106, 39, 255},
})

-- 四面骰：三角实体，中央刻“4”，不是缺省金币或六面骰。
sprites.die_d4 = Sprite({
    ".......oo.......",
    ".......oho......",
    "......ohhho.....",
    "......ohhdo.....",
    ".....ohhhddo....",
    ".....ohhhddo....",
    "....ohhhddddo...",
    "....ohododddo...",
    "...ohhododdddo..",
    "...ohhoooodddo..",
    "..ohhhhoddhdddo.",
    "..ohhhhodhhdddo.",
    ".ohhhhhhhhhddddo",
    ".ohhhhhhhhdddddo",
    "ohhhhhhhhddddddo",
    "oooooooooooooooo",
}, {
    o = INK, h = {165, 255, 222, 255}, d = {33, 189, 174, 255},
})

-- 六面骰：削角方形、六枚独立深色点。
sprites.die_d6 = Sprite({
    "................",
    "...oooooooooo...",
    "..ohhhhhhhhhdo..",
    ".ohhhhhhhhhhddo.",
    ".ohhoohhoohhddo.",
    ".ohhoohhoohhddo.",
    ".ohhhhhhhhhhddo.",
    ".ohhoohhoohhddo.",
    ".ohhoohhoohhddo.",
    ".ohhhhhhhhhhddo.",
    ".ohhoohhoohhddo.",
    ".ohhoohhoohhddo.",
    ".ohhhhhhhhhhddo.",
    "..oddddddddddo..",
    "...oooooooooo...",
    "................",
}, {
    o = INK, h = {245, 253, 255, 255}, d = {167, 197, 214, 255},
})

-- 赌徒：红马甲、偏斜黑礼帽，胸前白色扑克牌。
sprites.gambler = Sprite({
    ".....oooooo.....",
    "....oddddddo....",
    "....odhhhddo....",
    "..oooyyyyyyooo..",
    ".oddddddddddddo.",
    "..oollllllloo...",
    "..olowllowllo...",
    "..olobllobllo...",
    "...olllllllo....",
    "....olmmllo.....",
    "..ooowrrwoooo...",
    ".orrrwrrwrrrro..",
    "orhrrwrrwwwwro..",
    "orhrrrrrwwrwro..",
    ".orrrrrrwwwwdo..",
    "..ooooooooooo...",
}, {
    o = INK, d = {40, 40, 55, 255}, h = {220, 90, 80, 255},
    y = {255, 217, 61, 255}, l = {246, 197, 153, 255},
    w = {245, 245, 250, 255}, b = {40, 40, 60, 255}, r = {160, 40, 40, 255},
    m = {150, 80, 70, 255},
})

-- 赌神：金冠、紫色礼服与金色领饰，和红马甲赌徒独立可辨。
sprites.gambling_god = Sprite({
    "..o....o....o...",
    "..oyo.oyo.oyo...",
    "..oyyyyyyyyyo...",
    "...oyhhyyyyo....",
    "..oodddddddoo...",
    "..olllllllllo...",
    "..olowllowllo...",
    "..olobllobllo...",
    "...olllllllo....",
    "....olmmllo.....",
    "..oooyyhyoooo...",
    ".opppyyypppppo..",
    "ophpppypppppdo..",
    "ophpppppppppdo..",
    ".opppppppppdo...",
    "..oooooooooo....",
}, {
    o = INK, y = {255, 217, 61, 255}, h = {255, 244, 160, 255},
    d = {69, 43, 109, 255}, l = {246, 197, 153, 255},
    w = {245, 245, 250, 255}, b = {40, 40, 60, 255},
    m = {150, 80, 70, 255}, p = {130, 85, 185, 255},
})

-- 健身教练：青绿运动头带、背心和横握哑铃。
sprites.fitness_coach = Sprite({
    ".....oooooo.....",
    "...oodddddoo....",
    "..oddddddddho...",
    "..ogggggggggo...",
    "..oollllllloo...",
    "..olowllowllo...",
    "..olobllobllo...",
    "...olllllllo....",
    "....olmmllo.....",
    "..ooolllloooo...",
    ".ollgggggggllo..",
    "ollhggggggglllo.",
    "okkolggggglookko",
    "okkkssssssskkko.",
    "okkoogggggookko.",
    "..ooooooooooo...",
}, {
    o = INK, d = {70, 50, 35, 255}, h = {255, 222, 180, 255},
    l = {235, 190, 140, 255}, g = {33, 189, 174, 255},
    w = {255, 255, 255, 255}, b = {40, 40, 60, 255},
    m = {150, 80, 70, 255}, k = {76, 105, 141, 255}, s = {167, 197, 214, 255},
})

-- 果树：整片绿冠、红果、棕色树干与分叉根，树冠/树干可分凸片。
sprites.fruit_tree = Sprite({
    ".....oooooo.....",
    "...oohhhhggoo...",
    "..ohhhhggggggo..",
    ".ohhhhggggggggo.",
    ".ohhrrgggggrrgo.",
    "ohhgrrgggggrrggo",
    "ohggggggggggggdo",
    "ohgggggrrgggggdo",
    ".ogggggrrggggdo.",
    "..odgggssgggdo..",
    "...ooodssdooo...",
    "......ohsdo.....",
    "......ohsdo.....",
    ".....oohsdoo....",
    "...oohhsssddo...",
    "...oooooooooo...",
}, {
    o = INK, h = {136, 242, 160, 255}, g = {80, 180, 90, 255},
    d = {45, 100, 66, 255}, s = {151, 91, 49, 255}, r = {255, 71, 87, 255},
})

-- 农民：深棕草帽、青绿背带裤与右侧长柄锄头，不复用果农图案。
sprites.farmer = Sprite({
    ".....oooooo.....",
    "....ohhhhhho....",
    "....ohhhhddo....",
    "..oohhhhhddooo..",
    ".ohhhhhhhdddddo.",
    "...olllllllo....",
    "...lowllowlo....",
    "...loblloblo....",
    "...olllllllo....",
    "....olmmllo..k..",
    "..ooggllggoo.kkk",
    ".olhgggggghlo.k.",
    "olllgsggsglllok.",
    ".ollggggggllo.k.",
    "..oddddddddo..k.",
    "...ooooooo....o.",
}, {
    o = INK, h = {196, 140, 82, 255}, d = {96, 60, 30, 255},
    l = {235, 190, 140, 255}, w = {255, 255, 255, 255}, b = {40, 40, 60, 255},
    m = {150, 80, 70, 255}, g = {33, 189, 174, 255},
    s = {255, 217, 61, 255}, k = {167, 197, 214, 255},
})

-- 水果商人：紫头巾、红白条围裙，胸前金苹果徽章。
sprites.fruit_merchant = Sprite({
    ".....oooooo.....",
    "...oohppppoo....",
    "..ohpppppppdo...",
    "..oppppppppdo...",
    "..oollllllloo...",
    "..olowllowllo...",
    "..olobllobllo...",
    "..olllllllllo...",
    "...ollmmlllo....",
    "..ooolllloooo...",
    ".orwrwrwrwrwro..",
    "orhwrwygwrwrro..",
    "orhwrwyywrwrdo..",
    ".orwrwyywrwrdo..",
    "..odddddddddo...",
    "...oooooooo.....",
}, {
    o = INK, h = {198, 165, 248, 255}, p = {130, 85, 185, 255},
    d = {69, 43, 109, 255}, l = {246, 197, 153, 255},
    w = {245, 245, 250, 255}, b = {40, 40, 60, 255},
    m = {150, 80, 70, 255}, r = {200, 60, 60, 255},
    y = {255, 217, 61, 255}, g = {80, 200, 120, 255},
})

-- 水滴：上尖下圆，左上留连续冰蓝高光，绝非圆球。
sprites.droplet = Sprite({
    ".......oo.......",
    ".......oho......",
    "......ohho......",
    "......ohhbo.....",
    ".....ohhhbo.....",
    ".....ohhhbbo....",
    "....ohhhbbbbo...",
    "...ohhwhhbbbbo..",
    "..ohhwwhhbbbbo..",
    "..ohhwhhbbbbbdo.",
    "..ohhhhhbbbbbdo.",
    "..ohhhhbbbbbbdo.",
    "...ohhbbbbbbdo..",
    "...ohbbbbbbddo..",
    "....odddddddo...",
    ".....oooooo.....",
}, {
    o = {30, 80, 115, 255}, h = {122, 190, 255, 255},
    w = {226, 244, 255, 255}, b = {74, 138, 210, 255}, d = {42, 86, 150, 255},
})

-- 猴子：左右大圆耳、浅色口鼻、棕色身体与卷尾。
sprites.monkey = Sprite({
    "................",
    "................",
    ".....oooooo.....",
    "...oohbbbddoo...",
    "...ohbbbbbbdo...",
    ".ooohllllllhooo.",
    "ohhohoolloohoddo",
    "ohhohoolloohoddo",
    ".ooohllmmllhooo.",
    "....ohllllho....",
    "....ohbbbbdo.oo.",
    "...ohbbbbbbdodho",
    "...ohbllllbbodho",
    "...ohbllllbbddo.",
    "....ohbllbdo....",
    "....oooooooo....",
}, {
    o = INK, h = {196, 140, 82, 255}, b = {151, 91, 49, 255},
    d = {96, 60, 30, 255}, l = {255, 218, 157, 255}, m = {150, 80, 70, 255},
})

-- 幸运硬币：金色盘面内刻独立四叶草，不混同合成面额币。
sprites.lucky_coin = Sprite({
    ".....oooooo.....",
    "...oohhhhhhoo...",
    "..ohhyyyyyyhho..",
    ".ohyyyyyyyyyyho.",
    ".ohyyggyyggyyho.",
    "ohyyggggggggyyho",
    "ohyyggggggggyydo",
    "ohyyyggggggyyydo",
    "ohyyyggggggyyydo",
    "ohyyggggggggyydo",
    "ohyyggggggggyydo",
    ".oyyyggyyggydyo.",
    ".oyyyyyggyyddyo.",
    "..odyyyyggdddo..",
    "...oddddddddo...",
    ".....oooooo.....",
}, {
    o = INK, h = {255, 244, 160, 255}, y = {255, 217, 61, 255},
    d = {166, 110, 33, 255}, g = {45, 130, 85, 255},
})

-- 兔子：双长耳内粉、白色脸颊与脚，不画成只有圆头的动物。
sprites.rabbit = Sprite({
    "...ooo....ooo...",
    "...ohho...ohho..",
    "...ohpo...opho..",
    "...ohpo...opho..",
    "...ohpo...opho..",
    "...ohho...ohho..",
    "...ohhooooohho..",
    "..ohhhhhhhhhhho.",
    "..ohhoolloohhho.",
    "..ohhoolloohhho.",
    "..ohhhhpphhhddo.",
    "...ohhhmmhhddo..",
    "..ohhhhhhhhdddo.",
    "..ohhhlhlhhdddo.",
    "..ohhhllllhhddo.",
    "..oooooooooooo..",
}, {
    o = INK, h = {245, 253, 255, 255}, l = {193, 230, 245, 255},
    d = {140, 169, 204, 255}, p = {255, 150, 180, 255}, m = {150, 80, 100, 255},
})

-- 死灵术士：紫兜帽、青绿眼睛，胸前白色骷髅徽记。
sprites.necromancer = Sprite({
    "......oooo......",
    ".....ohpppo.....",
    "....ohppppdo....",
    "...ohppppppdo...",
    "..ohppddddppdo..",
    "..oppdggdggpdo..",
    "..oppddddddpdo..",
    "..opppdggdppdo..",
    "...opppppppdo...",
    "..ooppggpppdoo..",
    ".opppwwwwppppdo.",
    "ohppwowoowpppdo.",
    "ohppwwwwwwpppdo.",
    ".opppwwoowwppdo.",
    "..opppppppppdo..",
    "...oooooooooo...",
}, {
    o = INK, h = {198, 165, 248, 255}, p = {108, 92, 231, 255},
    d = {46, 29, 79, 255}, g = {33, 189, 174, 255}, w = {224, 247, 249, 255},
})

-- 培根：严格16×6横条（x0..16、y5..11），5段切片共用这张原图。
-- 左右端描边；脂肪条跨段连续，内部接缝不画边，所有像素完全不透明。
sprites.bacon = Sprite({
    "................",
    "................",
    "................",
    "................",
    "................",
    "oooooooooooooooo",
    "ohhhrrhhhrrrhhro",
    "orrrhhrrrhhrrrro",
    "ohhhrrhhhrrrhhro",
    "odrrhhrrrhhrrrdo",
    "oooooooooooooooo",
    "................",
    "................",
    "................",
    "................",
    "................",
}, {
    o = INK, h = {255, 218, 180, 255}, r = {220, 90, 80, 255}, d = {150, 45, 55, 255},
})

-- 硬币机：金属机壳、投币口、青绿显示灯与下方出币槽。
sprites.coin_machine = Sprite({
    "..oooooooooooo..",
    "..ohhhhhhhhhdo..",
    "..ohbbbbbbbbdo..",
    "..ohbooooobbdo..",
    "..ohbohhgobbdo..",
    "..ohbooooobbdo..",
    "..ohbbbbbbbbdo..",
    "..ohbbyybbbbdo..",
    "..ohbbyybbbbdo..",
    "..ohbbbbbbbbdo..",
    "..ohbooooobbdo..",
    "..ohbodddobbdo..",
    "..ohboyyyobbdo..",
    "..oddddddddddo..",
    ".ohhhhhhhhhhhdo.",
    ".oooooooooooooo.",
}, {
    o = INK, h = {210, 222, 230, 255}, b = {141, 160, 179, 255},
    d = {58, 77, 116, 255}, g = {33, 189, 174, 255}, y = {255, 217, 61, 255},
})

-- 五角星：五个尖端之间保留透明凹口，不用圆形/完整凸包替代。
sprites.star = Sprite({
    ".......oo.......",
    ".......oho......",
    "......ohhho.....",
    "......ohhdo.....",
    ".....ohhhddo....",
    "oooooohhhdoooooo",
    "ohhhhhhhhddddddo",
    ".ohhhhhhhdddddo.",
    "..ohhhoohodddo..",
    "...ohhhhhdddo...",
    "...ohhhhhdddo...",
    "...ohhhhddddo...",
    "...ohhhoddddo...",
    "...ohho.oddddo..",
    "...oho...oddo...",
    "...oo.....ooo...",
}, {
    o = INK, h = {255, 244, 160, 255}, d = {255, 217, 61, 255},
})

-- 3×5手绘数字，完整金额压印；24px币面可放下四位数字并保留外轮廓。
---@type table<string, string[]>
local DIGITS = {
    ["0"] = {"111", "101", "101", "101", "111"},
    ["1"] = {"010", "110", "010", "010", "111"},
    ["2"] = {"111", "001", "111", "100", "111"},
    ["3"] = {"111", "001", "111", "001", "111"},
    ["4"] = {"101", "101", "111", "001", "001"},
    ["5"] = {"111", "100", "111", "001", "111"},
    ["6"] = {"111", "100", "111", "101", "111"},
    ["7"] = {"111", "001", "010", "010", "010"},
    ["8"] = {"111", "101", "111", "101", "111"},
    ["9"] = {"111", "101", "111", "001", "111"},
}
local SPANS = {8, 12, 16, 18, 20, 22, 22, 24, 24, 24, 24, 24,
    24, 24, 24, 24, 24, 22, 22, 20, 18, 16, 12, 8}
---@param amount integer
---@return BottlePixelSprite
local function NumberCoin(amount)
    local rows = {}
    for y, span in ipairs(SPANS) do
        local margin = (24 - span) // 2
        local row = {}
        for x = 0, 23 do
            local key = "."
            if x >= margin and x < 24 - margin then
                if y == 1 or y == 24 or x == margin or x == 23 - margin then key = "o"
                elseif y <= 3 or x <= margin + 2 then key = "h"
                elseif y >= 21 or x >= 21 - margin then key = "d"
                else key = "b" end
            end
            row[x + 1] = key
        end
        rows[y] = table.concat(row)
    end
    local text = tostring(amount)
    local start = (24 - (#text * 4 - 1)) // 2
    for index = 1, #text do
        local digit = assert(DIGITS[text:sub(index, index)], "金币数字图案缺失")
        for dy = 1, 5 do
            local row = assert(rows[dy + 9], "金币图案行缺失")
            local digitRow = assert(digit[dy], "金币数字行缺失")
            for dx = 1, 3 do
                if digitRow:sub(dx, dx) == "1" then
                    local column = start + (index - 1) * 4 + dx
                    row = row:sub(1, column - 1) .. "n" .. row:sub(column + 1)
                end
            end
            rows[dy + 9] = row
        end
    end
    -- 沿用既有金币色板；不同面额靠完整数字区分，不靠随机色板。
    return Sprite(rows, {
        o = INK, h = {255, 244, 160, 255}, b = {255, 217, 61, 255},
        d = {166, 110, 33, 255}, n = {113, 64, 47, 255},
    })
end
for exponent = 0, 11 do
    local amount = 1 << exponent
    sprites["coin_" .. amount] = NumberCoin(amount)
end
end
