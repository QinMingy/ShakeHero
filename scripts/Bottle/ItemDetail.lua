-- 牌库与三选一共用的详情版式。UI 管理缩放、裁剪与命中；说明仍走唯一动态文本入口。
local UI = require("urhox-libs/UI")
local Description = require("Bottle.Description")
local Items = require("Bottle.Items")
local Money = require("Bottle.Money")
local Art = require("Bottle.Art")
local C = (require("Bottle.Theme") --[[@as any]]).colors
local Detail = {}
local qualityInk = {
    {224, 224, 211, 255}, {80, 200, 120, 255}, {69, 170, 242, 255},
    {167, 122, 245, 255}, {255, 205, 74, 255},
}
local field = {20, 34, 27, 255}
local recess = {10, 25, 20, 255}

---@class BottleDetailStatIcon : Widget
---@overload fun(props:WidgetProps): BottleDetailStatIcon
local StatIcon = UI.Widget:Extend("BottleDetailStatIcon") --[[@as BottleDetailStatIcon]]
function StatIcon:Render(vg)
    local l = self:GetAbsoluteLayout()
    Art.StatIcon(vg, self.props.kind, l.x + l.w / 2, l.y + l.h / 2, math.min(l.w, l.h) / 2)
end

---@param props table
---@return Panel root
---@return BottleDescription prose
function Detail.Create(props)
    local s, def, prefix = props.scale or 1, props.def, props.prefix
    local rarity = qualityInk[def.rarity] or C.text
    local badge = UI.Label {id = prefix .. "Quality", text = Items.rarityNames[def.rarity],
        fontSize = 11 * s, fontColor = rarity, backgroundColor = recess,
        paddingHorizontal = 8 * s, paddingVertical = 3 * s,
        textMotionDisabled = true, alignSelf = "flex-start"}
    local tags = props.isRelic and "遗物" or Items.TagsText(def)
    local title = UI.Label {id = prefix == "deck" and "deckDetailName" or "draftDetailName",
        text = def.name, fontSize = 24 * s, fontWeight = "bold", fontColor = C.text,
        width = "100%", whiteSpace = "normal", textMotionDisabled = true}
    local prose = Description {id = props.descriptionId, text = props.effect,
        fontSize = 15 * s, fontColor = C.text, onInspect = props.onInspect}
    local stats = props.isRelic and UI.Panel {id = "draftRelicInfo", width = "100%",
        padding = 12 * s, backgroundColor = field, children = {
            UI.Label {text = props.relicStatus or "遗物 · 永久生效", fontSize = 14 * s, fontColor = C.primary,
                textMotionDisabled = true, width = "100%", whiteSpace = "normal"},
        }} or UI.Panel {id = prefix .. "DetailStats", width = "100%", flexDirection = "row",
            alignItems = "center", paddingHorizontal = 12 * s, paddingVertical = 8 * s,
            gap = 10 * s, backgroundColor = field,
            children = {
                StatIcon {kind = "gain", width = 28 * s, height = 28 * s, pointerEvents = "none"},
                UI.Label {text = props.valueCaption or "当前收益", fontSize = 12 * s,
                    fontColor = C.textSecondary, textMotionDisabled = true, flexGrow = 1, flexBasis = 0},
                UI.Label {id = "goldValue", text = Money.Format(props.gold),
                    fontSize = 23 * s, fontColor = C.warning, textMotionDisabled = true,
                    width = 104 * s, height = 38 * s, textAlign = "right", verticalAlign = "middle"},
            }}
    local root = UI.Panel {id = prefix .. "DetailLayout", width = "100%", height = "100%",
        minHeight = 0, padding = 16 * s, gap = 12 * s, children = {
            UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 8 * s,
                children = {
                    UI.Panel {width = 3 * s, height = 15 * s, backgroundColor = C.gold},
                    UI.Label {id = prefix == "deck" and "deckDetailTitle" or "draftTitle",
                        text = props.caption, fontSize = 12 * s, fontColor = C.textSecondary,
                        textMotionDisabled = true, flexGrow = 1, flexBasis = 0},
                    UI.Label {id = prefix .. "DetailMeta", text = props.meta or "", fontSize = 10.5 * s,
                        fontColor = C.textSecondary, textMotionDisabled = true},
                }},
            UI.Panel {id = prefix .. "DetailHero", width = "100%", flexDirection = "row",
                alignItems = "center", gap = 14 * s, children = {
                    UI.Panel {width = 96 * s, height = 96 * s, backgroundColor = recess,
                        alignItems = "center", justifyContent = "center", children = {props.icon}},
                    UI.Panel {flexGrow = 1, flexBasis = 0, minWidth = 0, gap = 6 * s,
                        children = {badge, title,
                            UI.Label {id = prefix .. "DetailTags", text = tags, visible = tags ~= "",
                                fontSize = 12 * s, fontColor = C.textSecondary, whiteSpace = "normal",
                                width = "100%", textMotionDisabled = true}}},
                }},
            stats,
            UI.Panel {id = prefix .. "EffectPanel", width = "100%", flexGrow = 1, flexBasis = 0,
                minHeight = 48 * s, padding = 12 * s, gap = 7 * s, backgroundColor = recess,
                children = {
                    UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 10 * s,
                        children = {
                            UI.Label {text = props.isRelic and "遗物效果" or "物品效果", fontSize = 12 * s, fontColor = C.primary,
                                textMotionDisabled = true},
                            UI.Panel {height = s, flexGrow = 1, backgroundColor = C.secondary},
                        }},
                    UI.ScrollView {id = prefix == "deck" and "deckEffectScroll" or "draftEffectScroll",
                        width = "100%", flexGrow = 1, flexBasis = 0, minHeight = 0,
                        bounces = false, padding = 0, children = {prose}},
                }},
        }}
    return root, prose
end

return Detail
