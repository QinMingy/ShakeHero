-- 共享物品说明：只解析 Items.effect 的 @ / [[id]] / 换行模板。
-- RichText.RegisterTag 仅能扩展解析，Render 没有自定义 inline drawer，item 固定绘制名称/emoji。
-- Yoga Lua 绑定没有 SetMeasureFunc；沿用 Label 的 auto-height 模式，通过 SetHeight 同步实际测量。
-- 所有绘制都在 Widget.Render 内，复用 UI 的帧、字体、DPR 和 ScrollView 裁剪。
local UI = require("urhox-libs/UI")
local Items = require("Bottle.Items")
local Art = require("Bottle.Art")
local TextMotion = require("Bottle.TextMotion")
local theme = require("Bottle.Theme") --[[@as {colors:table<string, RGBAColor>}]]
local C = theme.colors

---@alias BottleDescriptionToken {kind:string,text:string,itemId:string,tone?:string}
---@alias BottleDescriptionRun {kind:string,text:string,itemId:string,x:number,y:number,w:number,h:number,index:integer,order?:number,tone?:string}

---@class BottleDescription : Widget
---@field tokens BottleDescriptionToken[]
---@field runs BottleDescriptionRun[]
---@field plainText string
---@field measuredWidth number
---@field contentHeight number
---@field measuredFont number
---@field measuredFace string
---@field fontVersion number
---@field measuredScale number
---@field pressId number
---@field pressIndex integer
---@field pressX number
---@field pressY number
---@field clickMoved boolean
---@field revealElapsed number
---@field wasDisplayed boolean
---@overload fun(props:WidgetProps): BottleDescription
local Description = UI.Widget:Extend("BottleDescription") --[[@as BottleDescription]]

function Description:Init(props)
    props.fontSize = props.fontSize or 12
    props.fontColor = props.fontColor or C.textSecondary
    props.width = props.width or "100%"
    props.flexShrink = 0 -- 不压缩内容高度：外层 ScrollView 负责滚动，不截断文字。
    props.pointerEvents = "auto"
    UI.Widget.Init(self, props)
    self.tokens, self.runs = {}, {}
    self.plainText = ""
    self.measuredWidth, self.contentHeight = -1, 0
    self.measuredFont, self.measuredFace = -1, ""
    self.fontVersion, self.measuredScale = -1, -1
    self.pressId, self.pressIndex = -1, 0
    self.pressX, self.pressY, self.clickMoved = 0, 0, false
    self.revealElapsed, self.wasDisplayed = 0, false
    self:SetText(props.text or "")
end

