-- Rules use retained UI for layout/input and the cabinet's existing wood slices.
local UI = require("urhox-libs/UI")
local Sprites = require("Machine.LayeredSprites")

---@type any
local Rules = {}
local ink = {237, 224, 187, 255}
local muted = {209, 188, 149, 255}
local clear = {0, 0, 0, 0}
Rules.iconPath = "image/ui/rules-scroll-v1.png"
Rules.entries = {
    {"01  抽取", "回合开始时，从牌库随机抽取最多20件物品进入瓶中，不足20件时全部入瓶。准备重抽与物品三选一共用累计刷新池；成功时花1次，有次数即可连续重抽，回合开始不重置。特别说明的物品效果可额外入瓶。"},
    {"02  摇晃", "点击开始后进入摇晃阶段，通过拖动瓶子触发物品之间的反应。手机原生端可启用体感，直接摇晃手机；网页预览可用鼠标或触摸拖动。"},
    {"03  结算", "摇晃结束后进入结算，禁止继续摇晃。物品自然下落2秒后，获得等同于物品当前价值的金币，再逐件展示收益。"},
    {"04  价值", "物品在回合内获得的价值加成与倍率默认为临时效果，回合结束后清除；特别说明为永久增加的效果会保留到之后的回合。"},
    {"05  冷却", "物品处于冷却期间，在瓶中会置灰；冷却结束后恢复原色。物品效果注明的冷却才会显示冷却提示，每回合重新计算。"},
    {"06  物品三选一", "每回合结算后有1次物品三选一机会，可选择1件加入牌库或跳过。开局有1次物品刷新机会，此后每完成1回合增加1次；未使用的物品刷新机会可累计。"},
    {"07  遗物三选一", "每次通过考核并完成物品三选一后，会获得1次遗物三选一机会。每组遗物候选有1次独立免费刷新机会，每次重置，不消耗物品刷新次数，也不累计。已拥有的遗物不会重复出现。"},
    {"08  考核", "每经过5天需要完成一次考核。金币达到目标时扣除对应金币，保留余额并继续；金币不足则游戏结束。当前目标与剩余天数会显示在机台上。"},
    {"09  体积与质量", "除特别说明外，物品的体积与质量均有上下限：最低50%，最高200%。"},
    {"10  移除机会", "每次通过考核，获得1次移除机会。在准备或物品三选一阶段，可打开牌库查看物品详情，点击“移除”并确认，消耗1次机会将该物品永久移出牌库。未使用的机会可以保留。"},
}

function Rules.Attach(view, button)
    button:SetText("")
    button.id = "rulesButton"
    ---@type table<NVGContextWrapper, integer>
    local images = {}
    local icon = UI.Widget {id = "rulesScrollIcon", pointerEvents = "none"}
    function icon:Render(vg)
        local handle = images[vg]
        if not handle then
            handle = nvgCreateImage(vg, Rules.iconPath, NVG_IMAGE_NEAREST)
            if handle <= 0 then return end
            images[vg] = handle
        end
        local b = self:GetAbsoluteLayout()
        nvgSave(vg)
        nvgBeginPath(vg)
        nvgRect(vg, b.x, b.y, b.w, b.h)
        nvgFillPaint(vg, nvgImagePattern(vg, b.x, b.y, b.w, b.h, 0, handle, 1))
        nvgFill(vg)
        nvgRestore(vg)
    end
    local destroy = icon.Destroy
    function icon:Destroy()
        for vg, handle in pairs(images) do nvgDeleteImage(vg, handle) end
        images = {}
        destroy(self)
    end
    local caption = UI.Label {id = "rulesCaption", text = "规则", pointerEvents = "none",
        textMotionDisabled = true, textAlign = "center", verticalAlign = "middle", fontColor = ink}
    button:AddChild(icon)
    button:AddChild(caption)
    view.rulesIcon, view.rulesCaption = icon, caption
end

function Rules.Layout(view, button)
    local s = view.machineSkin and view.machineSkin.scale or 1
    button:SetStyle({position = "absolute", left = 348*s, top = 10*s, width = 44*s, height = 58*s,
        padding = 0, backgroundColor = clear, borderWidth = 0, boxShadow = false,
        hoverBoxShadow = false, pressedBoxShadow = false, disabledBoxShadow = false,
        hoverBackgroundColor = {224, 215, 181, 20}, pressedBackgroundColor = {224, 215, 181, 36}})
    view.rulesIcon:SetStyle({position = "absolute", left = 4*s, top = 0, width = 36*s, height = 36*s})
    view.rulesCaption:SetStyle({position = "absolute", left = 0, top = 36*s, width = 44*s,
        height = 20*s, fontSize = 11*s})
end

function Rules.Open(view)
    local panel = view:Modal("玩法规则")
    panel.id = "rulesPanel"
    local s = view.machineSkin and view.machineSkin.scale or 1
    panel:SetStyle({height = "92%", padding = 16*s, gap = 10*s,
        backgroundColor = clear, borderWidth = 0, boxShadow = false})
    local sprites = Sprites.New()
    function panel:Render(vg)
        local b = self:GetAbsoluteLayout()
        nvgSave(vg)
        nvgShapeAntiAlias(vg, 0)
        sprites:Panel(vg, "wood", b.x, b.y, b.w, b.h, s)
        nvgRestore(vg)
    end
    local destroy = panel.Destroy
    function panel:Destroy() sprites:Dispose(); destroy(self) end
    local scroll = UI.ScrollView {id = "rulesScroll", width = "100%", flexGrow = 1, flexBasis = 0,
        minHeight = 0, gap = 12*s, padding = 4*s}
    for index, rule in ipairs(Rules.entries) do
        scroll:AddChild(UI.Panel {id = "rule"..index, width = "100%", flexShrink = 0, gap = 4*s,
            children = {
                UI.Label {text = rule[1], fontSize = 14*s, fontColor = ink, fontWeight = "bold",
                    textMotionDisabled = true, pointerEvents = "none"},
                UI.Label {text = rule[2], width = "100%", whiteSpace = "normal", fontSize = 11.25*s,
                    fontColor = muted, textMotionDisabled = true, pointerEvents = "none"},
            }})
    end
    panel:AddChild(scroll)
    return panel
end

return Rules
