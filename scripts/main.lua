-- 基于 scaffold-2d-physics：引擎原生Scene/Box2D独立推进，规则与表现预算分帧。
local UI = require("urhox-libs/UI")
local Game = require("Bottle.Game")
local Physics = require("Bottle.Physics")
local View = require("Bottle.View")
local Storage = require("Bottle.Storage")
local TouchController = require("urhox-libs.Input.TouchController")
local PlatformUtils = require("urhox-libs.Platform.PlatformUtils")
local TextMotion = require("Bottle.TextMotion")
local ButtonMotion = require("Bottle.ButtonMotion")
local GameAudio = require("Bottle.Audio")
local RelicEffects = require("Bottle.RelicEffects")
local Relics = require("Bottle.Relics")
local RelicView = require("Bottle.RelicView")
local StartScreen = require("Bottle.StartScreen")
local Tutorial = require("Bottle.Tutorial")
local DeveloperOverlay = require("Machine.DeveloperOverlay")
local PublishConfig = require("PublishConfig")
local SensorLab = require("Bottle.SensorLab")
local SensorTuning = require("Bottle.SensorTuning")
local Simulation = require("Bottle.Simulation")

-- WebGPU 校验 SetScissorRect 必须落在渲染区域内：全屏 scissor 按 ceil(逻辑尺寸 × scale) 取设备像素。
-- UI.Scale.DEFAULT 在部分窗口下（如 449×1000、DPR=3 → scale=1.875）会发生浮点往返上浮：
-- (1000 / 1.875) * 1.875 = 1000.0000000000001 → ceil → 1001 > 1000，
-- 整帧 CommandBuffer 被拒（Scissor rect is not contained in the render area）。
-- 这里在 DEFAULT 基础上按 ulp 向上微调 scale，保证 (尺寸/scale)*scale ≤ 物理尺寸；
-- 分辨率变化时 UI 库会重新调用本函数，微调量 <1e-14，视觉无差异。
---@param x number
---@return number
local function NextUp(x)
    local bits = string.unpack("<i8", string.pack("<d", x))
    return (string.unpack("<d", string.pack("<i8", bits + 1)))
end

---@return number
local function SafeUIScale()
    local base = UI.Scale.DPR_DENSITY_ADAPTIVE()
    local w, h = graphics:GetWidth(), graphics:GetHeight()
    if not (base > 0) or not (w > 0 and h > 0) then return base end
    local scale = base
    for _ = 1, 64 do
        if (w / scale) * scale <= w and (h / scale) * scale <= h then return scale end
        scale = NextUp(scale)
    end
    print("[界面] UI scale 浮点微调未收敛，沿用原值：" .. tostring(base))
    return base
end

---@type BottleGame?
local game = nil
---@type BottlePhysics?
local physics = nil
---@type any
local view = nil
---@type BottleSensorLab?
local sensorLab = nil
---@type BottleSimulation?
local simulation = nil
local sensorEnabled = false
local sensorSampled = false
---@type number
local sensorWait = 0
local lastSensorNotice = "off"
local SENSOR_READY_TIMEOUT = 2 -- 秒；开启异步注册，不能把首帧空读认作永久不支持。

local function ResetSensor()
    sensorSampled = false
    if physics then physics.motion:ResetSensor() end
    if sensorLab then sensorLab:Reset() end
end

local function SensorStatus(status, notify)
    if view then view:SetSensorStatus(status) end
    if lastSensorNotice == status then return end
    lastSensorNotice = status
    print("[体感] 平台=" .. PlatformUtils.GetPlatform() .. " 状态=" .. status)
    if not notify then return end
    local messages = {
        available = "已收到体感数据，可以左右／上下摇动手机",
        unavailable = "暂未收到体感数据；可重新校准或按住瓶子来回摇",
        unsupported = PlatformUtils.IsWebPlatform()
            and "网页预览不支持当前体感接口；请用手机原生端或触摸拖动"
            or "当前运行端不支持体感，请按住瓶子来回摇",
        waiting = "正在启用体感，请稍等并轻轻摇动手机",
        lab_available = "已接通 Wi-Fi 手机，摇动手机即可控制瓶子",
        lab_waiting = "等待 Wi-Fi 手机输入；请在实验台扫码并启用传感器",
        lab_unavailable = "Wi-Fi 手机数据已中断，瓶子已回中；恢复后会自动校准",
    }
    local message = messages[status]
    if message then
        UI.Toast.Show(message, {duration = 3, variant = status == "available" and "success" or "info"})
    end
