-- Text-only motion: Yoga boxes, button faces and pointer targets stay fixed.
-- Reference recordings: 20261015003231 / 20261015003610.
local UI = require("urhox-libs/UI")
---@type any
local Motion = {time = 0, period = 2.7, phaseStep = .48, revealStep = .012, settleTime = .14}
local EMPTY, DEFAULT_INK = {}, {224,215,181,255}

---@param index number
---@param fontSize number Actual NanoVG size in UI base pixels, before DPR scaling.
---@return number
function Motion.Offset(index, fontSize)
    return math.sin(Motion.time * math.pi * 2 / Motion.period - (index - 1) * Motion.phaseStep)
        * math.min(3, math.max(.6, fontSize * .065))
end

---@param elapsed number
---@param order number
---@return number alpha
---@return number rise
---@return number age
function Motion.Appearance(elapsed, order)
    local age = elapsed - (order - 1) * Motion.revealStep
    if age < 0 then return 0, 0, age end
    local progress = math.min(1, age / .035)
    return progress, -(1 - progress) ^ 2, age
end

---@param base RGBAColor
---@param age number
---@param tone string
---@return number r
---@return number g
---@return number b
function Motion.Ink(base, age, tone)
    local r, g, b = base[1], base[2], base[3]
    if tone == "text" then
        r, g, b = r * .35 + 197 * .65, g * .35 + 159 * .65, b * .35 + 102 * .65
    end
    if tone == "number" then r, g, b = 139, 193, 109
    elseif tone == "chance" then r, g, b = 230, 179, 81
    elseif tone == "multiplier" then r, g, b = 100, 177, 206 end
    -- Fresh glyphs flash pale, settle, then retain a gentle breathing tint.
    local flash = math.max(0, 1 - age / Motion.settleTime)
    local pulse = (.5 + .5 * math.sin(Motion.time * 1.8 - age * .3)) * .045
    local mix = math.min(1, flash + pulse)
    return math.floor(r + (244 - r) * mix), math.floor(g + (235 - g) * mix),
        math.floor(b + (195 - b) * mix)
end

---@param widget Widget
---@return boolean
function Motion.IsDisplayed(widget)
    ---@type Widget?
    local current = widget
    while current do
        if not current:IsVisible() then return false end
        current = current.parent
    end
    return true
end

