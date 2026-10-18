-- 全局非空间音频独立于反复重建的页面；固定声源池，不占用玩法随机序列。
local UI = require("urhox-libs/UI")
local TextMotion = require("Bottle.TextMotion")
---@type any
local Music = {current = "", tracks = {}, clicks = {}, pops = {}, impacts = {}, nextClick = 1,
    nextPop = 1, nextImpact = 1, clickCount = 0, popCount = 0, popPitchStep = 0,
    lastImpactTime = -1, time = 0, reelSpinning = false, reelLoopSource = nil,
    reelStartSource = nil, reelStopSource = nil}
---@type Scene?
local audioScene = nil
---@type Sound?
local clickSound = nil
---@type Sound?
local popSound = nil
---@type Sound?
local impactSound = nil
---@type Sound?
local reelLoopSound = nil
---@type Sound?
local reelStartSound = nil
---@type Sound?
local reelStopSound = nil
local FADE_SECONDS = 1.2
local MUSIC_GAIN = .36
local CLICK_GAIN = .55
local POP_GAIN = .7
-- 碰撞音：按碰撞强度过滤 + 全局节流 + 固定声源池 + 音量随强度。
local IMPACT_GAIN = .5
local IMPACT_MIN_SPEED = .7   -- 米/秒，低于此相对速度的轻碰静音
local IMPACT_MAX_SPEED = 6.0  -- 音量归一上限，超过按满音量
local IMPACT_THROTTLE = .05   -- 秒，两次碰撞音之间的最短间隔
local IMPACT_POOL = 4         -- 固定声源数，超出抢占
-- 转轮音：循环棘轮较低，开始/停止稍突出。
local REEL_LOOP_GAIN = .38
local REEL_START_GAIN = .7
local REEL_STOP_GAIN = .75
-- 出现音调阶梯（用户要求：音调从低到高，超出上限后从最低开始）：
-- 每批出现都从低于原调3个半音起，每次升高1.5个半音，共8档
-- （约0.84 → 1.55倍速），用完回到本批最低档；批次开始时由调用方重置。
local POP_PITCH_STEPS = 8
local POP_PITCH_STEP = 1.5    -- 每档提升的半音数
local POP_PITCH_BASE = -3     -- 起始相对原调的半音偏移（负值=更低）

-- 第 step 档（0-based）的播放相对倍率；超过档数按循环取最低档。
---@param step integer
---@return number
local function PopPitch(step)
    local semitones = POP_PITCH_BASE + (step % POP_PITCH_STEPS) * POP_PITCH_STEP
    return 2 ^ (semitones / 12)
end

-- 音频资源集中声明：替换/测试音效时只改这里的文件名即可。
-- 新文件放到 assets/audio/ 下，并让引擎生成对应 .meta（勿手写 uuid）。
local AUDIO_DIR = "audio/"
local BGM_RUNNING_FILE = "SynthStuff.wav" -- 摇晃阶段紧张 BGM《机械蓄能》
local BGM_CALM_FILE = "onehorsetown.mp3"   -- 准备/结算/三选一舒缓 BGM《齿轮间歇》
local CLICK_BOLT_FILE = "sfx/sd_button_click.wav" -- 按钮点击音（Slots and Daggers 木按钮，已裁剪）
-- 转轮音效（同上来源）：循环棘轮纹理 + 开始/停止机械声。
local REEL_LOOP_FILE = "sfx/sd_reel_loop.wav"
local REEL_START_FILE = "sfx/sd_reel_start.wav"
local REEL_STOP_FILE = "sfx/sd_reel_stop.wav"
-- 【占位音效】物品入瓶/出现弹跳音：暂用 assets/audio/sfx/balatro_chip.wav（筹码短音）代替，
-- 与按钮点击音区分。正式出现音效确定后替换此文件并删除本注释，调用点（Music.Pop）不变。
-- 加载失败时回退到按钮点击音，保证物品出现时仍有声音反馈。
local POP_CHIP_FILE = "sfx/balatro_chip.wav"
-- 【占位音效】瓶内物体碰撞音：暂用 assets/audio/sfx/balatro_coin.wav（筹码短音）代替，
-- 与出现音区分。正式碰撞音确定后替换此文件并删除本注释，调用点（Music.Impact）不变。
local IMPACT_FILE = "sfx/balatro_coin.wav"

local function Load(path, looped)
    local sound = cache:GetResource("Sound", path) --[[@as Sound?]]
    if not sound or sound:GetLength() <= 0 then
        print("[音频] 无法加载：" .. path)
        return nil
    end
    sound:SetLooped(looped)
    print(string.format("[音频] 已加载 %s，%.2f秒", path, sound:GetLength()))
    return sound
end

