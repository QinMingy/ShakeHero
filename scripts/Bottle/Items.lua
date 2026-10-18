-- Bottle 规则目录（98件）。纯 Lua；尺寸为米，RGBA 通道为 0..255。
-- 数据来源：docs/item.txt（98件，UTF-8 TSV）、docs/基础设定.txt、docs/概率.txt。
-- numberId 严格与源表一致；旧果汁字符串 juice 不变，数字编号从71移至87。
-- 全97件均已实装，卡池是否开放只依据源表屏蔽列，不按产物身份推断。
-- 价值默认临时，物理倍率默认永久；保留 PhysicalState 定义级体积/重量边界。
-- cooldown 包括调度防抖；只有源表明确写出冷却的效果才显示冷却提示。

---@alias RGBA number[]

---@class ItemDef
---@field id string 字符串 ID，兼容存档与物品引用
---@field numberId integer? 图鉴顺序 ID，1..97；由 Add 按源表顺序自动分配
---@field tags string[]? 分类只以标签判断，不以名字、shape 或 rarity 猜测
---@field name string
---@field base number 基础价值；结算时按当前有效价值产金币
---@field cooldown number 秒；基础设定：下限1秒（无触发效果可为0），每回合重置
---@field rarity integer
---@field unique boolean 仅已拥有时排除三选一，不限制合成数量
---@field pool boolean 是否进入三选一候选池；屏蔽或未实装为 false
---@field implemented boolean 效果是否已实装；false 时仅数据/图标占位
---@field trigger string 触发条件标识，由 Effects 解释
---@field effect string @ 为基础金币图标，[[id]] 为可点击的物品图标
---@field shape string 对应 Shapes.profiles；circle 沿用圆碰撞
---@field piercing boolean? 可穿透物品（ghost/discus），传感器接触仍用于规则
---@field radius number 显示半宽，米；已应用 sizeScale
---@field color RGBA
---@field scaleMin number? 定义级体积下限 override；缺省用 Settings.minScale，不从实例/存档读取
---@field scaleMax number? 定义级体积上限 override；缺省用 Settings.maxScale
---@field weightMin number? 定义级重量下限 override；缺省用 Settings.minWeight
---@field weightMax number? 定义级重量上限 override；缺省用 Settings.maxWeight

---@class BottleItemSettings
---@field nearSpawnRadius number 米；生成点距触发位置的最大偏移
---@field minCooldown number 秒；冷却下限，除非物品特别说明
---@field bottleLimit integer 瓶中物品上限
---@field timeLimit number 秒；时间上限
---@field defaultScale number 体积默认倍率（100%=1），直接乘半径
---@field minScale number 通用体积下限，物品定义可 override
---@field maxScale number 通用体积上限，物品定义可 override
---@field defaultWeight number 重量默认倍率（100%=1），相同尺寸下原 fixture 质量的倍率
---@field minWeight number 通用重量下限，物品定义可 override
---@field maxWeight number 通用重量上限，物品定义可 override

