-- 遗物数据与机制（docs/relic.txt，24 件）。纯 Lua，不依赖引擎。
-- 遗物是永久被动加成，通过“考核后的遗物三选一”获得，不进瓶、不参与物理。
-- 效果多为声明式标记：Game/Effects 在相应时机查询 Relics.Has(game, id)。
-- 全部24件已接线，五件复杂遗物的行为集中在 RelicEffects / RelicState。
-- 骰子、赌徒、云朵、兔子、灵魂石和硬币机的关联钩子已随物品实装接通。
-- 数据来源 relic.txt 的“备注”列保留语义；本轮明确细则在各 note 中注明。

---@class RelicDef
---@field id string
---@field numberId integer 1..24，与 relic.txt 序号一致
---@field name string
---@field rarity integer 1..5（白/绿/蓝/紫/黄）
---@field effect string UI 说明；@ 为金币图标，[[id]] 为物品引用
---@field note string? 源表备注
---@field pool boolean 是否进入遗物三选一卡池
---@field implemented boolean 效果是否已接线（false=仅数据/图标占位）

---@class RelicCatalog
---@field list RelicDef[]
---@field byId table<string, RelicDef>
---@field byNumber table<integer, RelicDef>
local Relics = { list = {}, byId = {}, byNumber = {} }

