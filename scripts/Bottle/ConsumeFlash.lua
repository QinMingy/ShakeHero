-- 消耗白闪与“消耗＋原图标”跳字：仅保存绘制数据，不持有刚体、实例或规则状态。
local Items = require("Bottle.Items")

---@class BottleConsumedPose
---@field uid integer
---@field id string
---@field x number
---@field y number
---@field angle number
---@field radius number
---@field age number
---@field rollValue number?
---@field woolCount number?
---@field soft BottleSoftPose[]?

---@class BottleConsumePopup
---@field uid integer
---@field id string
---@field x number
---@field y number
---@field age number
---@field lift number
---@field rollValue number?
---@field woolCount number?

---@class BottleConsumeFlash
---@field flashes BottleConsumedPose[]
---@field popups BottleConsumePopup[]
---@field seen table<table,boolean>
local Flash = {}
Flash.__index = Flash
Flash.LIFETIME, Flash.INTERVAL = .48, .08
Flash.POPUP_LIFETIME = 2
local POPUP_SIZE = 26
local OUTLINE = {{-2,-2},{0,-2},{2,-2},{-2,0},{2,0},{-2,2},{0,2},{2,2}}

---@return BottleConsumeFlash
function Flash.New()
    local self = setmetatable({}, Flash)
    self:Reset()
    return self
end

function Flash:Reset()
    self.flashes = {}
    self.popups = {}
    self.seen = setmetatable({}, {__mode = "k"})
end

---@param event GameEvent
---@param physics BottlePhysics
---@param origin {x:number,y:number}?
---@return boolean captured
function Flash:Capture(event, physics, origin)
    if event.kind ~= "consume" or self.seen[event] then return false end
    local def = event.id and Items.byId[event.id]
    if not def then return false end
    local record = physics.bodies[event.uid]
    local x, y = event.x, event.y
    local angle = 0
    ---@type BottleSoftPose[]?
    local soft = nil
    -- 同一 uid 可能已被规则转化；只借用与原图案一致的真实姿态。
    if record and record.kind == event.id then
        x, y, angle = physics:GetPose(event.uid)
        soft = physics:GetSoftPose(event.uid)
    elseif (x == nil or y == nil) and origin then
        x, y = origin.x, origin.y
    end
    return self:CapturePose(event, x, y, angle, soft)
end

-- 瓶中和牌库共用同一消耗表现；传入真实姿态后立即脱离原物理对象。
---@param event GameEvent
---@param x number?
---@param y number?
---@param angle number
---@param poses BottleSoftPose[]?
---@return boolean captured
function Flash:CapturePose(event, x, y, angle, poses)
    if event.kind ~= "consume" or self.seen[event] then return false end
    self.seen[event] = true
    local def = event.id and Items.byId[event.id]
    if not def then return false end
    -- 同一步入场又被消耗时可能没有刚体；无真实来源的位置不制造残影。
    if x == nil or y == nil then return false end
    ---@type BottleSoftPose[]?
    local soft = nil
    if poses then
        soft = {}
        for _, pose in ipairs(poses) do
            soft[#soft + 1] = {x = pose.x, y = pose.y, angle = pose.angle,
                halfLength = pose.halfLength, halfWidth = pose.halfWidth, u0 = pose.u0, u1 = pose.u1}
        end
    end
    self.flashes[#self.flashes + 1] = {
        uid = event.uid, id = def.id, x = x, y = y, angle = angle,
        radius = def.radius * (event.scale or 1), age = 0,
        rollValue = event.rollValue, woolCount = event.woolCount, soft = soft,
    }
    local lane = 0
    for _, popup in ipairs(self.popups) do
        if popup.uid == event.uid and popup.age < .12 then lane = lane + 1 end
    end
    -- 独立计时，不因0.48秒白闪结束而移除；图标保持被消耗前的身份。
    self.popups[#self.popups + 1] = {
        uid = event.uid, id = def.id, x = x, y = y, age = 0, lift = lane * 30,
        rollValue = event.rollValue, woolCount = event.woolCount,
    }
    return true
end

---@param pose BottleConsumedPose
---@return boolean
function Flash.Visible(pose)
    return pose.age < Flash.LIFETIME and math.floor(pose.age / Flash.INTERVAL) % 2 == 0
end

