-- UI与场景独立调色；物品像素直接提交原色，不对完整合成帧置灰。
local UI = require("urhox-libs/UI")
local fillColor = nvgFillColor
---@type any
local Palette = {saturation = .62}

---@param color NVGcolor
---@return NVGcolor
function Palette.Color(color)
    local luma = color.r * .2126 + color.g * .7152 + color.b * .0722
    local s = Palette.saturation
    return nvgRGBAf(luma + (color.r - luma) * s, luma + (color.g - luma) * s,
        luma + (color.b - luma) * s, color.a)
end

-- 只供Art.Item的像素使用；冷却灰暗已由Art自身处理，不豁免卡面或说明文字。
---@param vg NVGContextWrapper
---@param color NVGcolor
function Palette.FillItem(vg, color)
    fillColor(vg, color)
end

function Palette.Init()
    if Palette.installed then return end
    Palette.installed = true
    local render = UI.Render
    UI.Render = function(...)
        local vg = UI.GetNVGContext()
        local fill, stroke, fillPaint, strokePaint = nvgFillColor, nvgStrokeColor, nvgFillPaint, nvgStrokePaint
        local function paint(submit, ctx, value)
            -- 场景及浮尘RTT已在材质中调色，最终RTT内含原色物品，均不能再处理。
            if ctx ~= vg or value.image ~= 0 then return submit(ctx, value) end
            local inner, outer = value.innerColor, value.outerColor
            value.innerColor, value.outerColor = Palette.Color(inner), Palette.Color(outer)
            local ok, result = pcall(submit, ctx, value)
            value.innerColor, value.outerColor = inner, outer
            if not ok then error(result, 0) end
            return result
        end
        nvgFillColor = function(ctx, color)
            return fill(ctx, ctx == vg and Palette.Color(color) or color)
        end
        nvgStrokeColor = function(ctx, color)
            return stroke(ctx, ctx == vg and Palette.Color(color) or color)
        end
        nvgFillPaint = function(ctx, value) return paint(fillPaint, ctx, value) end
        nvgStrokePaint = function(ctx, value) return paint(strokePaint, ctx, value) end
        local ok, result = pcall(render, ...)
        nvgFillColor, nvgStrokeColor, nvgFillPaint, nvgStrokePaint = fill, stroke, fillPaint, strokePaint
        if not ok then error(result, 0) end
        return result
    end
    print("[机台配色] UI低饱和，物品保留原色")
end

return Palette
