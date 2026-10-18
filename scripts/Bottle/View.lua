local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local RelicView = require("Bottle.RelicView")
local Art = require("Bottle.Art")
local Board = require("Bottle.Board")
local Storage = require("Bottle.Storage")
local Description = require("Bottle.Description")
local DeckBoard = require("Bottle.DeckBoard")
local ItemText = require("Bottle.ItemText")
local Money = require("Bottle.Money")
local PaperNote = require("Bottle.PaperNote")
local RemovalConfirm = require("Bottle.RemovalConfirm")
local SaveCodeField = require("Bottle.SaveCodeField")
local RefreshUI = require("Bottle.RefreshUI")
local RulesUI = require("Bottle.RulesUI")
local MachineSkin = require("Machine.LayeredSkin")
local Atmosphere=require("Machine.Atmosphere")
local GameAudio = require("Bottle.Audio")

---@type any
local View = {}
View.__index = View
---@type table<string, RGBAColor>
local C = (require("Bottle.Theme") --[[@as any]]).colors

---摇晃与结算阶段统称“进行中”：禁止拾取、弹层与牌库操作。
---@param game BottleGame
---@return boolean
local function Busy(game)
    return game.phase == "running" or game.phase == "settle" or game.phase == "reveal"
end

local NO_REMOVALS_MESSAGE = "当前无移除机会0"

-- 品质铭牌文字色，与三选一候选、详情共用同一组。
local QUALITY_INK = {
    {224, 224, 211, 255}, {80, 200, 120, 255}, {69, 170, 242, 255},
    {167, 122, 245, 255}, {255, 205, 74, 255},
}

---@class BottleItemIcon : Widget
---@field itemId string
---@field isRelic boolean
---@field rollValue number? 有实例时的骰子点数，无实例默认1点
---@field woolCount number? 小羊当前储毛量，新候选/定义默认0
---@overload fun(props:WidgetProps): BottleItemIcon
local Icon = UI.Widget:Extend("BottleItemIcon") --[[@as BottleItemIcon]]
function Icon:Init(props)
    UI.Widget.Init(self, props)
    self.itemId = props.itemId or "apple"
    self.isRelic = props.isRelic == true
    self.rollValue = props.rollValue
    self.woolCount = props.woolCount
end
function Icon:Render(vg)
    local l = self:GetAbsoluteLayout()
    local x, y, radius = l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) * .38
    if self.isRelic then Art.Relic(vg, self.itemId, x, y, radius)
    else
        -- 固定UI槽按实际图形包围范围等比内收，保留原38%半宽的留白预算。
        -- 只缩图标，不改变瓶内/牌库沙盒的世界尺寸；培根的加长外形仍完整可见。
        local extent = Art.ItemExtent(self.itemId, radius, 0, self.woolCount)
        local fittedRadius = extent > radius and radius * radius / extent or radius
        Art.Item(vg, self.itemId, x, y, fittedRadius, 0, false, self.rollValue, self.woolCount)
    end
end

---@class BottleStatIcon : Widget
---@field kind string
---@overload fun(props:WidgetProps): BottleStatIcon
local StatIcon = UI.Widget:Extend("BottleStatIcon") --[[@as BottleStatIcon]]
function StatIcon:Init(props)
    UI.Widget.Init(self, props)
    self.kind = props.kind or "gain"
end
function StatIcon:Render(vg)
    local l = self:GetAbsoluteLayout()
    Art.StatIcon(vg, self.kind, l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) / 2)
end

-- 三选一、牌库和详情共用属性行：只显示金币与分类tag；冷却规则保留在效果说明。
---@param gold number
---@param tags? string
---@return Panel row
---@return Label goldLabel
---@return Label tagLabel
local function ItemStats(gold, tags)
    local goldLabel = UI.Label {id = "goldValue", text = Money.Format(gold),
        textMotionDisabled = true, fontSize = 11.25, fontFamily = "mono", fontColor = C.warning}
    local tagText = tags or ""
    local tagLabel = UI.Label {id = "itemTag", text = tagText, visible = tagText ~= "",
        fontSize = 11.25, fontColor = C.textSecondary, marginLeft = 8,
        whiteSpace = "normal", flexShrink = 1}
    local row = UI.Panel {id = "itemStats", width = "100%", flexDirection = "row",
        flexWrap = "wrap", alignItems = "center", gap = 12, pointerEvents = "none", children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 4, minHeight = 24, children = {
                StatIcon {kind = "gain", width = 24, height = 24}, goldLabel,
            }},
            tagLabel,
        }}
    return row, goldLabel, tagLabel
end

-- 当前三选一是尚未创建实例的 id；若候选是已有实例，必须显示它自己的动态现值。
-- 不借用牌库中同名物品的永久增长，避免把新卡的基础值误写成另一个实例的值。
---@param game BottleGame
---@param option string|ItemInstance
---@return string id
---@return number? gold 遗物不具有物品价值
---@return ItemDef|RelicDef def
local function DraftValue(game, option)
    local id = option --[[@as string]]
    if type(option) == "table" then id = option.id end
    if game.relicDraft then
        local relic = Relics.byId[id]
        assert(relic, "未知遗物候选：" .. tostring(id))
        return id, nil, relic
    end
    local def = Items.byId[id]
    assert(def, "未知物品候选：" .. tostring(id))
    return id, type(option) == "table" and game:_Value(option) or ItemText.InitialValue(game, id), def
end

---@class BottleEye : Widget
---@overload fun(props:WidgetProps): BottleEye
local Eye = UI.Widget:Extend("BottleEye") --[[@as BottleEye]]
function Eye:Render(vg)
    local l = self:GetAbsoluteLayout()
    Art.Eye(vg, l.x + l.w / 2, l.y + l.h / 2, 9)
end

---@param text string
---@param size? number
---@param color? RGBAColor
---@return Label
local function Label(text, size, color)
    local fontSize = math.max(size or 12, 11.25)
    return UI.Label {text = text, fontSize = fontSize, fontColor = color or C.text,
        fontWeight = fontSize >= 13 and "bold" or "normal", flexShrink = 1}
end

---@param text string
---@param callback function
---@param primary? boolean
---@return Button
local function Button(text, callback, primary)
    return GameAudio.Button {
        text = text, onClick = callback, fontSize = 12, height = 48,
        variant = primary and "primary" or "secondary",
        borderColor = C.border,
        flexShrink = 1,
    }
end

