-- 已拥有遗物与榨汁确认；规则变更仅通过 main 的 action，查看与取消不改对局。
local UI = require("urhox-libs/UI")
local Relics = require("Bottle.Relics")
local Items = require("Bottle.Items")
local Art = require("Bottle.Art")
local Description = require("Bottle.Description")
local Audio = require("Bottle.Audio")
local L = require("Machine.LayeredLayout")
local RelicView = {}
local ink = {226, 214, 174, 255}
local muted = {133, 145, 122, 255}

---@param game BottleGame
local function Busy(game)
    return game.phase == "running" or game.phase == "settle" or game.phase == "reveal"
end

---@param value number
local function Number(value)
    return string.format("%.10g", value)
end

---@param game BottleGame
---@param id string
local function Status(game, id)
    if id == "juicer" then
        return "累计价值：" .. Number(game.juicerValue or 0) .. " · 点击生成果汁"
    elseif id == "jungle_hunt" then
        local target = game:Get(game.huntTargetUid or 0)
        if target and target.location ~= "discard" then
            return "当前目标：" .. Items.byId[target.id].name .. " #" .. target.uid
        end
        return "当前无可追杀的人类目标"
    elseif id == "scramble_recipe" then
        return "西红柿炒蛋总消耗上限：10次（保留既有计数）"
    end
    return "已拥有 · 永久生效"
end

---@param id string
---@param size number
local function Icon(id, size)
    local icon = UI.Widget {width = size, height = size, flexShrink = 0, pointerEvents = "none"}
    function icon:Render(vg)
        local b = self:GetAbsoluteLayout()
        Art.Relic(vg, id, b.x + b.w / 2, b.y + b.h / 2, math.min(b.w, b.h) * .43)
    end
    return icon
end

---@param view any
---@param text string
local function Label(view, text)
    return UI.Label {text = text, fontSize = 13 * view.machineSkin.scale,
        fontColor = ink, width = "100%", whiteSpace = "normal", flexShrink = 0}
end

---@param view any
function RelicView.ConfirmJuicer(view)
    if Busy(view.game) or not Relics.Has(view.game, "juicer") then return end
    local game = view.game
    local value = game.juicerValue or 0
    local s = view.machineSkin.scale
    local panel = view:Modal("榨汁机 · 确认生成", true)
    panel:SetStyle({gap = 12 * s, padding = 16 * s})
    panel:AddChild(Icon("juicer", 72 * s))
    local prose = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0,
        minHeight = 0, children = {Label(view, "当前累计价值：" .. Number(value)
        .. "\n\n确认后生成1份果汁，基础价值为累计值，永久加入牌库，不直接进入瓶中。"
        .. "\n果汁被消耗时：消耗者价值永久增加，数值等于果汁当时的价值。"
        .. "\n果汁为食物，不进入三选一卡池；食物+2等遗物仍可额外生效。"
        .. "\n\n生成成功后累计值清零；取消不会消耗累计值。")}}
    panel:AddChild(prose)
    local confirm = Audio.Button {id = "juicerConfirm", text = "确认生成 · " .. Number(value),
        height = 44 * s, fontSize = 13 * s, onClick = function()
            -- 不允许旧局／旧数值的确认框兑现新状态；规则入口还会再次检查阶段与持有权。
            if view.game ~= game or Busy(game) or game.juicerValue ~= value then
                UI.Toast.Show("状态已变化，请重新确认", {variant = "info"})
                view.modal:Hide()
                return
            end
            if not view.actions.juicer then return end
            local ok, message = view.actions.juicer()
            UI.Toast.Show(message or (ok and "果汁已加入牌库" or "暂时无法生成"),
                {variant = ok and "success" or "info"})
            if ok then RelicView.Open(view) end
        end}
    confirm:SetDisabled(value <= 0)
    panel:AddChild(confirm)
    panel:AddChild(Audio.Button {id = "juicerCancel", text = "取消", height = 40 * s,
        fontSize = 13 * s, onClick = function() RelicView.Open(view) end})
end