function Music.Init()
    Music.Shutdown()
    audioScene = Scene()
    local paths = {
        running = AUDIO_DIR .. BGM_RUNNING_FILE,
        calm = AUDIO_DIR .. BGM_CALM_FILE,
    }
    for key, path in pairs(paths) do
        local sound = Load(path, true)
        if sound then
            local source = audioScene:CreateChild("BGM_" .. key):CreateComponent("SoundSource")
            source:SetSoundType(SOUND_MUSIC)
            Music.tracks[key] = {sound = sound, source = source, gain = 0, from = 0, target = 0, elapsed = 0}
        end
    end
    clickSound = Load(AUDIO_DIR .. CLICK_BOLT_FILE, false)
    for i = 1, 4 do
        local source = audioScene:CreateChild("ButtonClick_" .. i):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        Music.clicks[i] = source
    end
    -- 出现音效使用独立固定池，与按钮点击互不抢占。
    popSound = Load(AUDIO_DIR .. POP_CHIP_FILE, false)
    if not popSound then
        print("[音频] 出现占位音效加载失败，回退到按钮点击音（待正式音效替换）")
        popSound = clickSound
    end
    for i = 1, 3 do
        local source = audioScene:CreateChild("ItemPop_" .. i):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        Music.pops[i] = source
    end
    -- 碰撞音独立固定池，与出现音/按钮音互不抢占。
    impactSound = Load(AUDIO_DIR .. IMPACT_FILE, false)
    if not impactSound then
        print("[音频] 碰撞占位音效加载失败，回退到出现音（待正式音效替换）")
        impactSound = popSound
    end
    for i = 1, IMPACT_POOL do
        local source = audioScene:CreateChild("Impact_" .. i):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        Music.impacts[i] = source
    end
    -- 转轮音：独立循环源 + 开始/停止一次性源，不与按钮/出现音抢占。
    reelLoopSound = Load(AUDIO_DIR .. REEL_LOOP_FILE, true)
    reelStartSound = Load(AUDIO_DIR .. REEL_START_FILE, false)
    reelStopSound = Load(AUDIO_DIR .. REEL_STOP_FILE, false)
    if not reelStartSound then reelStartSound = clickSound end
    if not reelStopSound then reelStopSound = clickSound end
    Music.reelLoopSource = audioScene:CreateChild("ReelLoop"):CreateComponent("SoundSource")
    Music.reelLoopSource:SetSoundType(SOUND_EFFECT)
    Music.reelStartSource = audioScene:CreateChild("ReelStart"):CreateComponent("SoundSource")
    Music.reelStartSource:SetSoundType(SOUND_EFFECT)
    Music.reelStopSource = audioScene:CreateChild("ReelStop"):CreateComponent("SoundSource")
    Music.reelStopSource:SetSoundType(SOUND_EFFECT)
    print("[音频] 双状态BGM与机械按钮音已启用")
end

function Music.SetPhase(phase)
    if not audioScene then return end
    local wanted = phase == "running" and "running" or "calm"
    if Music.current == wanted then return end
    Music.current = wanted
    for key, track in pairs(Music.tracks) do
        track.from, track.elapsed = track.gain, 0
        track.target = key == wanted and MUSIC_GAIN or 0
        if key == wanted and not track.source:IsPlaying() then
            -- 0 指素材原采样率，不是变调倍数；复用声源时每次明确恢复原速。
            track.source:Play(track.sound, 0, track.gain)
        end
    end
    print("[音频] BGM切换：" .. (wanted == "running" and "紧张机械" or "舒缓机械"))
end

function Music.Update(dt)
    if not audioScene then return end
    Music.time = Music.time + math.max(0, dt)
    for _, track in pairs(Music.tracks) do
        track.elapsed = math.min(FADE_SECONDS, track.elapsed + math.max(0, dt))
        local progress = track.elapsed / FADE_SECONDS
        -- smoothstep：淡入淡出两端更缓，切换时不会有明显的音量台阶。
        local t = progress * progress * (3 - 2 * progress)
        track.gain = track.from + (track.target - track.from) * t
        track.source:SetGain(track.gain)
        if progress == 1 and track.target == 0 and track.source:IsPlaying() then track.source:Stop() end
    end
end

function Music.Click()
    if not audioScene or not clickSound then return end
    local source = Music.clicks[Music.nextClick] --[[@as SoundSource?]]
    if not source then return end
    source:Play(clickSound, 0, CLICK_GAIN)
    Music.nextClick = Music.nextClick % #Music.clicks + 1
    Music.clickCount = Music.clickCount + 1
end

-- 物品入瓶/出现的弹跳音（占位素材，见 POP_CHIP_FILE 声明）。每件出现播放一次，
-- 由3声源固定池轮转；同帧多件出现时后续播放会自然挤占前一声源。
-- 音调按批次内出现顺序逐档升高；批次由调用方在开始时 ResetPopPitch 重置到最低档。
function Music.Pop()
    if not audioScene or not popSound then return end
    local source = Music.pops[Music.nextPop] --[[@as SoundSource?]]
    if not source then return end
    -- 接口的 frequency 是绝对 Hz 而非倍率，须乘素材采样率（engine-docs/api/audio.md）。
    source:Play(popSound, popSound:GetFrequency() * PopPitch(Music.popPitchStep), POP_GAIN)
    Music.nextPop = Music.nextPop % #Music.pops + 1
    Music.popPitchStep = (Music.popPitchStep + 1) % POP_PITCH_STEPS
    Music.popCount = Music.popCount + 1
