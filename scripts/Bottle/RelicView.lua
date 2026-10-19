-- 已拥有遗物与榨汁确认；规则变更仅通过 main 的 action，查看与取消不改对局。
local UI = require("urhox-libs/UI")
local Relics = require("Bottle.Relics")
local Items = require("Bottle.Items")
local Art = require("Bottle.Art")
local Audio = require("Bottle.Audio")
local Money = require("Bottle.Money")
local L = require("Machine.LayeredLayout")
local RelicLighting = require("Machine.RelicLighting")
local RelicView = {}
local ink = {226, 214, 174, 255}

---@param game BottleGame
local function Busy(game)
    return game.phase == "running" or game.phase == "settle" or game.phase == "reveal"
end

---@param game BottleGame
---@param id string
local function Status(game, id)
    if id == "juicer" then
        return "累计价值：" .. Money.Format(game.juicerValue or 0) .. " · 点击生成果汁"
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
---@param lighting any?
---@param viewport Widget?
local function Icon(id, size, lighting, viewport)
    local icon = UI.Widget {width = size, height = size, flexShrink = 0, pointerEvents = "none"}
    function icon:Render(vg)
        local b = self:GetAbsoluteLayout()
        local radius = math.min(b.w, b.h) * .38
        if lighting and viewport and lighting:Draw(self, id,
            {x = b.x + b.w / 2 - radius, y = b.y + b.h / 2 - radius,
                w = radius * 2, h = radius * 2}, viewport) then return end
        Art.Relic(vg, id, b.x + b.w / 2, b.y + b.h / 2, radius)
    end
    local destroy = icon.Destroy
    icon.Destroy = function(self)
        if lighting then lighting:Release(self) end
        destroy(self)
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
    local inDeck = view.inventoryOpen
    local function Back()
        view.modal:Hide()
        if inDeck then view:OpenInventory("relics") end
        RelicView.Detail(view, "juicer")
    end
    local s = view.machineSkin.scale
    local panel = view:Modal("榨汁机 · 确认生成", true)
    panel:SetStyle({gap = 12 * s, padding = 16 * s})
    panel:AddChild(Icon("juicer", 72 * s))
    local prose = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0,
        minHeight = 0, children = {Label(view, "当前累计价值：" .. Money.Format(value)
        .. "\n\n确认后生成1份果汁，基础价值为累计值，永久加入牌库，不直接进入瓶中。"
        .. "\n果汁被消耗时：消耗者价值永久增加，数值等于果汁当时的价值。"
        .. "\n果汁为食物，不进入三选一卡池；食物+2等遗物仍可额外生效。"
        .. "\n\n生成成功后累计值清零；取消不会消耗累计值。")}}
    panel:AddChild(prose)
    local confirm = Audio.Button {id = "juicerConfirm", text = "确认生成 · " .. Money.Format(value),
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
            if ok then Back() end
        end}
    confirm:SetDisabled(value <= 0)
    panel:AddChild(confirm)
    panel:AddChild(Audio.Button {id = "juicerCancel", text = "取消", height = 40 * s,
        fontSize = 13 * s, onClick = Back})
end

---@param view any
---@param id string
function RelicView.Detail(view, id)
    if Busy(view.game) or not Relics.Has(view.game, id) then return end
    view:InspectRelic(id)
end