---@class BottleItemCatalog
---@field sizeScale number 统一尺寸倍率，只在 Add 时应用一次
---@field list ItemDef[]
---@field byId table<string, ItemDef>
---@field byNumber table<number,ItemDef>
---@field Settings BottleItemSettings
---@field rarityColors RGBA[]
---@field rarityNames string[]
---@field recipes table<string, string> 排序后的 id 用 + 连接
---@field temporaryRecipes table<string, boolean> 通用临时配方标记；当前为空
---@field draftWeights integer[][] 三选一稀有度概率（万分比），按考核次数（stage）索引
local Items = {
    sizeScale = 1.25,
    list = {},
    byId = {},
    byNumber = {},
    Settings = {
        nearSpawnRadius = .4,
        minCooldown = 1,
        bottleLimit = 100,
        timeLimit = 99,
        defaultScale = 1, minScale = .5, maxScale = 2,
        defaultWeight = 1, minWeight = .5, maxWeight = 2,
    },
    rarityColors = {
        { 96, 96, 128, 255 }, { 80, 200, 120, 255 },
        { 69, 170, 242, 255 }, { 108, 92, 231, 255 },
        { 255, 159, 67, 255 },
    },
    rarityNames = { "普通", "优秀", "稀有", "史诗", "传说" },
    recipes = {},
    temporaryRecipes = {},
    -- docs/概率.txt：第几次考核 → 普通/优秀/稀有/史诗/传说（万分比）。
    -- 第5次及以后共用最后一行；Game 按 stage 取 min(stage, #draftWeights)。
    draftWeights = {
        { 10000, 0, 0, 0, 0 },
        { 9000, 1000, 0, 0, 0 },
        { 7750, 2000, 250, 0, 0 },
        { 7250, 2500, 250, 0, 0 },
        { 6500, 3000, 375, 100, 25 },
    },
}

-- numberId 按录入顺序自动分配（源表序号连续），插入新物品无需全体重编号。
---@param def ItemDef
local function Add(def)
    local numberId = #Items.list + 1
    def.numberId = numberId
    assert(not Items.byId[def.id], "物品 ID 重复：" .. def.id)
    if def.cooldown > 0 then
        assert(def.cooldown >= Items.Settings.minCooldown,
            "冷却低于1秒下限：" .. def.id)
    end
    -- 同步放大瓶内图案、点击范围和物理尺寸，不在 View 再叠加倍率。
    def.radius = def.radius * Items.sizeScale
    Items.list[numberId] = def
    Items.byId[def.id] = def
    Items.byNumber[numberId] = def
end

-- 后半表共用默认字段；触发与形状在各条目明确指定。
---@param id string
---@param name string
---@param base number
---@param rarity integer
---@param effect string
---@param extra? table
local function Register(id, name, base, rarity, effect, extra)
    ---@type ItemDef
    local def = {
        id = id, name = name, base = base, cooldown = 1,
        rarity = rarity, unique = false, pool = true, implemented = true,
        trigger = "none", effect = effect, shape = "circle", radius = 0.27,
        color = { 160, 160, 176, 255 },
    }
    for key, value in pairs(extra or {}) do def[key] = value end
    Add(def)
end

---------------------------------------------------------------- 1..5 水果与垃圾

Add {
    id = "apple", name = "苹果", base = 2, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.26, color = { 230, 77, 86, 255 }, tags = { "水果", "植物", "食物" },
    effect = "没有特殊效果，结算时按当前价值产出金币",
}
Add {
    id = "banana", name = "香蕉", base = 6, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "banana",
    radius = 0.28, color = { 248, 211, 83, 255 }, tags = { "水果", "植物", "食物" },
    effect = "3回合后：变为[[rotten_banana]]（入瓶的回合开始计数）\n被消耗时：变为[[banana_peel]]",
}
Add {
    id = "orange", name = "橘子", base = 2, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.27, color = { 247, 148, 60, 255 }, tags = { "水果", "植物", "食物" },
    effect = "与瓶底接触时：价值+2（离开瓶底则不再持有该加成）",
}
Add {
    id = "rotten_banana", name = "腐烂的香蕉", base = 0, cooldown = 0, rarity = 1,
    unique = false, pool = false, implemented = true, trigger = "none", shape = "banana",
    radius = 0.28, color = { 122, 96, 48, 255 }, tags = { "垃圾" },
    effect = "没有特殊效果",
}
Add {
    id = "banana_peel", name = "香蕉皮", base = 1, cooldown = 0, rarity = 1,
    unique = false, pool = false, implemented = true, trigger = "none", shape = "peel",
    radius = 0.28, color = { 214, 182, 70, 255 }, tags = { "垃圾" },
    effect = "没有特殊效果",
}

---------------------------------------------------------------- 6..21 实装

Add {
    id = "seed", name = "种子", base = 1, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.18, color = { 106, 168, 79, 255 }, tags = { "农作物" },
    effect = "结算时：50%概率变为任一植物",
}
Add {
    id = "trash_can", name = "垃圾桶", base = -1, cooldown = 2, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "box",
    radius = 0.28, color = { 100, 120, 140, 255 },
    effect = "消耗相邻的垃圾和临时物品，自身价值永久+1（冷却：2s）",
}
Add {
    id = "glutton", name = "大胃王", base = 1, cooldown = 1, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.30, color = { 220, 120, 140, 255 }, tags = { "人类" },
    scaleMin = 1, scaleMax = 2, -- 特别说明：大胃王不随通用体积下限降至50%。
    effect = "消耗相邻食物，自身价值永久+1，体积（当前：100%）+10%（上限：200%，冷却：1s）\n体积达到上限时：无法消耗相邻食物\n位移50m：体积-10%（下限：100%）",
}
Add {
    id = "apple_half", name = "半个苹果", base = 1, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.22, color = { 240, 120, 130, 255 }, tags = { "水果", "植物", "食物" },
    effect = "没有特殊效果",
}
Add {
    id = "banana_half", name = "半根香蕉", base = 1, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "banana",
    radius = 0.22, color = { 250, 220, 110, 255 }, tags = { "水果", "植物", "食物" },
    effect = "没有特殊效果",
}
Add {
    id = "orange_half", name = "半块橘子", base = 1, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.22, color = { 250, 170, 90, 255 }, tags = { "水果", "植物", "食物" },
    effect = "触碰瓶底时：价值+2",
}
Add {
    id = "fruit_ninja", name = "水果忍者", base = 1, cooldown = 5, rarity = 5,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.30, color = { 60, 80, 160, 255 }, tags = { "人类" },
    effect = "将相邻的完整水果劈成两份，自身永久增加等同于该水果的价值（冷却：5秒）",
}
Add {
    id = "slipper_left", name = "忍者的左拖鞋", base = 2, cooldown = 0, rarity = 2,
    unique = true, pool = true, implemented = true, trigger = "none", shape = "slipper",
    radius = 0.24, color = { 160, 120, 80, 255 },
    effect = "与相邻忍者的[[slipper_right]]合成[[fruit_ninja]]",
}
Add {
    id = "slipper_right", name = "忍者的右拖鞋", base = 2, cooldown = 0, rarity = 2,
    unique = true, pool = true, implemented = true, trigger = "none", shape = "slipper",
    radius = 0.24, color = { 160, 120, 80, 255 },
    effect = "与相邻忍者的[[slipper_left]]合成[[fruit_ninja]]",
}
Add {
    id = "police", name = "警察", base = 4, cooldown = 1, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 60, 100, 200, 255 }, tags = { "人类" },
    effect = "不会被杀手消灭，消灭相邻的[[gambler]]、[[thief]]、[[killer]]；获得其价值×4的金币",
}
Add {
    id = "thief", name = "小偷", base = 1, cooldown = 6, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.26, color = { 80, 80, 90, 255 }, tags = { "人类" },
    effect = "永久偷取相邻人类、硬币、[[credit_card]]的1点价值（冷却：6秒）",
}
Add {
    id = "student", name = "学生", base = 2, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.26, color = { 130, 180, 230, 255 }, tags = { "人类" },
    effect = "结算5次后：成长为[[police]]、[[chef]]、[[teacher]]、[[doctor]]、[[soldier]]中的一个，有10%概率成长为[[thief]]、[[killer]]、[[gambler]]；成长后叠加当前自身价值",
}
Add {
    id = "teacher", name = "老师", base = 6, cooldown = 1, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 80, 160, 100, 255 }, tags = { "人类" },
    effect = "相邻[[student]]立刻执行成长效果，且不会成长为负面职业，然后自身价值永久+3",
}
Add {
    id = "balloon", name = "气球", base = 3, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.30, color = { 240, 100, 120, 255 },
    effect = "结算时：体积+10%，体积达到200%时：气球爆炸，所有物品价值×2",
}
Add {
    id = "killer", name = "杀手", base = 4, cooldown = 1, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 160, 40, 40, 255 }, tags = { "人类" },
    effect = "不会被杀手消灭，消灭相邻的人类，获得该人类价值×7的金币",
}
Add {
    id = "cherry", name = "樱桃", base = 3, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.22, color = { 200, 40, 60, 255 }, tags = { "水果", "植物", "食物" },
    effect = "结算时：再结算一次",
}