end

-- 新一批物品同时/错峰出现前调用：音调回到最低档，整批由低到高。
function Music.ResetPopPitch()
    Music.popPitchStep = 0
end

-- 瓶内碰撞音：由 Physics 每物理步上报一次 Begin 接触的相对速度。
-- 低于阈值的轻碰静音；全局节流吞掉密集接触；音量随速度归一，强碰更响。
-- 固定声源池轮转，超出抢占最早的声源，避免几十件物体同时响成噪音。
---@param speed number 相对速度（米/秒）
---@param pair boolean 是否物品互撞；false 为撞瓶壁
function Music.Impact(speed, pair)
    if not audioScene or not impactSound then return end
    if speed ~= speed or speed < IMPACT_MIN_SPEED then return end
    if Music.time - Music.lastImpactTime < IMPACT_THROTTLE then return end
    Music.lastImpactTime = Music.time
    local source = Music.impacts[Music.nextImpact] --[[@as SoundSource?]]
    if not source then return end
    local t = math.min(1, speed / IMPACT_MAX_SPEED)
    local strength = 0.35 + 0.65 * t
    if not pair then strength = strength * 1.25 end -- 撞瓶壁比物品互撞稍响，强化摇晃反馈
    local gain = IMPACT_GAIN * math.min(1.25, strength)
    source:Play(impactSound, 0, gain)
    Music.nextImpact = Music.nextImpact % #Music.impacts + 1
end

-- 转轮动画状态：开始旋转时播放机械启动音并起循环棘轮，停稳时停止循环并播放收尾。
-- 由 UI 每帧调用；重复状态不重复触发。
---@param spinning boolean
function Music.SetReels(spinning)
    if not audioScene then return end
    spinning = spinning == true
    if spinning == Music.reelSpinning then return end
    Music.reelSpinning = spinning
    if spinning then
        if Music.reelStartSource and reelStartSound then
            Music.reelStartSource:Play(reelStartSound, 0, REEL_START_GAIN)
        end
        if Music.reelLoopSource and reelLoopSound and not Music.reelLoopSource:IsPlaying() then
            Music.reelLoopSource:Play(reelLoopSound, 0, REEL_LOOP_GAIN)
        end
    else
        if Music.reelLoopSource and Music.reelLoopSource:IsPlaying() then
            Music.reelLoopSource:Stop()
        end
        -- 停止音暂时关闭（用户要求先试循环/开始音）；恢复时取消下一段注释即可。
        -- if Music.reelStopSource and reelStopSound then
        --     Music.reelStopSource:Play(reelStopSound, 0, REEL_STOP_GAIN)
        -- end
    end
end

-- 在项目按钮创建时接入，早于PageMotion包装：旧指针／退场门控先通过才会发声。
-- 不监听全局按下，因此拖瓶、滚动、遮罩与说明引用不会被误认为按钮点击。
function Music.Button(props)
    local callback = props.onClick
    if callback then
        props.onClick = function(button, event)
            if not button.props.disabled and TextMotion.IsDisplayed(button)
                and not (button.hoverBlocked and button.hoverBlocked()) then
                Music.Click()
            end
            return callback(button, event)
        end
    end
    return UI.Button(props)
end

function Music.Shutdown()
    -- Lua仍持有组件时，仅Dispose父Scene不会立即注销声源；逐个显式释放。
    for _, track in pairs(Music.tracks) do track.source:Stop(); track.source:Dispose() end
    for _, source in ipairs(Music.clicks) do source:Stop(); source:Dispose() end
    for _, source in ipairs(Music.pops) do source:Stop(); source:Dispose() end
    for _, source in ipairs(Music.impacts) do source:Stop(); source:Dispose() end
    for _, source in ipairs({Music.reelLoopSource, Music.reelStartSource, Music.reelStopSource}) do
        if source then source:Stop(); source:Dispose() end
    end
    if audioScene then audioScene:Dispose(); audioScene = nil end
    Music.current, Music.tracks, Music.clicks, Music.pops, Music.impacts = "", {}, {}, {}, {}
    Music.nextClick, Music.nextPop, Music.clickCount, Music.popCount = 1, 1, 0, 0
    Music.nextImpact, Music.lastImpactTime = 1, -1
    Music.reelSpinning = false
    Music.reelLoopSource, Music.reelStartSource, Music.reelStopSource = nil, nil, nil
    Music.popPitchStep = 0
    clickSound = nil
    popSound = nil
    impactSound = nil
    reelLoopSound, reelStartSound, reelStopSound = nil, nil, nil
end

return Music
