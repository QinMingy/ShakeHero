-- 开始页：自绘天空渐变背景，游戏道具随机从天而降；
-- 按进行中存档切换开始／继续入口；新局确认复用移除物品弹窗。
-- 标题从画面上方落入、白转浅金；点击开始后整页淡出并交还牌桌。
local UI = require("urhox-libs/UI")
local L = require("Machine.LayeredLayout")
local Art = require("Bottle.Art")
local GameAudio = require("Bottle.Audio")
local Storage = require("Bottle.Storage")
local Confirmation = require("Bottle.RemovalConfirm")
local TitleLogo = require("Bottle.TitleLogo")

---@class BottleStartScreen
---@field view any
---@field root Panel
---@field brand Panel
---@field title Widget
---@field subtitle Label
---@field titleIntroElapsed number
---@field startButton Button
---@field exitButton Button
---@field newRunButton Button
---@field newRunConfirm any
---@field active boolean
---@field closing boolean
---@field exitElapsed number
---@field masked Widget[]
local StartScreen = {}
StartScreen.__index = StartScreen

local INK = {240, 232, 200, 255}
local MUTED = {175, 174, 146, 255}
local BORDER = {120, 124, 103, 255}

-- 从天而降的道具：已实装/可绘制精灵中挑选的辨识度高的一批。
local FALL_IDS = {
    "apple", "banana", "orange", "cherry", "ball", "seed", "tomato", "egg",
    "balloon", "knife", "credit_card", "star", "coin_one", "coin_two",
    "die_d6", "droplet",
}

-- 私有 Park-Miller 随机源：开始页纯表现，不碰全局 math.random、不影响玩法序列。
---@param seed integer
---@return fun():number
local function makeRng(seed)
    local s = seed % 2147483647
    if s <= 0 then s = s + 2147483646 end
    return function()
        s = (s * 16807) % 2147483647
        return s / 2147483647
    end
end

---@param view any
---@return BottleStartScreen
function StartScreen.New(view)
    local self = setmetatable({}, StartScreen)
    self.view = view
    self.active = true
    self.closing = false
    self.exitElapsed = 0.0
    self.masked = {}
    self.rng = makeRng(math.floor(os.time() % 2147483646) + 1)
    self.titleScale, self.titleVel = 1.0, 0.0
    self.titleAngle, self.titleAngVel = 0.0, 0.0
    self.pulseTimer = 0.0
    self.floatTime = 0.0
    self.titleIntroElapsed = 0.0
    self.fallItems = {}
    self:Build()
    self.newRunConfirm = Confirmation.New(view, "newRunConfirm")
    self:InitFalling()
    self:Layout()
    self:MaskGameUi()
    print("[开始页] 实习造物主 · 金色像素标题从上方降下，白色过渡至金色")
    return self
end