---@param dt number
function Flash:Update(dt)
    for index = #self.flashes, 1, -1 do
        local pose = self.flashes[index]
        pose.age = pose.age + math.max(0, dt)
        if pose.age >= Flash.LIFETIME then table.remove(self.flashes, index) end
    end
    for index = #self.popups, 1, -1 do
        local popup = self.popups[index]
        popup.age = popup.age + math.max(0, dt)
        if popup.age >= Flash.POPUP_LIFETIME then table.remove(self.popups, index) end
    end
end

---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
---@param bounds table? UI布局的x/y/w/h
function Flash:RenderPopups(vg, x, y, ppu, bounds)
    if #self.popups == 0 then return end
    local UI = require("urhox-libs/UI")
    local Art = require("Bottle.Art")
    nvgSave(vg)
    nvgFontFace(vg, UI.Theme.FontFace("sans", "normal"))
    local fontSize = UI.Theme.FontSize(POPUP_SIZE)
    nvgFontSize(vg, fontSize)
    nvgTextAlign(vg, NVG_ALIGN_LEFT + NVG_ALIGN_MIDDLE)
    local textWidth = nvgTextBounds(vg, 0, 0, "消耗")
    local width, height = textWidth + 4 + POPUP_SIZE, math.max(fontSize, POPUP_SIZE) + 4
    for _, popup in ipairs(self.popups) do
        local s = 1 - math.exp(-4 * popup.age) * math.cos(9 * popup.age)
        local angle = (popup.uid % 2 == 0 and 1 or -1) * math.rad(14)
            * math.exp(-2.5 * popup.age) * math.sin(12 * popup.age)
        local tx, ty = x + popup.x * ppu, y - popup.y * ppu - 20 - popup.age * 42 - popup.lift
        local fit = 1.0
        if bounds and bounds.w > 0 and bounds.h > 0 then
            local cosine, sine = math.abs(math.cos(angle)), math.abs(math.sin(angle))
            local boxW, boxH = (width*cosine + height*sine)*s, (width*sine + height*cosine)*s
            fit = math.min(1, math.max(0, bounds.w - 12)/math.max(1, boxW),
                math.max(0, bounds.h - 12)/math.max(1, boxH))
            local halfW, halfH = boxW*fit/2 + 3, boxH*fit/2 + 3
            tx = math.max(bounds.x + halfW, math.min(bounds.x + bounds.w - halfW, tx))
            ty = math.max(bounds.y + halfH, math.min(bounds.y + bounds.h - halfH, ty))
        end
        nvgSave(vg)
        nvgTranslate(vg, tx, ty)
        nvgRotate(vg, angle)
        nvgScale(vg, s*fit, s*fit)
        local left = -width/2
        nvgFillColor(vg, nvgRGBA(0, 0, 0, 255))
        for _, offset in ipairs(OUTLINE) do nvgText(vg, left + offset[1], offset[2], "消耗", nil) end
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, left, 0, "消耗", nil)
        local radius = POPUP_SIZE/2
        local extent = Art.ItemExtent(popup.id, radius, 0, popup.woolCount)
        local fittedRadius = extent > radius and radius*radius/extent or radius
        Art.Item(vg, popup.id, left + textWidth + 4 + radius, 0, fittedRadius, 0, false,
            popup.rollValue, popup.woolCount)
        nvgRestore(vg)
    end
    nvgRestore(vg)
end

---@param vg NVGContextWrapper
---@param x number 瓶底屏幕原点
---@param y number
---@param ppu number 米到 UI 逻辑像素
---@param bounds table? UI布局的x/y/w/h
function Flash:Render(vg, x, y, ppu, bounds)
    if #self.flashes == 0 and #self.popups == 0 then return end
    local Art = require("Bottle.Art")
    local SoftView = require("Bottle.SoftView")
    for _, pose in ipairs(self.flashes) do
        if Flash.Visible(pose) then
            if pose.soft then SoftView.Draw(vg, pose.soft, x, y, ppu, false, true)
            else
                Art.Item(vg, pose.id, x + pose.x * ppu, y - pose.y * ppu,
                    pose.radius * ppu, -pose.angle, false, pose.rollValue, pose.woolCount, true)
            end
        end
    end
    self:RenderPopups(vg, x, y, ppu, bounds)
end

return Flash