---@param view any
---@param id string
function RelicView.Detail(view, id)
    if Busy(view.game) or not Relics.Has(view.game, id) then return end
    if id == "juicer" then RelicView.ConfirmJuicer(view); return end
    local def = assert(Relics.byId[id])
    local s = view.machineSkin.scale
    local panel = view:Modal(def.name, true)
    panel:SetStyle({padding = 16 * s, gap = 12 * s})
    panel:AddChild(Icon(id, 72 * s))
    panel:AddChild(Label(view, Status(view.game, id)))
    panel:AddChild(UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
        children = {Description {text = def.effect, fontSize = 13 * s,
            onInspect = function(itemId) view:InspectDefinition(itemId) end}}})
    panel:AddChild(Audio.Button {id = "relicBack", text = "返回遗物", height = 44 * s,
        fontSize = 13 * s, onClick = function() RelicView.Open(view) end})
end

---@param view any
function RelicView.Open(view)
    if Busy(view.game) then return end
    view.board:ResetShake()
    view.physicsMenu:Hide()
    local s = view.machineSkin.scale
    local panel = view:Modal("已拥有遗物", true)
    panel:SetStyle({padding = 16 * s, gap = 10 * s})
    local list = UI.ScrollView {id = "ownedRelics", width = "100%", flexGrow = 1,
        flexBasis = 0, minHeight = 0, bounces = false, gap = 8 * s}
    local count = 0
    for _, def in ipairs(Relics.list) do
        if Relics.Has(view.game, def.id) then
            count = count + 1
            local id = def.id
            local row = UI.Panel {width = "100%", height = 70 * s, flexShrink = 0,
                flexDirection = "row", alignItems = "center", gap = 8 * s,
                backgroundColor = {24, 30, 27, 245}, padding = 8 * s,
                borderWidth = 1, borderColor = {94, 96, 97, 255}}
            row:AddChild(Icon(id, 42 * s))
            row:AddChild(Audio.Button {id = "ownedRelic_" .. id,
                text = def.name .. "\n" .. Status(view.game, id),
                flexGrow = 1, flexBasis = 0, height = 54 * s, fontSize = 11 * s,
                padding = 2 * s, textColor = ink, textAlign = "left",
                onClick = function() RelicView.Detail(view, id) end})
            list:AddChild(row)
        end
    end
    if count == 0 then list:AddChild(Label(view, "尚未拥有遗物。每5回合考核达标后，可额外挑选一件遗物。")) end
    panel:AddChild(list)
    panel:AddChild(Label(view, "已拥有 " .. count .. "/" .. #Relics.list .. " 件 · 点击查看详情或使用榨汁机"))
    panel:AddChild(Audio.Button {id = "relicsClose", text = "返回游戏", height = 44 * s,
        fontSize = 13 * s, onClick = function() view.modal:Hide() end})
end

---@param view any
function RelicView.Attach(view)
    local button = Audio.Button {id = "relicsButton", text = "遗物 0", zIndex = 25,
        textMotionDisabled = true, onClick = function() RelicView.Open(view) end}
    view.machineSkin.relicsButton = button
    view.container:AddChild(button)
end

---@param view any
function RelicView.Layout(view)
    local button = view.machineSkin.relicsButton
    local s = view.machineSkin.scale
    button:SetStyle(L.Style({184, 64, 116, 30}, s))
    button:SetStyle({fontSize = 11 * s, padding = 0, borderWidth = 1,
        boxShadow = false, backgroundColor = {24, 30, 27, 235},
        textColor = ink, disabledTextColor = muted, borderColor = {94, 96, 97, 255}})
end

---@param view any
function RelicView.Update(view)
    local count = 0
    for _, def in ipairs(Relics.list) do
        if Relics.Has(view.game, def.id) then count = count + 1 end
    end
    local button = view.machineSkin.relicsButton
    local text = "遗物 " .. count
    if Relics.Has(view.game, "juicer") then text = text .. " · " .. Number(view.game.juicerValue or 0) end
    if button.props.text ~= text then button:SetText(text) end
    button:SetDisabled(Busy(view.game))
end

return RelicView
