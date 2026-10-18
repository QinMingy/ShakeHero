local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local Art = require("Bottle.Art")
local Board = require("Bottle.Board")
local Storage = require("Bottle.Storage")
local Description = require("Bottle.Description")
local DeckBoard = require("Bottle.DeckBoard")
local ItemText = require("Bottle.ItemText")
local ItemDetail = require("Bottle.ItemDetail")
local RefreshUI = require("Bottle.RefreshUI")
local Removal = require("Bottle.Removal")
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
    local goldLabel = UI.Label {id = "goldValue", text = string.format("%g", gold),
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
---@field detail Card
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
---@field deckBody Panel?
---@field deckBoard any
---@field deckSim any
---@field deckBackButton Button?
---@field deckDetailUid integer
---@field removalConfirmUid integer
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
    self.deckDetailUid, self.deckDraftWasOpen, self.removalConfirmUid = 0, false, 0
    self.lastRevision, self.lastDisplayedScore, self.lastRound = -1, -1, -1
    self.lastRerollUsed = false
    self.lastRefreshes = RefreshUI.Count(game)
    self.selectedUid, self.detailRound, self.detailRevision = 0, -1, -1
    self.detailIcon = Icon {itemId = "apple", width = 42, height = 42, pointerEvents = "none"}
    self.detailTitle = UI.Label {text = "", fontSize = 14.25, fontWeight = "bold",
        whiteSpace = "normal", width = "100%", fontColor = C.text}
    self.detailStats, self.detailGold, self.detailTag = ItemStats(0)
    self.detailEffect = Description {id = "detailDescription", text = "", fontSize = 12, fontColor = C.text,
        onInspect = function(id) self:InspectDefinition(id) end}
    self.detailScroll = UI.ScrollView {id = "detailScroll", width = "100%", height = 32,
        bounces = false, children = {self.detailEffect}}
    self.detail = UI.Card {id = "itemDetail", position = "absolute", visible = false,
        width = 280, padding = 12, gap = 8, backgroundColor = C.surface,
        borderColor = C.border, zIndex = 15, pointerEvents = "auto",
        onClick = function() end, children = {
            UI.Panel {flexDirection = "row", alignItems = "center", gap = 10, children = {
                self.detailIcon,
                UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {self.detailTitle, self.detailStats}},
            }},
            self.detailScroll,
        }}
    self.definitionId = ""
    self.definitionIcon = Icon {id = "definitionIcon", itemId = "apple", width = 52, height = 52,
        pointerEvents = "none", flexShrink = 0}
    ---@type Panel
    local definitionStats
    definitionStats, self.definitionGold, self.definitionTag = ItemStats(0)
    local definitionClose = Button("关闭", function(widget, event)
        if event then event:StopPropagation() end
        self:CloseDefinition()
    end)
    definitionClose:SetStyle({width = 70, height = 40, flexShrink = 0})
    definitionClose.id = "definitionClose"
    local popup = Description.CreatePopup(self.definitionIcon, definitionStats, definitionClose,
        function(id) self:InspectDefinition(id) end, function() self:CloseDefinition() end)
    self.definitionModal, self.definitionTitle = popup.overlay, popup.title
    self.definitionEffect, self.definitionScroll = popup.effect, popup.scroll
    self.scoreLabel = Label("0", 27, C.warning)
    self.scoreLabel:SetStyle({fontFamily = "mono"})
    self.roundLabel = Label("回合 1/5", 12, C.textSecondary)
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
            self.detail, self.draft, self.modal,
        }}
    self.root = UI.Panel {width = "100%", height = "100%", backgroundColor = C.background,
        pointerEvents = "auto", onClick = function() self:CloseItemDetail() end,
        children = {UI.SafeAreaView {width = "100%", height = "100%", nativeMenuInset = true,
            children = {self.container}}, self.definitionModal}}
    MachineSkin.Apply(self,title,help,save,gm)
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
    self.selectedUid, self.board.selectedUid = 0, 0
    self.detail:Hide()
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
    self.definitionTitle:SetText(def.name .. " · " .. Items.rarityNames[def.rarity])
    self.definitionGold:SetText(string.format("%g", ItemText.InitialValue(self.game, id)))
    self.definitionTag:SetText(Items.TagsText(def))
    self.definitionTag:SetVisible(Items.TagsText(def) ~= "")
    self.definitionEffect:SetText(ItemText.Effect(self.game, id))
    self.definitionEffect:RestartReveal()
    self.definitionModal:Show()
    UI.Layout()
    self.definitionEffect:Measure(self.definitionEffect:GetLayout().w)
    UI.Layout()
    self.definitionScroll:ScrollToTop()
    return true
