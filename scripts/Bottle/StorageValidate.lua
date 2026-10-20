-- 存档写入专项：只在独立验收目录运行，不读取或覆盖玩家存档。
local Storage = require("Bottle.Storage")
local Game = require("Bottle.Game")

---@param name string
---@return string
local function Read(name)
    local file = File(name, FILE_READ)
    assert(file:IsOpen())
    local text, size = file:ReadString(), file:GetSize()
    file:Dispose()
    assert(size == #text + 1, "原生字符串必须保留末尾零字节")
    return text
end

function Start()
    local ok, message = pcall(function()
        assert(not fileSystem:FileExists("bottle-save-1.json")
            and not fileSystem:FileExists("bottle-save-2.json"), "验收目录必须没有玩家存档")
        local cases = require("Bottle.StorageTests").Run()
        print("STORAGE_FAILURE_CASES_PASS " .. cases)
        local game = Game.New(7319)
        Storage.sequence, Storage.slot = 0, 0
        assert(Storage.Save(game), Storage.status)
        local before = Read("bottle-save-2.json")
        assert(cjson.decode(before).sequence == 1 and Storage.sequence == 1 and Storage.slot == 2)
        assert(not fileSystem:FileExists("bottle-save-2.json.tmp"))
        assert(Storage.Load())
        print("STORAGE_NATIVE_INITIAL_PASS bytes=" .. (#before + 1))
        for sequence = 2, 12 do
            assert(Storage.Save(game) and Storage.sequence == sequence)
            local saved = cjson.decode(Read("bottle-save-" .. Storage.slot .. ".json"))
            assert(saved.sequence == sequence and saved.game.round == game.round)
            assert(Storage.Load() and Storage.sequence == sequence)
        end
        print("STORAGE_NATIVE_REPLACE_PASS 12")
        -- 真实写入旧格式，确认新读取器兼容旧WriteString而不是仅兼容内存替身。
        local old = File("bottle-save-1.json", FILE_WRITE)
        assert(old:IsOpen() and old:WriteString(before))
        old:Dispose()
        local broken = File("bottle-save-2.json", FILE_WRITE)
        assert(broken:IsOpen() and broken:WriteString("损坏的新存档"))
        broken:Dispose()
        assert(Storage.Load() and Storage.sequence == 1 and Storage.slot == 1)
        assert(Storage.Save(game) and Storage.sequence == 2 and Storage.slot == 2)
        assert(Read("bottle-save-1.json") == before, "回退后重试不能覆盖旧好槽")
        print("STORAGE_NATIVE_LEGACY_RECOVERY_PASS")
        assert(game:Start())
        assert(Storage.Save(game))
        local rollback = assert(Storage.Load())
        assert(rollback.phase == "prepare" and rollback.round == 1)
        game:Step(10)
        game:SettleStep(2)
        game:RevealStep(100)
        assert(game.phase == "draft" and Storage.Save(game))
        local draft = Game.Restore(assert(Storage.Load()))
        assert(draft.phase == "draft" and draft.score == game.score and draft.refreshes == game.refreshes)
        assert(draft:Choose(1) and Storage.Save(draft))
        local restored = Game.Restore(assert(Storage.Load()))
        assert(restored.phase == "prepare" and restored.round == 2 and #restored.deck == #draft.deck)
        print("STORAGE_NATIVE_ROUND_RESTORE_PASS")
        local tests = require("Bottle.Tests")
        print("STORAGE_FULL_RULES_PASS " .. tests.Run())
        assert(tests.jsonRoundtripRan, "原生cjson往返必须实际执行")
        print("STORAGE_VALIDATE_PASS")
    end)
    if not ok then log:Write(LOG_ERROR, "[存档验收] " .. tostring(message)) end
    engine:Exit()
end
