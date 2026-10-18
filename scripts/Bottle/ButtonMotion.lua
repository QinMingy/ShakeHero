-- 按钮悬停只改变视觉子树；固定命中框不参与缩放，避免边缘反复进入／离开。
local UI = require("urhox-libs/UI")
local TextMotion = require("Bottle.TextMotion")
---@type any
local Motion = {mouseActive = false, mouseX = 0, mouseY = 0, listeners = {}}

function Motion.NewPose()
    return {scale = 1, velocity = 0, angle = 0, angularVelocity = 0, hovered = false}
end

function Motion.Reset(pose)
    pose.scale = 1; pose.velocity = 0; pose.angle = 0; pose.angularVelocity = 0; pose.hovered = false
end

-- 解析欠阻尼弹簧，与三选一使用同一响应形式，不依赖帧率积分。
local function spring(value, velocity, target, dt)
    local damping, frequency = 9, 23
    local wave = math.sqrt(frequency * frequency - damping * damping)
    local delta = value - target
    local c, s, decay = math.cos(wave * dt), math.sin(wave * dt), math.exp(-damping * dt)
    return target + decay * (delta * c + (velocity + damping * delta) / wave * s),
        decay * (velocity * c - (damping * velocity + frequency * frequency * delta) / wave * s)
end

function Motion.Step(pose, hovered, selectionBusy, dt)
    if hovered and not pose.hovered and not selectionBusy then
        pose.angularVelocity = 1.5
    end
    pose.hovered = hovered
    -- 选中／落回中的整卡已有角弹簧，不再叠加另一套回摆。
    if selectionBusy then pose.angle = 0; pose.angularVelocity = 0 end
    local target = hovered and (selectionBusy and 1.035 or 1.06) or 1
    local step = math.max(0, dt)
    pose.scale, pose.velocity = spring(pose.scale, pose.velocity, target, step)
    pose.angle, pose.angularVelocity = spring(pose.angle, pose.angularVelocity, 0, step)
    if math.abs(pose.scale - target) < .00005 and math.abs(pose.velocity) < .0002 then
        pose.scale = target; pose.velocity = 0
    end
    if math.abs(pose.angle) < .0001 and math.abs(pose.angularVelocity) < .001 then
        pose.angle = 0; pose.angularVelocity = 0
    end
end

local function hoveredButton()
    if not Motion.mouseActive then return nil end
    local widget = UI.FindWidgetAt(Motion.mouseX / UI.GetScale(), Motion.mouseY / UI.GetScale())
    while widget do
        if widget._className == "Button" then return widget end
        widget = widget.parent
    end
    return nil
end

function Motion.IsHovered(button)
    return not button.props.disabled and button.props.onClick ~= nil
        and TextMotion.IsDisplayed(button)
        and not (button.hoverBlocked and button.hoverBlocked())
        and hoveredButton() == button
end

function Motion.Attach(button, pose, custom)
    if button.hoverPose then return end
    button.hoverPose = pose or Motion.NewPose()
    button.hoverCustom = custom == true
    if custom then return end
    -- 原Render（含文字浮动、九宫格与按下反馈）原样保留，只把它放到无指针视觉层。
    local render = button.Render
    local children = {}
    for _, child in ipairs(button:GetChildren()) do children[#children + 1] = child end
    local face = UI.Panel {position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
        padding = 0, pointerEvents = "none", transformOrigin = "center"} --[[@as any]]
    face.Render = function(_, vg) render(button, vg) end
    for _, child in ipairs(children) do face:AddChild(child) end
    button.Render = function() end
    button:AddChild(face)
    button.hoverVisual = face
end

-- 原按下偏移发生在视觉缩放／旋转内，3D底板使用相同组合变换。
function Motion.Transform(button, rect, offset)
    local pose = button.hoverPose
    local zoom, angle = pose and pose.scale or 1, pose and pose.angle or 0
    local dy = offset or 0
    return {cx = rect.x + rect.w / 2, cy = rect.y + rect.h / 2,
        scale = zoom, angle = angle, x = -math.sin(angle) * zoom * dy, y = math.cos(angle) * zoom * dy}
end

local function visit(widget, dt, hovered)
    if not widget then return end
    if widget._className == "Button" then
        Motion.Attach(widget)
        if not widget.hoverCustom then
            local enabled = not widget.props.disabled and widget.props.onClick ~= nil
                and not (widget.hoverBlocked and widget.hoverBlocked())
            local active = enabled and TextMotion.IsDisplayed(widget)
            local pose = widget.hoverPose
            if active then
                local page = widget.pageEntry
                local moving = page and (math.abs(page.pose.y) > .05 or math.abs(page.pose.angle) > .0002)
                Motion.Step(pose, hovered == widget, moving == true, dt)
            else
                -- 隐藏／禁用／被业务屏蔽时清除反馈，不保留触摸造成的假悬停。
                Motion.Reset(pose)
            end
            widget.hoverVisual:SetStyle({scale = pose.scale, rotate = math.deg(pose.angle)})
        end
    end
    for _, child in ipairs(widget:GetChildren()) do visit(child, dt, hovered) end
end

function Motion.Init()
    Motion.Shutdown()
    -- 高优先级保存物理坐标；UI随后会把事件坐标改成控件局部坐标。
    local function pointer(event)
        if event.pointerType == "mouse" then
            Motion.mouseActive = true; Motion.mouseX = event.x; Motion.mouseY = event.y
        elseif event.type == "PointerDown" then
            Motion.mouseActive = false
        end
    end
    for _, name in ipairs({"PointerMove", "PointerDown", "PointerUp"}) do
        Motion.listeners[name] = UI.Input.On(name, pointer, 10)
    end
    print("[按钮动效] 悬停弹簧已启用；三选一选中回摆优先，点击框固定")
end

function Motion.Update(dt)
    visit(UI.GetRoot(), math.max(0, dt), hoveredButton())
end

function Motion.Shutdown()
    for name, id in pairs(Motion.listeners) do UI.Input.Off(name, id) end
    Motion.listeners = {}; Motion.mouseActive = false
end

return Motion