-- Reuse Label/Button's original fitting, wrapping, shadow, state and clipping.
-- Only their synchronous text draw calls are adapted. The engine globals are
-- restored even if Render fails; no replacement survives this Render scope.
---@param widget any
---@param render function
local function CreateRender(widget, render)
    ---@type any
    local vg = nil
    local text, box, align, size = nvgText, nvgTextBox, nvgTextAlign, nvgFontSize
    local alignment, fontSize = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 16
    local cache = widget.textMotionCache or {}
    widget.textMotionCache = cache
    cache.glyphs, cache.numberRanges = cache.glyphs or {}, cache.numberRanges or {}
    -- 每个widget只构造这一组包装器；Render只改当前上下文和原函数引用。
    local alignWrapper = function(ctx, value)
        if ctx == vg then alignment = value end
        return align(ctx, value)
    end
    local sizeWrapper = function(ctx, value)
        if ctx == vg then fontSize = value end
        return size(ctx, value)
    end
    local textWrapper = function(ctx, x, y, value, finish, autoFit)
        if ctx ~= vg or type(value) ~= "string" or value == "" then
            return text(ctx, x, y, value, finish, autoFit)
        end
        -- The bundled local Runtime may ship the pre-GetProps UI library.
        local props = widget.GetProps and widget:GetProps() or widget.props or EMPTY
        local family, weight, spacing = props.fontFamily or "sans", props.fontWeight or "normal", props.letterSpacing or 0
        local version, scale = UI.GetFontVersion(), UI.GetScale()
        if cache.value ~= value or cache.fontSize ~= fontSize or cache.family ~= family or cache.weight ~= weight
            or cache.spacing ~= spacing or cache.version ~= version or cache.scale ~= scale then
            cache.value, cache.fontSize, cache.family, cache.weight = value, fontSize, family, weight
            cache.spacing, cache.version, cache.scale = spacing, version, scale
            nvgSave(ctx)
            align(ctx, NVG_ALIGN_LEFT | NVG_ALIGN_MIDDLE)
            local width, bounds = nvgTextBounds(ctx, 0, 0, value, nil, nil, false)
            width = width or 0
            cache.width, cache.visualCenter = width, bounds and (bounds[1] + bounds[3]) / 2 or width / 2
            local prefix = ""
            -- 按钮次数、标题中的编号等与文案混排时，只固定完整数值片段。
            -- 描述正文由 Bottle.Description 绘制，仍作为文案整体保留浮动。
            local numberRanges, rangeCount = cache.numberRanges, 0
            local cursor = 1
            while cursor <= #value do
                local first, last = value:find("[%d%+%-%.%%/eE]+", cursor)
                if not first then break end
                if value:sub(first, last):find("%d") then
                    rangeCount = rangeCount + 1
                    local range = numberRanges[rangeCount] or {}
                    range.first, range.last = first, last
                    numberRanges[rangeCount] = range
                end
                cursor = last + 1
            end
            local glyphCount = 0
            for position, code in utf8.codes(value) do
                local glyph = utf8.char(code)
                local advance = prefix == "" and 0 or nvgTextBounds(ctx, 0, 0, prefix, nil, nil, false)
                local fixed = false
                for index = 1, rangeCount do
                    local range = numberRanges[index]
                    if position >= range.first and position <= range.last then fixed = true; break end
                end
                glyphCount = glyphCount + 1
                local info = cache.glyphs[glyphCount] or {}
                info.text, info.x, info.fixed = glyph, advance, fixed
                cache.glyphs[glyphCount] = info
                prefix = prefix .. glyph
            end
            cache.glyphCount = glyphCount
            nvgRestore(ctx)
        end
        local left = x
        if alignment & NVG_ALIGN_CENTER_VISUAL ~= 0 then left = x - cache.visualCenter
        elseif alignment & NVG_ALIGN_CENTER ~= 0 then left = x - cache.width / 2
        elseif alignment & NVG_ALIGN_RIGHT ~= 0 then left = x - cache.width end
        nvgSave(ctx)
        align(ctx, (alignment & (NVG_ALIGN_TOP | NVG_ALIGN_MIDDLE | NVG_ALIGN_BOTTOM | NVG_ALIGN_BASELINE)) | NVG_ALIGN_LEFT)
        for index = 1, cache.glyphCount do
            local glyph = cache.glyphs[index]
            local alpha, rise, age = 1, 0, 1
            if props.textReveal then
                alpha, rise, age = Motion.Appearance(Motion.time - (widget.textMotionStarted or Motion.time), index)
            end
            if alpha > 0 then
                nvgSave(ctx)
                if props.textReveal then
                    nvgGlobalAlpha(ctx, alpha)
                    local r, g, b = Motion.Ink(props.fontColor or DEFAULT_INK, age, "text")
                    nvgFillColor(ctx, nvgRGBA(r, g, b, 255))
                end
                local motion = glyph.fixed and 0 or Motion.Offset(index, fontSize) + rise * fontSize * .08
                text(ctx, left + glyph.x, y + motion, glyph.text, nil, false)
                nvgRestore(ctx)
            end
        end
        nvgRestore(ctx)
        return x + cache.width
    end
    -- The engine retains ownership of multiline word wrapping and line metrics.
    -- Each wrapped block floats without changing its measured height.
    local boxWrapper = function(ctx, x, y, width, value, finish, autoFit)
        local props = widget.GetProps and widget:GetProps() or widget.props or EMPTY
        local fixed = type(value) == "string" and value:find("%d") ~= nil
        if ctx == vg and props.textReveal and type(value) == "string" then
            local family, weight, spacing = props.fontFamily or "sans", props.fontWeight or "normal", props.letterSpacing or 0
            local version, scale = UI.GetFontVersion(), UI.GetScale()
            if cache.boxValue ~= value or cache.boxSize ~= fontSize or cache.boxFamily ~= family
                or cache.boxWeight ~= weight or cache.boxSpacing ~= spacing or cache.boxVersion ~= version or cache.boxScale ~= scale then
                cache.boxAdvance = nvgTextBounds(ctx, 0, 0, value, nil, nil, false) or 0
                cache.boxValue, cache.boxSize, cache.boxFamily = value, fontSize, family
                cache.boxWeight, cache.boxSpacing, cache.boxVersion, cache.boxScale = weight, spacing, version, scale
            end
            local advance = cache.boxAdvance
            if advance <= width then
                -- Names use whiteSpace=normal even when they fit on one line.
                local anchor = x
                if alignment & NVG_ALIGN_CENTER ~= 0 then anchor = x + width / 2
                elseif alignment & NVG_ALIGN_RIGHT ~= 0 then anchor = x + width end
                return textWrapper(ctx, anchor, y, value, finish, false)
            end
            -- Keep the engine's full-text layout; only the drawn prefix changes.
            local elapsed = Motion.time - (widget.textMotionStarted or Motion.time)
            local count = math.max(0, math.floor(elapsed / Motion.revealStep) + 1)
            local stop = utf8.offset(value, count + 1) or (#value + 1)
            value = value:sub(1, stop - 1)
        end
        -- 多行统计文案保留引擎换行；整块固定，避免数值随段落一起漂移。
        local motion = ctx == vg and not fixed and Motion.Offset(1, fontSize) or 0
        return box(ctx, x, y + motion, width, value, finish, autoFit)
    end
    return function(w, context)
        if w.textMotionDisabled then return render(w, context) end
        vg = context
        text, box, align, size = nvgText, nvgTextBox, nvgTextAlign, nvgFontSize
        alignment, fontSize = NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE, 16
        nvgText, nvgTextBox, nvgTextAlign, nvgFontSize = textWrapper, boxWrapper, alignWrapper, sizeWrapper
        local ok, err = pcall(render, w, context)
        nvgText, nvgTextBox, nvgTextAlign, nvgFontSize = text, box, align, size
        if not ok then error(err, 0) end
    end
end

-- 输入值是数据，保持光标、选区和文字的基线一致，不参与装饰浮动。
local classes = {Label = true, Button = true, RichText = true, Toast = true}
---@param widget any
---@param disabled boolean?
function Motion.AttachTree(widget, disabled)
    if not widget then return end
    local skip = disabled or widget.props.textMotionDisabled == true
    widget.textMotionDisabled = skip
    if widget.props.textReveal and not skip then
        local displayed = Motion.IsDisplayed(widget)
        if (displayed and not widget.textMotionWasDisplayed) or widget.textMotionLastText ~= widget.props.text then
            widget.textMotionStarted = Motion.time
            widget.textMotionLastText = widget.props.text
        end
        widget.textMotionWasDisplayed = displayed
    end
    if classes[widget._className] and not widget.textMotionAttached then
        local render = widget.Render
        widget.Render = CreateRender(widget, render)
        widget.textMotionAttached = true
    end
    for _, child in ipairs(widget:GetChildren()) do Motion.AttachTree(child, skip) end
end

---@param dt number
function Motion.Update(dt)
    Motion.time = Motion.time + math.max(0, dt)
    Motion.AttachTree(UI.GetRoot())
    -- Toast is rendered as a global component rather than a root child.
    Motion.AttachTree(UI.Toast.GetGlobal())
end

return Motion
