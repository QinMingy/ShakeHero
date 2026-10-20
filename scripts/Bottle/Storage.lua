-- 原生平台使用项目隔离文件；网页预览可用存档码手动跨刷新恢复。
local Game = require("Bottle.Game")
local Atmosphere=require("Machine.Atmosphere")
local TutorialState = require("Bottle.TutorialState")
local SensorTuning = require("Bottle.SensorTuning")
---@class BottleStorage
---@field status string
---@field sequence integer
---@field slot integer 最近一次验证成功的槽；失败不能改变它
---@field readBlocked boolean 旧档读取发生I/O异常时禁止覆盖
---@field atmosphereMode string
---@field tutorial BottleTutorialState
---@field runStarted boolean 玩家已经进入本局；启动页预先保存不算开始
---@field sensorGain number
local Storage = { status = "未保存", sequence = 0, slot = 0, readBlocked = false, atmosphereMode = "auto",
    sensorGain = SensorTuning.DEFAULT,
    tutorial = TutorialState.New(false), runStarted = false }

---@return BottleTutorialState
function Storage.GetTutorial()
    return TutorialState.FromSaved(Storage.tutorial, false)
end

--- 普通同步保留完成/旧玩家标记；显式新游戏通过 RestartTutorial 重播。
--- 返回独立副本，避免外部引用改写存档状态。
---@param value any
---@return BottleTutorialState
function Storage.SetTutorial(value)
    local state = TutorialState.FromSaved(value, false)
    local current = Storage.GetTutorial()
    if current.status == "complete" and state.status ~= "complete" then return current end
    if current.status == "legacy" and state.status ~= "legacy" then return current end
    state.examSeen = state.examSeen or current.examSeen
    state.relicSeen = state.relicSeen or current.relicSeen
    Storage.tutorial = state
    return Storage.GetTutorial()
end

--- 仅显式开始新游戏时重播引导；继续、读档和导入仍使用受保护的 SetTutorial。
---@return BottleTutorialState
function Storage.RestartTutorial()
    Storage.tutorial = TutorialState.New(false)
    return Storage.GetTutorial()
end

--- 仅在 Game.Restore 成功后调用，失败的导入不改变本地玩家标记。
---@return BottleTutorialState
function Storage.MarkImported()
    return Storage.SetTutorial(TutorialState.MarkImported(Storage.tutorial))
end

local function AtmosphereMode(value)
    local mode=type(value)=="table" and value.atmosphereMode or nil
    return Atmosphere.Valid(mode) and mode or "auto"
end

function Storage.SetAtmosphere(mode)
    if not Atmosphere.Valid(mode) then return false end
    Storage.atmosphereMode=mode
    return true
end

---@param value number
---@return boolean
function Storage.SetSensorGain(value)
    local gain = SensorTuning.Normalize(value)
    if not gain then return false end
    Storage.sensorGain = gain
    return true
end

---@param game BottleGame
---@return string
function Storage.Export(game)
    return cjson.encode({ format = "bottle-lab-v1", game = game:Snapshot(),
        settings = {atmosphereMode=Storage.atmosphereMode} })
end

---@param text string
---@return table?
---@return string?
---@return string? atmosphereMode 仅在对局恢复成功后提交，失败导入不改变设置。
function Storage.Import(text)
    if #text > 2000000 then return nil, "存档码过长", nil end
    local ok, value = pcall(cjson.decode, text)
    if not ok or type(value) ~= "table" or value.format ~= "bottle-lab-v1"
        or type(value.game) ~= "table" then
        return nil, "存档码格式不正确", nil
    end
    return value.game, nil, AtmosphereMode(value.settings)
end

local MAX_SEQUENCE = 2147483646

---@param slot integer
---@return string
local function SlotName(slot)
    return "bottle-save-" .. slot .. ".json"
end