---@class BottleView
---@field game BottleGame
---@field physics BottlePhysics
---@field actions table<string,function>
---@field targetBursts table[]? 目标进度条前沿的重力像素粒子
---@field root Panel
---@field container Panel
---@field board BottleBoard
---@field detail Panel
---@field detailOverlay Panel
---@field detailIcon BottleItemIcon
---@field detailTitle Label
---@field detailStats Panel
---@field detailGold Label
---@field detailTag Label
---@field detailEffect BottleDescription
---@field detailScroll ScrollView
---@field definitionModal Panel
---@field definitionId string
---@field definitionIcon BottleItemIcon
---@field definitionTitle Label
---@field definitionGold Label
---@field definitionTag Label
---@field definitionEffect BottleDescription
---@field definitionScroll ScrollView
---@field selectedUid integer
---@field detailRound integer
---@field detailRevision number
---@field physicsButton Button
---@field physicsMenu Panel
---@field physicsOne Button
---@field physicsTwo Button
---@field scoreLabel Label
---@field roundLabel Label
---@field goalLabel Label
---@field progress ProgressBar
---@field timer ProgressBar
---@field statusLabel Label
---@field footer Panel
---@field draft Panel
---@field modal Panel
---@field deckButton Button
---@field badgeLabel Label
---@field currentPhase string
---@field inventoryOpen boolean
---@field inventoryPanel Card?
---@field inventoryTitle Label?
---@field inventoryHead Panel?
---@field inventoryRemovalLabel Label?
---@field deckBody Panel?
---@field deckBoard any
---@field deckSim any
---@field removalConfirm any
---@field deckBackButton Button?
---@field deckDetailUid integer
---@field inventoryTab string
---@field relicDetailId string
---@field deckDraftWasOpen boolean
---@field choiceHidden boolean
---@field lastRevision number
---@field lastDisplayedScore number
---@field lastRound number

---@param game BottleGame
---@param physics BottlePhysics
---@param actions table<string,function>
---@return BottleView
function View.New(game, physics, actions)
    local self = setmetatable({}, View)
    self:Init(game, physics, actions)
    return self
end

function View:Init(game, physics, actions)
    self.game, self.physics, self.actions = game, physics, actions
    self.currentPhase = ""
    self.inventoryOpen, self.choiceHidden = false, false
    self.deckDetailUid, self.deckDraftWasOpen = 0, false
    self.inventoryTab, self.relicDetailId = "items", ""
    self.lastRevision, self.lastDisplayedScore, self.lastRound = -1, -1, -1
    self.lastRerollUsed = false
    self.lastRefreshes = RefreshUI.Count(game)
    self.selectedUid, self.detailRound, self.detailRevision = 0, -1, -1
    self.detailSource = ""
    self.detailIcon = Icon {itemId = "apple", width = 64, height = 64, pointerEvents = "none"}
    self.detailStats, self.detailGold, self.detailTag = ItemStats(0)
    self.itemNote = PaperNote.New {prefix = "detail", icon = self.detailIcon, stats = self.detailStats,
        zIndex = 32, onClose = function() self:CloseItemDetail() end,
        onInspect = function(id) self:InspectDefinition(id) end,
        scale = function() return self.machineSkin and self.machineSkin.scale or 1 end}
    self.detail, self.detailOverlay = self.itemNote.card, self.itemNote.overlay
    self.detailTitle, self.detailEffect, self.detailScroll = self.itemNote.title, self.itemNote.effect, self.itemNote.scroll
    self.definitionId = ""
    self.definitionIcon = Icon {id = "definitionIcon", itemId = "apple", width = 64, height = 64,
        pointerEvents = "none", flexShrink = 0}
    ---@type Panel
    local definitionStats
    definitionStats, self.definitionGold, self.definitionTag = ItemStats(0)
    local popup = PaperNote.New {prefix = "definition", icon = self.definitionIcon, stats = definitionStats,
        zIndex = 34, onClose = function() self:CloseDefinition() end,
        onInspect = function(id) self:InspectDefinition(id) end,
        scale = function() return self.machineSkin and self.machineSkin.scale or 1 end}
    self.definitionNote = popup
    self.definitionModal, self.definitionTitle = popup.overlay, popup.title
    self.definitionEffect, self.definitionScroll = popup.effect, popup.scroll
    self.scoreLabel = Label("0", 27, C.warning)
    self.scoreLabel:SetStyle({fontFamily = "mono"})
    self.roundLabel = Label("天数 1/5", 12, C.textSecondary)
    self.goalLabel = Label("40", 27, C.warning)
    self.badgeLabel = Label("考核阶段 1", 10, C.textSecondary)
    -- 统计区整体固定，不让回合／分数的文字基线随装饰时钟漂移。
    for _, value in ipairs({self.scoreLabel, self.roundLabel, self.goalLabel, self.badgeLabel}) do
        value:SetStyle({textMotionDisabled = true})
    end
    self.statusLabel = Label("准备好，摇出你的组合", 11, C.textSecondary)
    self.progress = UI.ProgressBar {value = 0, height = 12, showLabel = false, fillColor = C.primary}
    self.timer = UI.ProgressBar {value = 1, height = 8, showLabel = false, fillColor = C.warning}
    self.board = Board {game = game, physics = physics, shake = actions.shake,
        inspect = function(uid) self:InspectItem(uid) end,
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 120, pointerEvents = "auto"}
    self.physicsButton = Button("切换物理 · 二", function()
        self.board:ResetShake()
        self.physicsMenu:SetVisible(not self.physicsMenu:IsVisible())
    end)
    self.physicsButton:SetStyle({position = "absolute", left = 8, top = 8,
        width = 144, height = 40, fontSize = 11.25, zIndex = 5})
    self.physicsButton:SetWidth(144)
    self.physicsOne = Button("物理一 · 原版", function() self.actions.physics(1) end)
    self.physicsTwo = Button("物理二 · 摇晃", function() self.actions.physics(2) end, true)
    self.physicsOne:SetWidth(162)
    self.physicsTwo:SetWidth(162)
    self.physicsOne:SetStyle({fontSize = 11.25})
    self.physicsTwo:SetStyle({fontSize = 11.25})
    self.sensorStatus = "off"
    self.sensorLabel = UI.Label {id = "sensorStatus", text = "体感：未启用", fontSize = 10,
        whiteSpace = "normal", width = "100%", fontColor = C.textSecondary}
    self.sensorButton = Button("启用／校准体感", function()
        self.actions.sensor()
        self.physicsMenu:Hide()
    end)
    self.sensorButton.id = "sensorCalibrate"
    self.sensorButton:SetStyle({width = 162, fontSize = 11.25})
    self.physicsMenu = UI.Panel {position = "absolute", left = 8, top = 54,
        width = 178, padding = 8, gap = 8, backgroundColor = C.surface,
        visible = false, zIndex = 6, pointerEvents = "auto",
        children = {self.physicsOne, self.physicsTwo, self.sensorLabel, self.sensorButton}}
    self.board.physicsButton, self.board.physicsMenu = self.physicsButton, self.physicsMenu
    self.board:AddChild(self.physicsButton)
    self.board:AddChild(self.physicsMenu)
    self.footer = UI.Panel {width = "100%", gap = 10, paddingTop = 6, paddingBottom = 12}
    self.draft = UI.Panel {position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        visible = false, backgroundColor = C.overlay, justifyContent = "center", alignItems = "center",
        padding = 12, zIndex = 20, pointerEvents = "auto"}
    self.modal = UI.Panel {position = "absolute", top = 0, left = 0, right = 0, bottom = 0,
        visible = false, backgroundColor = C.overlay, padding = 16,
        justifyContent = "center", zIndex = 30, pointerEvents = "auto"}
    -- 牌库入口以袋子为底图，文字写在袋身上。
    self.deckButton = Button("牌库 3", function() self:OpenInventory() end)
    self.deckButton:SetStyle({height = 40, fontSize = 11.25, width = 86})
    local help = Button("规则", function() self:OpenHelp() end)
    help:SetStyle({height = 40, fontSize = 11.25, width = 64})
    local save = Button("存档", function() self:OpenSave() end)
    save:SetStyle({height = 40, fontSize = 11.25, width = 64})
    local gm = Button("GM", function() self:OpenGm() end)
    gm:SetStyle({textMotionDisabled = true})
    gm:SetStyle({height = 40, fontSize = 11.25, width = 52})
    local title = Label("摇摇牌库", 22.5, C.primary)
    title:SetStyle({textShadow = {offsetX = 2, offsetY = 2, blur = 0, color = C.secondary}})
    self.container = UI.Panel {width = "100%", maxWidth = 560, height = "100%",
        alignSelf = "center", paddingHorizontal = 20, paddingTop = 16, gap = 10,
        children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                    title, Label("瓶子里，藏着无限可能", 9, C.textSecondary),
                }}, gm, help, save,
            }},
            UI.Card {id = "scoreSummary", backgroundColor = C.surface, padding = 14, gap = 6,
                pointerEvents = "none", children = {
                    UI.Panel {flexDirection = "row", alignItems = "center", children = {
                        UI.Panel {flexGrow = 1, children = {Label("可用分数", 10, C.textSecondary), self.scoreLabel}},
                        UI.Panel {alignItems = "flex-end", gap = 4, children = {self.roundLabel, self.goalLabel}},
                    }}, self.progress,
                    self.badgeLabel,
                }},
            UI.Panel {flexDirection = "row", alignItems = "center", children = {
                UI.Panel {flexGrow = 1, children = {self.statusLabel}}, self.deckButton,
            }},
            self.timer, self.board, self.footer,
            self.detailOverlay, self.definitionModal, self.draft, self.modal,
        }}
    self.root = UI.Panel {width = "100%", height = "100%", backgroundColor = C.background,
        pointerEvents = "auto", onClick = function() self:CloseItemDetail() end,
        children = {UI.SafeAreaView {width = "100%", height = "100%", nativeMenuInset = true,
            children = {self.container}}}}
    MachineSkin.Apply(self,title,help,save,gm)
    self.removalConfirm = RemovalConfirm.New(self)
    UI.SetRoot(self.root)
    self:UpdatePhysicsMode()
    self:Update(true)
