-- A save code keeps its complete editable value, but only its visible glyphs
-- are rendered. The standard TextField measures every growing prefix per frame.
local UI = require("urhox-libs/UI")
local Theme = require("urhox-libs/UI/Core/Theme")
local TextField = UI.TextField

---@class BottleSaveCodeField : TextField
---@overload fun(props?: TextFieldProps): BottleSaveCodeField
---@field new fun(self, props?: TextFieldProps): BottleSaveCodeField
---@field saveValue_ string?
---@field saveBytes_ integer[]
---@field saveChars_ string[]
---@field savePositionsValue_ string?
---@field saveContext_ NVGContextWrapper?
---@field saveFace_ string?
---@field saveSize_ number?
---@field saveFontVersion_ number?
---@field saveScale_ number?
---@field savePassword_ boolean?
---@field saveAdvances_ table<string, number?>
---@field savePairs_ table<string, number?>
---@field charPositions_ number[]
---@field textAreaX_ number
---@field scrollX_ number
---@field state {focused: boolean, cursorPos: number, cursorBlink: boolean, selectionStart: number?, selectionEnd: number?, scrollX: number}
local Field = TextField:Extend("BottleSaveCodeField")

---@param values number[]
---@param target number
---@return integer
local function lowerBound(values, target)
    local lo, hi = 1, #values + 1
    while lo < hi do
        local mid = (lo + hi) // 2
        if values[mid] < target then lo = mid + 1 else hi = mid end
    end
    return lo
end

---@param props TextFieldProps?
function Field:Init(props)
    TextField.Init(self, props)
    self.saveBytes_, self.saveChars_ = {1}, {}
    self.saveAdvances_, self.savePairs_ = {}, {}
end

