-- 瓶下摇晃提示独立回归；纯 Lua UI 替身，不接入总 Tests、不初始化引擎或读写存档。
-- 运行：require("Bottle.ShakeHintTests").Run()；返回通过的用例数。
local Hint = require("Bottle.ShakeHint")
local L = require("Machine.LayeredLayout")
local Tests = {}
local HEIGHT, PERIOD = 26, 2.4
-- 覆盖机台缩放下限、窄屏／常见手机宽高比、整数／分数倍率与上限。
local SCALES = {.01, .5, .625, .75, 320/402, 360/402, 375/402, 390/402,
    844/874, 1, 915/874, 1.125, 1.25, 1.5, 1.65}
local PHASES = {"prepare", "running", "settle", "reveal", "draft"}

---@param actual number
---@param expected number
---@param message string?
local function Near(actual, expected, message)
    assert(math.abs(actual - expected) < 1e-8,
        (message or "数值不一致") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end

---@param props table?
---@return any
local function Widget(props)
    local widget = {props={}, children={}, styles={}, visibilityChanges=0, baseUpdates=0,
        baseTime=0, lastBaseDt=0, opacityWrites=0}
    for key, value in pairs(props or {}) do widget.props[key] = value end
    if widget.props.visible == nil then widget.props.visible = true end
    if widget.props.opacity == nil then widget.props.opacity = 1 end
    function widget:SetStyle(style)
        self.styles[#self.styles + 1] = style
        if style.opacity ~= nil then self.opacityWrites = self.opacityWrites + 1 end
        for key, value in pairs(style) do self.props[key] = value end
    end
    function widget:IsVisible() return self.props.visible end
    function widget:SetVisible(visible)
        self.visibilityChanges = self.visibilityChanges + 1
        self.props.visible = visible
    end
    function widget:AddChild(child) self.children[#self.children + 1] = child end
    function widget:Update(dt)
        self.baseUpdates = self.baseUpdates + 1
        self.baseTime = self.baseTime + dt
        self.lastBaseDt = dt
    end
    return widget
end

---@param scale number?
---@return any
local function Fixture(scale)
    local s = scale or 1
    return {
        game={stage=1, phase="prepare", elapsed=0, score=0, revision=0},
        machineSkin={scale=s, shakeHint=Widget()},
        board=Widget(L.Style(L.board, s)), container=Widget(), inventoryOpen=false,
        startScreen={active=false, IsActive=function(self) return self.active end},
        modal=Widget({visible=false}), detailOverlay=Widget({visible=false}),
        definitionModal=Widget({visible=false}),
    }
end

-- 仅 Attach 时替换标准 Lua require 缓存；成功／断言失败均还原，避免污染其他专项。
---@param run fun(theme:any)
---@param withoutBaseUpdate boolean?
local function WithUI(run, withoutBaseUpdate)
    local oldUI, oldTheme = package.loaded["urhox-libs/UI"], package.loaded["Bottle.Theme"]
    local theme = {colors={textSecondary={161, 166, 135, 255}}}
    package.loaded["urhox-libs/UI"] = {Label=function(props)
        local label = Widget(props)
        if withoutBaseUpdate then label.Update = nil end
        return label
    end}
    package.loaded["Bottle.Theme"] = theme
    local ok, err = pcall(run, theme)
    package.loaded["urhox-libs/UI"], package.loaded["Bottle.Theme"] = oldUI, oldTheme
    assert(ok, tostring(err))
end

---@param view any
---@param expected boolean
local function Visibility(view, expected)
    assert(Hint.Visible(view) == expected, "Visible 返回错误")
    Hint.Sync(view)
    assert(view.machineSkin.shakeHint:IsVisible() == expected, "Sync 未同步标签可见性")
end

---@param view any
---@param reserve number
local function BoardRect(view, reserve)
    local props, s = view.board.props, view.machineSkin.scale
    Near(props.left, L.board[1] * s, "board left")
    Near(props.top, L.board[2] * s, "board top")
    Near(props.width, L.board[3] * s, "board width")
    Near(props.height, (L.board[4] - reserve) * s, "board height")
    assert(props.position == "absolute" and props.flexGrow == 0 and props.flexShrink == 0)
end

---@param elapsed number
---@return number
local function QuantizedOpacity(elapsed)
    return math.floor(Hint.Opacity(elapsed) * 255 + .5) / 255
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end

Test("stage1 五种正常阶段均可见且预留26设计像素", function()
    local view = Fixture()
    for _, phase in ipairs(PHASES) do
        view.game.phase = phase
        assert(Hint.Reserve(view.game) == HEIGHT, phase)
        Visibility(view, true)
        BoardRect(view, HEIGHT)
    end
end)

Test("stage2 所有阶段及stage1 over隐藏并归还board高度", function()
    local view = Fixture()
    for _, stage in ipairs({1, 2}) do
        for _, phase in ipairs({"prepare", "running", "settle", "reveal", "draft", "over"}) do
            view.game.stage, view.game.phase = stage, phase
            local visible = stage == 1 and phase ~= "over"
            local reserve = visible and HEIGHT or 0
            assert(Hint.Reserve(view.game) == reserve)
            Visibility(view, visible)
            BoardRect(view, reserve)
        end
    end
end)

Test("开始菜单遮挡但不取消预留且关闭后恢复，无开始菜单也可见", function()
    local view = Fixture()
    view.startScreen.active = true
    Visibility(view, false)
    BoardRect(view, HEIGHT)
    view.startScreen.active = false
    Visibility(view, true)
    view.startScreen = nil
    Visibility(view, true)
end)

Test("牌库开关遮挡且恢复时不抖动board高度", function()
    local view = Fixture()
    Visibility(view, true)
    view.inventoryOpen = true
    Visibility(view, false)
    BoardRect(view, HEIGHT)
    view.inventoryOpen = false
    Visibility(view, true)
    BoardRect(view, HEIGHT)
end)

Test("三种modal分别遮挡，关闭后恢复且预留不受影响", function()
    local view = Fixture()
    for _, field in ipairs({"modal", "detailOverlay", "definitionModal"}) do
        view[field]:SetVisible(true)
        Visibility(view, false)
        BoardRect(view, HEIGHT)
        view[field]:SetVisible(false)
        Visibility(view, true)
    end
end)

Test("多重遮挡须全部关闭才重新显示", function()
    local view = Fixture()
    view.startScreen.active, view.inventoryOpen = true, true
    view.modal:SetVisible(true)
    view.detailOverlay:SetVisible(true)
    view.definitionModal:SetVisible(true)
    Visibility(view, false)
    view.startScreen.active = false
    Visibility(view, false)
    view.inventoryOpen = false
    Visibility(view, false)
    view.modal:SetVisible(false)
    Visibility(view, false)
    view.detailOverlay:SetVisible(false)
    Visibility(view, false)
    view.definitionModal:SetVisible(false)
    Visibility(view, true)
end)

Test("同一view换局后按新game恢复提示而不沿用旧stage", function()
    WithUI(function()
        local view = Fixture()
        Hint.Attach(view)
        local label, oldGame = view.machineSkin.shakeHint, view.game
        oldGame.stage, oldGame.phase = 2, "draft"
        label:Update(0)
        assert(not label:IsVisible())
        BoardRect(view, 0)
        view.game = {stage=1, phase="prepare", elapsed=0, score=0, revision=0}
        label:Update(0)
        assert(label:IsVisible() and view.machineSkin.shakeHint == label)
        assert(#view.container.children == 1 and view.container.children[1] == label)
        BoardRect(view, HEIGHT)
        view.game.phase = "over"
        label:Update(0)
        assert(not label:IsVisible())
        BoardRect(view, 0)
        view.game = {stage=1, phase="running", elapsed=0, score=0, revision=0}
        label:Update(0)
        assert(label:IsVisible() and oldGame.stage == 2 and oldGame.phase == "draft")
        BoardRect(view, HEIGHT)
    end)
end)

Test("15种常用及边界scale的board底与提示带相邻且恢复全高", function()
    local view = Fixture()
    for _, scale in ipairs(SCALES) do
        view.machineSkin.scale, view.game.stage = scale, 1
        Hint.Sync(view)
        BoardRect(view, HEIGHT)
        local board, band = view.board.props, view.machineSkin.shakeHint.props
        Near(board.top + board.height, band.top, "board底须紧邻提示带")
        Near(band.top + band.height, (L.board[2] + L.board[4]) * scale, "提示带底不越过原board")
        Near(band.left, board.left + 8 * scale, "左侧内缩")
        Near(band.width, board.width - 16 * scale, "提示带宽度")
        Near(band.left + band.width, board.left + board.width - 8 * scale, "右侧内缩")
        Near(band.height, HEIGHT * scale)
        Near(band.fontSize, 10.5 * scale)
        Near(band.textShadow.offsetX, scale)
        Near(band.textShadow.offsetY, scale)
        assert(band.textShadow.blur == 0 and band.textShadow.color[4] == 255)
        assert(view.machineSkin.shakeHintScale == scale and view.machineSkin.shakeHintReserve == HEIGHT)
        view.game.stage = 2
        Hint.Sync(view)
        BoardRect(view, 0)
        assert(not view.machineSkin.shakeHint:IsVisible())
    end
end)

Test("布局及可见性不变时Sync不重复写样式或可见性", function()
    local view = Fixture(.75)
    Hint.Sync(view)
    local label = view.machineSkin.shakeHint
    local boardWrites, labelWrites, visibilityChanges = #view.board.styles, #label.styles, label.visibilityChanges
    for _ = 1, 20 do Hint.Sync(view) end
    assert(#view.board.styles == boardWrites and #label.styles == labelWrites)
    assert(label.visibilityChanges == visibilityChanges)
    view.game.stage = 2
    Hint.Sync(view)
    local hiddenChanges = label.visibilityChanges
    assert(hiddenChanges == visibilityChanges + 1)
    Hint.Sync(view)
    assert(label.visibilityChanges == hiddenChanges)
end)

Test("外部重设board全高或错误高度后即使缓存命中仍修复预留", function()
    local view = Fixture()
    for _, scale in ipairs(SCALES) do
        view.machineSkin.scale = scale
        Hint.Sync(view)
        view.board:SetStyle(L.Style(L.board, scale))
        assert(view.machineSkin.shakeHintScale == scale and view.machineSkin.shakeHintReserve == HEIGHT)
        local writes = #view.board.styles
        Hint.Sync(view)
        assert(#view.board.styles == writes + 1)
        BoardRect(view, HEIGHT)
        Near(view.board.props.top + view.board.props.height, view.machineSkin.shakeHint.props.top)
        view.board:SetStyle({height=1})
        Hint.Layout(view)
        BoardRect(view, HEIGHT)
    end
end)

Test("透明度在.78至.96之间且2.4秒周期与四分位准确", function()
    Near(Hint.Opacity(0), .96)
    Near(Hint.Opacity(PERIOD / 4), .87)
    Near(Hint.Opacity(PERIOD / 2), .78)
    Near(Hint.Opacity(PERIOD * .75), .87)
    Near(Hint.Opacity(PERIOD), .96)
    for step = 0, 1200 do
        local elapsed = step * PERIOD / 240
        local opacity = Hint.Opacity(elapsed)
        assert(opacity >= .78 - 1e-12 and opacity <= .96 + 1e-12, "透明度越界")
        Near(opacity, Hint.Opacity(elapsed + PERIOD), "透明度应周期重复")
    end
end)

Test("Attach创建单行非交互文本并立即挂入container和同步布局", function()
    WithUI(function(theme)
        local view = Fixture(.75)
        Hint.Attach(view)
        local label = view.machineSkin.shakeHint
        local props = label.props
        assert(Hint.TEXT == "摇晃手机/按住瓶子摇晃" and props.text == Hint.TEXT)
        assert(#view.container.children == 1 and view.container.children[1] == label)
        assert(props.id == "shakeHint" and props.pointerEvents == "none" and props.zIndex == 22)
        assert(props.fontFamily == "sans" and props.fontColor == theme.colors.textSecondary)
        assert(props.textMotionDisabled and props.whiteSpace == "nowrap" and props.maxLines == 1)
        assert(props.textAlign == "center" and props.verticalAlign == "middle" and props.padding == 0)
        Near(props.opacity, Hint.Opacity(0), "首帧即使用呼吸亮度，避免全亮跳变")
        assert(label:IsVisible() and type(label.Update) == "function")
        BoardRect(view, HEIGHT)
        local blocked = Fixture()
        blocked.startScreen.active = true
        Hint.Attach(blocked)
        assert(not blocked.machineSkin.shakeHint:IsVisible(), "Attach当帧不能漏出菜单后的提示")
    end)
end)

Test("Update保留原更新、推进呼吸、量化透明度并跳过相同值写入", function()
    WithUI(function()
        local view = Fixture()
        Hint.Attach(view)
        local label = view.machineSkin.shakeHint
        label:Update(0)
        assert(label.baseUpdates == 1 and label.lastBaseDt == 0)
        Near(label.props.opacity, QuantizedOpacity(0))
        local writes = label.opacityWrites
        label:Update(0)
        assert(label.opacityWrites == writes, "相同透明度不应重复SetStyle")
        label:Update(.6)
        assert(label.baseUpdates == 3 and label.lastBaseDt == .6)
        Near(label.baseTime, .6)
        Near(label.props.opacity, QuantizedOpacity(.6))
        label:Update(.6)
        Near(label.props.opacity, QuantizedOpacity(1.2))
        label:Update(1.2)
        Near(label.props.opacity, QuantizedOpacity(0))
        assert(view.game.elapsed == 0 and view.game.score == 0 and view.game.revision == 0,
            "提示Update不能推进规则时钟或改写对局")
    end)
end)

Test("隐藏时仍同步及调用原Update但冻结提示时钟，重现时接着推进", function()
    WithUI(function()
        local view = Fixture()
        Hint.Attach(view)
        local label = view.machineSkin.shakeHint
        label:Update(.6)
        local opacity, writes = label.props.opacity, label.opacityWrites
        view.detailOverlay:SetVisible(true)
        label:Update(7)
        assert(not label:IsVisible() and label.baseUpdates == 2 and label.lastBaseDt == 7)
        assert(label.props.opacity == opacity and label.opacityWrites == writes)
        view.detailOverlay:SetVisible(false)
        label:Update(0)
        assert(label:IsVisible())
        Near(label.props.opacity, QuantizedOpacity(.6))
        label:Update(.6)
        Near(label.props.opacity, QuantizedOpacity(1.2))
        view.game.stage = 2
        label:Update(9)
        assert(not label:IsVisible())
        BoardRect(view, 0)
        view.game.stage = 1
        label:Update(0)
        assert(label:IsVisible())
        Near(label.props.opacity, QuantizedOpacity(1.2))
        BoardRect(view, HEIGHT)
    end)
end)

Test("负dt不倒退提示时钟，大dt按周期取模", function()
    WithUI(function()
        local view = Fixture()
        Hint.Attach(view)
        local label = view.machineSkin.shakeHint
        label:Update(.6)
        local opacity = label.props.opacity
        label:Update(-10)
        assert(label.props.opacity == opacity)
        label:Update(PERIOD * 17 + .6)
        Near(label.props.opacity, QuantizedOpacity(1.2))
    end)
end)

Test("多个Attach实例的动画时钟独立且支持没有原Update的Label", function()
    WithUI(function()
        local first, second = Fixture(), Fixture()
        Hint.Attach(first)
        Hint.Attach(second)
        first.machineSkin.shakeHint:Update(.6)
        second.machineSkin.shakeHint:Update(1.2)
        Near(first.machineSkin.shakeHint.props.opacity, QuantizedOpacity(.6))
        Near(second.machineSkin.shakeHint.props.opacity, QuantizedOpacity(1.2))
        first.machineSkin.shakeHint:Update(.6)
        Near(first.machineSkin.shakeHint.props.opacity, QuantizedOpacity(1.2))
        Near(second.machineSkin.shakeHint.props.opacity, QuantizedOpacity(1.2))
    end)
    WithUI(function()
        local view = Fixture()
        Hint.Attach(view)
        view.machineSkin.shakeHint:Update(.6)
        Near(view.machineSkin.shakeHint.props.opacity, QuantizedOpacity(.6))
        assert(view.machineSkin.shakeHint.baseUpdates == 0)
    end, true)
end)

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.ShakeHintTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end

return Tests
