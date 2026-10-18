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
    if Relics.Has(game, "lucky_charm") then
        if id == "credit_card" then
            text = text:gsub("价值永久%-1", "价值永久+1")
        elseif id == "thief" and not Relics.Has(game, "wash_hands") then
            text = "相邻人类、硬币、[[credit_card]]价值永久+1，自身价值永久+1（冷却：6秒）"
        elseif id == "trash_can" then
            text = text .. "\n幸运符：基础价值由-1变为+1。"
        end
    end
    if item then
        if id == "glutton" then
            text = text:gsub("当前：x", function()
                return "当前：" .. string.format("%.0f%%", item.scale * 100)
            end)
        elseif id == "diner" or id == "tomato_egg" then
            text = text:gsub("当前：0", "当前：" .. tostring(item.counter))
        end
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
    if id == "tomato" and Relics.Has(game, "tomato_tycoon") then return base * 2 end
    if id == "credit_card" and Relics.Has(game, "credit_line") then return 25 end
    return base
end

return Text