end

function View:CloseDefinition()
    self.definitionModal:Hide()
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
    local def = Items.byId[item.id]
    self.selectedUid, self.board.selectedUid = uid, uid
    self.detailRound, self.detailRevision = self.game.round, self.game.revision
    self.detailIcon.itemId, self.detailIcon.rollValue, self.detailIcon.woolCount = item.id, item.rollValue, item.woolCount
    self.detailTitle:SetText(def.name .. "  #" .. uid .. " · " .. Items.rarityNames[def.rarity])
    self.detailGold:SetText(string.format("%g", self.game:_Value(item)))
    self.detailTag:SetText(Items.TagsText(def))
    self.detailTag:SetVisible(Items.TagsText(def) ~= "")
    self.detailEffect:SetText(ItemText.Effect(self.game, item.id, item))
    self.detailEffect:RestartReveal()
    self.detailTitle:SetStyle({textReveal = true})
    self.detailScroll:ScrollToTop()
    self.detail:SetStyle({borderColor = C.border})
    self.detail:Show()
    self:PositionItemDetail()
end

function View:PositionItemDetail()
    if self.selectedUid == 0 then return end
    local rootBounds = self.container:GetAbsoluteLayout()
    local container = self.board.layered and self.board:GetAbsoluteLayout() or rootBounds
    local width = math.min(300, math.max(1, container.w - 24))
    if self.detail.props.width ~= width then self.detail:SetWidth(width) end
    UI.Layout()
    local effectHeight = self.detailEffect:Measure(self.detailEffect:GetLayout().w)
    -- 常规内容自然展开；极小屏或长说明仅滚动效果区，保留标题、属性和关闭提示。
    local chromeHeight = self.detail:GetAbsoluteLayout().h - self.detailScroll:GetAbsoluteLayout().h
    local effectBudget = math.max(32, container.h - math.max(124, chromeHeight) - 32)
    local effectViewport = math.min(effectHeight, effectBudget)
    if self.detailScroll.props.height ~= effectViewport then self.detailScroll:SetHeight(effectViewport) end
    UI.Layout()
    local bounds = self.board:GetItemBounds(self.selectedUid)
    local detail = self.detail:GetAbsoluteLayout()
    local centerX = bounds.x + bounds.w / 2
    local x = math.max(container.x + 12,
        math.min(centerX - width / 2, container.x + container.w - width - 12))
    local gap = 10
    local y = bounds.y - detail.h - gap
    local minY = container.y + 8
    local maxY = container.y + container.h - detail.h - 8
    if y < minY then y = bounds.y + bounds.h + gap end
    y = math.max(minY, math.min(y, maxY))
    local left, top = x - rootBounds.x, y - rootBounds.y
    if self.detail.props.left ~= left or self.detail.props.top ~= top then
        self.detail:SetStyle({left = left, top = top})
    end
end

function View:Rebind(game)
    if self.machineSkin then
        self.machineSkin.pageMotion:Reset()
        self.machineSkin.draftMotionKey=nil
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
    self.deckDetailUid, self.deckDraftWasOpen, self.removalConfirmUid = 0, false, 0
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    self.modal:Hide()
    self:Update(true)
end