---@param text string
function Description:SetText(text)
    if self.props.text == text and #self.tokens > 0 then return end
    self.props.text = text
    self:RestartReveal()
    self.tokens, self.runs = {}, {}
    local plain = {}
    local pos = 1
    while pos <= #text do
        local char = text:sub(pos, pos)
        if char == "@" then
            self.tokens[#self.tokens + 1] = {kind = "gain", text = "", itemId = ""}
            pos = pos + 1
        elseif text:sub(pos, pos + 1) == "[[" then
            local finish = text:find("]]", pos + 2, true)
            if finish then
                local id = text:sub(pos + 2, finish - 1)
                local def = Items.byId[id]
                if def then
                    self.tokens[#self.tokens + 1] = {kind = "item", text = "", itemId = id}
                    plain[#plain + 1] = def.name
                else
                    -- 无效引用不显示 ID；也不把未知 ID 交给 Art 的默认苹果绘制。
                    self.tokens[#self.tokens + 1] = {kind = "text", text = "未知物品", itemId = ""}
                    plain[#plain + 1] = "未知物品"
                end
                pos = finish + 2
            else
                pos = #text + 1 -- 不向屏幕泄漏未闭合的模板标记或其内部 ID。
            end
        elseif char == "\n" then
            self.tokens[#self.tokens + 1] = {kind = "break", text = "", itemId = ""}
            plain[#plain + 1] = "\n"
            pos = pos + 1
        else
            -- 按完整 UTF-8 字符拆分，中文可在任意字间换行，绝不截断字节。
            local nextPos = utf8.offset(text, 2, pos) or (#text + 1)
            local glyph = text:sub(pos, nextPos - 1)
            self.tokens[#self.tokens + 1] = {kind = "text", text = glyph, itemId = ""}
            plain[#plain + 1] = glyph
            pos = nextPos
        end
    end
    self.plainText = table.concat(plain)
    -- Numerical ranges/probabilities/multipliers retain their color after the flash.
    for i, token in ipairs(self.tokens) do
        if token.kind == "text" and token.text:match("%d") then
            token.tone = "number"
            local first, last = i, i
            while first > 1 and self.tokens[first - 1].kind == "text"
                and self.tokens[first - 1].text:match("^[%d%.%+%-×÷]$") do first = first - 1 end
            while last < #self.tokens and self.tokens[last + 1].kind == "text"
                and self.tokens[last + 1].text:match("^[%d%.%%%-]$") do last = last + 1 end
            local tone = self.tokens[last].text == "%" and "chance"
                or (first > 1 and self.tokens[first - 1].text == "×") and "multiplier" or "number"
            for j = first, last do self.tokens[j].tone = tone end
        end
    end
    self.measuredWidth = -1
    self.pressIndex = 0
    self:Measure(math.max(1, self:GetLayout().w))
end

function Description:RestartReveal()
    self.revealElapsed, self.wasDisplayed = 0, false
end

-- 保留旧 detailEffect:GetText() 测试接口；返回可读语义文本，不包含 @、[[...]] 或 ID。
-- 物品名称仅在此查询接口中展开，实际 Render 始终绘制对应 Art.Item。
---@return string
function Description:GetText()
    return self.plainText
end

---@return BottleDescriptionToken[]
function Description:GetSegments()
    return self.tokens
end

-- 布局/渲染/点击共享这一份 run。坐标是 Widget 内的基准像素，不缓存屏幕位置。
---@param width number
---@return number height
function Description:Measure(width)
    width = math.max(1, width)
    local font = UI.Theme.FontSize(self.props.fontSize)
    local face = UI.Theme.FontFace(self.props.fontFamily or "sans", "normal")
    local version, scale = UI.GetFontVersion(), UI.Theme.GetScale()
    if self.measuredWidth == width and self.measuredFont == font and self.measuredFace == face
        and self.fontVersion == version and self.measuredScale == scale then return self.contentHeight end
    self.measuredWidth, self.measuredFont, self.measuredFace = width, font, face
    self.fontVersion, self.measuredScale = version, scale
    self.runs = {}
    local textHeight = math.ceil(font * 1.35)
    local itemSize, gainSize = math.max(32, math.ceil(font * 1.5)), math.max(24, math.ceil(font * 1.3))
    ---@type number
    local x = 0
    ---@type number
    local y = 0
    local rowHeight, rowStart = textHeight, 1
    ---@type table<string, number>
    local glyphWidths = {}
    local function FinishRow(paragraph)
        for i = rowStart, #self.runs do
            local run = self.runs[i]
            run.y = y + (rowHeight - run.h) / 2
        end
        y = y + rowHeight + (paragraph and 6 or 4)
        x, rowHeight, rowStart = 0, textHeight, #self.runs + 1
    end
    for index, token in ipairs(self.tokens) do
        if token.kind == "break" then
            FinishRow(true)
        else
            local w, h = 0, textHeight
            if token.kind == "gain" then w, h = gainSize, gainSize
            elseif token.kind == "item" then w, h = itemSize, itemSize
            else
                local measured = glyphWidths[token.text]
                if not measured then
                    measured = UI.MeasureTextWidth(token.text, font, face, 0)
                    -- 初始化时字体资源尚未到达：之后 fontVersion 变化会重新测量。
                    if measured <= 0 then measured = token.text == " " and font * .35 or font end
                    glyphWidths[token.text] = measured
                end
                w = measured
            end
            if x > 0 and x + w > width then FinishRow(false) end
            -- 极窄容器仍能容纳一个图标；不缩小正文/触摸目标来掩盖布局问题。
            self.runs[#self.runs + 1] = {kind = token.kind, text = token.text, itemId = token.itemId,
                x = x, y = y, w = w, h = h, index = index, order = #self.runs + 1, tone = token.tone}
            x, rowHeight = x + w, math.max(rowHeight, h)
        end
    end
    for i = rowStart, #self.runs do
        local run = self.runs[i]
        run.y = y + (rowHeight - run.h) / 2
    end
    self.contentHeight = math.ceil(y + rowHeight + 2)
    self:SetHeight(self.contentHeight)
    return self.contentHeight
end

function Description:Update(dt)
    self:Measure(self:GetLayout().w)
    local displayed = TextMotion.IsDisplayed(self)
    if displayed then
        if not self.wasDisplayed then self.revealElapsed = 0 end
        self.revealElapsed = self.revealElapsed + math.max(0, dt)
    end
    self.wasDisplayed = displayed
end

---@param vg NVGContextWrapper
function Description:Render(vg)
    local l = self:GetAbsoluteLayout()
    if l.w <= 0 or l.h <= 0 then return end
    self:Measure(l.w)
    nvgSave(vg)
    nvgFontFace(vg, self.measuredFace)
    nvgFontSize(vg, self.measuredFont)
    nvgTextLetterSpacing(vg, 0)
    nvgTextAlign(vg, math.floor(NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE))
    local color = self.props.fontColor --[[@as RGBAColor]]
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    for _, run in ipairs(self.runs) do
        local order = run.order or 1
        local alpha, rise, age = TextMotion.Appearance(self.revealElapsed, order)
        if alpha > 0 then
            local x = l.x + run.x
            local y = l.y + run.y + TextMotion.Offset(order, self.measuredFont) + rise * self.measuredFont * .08
            nvgSave(vg)
            nvgGlobalAlpha(vg, alpha)
            if run.kind == "gain" then
                Art.StatIcon(vg, "gain", x + run.w / 2, y + run.h / 2, run.w / 2)
            elseif run.kind == "item" then
                -- 保留整个 32px 方框的点击范围；长条培根内收绘制，避免压住相邻正文。
                local radius = run.w * .38
                local extent = Art.ItemExtent(run.itemId, radius, 0)
                local fittedRadius = extent > radius and radius * radius / extent or radius
                Art.Item(vg, run.itemId, x + run.w / 2, y + run.h / 2, fittedRadius)
            else
                local r, g, b = TextMotion.Ink(color, age, run.tone or "text")
                nvgFillColor(vg, nvgRGBA(r, g, b, color[4] or 255))
                nvgText(vg, x, y + run.h / 2, run.text)
            end
            nvgRestore(vg)
        end
    end
    nvgRestore(vg)
end

-- 提供稳定的屏幕命中区域，含父 ScrollView 的滚动偏移；headless 可直接取中心模拟点击。
---@return BottleDescriptionRun[]
function Description:GetLinkBounds()
    local l = self:GetAbsoluteLayoutForHitTest()
    self:Measure(l.w)
    local result = {}
    for _, run in ipairs(self.runs) do
        local alpha = TextMotion.Appearance(self.revealElapsed, run.order or 1)
        if run.kind == "item" and alpha >= 1 then
            result[#result + 1] = {kind = run.kind, text = "", itemId = run.itemId,
                x = l.x + run.x, y = l.y + run.y, w = run.w, h = run.h, index = run.index}
        end
    end
    return result
end

---@param x number
---@param y number
---@return integer
function Description:ItemAt(x, y)
    for _, bounds in ipairs(self:GetLinkBounds()) do
        if x >= bounds.x and x <= bounds.x + bounds.w and y >= bounds.y and y <= bounds.y + bounds.h then
            return bounds.index
        end
    end
    return 0
end

---@param event PointerEvent
function Description:OnPointerDown(event)
    self.pressId = event.pointerId
    self.pressX, self.pressY, self.clickMoved = event.x, event.y, false
    self.pressIndex = event.isPrimary and event:IsPrimaryButton() and self:ItemAt(event.x, event.y) or 0
    UI.Widget.OnPointerDown(self, event) -- 允许 ScrollView 接管拖动，不冒泡点击。
end

---@param event PointerEvent
function Description:OnPointerMove(event)
    if event.pointerId == self.pressId then
        local dx, dy = event.x - self.pressX, event.y - self.pressY
        if dx * dx + dy * dy > 64 then self.clickMoved = true end
    end
    UI.Widget.OnPointerMove(self, event)
end

---@param event PointerEvent
function Description:OnPointerUp(event)
    self:OnPointerMove(event)
    UI.Widget.OnPointerUp(self, event)
end

---@param event PointerEvent
function Description:OnPointerCancel(event)
    if event.pointerId == self.pressId then self.pressIndex = 0; self.clickMoved = true end
    UI.Widget.OnPointerCancel(self, event)
end

---@param event PointerEvent?
function Description:OnClick(event)
    if event then event:StopPropagation() end
    if not event or not event:IsPrimaryButton() or event.pointerId ~= self.pressId or self.clickMoved then return end
    local index = self:ItemAt(event.x, event.y)
    if index == 0 or index ~= self.pressIndex then return end
    self.pressIndex = 0 -- 一次按下只激活一次，不在递归引用中重复开层。
    local token = self.tokens[index]
    if token and self.props.onInspect then self.props.onInspect(token.itemId) end
end

---@class BottleDefinitionPopup
---@field overlay Panel
---@field title Label
---@field effect BottleDescription
---@field scroll ScrollView

-- 只创建一次独立弹层，切换引用仅更新现有控件，避免递归创建 Modal/字体/Yoga 节点。
---@param icon Widget
---@param stats Panel
---@param close Button
---@param inspect fun(id:string)
---@param dismiss function
---@return BottleDefinitionPopup
function Description.CreatePopup(icon, stats, close, inspect, dismiss)
    local title = UI.Label {id = "definitionTitle", text = "", fontSize = 15, fontWeight = "bold",
        whiteSpace = "normal", width = "100%", fontColor = C.text}
    title:SetStyle({textReveal = true})
    local effect = Description {id = "definitionDescription", text = "", onInspect = inspect}
    -- 关闭按钮固定，定义元数据与完整描述一起滚动；横屏/小屏也不挤掉关闭入口。
    local scroll = UI.ScrollView {id = "definitionScroll", width = "100%", flexGrow = 1,
        flexBasis = 0, minHeight = 32, gap = 12, padding = 4, children = {
            UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10, children = {
                icon, UI.Panel {flexGrow = 1, flexBasis = 0, gap = 4, children = {title, stats}},
            }},
            effect,
        }}
    local function Stop(widget, event)
        if event then event:StopPropagation() end
    end
    local card = UI.Card {id = "definitionCard", width = "100%", maxWidth = 420,
        height = "80%", maxHeight = 480, padding = 14, gap = 12, backgroundColor = C.surface,
        borderColor = C.border, overflow = "hidden", onClick = Stop, children = {
            UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 8, children = {
                UI.Panel {flexGrow = 1, flexBasis = 0, children = {
                    UI.Label {text = "物品信息", fontSize = 16, fontWeight = "bold",
                        width = "100%", whiteSpace = "normal", fontColor = C.primary},
                }}, close,
            }},
            scroll,
        }}
    local overlay = UI.Panel {id = "definitionModal", position = "absolute", left = 0, top = 0,
        right = 0, bottom = 0, visible = false, zIndex = 40, backgroundColor = C.overlay,
        pointerEvents = "auto", onClick = function(widget, event)
            if event then event:StopPropagation() end
            if not event or (event.target == widget and event:IsPrimaryButton()) then dismiss() end
        end,
        onPointerDown = function(event) event:StopPropagation() end,
        children = {UI.SafeAreaView {width = "100%", height = "100%", nativeMenuInset = true,
            pointerEvents = "box-none", padding = 12, alignItems = "center", justifyContent = "center",
            children = {card}}}}
    return {overlay = overlay, title = title, effect = effect, scroll = scroll}
end

return Description
