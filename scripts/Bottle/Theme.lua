-- 机台主题：用同一套非像素中文字形覆盖正文、数字和展示文字。
local UI = require("urhox-libs/UI")

local BUTTON_SHADOW = {
    {x = 3, y = 3, blur = 0, color = {12, 14, 12, 204}},
    {x = -1, y = -1, blur = 0, color = {181, 185, 151, 48}},
}
local DROP_SHADOW = {{x = 4, y = 4, blur = 0, color = {12, 14, 12, 204}}}

---@type any
local theme = UI.Theme.ExtendTheme(UI.Theme.defaultTheme, {
    fonts = {
        {family = "sans", weights = {
            normal = "Fonts/SmileySans-Oblique.ttf",
            bold = "Fonts/SmileySans-Oblique.ttf",
        }},
        {family = "mono", weights = {normal = "Fonts/SmileySans-Oblique.ttf"}},
        {family = "display", weights = {normal = "Fonts/SmileySans-Oblique.ttf"}},
        {family = "pixel", weights = {normal = "Fonts/m6x11.ttf"}},
    },
    colors = {
        -- Neutral popup ink stays readable under all three cabinet moods.
        primary = {154, 164, 115, 255}, primaryHover = {178, 187, 131, 255},
        primaryPressed = {113, 124, 84, 255},
        secondary = {108, 116, 94, 255}, secondaryHover = {135, 143, 108, 255},
        secondaryPressed = {84, 94, 74, 255},
        background = {18, 22, 19, 255}, surface = {39, 44, 38, 255},
        surfaceHover = {55, 62, 51, 255}, surfaceAlt = {31, 37, 32, 255},
        text = {224, 215, 181, 255}, textSecondary = {161, 166, 135, 255},
        textDisabled = {101, 110, 91, 255}, border = {94, 96, 97, 255},
        borderFocus = {153, 155, 156, 255}, disabled = {49, 56, 47, 255},
        disabledText = {109, 118, 99, 255}, disabledBorder = {62, 64, 65, 255},
        success = {127, 161, 112, 255}, successHover = {151, 184, 130, 255},
        warning = {211, 177, 96, 255}, warningHover = {238, 197, 100, 255},
        error = {181, 78, 68, 255}, errorHover = {220, 94, 75, 255},
        info = {154, 164, 115, 255}, overlay = {9, 13, 11, 210},
        tableDark = {12, 39, 40, 255}, tableMid = {26, 72, 67, 255},
        tableLight = {48, 96, 82, 255}, paper = {218, 211, 177, 255},
        paperInk = {30, 42, 39, 255}, red = {181, 78, 68, 255},
        blue = {106, 144, 132, 255}, gold = {211, 177, 96, 255}, ink = {21,28,22,255},
    },
    spacing = {xs = 4, sm = 8, md = 12, lg = 16, xl = 24, xxl = 32},
    radius = {none = 0, sm = 2, md = 2, lg = 4, xl = 4, full = 0},
    componentDefaults = {borderRadius = 0},
    components = {
        Button = {
            borderColor = {94, 96, 97, 255},
            borderWidth = 2, boxShadow = BUTTON_SHADOW, fontWeight = "bold",
            paddingHorizontal = 12,
            pressedBoxShadow = {{x = 1, y = 1, blur = 0, color = {10, 10, 26, 204}}},
            disabledBoxShadow = false,
        },
        Card = {borderWidth = 2, borderColor = {94, 96, 97, 255}, boxShadow = DROP_SHADOW},
        ProgressBar = {height = 12, borderWidth = 2, borderColor = {94, 96, 97, 255}},
        TextField = {borderWidth = 2, borderColor = {94, 96, 97, 255},
            backgroundColor = {18, 26, 21, 255}},
        Label = {fontSize = 10.5},
        Toast = {
            borderWidth = 2, borderColor = {94, 96, 97, 255},
            boxShadow = {{x = 3, y = 3, blur = 0, color = {5, 14, 16, 204}}},
            accentBarHeight = 32, accentBarWidth = 4, accentBarInset = 12, showIcon = false,
        },
        Modal = {borderWidth = 2, borderColor = {94, 96, 97, 255}, boxShadow = DROP_SHADOW},
    },
})

-- ExtendTheme 会保留基础主题的组件圆角；统一清除，避免覆盖全局直角默认值。
for _, component in pairs(theme.components) do component.borderRadius = 0 end

return theme