end

local function Sensor(notify)
    ResetSensor()
    -- 用户重复点击也要给出说明；自动轮询状态仍只提示一次。
    if notify then lastSensorNotice = "off" end
    local native = PlatformUtils.IsAndroid() or PlatformUtils.IsIOS()
    if not native then
        sensorEnabled = false
        if sensorLab and sensorLab.enabled and sensorLab.configured and physics then
            SensorStatus("lab_waiting", notify)
            return
        end
        SensorStatus("unsupported", notify)
        return
    end
    local ok, errorText = pcall(TouchController.EnableAccelerometer)
    sensorEnabled = ok
    sensorWait = ok and SENSOR_READY_TIMEOUT or 0
    if not ok then print("[体感] 开启失败：" .. tostring(errorText)) end
    SensorStatus(ok and "waiting" or "unavailable", notify)
end

local saveWarningShown = false

local function Save(notify)
    if not game then return false end
    local saved = Storage.Save(game)
    if saved then
        saveWarningShown = false
    elseif notify ~= false and view and not saveWarningShown then
        saveWarningShown = true
        local message = Storage.readBlocked
            and "旧存档暂时无法读取，已禁止覆盖；请重新进入游戏重试"
            or "本次进度未能保存，已保留上次存档；请稍后重试，暂勿退出游戏"
        UI.Toast.Show(message, {duration = 5, variant = "warning"})
    end
    return saved
end

local function SyncPhysics(reset)
    if not game or not physics then return end
    physics:Sync(game:BottleItems(), reset, game.revision, {
        accelerator = Relics.Has(game, "accelerator"),
        ghostPoop = Relics.Has(game, "ghost_poop"),
    })
end

local function WorkPending()
    return simulation ~= nil and simulation:Busy()
end

local function PublishRelicFeedback(events)
    GameAudio.RelicTrigger(RelicView.Trigger(view, events))
end

local function ResetSimulation()
    if simulation then simulation:Dispose() end
    if not game or not physics or not view then simulation = nil; return end
    view.relicFeedbackOwner = game
    RelicView.Reset(view)
    simulation = Simulation.New(game, physics, {
        bind = function(displayGame, pending)
            view.game, view.board.game = displayGame, displayGame
            view.simulationPending, view.board.simulationPending = pending, pending
        end,
        events = function(events, physicsSnapshot)
            view.board:Effects(events, physicsSnapshot)
            for _, event in ipairs(events) do
                if event.kind == "dash" then GameAudio.Calf() end
            end
        end,
        sync = function() SyncPhysics(false) end,
        publish = PublishRelicFeedback,
    })
    view.simulationClock = simulation:Clock()
end

local function Refresh(reset)
    if not game or not physics or not view or WorkPending() then return end
    -- reset 时用 revision 作洗牌种子：重抽/新回合 revision 必变，布局才会刷新。
    SyncPhysics(reset)
    view:Update(true)
    Save()
end