end

function View:UpdatePhysicsMode()
    local original = self.physics.mode == 1
    self.physicsButton:SetText("切换物理 · " .. (original and "一" or "二"))
    self.physicsOne:SetText(original and "物理一 [当前]" or "物理一 · 原版")
    self.physicsTwo:SetText(original and "物理二 · 摇晃" or "物理二 [当前]")
    self.physicsMenu:Hide()
end

function View:SetSensorStatus(status)
    if self.sensorStatus == status then return end
    self.sensorStatus = status
    local labels = {
        waiting = "体感：等待设备",
        available = "体感：已接通",
        unavailable = "体感：暂无数据",
        unsupported = "体感：当前端不支持",
    }
    self.sensorLabel:SetText(labels[status] or "体感：未启用")
    self.sensorButton:SetText(status == "available" and "重新校准体感"
        or status == "unsupported" and "查看体感说明" or "启用／校准体感")
    if Busy(self.game) then self:BuildFooter() end
end

function View:CloseItemDetail()
    if self.removalConfirm then self.removalConfirm:Close() end
    if self.deckBoard then self.deckBoard.selectedUid = 0 end
    self.selectedUid, self.board.selectedUid = 0, 0
    self.detailSource = ""
    self.deckDetailUid, self.relicDetailId = 0, ""
    self.itemNote:Close()
end

function View:NoteBounds()
    -- The playable portrait area excludes the window's side bars, but includes the whole machine.
    -- The note itself counters camera translation; these are stable layout-space edges.
    local game = self.container:GetAbsoluteLayout()
    local left, top = math.max(0, game.x), math.max(0, game.y)
    local right, bottom = math.min(UI.GetWidth(), game.x + game.w), math.min(UI.GetHeight(), game.y + game.h)
    return {x = left, y = top,w = math.max(1, right - left), h = math.max(1, bottom - top)}
end

-- 查看定义，不查询/创建实例，不改变牌库、三选一或瓶中选择。
---@param id string
---@return boolean
function View:InspectDefinition(id)
    local def = Items.byId[id]
    if not def or Busy(self.game) then return false end
    if self.definitionModal:IsVisible() and self.definitionId == id then return true end
    self.board:ResetShake()
    self.definitionId = id
    self.definitionIcon.itemId, self.definitionIcon.woolCount = id, nil
    self.definitionTitle:SetText(def.name)
    self.definitionNote:SetMeta("物品图鉴 · " .. Items.rarityNames[def.rarity])
    self.definitionGold:SetText(Money.Format(ItemText.InitialValue(self.game, id)))
    self.definitionTag:SetText(Items.TagsText(def))
    self.definitionTag:SetVisible(Items.TagsText(def) ~= "")
    self.definitionEffect:SetText(ItemText.Effect(self.game, id))
    self.definitionEffect:RestartReveal()
    self.definitionNote:Open(self.itemNote.anchor or function()
        local b = self:NoteBounds()
        return {x = b.x + b.w / 2, y = b.y + b.h / 2, w = 0, h = 0}
    end, function() return self:NoteBounds() end, self.machineSkin.scale)
    return true