---------------------------------------------------------------- 22..31 实装

Add {
    id = "cherry_half", name = "半个樱桃", base = 2, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.18, color = { 220, 90, 110, 255 }, tags = { "水果", "植物", "食物" },
    effect = "结算时：再结算一次",
}
Add {
    id = "credit_card", name = "信用卡", base = 10, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "box",
    radius = 0.24, color = { 70, 130, 180, 255 },
    effect = "每次结算后：价值永久-1",
}
Add {
    id = "knife", name = "小刀", base = 4, cooldown = 5, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.24, color = { 180, 190, 200, 255 },
    effect = "将相邻的水果切成两份（冷却：5秒）；将相邻[[sheep]]的羊毛脱落",
}
Add {
    id = "fruit_farmer", name = "果农", base = 4, cooldown = 8, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 150, 110, 70, 255 }, tags = { "人类" },
    effect = "结算一次相邻水果（冷却：8秒）",
}
Add {
    id = "diner", name = "食客", base = 4, cooldown = 1, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 230, 160, 90, 255 }, tags = { "人类" },
    effect = "消耗相邻的食物，给予对应价值×2的金币，消耗5个食物后消耗自身（当前：0）\n最后一次消耗整批相邻食物，累计可超过5个",
}
Add {
    id = "tomato", name = "西红柿", base = 3, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.26, color = { 220, 60, 50, 255 }, tags = { "食物", "植物" },
    effect = "与[[egg]]合成[[tomato_egg]]",
}
Add {
    id = "tomato_egg", name = "西红柿炒蛋", base = 5, cooldown = 0, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.28, color = { 240, 140, 60, 255 }, tags = { "食物" },
    effect = "被消耗后在瓶顶重新生成，被消耗5次后消失（当前：0）",
}
Add {
    id = "chef", name = "厨师", base = 4, cooldown = 5, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 240, 240, 240, 255 }, tags = { "人类" },
    effect = "相邻食物价值×2。将相邻的完整水果切成两份，并使产物价值永久+3",
}
Add {
    id = "enoki", name = "金针菇", base = 2, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.24, color = { 235, 225, 190, 255 }, tags = { "食物" },
    effect = "被消耗后在瓶顶再次生成",
}
Add {
    id = "laurel", name = "桂冠", base = 8, cooldown = 0, rarity = 5,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.28, color = { 212, 175, 55, 255 },
    effect = "场上唯一价值最高的物品价值×1.5；若其价值至少为20，则该物品价值再×1.5。",
}