local function StartRound()
    if not game or not view or WorkPending() then return end
    if view.tutorial and not view.tutorial:OnStartRequested() then return end
    view.modal:Hide()
    view.inventoryOpen = false
    view.deckDetailUid = 0
    view:DisposeDeckSim()
    if view.physicsButton then view.physicsButton:SetVisible(DeveloperOverlay.IsAllowed(view)) end
    if game:Start() then
        if view.tutorial then view.tutorial:OnStarted() end
        -- 篮筐沿用准备阶段位置；开始按钮不重新随机设施。
        if simulation then simulation:ResetClock() end
        ResetSensor()
        -- 自动启用失败或设备断开后，开始按钮再试一次；仍保留触摸操作。
        if lastSensorNotice ~= "available" and lastSensorNotice ~= "lab_available" then Sensor(false) end
        SyncPhysics(false)
        physics:RememberEvents(game.startEvents)
        view:Update(true)
        view.board:Effects(game.startEvents)
        PublishRelicFeedback(game.startEvents)
        game.startEvents = {}
        Save()
        print(string.format("[回合] 开始 %d，入瓶 %d，余额 %.0f，目标 %.0f", game.round,
            #game:BottleItems(), game.score, game.target))
    end
end

local function NewRun()
    if not view or not physics then return false end
    if simulation then simulation:Dispose() end
    game = Game.New(math.floor(os.time() % 2147483646) + 1)
    Storage.runStarted = true
    Storage.RestartTutorial()
    physics:Clear()
    if sensorLab then sensorLab:Reset() end
    SyncPhysics(true)
    view.simulationPending, view.board.simulationPending = false, false
    view:Rebind(game)
    ResetSimulation()
    if view.tutorial then view.tutorial:Rebind(false) end
    Save()
    print("[对局] 新局：小羊、小草、苹果、小球各一件")
    return true
end

local function Import(text)
    local snapshot, errorText, atmosphereMode = Storage.Import(text)
    if not snapshot then return false, errorText end
    local ok, restored = pcall(Game.Restore, snapshot)
    if not ok then
        print("[存档] 导入校验失败：" .. tostring(restored))
        return false, "存档内容不完整或版本不兼容"
    end
    if not view or not physics then return false, "游戏尚未就绪" end
    if simulation then simulation:Dispose() end
    game = restored
    Storage.runStarted = true
    Storage.SetAtmosphere(atmosphereMode or "auto")
    sensorSampled = false
    physics:Clear()
    if sensorLab then sensorLab:Reset() end
    -- 存档含 revision：同一份存档恢复出同一布局，保持可复现。
    SyncPhysics(true)
    view.simulationPending, view.board.simulationPending = false, false
    view:Rebind(game)
    ResetSimulation()
    if view.tutorial then view.tutorial:Rebind(true) end
    Save()
    return true, nil
end

local function SetSensorGain(value, persist)
    if PublishConfig.PUBLISH_MODE ~= false or not physics then return false end
    if not Storage.SetSensorGain(value) then return false end
    physics.motion:SetSensorGain(Storage.sensorGain)
    -- 滑动时只更新倍率，松手/点快捷档才写盘，避免逐触摸事件保存造成卡顿。
    if persist then
        Save()
        print(string.format("[体感GM] 系数 %.2f×", Storage.sensorGain))
    end
    return true
end

local function SetSensorLabEnabled(enabled)
    if PublishConfig.PUBLISH_MODE ~= false or not sensorLab then return false end
    local ok = sensorLab:SetEnabled(enabled)
    ResetSensor()
    if view then view:SetSensorLabState(sensorLab:GetState()) end
    if enabled and not ok then
        UI.Toast.Show("请先运行体感实验台 start-wifi.cmd，再重新打开本地游戏", {duration = 3, variant = "info"})
    end
    if not enabled then Sensor(false) end
    return ok
end

local function UpdateSensorLab(dt, canApply)
    if not sensorLab or not physics or not view then return end
    sensorLab:Update(dt, canApply, physics.motion.holding)
    if PublishConfig.PUBLISH_MODE == false then
        local settings = sensorLab:TakeSettings()
        if settings and SetSensorGain(settings.gain, false) and view.RefreshSensorGm then view.RefreshSensorGm() end
    end
    local info = sensorLab:GetState()
    view:SetSensorLabState(info)
    if info.enabled and info.configured then
        SensorStatus(info.available and "lab_available" or info.status == "stale" and "lab_unavailable" or "lab_waiting", false)
    end
end

function Start()
    graphics.windowTitle = "摇摇上帝"
    input.mouseMode = MM_ABSOLUTE
    -- scale 传函数：初始化与窗口尺寸变化时都会重新计算，浮点安全微调随之生效。
    UI.Init({theme = require("Bottle.Theme"), scale = SafeUIScale})
    require("Machine.Palette").Init()
    ButtonMotion.Init()
    GameAudio.Init()
    print("[界面] 机台手绘字形主题已启用")
    local tests = require("Bottle.Tests")
    local passed, result = pcall(tests.Run)
    if not passed then error("[规则自检] " .. tostring(result)) end
    result = result + require("Bottle.TutorialStateTests").Run()
        + require("Bottle.TutorialHandMotionTests").Run()
    print("[规则自检] 全部通过，共 " .. result .. " 项")

    local snapshot = Storage.Load()
    if snapshot then
        local ok, restored = pcall(Game.Restore, snapshot)
        if ok then game = restored else print("[存档] 无法恢复，开启新局：" .. tostring(restored)) end
    end
    if not game then game = Game.New(math.floor(os.time() % 2147483646) + 1) end
    physics = Physics.New()
    physics.motion:SetSensorGain(Storage.sensorGain)
    SyncPhysics(true)
    sensorLab = SensorLab.New()
    view = View.New(game, physics, {
        start = StartRound,
        shake = function(dx, dy)
            -- 输入只记录目标；刚体/惯性由下一次原生物理步消费。
            if game and physics and simulation and simulation:Clock().phase == "running"
                and (not view.tutorial or view.tutorial:Allows("shake")) then physics:Shake(dx, dy) end
        end,
        reroll = function()
            if WorkPending() then return end
            if view.tutorial and not view.tutorial:Allows("reroll") then return end
            if game and game:Reroll() then Refresh(true); print("[抽取] 本回合重抽已使用") end
        end,
        refresh = function()
            if WorkPending() then return end
            if view.tutorial and not view.tutorial:Allows("refresh") then return end
            if game and game:DraftRefresh() then
                if view.tutorial then view.tutorial:OnRefreshed() end
                view:Update(true); Save(); print("[三选一] 刷新已使用")
            end
        end,
        choose = function(index)
            if WorkPending() then return end
            if view.tutorial and not view.tutorial:Allows("choose") then return end
            local wasRelicDraft = game and game.relicDraft
            if game and game:Choose(index) then
                if view.tutorial then view.tutorial:OnChosen() end
                Refresh(true)
                if not wasRelicDraft and game.relicDraft then view.board:AddRefreshPopup() end
                print("[三选一] 选择完成，当前状态：" .. game.phase .. (game.relicDraft and "（遗物）" or ""))
            end
        end,
        skip = function()
            if WorkPending() then return end
            if view.tutorial and not view.tutorial:Allows("skip") then return end
            local wasRelicDraft = game and game.relicDraft
            if game and game:Skip() then
                Refresh(true)
                if not wasRelicDraft and game.relicDraft then view.board:AddRefreshPopup() end
                print("[三选一] 跳过完成，当前状态：" .. game.phase .. (game.relicDraft and "（遗物）" or ""))
            end
        end,
        remove = function(uid)
            if WorkPending() then return false, "正在处理物品效果，请稍后重试" end
            if not game then return false, "游戏尚未就绪" end
            local ok, message = game:RemoveOwned(uid)
            if ok then SyncPhysics(false); Save() end
            return ok, message
        end,
        newrun = NewRun, import = Import,
        juicer = function()
            if WorkPending() then return false, "正在处理物品效果，请稍后重试" end
            if not game then return false, "游戏尚未就绪" end
            local ok, message = RelicEffects.UseJuicer(game)
            if ok then
                if view then view:Update(true) end
                Save()
                print("[遗物] " .. tostring(message))
            end
            return ok, message
        end,
        sensor = function()
            if PublishConfig.PUBLISH_MODE == false then Sensor(true) end
        end, sensorGain = SetSensorGain, sensorLab = SetSensorLabEnabled,
        atmosphere = function(mode)
            if PublishConfig.PUBLISH_MODE ~= false then return end
            if not Storage.SetAtmosphere(mode) then return end
            if view then view:Update(true) end
            Save()
        end,
        gmadd = function(id)
            if WorkPending() then return false, "正在处理物品效果，请稍后重试" end
            if PublishConfig.PUBLISH_MODE ~= false then return false, "发布模式已禁用 GM" end
            if not game then return false, "游戏尚未就绪" end
            local ok, message = game:GmAddItem(id)
            if ok then
                if view then view:Update(true) end
                Save()
            end
            print("[GM] " .. tostring(message))
            return ok, message
        end,
    })
    ResetSimulation()
    view.startScreen = StartScreen.New(view)
    view.tutorial = Tutorial.New(view, {save=Save,start=StartRound})
    view.board.isPaused = function()
        return view.startScreen:IsActive() or view.tutorial:IsPaused()
    end
    view.board.animateAppearanceWhilePaused = function()
        return not view.startScreen:IsActive() and game.phase == "prepare" and view.tutorial:Active()
    end
    -- 原生手机沿用系统传感器；PC 开发态可读取已启动的本地 Wi-Fi 输入桥。
    Sensor(false)
    TextMotion.Update(0)
    ButtonMotion.Update(0)
    print("[启动] PUBLISH_MODE=" .. tostring(PublishConfig.PUBLISH_MODE)
        .. (PublishConfig.PUBLISH_MODE ~= false and "，全部 GM 已禁用" or "，允许 G 键显隐 GM"))
    -- 验收助手在 Start 之后加载；发布模式即使出现 V 也不暴露可写调试对象。
    _G["BottleValidationGet"] = function()
        if PublishConfig.PUBLISH_MODE ~= false or not _G["V"] then return nil end
        return {
            GetGame = function() return game end,
            GetView = function() return view end,
            GetPhysics = function() return physics end,
            GetStartScreen = function() return view and view.startScreen or nil end,
            GetTutorial = function() return view and view.tutorial or nil end,
            StartRound = StartRound, NewRun = NewRun,
        }
    end
    physics:SetAutoUpdate(true)
    SubscribeToEvent(physics.scene, "SceneUpdate", "HandlePhysicsSceneUpdate")
    SubscribeToEvent(physics.world, "PhysicsPreStep", "HandleNativePhysicsPreStep")
    SubscribeToEvent(physics.world, "PhysicsPostStep", "HandleNativePhysicsPostStep")
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandleRenderPrepare")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleContactBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleContactEnd")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    Save()
    print("[启动] 摇摇上帝 V0.6，单机竖屏2D，98件物品与37件遗物已实装")
end

-- SceneUpdate先于本世界子系统：只暂停物理世界，Scene保留自动更新以便恢复。
function HandlePhysicsSceneUpdate()
    if not physics or not physics.autoUpdate or physics._manualStep then return end
    local paused = not view or not simulation or (view.startScreen and view.startScreen:IsActive())
        or (view.tutorial and view.tutorial:IsPaused())
    physics.world.updateEnabled = not paused and simulation:PhysicsActive()
end

-- 2D原生前后回调每引擎物理步一次；不可yield、不可递归Scene.Update。
function HandleNativePhysicsPreStep(eventType, eventData)
    if not physics or not physics.autoUpdate or physics._manualStep or not simulation then return end
    local labInput = PublishConfig.PUBLISH_MODE == false
        and sensorLab and sensorLab.enabled and sensorLab.configured and sensorLab.input or nil
    if simulation:Clock().phase ~= "running" then
        physics:EndShake()
        physics.motion:ResetSensor()
        labInput = nil
    end
    simulation:BeforePhysics(eventData:GetFloat("TimeStep"), labInput)
end

function HandleNativePhysicsPostStep(eventType, eventData)
    if not physics or not physics.autoUpdate or physics._manualStep or not simulation then return end
    simulation:AfterPhysics(eventData:GetFloat("TimeStep"))
    if not simulation:PhysicsActive() then physics.world.updateEnabled = false end
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if not game or not physics or not view then return end
    local dt = math.max(0, eventData:GetFloat("TimeStep"))
    if view.startScreen and view.startScreen:IsActive() then
        -- 开始页期间不推进回合、体感或物理；只保留机台动画、文字浮动与按钮反馈。
        if view.tutorial then view.tutorial.overlay:Hide(true) end
        ResetSensor()
        UpdateSensorLab(dt, false)
        view:Update()
        view.startScreen:Update(dt)
        GameAudio.Update(dt)
        RelicView.Update(view, dt)
        TextMotion.Update(dt)
        ButtonMotion.Update(dt)
        return
    end
    -- 未完成批次优先续算，教程不读取半步状态。
    local resumed = WorkPending()
    if not resumed then view.tutorial:Update(dt) end
    if not resumed and view.tutorial:IsPaused() then
        if simulation then simulation:ResetClock() end
        ResetSensor()
        UpdateSensorLab(dt, false)
        view:Update()
        GameAudio.Update(dt)
        RelicView.Update(view, dt)
        TextMotion.Update(dt)
        ButtonMotion.Update(dt)
        return
    end
    do -- 续算期间仍采集输入目标，不推进规则或刚体。
        local canShake = simulation and simulation:Clock().phase == "running"
            and (not view.tutorial or view.tutorial:Allows("shake"))
        UpdateSensorLab(dt, canShake)
        if sensorEnabled and not (sensorLab and sensorLab:IsAvailable()) then
            sensorWait = math.max(0, sensorWait - dt)
            local ok, available = pcall(TouchController.IsAccelerometerAvailable)
            if ok and available then
                local readOk, ax, ay = pcall(TouchController.ReadAccelerometer)
                local valid = readOk and type(ax) == "number" and type(ay) == "number"
                    and ax == ax and ay == ay and math.abs(ax) < math.huge and math.abs(ay) < math.huge
                if valid then
                    if canShake then
                        -- 先把平台轴统一到世界坐标，再应用本版原生体感的双轴反转。
                        -- 虚拟拖动仍由固定步跟随统一计算惯性，Wi-Fi 方向由输入桥处理。
                        local worldX, worldY = ax --[[@as number]], -ay
                        if not PlatformUtils.IsAndroid() then worldX, worldY = -ax, ay --[[@as number]] end
                        worldX, worldY = SensorTuning.ApplyAxes(worldX, worldY)
                        physics:Sensor(worldX, worldY, dt)
                    else
                        physics.motion:ResetSensor()
                    end
                    if not sensorSampled then
                        print(string.format("[体感] 首样本 x=%.3f y=%.3f", ax, ay))
                    end
                    sensorSampled = true
                    sensorWait = 0
                    SensorStatus("available", true)
                else
                    ResetSensor()
                    SensorStatus("unavailable", true)
                end
            else
                ResetSensor()
                if sensorWait == 0 then SensorStatus("unavailable", true) end
            end
        end
    end
    if simulation and (resumed or game.phase == "running" or game.phase == "settle") then
        local labInput = PublishConfig.PUBLISH_MODE == false
            and sensorLab and sensorLab.enabled and sensorLab.configured and sensorLab.input or nil
        local phaseChanged = simulation:Update(dt, labInput)
        if WorkPending() then
            view:Update()
            GameAudio.Update(dt)
            RelicView.Update(view, dt)
            TextMotion.Update(dt)
            ButtonMotion.Update(dt)
            return
        end
        if phaseChanged then view:Update(true) end
        -- 有排队输入时在完整提交后让教程读取新状态，不能因每帧入队永久跳过教程。
        if resumed and not WorkPending() then view.tutorial:Update(dt) end
    end
    if game.phase == "reveal" then
        -- 结算汇总→停1秒→缩小→飞币入转轮；转轮停稳再考核／三选一。
        local pending = view.board:CoinPickupsBusy()
        local revealEvents = game:RevealStep(dt, pending, not pending)
        for _, event in ipairs(revealEvents) do
            if event.kind == "deduction" then view:ShowDeduction(event.value or 0) end
        end
        if game.phase ~= "reveal" then
            if simulation then simulation:ResetClock() end
            view:Update(true)
            Save()
            print(string.format("[结算] 回合 %d，收益 %.0f，余额 %.0f，状态 %s", game.round,
                game.lastRoundScore, game.score, game.phase))
        end
    end
    view:Update()
    GameAudio.Update(dt)
    RelicView.Update(view, dt)
    TextMotion.Update(dt)
    ButtonMotion.Update(dt)
end

-- 统一在渲染开始前更新全屏RTT；不能等到Widget.Render里才追赶窗口尺寸。
function HandleRenderPrepare()
    if view and view.machineSkin then
        DeveloperOverlay.Sync(view)
        view.machineSkin.litScene.post:PrepareFrame()
    end
end

---@param eventType string
---@param eventData PhysicsBeginContact2DEventData
function HandleContactBegin(eventType, eventData)
    if physics then physics:Contact(eventData, true) end
end

---@param eventType string
---@param eventData PhysicsEndContact2DEventData
function HandleContactEnd(eventType, eventData)
    if physics then physics:Contact(eventData, false) end
end

---@param eventType string
---@param eventData KeyDownEventData
function HandleKeyDown(eventType, eventData)
    if not game or not view or WorkPending() then return end
    -- Developer visibility stays available above start pages and tutorial steps.
    if DeveloperOverlay.HandleKeyDown(view,eventData) then return end
    if view.startScreen and view.startScreen:IsActive() then
        local key = eventData:GetInt("Key")
        if view.startScreen.newRunConfirm:IsOpen() then
            if key == KEY_ESCAPE then view.startScreen.newRunConfirm:Close() end
            return
        end
        if key == KEY_SPACE or key == KEY_RETURN or key == KEY_RETURN2 then
            view.startScreen:Activate()
        end
        return
    end
    local key = eventData:GetInt("Key")
    -- Required teaching steps cannot be bypassed by Space, Escape or hidden controls.
    if view.tutorial and view.tutorial:Active() then return end
    if key == KEY_ESCAPE and view.removalConfirm and view.removalConfirm:IsOpen() then
        view.removalConfirm:Close()
        return
    end
    if key == KEY_ESCAPE and view.machineSkin and view.machineSkin.presentationMenu:IsVisible() then
        view.machineSkin.presentationMenu:Hide()
        return
    end
    if key == KEY_ESCAPE and view.definitionModal:IsVisible() then
        view:CloseDefinition()
        return
    end
    -- 牌库页自身分层：详情先回网格，网格再退出牌库。
    if key == KEY_ESCAPE and view.inventoryOpen and view.modal:IsVisible() then
        view:DeckBack()
        return
    end
    if key == KEY_SPACE and game.phase == "prepare" and not view.modal:IsVisible()
        and not view.machineSkin.presentationMenu:IsVisible()
        and not view.definitionModal:IsVisible() then StartRound() end
    if key == KEY_ESCAPE then view.physicsMenu:Hide() end
    if key == KEY_ESCAPE and game.phase ~= "running" and game.phase ~= "settle" then
        view:CloseItemDetail()
        view.modal:Hide()
        view.inventoryOpen = false
        if game.phase == "draft" then
            require("Machine.LayeredSkin").SetDraftOpen(view,false)
        end
    end
end

function Stop()
    UnsubscribeFromEvent("PostUpdate")
    Save(false)
    if simulation then simulation:Dispose(); simulation = nil end
    if sensorEnabled then TouchController.DisableAccelerometer() end
    if sensorLab then sensorLab:Dispose(); sensorLab = nil end
    if physics then physics:Dispose(); physics = nil end
    ButtonMotion.Shutdown()
    GameAudio.Shutdown()
    UI.Shutdown()
    view, game = nil, nil
end