-- File.WriteString的原生格式为UTF-8正文加一个零字节；保留旧档格式。
---@param name string
---@param tolerateCorrupt boolean?
---@return string
local function ReadText(name, tolerateCorrupt)
    local file = File(name, FILE_READ)
    local ok, result = pcall(function()
        assert(file:IsOpen(), "无法打开文件")
        local size = file:GetSize()
        if size == 0 and tolerateCorrupt then return "" end
        assert(size > 0, "存档文件大小无效")
        local text = file:ReadString()
        if size ~= #text + 1 and tolerateCorrupt then return "" end
        assert(size == #text + 1, "存档文件不完整")
        return text
    end)
    local closed, closeError = pcall(file.Close, file)
    local disposed, disposeError = pcall(file.Dispose, file)
    assert(closed, tostring(closeError))
    assert(disposed, tostring(disposeError))
    assert(ok, tostring(result))
    return result
end

---@return table?
function Storage.Load()
    local bestSequence = -1
    local bestSlot = 0
    local bestAtmosphere = "auto"
    local bestSensorGain = SensorTuning.DEFAULT
    local bestTutorial = TutorialState.New(false)
    local bestStarted = false
    local best = nil ---@type table?
    local readFailed = false
    for i = 1, 2 do
        local readable, text = pcall(function()
            local name = SlotName(i)
            if not fileSystem:FileExists(name) then return nil end
            return ReadText(name, true)
        end)
        local ok, value = false, nil
        if readable and text then
            ok, value = pcall(cjson.decode, text)
        elseif not readable then
            readFailed = true
            print("[存档] 读取槽 " .. i .. " 失败：" .. tostring(text))
        end
        if ok and type(value) == "table" and value.format == "bottle-lab-v1"
            and type(value.sequence) == "number" and type(value.game) == "table"
            and value.sequence >= 0 and value.sequence <= MAX_SEQUENCE
            and value.sequence == math.floor(value.sequence)
            and value.sequence > bestSequence then
            -- 每个候选槽先验证，较新槽损坏时仍可恢复较旧槽。
            local valid = pcall(Game.Restore, value.game)
            if valid then
                best = value.game
                bestSequence = math.floor(value.sequence)
                bestSlot = i
                bestAtmosphere = AtmosphereMode(value.settings)
                local savedSettings = type(value.settings) == "table" and value.settings or {}
                bestSensorGain = savedSettings.sensorGainRevision == SensorTuning.SAVE_REVISION
                    and SensorTuning.Normalize(savedSettings.sensorGain) or SensorTuning.DEFAULT
                bestTutorial = TutorialState.Reconcile(TutorialState.FromSaved(value.tutorial, true), best)
                -- 旧档缺少标记时保守保留继续入口，避免丢掉第一回合的真实进度。
                bestStarted = value.runStarted ~= false
            else
                print("[存档] 忽略损坏的存档槽 " .. i)
            end
        end
    end
    if readFailed then
        -- 不能把临时不可读当成“没有旧档”，也不能覆盖可能更新的不可读槽。
        Storage.readBlocked = true
        Storage.status = "本地存档读取失败，已禁止覆盖"
        return nil
    end
    Storage.readBlocked = false
    Storage.atmosphereMode = bestAtmosphere
    Storage.sensorGain = bestSensorGain
    Storage.tutorial = bestTutorial
    Storage.runStarted = bestStarted
    Storage.slot = bestSlot
    Storage.sequence = best and bestSequence or 0
    Storage.status = best and "已读取存档" or "未保存"
    return best
end

---@param game BottleGame
---@return boolean
function Storage.Save(game)
    if Storage.readBlocked then
        Storage.status = "本地存档读取失败，已禁止覆盖"
        print("[存档] 未写入：旧档读取失败，请重新进入游戏重试，避免覆盖旧进度")
        return false
    end
    -- 不直接截断正式槽：写临时文件、关闭后逐字核验，再同目录替换另一槽。
    -- 任一阶段失败均保留最后有效槽与序号；临时文件不参与Load。
    local sequence = Storage.sequence + 1
    local slot = Storage.slot > 0 and (3 - Storage.slot) or ((sequence % 2) + 1)
    local name = SlotName(slot)
    local pending = name .. ".tmp"
    local stage = "编码"
    ---@type File?
    local file = nil
    local ok, message = pcall(function()
        assert(sequence >= 1 and sequence <= MAX_SEQUENCE and sequence == math.floor(sequence),
            "存档序号超出安全范围")
        local snapshot = game:Snapshot()
        local text = cjson.encode({
            format = "bottle-lab-v1", sequence = sequence, game = snapshot,
            runStarted = Storage.runStarted,
            settings = {atmosphereMode = Storage.atmosphereMode,
                sensorGain = Storage.sensorGain, sensorGainRevision = SensorTuning.SAVE_REVISION},
            tutorial = TutorialState.ForSnapshot(Storage.tutorial, snapshot),
        })
        -- 先在内存完整序列化，再单次写出；不对文件逐字符调用WriteString。
        local buffer = VectorBuffer()
        assert(buffer:WriteString(text), "存档缓冲编码失败")
        stage = "打开临时文件"
        file = File(pending, FILE_WRITE)
        assert(file:IsOpen(), "本地文件不可写")
        stage = "写入"
        assert(file:Write(buffer) == buffer:GetSize(), "本地文件写入不完整")
        stage = "刷新"
        file:Flush()
        stage = "关闭"
        file:Close()
        local closing = file
        file = nil
        closing:Dispose()
        stage = "核验"
        assert(ReadText(pending) == text, "存档写后核验不一致")
        stage = "提交"
        assert(fileSystem:Rename(pending, name), "无法提交临时存档")
    end)
    if file then
        local closed, closeError = pcall(file.Close, file)
        local disposed, disposeError = pcall(file.Dispose, file)
        if not closed then print("[存档] 关闭文件失败：" .. tostring(closeError)) end
        if not disposed then print("[存档] 释放文件失败：" .. tostring(disposeError)) end
    end
    if not ok then
        Storage.status = "本地存档保存失败"
        print(string.format("[存档] %s失败，槽%d，序号%d；保留上次有效存档：%s",
            stage, slot, sequence, tostring(message)))
        return false
    end
    Storage.sequence, Storage.slot = sequence, slot
    Storage.status = "已保存"
    print(string.format("[存档] 已保存回合 %d，阶段 %s，槽%d，序号%d", game.round, game.phase, slot, sequence))
    return true
end

return Storage