---------------------------------------------------------------- 32..47 骰子、农作物与动物

Register("die_d4", "四面骰", 1, 1,
    "回合开始时：投掷自身，价值随机变为1-4；投掷完成时：进行一次结算",
    { cooldown = 0, shape = "die_d4", tags = { "骰子" }, color = { 114, 210, 183, 255 } })
Register("die_d6", "六面骰", 1, 2,
    "回合开始时：投掷自身，价值随机变为1-6；投掷完成时：进行一次结算",
    { cooldown = 0, shape = "die_d6", tags = { "骰子" }, color = { 230, 225, 204, 255 } })
Register("gambler", "赌徒", 0, 2,
    "重投一次相邻的骰子（每回合每个骰子限一次），自身价值永久+1\n投到1：立即结算一次金币，价值变为0\n投到最大点数：立即结算一次金币",
    { trigger = "touch", tags = { "人类" }, color = { 190, 91, 121, 255 } })
Register("gambling_god", "赌神", 8, 5,
    "重投一次相邻的骰子（每回合每个骰子限一次），自身价值永久+对应点数\n投到最大点数：立即结算一次金币",
    { trigger = "touch", tags = { "人类" }, color = { 240, 193, 83, 255 } })
Register("fitness_coach", "健身教练", 3, 2, "所有体积缩小效果×2；每当有物品体积变小时，自身价值永久+1",
    { cooldown = 0, tags = { "人类" }, color = { 226, 129, 83, 255 } })
Register("fruit_tree", "果树", 3, 2, "每10秒有50%概率生成一个水果",
    { cooldown = 10, trigger = "timer", shape = "tree", tags = { "农作物", "植物" }, color = { 85, 177, 88, 255 } })
Register("farmer", "农民", 3, 2,
    "使相邻[[fruit_tree]]下一次100%生成一个水果，并有50%概率额外生成一个",
    { trigger = "touch", tags = { "人类" }, color = { 186, 151, 83, 255 } })
Register("fruit_merchant", "水果商人", 3, 3, "相邻水果价值×2",
    { cooldown = 0, tags = { "人类" }, color = { 88, 183, 132, 255 } })
Register("counter", "计数器", 0, 2, "场上每有3个元素，价值+1",
    { cooldown = 0, shape = "counter", color = { 111, 161, 178, 255 } })
Register("droplet", "水珠", 1, 1, "触发一次相邻农作物的效果，然后消除自身",
    { trigger = "touch", shape = "droplet", color = { 100, 191, 240, 255 } })
Register("cloud", "云朵", 2, 2, "每5秒：生成一个[[droplet]]；20%概率在瓶顶生成6个临时[[droplet]]",
    { cooldown = 5, trigger = "timer", shape = "cloud", color = { 213, 225, 240, 255 } })
Register("monkey", "猴子", 2, 2, "消耗相邻[[banana]]，+7金币（冷却：5秒）",
    { cooldown = 5, trigger = "touch", shape = "monkey", tags = { "动物" }, color = { 167, 116, 76, 255 } })
Register("lucky_coin", "幸运硬币", 2, 2, "每过5秒进行一次投掷：正面则自身进行一次结算",
    { cooldown = 5, trigger = "timer", color = { 246, 208, 90, 255 } })
