-- 遗物数据与机制（docs/relic.txt，37 件）。纯 Lua，不依赖引擎。
-- 遗物是永久被动加成，通过“考核后的遗物三选一”获得，不进瓶、不参与物理。
-- 效果多为声明式标记：Game/Effects 在相应时机查询 Relics.Has(game, id)。
-- 全部37件已接线；复杂行为由 RelicEffects / RelicExpansion 与规则/物理查询协作。
-- 骰子、赌徒、云朵、兔子、灵魂石和硬币机的关联钩子已随物品实装接通。
-- 数据来源 relic.txt 的“备注”列保留语义；本轮明确细则在各 note 中注明。

---@class RelicDef
---@field id string
---@field numberId integer 1..37，与 relic.txt 序号一致
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
    effect = "[[gambler]]完成本次投掷效果后，价值达到50时有25%概率变为[[gambling_god]]；每个赌徒失败后不再尝试，价值归0刷新。转化后永久叠加转化前价值",
    note = "旧投掷的加值、特殊结算、投1归零先完成；成功保留UID和本回合骰子重投额度并结束原赌徒批次。尝试标记跨回合/存档；外部价值变化完成后也可触发；负值不刷新",
}
Add {
    numberId = 2, id = "one_more_round", name = "再来一把", rarity = 1, pool = true, implemented = true,
    effect = "[[gambler]]每回合每个骰子可连续投掷两次",
    note = "已接线：ExtraEffects 赌徒重投上限2次/骰",
}
Add {
    numberId = 3, id = "small_savings", name = "积少成多", rarity = 1, pool = true, implemented = true,
    effect = "每次添加物品，立即获得1金币（不增加物品价值）",
}
Add {
    numberId = 4, id = "coin_rain", name = "硬币雨", rarity = 2, pool = true, implemented = true,
    effect = "之后的[[cloud]]产生[[coin_1]]而不是[[droplet]]；立即获得1个[[cloud]]",
    note = "已接线：ExtraEffects 云朵生成 coin_1 替换 droplet",
}
Add {
    numberId = 5, id = "in_groups", name = "成群结队", rarity = 2, pool = true, implemented = true,
    effect = "[[rabbit]]现在会同时为场上其他兔子永久增加价值；立即获得1个[[rabbit]]",
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
    effect = "骰子不再会投到点数1；立即获得1个[[die_d6]]",
    note = "已接线：ExtraEffects 骰子点数下限2",
}
Add {
    numberId = 10, id = "upgrade_coin_machine", name = "升级硬币机", rarity = 2, pool = true, implemented = true,
    effect = "[[coin_machine]]现在有机会产生[[coin_4]]；立即获得1个[[coin_machine]]",
    note = "已接线：ExtraEffects 硬币机产出池加入 coin_4",
}
Add {
    numberId = 11, id = "gm_fruit", name = "转基因水果", rarity = 3, pool = true, implemented = true,
    effect = "水果被消耗时，有10%几率在瓶子顶部随机生成一个新的完整水果",
    note = "V0.4 已接线：Game:_Destroy 钩子，完整水果=苹果/香蕉/橘子/樱桃",
}
Add {
    numberId = 12, id = "tomato_tycoon", name = "西红柿首富", rarity = 2, pool = true, implemented = true,
    effect = "[[tomato]]价值×2；立即获得1个[[tomato]]",
}
Add {
    numberId = 13, id = "lucky_charm", name = "幸运符", rarity = 2, pool = true, implemented = true,
    effect = "所有物品描述中与价值有关的“-”号全部变为“+”号",
    note = "垃圾桶基础-1变+1、信用卡每结算永久+1、小偷被偷方-1变+1、草堆每次触发永久-1变+1；不反转历史负加值，不改变体积、冷却或计数",
}
Add {
    numberId = 14, id = "scramble_recipe", name = "炒蛋秘籍", rarity = 2, pool = true, implemented = true,
    effect = "[[tomato_egg]]可被消耗总次数从5次提升为10次；立即获得1个[[egg]]和1个[[tomato]]",
    note = "总计10次，不是额外10次；保留原有累计消耗次数，跨回合与存档",
}
Add {
    numberId = 15, id = "see_you_tomorrow", name = "seeYouTomorrow", rarity = 2, pool = true, implemented = true,
    effect = "[[enoki]]每次被消耗，自身价值永久+1；立即获得1个[[enoki]]",
}
Add {
    numberId = 16, id = "teach_all", name = "有教无类", rarity = 2, pool = true, implemented = true,
    effect = "[[teacher]]不会被杀手杀害，将相邻的杀手、赌徒、小偷转变为[[student]]，学生叠加其价值；立即获得1个[[teacher]]",
    note = "V0.4 已接线：Effects.Teacher 转化 + Killer 豁免老师",
}
Add {
    numberId = 17, id = "jungle_hunt", name = "江湖追杀", rarity = 3, pool = true, implemented = true,
    effect = "标记拥有牌库中一个可被[[killer]]击杀的人类。杀手击杀当前目标后，自身永久倍率×1.5，并刷新目标；立即获得1个[[killer]]",
    note = "只从deck/bottle标记既有人类UID，刷新目标不生成新人；首次获得另赠杀手入牌库；排除警察/杀手，有教无类时排除老师；目标跨回合/存档稳定，失效才按UID排序随机补选，无候选为0。警察或其他消耗不奖励",
}
Add {
    numberId = 18, id = "juicer", name = "榨汁机", rarity = 2, pool = true, implemented = true,
    effect = "回合结束时消耗瓶内所有半份水果，将当前有效价值累积到榨汁机；点击生成等值[[juice]]永久加入牌库，并清空累计值",
    note = "仅四种_half；统一结算、死灵返还之后再榨取。果汁采用新源表#87基础3、品质3、仅食物tag及被消耗加值效果；生成时当前价值等于本次累计值，不入瓶；点击需弹窗确认，running/settle/reveal不可用，失败不清值",
}
Add {
    numberId = 19, id = "last_second", name = "最后一秒", rarity = 1, pool = true, implemented = true,
    effect = "摇晃持续时间+1秒",
}
Add {
    numberId = 20, id = "cherry_plus", name = "车厘子", rarity = 1, pool = true, implemented = true,
    effect = "[[cherry]]现在改为结算多2次；立即获得1个[[cherry]]",
}
Add {
    numberId = 21, id = "knife_skill", name = "精进刀法", rarity = 2, pool = true, implemented = true,
    effect = "完整水果被切时有50%概率额外产生一个对应的半份水果",
    note = "V0.4 已接线：Effects.CutFruit 50%额外半份",
}
Add {
    numberId = 22, id = "wash_hands", name = "金盘洗手", rarity = 2, pool = true, implemented = true,
    effect = "[[thief]]不再偷取价值，而是和对方共同永久+1价值，且不再是负面职业（不会被[[police]]、[[teacher]]影响）；立即获得1个[[thief]]",
    note = "共同加值保留原合法目标分类；警察不消灭该小偷，有教无类老师不将其转为学生；不改变杀手的一般人类目标规则",
}
Add {
    numberId = 23, id = "chef_hat", name = "厨师帽", rarity = 2, pool = true, implemented = true,
    effect = "[[chef]]现在可以消耗相邻的[[knife]]，每消耗一把小刀，为本次切割产物额外增加1点永久价值（冷却：1秒）；立即获得1个[[chef]]",
    note = "持帽厨师1秒调度，无帽5秒；本次先消耗相邻小刀，再令本次全部切割产物永久+1/把；无切割不累计给下次，不永久累计到厨师自身",
}
Add {
    numberId = 24, id = "credit_line", name = "贷款额度", rarity = 2, pool = true, implemented = true,
    effect = "后续获取的[[credit_card]]，初始价值为25；立即获得1张[[credit_card]]",
}