end

function View:CloseDefinition()
    self.definitionNote:Close()
    self.definitionId = ""
end

---@param uid integer
function View:InspectItem(uid)
    if self.definitionModal:IsVisible() then return end
    local item = self.game:Get(uid)
    if Busy(self.game) or self.modal:IsVisible() or self.draft:IsVisible()
        or not item or item.location ~= "bottle" then
        self:CloseItemDetail()
        return
    end
    self:ShowItemNote(item, "bottle")
end

function View:ShowItemNote(item, source)
    local def = Items.byId[item.id]
    self.detailSource = source
    self.selectedUid = item.uid
    self.board.selectedUid = source == "bottle" and item.uid or 0
    self.deckDetailUid = source == "deck" and item.uid or 0
    if self.deckBoard then self.deckBoard.selectedUid = self.deckDetailUid end
    self.relicDetailId = ""
    self.detailRound, self.detailRevision = self.game.round, self.game.revision
    self.detailIcon.itemId, self.detailIcon.rollValue, self.detailIcon.woolCount = item.id, item.rollValue, item.woolCount
    self.detailIcon.isRelic = false
    self.detailTitle:SetText(def.name)
    self.itemNote:SetMeta(Items.rarityNames[def.rarity] .. " · 持有编号 #" .. item.uid)
    self.itemNote:SetStatus(nil); self.itemNote:SetAction(nil, nil)
    if source == "deck" and self.inventoryOpen and self.inventoryTab == "items" then
        self.itemNote:SetAction("移除", function() self:ConfirmRemoveDeckItem(item.uid) end,
            {danger = true, disabled = Busy(self.game)})
    end
    self.itemNote:SetStatsVisible(true)
    self.detailGold:SetText(Money.Format(self.game:_Value(item)))
    self.detailTag:SetText(Items.TagsText(def))
    self.detailTag:SetVisible(Items.TagsText(def) ~= "")
    self.detailEffect:SetText(ItemText.Effect(self.game, item.id, item))
    self.detailEffect:RestartReveal()
    self.itemNote:Open(function()
        local board = source == "deck" and self.deckBoard or self.board
        return board and board:GetItemBounds(item.uid) or nil
    end, function() return self:NoteBounds() end, self.machineSkin.scale)
end

function View:PositionItemDetail()
    self.itemNote:Place()
end

-- Both the bottom relic icons and the relic sandbox inspect through this note.
function View:InspectRelic(id)
    if Busy(self.game) or not Relics.Has(self.game, id) then return end
    self:CloseDefinition()
    self:CloseItemDetail()
    self.board:ResetShake()
    local inDeck = self.inventoryOpen and self.inventoryTab == "relics"
    if self.modal:IsVisible() and not inDeck then return end
    local def = assert(Relics.byId[id])
    self.detailSource = inDeck and "relic-deck" or "relic"
    if inDeck and self.deckBoard then self.deckBoard.selectedUid = def.numberId end
    self.relicDetailId = id
    self.detailRound, self.detailRevision = self.game.round, self.game.revision
    self.detailIcon.itemId, self.detailIcon.isRelic = id, true
    self.detailTitle:SetText(def.name)
    self.itemNote:SetStatsVisible(false)
    self.itemNote:SetMeta("遗物 · " .. Items.rarityNames[def.rarity])
    self.itemNote:SetStatus(RelicView.Status(self.game, id))
    self.detailEffect:SetText(def.effect); self.detailEffect:RestartReveal()
    self.itemNote:SetAction(id == "juicer" and ("生成果汁 · " .. string.format("%g", self.game.juicerValue or 0)) or nil,
        id == "juicer" and function() RelicView.ConfirmJuicer(self) end or nil)
    self.itemNote:Open(function()
        if inDeck and self.deckBoard then return self.deckBoard:GetItemBounds(def.numberId) end
        local button = self.machineSkin.relicGrid:FindById("relicSlot_" .. id)
        return button and button:GetAbsoluteLayout() or self:NoteBounds()
    end, function() return self:NoteBounds() end, self.machineSkin.scale)
end

function View:Rebind(game)
    if self.machineSkin then
        self.machineSkin.pageMotion:Reset()
        self.machineSkin.draftMotionKey=nil
        self.machineSkin.deductionNote:Reset()
    end
    self:CloseDefinition()
    self:CloseItemDetail()
    self.board:ResetShake()
    self:UpdatePhysicsMode()
    self.game = game
    self.board.game = game
    self.board:ResetEffects()
    self.board:ResetPopState()
    -- 读档/换局后的刷新池及历史布尔值属于基线，不触发额外重抽动画。
    self.lastRerollUsed = game.rerollUsed
    self.lastRefreshes = RefreshUI.Count(game)
    self.choiceHidden, self.inventoryOpen = false, false
    self.deckDetailUid, self.deckDraftWasOpen = 0, false
    self.inventoryTab, self.relicDetailId = "items", ""
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    self.modal:Hide()
    self:Update(true)
end

---只响应实际发生的考核扣款；余额与规则已由 Game 结算。
---@param amount number
function View:ShowDeduction(amount)
    if not (amount>0) then return end
    self.board.displayScore=nil
    self.machineSkin.deductionNote:Show(amount)
    GameAudio.Deduction()
end