---@param force? boolean
function View:Update(force)
    MachineSkin.Update(self)
    local game = self.game
    if self.selectedUid ~= 0 then
        local item = game:Get(self.selectedUid)
        if Busy(game) or game.round ~= self.detailRound or game.revision ~= self.detailRevision
            or self.modal:IsVisible() or self.draft:IsVisible() or self.physicsMenu:IsVisible()
            or not item or item.location ~= "bottle" then
            self:CloseItemDetail()
        else
            self:PositionItemDetail()
        end
    end
    if force or game.score ~= self.lastDisplayedScore or game.target ~= self.lastDisplayedTarget then
        self.scoreLabel:SetText(string.format("%g", game.score))
        self.lastDisplayedScore = game.score
        self.lastDisplayedTarget = game.target
        self.progress:SetValue(math.min(1, game.score / game.target))
    end
    self.roundLabel:SetText("回合 " .. (((game.round - 1) % 5) + 1) .. "/5")
    self.goalLabel:SetText(string.format("%g", game.target))
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
    -- 牌库详情与确认页共享当前实例，不以类型名删牌；次数在牌库标题中始终可见。
    if self.inventoryOpen and self.inventoryTitle then
        self.inventoryTitle:SetText("我的牌库 · " .. #game.deck .. " 件 · 移除 " .. Removal.Count(game) .. " 次")
        if Busy(game) then self:CloseInventory() end
    end
    self.deckButton:SetText("牌库 " .. #game.deck)
    self.deckButton:SetDisabled(Busy(game))
    -- 每次成功准备重抽都会扣共享池；即使抽回同批uid，也重新错峰弹跳。
    -- 旧布尔字段只作为动画兼容基线，不再限制同回合多次重抽。
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
        self.statusLabel:SetText("本回合 +" .. string.format("%g", game.lastRoundScore) .. " 金币")
        local label = Label("结算完成", 15, C.primary)
        label:SetStyle({height = 52, textAlign = "center", verticalAlign = "middle"})
        self.footer:AddChild(label)
    elseif game.phase == "draft" then
        self.statusLabel:SetText("本回合 +" .. string.format("%g", game.lastRoundScore)
            .. (game.relicDraft and " · 选一件遗物永久生效" or " · 选一件加入牌库"))
        local show = Button("查看本回合三选一", function()
            self:CloseItemDetail()
            MachineSkin.SetDraftOpen(self,true)
        end, true)
        show:SetStyle({width = "100%", height = 54})
        self.footer:AddChild(show)
    else
        self.statusLabel:SetText("未达到阶段目标，本局结束")
        local result = Label("坚持了 " .. game.bestRound .. " 回合 · 累计 " .. string.format("%g", game.totalScore) .. " 分", 12)
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
            Label("本回合 +" .. string.format("%g", self.game.lastRoundScore) .. " · 三选一", 12, C.textSecondary),
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
        self.deckDetailUid,self.removalConfirmUid=0,0
        self:DisposeDeckSim()
        if self.game.phase=="draft" and self.deckDraftWasOpen then self.draft:Show() end
        self.deckDraftWasOpen=false
        if self.physicsButton then self.physicsButton:Show() end
    end
    self.inventoryPanel,self.inventoryTitle,self.deckBody=nil,nil,nil
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
            children = {UI.Label {text = "牌库为空", fontSize = 12 * s, fontColor = C.textSecondary}}})
        return
    end
    local board = DeckBoard.Widget {id = "deckBoard", sim = self.deckSim,
        onPick = function(uid) self:ShowDeckItem(uid) end,
        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 40, pointerEvents = "auto"}
    body:AddChild(board)
    self.deckBoard = board
end

-- 牌库与三选一共用详情版式；实例数值与编号仍来自当前持有物品。
function View:BuildDeckDetail(body, item, s)
    local def = Items.byId[item.id]
    local content = ItemDetail.Create {prefix = "deck", scale = s, def = def,
        caption = "物品详情", meta = "持有编号 #" .. item.uid,
        gold = self.game:_Value(item),
        icon = Icon {itemId = item.id, rollValue = item.rollValue, woolCount = item.woolCount,
            width = 88 * s, height = 88 * s, pointerEvents = "none"},
        descriptionId = "deckDescription", effect = ItemText.Effect(self.game, item.id, item),
        onInspect = function(id) self:InspectDefinition(id) end}
    content:SetStyle({height = "auto", flexGrow = 1, flexBasis = 0})
    body:AddChild(content)
    local uid = item.uid
    local allowed = self.game:CanRemoveOwned(uid)
    local remove = Button("永久移除 · 消耗1次（剩余" .. Removal.Count(self.game) .. "次）",
        function() self:ConfirmRemoval(uid) end)
    remove.id = "deckRemove"
    remove:SetStyle({width = "100%", height = 42 * s, fontSize = 12 * s, flexShrink = 0})
    remove:SetDisabled(not allowed)
    body:AddChild(remove)
end