Add {
    numberId = 25, id = "teacher_team", name = "名师团队", rarity = 2, pool = true, implemented = true,
    effect = "[[teacher]]与老师会合成老师，新的老师获得他们的价值和倍率",
    note = "双方加法项相加写入新基础，永久倍率及事件倍率分别乘积；接触光环重新计算，不固化重复乘算，不改变普通催熟收益",
}
Add {
    numberId = 26, id = "accelerator", name = "加速器", rarity = 2, pool = true, implemented = true,
    effect = "物品移动速度增加20%",
    note = "瓶内移动速度×1.2，不缩短冷却/回合时间，不每帧指数叠加；牌库独立展示沙盒不应用瓶内加速",
}
Add {
    numberId = 27, id = "ghost_poop", name = "幽灵便便", rarity = 2, pool = true, implemented = true,
    effect = "现在便便在瓶子内自由飘动，可穿透物品",
    note = "适用于普通/黄金/钻石/彩虹四种便便；按对局查询，不修改共享物品定义，不污染新局；牌库仍普通下落展示",
}
Add {
    numberId = 28, id = "premium_grass", name = "优质小草", rarity = 1, pool = true, implemented = true,
    effect = "现在消耗[[grass]]的动物必定产出便便",
    note = "动物必产按普通40/60、黄金15/60、钻石4/60、彩虹1/60；人类消费保原概率，羊的额外草判定同样必产且积毛仍独立50%",
}
Add {
    numberId = 29, id = "food_comfort", name = "吃了不烧心", rarity = 2, pool = true, implemented = true,
    effect = "所有食物当前价值+2",
    note = "持有期间对食物基础项加2，之后再算倍率；不是永久加值，不写permBonus，不改变物品tag",
}
Add {
    numberId = 30, id = "bacon_network", name = "培根是对的", rarity = 2, pool = true, implemented = true,
    effect = "所有和[[bacon]]相邻的物品视为相邻；立即获得1个[[bacon]]",
    note = "共享同一块培根的邻居建立效果邻接关系，不扩大物理碰撞或拾取轮廓",
}
Add {
    numberId = 31, id = "ghost_sport", name = "幽灵运动", rarity = 1, pool = true, implemented = true,
    effect = "[[ghost]]每移动30m，+1金币；立即获得1个[[ghost]]",
    note = "只记真实位移，不把闪现算路程；不直接增加幽灵价值",
}
Add {
    numberId = 32, id = "spin_reward", name = "转圈圈", rarity = 2, pool = true, implemented = true,
    effect = "物品每累计自然旋转三圈，独立30%概率+1金币",
    note = "真实自然绝对角路程含反转，指南针和齿轮强制转角不计；每次判定无论成败都消耗三圈并保留余角，进度回合末清零",
}
Add {
    numberId = 33, id = "wool_market", name = "羊毛集市", rarity = 1, pool = true, implemented = true,
    effect = "[[sheep]]现在产出的[[wool]]会自动兑换成[[coin_1]]",
    note = "只替换小羊脱毛的新产出，不兑换已有羊毛；每份产出对应一枚1元硬币",
}