function Field:CacheCharacters()
    local value = self.props.value or ""
    if self.saveValue_ == value then return end
    local bytes, chars = {1}, {}
    local i = 1
    while i <= #value do
        local first = value:byte(i)
        -- Match TextField's character indexing, including a partial pasted
        -- sequence at the end, without ever throwing on invalid import text.
        local size = first < 128 and 1 or first < 224 and 2 or first < 240 and 3 or 4
        local nextByte = math.min(#value + 1, i + size)
        chars[#chars + 1] = value:sub(i, nextByte - 1)
        bytes[#bytes + 1] = nextByte
        i = nextByte
    end
    self.saveValue_, self.saveBytes_, self.saveChars_ = value, bytes, chars
end

---@param vg NVGContextWrapper
---@param face string
---@param size number
function Field:CachePositions(vg, face, size)
    self:CacheCharacters()
    local version, scale = UI.GetFontVersion(), UI.GetScale()
    local password = self.props.password == true
    local fontChanged = self.saveContext_ ~= vg or self.saveFace_ ~= face
        or self.saveSize_ ~= size or self.saveFontVersion_ ~= version or self.saveScale_ ~= scale
    if not fontChanged and self.savePositionsValue_ == self.saveValue_
        and self.savePassword_ == password then return end
    if fontChanged then self.saveAdvances_, self.savePairs_ = {}, {} end
    local advances, pairs = self.saveAdvances_, self.savePairs_
    ---@type number[]
    local positions = {0}
    ---@type string?
    local previous = nil
    local previousAdvance, x = 0.0, 0.0
    for _, source in ipairs(self.saveChars_) do
        local char = password and "●" or source
        local advance = advances[char]
        if advance == nil then
            advance = nvgTextBounds(vg, 0, 0, char)
            advances[char] = advance
        end
        local increment = advance --[[@as number]]
        if previous then
            local pair = previous .. char
            local pairAdvance = pairs[pair]
            if pairAdvance == nil then
                pairAdvance = nvgTextBounds(vg, 0, 0, pair)
                pairs[pair] = pairAdvance
            end
            increment = (pairAdvance - previousAdvance) --[[@as number]]
        end
        -- Zero-width glyphs remain valid boundaries and binary searches must
        -- also remain ordered for malformed or unusual pasted glyph metrics.
        x = x + math.max(0.0, increment)
        positions[#positions + 1] = x
        previous, previousAdvance = char, advance --[[@as number]]
    end
    self.charPositions_ = positions
    self.saveContext_, self.saveFace_, self.saveSize_ = vg, face, size
    self.saveFontVersion_, self.saveScale_ = version, scale
    self.savePositionsValue_, self.savePassword_ = self.saveValue_, password
end

---@param x number
---@return integer
function Field:GetCursorPosFromX(x)
    local positions = self.charPositions_ or {0}
    local relative = x - (self.textAreaX_ or 0) + (self.scrollX_ or 0)
    local right = lowerBound(positions, relative)
    local index = math.min(right, #positions)
    if right > 1 and (right > #positions
        or relative - positions[right - 1] <= positions[right] - relative) then index = right - 1 end
    -- Base TextField chooses the first boundary when several glyphs have the
    -- same advance. Preserve that rule without scanning a zero-width run.
    return lowerBound(positions, positions[index] or 0) - 1
end

---@param vg NVGContextWrapper
---@param l table
---@param x number
---@param color RGBAColor
local function drawCursor(vg, l, x, color)
    local _, _, lineHeight = nvgTextMetrics(vg)
    local height = math.min(lineHeight, l.h - 2)
    local top = l.y + (l.h - height) / 2
    nvgBeginPath(vg)
    nvgMoveTo(vg, x, top)
    nvgLineTo(vg, x, top + height)
    nvgStrokeColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
    nvgStrokeWidth(vg, 1)
    nvgStroke(vg)
end

---@param vg NVGContextWrapper
function Field:Render(vg)
    local l, props, state = self:GetAbsoluteLayout(), self.props, self.state
    local filled, disabled, focused = (props.value or "") ~= "", props.disabled, state.focused
    local bgColor
    if disabled then bgColor = props.disabledBgColor or Theme.Color("disabled")
    elseif focused then bgColor = props.focusedBgColor or props.backgroundColor or Theme.Color("surface")
    elseif filled then bgColor = props.filledBgColor or props.backgroundColor or Theme.Color("surface")
    else bgColor = props.backgroundColor or Theme.Color("surface") end
    local borderColor, borderWidth
    if disabled then
        borderColor = props.disabledBorderColor or props.borderColor or Theme.Color("border")
        borderWidth = props.disabledBorderWidth
    elseif props.error then
        borderColor = props.errorBorderColor or Theme.Color("error")
        borderWidth = props.errorBorderWidth
    elseif focused then
        borderColor = props.focusedBorderColor or Theme.Color("borderFocus")
        borderWidth = props.focusedBorderWidth
    elseif filled then
        borderColor = props.filledBorderColor or props.borderColor or Theme.Color("border")
        borderWidth = props.filledBorderWidth
    else
        borderColor = props.borderColor or Theme.Color("border")
        borderWidth = props.borderWidth
    end
    if borderWidth == nil then borderWidth = focused and 2 or (props.borderWidth or 1) end
    self:CreateShapePath(vg, self:GetShapeGeometry(l, nil, props.borderRadius or 0))
    nvgFillColor(vg, nvgRGBA(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 255))
    nvgFill(vg)
    if borderColor and borderWidth > 0 then
        self:CreateShapePath(vg, self:GetShapeGeometry(l, nil, props.borderRadius or 0))
        nvgStrokeColor(vg, nvgRGBA(borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 255))
        nvgStrokeWidth(vg, borderWidth)
        nvgStroke(vg)
    end

    local textColor = disabled
        and (props.disabledTextColor or props.textColor or Theme.Color("disabledText"))
        or (props.textColor or Theme.Color("text"))
    local face = Theme.FontFace(props.fontFamily, props.fontWeight)
    local size = Theme.FontSize(props.fontSize or Theme.BaseFontSize("body"))
    nvgSave(vg)
    nvgFontFace(vg, face)
    nvgFontSize(vg, size)
    nvgTextLetterSpacing(vg, 0)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    self:CachePositions(vg, face, size)
    local positions, count = self.charPositions_, #self.saveChars_
    local paddingLeft, paddingRight = tonumber(props.paddingLeft) or 0, tonumber(props.paddingRight) or 0
    local areaX = l.x + paddingLeft
    local areaWidth = math.max(0, l.w - paddingLeft - paddingRight)
    self.textAreaX_ = areaX
    local cursor = math.max(0, math.min(count, math.floor(state.cursorPos)))
    local cursorOffset, scroll = positions[cursor + 1] or 0, state.scrollX or 0.0
    if cursorOffset - scroll > areaWidth then scroll = cursorOffset - areaWidth + 2
    elseif cursorOffset < scroll then scroll = cursorOffset end
    scroll = math.max(0.0, math.min(scroll, math.max(0.0, positions[count + 1] - areaWidth)))
    state.scrollX, self.scrollX_ = scroll, scroll
    nvgIntersectScissor(vg, areaX, l.y, areaWidth, l.h)
    if count > 0 then
        if self:HasSelection() then
            local first, last = self:GetSelectionRange()
            local startX, endX = positions[first + 1] or 0, positions[last + 1] or 0
            local color = props.selectionBgColor or Theme.Color("primary") or {66, 133, 244, 100}
            local _, _, lineHeight = nvgTextMetrics(vg)
            local height = math.min(lineHeight, l.h - 2)
            nvgBeginPath(vg)
            nvgRect(vg, areaX + startX - scroll, l.y + (l.h - height) / 2, endX - startX, height)
            nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], props.selectionBgColor and (color[4] or 255) or 100))
            nvgFill(vg)
        end
        -- Include the neighbouring glyphs and italic overhang in the clipped
        -- window. Bound degenerate runs too: a million zero-width glyphs all
        -- overlap in the same few pixels and must not be submitted together.
        local margin = math.max(2, size * 2)
        local first = math.max(1, math.min(count, lowerBound(positions, scroll - margin) - 1))
        local last = math.min(count, lowerBound(positions, scroll + areaWidth + margin) + 1)
        if last - first > 1023 then
            first = math.max(first, math.min(last - 1023, cursor - 511))
            last = math.min(last, first + 1023)
        end
        local text = self.savePassword_ and string.rep("●", last - first + 1)
            or (self.saveValue_ or ""):sub(self.saveBytes_[first] or 1, (self.saveBytes_[last + 1] or 1) - 1)
        local char = self.savePassword_ and "●" or self.saveChars_[first]
        local leadingKern = positions[first + 1] - positions[first] - (self.saveAdvances_[char] or 0)
        nvgFillColor(vg, nvgRGBA(textColor[1], textColor[2], textColor[3], textColor[4] or 255))
        nvgText(vg, areaX + positions[first] + leadingKern - scroll, l.y + l.h / 2, text, nil)
    else
        local color = props.placeholderColor or Theme.Color("textSecondary")
        nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], color[4] or 255))
        nvgText(vg, areaX, l.y + l.h / 2, props.placeholder or "", nil)
    end
    if focused and state.cursorBlink then
        drawCursor(vg, l, areaX + cursorOffset - scroll, (props.cursorColor or textColor) --[[@as RGBAColor]])
    end
    nvgRestore(vg)