Register("rabbit", "兔子", 2, 2, "每移动100m，价值永久+1",
    { cooldown = 0, shape = "rabbit", tags = { "动物" }, color = { 241, 217, 222, 255 } })
Register("necromancer", "死灵术士", 3, 3, "结算时：将本回合消耗的一个物品添加回牌库",
    { cooldown = 0, tags = { "人类" }, color = { 154, 109, 205, 255 } })
Register("bacon", "培根", 3, 2, "结算时：每个相邻食物为其增加1.5倍率",
    { cooldown = 0, shape = "bacon", tags = { "食物" }, color = { 219, 129, 127, 255 } })

---------------------------------------------------------------- 48 小球（实装）

Add {
    id = "ball", name = "小球", base = 1, cooldown = 3, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "wall", shape = "circle",
    radius = 0.24, color = { 122, 190, 255, 255 },
    effect = "每次碰撞瓶子时：价值+1（冷却：3秒）",
}

---------------------------------------------------------------- 49..67 灵魂系与硬币链

Register("ghost", "幽灵", 2, 1, "在瓶子内自由飘动，穿透其他物品，不受重力、碰撞和摇晃影响\n被消耗时：进行一次结算",
    { shape = "ghost", piercing = true })
Register("soul_jar", "灵魂罐", 3, 2, "碰撞瓶子时：消耗自身，随机位置生成1-3个[[ghost]]",
    { shape = "jar", trigger = "wall", color = { 137, 194, 200, 255 } })
Register("coffin", "棺材", 1, 3, "碰撞[[ghost]]时：生成一个[[ghost]]（冷却：4秒）",
    { cooldown = 4, shape = "coffin", trigger = "touch", color = { 141, 101, 88, 255 } })
Register("tombstone", "墓碑", 1, 4, "碰撞[[ghost]]时：价值永久+1（冷却：4秒）",
    { cooldown = 4, shape = "tombstone", trigger = "touch", color = { 156, 168, 180, 255 } })
Register("soul_stone", "灵魂石", 5, 3, "碰撞[[ghost]]时：消耗[[ghost]]，进行一次结算",
    { shape = "rock", trigger = "touch", color = { 129, 188, 214, 255 } })
Register("coin_1", "1元硬币", 1, 1, "与另一个[[coin_1]]合成[[coin_2]]")
Register("coin_2", "2元硬币", 2, 1, "与另一个[[coin_2]]合成[[coin_4]]")
Register("coin_4", "4元硬币", 4, 2, "与另一个[[coin_4]]合成[[coin_8]]")
Register("coin_8", "8元硬币", 8, 2, "与另一个[[coin_8]]合成[[coin_16]]")
Register("coin_16", "16元硬币", 16, 3, "与另一个[[coin_16]]合成[[coin_32]]")
Register("coin_32", "32元硬币", 32, 3, "与另一个[[coin_32]]合成[[coin_64]]")
Register("coin_64", "64元硬币", 64, 4, "与另一个[[coin_64]]合成[[coin_128]]")
Register("coin_128", "128元硬币", 128, 4, "与另一个[[coin_128]]合成[[coin_256]]")
Register("coin_256", "256元硬币", 256, 4, "与另一个[[coin_256]]合成[[coin_512]]")
Register("coin_512", "512元硬币", 512, 4, "与另一个[[coin_512]]合成[[coin_1024]]")
Register("coin_1024", "1024元硬币", 1024, 4, "与另一个[[coin_1024]]合成[[coin_2048]]")
Register("coin_2048", "2048元硬币", 2048, 5, "没有特殊效果")
Register("coin_machine", "硬币机", 3, 2,
    "与人类相邻时，随机获得等同于相邻人类数量的[[coin_1]]和[[coin_2]]（从瓶顶落下）（冷却：5秒）",
    { cooldown = 5, trigger = "touch", shape = "coin_machine", color = { 174, 156, 110, 255 } })
Register("star", "星星", 3, 1, "触碰瓶底时：闪现到瓶子顶部，价值+1（本回合）",
    { trigger = "bottom", shape = "star", color = { 250, 220, 110, 255 } })

---------------------------------------------------------------- 68..70 职业与鸡蛋

