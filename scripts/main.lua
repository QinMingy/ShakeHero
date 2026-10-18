-- 基于 scaffold-2d-physics：Scene/Box2D + urhox-libs/UI，固定步长驱动物理与规则。
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
local StartScreen = require("Bottle.StartScreen")

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
local accumulator = 0
local STEP = 1 / 60
local sensorEnabled = false
local sensorSampled = false
---@type number
local sensorAx = 0
---@type number
local sensorAy = 0
local sensorWait = 0
local lastSensorNotice = "off"
local SENSOR_READY_TIMEOUT = 2 -- 秒；开启异步注册，不能把首帧空读认作永久不支持。

local function ResetSensor()
    sensorSampled = false
    sensorAx, sensorAy = 0, 0
    if physics then physics.motion:ResetSensor() end
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
        SensorStatus("unsupported", notify)
        return
    end
    local ok, errorText = pcall(TouchController.EnableAccelerometer)
    sensorEnabled = ok
    sensorWait = ok and SENSOR_READY_TIMEOUT or 0
    if not ok then print("[体感] 开启失败：" .. tostring(errorText)) end
    SensorStatus(ok and "waiting" or "unavailable", notify)
end

local function Save()
    if game then Storage.Save(game) end
end

local function Refresh(reset)
    if not game or not physics or not view then return end
    -- reset 时用 revision 作洗牌种子：重抽/新回合 revision 必变，布局才会刷新。
    physics:Sync(game:BottleItems(), reset, game.revision)
    view:Update(true)
    Save()
end