-- 仍留在牌库页的同一弹窗中二次确认；不重开牌库或重抽瓶内实例。
---@param uid integer
function View:ConfirmRemoval(uid)
    if not self.inventoryOpen or self.deckDetailUid ~= uid then return false end
    local game = self.game
    local allowed, message = game:CanRemoveOwned(uid)
    local item = game:Get(uid)
    if not allowed or not item then
        UI.Toast.Show(message, {variant = "info"})
        return false
    end
    self.removalConfirmUid = uid
    self:CloseDefinition()
    self:BuildDeckPage(true)
    print(string.format("[移除] 等待确认 %s #%d，剩余%d次", item.id, uid, Removal.Count(game)))
    return true
end

function View:BuildRemovalConfirm(body, item, s)
    local game, uid = self.game, item.uid
    local round, phase = game.round, game.phase
    local def = Items.byId[item.id]
    body:AddChild(UI.Panel {width = "100%", flexGrow = 1, flexBasis = 0,
        padding = 14 * s, gap = 12 * s, justifyContent = "center", children = {
            Label("确认永久移除？", 18 * s, C.warning),
            Icon {itemId = item.id, rollValue = item.rollValue, woolCount = item.woolCount,
                width = 72 * s, height = 72 * s, alignSelf = "center", pointerEvents = "none"},
            UI.Label {id = "removalTarget", text = def.name .. " · 持有编号 #" .. uid
                .. "\n当前价值 " .. string.format("%g", game:_Value(item)),
                fontSize = 13 * s, fontColor = C.text, whiteSpace = "normal", width = "100%"},
            UI.Label {text = "仅移除这一件，永久离开牌库与瓶中。不会进入弃牌堆，"
                .. "不会触发被消耗效果，也不能被死灵返还。\n成功后消耗1次，取消不扣次数。",
                fontSize = 12 * s, fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"},
        }})
    local used = false
    local confirm = Button("确认永久移除 · 剩余" .. Removal.Count(game) .. "次", function()
        if used or self.game ~= game or not self.inventoryOpen or self.removalConfirmUid ~= uid
            or game.round ~= round or game.phase ~= phase or game:Get(uid) ~= item then return end
        used = true
        local ok, text = self.actions.remove(uid)
        UI.Toast.Show(text or (ok and "已永久移除" or "无法移除"), {variant = ok and "success" or "info"})
        if not ok then self.removalConfirmUid = 0; self:BuildDeckPage(true) end
    end, true)
    confirm.id = "removalConfirm"
    confirm:SetStyle({width = "100%", height = 44 * s, fontSize = 12 * s, flexShrink = 0})
    local cancel = Button("取消 · 保留物品", function()
        if self.game ~= game or self.removalConfirmUid ~= uid then return end
        self.removalConfirmUid = 0
        self:BuildDeckPage(true)
    end)
    cancel.id = "removalCancel"
    cancel:SetStyle({width = "100%", height = 40 * s, fontSize = 12 * s, flexShrink = 0})
    body:AddChild(confirm)
    body:AddChild(cancel)
end

---成功移除后只退休该UID沙盒实体；其他沙盒和瓶内物理姿态不重建。
---@param uid integer
function View:OwnedItemRemoved(uid)
    local sim = self.deckSim
    local record = sim and sim.records[uid]
    if record then
        if record.soft then record.soft:Dispose()
        elseif record.node then record.node:Remove(); record.node:Dispose() end
        sim.records[uid] = nil
        for index = #sim.order, 1, -1 do
            if sim.order[index].uid == uid then table.remove(sim.order, index) end
        end
    end
    self.board:Effects({{kind = "remove", uid = uid}})
    if self.selectedUid == uid then self:CloseItemDetail() end
    self.deckDetailUid, self.removalConfirmUid = 0, 0
    if self.inventoryOpen then self:BuildDeckPage(true) end
    self:Update(true)
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
    local item = self.deckDetailUid ~= 0 and self.game:Get(self.deckDetailUid) or nil
    if item and self.removalConfirmUid == item.uid then
        self:BuildRemovalConfirm(body, item, s)
    elseif item then
        self:BuildDeckDetail(body, item, s)
    else
        self.removalConfirmUid = 0
        self:BuildDeckSandbox(body, s)
    end
    if syncLayout then UI.Layout() end
end

---@param uid integer
function View:ShowDeckItem(uid)
    if Busy(self.game) or not self.game:Get(uid) then return end
    self.deckDetailUid = uid
    self:BuildDeckPage(true)
end

-- 返回按钮分层后退：详情 → 沙盒 → 离开牌库回到原页面。
function View:DeckBack()
    if self.removalConfirmUid ~= 0 then
        self.removalConfirmUid = 0
        self:BuildDeckPage(true)
        return
    end
    if self.deckDetailUid ~= 0 then
        self.deckDetailUid = 0
        self:BuildDeckPage(true)
        return
    end
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
    self.modal:Hide()
    self.inventoryOpen = false
    self.deckDetailUid, self.removalConfirmUid = 0, 0
    self:DisposeDeckSim()
    if self.physicsButton then self.physicsButton:Show() end
    if self.game.phase == "draft" and self.deckDraftWasOpen then self.draft:Show() end
    self.deckDraftWasOpen = false
    self:Update(true)
end

function View:OpenInventory()
    if Busy(self.game) then return end
    self:CloseDefinition()
    self:CloseItemDetail()
    -- 三选一页面被牌库页整体接管；返回时恢复原候选页。
    self.deckDraftWasOpen = self.draft:IsVisible()
    local panel=self.inventoryPanel
    if not panel or not panel.node or panel.parent~=self.modal then
        panel=self:Modal("我的牌库", true)
        self.inventoryPanel=panel
        self.inventoryTitle=panel:FindById("modalTitle") --[[@as Label]]
        self.deckBody=UI.Panel {id = "deckBody", width = "100%", flexGrow = 1, flexBasis = 0}
        panel:AddChild(self.deckBody)
    end
    self.inventoryOpen = true
    self.deckDetailUid, self.removalConfirmUid = 0, 0
    self:DisposeDeckSim()
    -- 每次打开牌库都让全部持有实例重新从顶部落下。
    self.deckSim = DeckBoard.Sim.New(self.game.deck)
    self.inventoryTitle:SetText("我的牌库 · " .. #self.game.deck .. " 件 · 移除 " .. Removal.Count(self.game) .. " 次")
    if self.machineSkin then MachineSkin.Modal(self,panel,true) end
    self.modal:Show()
    -- 面板可见后再排版，隐藏节点的 Yoga display=none 会得到零尺寸。
    self:BuildDeckPage(true)
    -- 牌库页占据中央屏幕，隐藏会悬浮在其上的物理入口。
    self.physicsButton:Hide()
    self.physicsMenu:Hide()
    self:Update(true)
    print(string.format("[牌库] 物理沙盒打开：%d件从顶部落下",#self.game.deck))
end

function View:OpenHelp()
    if Busy(self.game) then return end
    local panel = self:Modal("摇摇牌库 · 玩法")
    local mood=Button("机台氛围 · "..Atmosphere.names[Storage.atmosphereMode],
        function() self:OpenAtmosphere() end)
    mood:SetStyle({width="100%",height=42})
    panel:AddChild(mood)
    local scroll = UI.ScrollView {width = "100%", flexGrow = 1, flexBasis = 0, gap = 12, padding = 4}
    local rules = {
        {"01  抽取与刷新", "回合开始从牌库随机抽取最多20件进入瓶中，不足时全部入瓶。准备重抽与物品三选一共用刷新池：新局1次，每完成两回合+1；成功刷新消耗1次，有次数即可连续刷新，回合开始不重置。遗物三选一每次独立免费刷新1次，不消耗共享池，未用次数不累计。[[egg]]入瓶满3回合消耗自身，50%概率增加1次免费刷新。"},
        {"02  摇晃", "点击开始后运行10秒（遗物最后一秒可增加1秒），不操作照常计时。瓶中物品按说明实时反应。瓶子左上可切换物理；手机原生端可启用体感，网页预览可触摸拖动。"},
        {"03  结算", "摇晃结束后禁止摇晃，物品自然下落2秒；持续接触加成继续同步，不再执行离散触发。随后按当前有效价值产金币，逐件弹出收益，全部展示后再停留2秒。"},
        {"04  价值与冷却", "价值增益默认临时，回合末清除；明确永久的加值与倍率跨回合保留。冷却下限1秒（特别说明除外），仅在瓶中推进，每回合重置，开局触发冷却就绪；运行中新入场或重生等待完整冷却，周期效果等待完整周期。触发成功才进入冷却，概率失败、额度耗尽、护盾拦截不冷却；每X秒周期仍按原周期等待。描述未写冷却的内部防抖、周期计时不显示冷却环。"},
        {"05  消耗与生成", "消耗默认离开拥有牌库与瓶中，记入本回合弃牌堆，不在回合末自动恢复；临时消耗才会回牌库。生成默认永久，只有明确临时生成才在回合末移除。[[banana]]被消耗变为[[banana_peel]]等特例遵循各自说明。"},
        {"06  入瓶计时", "每x秒、过x回合只在瓶中计算，未入瓶牌库不计时。[[banana]]、[[egg]]读取各自的瓶中回合数；[[chicken_keeper]]的每5次刷新永久+1明确在牌库也生效。"},
        {"07  构筑与遗物", "结算后进入物品三选一，可选一件永久加入牌库或跳过；考核达标后还可选择遗物。候选稀有度概率随考核阶段变化；每次考核回合仅物品三选一不出现普通品质，刷新同样生效；遗物不排除普通品质。已拥有的唯一物品与遗物不再作为对应候选。准备重抽与物品刷新使用同一累计池；每次遗物三选一独立免费刷新1次，用完不能再刷，离开即清空。"},
        {"08  考核", "每5回合考核并扣除目标分数，余额保留。目标40/80/140/220/320/450/600/780，之后每阶段×1.3并向上取整到10；不足则结束本局。每次达标另获得1次移除机会，新局0次、可跨回合累计。"},
        {"09  上限与物理", "瓶中上限100件，超出的新生成物按顺序等待入瓶；等待物品不算瓶中物品，回合末回牌库。时间上限99秒。体积、重量默认100%，常规范围50%至200%；物理修改默认永久，特殊物品按自身说明。"},
        {"10  存档", "非摇晃/结算阶段自动保存。运行中退出回退到本回合开始前，包括生成与永久变化。网页刷新可能丢失本地文件，请导出存档码。"},
        {"11  物品目录", "当前98件物品均已实装；仅源表标记屏蔽的物品不进入普通卡池，GM可添加全部98件。分类严格按标签，不按名称或外观推测；士兵与医生保留人类标签。"},
        {"12  主动移除", "新局移除0次，每次考核达标+1次，可累计；[[removal_coin]]结算后成功消耗自身也+1。准备或物品／遗物三选一阶段打开牌库，点选具体编号物品，再二次确认即可永久移除1件。成功才花1次，不进弃牌，不触发被消耗效果，不补抽替代物品，取消／失败不扣次数。"},
    }
    for _, rule in ipairs(rules) do
        scroll:AddChild(UI.Card {width = "100%", gap = 5, padding = 12, backgroundColor = C.background,
            children = {Label(rule[1], 13, C.primary),
                Description {text = rule[2], fontSize = 11.25, fontColor = C.text,
                    onInspect = function(id) self:InspectDefinition(id) end}}})
    end
    panel:AddChild(scroll)
    local sensor = Button("启用／校准手机体感", function() self.actions.sensor() end)
    sensor:SetStyle({width = "100%"})
    panel:AddChild(sensor)
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

--- GM 面板：接受数字编号 1–98 或字符串 id，由 Game:GmAddItem 统一匹配；未实装物品会被拒绝。
function View:OpenGm()
    if Busy(self.game) then return end
    local panel = self:Modal("GM 面板")
    panel:SetStyle({textMotionDisabled = true})
    panel:AddChild(UI.Label {text = "功能一 · 添加物品：输入数字编号 1–98 或字符串 id，全部98件可添加，加入牌库供后续抽取",
        fontSize = 11.25, fontColor = C.textSecondary, whiteSpace = "normal", width = "100%"})
    local message = UI.Label {text = "输入数字或字符串 id；也可点击下方列表“添加”快捷加入",
        fontSize = 10.5, fontColor = C.primary, whiteSpace = "normal", width = "100%"}
    local field = UI.TextField {id = "gmItemId", placeholder = "数字 1–98 或 id，如 1 / apple",
        width = "100%", height = 48, fontSize = 12, fontFamily = "mono", flexGrow = 1, flexBasis = 0,
        onSubmit = function(self_, value)
            local id = value:match("^%s*(%S+)%s*$")
            if not id or id == "" then
                message:SetText("请先输入数字编号 1–98 或字符串 id")
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
            message:SetText("请先输入数字编号 1–98 或字符串 id")
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
    local field = UI.TextField {value = code, width = "100%", height = 54, fontSize = 10,
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