Add {
    id = "soldier", name = "士兵", base = 5, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.27, color = { 110, 130, 90, 255 }, tags = { "人类" },
    effect = "没有特殊效果",
}
Add {
    id = "doctor", name = "医生", base = 5, cooldown = 0, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.27, color = { 240, 240, 250, 255 }, tags = { "人类" },
    effect = "没有特殊效果",
}
Add {
    id = "egg", name = "鸡蛋", base = 3, cooldown = 0, rarity = 1,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.22, color = { 245, 235, 210, 255 }, tags = { "食物" },
    effect = "3回合后（当前：0）消耗自身：50%概率获得一次免费刷新（仅入瓶回合计数）",
}

---------------------------------------------------------------- 71..97 源表新增（juice 的字符串 ID 保持不变）

Register("chick", "小鸡", 3, 1, "每5秒：30%概率产生一个[[egg]]",
    { cooldown = 5, trigger = "timer", shape = "chick", tags = { "动物" }, color = { 249, 216, 90, 255 } })
Register("sheep", "小羊", 3, 1,
    "消耗[[grass]]时：额外执行一次小草的效果，且50%概率增加自身羊毛（当前：0）；剧烈摇晃时：小羊羊毛脱落，从瓶顶生成[[wool]]",
    { cooldown = 0, shape = "sheep", tags = { "动物" }, color = { 235, 230, 209, 255 } })
Register("pig", "小猪", 4, 1,
    "消耗相邻[[apple]]、[[orange]]、[[enoki]]、[[tomato_egg]]、[[banana]]和[[banana_peel]]，获得消费前价值×2的金币（冷却：2秒）；消耗物品后：自身体积（当前：100%）和重量（当前：100%）+10%；体积达到上限后：变成[[bacon]]",
    { cooldown = 2, trigger = "touch", shape = "pig", tags = { "动物" }, color = { 239, 153, 170, 255 } })
Register("calf", "小牛", 3, 1, "每次消耗物品，会冲刺一段距离，期间每触碰一个物品：+1价值",
    { cooldown = 0, shape = "calf", tags = { "动物" }, color = { 228, 220, 199, 255 } })
Register("grass", "小草", 3, 1,
    "被相邻的一个动物消耗。被动物或人类消耗时：40%不产出便便，40%[[poop]]，15%[[golden_poop]]，4%[[diamond_poop]]，1%[[rainbow_poop]]",
    { cooldown = 1, trigger = "touch", shape = "grass", radius = .23, tags = { "植物" }, color = { 112, 184, 87, 255 } })
Register("hay", "草堆", 5, 1,
    "与动物相邻时，为每个相邻动物产生一个[[grass]]，自身价值永久-1（冷却：3秒）\n自身价值小于等于0时：消耗自身\n生成的小草会自动被对应动物消耗",
    { cooldown = 3, trigger = "touch", shape = "hay", tags = { "植物" }, color = { 211, 184, 99, 255 } })
Register("poop", "普通便便", 1, 1, "被相邻植物消耗，被消耗时：消耗者价值永久+1，20%概率额外永久+1",
    { cooldown = 1, trigger = "touch", shape = "poop", tags = { "垃圾" }, color = { 143, 100, 66, 255 } })
Register("golden_poop", "黄金便便", 3, 3, "被相邻植物消耗，被消耗时：消耗者价值永久+3，20%概率额外永久+3",
    { cooldown = 1, trigger = "touch", shape = "golden_poop", tags = { "垃圾" }, color = { 236, 191, 67, 255 } })
Register("diamond_poop", "钻石便便", 8, 4, "被相邻植物消耗，被消耗时，消耗者永久获得1.2倍率",
    { cooldown = 0, shape = "diamond_poop", tags = { "垃圾" }, color = { 107, 209, 232, 255 } })
Register("rainbow_poop", "彩虹便便", 16, 5,
    "被相邻植物消耗，被消耗时：消耗者获得1.5倍率；20%概率从瓶顶重新生成[[poop]]、[[golden_poop]]、[[diamond_poop]]各一个",
    { cooldown = 0, shape = "rainbow_poop", tags = { "垃圾" }, color = { 199, 133, 223, 255 } })
Register("gecko", "壁虎", 4, 2,
    "触碰两侧或其他壁虎时，延迟0.25秒粘在该位置；每直接连接一个壁虎：壁虎额外结算一次",
    { cooldown = 1, trigger = "side", shape = "gecko", tags = { "动物" }, color = { 133, 188, 109, 255 } })
Register("cactus", "仙人掌", 4, 1, "可以扎破[[balloon]]；消耗[[droplet]]时：体积+10%；体积增大时：自身倍率增加对应数值（本回合）",
    { cooldown = 1, trigger = "touch", shape = "cactus", tags = { "植物" }, color = { 74, 166, 111, 255 } })