end

local function category(char)
    local a, b, c, d = char:byte(1, 4)
    local cp = a
    if a >= 240 and d then cp = (a - 240) * 262144 + (b - 128) * 4096 + (c - 128) * 64 + d - 128
    elseif a >= 224 and c then cp = (a - 224) * 4096 + (b - 128) * 64 + c - 128
    elseif a >= 192 and b then cp = (a - 192) * 64 + b - 128 end
    if cp == 32 or cp == 9 or cp == 10 or cp == 13 then return "space" end
    if (cp >= 0x4E00 and cp <= 0x9FFF) or (cp >= 0x3400 and cp <= 0x4DBF)
        or (cp >= 0x20000 and cp <= 0x2A6DF) or (cp >= 0x3040 and cp <= 0x30FF) then return "cjk" end
    if (cp >= 0x3000 and cp <= 0x303F) or (cp >= 0xFF01 and cp <= 0xFF0F)
        or (cp >= 0xFF1A and cp <= 0xFF20) or (cp >= 0x21 and cp <= 0x2F)
        or (cp >= 0x3A and cp <= 0x40) or (cp >= 0x5B and cp <= 0x60)
        or (cp >= 0x7B and cp <= 0x7E) then return "punct" end
    return "word"
end

function Field:OnDoubleTap(event)
    if self.props.disabled then return end
    self:CacheCharacters()
    local chars = self.saveChars_
    if #chars == 0 then
        if self.lastPointerType_ == "touch" then self:ShowEditMenu() end
        return
    end
    local pos = math.max(1, math.min(#chars, self:GetCursorPosFromX(event.x) + 1))
    local kind, first, last = category(chars[pos]), pos, pos
    if kind ~= "cjk" then
        while first > 1 and category(chars[first - 1]) == kind do first = first - 1 end
        while last < #chars and category(chars[last + 1]) == kind do last = last + 1 end
    end
    self:SetState({cursorPos = last, selectionStart = first - 1, selectionEnd = last, cursorBlink = true})
    self.blinkTimer_ = 0
    if self.lastPointerType_ == "touch" then self:ShowEditMenu() end
end

return Field
