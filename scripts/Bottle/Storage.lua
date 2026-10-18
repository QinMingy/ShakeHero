-- 原生平台使用项目隔离文件；网页预览可用存档码手动跨刷新恢复。
local Game = require("Bottle.Game")
local Atmosphere=require("Machine.Atmosphere")
local TutorialState = require("Bottle.TutorialState")
---@class BottleStorage
---@field status string
---@field sequence number
---@field physicsMode number
---@field atmosphereMode string
---@field tutorial BottleTutorialState
---@field runStarted boolean 玩家已经进入本局；启动页预先保存不算开始
local Storage = { status = "未保存", sequence = 0, physicsMode = 2, atmosphereMode = "auto",
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

-- 物理模式是玩家设置，不进入 Game 的回合回滚快照；旧存档默认优化版。
---@param value any
---@return integer
local function PhysicsMode(value)
    if type(value) == "table" and value.physicsMode == 1 then return 1 end
    return 2
end

local function AtmosphereMode(value)
    local mode=type(value)=="table" and value.atmosphereMode or nil
    return Atmosphere.Valid(mode) and mode or "auto"
end

---@param mode number
---@return boolean
function Storage.SetPhysicsMode(mode)
    if mode ~= 1 and mode ~= 2 then return false end
    Storage.physicsMode = mode
    return true
end

function Storage.SetAtmosphere(mode)
    if not Atmosphere.Valid(mode) then return false end
    Storage.atmosphereMode=mode
    return true
end

---@param game BottleGame
---@return string
function Storage.Export(game)
    return cjson.encode({ format = "bottle-lab-v1", game = game:Snapshot(),
        settings = {physicsMode = Storage.physicsMode,atmosphereMode=Storage.atmosphereMode} })
end

---@param text string
---@return table?
---@return string?
---@return number? physicsMode 仅在对局恢复成功后提交，失败导入不改变设置。
---@return string? atmosphereMode
function Storage.Import(text)
    if #text > 2000000 then return nil, "存档码过长" end
    local ok, value = pcall(cjson.decode, text)
    if not ok or type(value) ~= "table" or value.format ~= "bottle-lab-v1"
        or type(value.game) ~= "table" then
        return nil, "存档码格式不正确"
    end
    return value.game, nil, PhysicsMode(value.settings), AtmosphereMode(value.settings)
end

---@return table?
function Storage.Load()
    local bestSequence = -1
    local bestMode = 2
    local bestAtmosphere = "auto"
    local bestTutorial = TutorialState.New(false)
    local bestStarted = false
    local best = nil ---@type table?
    for i = 1, 2 do
        local name = "bottle-save-" .. i .. ".json"
        if fileSystem:FileExists(name) then
            local file = File(name, FILE_READ)
            if file:IsOpen() then
                local text = file:ReadString()
                file:Dispose()
                local ok, value = pcall(cjson.decode, text)
                if ok and type(value) == "table" and value.format == "bottle-lab-v1"
                    and type(value.sequence) == "number" and type(value.game) == "table"
                    and value.sequence >= 0 and value.sequence <= 2147483646
                    and value.sequence == math.floor(value.sequence)
                    and value.sequence > bestSequence then
                    -- 每个候选槽先验证，较新槽损坏时仍可恢复较旧槽。
                    local valid = pcall(Game.Restore, value.game)
                    if valid then
                        best = value.game
                        bestSequence = math.floor(value.sequence)
                        bestMode = PhysicsMode(value.settings)
                        bestAtmosphere = AtmosphereMode(value.settings)
                        bestTutorial = TutorialState.Reconcile(TutorialState.FromSaved(value.tutorial, true), best)
                        -- 旧档缺少标记时保守保留继续入口，避免丢掉第一回合的真实进度。
                        bestStarted = value.runStarted ~= false
                    else
                        print("[存档] 忽略损坏的存档槽 " .. i)
                    end
                end
            else
                file:Dispose()
            end
        end
    end
    Storage.physicsMode = bestMode
    Storage.atmosphereMode = bestAtmosphere
    Storage.tutorial = bestTutorial
    Storage.runStarted = bestStarted
    if best then
        Storage.sequence = bestSequence
        Storage.status = "已读取存档"
    end
    return best
end

---@param game BottleGame
---@return boolean
function Storage.Save(game)
    Storage.sequence = Storage.sequence + 1
    local snapshot = game:Snapshot()
    local ok, text = pcall(cjson.encode, {
        format = "bottle-lab-v1", sequence = Storage.sequence, game = snapshot,
        runStarted = Storage.runStarted,
        settings = {physicsMode = Storage.physicsMode,atmosphereMode=Storage.atmosphereMode},
        tutorial = TutorialState.ForSnapshot(Storage.tutorial, snapshot),
    })
    if not ok then
        Storage.status = "存档编码失败"
        print("[存档] 编码失败：" .. tostring(text))
        return false
    end
    local file = File("bottle-save-" .. ((Storage.sequence % 2) + 1) .. ".json", FILE_WRITE)
    if not file:IsOpen() then
        file:Dispose()
        Storage.status = "无法写入本地存档"
        print("[存档] 本地文件不可写，请使用存档码")
        return false
    end
    local written = file:WriteString(text)
    file:Flush()
    file:Dispose()
    if not written then
        Storage.status = "存档写入失败"
        return false
    end
    Storage.status = "已保存"
    print(string.format("[存档] 已保存回合 %d，阶段 %s", game.round, game.phase))
    return true
end

return Storage