Register("abacus", "算盘", 5, 2, "场上有硬币合成时，价值永久+1\n单回合内每合成3次：进行一次结算",
    { cooldown = 0, shape = "abacus", color = { 175, 120, 74, 255 } })
Register("bodyguard", "保镖", 4, 1,
    "场上有人类即将被消耗时，为该人类提供护盾（本回合无法被消耗）并使保护对象进行一次结算；提供3次护盾后消失（当前：0）\n成长不算被消耗",
    { cooldown = 0, shape = "bodyguard", tags = { "人类" }, color = { 79, 104, 144, 255 } })
Register("chicken_keeper", "养鸡人", 3, 2,
    "消耗相邻[[egg]]：获得等同于鸡蛋价值的金币，50%概率产生一只[[chick]]（冷却：3s）\n每5次刷新：价值永久+1（在牌库中也生效）",
    { cooldown = 3, trigger = "touch", shape = "chicken_keeper", tags = { "人类" }, color = { 192, 153, 100, 255 } })
Register("splitter", "分裂器", 3, 3, "穿过自身的物品被分为两个价值减半的物品（向上取整，冷却：4秒）\n穿过指可穿透物品与其触碰",
    { cooldown = 4, trigger = "touch", shape = "splitter", color = { 138, 160, 199, 255 } })
Register("juice", "果汁", 3, 3, "被消耗时：消耗者价值永久增加，数值等于果汁的价值",
    { cooldown = 0, shape = "juice", tags = { "食物" }, color = { 242, 175, 71, 255 } })
Register("discus_athlete", "飞盘运动员", 4, 2,
    "向场内随机物品抛出[[discus]]，如果对方是人类，则0.2s后会再次被抛出；如果对方非人类，则飞盘闪现回到自身，3s后重新抛出\n飞盘为临时物品",
    { cooldown = 0, shape = "discus_athlete", tags = { "人类" }, color = { 104, 171, 204, 255 } })
Register("discus", "飞盘", 2, 2, "自动移动，可穿透物品；每移动5m：进行一次结算",
    { cooldown = 0, shape = "discus", radius = .23, piercing = true, color = { 119, 205, 217, 255 } })
Register("compass", "指南针", 3, 1, "每旋转360°：场内所有物品顺时针旋转90°（冷却：3秒）\n冷却期间仍累积旋转进度，反向旋转也计算进度",
    { cooldown = 3, shape = "compass", color = { 224, 185, 108, 255 } })
Register("jelly", "果冻", 4, 1, "触碰到果冻的物体被以一定力量弹开（冷却：2.5秒）",
    { cooldown = 2.5, trigger = "touch", shape = "jelly", color = { 151, 142, 216, 255 } })
Register("wool", "羊毛", 1, 1,
    "与其他羊毛合成新的羊毛，新的羊毛价值等于旧羊毛价值之和\n羊毛价值>10：变成[[sweater]]\n价值为1的羊毛下回合开始自动从瓶顶进入场内，不占用抽取数量；且获得临时属性",
    { cooldown = 1, trigger = "touch", shape = "wool", radius = .23, color = { 235, 227, 208, 255 } })
Register("sweater", "羊毛衫", 10, 1, "消耗相邻[[wool]]：自身价值永久+1",
    { cooldown = 1, trigger = "touch", shape = "sweater", color = { 212, 160, 160, 255 } })

---------------------------------------------------------------- 94..97 旋转构筑

Register("spinning_top", "陀螺", 3, 1, "累计旋转360°：价值+1（本回合）",
    { cooldown = 0, shape = "spinning_top", color = { 226, 119, 91, 255 } })
Register("windmill", "风车", 4, 2, "每累积旋转360°：随机产生一个临时[[droplet]]、临时[[wool]]或临时[[grass]]",
    { cooldown = 0, shape = "windmill", color = { 123, 193, 210, 255 } })
Register("gear", "齿轮", 4, 2,
    "标记相邻物品并进入4秒冷却，记录其累积旋转角度之和\n冷却结束后：自身和仍在场的标记物品在1秒内顺时针旋转同样角度，完成后重新标记并进入冷却",
    { cooldown = 4, shape = "gear", color = { 182, 164, 115, 255 } })
Register("roulette", "转盘", 4, 3, "每累积旋转360°：50%概率价值永久+3，50%概率价值永久-1",
    { cooldown = 0, shape = "roulette", color = { 201, 102, 119, 255 } })
Register("removal_coin", "移除币", 4, 2, "结算后：消耗自身，给予一次移除机会",
    { cooldown = 0, shape = "circle", color = { 91, 194, 166, 255 } })