function RelicView.Entries(game)
    local entries = {}
    for _, def in ipairs(Relics.list) do
        if Relics.Has(game, def.id) then
            entries[#entries + 1] = {uid = def.numberId, id = def.id, scale = 1}
        end
    end
    return entries
end

-- 牌库与遗物共用中央屏、详情版式和屏外返回键。
function RelicView.Open(view)
    view:OpenInventory("relics")
end

RelicView.Status = Status

---@param view any
function RelicView.Attach(view)
    if view.machineSkin.litScene then
        view.machineSkin.relicLighting = RelicLighting.New(view.machineSkin.litScene, view.container)
    end
    local grid = UI.Panel {id = "relicGrid", flexDirection = "row", flexWrap = "wrap",
        alignContent = "flex-start", flexShrink = 0, pointerEvents = "box-none",
        backgroundColor = {0, 0, 0, 0}, boxShadow = false}
    local scroll = UI.ScrollView {id = "relicGridScroll", zIndex = 8, padding = 0,
        scrollX = false, scrollY = true, showScrollbar = true, bounces = false,
        borderRadius = 0, backgroundColor = {0, 0, 0, 0}, boxShadow = false,
        children = {grid}}
    view.machineSkin.relicGrid = grid
    view.machineSkin.relicGridScroll = scroll
    view.machineSkin.relicSlots = {}
    view.machineSkin.relicButtons = {}
    view.container:AddChild(scroll)
end

-- 仅持有集合变化时重建，不因每帧数值/阶段更新丢失滚动和指针状态。
---@param view any
---@param owned string[]
local function BuildGrid(view, owned)
    local m = view.machineSkin
    local children = m.relicGrid:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    m.relicGrid:ClearChildren()
    m.relicSlots, m.relicButtons = {}, {}
    -- 最少两行空槽，已有遗物从左至右排列；后续每次补齐一整行。
    local count = math.max(L.relicColumns * 2, math.ceil(#owned / L.relicColumns) * L.relicColumns)
    for i = 1, count do
        local id = owned[i]
        ---@type Widget
        local slot
        if id then
            local button = Audio.Button {id = "relicSlot_" .. id, text = "",
                alignItems = "center", justifyContent = "center",
                onClick = function(_, event)
                    if event then event:StopPropagation() end
                    RelicView.Detail(view, id)
                end}
            slot = button
            local icon = Icon(id, L.relicSlot * m.scale, m.relicLighting, m.relicGridScroll)
            icon.id = "relicGridIcon"
            -- 悬停层会重挂子控件，使用满槽绝对布局保持图案居中及统一比例。
            icon:SetStyle({position = "absolute", left = 0, top = 0, width = "100%", height = "100%"})
            button:AddChild(icon)
            m.relicButtons[#m.relicButtons + 1] = button
        else
            slot = UI.Panel {id = "relicEmpty_" .. i, pointerEvents = "none"}
        end
        m.relicSlots[#m.relicSlots + 1] = slot
        m.relicGrid:AddChild(slot)
    end
    m.relicGridScroll:ScrollToTop()
    RelicView.Layout(view)
end

---@param view any
function RelicView.Layout(view)
    local m = view.machineSkin
    local s = m.scale
    m.relicGridScroll:SetStyle(L.Style(L.relicGrid, s))
    m.relicGrid:SetStyle({width = (L.relicColumns * L.relicSlot
        + (L.relicColumns - 1) * L.relicColumnGap) * s,
        columnGap = L.relicColumnGap * s, rowGap = L.relicRowGap * s})
    for _, slot in ipairs(m.relicSlots) do
        slot:SetStyle({width = L.relicSlot * s, height = L.relicSlot * s,
            flexGrow = 0, flexShrink = 0, padding = 0, borderRadius = 0,
            borderWidth = 0, hoverBorderWidth = 0, pressedBorderWidth = 0,
            backgroundColor = {0, 0, 0, 0}, hoverBackgroundColor = {0, 0, 0, 0},
            pressedBackgroundColor = {0, 0, 0, 0}, disabledBackgroundColor = {0, 0, 0, 0},
            boxShadow = false, hoverBoxShadow = false, pressedBoxShadow = false,
            disabledBoxShadow = false})
    end
end

---@param view any
---@param visible boolean
function RelicView.SetVisible(view, visible)
    view.machineSkin.relicGridScroll:SetVisible(visible)
    if not visible and view.machineSkin.relicLighting then view.machineSkin.relicLighting:Hide() end
end

---@param view any
function RelicView.Update(view)
    ---@type string[]
    local owned = {}
    for _, def in ipairs(Relics.list) do
        if Relics.Has(view.game, def.id) then owned[#owned + 1] = def.id end
    end
    local m = view.machineSkin
    local key = table.concat(owned, "|")
    if m.relicGridKey ~= key then
        m.relicGridKey = key
        BuildGrid(view, owned)
    end
    local busy = Busy(view.game)
    for _, relicButton in ipairs(m.relicButtons) do
        if relicButton.props.disabled ~= busy then relicButton:SetDisabled(busy) end
    end
end

return RelicView
