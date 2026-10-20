-- 独立原生验收入口：新建内存对局，不加载／保存玩家档，不开放发布GM接口。
local UI = require("urhox-libs/UI")
local CoreUI = require("urhox-libs.UI.Core.UI")
local Game = require("Bottle.Game")
local Physics = require("Bottle.Physics")
local View = require("Bottle.View")
local Hint = require("Bottle.ShakeHint")
local Skin = require("Machine.LayeredSkin")
---@type any
local view = nil
local frame, checks = 0, 0

local function Check(value, message)
    assert(value, "[瓶下提示验收] " .. message)
    checks = checks + 1
end

local function Layout()
    Skin.Layout(view)
    CoreUI.Layout()
end

local function Bounds()
    local label = view.machineSkin.shakeHint
    local b, h = view.board:GetAbsoluteLayout(), label:GetAbsoluteLayout()
    Check(math.abs(b.y + b.h - h.y) < 1, "瓶区与文字带相邻")
    Check(h.w > UI.MeasureTextWidth(Hint.TEXT, label.props.fontSize, "sans"), "完整文案不截断")
    local _, floorY = view.board:GetBottleTransform()
    Check(floorY < h.y, "静止瓶底在文字带上方")
    -- 最大纵向摆幅；沿用Board真实映射，不用假定的瓶子像素尺寸。
    local _, _, ppu = view.board:GetBottleTransform()
    Check(floorY + .36 * ppu < h.y + (h.h - label.props.fontSize) / 2,
        "最大向下摆动不触及文字")
    Check(label.props.pointerEvents == "none", "提示不拦截输入")
end

function Start()
    input.mouseMode = MM_ABSOLUTE
    UI.Init({theme = require("Bottle.Theme"), scale = UI.Scale.DEFAULT})
    require("Machine.Palette").Init()
    require("Bottle.ButtonMotion").Init()
    local game = Game.New(20261020)
    local physics = Physics.New()
    physics:Sync(game:BottleItems(), true, game.revision)
    local function noop() end
    view = View.New(game, physics, {shake=noop, start=noop, reroll=noop,
        refresh=noop, choose=noop, skip=noop, newrun=noop, import=noop,
        sensor=noop, sensorGain=noop, sensorLab=noop, atmosphere=noop,
        remove=noop, gmadd=noop, juicer=noop})
    view.machineSkin.litScene:ToggleCameraMotion()
    SubscribeToEvent("Update", "HandleShakeHintValidationUpdate")
    SubscribeToEvent("PostUpdate", "HandleShakeHintValidationPrepare")
    print("[瓶下提示验收] 独立内存场景启动，不读写玩家存档")
end

function HandleShakeHintValidationUpdate()
    frame = frame + 1
    if frame == 12 then
        Check(view.machineSkin.shakeHint.props.text == Hint.TEXT, "真实Label文案正确")
        Layout()
        Check(view.machineSkin.shakeHint:IsVisible(), "准备阶段可见")
        Bounds()
    elseif frame == 16 then
        for _, phase in ipairs({"running", "settle", "reveal"}) do
            view.game.phase = phase
            Hint.Sync(view)
            Check(view.machineSkin.shakeHint:IsVisible(), phase .. "可见")
        end
        view.game.phase, view.game.options = "draft", {"apple", "ball", "grass"}
        view:Update(true)
        Layout()
        Check(view.machineSkin.shakeHint:IsVisible(), "三选一阶段可见")
        local draft = assert(view.draft:FindById("draftDisplay"))
        local d, h = draft:GetAbsoluteLayout(), view.machineSkin.shakeHint:GetAbsoluteLayout()
        Check(math.abs(d.y + d.h - h.y) < 1, "候选说明不覆盖提示带")
    elseif frame == 20 then
        view.game.stage = 2
        Hint.Sync(view)
        Check(not view.machineSkin.shakeHint:IsVisible(), "首次考核后隐藏")
        view.game.stage, view.game.phase = 1, "over"
        Hint.Sync(view)
        Check(not view.machineSkin.shakeHint:IsVisible(), "首次考核失败后隐藏")
        view.game.phase = "prepare"
        view:Update(true)
        Layout()
        view.modal:Show(); Hint.Sync(view)
        Check(not view.machineSkin.shakeHint:IsVisible(), "规则弹层遮挡")
        view.modal:Hide(); Hint.Sync(view)
        Check(view.machineSkin.shakeHint:IsVisible(), "关闭弹层恢复")
        print("[瓶下提示验收] PASS 原生断言=" .. checks)
    end
end

function HandleShakeHintValidationPrepare()
    if view then view.machineSkin.litScene.post:PrepareFrame() end
end

function Stop()
    if view then UI.SetRoot(nil); view.root:Destroy(); view.physics:Clear() end
    UI.Shutdown()
end
