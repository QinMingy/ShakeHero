-- 物品说明的唯一动态入口：保留源表正文，仅追加已解锁规则及实例当前值。
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Text = {}

---@param game BottleGame
---@param id string
---@param item ItemInstance?
---@return string
function Text.Effect(game, id, item)
    local def = assert(Items.byId[id], "未知物品说明：" .. id)
    local text = def.effect
    if id == "tomato_egg" and Relics.Has(game, "scramble_recipe") then
        text = text:gsub("被消耗5次", "被消耗10次")
    end
    local washed = Relics.Has(game, "wash_hands")
    if id == "thief" and washed then
        text = "与相邻人类、硬币、[[credit_card]]共同增加价值：对方和自身价值各永久+1（冷却：6秒）\n不再是负面职业，不会被[[police]]消灭，也不会被[[teacher]]转变为学生"
    elseif id == "police" and washed then
        text = "不会被杀手消灭，消灭相邻的[[gambler]]、[[killer]]；获得其价值×4的金币\n金盘洗手：不再消灭[[thief]]"
    end
    if id == "teacher" and Relics.Has(game, "teach_all") then
        text = text .. "\n有教无类：不会被杀手杀害；将相邻[[killer]]、[[gambler]]"
            .. (washed and "" or "、[[thief]]") .. "转变为[[student]]，学生叠加其价值"
    end
    if Relics.Has(game, "lucky_charm") then
        if id == "credit_card" or id == "hay" then
            text = text:gsub("价值永久%-1", "价值永久+1")
        elseif id == "thief" and not washed then
            text = "相邻人类、硬币、[[credit_card]]价值永久+1，自身价值永久+1（冷却：6秒）\n幸运符只改变价值减量，不改变负面职业身份"
        elseif id == "trash_can" then
            text = text .. "\n幸运符：基础价值由-1变为+1。"
        end
    end
    if id == "thief" and Relics.Has(game, "thief_handbook") then
        text = text:gsub("冷却：6秒", "冷却：5秒")
    elseif id == "chef" and Relics.Has(game, "chef_hat") then
        text = text .. "\n厨师帽：消耗相邻[[knife]]，每把仅为本次切割的产物额外永久+1（冷却：1秒），不累计厨师自身加成"
    end
    -- 候选／定义没有实例时显示初始值；实例详情始终读取这一件的真实状态。
    if id == "glutton" then
        local scale = item and item.scale or Items.Settings.defaultScale
        text = text:gsub("当前：[%d%.]+%%", function()
            return "当前：" .. string.format("%.0f%%", scale * 100)
        end)
    elseif id == "pig" then
        local scale = item and item.scale or Items.Settings.defaultScale
        local weight = item and item.weight or Items.Settings.defaultWeight
        text = text:gsub("体积（当前：[%d%.]+%%）", function()
            return "体积（当前：" .. string.format("%.0f%%", scale * 100) .. "）"
        end)
        text = text:gsub("重量（当前：[%d%.]+%%）", function()
            return "重量（当前：" .. string.format("%.0f%%", weight * 100) .. "）"
        end)
    elseif id == "sheep" then
        local woolCount = item and item.woolCount or 0
        text = text:gsub("当前：%d+", function()
            return "当前：" .. tostring(woolCount)
        end)
    elseif id == "diner" or id == "tomato_egg" or id == "bodyguard" or id == "egg" then
        local counter = 0
        if item then
            if id == "egg" then counter = item.bottleRounds or 0
            else counter = item.counter or 0 end
        end
        text = text:gsub("当前：%d+", function()
            return "当前：" .. tostring(counter)
        end)
    end
    if id == "cloud" and Relics.Has(game, "coin_rain") then
        text = text:gsub("%[%[droplet%]%]", "[[coin_1]]")
        text = text .. "\n硬币雨：单件为永久生成，20%额外6枚仍为临时物品"
    end
    if id == "teacher" and Relics.Has(game, "teacher_team") then
        text = text .. "\n名师团队：相邻老师合成老师，保留双方加法价值与倍率，重新计算接触光环"
    end
    if id == "grass" and Relics.Has(game, "premium_grass") then
        text = text .. "\n优质小草：动物消耗必定产出便便，普通/黄金/钻石/彩虹权重为40:15:4:1；人类消费概率不变"
    end
    if id == "sheep" and Relics.Has(game, "wool_market") then
        text = text .. "\n羊毛集市：每份脱落库存改为从瓶顶生成1枚永久[[coin_1]]，不直接获得金币，也不兑换已有羊毛"
    end
    if id == "ghost" and Relics.Has(game, "ghost_sport") then
        text = text .. "\n幽灵运动：每真实移动5m，+1金币；闪现不计路程"
    end
    if id == "bacon" and Relics.Has(game, "bacon_network") then
        text = text .. "\n培根是对的：和同一块培根相邻的其他物品视为相邻，不改变物理碰撞轮廓"
    end
    if Items.IsPoop(id) and Items.IsPiercing(id, game) then
        text = text .. "\n幽灵便便：在瓶内自由飘动，可穿透物品"
    end
    if Items.HasTag(id, "食物") and Relics.Has(game, "food_comfort") then
        text = text .. "\n吃了不烧心：持有期间当前价值+2（基础项，之后计算倍率；非永久加值）"
    end
    if Relics.Has(game, "accelerator") then
        text = text .. "\n加速器：瓶内移动速度+20%，不缩短冷却或回合时间"
    end
    if Relics.Has(game, "spin_reward") then
        text = text .. "\n转圈圈：自然旋转每满一圈，+1金币"
    end
    local coin = tonumber(id:match("^coin_(%d+)$"))
    if coin and coin >= 64 and coin < 2048 and Relics.Has(game, "merge_2048") then
        text = text .. "\n合成2048已解锁：两枚[[" .. id .. "]]可合成[[coin_"
            .. string.format("%.0f", coin * 2) .. "]]。"
    end
    return text
end

---@param game BottleGame
---@param id string
---@return number
function Text.InitialValue(game, id)
    if id == "trash_can" and Relics.Has(game, "lucky_charm") then return 1 end
    local base = assert(Items.byId[id]).base
    if id == "credit_card" and Relics.Has(game, "credit_line") then return 25 end
    local foodBonus = Items.HasTag(id, "食物") and Relics.Has(game, "food_comfort") and 2 or 0
    local currentBase = base + foodBonus
    if id == "tomato" and Relics.Has(game, "tomato_tycoon") then return currentBase * 2 end
    return currentBase
end

return Text