local function StartRound()
    if not game or not view then return end
    view.modal:Hide()
    view.inventoryOpen = false
    view.deckDetailUid = 0
    view:DisposeDeckSim()
    if view.physicsButton then view.physicsButton:Show() end
    if game:Start() then
        -- 篮筐沿用准备阶段位置；开始按钮不重新随机设施。
        accumulator = 0
        ResetSensor()
        -- 自动启用失败或设备断开后，开始按钮再试一次；仍保留触摸操作。
        if lastSensorNotice ~= "available" then Sensor(false) end
        view.board:Effects(game.startEvents)
        game.startEvents = {}
        Save()
        view:Update(true)
        print(string.format("[回合] 开始 %d，入瓶 %d，余额 %.0f，目标 %.0f", game.round,
            #game:BottleItems(), game.score, game.target))
    end
end

local function NewRun()
    if not view or not physics then return end
    game = Game.New(math.floor(os.time() % 2147483646) + 1)
    accumulator = 0
    physics:Clear()
    physics:Sync(game:BottleItems(), true, game.revision)
    view:Rebind(game)
    Save()
    print("[对局] 新局：苹果、香蕉、小球、橘子各一件")
end

local function Import(text)
    local snapshot, errorText, physicsMode, atmosphereMode = Storage.Import(text)
    if not snapshot then return false, errorText end
    local ok, restored = pcall(Game.Restore, snapshot)
    if not ok then
        print("[存档] 导入校验失败：" .. tostring(restored))
        return false, "存档内容不完整或版本不兼容"
    end
    if not view or not physics then return false, "游戏尚未就绪" end
    game = restored
    Storage.SetPhysicsMode(physicsMode or 2)
    Storage.SetAtmosphere(atmosphereMode or "auto")
    physics:SetMode(Storage.physicsMode)
    sensorSampled = false
    accumulator = 0
    physics:Clear()
    -- 存档含 revision：同一份存档恢复出同一布局，保持可复现。
    physics:Sync(game:BottleItems(), true, game.revision)
    view:Rebind(game)
    Save()
    return true, nil
end

local function SetPhysicsMode(mode)
    if not physics or not view or not physics:SetMode(mode) then return end
    Storage.SetPhysicsMode(mode)
    sensorSampled = false
    view.board:ResetShake()
    view:UpdatePhysicsMode()
    view:Update(true)
    Save()
end

function Start()
    graphics.windowTitle = "摇摇牌库"
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
    print("[规则自检] 全部通过，共 " .. result .. " 项")

    local snapshot = Storage.Load()
    if snapshot then
        local ok, restored = pcall(Game.Restore, snapshot)
        if ok then game = restored else print("[存档] 无法恢复，开启新局：" .. tostring(restored)) end
    end
    if not game then game = Game.New(math.floor(os.time() % 2147483646) + 1) end
    physics = Physics.New()
    physics:SetMode(Storage.physicsMode)
    physics:Sync(game:BottleItems(), true, game.revision)
    view = View.New(game, physics, {
        start = StartRound,
        shake = function(dx, dy)
            if game and physics and game.phase == "running" then physics:Shake(dx, dy) end
        end,
        reroll = function()
            if game and game:Reroll() then Refresh(true); print("[抽取] 本回合重抽已使用") end
        end,
        refresh = function()
            if game and game:DraftRefresh() then
                view:Update(true); Save(); print("[三选一] 刷新已使用")
            end
        end,
        choose = function(index)
            if game and game:Choose(index) then Refresh(true); print("[三选一] 选择完成，当前状态：" .. game.phase .. (game.relicDraft and "（遗物）" or "")) end
        end,
        skip = function()
            if game and game:Skip() then Refresh(true); print("[三选一] 跳过完成，当前状态：" .. game.phase .. (game.relicDraft and "（遗物）" or "")) end
        end,
        newrun = NewRun, import = Import,
        juicer = function()
            if not game then return false, "游戏尚未就绪" end
            local ok, message = RelicEffects.UseJuicer(game)
            if ok then
                if view then view:Update(true) end
                Save()
                print("[遗物] " .. tostring(message))
            end
            return ok, message
        end,
        sensor = function() Sensor(true) end, physics = SetPhysicsMode,
        atmosphere = function(mode)
            if not Storage.SetAtmosphere(mode) then return end
            if view then view:Update(true) end
            Save()
        end,
        gmadd = function(id)
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
    view.startScreen = StartScreen.New(view)
    -- Android/iOS 原生端默认接通体感；Web/桌面仅显示触摸回退提示。
    Sensor(false)
    TextMotion.Update(0)
    ButtonMotion.Update(0)
    -- 验收助手在 Start 之后加载，所以在调用时判断验证运行时。
    _G["BottleValidationGet"] = function()
        if not _G["V"] then return nil end
        return {
            GetGame = function() return game end,
            GetView = function() return view end,
            GetPhysics = function() return physics end,
            GetStartScreen = function() return view and view.startScreen or nil end,
            StartRound = StartRound, NewRun = NewRun,
        }
    end
    SubscribeToEvent("Update", "HandleUpdate")
    SubscribeToEvent("PostUpdate", "HandleRenderPrepare")
    SubscribeToEvent("PhysicsBeginContact2D", "HandleContactBegin")
    SubscribeToEvent("PhysicsEndContact2D", "HandleContactEnd")
    SubscribeToEvent("KeyDown", "HandleKeyDown")
    Save()
    print("[启动] 摇摇牌库 V0.4，单机竖屏2D，71件物品与24件遗物已实装")
end

---@param eventType string
---@param eventData UpdateEventData
function HandleUpdate(eventType, eventData)
    if not game or not physics or not view then return end
    local dt = math.max(0, eventData:GetFloat("TimeStep"))
    if view.startScreen and view.startScreen:IsActive() then
        -- 开始页期间不推进回合、体感或物理；只保留机台动画、文字浮动与按钮反馈。
        view:Update()
        view.startScreen:Update(dt)
        GameAudio.Update(dt)
        TextMotion.Update(dt)
        ButtonMotion.Update(dt)
        return
    end
    if sensorEnabled then
        sensorWait = math.max(0, sensorWait - dt)
        local ok, available = pcall(TouchController.IsAccelerometerAvailable)
        if ok and available then
            local readOk, ax, ay = pcall(TouchController.ReadAccelerometer)
            local valid = readOk and type(ax) == "number" and type(ay) == "number"
                and ax == ax and ay == ay and math.abs(ax) < math.huge and math.abs(ay) < math.huge
            if valid then
                if game.phase == "running" and physics.mode == 2 then
                    physics:Sensor(-ax, ay, dt)
                elseif sensorSampled and game.phase == "running" then
                    -- 物理一的体感差分与冲量增益原样保留。
                    local dx, dy = ax - sensorAx, ay - sensorAy
                    if dx * dx + dy * dy > .0009 then
                        physics:Shake(math.max(-.6, math.min(.6, -dx * 2.6)),
                            math.max(-.6, math.min(.6, dy * 2.6)))
                    end
                end
                if not sensorSampled then
                    print(string.format("[体感] 首样本 x=%.3f y=%.3f", ax, ay))
                end
                sensorAx, sensorAy = ax --[[@as number]], ay --[[@as number]]
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
    if game.phase == "running" or game.phase == "settle" then
        -- settle 阶段：禁止摇晃（体感/触摸已在入口按 phase=="running" 拦截），
        -- 物体自然下落2秒后全体一次性结算（docs/游戏流程.txt）。
        local settling = game.phase == "settle"
        local stepPhase = game.phase
        accumulator = accumulator + dt
        while accumulator + .0000001 >= STEP and game.phase == stepPhase do
            local cap = settling and (Game.SETTLE_DELAY - game.settleElapsed) or (game:Duration() - game.elapsed)
            local step = math.min(STEP, cap)
            if step <= .0000001 then break end
            physics:Step(step)
            -- 本步真实新接触交给Audio同帧择强；不按全局固定间隔放行声音。
            for _, impact in ipairs(physics:TakeImpacts()) do
                GameAudio.Impact(impact.speed, impact.pair, impact.key)
            end
            local events = settling
                and game:SettleStep(step, physics:Contacts() --[[@as BottleContacts]])
                or game:Step(step, physics:Contacts() --[[@as BottleContacts]])
            physics:RememberEvents(events)
            view.board:Effects(events)
            physics:Sync(game:BottleItems())
            for _, event in ipairs(events) do
                if event.kind == "transform" then
                    print("[转化] uid" .. event.uid .. " → " .. tostring(event.id))
                end
                if event.kind == "buff" then
                    print("[价值] " .. tostring(event.id) .. " 临时价值 " .. tostring(event.value))
                end
            end
            accumulator = math.max(0, accumulator - step)
            settling = game.phase == "settle"
        end
        if game.phase ~= "running" and game.phase ~= "settle" then
            accumulator = 0
            view:Update(true)
        end
    end
    if game.phase == "reveal" then
        -- 结算展示：分数弹出后停留2秒让玩家看清，不做物理步进；结束再存档并打印结算。
        game:RevealStep(dt)
        if game.phase ~= "reveal" then
            accumulator = 0
            view:Update(true)
            Save()
            print(string.format("[结算] 回合 %d，收益 %.0f，余额 %.0f，状态 %s", game.round,
                game.lastRoundScore, game.score, game.phase))
        end
    end
    view:Update()
    GameAudio.Update(dt)
    TextMotion.Update(dt)
    ButtonMotion.Update(dt)
end

-- 统一在渲染开始前更新全屏RTT；不能等到Widget.Render里才追赶窗口尺寸。
function HandleRenderPrepare()
    if view and view.machineSkin then view.machineSkin.litScene.post:PrepareFrame() end
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
    if not game or not view then return end
    if view.startScreen and view.startScreen:IsActive() then
        local key = eventData:GetInt("Key")
        if key == KEY_SPACE or key == KEY_RETURN or key == KEY_RETURN2 then
            view.startScreen:Close()
        end
        return
    end
    local key = eventData:GetInt("Key")
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
    Save()
    if sensorEnabled then TouchController.DisableAccelerometer() end
    if physics then physics:Dispose(); physics = nil end
    ButtonMotion.Shutdown()
    GameAudio.Shutdown()
    UI.Shutdown()
    view, game = nil, nil
end