---@param force? boolean
function View:Update(force)
    MachineSkin.Update(self)
    if self.removalConfirm then self.removalConfirm:Update() end
    local game = self.game
    if self.detailOverlay:IsVisible() then
        local item = game:Get(self.selectedUid)
        local source = self.detailSource
        local invalid = source == "bottle" and (self.modal:IsVisible() or self.draft:IsVisible()
                or not item or item.location ~= "bottle")
            or source == "deck" and (not self.inventoryOpen or self.inventoryTab ~= "items" or not item)
            or source == "relic-deck" and (not self.inventoryOpen or self.inventoryTab ~= "relics"
                or not Relics.Has(game, self.relicDetailId))
            or source == "relic" and (self.modal:IsVisible() or self.draft:IsVisible()
                or not Relics.Has(game, self.relicDetailId))
        if Busy(game) or game.round ~= self.detailRound or game.revision ~= self.detailRevision
            or self.physicsMenu:IsVisible() or invalid then
            self:CloseItemDetail()
        else
            self:PositionItemDetail()
        end
    end
    if force or game.score ~= self.lastDisplayedScore or game.target ~= self.lastDisplayedTarget then
        self.scoreLabel:SetText(Money.Format(game.score))
        self.lastDisplayedScore = game.score
        self.lastDisplayedTarget = game.target
        self.progress:SetValue(math.min(1, game.score / game.target))
    end
    self.roundLabel:SetText("天数 " .. (((game.round - 1) % 5) + 1) .. "/5")
    self.goalLabel:SetText(Money.Format(MachineSkin.TargetValue(self)))
    MachineSkin.FitNumbers(self)
    self.badgeLabel:SetText("考核阶段 " .. game.stage)
    if game.phase == "running" then
        self.timer:SetValue(math.max(0, 1 - game.elapsed / 10))
    elseif game.phase == "settle" then
        -- 结算下落2秒复用进度条：显示剩余缓冲时间。
        self.timer:SetValue(math.max(0, 1 - game.settleElapsed / 2))
    else
        self.timer:SetValue(1)
    end
    self.deckButton:SetText("牌库 " .. #game.deck)
    self.deckButton:SetDisabled(Busy(game))
    self:UpdateRemovalCount()
    -- 独立重抽机会用尽时，即使抽回同批 uid，也重新错峰弹跳。
    local refreshes = RefreshUI.Count(game)
    local refreshChanged = refreshes ~= self.lastRefreshes
    if game.phase == "prepare" and (refreshes < self.lastRefreshes
        or (game.rerollUsed and not self.lastRerollUsed)) then
        self.board:ResetPopState()
    end
    self.lastRerollUsed = game.rerollUsed
    self.lastRefreshes = refreshes
    if force or refreshChanged or game.phase ~= self.currentPhase or game.round ~= self.lastRound
        or game.revision ~= self.lastRevision or game.relicDraft ~= self.lastRelicDraft then
        local phaseChanged = game.phase ~= self.currentPhase or game.round ~= self.lastRound
            or game.relicDraft ~= self.lastRelicDraft
        if phaseChanged then
            self:CloseDefinition()
            self.choiceHidden = false
            self.board:ResetShake()
            -- 回合开始阶段已清旧残留；running/settle切换必须保留开局与即时收益队列。
            if game.round ~= self.lastRound or game.phase == "prepare" then
                self.board:ResetEffects()
            end
            self.physicsMenu:Hide()
        end
        self.currentPhase, self.lastRound = game.phase, game.round
        self.lastRevision, self.lastRelicDraft = game.revision, game.relicDraft
        self:BuildFooter()
        if game.phase == "draft" then
            self:BuildDraft()
            -- Finish the three red clock flashes before opening the CRT draft page.
            if self.machineSkin.cabinet.clock.flashElapsed >= 0 then self.draft:Hide() end
        else self.draft:Hide() end
    end
    MachineSkin.SyncPages(self)
    GameAudio.SetPhase(game.phase)
end

function View:BuildFooter()
    if self.machineSkin then self.machineSkin.pageMotion:Clear("footer") end
    local children = self.footer:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.footer:ClearChildren()
    local game = self.game
    if game.phase == "prepare" then
        self.statusLabel:SetText(game.lastResult ~= "" and game.lastResult
            or (self.physics.mode == 2 and "点击物品查看效果 · 开始后短距离来回摇" or "点击物品查看效果 · 开始后拖动瓶子"))
        local reroll = Button(RefreshUI.ButtonText(game, "重抽"), function() self.actions.reroll() end)
        reroll.id = "prepareReroll"
        reroll:SetDisabled(RefreshUI.Count(game) <= 0)
        reroll:SetStyle({flexGrow = 1, flexBasis = 0})
        local start = Button("开始摇晃", function() self.actions.start() end, true)
        start:SetStyle({flexGrow = 2, flexBasis = 0, height = 56, fontSize = 15})
        self.footer:AddChild(UI.Panel {flexDirection = "row", height = 60, gap = 10,
            alignItems = "center", children = {reroll, start}})
        local hint = Label(RefreshUI.Hint(game), 11.25, C.textSecondary)
        hint.id = "refreshPoolHint"
        hint:SetStyle({width = "100%", textAlign = "center", textMotionDisabled = true})
        self.footer:AddChild(hint)
    elseif game.phase == "running" then
        self.statusLabel:SetText(self.sensorStatus == "available" and "摇动手机或按住瓶子来回摇，带动物品碰撞"
            or self.physics.mode == 2 and "按住来回摇，换向时物品惯性翻滚"
            or "按住瓶子来回拖动，碰撞会改变组合")
        local label = Label("正在摇晃", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "settle" then
        self.statusLabel:SetText("禁止摇晃 · 物品自然下落，随后统一结算")
        local label = Label("结算中", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "reveal" then
        self.statusLabel:SetText("本回合 +" .. Money.Format(game.lastRoundScore) .. " 金币")
        local label = Label("结算完成", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "draft" then
        self.statusLabel:SetText("本回合 +" .. Money.Format(game.lastRoundScore)
            .. (game.relicDraft and " · 选一件遗物永久生效" or " · 选一件加入牌库"))
        local show = Button("查看本回合三选一", function()
            self:CloseItemDetail()
            MachineSkin.SetDraftOpen(self,true)
        end, true)
        show:SetStyle({width = "100%", height = 54})
        self.footer:AddChild(show)
    else
        self.statusLabel:SetText("未达到阶段目标，本局结束")
        local result = Label("坚持了 " .. game.bestRound .. " 回合 · 累计 " .. Money.Format(game.totalScore) .. " 分", 12)
        self.footer:AddChild(result)
        self.footer:AddChild(Button("重新开始", function() self:ConfirmNewRun() end, true))
    end
    MachineSkin.Footer(self)
end

function View:BuildDraft()
    if self.machineSkin then
        return MachineSkin.BuildDraft(self,Icon,Description,DraftValue,ItemStats)
    end
    local relicDraft = self.game.relicDraft == true
    local children = self.draft:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.draft:ClearChildren()
    -- 面板按屏幕比例放大并居中；内容过多时只滚动候选区，底部操作始终可见。
    local panel = UI.Card {width = "100%", height = "90%", maxHeight = 820, backgroundColor = C.surface,
        padding = 14, gap = 12, overflow = "hidden"}
    local eye = Button("", function()
        self.choiceHidden = true; self.draft:Hide()
    end)
    eye:SetStyle({width = 48, height = 44, flexShrink = 0})
    eye:AddChild(Eye {width = "100%", height = "100%", pointerEvents = "none"})
    panel:AddChild(UI.Panel {flexDirection = "row", alignItems = "center", gap = 12, children = {
        UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {
            UI.Label {text = relicDraft and "挑选你的下一件遗物" or "挑选你的下一件物品",
                fontSize = 20.25, fontWeight = "bold",
                whiteSpace = "normal", width = "100%", fontColor = C.text},
            Label("本回合 +" .. Money.Format(self.game.lastRoundScore) .. " · 三选一", 12, C.textSecondary),
        }}, eye,
    }})
    if self.game.lastResult ~= "" then
        panel:AddChild(UI.Label {text = self.game.lastResult, fontSize = 11.25,
            whiteSpace = "normal", width = "100%", fontColor = C.primary})
    end
    local choices = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 12, padding = 4}
    for i, option in ipairs(self.game.options) do
        local index = i
        local id, gold, def = DraftValue(self.game, option)
        local card = UI.Card {width = "100%", minHeight = 132, gap = 8,
            padding = 12, backgroundColor = C.background, borderColor = C.border}
        local choose = Button("选择", function() self.actions.choose(index) end, true)
        choose:SetStyle({width = 76, height = 48, fontSize = 12, flexShrink = 0})
        card:AddChild(UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10,
            children = {
                Icon {itemId = id, rollValue = type(option) == "table" and option.rollValue or nil,
                    woolCount = type(option) == "table" and option.woolCount or nil,
                    isRelic = relicDraft, width = 52, height = 52, pointerEvents = "none"},
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {
                    UI.Label {text = def.name .. " · " .. Items.rarityNames[def.rarity], whiteSpace = "normal",
                        fontSize = 14.25, fontWeight = "bold", width = "100%", fontColor = C.text},
                    (relicDraft and Label("遗物 · 永久生效", 12, C.textSecondary)
                        or ItemStats(gold --[[@as number]], Items.TagsText(def --[[@as ItemDef]]))),
                }}, choose,
            }})
        -- 效果说明独占整行，避免被图标和按钮挤窄，也不截断长描述。
        card:AddChild(Description {id = "draftDescription_" .. index,
            text = relicDraft and def.effect or ItemText.Effect(self.game, id,
                type(option) == "table" and option or nil), fontSize = 12,
            onInspect = function(itemId) self:InspectDefinition(itemId) end})
        choices:AddChild(card)
    end
    panel:AddChild(choices)
    panel:AddChild(UI.Label {id = "refreshPoolHint", text = RefreshUI.Hint(self.game),
        fontSize = 11.25, fontColor = C.textSecondary, textMotionDisabled = true,
        width = "100%", whiteSpace = "normal"})
    local refresh = Button(RefreshUI.ButtonText(self.game), function() self.actions.refresh() end)
    refresh.id = "draftRefresh"
    refresh:SetDisabled(RefreshUI.Count(self.game) <= 0)
    refresh:SetStyle({flexGrow = 1, flexBasis = 0})
    local skip = Button("跳过", function() self.actions.skip() end)
    skip:SetStyle({flexGrow = 1, flexBasis = 0})
    panel:AddChild(UI.Panel {flexDirection = "row", gap = 10, children = {refresh, skip}})
    self.draft:AddChild(panel)
    self.draft:SetVisible(not self.choiceHidden)
