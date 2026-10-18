-- Bottle 规则数据（V0.4，70件表）。纯 Lua；尺寸为米，RGBA 通道为 0..255。
-- 数据来源：docs/item.txt（70件，UTF-8 TSV）与 docs/基础设定.txt、docs/概率.txt。
-- 新表变化（相对66件旧表）：插入半个樱桃(#22)，末尾新增士兵/医生/鸡蛋(#68-70)，
-- 种子获得“结算时50%变任一植物”效果，水珠描述修正为单次触发，西红柿炒蛋材料鸡蛋已入表。
-- 本表70件均已实装；卡池屏蔽只遵守源表，不因合成产物而误标未实装。
-- 硬币默认最高合成64元，获得合成2048遗物后开放后续链（说明由 ItemText 追加）。
-- 卡池屏蔽（源表第8列=1）：pool=false，只能通过转化/切割/合成等效果产生。
-- 新结算模型：摇晃阶段物品只改变价值/状态，结算阶段统一按当前价值产金币。
-- 价值默认临时（回合末清零回基础值）；“永久+N”才跨回合保留（见基础设定.txt）。

---@alias RGBA number[]

---@class ItemDef
---@field id string 字符串 ID，兼容存档与物品引用
---@field numberId integer? 图鉴顺序 ID，1..70；由 Add 按录入顺序自动分配，调用处省略
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
---@field radius number 显示半宽，米；已应用 sizeScale
---@field color RGBA

---@class BottleItemSettings
---@field nearSpawnRadius number 米；生成点距触发位置的最大偏移
---@field minCooldown number 秒；冷却下限，除非物品特别说明
---@field bottleLimit integer 瓶中物品上限
---@field timeLimit number 秒；时间上限

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
    id = "banana", name = "香蕉", base = 2, cooldown = 0, rarity = 1,
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
    id = "glutton", name = "大胃王", base = 1, cooldown = 1, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.30, color = { 220, 120, 140, 255 }, tags = { "人类" },
    effect = "消耗相邻食物，自身价值永久+1，体积（当前：x）+10%（上限：200%，冷却：1s）\n体积达到上限时：无法消耗相邻食物\n位移10m：体积-10%（下限：100%）",
}
Add {
    id = "apple_half", name = "半根苹果", base = 1, cooldown = 0, rarity = 1,
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
    effect = "相邻[[student]]立刻执行成长效果，且不会成长为负面职业",
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
    effect = "将相邻的水果切成两份（冷却：5秒）",
}
Add {
    id = "fruit_farmer", name = "果农", base = 4, cooldown = 8, rarity = 3,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 150, 110, 70, 255 }, tags = { "人类" },
    effect = "结算一次相邻水果（冷却：8秒）",
}
Add {
    id = "diner", name = "食客", base = 4, cooldown = 1, rarity = 2,
    unique = false, pool = true, implemented = true, trigger = "touch", shape = "circle",
    radius = 0.28, color = { 230, 160, 90, 255 }, tags = { "人类" },
    effect = "消耗相邻的食物，给予对应价值×2的金币，消耗5个食物后消耗自身（当前：0）",
}
Add {
    id = "tomato", name = "西红柿", base = 3, cooldown = 0, rarity = 4,
    unique = false, pool = true, implemented = true, trigger = "none", shape = "circle",
    radius = 0.26, color = { 220, 60, 50, 255 }, tags = { "食物" },
    effect = "与[[egg]]合成[[tomato_egg]]",
}
Add {
    id = "tomato_egg", name = "西红柿炒蛋", base = 5, cooldown = 0, rarity = 1,
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
Register("fitness_coach", "健身教练", 3, 2, "所有体积缩小效果×2",
    { cooldown = 0, tags = { "人类" }, color = { 226, 129, 83, 255 } })
Register("fruit_tree", "果树", 3, 2, "每10秒有50%概率生成一个水果",
    { cooldown = 10, trigger = "timer", shape = "tree", tags = { "农作物" }, color = { 85, 177, 88, 255 } })
Register("farmer", "农民", 3, 2,
    "使相邻[[fruit_tree]]下一次100%生成一个水果，并有50%概率额外生成一个",
    { trigger = "touch", tags = { "人类" }, color = { 186, 151, 83, 255 } })
Register("fruit_merchant", "水果商人", 3, 3, "相邻水果价值×2",
    { cooldown = 0, tags = { "人类" }, color = { 88, 183, 132, 255 } })
Register("counter", "计数器", 0, 2, "场上每有3个元素，价值+1",
    { cooldown = 0, shape = "counter", color = { 111, 161, 178, 255 } })
Register("droplet", "水珠", 1, 1, "触发一次相邻农作物的效果，然后消除自身",
    { trigger = "touch", shape = "droplet", color = { 100, 191, 240, 255 } })
Register("cloud", "云朵", 2, 2, "每5秒生成一个[[droplet]]",
    { cooldown = 5, trigger = "timer", shape = "cloud", color = { 213, 225, 240, 255 } })
Register("monkey", "猴子", 2, 2, "消耗相邻[[banana]]，+7金币（冷却：5秒）",
    { cooldown = 5, trigger = "touch", shape = "monkey", tags = { "动物" }, color = { 167, 116, 76, 255 } })
Register("lucky_coin", "幸运硬币", 2, 2, "每过5秒进行一次投掷：正面则自身进行一次结算",
    { cooldown = 5, trigger = "timer", color = { 246, 208, 90, 255 } })
Register("rabbit", "兔子", 2, 2, "每移动10m，价值永久+1",
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

Register("ghost", "幽灵", 2, 1, "在瓶子内自由飘动\n被消耗时：进行一次结算（不受重力影响）",
    { shape = "ghost" })
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
Register("star", "星星", 3, 1, "触碰瓶底时：闪现到瓶子顶部",
    { trigger = "bottom", shape = "star", color = { 250, 220, 110, 255 } })

---------------------------------------------------------------- 68..70 实装（无特殊效果）

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
    effect = "没有特殊效果",
}

-- 榨汁机专用产物：纯食物、无特殊效果、基础0；有效价值由实例永久加值承载。
Register("juice", "果汁", 0, 1, "没有特殊效果；生成时永久获得榨汁机本次累计价值",
    { cooldown = 0, pool = false, tags = { "食物" }, color = { 242, 175, 71, 255 } })

-- 卡池屏蔽（源表第8列=1）：只能由效果产生，不进三选一。
-- 腐烂的香蕉/香蕉皮已在 Add 中 pool=false；以下为其他已实装屏蔽项。
for _, id in ipairs({
    "apple_half", "banana_half", "orange_half", "fruit_ninja", "cherry_half",
    "laurel", "coin_4", "coin_8", "coin_16", "coin_32", "coin_64", "coin_128",
    "coin_256", "coin_512", "coin_1024", "coin_2048",
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