-- 骰号大奖明确允许骰子达到300%；定义是可信上限，未持遗物时不会自行增长。
Items.byId.die_d4.scaleMax = 3
Items.byId.die_d6.scaleMax = 3

-- 源表第8列=1，且仅这一列决定屏蔽；腐烂香蕉屏蔽，桂冠仍开放。
for _, id in ipairs({
    "rotten_banana", "banana_peel", "apple_half", "banana_half", "orange_half",
    "fruit_ninja", "cherry_half", "tomato_egg", "coin_4", "coin_8", "coin_16", "coin_32",
    "coin_64", "coin_128", "coin_256", "coin_512", "coin_1024", "coin_2048",
    "poop", "golden_poop", "diamond_poop", "rainbow_poop", "juice", "discus_athlete", "discus", "wool", "sweater",
}) do
    assert(Items.byId[id], "屏蔽清单包含未知物品：" .. id)
    Items.byId[id].pool = false
end

-- 合成配方（键为排序后的 id 用 + 连接，见 Items.RecipeKey）；由 Effects.Merge 消费。
Items.recipes["slipper_left+slipper_right"] = "fruit_ninja"
Items.recipes["egg+tomato"] = "tomato_egg"
-- 配方登记完整链；实际是否允许64元以上合成由 Effects.Merge 查询遗物。
for power = 0, 10 do
    local value = 2 ^ power
    local id = "coin_" .. string.format("%.0f", value)
    Items.byId[id].cooldown = 0
    Items.recipes[id .. "+" .. id] = "coin_" .. string.format("%.0f", value * 2)
end
Items.byId.coin_2048.cooldown = 0

--- 源表明确声明冷却的物品白名单；周期计时和内部防抖绝不显示冷却环。
--- compass 使用专用旋转调度、trigger=none，仍须显示明确的3秒冷却。
local cooldownHints = {
    trash_can = true, glutton = true, fruit_ninja = true, thief = true,
    knife = true, fruit_farmer = true, monkey = true, ball = true,
    coffin = true, tombstone = true, coin_machine = true,
    pig = true, hay = true, chicken_keeper = true, splitter = true, compass = true, jelly = true, gear = true,
}
---@param id string
---@return boolean
function Items.HasCooldown(id)
    local def = Items.byId[id]
    return def ~= nil and def.cooldown > 0 and cooldownHints[id] == true
end

---@param id string
---@return boolean
function Items.IsPoop(id)
    return id == "poop" or id == "golden_poop" or id == "diamond_poop" or id == "rainbow_poop"
end

--- 按对局查询穿透能力；遗物绝不写回共享定义，以免污染别的新局。
---@param id string
---@param game BottleGame?
---@return boolean
function Items.IsPiercing(id, game)
    local def = Items.byId[id]
    if not def then return false end
    if def.piercing then return true end
    return Items.IsPoop(id) and game ~= nil and game.relics ~= nil and game.relics.ghost_poop == true
end

---@param id string|number
---@param tag string
---@return boolean
function Items.HasTag(id, tag)
    ---@type ItemDef?
    local def = nil
    if type(id) == "number" then
        def = Items.byNumber[id]
    else
        def = Items.byId[id]
    end
    if not def then return false end
    for _, value in ipairs(def.tags or {}) do
        if value == tag then return true end
    end
    return false
end

-- UI 使用同一入口显示唯一及任意分类标签，不把 tag 写死在视图里。
---@param def ItemDef
---@return string
function Items.TagsText(def)
    local labels = {}
    if def.unique then labels[#labels + 1] = "唯一" end
    for _, tag in ipairs(def.tags or {}) do
        if tag ~= "唯一" then labels[#labels + 1] = tag end
    end
    return table.concat(labels, " · ")
end

---@param aId string
---@param bId string
---@return string
function Items.RecipeKey(aId, bId)
    if aId < bId then return aId .. "+" .. bId end
    return bId .. "+" .. aId
end

---@param aId string
---@param bId string
---@return string?
function Items.Recipe(aId, bId)
    return Items.recipes[Items.RecipeKey(aId, bId)]
end

--- 三选一稀有度概率（万分比），按考核次数取表；第5次及以后沿用最后一行。
---@param stage integer
---@return integer[]
function Items.DraftWeights(stage)
    local index = math.max(1, math.min(stage, #Items.draftWeights))
    return assert(Items.draftWeights[index], "考核概率表缺行")
end

return Items
