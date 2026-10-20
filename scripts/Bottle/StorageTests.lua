-- 存档异常回归仅使用内存文件；不会访问玩家存档。
local Storage = require("Bottle.Storage")
local Game = require("Bottle.Game")
local Tests = {}

---@param run fun(files:table<string,string>,fault:table)
local function WithFiles(run)
    local original = {}
    for key, value in pairs(Storage) do original[key] = value end
    local nativeFile, nativeFS = rawget(_G, "File"), rawget(_G, "fileSystem")
    local files, fault = {}, {stage = "", handles = 0, writes = 0}
    Storage.sequence, Storage.slot, Storage.readBlocked = 0, 0, false
    rawset(_G, "fileSystem", {
        FileExists = function(_, name) return files[name] ~= nil end,
        Rename = function(_, source, target)
            if fault.stage == "rename" then return false end
            if not files[source] then return false end
            files[target], files[source] = files[source], nil
            return true
        end,
    })
    rawset(_G, "File", function(name, mode)
        if fault.stage == "construct" then error("测试构造失败") end
        local writable, closed = mode == FILE_WRITE, false
        local text = files[name] or ""
        fault.handles = fault.handles + 1
        if writable then fault.writes = fault.writes + 1 end
        return {
            IsOpen = function() return fault.stage ~= "open" and (writable or files[name] ~= nil) end,
            GetSize = function() return #text + 1 end,
            ReadString = function()
                if fault.stage == "read" or fault.stage == "readNewest" and name == "bottle-save-1.json" then
                    error("测试读取异常")
                end
                return text
            end,
            Write = function(_, buffer)
                if fault.stage == "writeError" then error("测试写入异常") end
                buffer:Seek(0)
                text = buffer:ReadString()
                if fault.stage == "short" then
                    text = text:sub(1, #text // 2)
                    return #text
                end
                return buffer:GetSize()
            end,
            Flush = function()
                if fault.stage == "flush" then error("测试刷新异常") end
                if writable then files[name] = fault.stage == "corrupt" and "{}" or text end
            end,
            Close = function()
                if fault.stage == "close" then error("测试关闭前异常") end
            end,
            Dispose = function()
                if not closed then fault.handles = fault.handles - 1; closed = true end
                if fault.stage == "dispose" then error("测试释放异常") end
            end,
        }
    end)
    local ok, message = pcall(run, files, fault)
    rawset(_G, "File", nativeFile)
    rawset(_G, "fileSystem", nativeFS)
    for key in pairs(Storage) do if original[key] == nil then Storage[key] = nil end end
    for key, value in pairs(original) do Storage[key] = value end
    assert(ok, tostring(message))
end

---@return integer
function Tests.Run()
    assert(rawget(_G, "cjson"), "存档回归必须实际提供cjson，禁止跳过计为通过")
    local passed = 0
    for _, stage in ipairs({"construct", "open", "short", "writeError", "flush", "close", "dispose", "corrupt", "read", "rename"}) do
        WithFiles(function(files, fault)
            local game = Game.New(7123)
            assert(Storage.Save(game))
            local before = assert(files["bottle-save-2.json"])
            assert(Storage.slot == 2 and Storage.sequence == 1)
            assert(game:Reroll())
            fault.stage = stage
            for _ = 1, 3 do
                local ok, saved = pcall(Storage.Save, game)
                assert(ok and saved == false, "异常必须返回false而非中断游戏：" .. stage)
                assert(Storage.sequence == 1 and Storage.slot == 2, "失败不能提交序号或槽位")
                assert(files["bottle-save-2.json"] == before and files["bottle-save-1.json"] == nil,
                    "连续失败不得截断正式档：" .. stage)
                assert(Storage.status ~= "已保存" and fault.handles == 0, "失败不能误报成功或泄漏句柄")
            end
            fault.stage = ""
            assert(Storage.Save(game) and Storage.sequence == 2 and Storage.slot == 1)
            assert(files["bottle-save-2.json"] == before, "重试成功仍保留前次好档")
            assert(files["bottle-save-1.json.tmp"] == nil, "成功提交后无残留临时文件")
            local restored = assert(Storage.Load())
            assert(restored.refreshes == game.refreshes and Storage.sequence == 2 and Storage.slot == 1)
            assert(fault.handles == 0)
        end)
        passed = passed + 1
    end
    WithFiles(function(files, fault)
        local game = Game.New(7123)
        assert(Storage.Save(game))
        local before, writes = files["bottle-save-2.json"], fault.writes
        local snapshot = game.Snapshot
        game.Snapshot = function() error("测试快照异常") end
        assert(not Storage.Save(game) and Storage.sequence == 1 and Storage.slot == 2)
        game.Snapshot = snapshot
        local encode = cjson.encode
        cjson.encode = function() error("测试编码异常") end
        local ok, saved = pcall(Storage.Save, game)
        cjson.encode = encode
        assert(ok and saved == false and fault.writes == writes)
        assert(files["bottle-save-2.json"] == before and Storage.sequence == 1)
        assert(Storage.Save(game))
    end)
    passed = passed + 1
    WithFiles(function(files)
        local game = Game.New(7123)
        -- 旧序号与实际槽位可不对应；新写入必须避开实际好槽而不是只看奇偶。
        files["bottle-save-2.json"] = cjson.encode({format = "bottle-lab-v1", sequence = 8,
            game = game:Snapshot()})
        files["bottle-save-1.json"] = "{}"
        local before = files["bottle-save-2.json"]
        assert(Storage.Load() and Storage.sequence == 8 and Storage.slot == 2)
        assert(Storage.Save(game) and Storage.sequence == 9 and Storage.slot == 1)
        assert(files["bottle-save-2.json"] == before)
        files["bottle-save-1.json"] = "损坏"
        assert(Storage.Load() and Storage.sequence == 8 and Storage.slot == 2)
        assert(Storage.Save(game) and Storage.slot == 1)
    end)
    passed = passed + 1
    WithFiles(function(files)
        local game = Game.New(7123)
        assert(Storage.Save(game))
        files["bottle-save-1.json.tmp"] = cjson.encode({format = "bottle-lab-v1", sequence = 100,
            game = game:Snapshot()})
        assert(Storage.Load() and Storage.sequence == 1 and Storage.slot == 2,
            "中断产生的临时文件不能冒充已提交存档")
        Storage.sequence = 2147483646
        local before = files["bottle-save-2.json"]
        assert(not Storage.Save(game) and Storage.sequence == 2147483646)
        assert(files["bottle-save-2.json"] == before and files["bottle-save-1.json"] == nil)
    end)
    passed = passed + 1
    for _, stage in ipairs({"read", "readNewest"}) do
        WithFiles(function(files, fault)
            local game = Game.New(7123)
            assert(Storage.Save(game) and Storage.Save(game))
            local one, two = files["bottle-save-1.json"], files["bottle-save-2.json"]
            local writes = fault.writes
            fault.stage = stage
            assert(Storage.Load() == nil and Storage.readBlocked)
            assert(Storage.sequence == 2 and Storage.slot == 1, "读取错误不清除已提交状态")
            for _ = 1, 3 do assert(not Storage.Save(Game.New(9876))) end
            assert(fault.writes == writes and files["bottle-save-1.json"] == one
                and files["bottle-save-2.json"] == two, "启动误建的新局不得覆盖暂时不可读的旧档")
            fault.stage = ""
            assert(Storage.Load() and not Storage.readBlocked and Storage.sequence == 2)
            assert(Storage.Save(game))
        end)
        passed = passed + 1
    end
    return passed
end

return Tests