end

---@param title string
---@param noClose boolean?
---@return Card
function View:Modal(title, noClose)
    self.modalDeveloperUi=title=="GM 面板"
    self:CloseDefinition()
    self:CloseItemDetail()
    if self.inventoryOpen then
        -- 打开其它面板即离开牌库页：恢复机台输入与牌库页暂时接管的三选一页面。
        self.inventoryOpen=false
        self.deckDetailUid=0
        self.relicDetailId=""
        self:DisposeDeckSim()
        if self.game.phase=="draft" and self.deckDraftWasOpen then self.draft:Show() end
        self.deckDraftWasOpen=false
        if self.physicsButton then self.physicsButton:Show() end
    end
    self.inventoryPanel,self.inventoryTitle,self.deckBody=nil,nil,nil
    self.inventoryHead,self.inventoryRemovalLabel=nil,nil
    local children = self.modal:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    self.modal:ClearChildren()
    local panel = UI.Card {width = "100%", height = "88%", backgroundColor = C.surface,
        padding = 16, gap = 12}
    local heading=Label(title,18)
    heading.id="modalTitle"
    ---@type Widget[]
    local headChildren={UI.Panel {flexGrow = 1, children = {heading}}}
    if not noClose then
        local close = Button("关闭", function() self.modal:Hide(); self.inventoryOpen = false end)
        close:SetStyle({width = 70, height = 40, fontSize = 11.25})
        headChildren[#headChildren+1]=close
    end
    local head = UI.Panel {flexDirection = "row", alignItems = "center", children = headChildren}
    if noClose then
        -- 牌库页由物理沙盒铺满整个中部区域，标题行单独留出内边距。
        local s = self.machineSkin and self.machineSkin.scale or 1
        head:SetStyle({paddingLeft = 12 * s, paddingRight = 12 * s,
            paddingTop = 6 * s, paddingBottom = 4 * s})
    end
    panel:AddChild(head)
    self.modal:AddChild(panel)
    if self.machineSkin then MachineSkin.Modal(self,panel,false) end
    self.modal:Show()
    return panel
end

-- 牌库沙盒：全部持有实例从顶部落下，碰撞停稳后可点击进入详情。
function View:BuildDeckSandbox(body, s)
    if not self.deckSim or #self.deckSim.order == 0 then
        body:AddChild(UI.Panel {flexGrow = 1, flexBasis = 0,
            justifyContent = "center", alignItems = "center",
            children = {UI.Label {text = self.inventoryTab == "relics"
                and "尚未拥有遗物\n每5回合考核达标后可额外挑选一件" or "牌库为空",
                textAlign = "center", whiteSpace = "normal", width = "100%",
                fontSize = 12 * s, fontColor = C.textSecondary}}})
        return
    end
    local board = DeckBoard.Widget {id = "deckBoard", sim = self.deckSim,
        onPick = function(uid)
            if self.inventoryTab == "relics" then
                local def = Relics.byNumber[uid]
                if def then self:ShowDeckRelic(def.id) end
            else self:ShowDeckItem(uid) end
        end,
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 40, pointerEvents = "auto"}
    body:AddChild(board)
    self.deckBoard = board
end

---@param syncLayout boolean? 事件回调中立即排版；尺寸变化时由 UI 帧自行排版。
function View:BuildDeckPage(syncLayout)
    local body = self.deckBody
    if not body then return end
    local children = body:GetChildren()
    for i = #children, 1, -1 do children[i]:Destroy() end
    body:ClearChildren()
    self.deckBoard = nil
    local s = self.machineSkin and self.machineSkin.scale or 1
    local relicCount = #RelicView.Entries(self.game)
    if self.inventoryTitle then
        self.inventoryTitle:SetText(self.inventoryTab == "relics"
            and "我的遗物 · " .. relicCount .. " 件" or "我的牌库 · " .. #self.game.deck .. " 件")
        self.inventoryTitle:SetStyle({fontSize = 18 * s})
    end
    if self.inventoryHead then
        self.inventoryHead:SetStyle({paddingLeft = 12 * s, paddingRight = 12 * s,
            paddingTop = 6 * s, paddingBottom = 4 * s, gap = 8 * s})
    end
    if self.inventoryRemovalLabel then
        self.inventoryRemovalLabel:SetStyle({fontSize = 14 * s})
    end
    self:UpdateRemovalCount()
    self:BuildDeckSandbox(body, s)
    MachineSkin.InventoryTabs(self)
    if syncLayout then UI.Layout() end
end

function View:CreateDeckSim()
    self:DisposeDeckSim()
    local relics = self.inventoryTab == "relics"
    self.deckSim = DeckBoard.Sim.New(relics and RelicView.Entries(self.game) or self.game.deck, relics)
end

function View:SwitchInventoryTab(tab)
    if Busy(self.game) or not self.inventoryOpen or (tab ~= "items" and tab ~= "relics")
        or self.inventoryTab == tab then return end
    self:CloseDefinition()
    self:CloseItemDetail()
    self.inventoryTab = tab
    self.deckDetailUid, self.relicDetailId = 0, ""
    self:CreateDeckSim()
    self:BuildDeckPage(true)
end

function View:ShowDeckRelic(id)
    if Busy(self.game) or not self.inventoryOpen or self.inventoryTab ~= "relics"
        or not Relics.Has(self.game, id) then return end
    self:InspectRelic(id)
end

---@param uid integer
function View:ShowDeckItem(uid)
    local item = self.game:Get(uid)
    if Busy(self.game) or not self.inventoryOpen or self.inventoryTab ~= "items" or not item then return end
    self:CloseDefinition()
    self:ShowItemNote(item, "deck")
end

---@param uid integer
function View:ConfirmRemoveDeckItem(uid)
    if Busy(self.game) or not self.inventoryOpen or self.inventoryTab ~= "items"
        or self.detailSource ~= "deck" or self.deckDetailUid ~= uid then return end
    if (self.game.removals or 0) <= 0 then
        UI.Toast.Show(NO_REMOVALS_MESSAGE, {duration = 2, variant = "info"})
        return
    end
    self.removalConfirm:Open(uid, function(confirmedUid) self:RemoveDeckItem(confirmedUid) end)
end

-- Only the confirmed owned item is removed; keep the live sandbox and all remaining bodies.
---@param uid integer
function View:RemoveDeckItem(uid)
    if Busy(self.game) or not self.inventoryOpen or self.inventoryTab ~= "items"
        or self.detailSource ~= "deck" or self.deckDetailUid ~= uid then return end
    local board = self.deckBoard
    if not board or not self.deckSim or not self.deckSim.records[uid] then return end
    local ok, message = self.actions.remove(uid)
    if not ok then
        UI.Toast.Show((self.game.removals or 0) <= 0 and NO_REMOVALS_MESSAGE
            or message or "暂时无法移除", {variant = "info"})
        self:UpdateRemovalCount()
        return
    end
    self:CloseDefinition()
    self:CloseItemDetail()
    board:RemoveItem(uid)
    if self.inventoryTitle then self.inventoryTitle:SetText("我的牌库 · " .. #self.game.deck .. " 件") end
    self:UpdateRemovalCount()
    self:Update()
end

function View:UpdateRemovalCount()
    local count = math.max(0, math.floor(self.game.removals or 0))
    if self.inventoryRemovalLabel then
        local text = "移除机会 · " .. count
        if self.inventoryRemovalLabel.props.text ~= text then self.inventoryRemovalLabel:SetText(text) end
        self.inventoryRemovalLabel:SetVisible(self.inventoryTab == "items")
    end
    if self.detailSource == "deck" and self.itemNote.actionDanger then
        self.itemNote.action:SetDisabled(Busy(self.game))
    end
end

-- 返回按钮分层后退：详情 → 沙盒 → 离开牌库回到原页面。
function View:DeckBack()
    if self.removalConfirm and self.removalConfirm:IsOpen() then self.removalConfirm:Close(); return end
    if self.definitionModal:IsVisible() then self:CloseDefinition(); return end
    if self.detailOverlay:IsVisible() then self:CloseItemDetail(); return end
    self:CloseInventory()
end

-- 牌库沙盒只服务于牌库页；关闭、切换面板或换局时连同独立物理世界一起释放。
function View:DisposeDeckSim()
    self.deckBoard = nil
    if self.deckSim then
        self.deckSim:Dispose()
        self.deckSim = nil
    end
end

function View:CloseInventory()
    self:CloseDefinition()
    self:CloseItemDetail()
    self.modal:Hide()
    self.inventoryOpen = false
    self.deckDetailUid = 0
    self.relicDetailId = ""
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    if self.game.phase == "draft" and self.deckDraftWasOpen then self.draft:Show() end
    self.deckDraftWasOpen = false
    self:Update(true)
end

function View:OpenInventory(tab)
    if Busy(self.game) then return end
    tab = tab == "relics" and "relics" or "items"
    if self.inventoryOpen then
        self:SwitchInventoryTab(tab)
        return
    end
    self:CloseDefinition()
    self:CloseItemDetail()
    -- 三选一页面被牌库页整体接管；返回时恢复原候选页。
    self.deckDraftWasOpen = self.draft:IsVisible()
    local panel=self.inventoryPanel
    if not panel or not panel.node or panel.parent~=self.modal then
        panel=self:Modal("我的牌库", true)
        self.inventoryPanel=panel
        self.inventoryTitle=panel:FindById("modalTitle") --[[@as Label]]
        self.inventoryHead=panel:GetChildren()[1] --[[@as Panel]]
        self.inventoryHead:GetChildren()[1]:SetStyle({minWidth = 0, flexBasis = 0})
        self.inventoryRemovalLabel=UI.Label {id = "deckRemovalCount", text = "", fontSize = 14,
            fontColor = C.error, flexShrink = 0, textAlign = "right", textMotionDisabled = true,
            pointerEvents = "none"}
        self.inventoryHead:AddChild(self.inventoryRemovalLabel)
        self.deckBody=UI.Panel {id = "deckBody", width = "100%", flexGrow = 1, flexBasis = 0}
        panel:AddChild(self.deckBody)
    end
    self.inventoryOpen = true
    self.deckDetailUid = 0
    self.relicDetailId = ""
    self.inventoryTab = tab
    -- 每次打开相应收藏，都让持有的物品或遗物从顶部落下。
    self:CreateDeckSim()
    if self.machineSkin then MachineSkin.Modal(self,panel,true) end
    self.modal:Show()
    -- 面板可见后再排版，隐藏节点的 Yoga display=none 会得到零尺寸。
    self:BuildDeckPage(true)
    -- 牌库页占据中央屏幕，隐藏会悬浮在其上的物理入口。
    self.physicsButton:Hide()
    self.physicsMenu:Hide()
    self:Update(true)
    print(string.format("[%s] 物理沙盒打开：%d件从顶部落下",
        self.inventoryTab == "relics" and "遗物" or "牌库", #self.deckSim.order))
end

function View:OpenHelp()
    if Busy(self.game) then return end
    RulesUI.Open(self)
end

function View:OpenAtmosphere()
    if Busy(self.game) then return end
    local panel=self:Modal("机台氛围")
    panel:SetStyle({height="auto"})
    panel:AddChild(Label("调整屏幕的环境色，保留面板原有材质。",13,C.textSecondary))
    local descriptions={
        auto="默认 · 原色屏幕",
        brass="暖灯 · 原色屏幕",
        slate="冷夜 · 微冷玻璃",
        ember="余烬 · 微暖玻璃",
    }
    for _,id in ipairs(Atmosphere.order) do
        local button=Button((Storage.atmosphereMode==id and "● " or "○ ")..descriptions[id],function()
            self.actions.atmosphere(id)
            self.modal:Hide()
        end,Storage.atmosphereMode==id)
        button:SetStyle({width="100%",height=50,fontSize=15})
        panel:AddChild(button)
    end
end

--- GM 面板：接受数字编号 1–93 或字符串 id，由 Game:GmAddItem 统一匹配；未实装物品会被拒绝。
function View:OpenGm()
    local panel = self:Modal("GM 面板")
    panel:SetStyle({textMotionDisabled = true})
    panel:AddChild(UI.Label {text = "功能一 · 添加物品：输入数字编号 1–93 或字符串 id，全部93件可添加，加入牌库供后续抽取",
        fontSize = 11.25, fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"})
    local message = UI.Label {text = "输入数字或字符串 id；也可点击下方列表“添加”快捷加入",
        fontSize = 10.5, fontColor = C.primary, whiteSpace = "normal", width = "100%"}
    local field = UI.TextField {id = "gmItemId", placeholder = "数字 1–93 或 id，如 1 / apple",
        width = "100%", height = 48, fontSize = 12, fontFamily = "mono", flexGrow = 1, flexBasis = 0,
        onSubmit = function(self_, value)
            local id = value:match("^%s*(%S+)%s*$")
            if not id or id == "" then
                message:SetText("请先输入数字编号 1–93 或字符串 id")
                return
            end
            local ok, text = self.actions.gmadd(id)
            message:SetText(text or "")
            if ok then self_:SetValue("") end
        end}
    local submit = Button("添加", function()
        local value = field:GetValue()
        local id = value:match("^%s*(%S+)%s*$")
        if not id or id == "" then
            message:SetText("请先输入数字编号 1–93 或字符串 id")
            return
        end
        local ok, text = self.actions.gmadd(id)
        message:SetText(text or "")
        if ok then field:SetValue("") end
    end, true)
    submit:SetStyle({width = 84, height = 48, flexShrink = 0})
    panel:AddChild(UI.Panel {width = "100%", flexDirection = "row", gap = 10, alignItems = "center",
        children = {field, submit}})
    panel:AddChild(message)
    local scroll = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 6, padding = 4}
    for _, def in ipairs(Items.list) do
        local row = UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10,
            padding = 8, backgroundColor = C.background}
        row:AddChild(Icon {itemId = def.id, width = 36, height = 36, pointerEvents = "none", flexShrink = 0})
        row:AddChild(UI.Panel {flexGrow = 1, flexBasis = 0, gap = 2, pointerEvents = "none", children = {
            Label(def.name .. " · " .. Items.rarityNames[def.rarity]
                .. (def.implemented and "" or " · 未实装"), 11.25),
            UI.Label {text = string.format("%d · %s", def.numberId, def.id), fontSize = 11.25,
                fontFamily = "mono", fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"},
        }})
        local add = Button("添加", function()
            local ok, text = self.actions.gmadd(def.id)
            message:SetText(text or "")
            if ok then UI.Toast.Show(text, {duration = 2, variant = "success"}) end
        end)
        add:SetDisabled(not def.implemented)
        add:SetStyle({width = 64, height = 38, fontSize = 11.25, flexShrink = 0})
        row:AddChild(add)
        scroll:AddChild(row)
    end
    panel:AddChild(scroll)
end

function View:OpenSave()
    if Busy(self.game) then return end
    local panel = self:Modal("保存与继续")
    panel:AddChild(Label("本地状态：" .. Storage.status, 11, C.primary))
    panel:AddChild(UI.Label {text = "网页预览刷新后本地文件可能丢失。请复制下方存档码到外部保存，再粘贴导入。原生平台使用本地自动存档。",
        whiteSpace = "normal", width = "100%", fontSize = 11, fontColor = C.textSecondary})
    local code = Storage.Export(self.game)
    local field = SaveCodeField {id = "saveCode", value = code, width = "100%", height = 54, fontSize = 10,
        fontFamily = "mono"}
    panel:AddChild(field)
    panel:AddChild(Label("点击输入框，全选并复制；导入时替换为已保存的完整内容。", 10, C.textSecondary))
    local message = Label("摇晃阶段的存档会回退本回合所有变化。", 10, C.textSecondary)
    panel:AddChild(message)
    local import = Button("导入此存档", function()
        local ok, errorText = self.actions.import(field:GetValue())
        if ok then self.modal:Hide() else message:SetText(errorText or "导入失败") end
    end, true)
    import:SetStyle({width = "100%"})
    panel:AddChild(import)
    panel:AddChild(Button("开始新的一局", function() self:ConfirmNewRun() end))
end

function View:ConfirmNewRun()
    local panel = self:Modal("开始新的一局？")
    panel:SetStyle({height = 260})
    panel:AddChild(UI.Label {text = "当前自动存档将被新局覆盖。如需保留，请先导出存档码。",
        whiteSpace = "normal", width = "100%", fontSize = 12, fontColor = C.textSecondary})
    panel:AddChild(Button("确认开始新局", function() self.actions.newrun(); self.modal:Hide() end, true))
end

return View
