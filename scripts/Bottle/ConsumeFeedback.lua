-- 统一消耗反馈播放器：策略选择、旧姿态捕获、计时、退场与消耗者响应。
-- 所有规则先即时完成；本模块只读事件和物理姿态，渲染器不修改规则对象。
local Items = require("Bottle.Items")
local Styles = require("Bottle.ConsumeStyles")
local Smoke = require("Bottle.ConsumeSmoke")
local Pool = require("Bottle.RecordPool")
local flashPool, popupPool, reboundPool = Pool.New(192), Pool.New(256), Pool.New(128)
local softPosePool, softArrayPool = Pool.New(512), Pool.New(96)

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
---@field textWidth number?
---@field textFontSize number?
---@field textFontVersion number?
---@field textScale number?
---@field textLabel string?
---@field soft BottleSoftPose[]?
---@field consumerUid integer?
---@field consumerId string?
---@field targetX number?
---@field targetY number?
---@field emphasis boolean?
---@field style string
---@field animation string
---@field rebound boolean
---@field lifetime number

---@class BottleConsumePopup
---@field uid integer
---@field id string
---@field x number
---@field y number
---@field age number
---@field lift number
---@field label string
---@field rollValue number?
---@field woolCount number?
---@field textWidth number?
---@field textFontSize number?
---@field textFontVersion number?
---@field textScale number?
---@field textLabel string?

---@class BottleConsumeFeedback
---@field flashes BottleConsumedPose[]
---@field popups BottleConsumePopup[]
---@field seen table<table,boolean>
---@field rebounds table<number,{id:string,age:number}>
---@alias BottleConsumeFlash BottleConsumeFeedback
local Flash = {}
Flash.__index = Flash
Flash.LIFETIME, Flash.INTERVAL = .48, .08
Flash.POPUP_LIFETIME = 2
Flash.HOLD, Flash.FLIGHT, Flash.REBOUND = .06, .22, .18
Flash.ABSORB_LIFETIME = Flash.HOLD + Flash.FLIGHT
local POPUP_SIZE = 26
local OUTLINE = {{-2,-2},{0,-2},{2,-2},{-2,0},{2,0},{-2,2},{0,2},{2,2}}

---@param pose BottleConsumedPose
---@return boolean
function Flash.ReleasePose(pose)
    local soft = pose.soft
    if not flashPool:Release(pose) then return false end
    -- Pin期间保留共享软体数组和字段；子记录只登记延迟归还，不清数组。
    if soft then
        for _, part in ipairs(soft) do softPosePool:Release(part) end
        softArrayPool:Release(soft)
    end
    return true
end

---@return BottleConsumeFeedback
function Flash.New()
    local self = setmetatable({}, Flash)
    self:Reset()
    return self
end

