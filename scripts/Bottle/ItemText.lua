-- 物品说明展示本体与实例当前值；持帽厨师补充独立永久强化及实际冷却，遗物详情说明全局规则。
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
    if id == "chef" and item and Relics.Has(game, "chef_hat") then
        local boost = item.chefBoost or 0
        text = text .. "\n厨师帽强化（当前：+" .. tostring(boost)
            .. "）：每次为相邻食物永久增加" .. tostring(1 + boost) .. "价值，强化与本厨师永久绑定。"
    end
    return text
end

---@param game BottleGame
---@param id string
---@return number
function Text.InitialValue(game, id)
    local base = assert(Items.byId[id]).base
    if id == "credit_card" and Relics.Has(game, "credit_line") then return 25 end
    local foodBonus = Items.HasTag(id, "食物") and Relics.Has(game, "food_comfort") and 2 or 0
    local currentBase = base + foodBonus
    if id == "tomato" and Relics.Has(game, "tomato_tycoon") then return currentBase * 2 end
    return currentBase
end

return Text