Add {
    numberId = 34, id = "wool_recycle", name = "羊毛回收", rarity = 1, pool = true, implemented = true,
    effect = "[[wool]]合成或被消耗时，每份材料独立有50%概率在瓶顶生成1份临时羊毛",
    note = "成功消费才判定；合成双方各判一次，临时羊毛再次合成或被耗同样可触发；临时产物满瓶FIFO，回合末删除，不受羊毛集市替换",
}
Add {
    numberId = 35, id = "dice_jackpot", name = "骰号大奖", rarity = 2, pool = true, implemented = true,
    effect = "骰子每投出6点，体积+50%（最高300%）；场上所有骰子、硬币、[[gambler]]、[[gambling_god]]立刻获得等于该骰子体积增量的本回合倍率加数，重复可叠加。非6点时该骰子体积恢复100%",
    note = "按增长后scale-1累加jackpotBonus，最终独立倍率为1+累计加数，再乘其他来源；封顶再6仍奖励，非6不撤旧奖励。尺寸默认永久、倍率回合末清；硬币只指coin_N，不含幸运硬币",
}
Add {
    numberId = 36, id = "calf_rush", name = "牛来！", rarity = 2, pool = true, implemented = true,
    effect = "[[calf]]每次成功消耗启动冲刺时，价值临时+1、体积+20%；体积达到200%时价值永久+2，体积恢复100%",
    note = "每次移动明确为每次冲刺启动，不按帧/米/碰撞次数；叠加原有每目标每冲刺临时+1，尺寸默认永久，新增+1回合末清",
}
Add {
    numberId = 37, id = "lucky_roulette", name = "幸运转盘", rarity = 2, pool = true, implemented = true,
    effect = "[[roulette]]每累计旋转360°时，5%概率价值临时+77；其余95%按原比例永久+3或永久-1（各47.5%）；立即获得1个[[roulette]]",
    note = "大奖与基础正负互斥；基础原50%/50%，先判1/20大奖，未中再等概率基础正负；幸运符只将基础永久-1改永久+1，不改变概率或临时大奖",
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