function StartScreen:Build()
    local screen = self
    self.root = UI.Panel {
        position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
        -- z34：必须排在机台后效合成节点（z35）之前，否则不会进入本帧 UI 捕获。
        zIndex = 34, pointerEvents = "auto", backgroundColor = {0, 0, 0, 0}, overflow = "hidden",
        onClick = function() end,
    }
    -- 天空渐变背景：上浅下深，给道具雨留出纵深。
    local sky = UI.Widget {position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
        pointerEvents = "none"} --[[@as any]]
    function sky:Render(vg)
        local b = self:GetAbsoluteLayout()
        if b.w <= 0 or b.h <= 0 then return end
        local p = nvgLinearGradient(vg, b.x, b.y, b.x, b.y + b.h,
            nvgRGBA(20, 34, 40, 255), nvgRGBA(7, 11, 12, 255))
        nvgBeginPath(vg); nvgRect(vg, b.x, b.y, b.w, b.h)
        nvgFillPaint(vg, p); nvgFill(vg)
    end
    self.root:AddChild(sky)

    -- 道具雨层：纯绘制，状态由 StartScreen:Update 驱动。
    local fall = UI.Widget {position = "absolute", left = 0, top = 0, width = "100%", height = "100%",
        pointerEvents = "none"} --[[@as any]]
    function fall:Render(vg)
        screen:RenderFalling(self, vg)
    end
    self.fallWidget = fall
    self.root:AddChild(fall)

    self.brand = UI.Panel {id = "startBrand", position = "absolute", left = 0, top = 0,
        width = "100%", height = 156, padding = 0, pointerEvents = "none",
        backgroundColor = {0, 0, 0, 0}, transformOrigin = "center"}
    local title = UI.Widget {id = "startTitle", position = "absolute", left = 0, top = 0, width = "100%",
        height = 120, pointerEvents = "none"} --[[@as any]]
    function title:Render(vg)
        screen:RenderTitle(self, vg)
    end
    self.title = title
    self.subtitle = UI.Label {
        text = TitleLogo.SUBTITLE, fontColor = TitleLogo.Color(0), textAlign = "center", verticalAlign = "middle",
        whiteSpace = "normal", position = "absolute", width = "100%", pointerEvents = "none",
        fontFamily = "pixel",
        textMotionDisabled = true,
        textShadow = {offsetX = 2, offsetY = 2, blur = 0, color = {8, 11, 10, 210}},
    }
    local function option(text, onClick, primary)
        local button = GameAudio.Button {text = text, onClick = onClick}
        button:SetStyle({
            position = "absolute", fontWeight = "bold", textColor = primary and INK or MUTED,
            borderWidth = 2, borderColor = BORDER, paddingHorizontal = 0,
            backgroundColor = primary and {52, 74, 58, 245} or {34, 42, 37, 240},
            hoverBackgroundColor = primary and {64, 92, 70, 250} or {46, 56, 48, 245},
            pressedBackgroundColor = primary and {40, 56, 44, 250} or {26, 32, 28, 245},
            boxShadow = {{x = 3, y = 3, blur = 0, color = {7, 10, 8, 210}}},
        })
        return button
    end
    self.startButton = option("开始游戏", function() self:Activate() end, true)
    self.newRunButton = option("开始新游戏", function() self:RequestNewRun() end, false)
    self.exitButton = option("退出", function() self:Exit() end, false)

    self.brand:AddChild(self.title)
    self.brand:AddChild(self.subtitle)
    self.root:AddChild(self.brand)
    self.root:AddChild(self.startButton)
    self.root:AddChild(self.newRunButton)
    self.root:AddChild(self.exitButton)
    self.view.container:AddChild(self.root)
end

function StartScreen:InitFalling()
    local count = 22
    for i = 1, count do
        local p = {}
        self.fallItems[i] = p
        self:RespawnFalling(p)
        -- 首次铺满整屏，避免开场上半截空白。
        p.y = self.rng() * L.height
    end
end