function Flash:Reset()
    if self.flashes then
        for index = #self.flashes, 1, -1 do Flash.ReleasePose(self.flashes[index]);self.flashes[index] = nil end
    else self.flashes = {} end
    if self.popups then popupPool:ClearActive(self.popups) else self.popups = {} end
    if self.rebounds then
        for uid, rebound in pairs(self.rebounds) do reboundPool:Release(rebound);self.rebounds[uid] = nil end
    else self.rebounds = {} end
    if self.seen then for event in pairs(self.seen) do self.seen[event] = nil end
    else self.seen = setmetatable({}, {__mode = "k"}) end
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
    local angle = 0.0
    ---@type BottleSoftPose[]?
    local soft = nil
    -- 同一 uid 可能已被规则转化；只借用与原图案一致的真实姿态。
    if record and record.kind == event.id then
        x, y, angle = physics:GetPose(event.uid)
        soft = physics:GetSoftPose(event.uid)
    elseif (x == nil or y == nil) and origin then
        x, y = origin.x, origin.y
    end
    local captured = self:CapturePose(event, x, y, angle, soft)
    if captured then self:TrackTarget(self.flashes[#self.flashes], physics) end
    return captured
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
        soft = softArrayPool:Acquire() --[[@as BottleSoftPose[] ]]
        for _, pose in ipairs(poses) do
            local part = softPosePool:Acquire() --[[@as BottleSoftPose]]
            part.x, part.y, part.angle = pose.x, pose.y, pose.angle
            part.halfLength, part.halfWidth, part.u0, part.u1 = pose.halfLength, pose.halfWidth, pose.u0, pose.u1
            soft[#soft + 1] = part
        end
    end
    local style = Styles.Resolve(event)
    local profile = Styles.profiles[style]
    local animation = profile.animation
    local linked = event.consumerUid and event.consumerUid ~= event.uid and event.consumerId
    if animation == "absorb" and not linked then animation = "flash" end
    local pose = flashPool:Acquire() --[[@as BottleConsumedPose]]
    pose.uid, pose.id, pose.x, pose.y, pose.angle = event.uid, def.id, x, y, angle
    pose.radius, pose.age = def.radius * (event.scale or 1), 0
    pose.rollValue, pose.woolCount, pose.soft = event.rollValue, event.woolCount, soft
    pose.consumerId = animation == "smoke" and event.consumerId or nil
    pose.style, pose.animation, pose.rebound = style, animation, profile.rebound
    pose.lifetime = animation == "absorb" and Flash.ABSORB_LIFETIME
        or (animation == "smoke" and Smoke.LIFETIME or Flash.LIFETIME)
    self.flashes[#self.flashes + 1] = pose
    if animation == "absorb" then
        pose.consumerUid, pose.consumerId = event.consumerUid, event.consumerId
        pose.targetX, pose.targetY = event.toX, event.toY
    end
    local emphasized = 0
    for _, active in ipairs(self.flashes) do
        if active ~= pose and active.emphasis then emphasized = emphasized + 1 end
    end
    pose.emphasis = emphasized < 3
    if not profile.popup then return true end
    local lane = 0
    for _, popup in ipairs(self.popups) do
        if popup.uid == event.uid and popup.age < .12 then lane = lane + 1 end
    end
    -- 独立计时，不因0.48秒白闪结束而移除；图标保持被消耗前的身份。
    local popup = popupPool:Acquire() --[[@as BottleConsumePopup]]
    popup.uid, popup.id, popup.x, popup.y = event.uid, def.id, x, y
    popup.age, popup.lift, popup.label = 0, lane * 30, profile.label
    popup.rollValue, popup.woolCount = event.rollValue, event.woolCount
    self.popups[#self.popups + 1] = popup
    return true
end

---@param pose BottleConsumedPose
---@return boolean
function Flash.Visible(pose)
    if pose.animation ~= "flash" then return pose.age < pose.lifetime end
    return pose.age < Flash.LIFETIME and math.floor(pose.age / Flash.INTERVAL) % 2 == 0
end

-- 消耗者继续随物理移动；消失/换图案后保留最后已知终点，不指向新身份。
---@param pose BottleConsumedPose
---@param physics BottlePhysics
function Flash:TrackTarget(pose, physics)
    local record = pose.consumerUid and physics.bodies[pose.consumerUid]
    if record and record.kind == pose.consumerId and pose.consumerUid then
        pose.targetX, pose.targetY = physics:GetPose(pose.consumerUid)
    end
end

---@param pose BottleConsumedPose
---@return number x, number y, number scale, number alpha
function Flash.VisualPose(pose)
    if pose.animation == "smoke" then return Smoke.VisualPose(pose) end
    if pose.animation ~= "absorb" then return pose.x, pose.y, 1, 1 end
    local hold = math.min(1, pose.age / Flash.HOLD)
    local t = math.max(0, math.min(1, (pose.age - Flash.HOLD) / Flash.FLIGHT))
    local travel = t * t
    local lift = pose.emphasis and .12 or .04
    local arc = pose.emphasis and math.max(.3, pose.radius) or .12
    local tx, ty = pose.targetX or pose.x, pose.targetY or pose.y
    return pose.x + (tx - pose.x) * travel,
        pose.y + (ty - pose.y) * travel + lift * hold * (1 - t) + 4 * arc * t * (1 - t),
        (1 + .12 * hold) * (1 - travel), math.min(1, (1 - t) / .15)
end

-- 同一消耗者正在回弹时只合并反馈，不叠加幅度或重置动画。
---@param uid integer
---@param age number?
---@return number scaleX, number scaleY
function Flash:ReboundScale(uid, age)
    local rebound = self.rebounds[uid]
    local elapsed = age or (rebound and rebound.age)
    if not elapsed or elapsed >= Flash.REBOUND then return 1, 1 end
    local t = math.max(0, elapsed / Flash.REBOUND)
    local squash = math.sin(t * math.pi * 2) * (1 - t) * .2
    return 1 + squash, 1 - squash
end

---@param dt number
---@param physics BottlePhysics?
function Flash:Update(dt, physics)
    local elapsed = math.max(0, dt)
    for uid, rebound in pairs(self.rebounds) do
        rebound.age = rebound.age + elapsed
        if rebound.age >= Flash.REBOUND then reboundPool:Release(rebound);self.rebounds[uid] = nil end
    end
    local flashCount = #self.flashes
    for index = flashCount, 1, -1 do
        local pose = self.flashes[index] --[[@as BottleConsumedPose]]
        if physics then self:TrackTarget(pose, physics) end
        pose.age = pose.age + elapsed
        local life = pose.lifetime
        if pose.age >= life then
            local uid = pose.consumerUid
            local consumerId = pose.consumerId or ""
            local record = uid and physics and physics.bodies[uid]
            local overshoot = pose.age - life
            if pose.rebound and uid and consumerId ~= "" and record and record.kind == consumerId and not self.rebounds[uid]
                and overshoot < Flash.REBOUND then
                local rebound = reboundPool:Acquire()
                rebound.id, rebound.age = consumerId, overshoot
                self.rebounds[uid] = rebound
            end
            Flash.ReleasePose(pose)
            self.flashes[index] = nil
        end
    end
    local kept = 0
    for index = 1, flashCount do
        local pose = self.flashes[index]
        if pose then kept = kept + 1;self.flashes[kept] = pose end
    end
    for index = flashCount, kept + 1, -1 do self.flashes[index] = nil end
    local popupCount, keptPopups = #self.popups, 0
    for index = 1, popupCount do
        local popup = self.popups[index]
        popup.age = popup.age + math.max(0, dt)
        if popup.age >= Flash.POPUP_LIFETIME then popupPool:Release(popup)
        else keptPopups = keptPopups + 1;self.popups[keptPopups] = popup end
    end
    for index = popupCount, keptPopups + 1, -1 do self.popups[index] = nil end
end

function Flash.PoolStats()
    return flashPool:GetStats(), popupPool:GetStats(), reboundPool:GetStats(), softPosePool:GetStats(), softArrayPool:GetStats()
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
    for _, popup in ipairs(self.popups) do
        local version, scale = UI.GetFontVersion(), UI.GetScale()
        if popup.textWidth == nil or popup.textFontSize ~= fontSize or popup.textFontVersion ~= version
            or popup.textScale ~= scale or popup.textLabel ~= popup.label then
            popup.textWidth = nvgTextBounds(vg, 0, 0, popup.label)
            popup.textFontSize, popup.textFontVersion, popup.textScale, popup.textLabel = fontSize, version, scale, popup.label
        end
        local textWidth = popup.textWidth or 0
        local width, height = textWidth + 4 + POPUP_SIZE, math.max(fontSize, POPUP_SIZE) + 4
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
        for _, offset in ipairs(OUTLINE) do nvgText(vg, left + offset[1], offset[2], popup.label, nil) end
        nvgFillColor(vg, nvgRGBA(255, 255, 255, 255))
        nvgText(vg, left, 0, popup.label, nil)
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
            local absorbing = pose.animation == "absorb"
            local white = pose.animation == "flash"
            local px, py, scale, alpha = Flash.VisualPose(pose)
            local sx, sy = x + pose.x * ppu, y - pose.y * ppu
            nvgSave(vg)
            nvgTranslate(vg, x + px * ppu, y - py * ppu)
            nvgScale(vg, math.max(.001, scale), math.max(.001, scale))
            nvgTranslate(vg, -sx, -sy)
            nvgGlobalAlpha(vg, alpha)
            if absorbing and pose.emphasis then
                -- 白边只衬托原色，覆盖范围限于物品轮廓；最多三组强调。
                if pose.soft then
                    for _, part in ipairs(pose.soft) do
                        Art.BaconSegmentOutline(vg, x + part.x * ppu, y - part.y * ppu, -part.angle,
                            part.halfLength * ppu, part.halfWidth * ppu, part.u0, part.u1, 2)
                    end
                else Art.ItemOutline(vg, pose.id, sx, sy, pose.radius * ppu, -pose.angle,
                    pose.rollValue, pose.woolCount, 2) end
            end
            if pose.soft then SoftView.Draw(vg, pose.soft, x, y, ppu, false, white)
            else
                Art.Item(vg, pose.id, sx, sy, pose.radius * ppu, -pose.angle,
                    false, pose.rollValue, pose.woolCount, white)
            end
            nvgRestore(vg)
            if pose.animation == "smoke" then Smoke.Render(vg, pose, x, y, ppu) end
        end
    end
    self:RenderPopups(vg, x, y, ppu, bounds)
end

return Flash
