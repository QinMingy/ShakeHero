-- 非空间物品音效。与 Audio 共用常驻 Scene，三个声源固定复用，离场时显式销毁。
local State = require("Bottle.ItemSoundState")
local Sounds = {}
---@type table<string,Sound>
local clips = {}
---@type SoundSource[]
local sources = {}
local state = State.New()
local READY = false

function Sounds.Shutdown()
    for _, source in ipairs(sources) do source:Stop(); source:Dispose() end
    clips, sources, READY = {}, {}, false
    state:Reset()
end

---@param scene Scene
function Sounds.Init(scene)
    Sounds.Shutdown()
    for action, profile in pairs(State.profiles) do
        local path = "audio/sfx/" .. profile.file
        local sound = cache:GetResource("Sound", path) --[[@as Sound?]]
        if sound and sound:GetLength() > 0 then
            sound:SetLooped(false)
            clips[action] = sound
            state:SetDuration(action, sound:GetLength())
        else
            state:SetDuration(action, nil)
            print("[音频] 物品音效未加载：" .. path)
        end
    end
    for index = 1, State.POOL_SIZE do
        local source = scene:CreateChild("ItemFeedback_" .. index):CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        sources[index] = source
    end
    READY = true
end

---@param events GameEvent[]
function Sounds.Events(events)
    if READY then state:Collect(events) end
end

---@param dt number
function Sounds.Update(dt)
    if not READY then return end
    state:Advance(dt)
    for _, play in ipairs(state:Flush()) do
        local sound, source = clips[play.action], sources[play.slot]
        if sound and source then source:Play(sound, 0, play.gain) end
    end
end

return Sounds