---@param def RelicDef
local function Add(def)
    assert(def.numberId == #Relics.list + 1, "遗物顺序 ID 不连续：" .. def.id)
    assert(not Relics.byId[def.id], "遗物 ID 重复：" .. def.id)
    Relics.list[#Relics.list + 1] = def
    Relics.byId[def.id] = def
    Relics.byNumber[def.numberId] = def
end

Add {
    numberId = 1, id = "gambling_token", name = "赌神令牌", rarity = 1, pool = true, implemented = true,
    effect = "[[gambler]]完成本次投掷效果后，价值达到50时有50%概率变为[[gambling_god]]；每个赌徒失败后不再尝试，价值归0刷新。转化后永久叠加转化前价值",
    note = "旧投掷的加值、特殊结算、投1归零先完成；成功保留UID和本回合骰子重投额度并结束原赌徒批次。尝试标记跨回合/存档；外部价值变化完成后也可触发；负值不刷新",
}
Add {
    numberId = 2, id = "one_more_round", name = "再来一把", rarity = 1, pool = true, implemented = true,
    effect = "[[gambler]]每回合每个骰子可连续投掷两次",
    note = "已接线：ExtraEffects 赌徒重投上限2次/骰",
}
Add {
    numberId = 3, id = "small_savings", name = "积少成多", rarity = 1, pool = true, implemented = true,
    effect = "每次添加物品，+1 @",
}
Add {
    numberId = 4, id = "coin_rain", name = "硬币雨", rarity = 2, pool = true, implemented = true,
    effect = "之后的[[cloud]]产生[[coin_1]]而不是[[droplet]]",
    note = "已接线：ExtraEffects 云朵生成 coin_1 替换 droplet",
}
Add {
    numberId = 5, id = "in_groups", name = "成群结队", rarity = 2, pool = true, implemented = true,
    effect = "[[rabbit]]现在会同时为场上其他兔子永久增加价值",
    note = "已接线：ExtraEffects 兔子位移为全部兔子加值",
}
Add {
    numberId = 6, id = "soul_resonance", name = "灵魂共振", rarity = 3, pool = true, implemented = true,
    effect = "[[soul_stone]]的价值等于场上价值最高的[[tombstone]]相同",
    note = "如果有倍率，先复制最值再乘算；已接线：Game:_Value 查询",
}
Add {
    numberId = 7, id = "merge_2048", name = "合成2048", rarity = 3, pool = true, implemented = true,
    effect = "现在硬币最高可合成到[[coin_2048]]",
    note = "已接线：Items.recipes 硬币合成链开放至2048",
}
Add {
    numberId = 8, id = "thief_handbook", name = "小偷手册", rarity = 2, pool = true, implemented = true,
    effect = "[[thief]]冷却-1秒",
    note = "V0.4 已接线：Game:CooldownOf 查询生效",
}
Add {
    numberId = 9, id = "cheat_dice", name = "作弊骰子", rarity = 1, pool = true, implemented = true,
    effect = "骰子不再会投到点数1",
    note = "已接线：ExtraEffects 骰子点数下限2",
}
Add {
    numberId = 10, id = "upgrade_coin_machine", name = "升级硬币机", rarity = 2, pool = true, implemented = true,
    effect = "[[coin_machine]]现在有机会产生[[coin_4]]",
    note = "已接线：ExtraEffects 硬币机产出池加入 coin_4",
}
Add {
    numberId = 11, id = "gm_fruit", name = "转基因水果", rarity = 3, pool = true, implemented = true,
    effect = "水果被消耗时，有10%几率在瓶子顶部随机生成一个新的完整水果",
    note = "V0.4 已接线：Game:_Destroy 钩子，完整水果=苹果/香蕉/橘子/樱桃",
}
Add {
    numberId = 12, id = "tomato_tycoon", name = "西红柿首富", rarity = 2, pool = true, implemented = true,
    effect = "[[tomato]]价值×2",
}
Add {
    numberId = 13, id = "lucky_charm", name = "幸运符", rarity = 2, pool = true, implemented = true,
    effect = "所有物品描述中与价值有关的“-”号全部变为“+”号",
    note = "垃圾桶基础-1变+1、信用卡每结算永久+1、小偷被偷方-1变+1；不绝对化历史负加值，不改变体积、冷却或计数",
}
Add {
    numberId = 14, id = "scramble_recipe", name = "炒蛋秘籍", rarity = 2, pool = true, implemented = true,
    effect = "[[tomato_egg]]可被消耗总次数从5次提升为10次",
    note = "总计10次，不是额外10次；保留原有累计消耗次数，跨回合与存档",
}
Add {
    numberId = 15, id = "see_you_tomorrow", name = "seeYouTomorrow", rarity = 2, pool = true, implemented = true,
    effect = "[[enoki]]每次被消耗，自身价值永久+1",
}
Add {
    numberId = 16, id = "teach_all", name = "有教无类", rarity = 2, pool = true, implemented = true,
    effect = "[[teacher]]不会被杀手杀害，将相邻的杀手、赌徒、小偷转变为[[student]]，学生叠加其价值",
    note = "V0.4 已接线：Effects.Teacher 转化 + Killer 豁免老师",
}
Add {
    numberId = 17, id = "jungle_hunt", name = "江湖追杀", rarity = 3, pool = true, implemented = true,
    effect = "标记拥有牌库中一个可被[[killer]]击杀的人类。杀手击杀当前目标后，自身永久倍率×1.5，并刷新目标",
    note = "只从deck/bottle标记既有人类UID，不生成新人；排除警察/杀手，有教无类时排除老师；目标跨回合/存档稳定，失效才按UID排序随机补选，无候选为0。警察或其他消耗不奖励",
}
Add {
    numberId = 18, id = "juicer", name = "榨汁机", rarity = 2, pool = true, implemented = true,
    effect = "回合结束时消耗瓶内所有半份水果，将当前有效价值累积到榨汁机；点击生成等值[[juice]]永久加入牌库，并清空累计值",
    note = "仅四种_half；默认时序为统一结算、死灵返还之后再榨取。果汁基础0、仅食物tag、无特殊效果、不入卡池，permBonus=本次累计值、不入瓶；点击需弹窗确认，running/settle/reveal不可用，失败不清值",
}
Add {
    numberId = 19, id = "last_second", name = "最后一秒", rarity = 1, pool = true, implemented = true,
    effect = "摇晃持续时间+1秒",
}
Add {
    numberId = 20, id = "cherry_plus", name = "车厘子", rarity = 1, pool = true, implemented = true,
    effect = "[[cherry]]现在改为结算多2次",
}
Add {
    numberId = 21, id = "knife_skill", name = "精进刀法", rarity = 2, pool = true, implemented = true,
    effect = "完整水果被切时有50%概率额外产生一个对应的半份水果",
    note = "V0.4 已接线：Effects.CutFruit 50%额外半份",
}
Add {
    numberId = 22, id = "wash_hands", name = "金盘洗手", rarity = 2, pool = true, implemented = true,
    effect = "[[thief]]不再偷取价值，而是和对方共同增加价值，且不再是负面职业",
    note = "V0.4 已接线：Effects.Thief 分支；负面职业部分（警察消灭名单）待警察效果确认语义",
}
Add {
    numberId = 23, id = "chef_hat", name = "厨师帽", rarity = 2, pool = true, implemented = true,
    effect = "[[chef]]现在可以消耗相邻的[[knife]]，为产物增加的价值永久+1（当前：+0；冷却：1秒）",
    note = "V0.4 已接线：Effects.Chef 先消耗相邻小刀再切割，产物额外+1/把",
}
Add {
    numberId = 24, id = "credit_line", name = "贷款额度", rarity = 2, pool = true, implemented = true,
    effect = "后续获取的[[credit_card]]，初始价值为25",
}

--- 查询对局是否持有某遗物。
---@param game BottleGame?
---@param id string
---@return boolean
function Relics.Has(game, id)
    if not game or not game.relics then return false end
    return game.relics[id] == true
end

--- 统计已实装且未拥有的遗物，供三选一卡池使用。
---@param game BottleGame
---@return RelicDef[]
function Relics.Available(game)
    ---@type RelicDef[]
    local result = {}
    for _, def in ipairs(Relics.list) do
        if def.pool and def.implemented and not Relics.Has(game, def.id) then result[#result + 1] = def end
    end
    return result
end

return Relics