---@param p table
function StartScreen:RespawnFalling(p)
    p.id = FALL_IDS[math.floor(self.rng() * #FALL_IDS) + 1]
    p.r = 13 + self.rng() * 13
    -- 横向留出半径余量，精灵不贴边、不超出机台边框。
    p.x = p.r + self.rng() * (L.width - p.r * 2)
    p.y = -24 - self.rng() * 60
    p.vy = 34 + self.rng() * 78
    p.vx = (self.rng() * 2 - 1) * 16
    p.spin = (self.rng() * 2 - 1) * 1.7
    p.angle = self.rng() * math.pi * 2
    p.alpha = 0.45 + self.rng() * 0.5
end

---@param w Widget
---@param vg NVGContextWrapper
function StartScreen:RenderFalling(w, vg)
    local b = w:GetAbsoluteLayout()
    if b.w <= 0 or b.h <= 0 then return end
    local sx, sy = b.w / L.width, b.h / L.height
    -- 裁剪到机台边框内，飘落道具不溢出到四周留白。
    nvgSave(vg)
    nvgIntersectScissor(vg, b.x, b.y, b.w, b.h)
    for _, p in ipairs(self.fallItems) do
        nvgSave(vg)
        nvgGlobalAlpha(vg, p.alpha)
        Art.Item(vg, p.id, b.x + p.x * sx, b.y + p.y * sy, p.r * sx, p.angle, false)
        nvgRestore(vg)
    end
    nvgRestore(vg)
end

-- 标题只读动画进度；整体入场和空闲运动由同一UI视觉层承载。
---@param w Widget
---@param vg NVGContextWrapper
function StartScreen:RenderTitle(w, vg)
    local b = w:GetAbsoluteLayout()
    if b.w <= 0 or b.h <= 0 then return end
    TitleLogo.Draw(vg, b, TitleLogo.Pose(self.titleIntroElapsed).colorProgress)
end

function StartScreen:SyncTitle()
    local s = (self.view.machineSkin and self.view.machineSkin.scale) or 1
    local pose = TitleLogo.Pose(self.titleIntroElapsed)
    local float = pose.settled and math.sin(self.floatTime * math.pi * 2 / 2.7) * 1.5 or 0
    self.brand:SetStyle({translateY = (pose.offsetY + float) * s,
        scale = self.titleScale, rotate = math.deg(self.titleAngle)})
    if self.lastTitleColor ~= pose.colorProgress then
        self.subtitle:SetStyle({fontColor = TitleLogo.Color(pose.colorProgress)})
        self.lastTitleColor = pose.colorProgress
    end
end

function StartScreen:Layout()
    local m = self.view.machineSkin
    local s = (m and m.scale) or 1
    local width = L.width * s
    self.root:SetStyle({width = width, height = L.height * s})
    self.brand:SetStyle({left = 0, top = 218 * s, width = width, height = 156 * s})
    self.title:SetStyle({left = 0, top = 0, width = width, height = 120 * s})
    self.subtitle:SetStyle({left = 0, top = 124 * s, width = width, height = 28 * s,
        fontSize = 14 * s, letterSpacing = 2 * s})
    self:SyncTitle()
    local buttonW, buttonH = 240 * s, 64 * s
    local left = (L.width - 240) * .5 * s
    local hasRun = self:HasRun()
    self.startButton:SetText(hasRun and "继续游戏" or "开始游戏")
    self.newRunButton:SetVisible(hasRun)
    self.startButton:SetStyle({left = left, top = 492 * s, width = buttonW, height = buttonH,
        fontSize = 20 * s})
    self.newRunButton:SetStyle({left = left, top = 570 * s, width = buttonW, height = buttonH,
        fontSize = 20 * s})
    self.exitButton:SetStyle({left = left, top = (hasRun and 648 or 570) * s, width = buttonW, height = buttonH,
        fontSize = 17 * s})
end

-- 开始页期间收起游戏入口，避免背景桌被误触。
function StartScreen:MaskGameUi()
    if not self.active then return end
    local m = self.view.machineSkin
    if not m then return end
    if #self.masked == 0 then
        for _, widget in ipairs({self.view.footer, self.view.deckButton,
            self.view.mainMenuButton,
            m.help}) do
            if widget then self.masked[#self.masked + 1] = widget end
        end
    end
    for _, widget in ipairs(self.masked) do widget:Hide() end
end

---@return boolean
function StartScreen:IsActive()
    return self.active
end

---@return boolean
function StartScreen:HasRun()
    return Storage.runStarted and self.view.game.phase ~= "over"
end

function StartScreen:StartNewRun()
    if not self.active or self.closing then return end
    if self.view.actions.newrun() == false then return end
    self:Close()
end

-- 鼠标和键盘共用入口；确认框打开时不能透过遮罩继续游戏。
function StartScreen:Activate()
    if not self.active or self.closing or self.newRunConfirm:IsOpen() then return end
    if self:HasRun() then self:Close() else self:StartNewRun() end
end

function StartScreen:RequestNewRun()
    if not self.active or self.closing or self.newRunConfirm:IsOpen() then return end
    if not self:HasRun() then self:StartNewRun(); return end
    self.newRunConfirm:OpenMessage("开始新游戏", "上局游戏进度将会丢失，是否开始新游戏？",
        function() self:StartNewRun() end,
        function() return self.active and not self.closing and self:HasRun() end)
end

function StartScreen:Close()
    if not self.active or self.closing then return end
    if self.newRunConfirm:IsOpen() then return end
    self.closing = true
    self.exitElapsed = 0
    self.startButton:SetDisabled(true)
    self.newRunButton:SetDisabled(true)
    self.exitButton:SetDisabled(true)
    print("[开始页] 开始游戏")
end

-- 从游戏内返回主菜单：重新显示开始页并暂停回合，游戏状态保留。
-- 继续游戏从内存中的原阶段恢复，不重置对局。
function StartScreen:Open()
    if self.active then return end
    self.active = true
    self.closing = false
    self.exitElapsed = 0
    self.pulseTimer = 0
    self.titleScale, self.titleVel = 1, 0
    self.titleAngle, self.titleAngVel = 0, 0
    self.titleIntroElapsed, self.floatTime = 0, 0
    self.root:SetStyle({opacity = 1})
    self.root:Show()
    self.startButton:SetDisabled(false)
    self.newRunButton:SetDisabled(false)
    self.exitButton:SetDisabled(false)
    self.masked = {}
    self:Layout()
    self.view:Update(true)
    self:MaskGameUi()
    print("[开始页] 返回主菜单")
end

function StartScreen:Exit()
    if self.closing or self.newRunConfirm:IsOpen() then return end
    print("[开始页] 请求退出游戏")
    local ok, err = pcall(function() engine:Exit() end)
    if not ok then
        print("[开始页] 当前平台无法退出：" .. tostring(err))
        UI.Toast.Show("当前平台不支持退出", {duration = 2, variant = "info"})
    end
end

-- 标题弹性缩放/摇晃的欠阻尼弹簧：每2秒踢一脚，过冲后稳定回1。
local TITLE_STIFFNESS, TITLE_DAMPING = 160, 9
local TITLE_SCALE_KICK, TITLE_ANGLE_KICK = .6, .35

-- 解析弹簧避免大dt时标题/细框爆振，仍保留原有每2秒的轻回弹。
local function titleSpring(value, velocity, target, dt)
    local damping = TITLE_DAMPING / 2
    local wave = math.sqrt(TITLE_STIFFNESS - damping*damping)
    local delta = value - target
    local cosine, sine, decay = math.cos(wave*dt), math.sin(wave*dt), math.exp(-damping*dt)
    return target + decay*(delta*cosine + (velocity + damping*delta)/wave*sine),
        decay*(velocity*cosine - (damping*velocity + TITLE_STIFFNESS*delta)/wave*sine)
end

---@param dt number
function StartScreen:Update(dt)
    if not self.active then return end
    dt = math.max(0, dt)
    for _, p in ipairs(self.fallItems) do
        p.y = p.y + p.vy * dt
        p.x = p.x + p.vx * dt
        p.angle = p.angle + p.spin * dt
        if p.y > L.height + 60 then self:RespawnFalling(p) end
    end

    if self.closing then
        self.exitElapsed = self.exitElapsed + dt
        local fade = math.max(0, 1 - self.exitElapsed / .4)
        self.root:SetStyle({opacity = fade})
        if self.exitElapsed >= .4 then
            self.active = false
            self.root:Hide()
            for _, widget in ipairs(self.masked) do widget:Show() end
            self.masked = {}
            self.view:Update(true)
            print("[开始页] 已进入牌桌")
            return
        end
    else
        local remaining = math.max(0, TitleLogo.DURATION - self.titleIntroElapsed)
        self.titleIntroElapsed = math.min(TitleLogo.DURATION, self.titleIntroElapsed + dt)
        local idleDt = math.max(0, dt - remaining)
        self.pulseTimer = self.pulseTimer + idleDt
        while self.pulseTimer >= 2.0 do
            self.pulseTimer = self.pulseTimer - 2.0
            self.titleVel = self.titleVel + TITLE_SCALE_KICK
            self.titleAngVel = self.titleAngVel + (self.rng() * 2 - 1) * TITLE_ANGLE_KICK
        end
        self.titleScale, self.titleVel = titleSpring(self.titleScale, self.titleVel, 1, idleDt)
        self.titleAngle, self.titleAngVel = titleSpring(self.titleAngle, self.titleAngVel, 0, idleDt)
        self.floatTime = self.floatTime + idleDt
        self:SyncTitle()
    end
    self:MaskGameUi()
end

return StartScreen
