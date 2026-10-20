-- Event presentation is private until the complete batch commits.
-- Reusable workspaces retain snapshots across yields; pool pins prevent ABA reuse.
local FrameBudget = require("Bottle.FrameBudget")
local Records = require("Bottle.RecordPool")
local Stage = {}
local ABSENT = {}
local BOARD_ARRAYS = {"particles", "scoreQueue", "burstRings", "bursts", "dashTrails", "pops"}
local BOARD_MAPS = {"pulses", "residue", "feedbackPopMute", "inflations", "explodedUids", "dashEmitters", "presentUids"}
local Workspace = {}
Workspace.__index = Workspace
---@type table<table,table>
local workspaces = setmetatable({}, {__mode = "k"})

---@param target table
local function Clear(target)
    for key in pairs(target) do target[key] = nil end
end

---@param source table
---@param target table?
---@return table
local function Copy(source, target)
    target = target or {}
    Clear(target)
    for key, value in pairs(source) do target[key] = value end
    return setmetatable(target, getmetatable(source))
end

---@param value any
---@return any
local function Unwrap(value)
    if value ~= ABSENT then return value end
end

---@param record table
---@return table
local function Proxy(record)
    return setmetatable({}, {
        __index = function(_, key)
            local value = record.writes[key]
            if value ~= nil then return Unwrap(value) end
            return record.values[key]
        end,
        __newindex = function(_, key, value) record.writes[key] = value == nil and ABSENT or value end,
        __pairs = function()
            Copy(record.values, record.merged)
            for key, value in pairs(record.writes) do record.merged[key] = Unwrap(value) end
            return next, record.merged, nil
        end,
    })
end

---@param workspace table
---@param owner table
---@param target table
---@param field string
---@param limit number?
---@return table
local function Array(workspace, owner, target, field, limit)
    FrameBudget.Checkpoint()
    local index = workspace.arrayCount + 1
    workspace.arrayCount = index
    local record = workspace.arrays[index]
    if not record then
        record = {values = {}, original = {}, removed = {}, added = {}, retained = {}}
        workspace.arrays[index] = record
    end
    record.owner, record.field, record.limit, record.reject = owner, field, limit, nil
    Clear(record.values);Clear(record.original);Clear(record.removed);Clear(record.added);Clear(record.retained)
    workspace.pin:BorrowDeep(owner[field])
    for itemIndex, value in ipairs(owner[field]) do
        record.values[itemIndex], record.original[value] = value, true
    end
    target[field] = record.values
    return record
end

---@param workspace table
---@param owner table
---@param target table
---@param field string
---@param entries boolean?
local function Map(workspace, owner, target, field, entries)
    FrameBudget.Checkpoint()
    local index = workspace.mapCount + 1
    workspace.mapCount = index
    local record = workspace.maps[index]
    if not record then
        record = {original = {}, values = {}, writes = {}, merged = {},
            entryValues = {}, entryOriginal = {}}
        record.proxy = Proxy(record)
        workspace.maps[index] = record
    end
    record.owner, record.field, record.entries = owner, field, entries == true
    Clear(record.original);Clear(record.values);Clear(record.writes);Clear(record.merged)
    local live = owner[field]
    workspace.pin:BorrowDeep(live)
    for key in pairs(record.entryValues) do
        if not live[key] then record.entryValues[key], record.entryOriginal[key] = nil, nil end
    end
    for key, value in pairs(live) do
        if entries and type(value) == "table" then
            local a = Copy(value, record.entryValues[key])
            local b = Copy(value, record.entryOriginal[key])
            record.entryValues[key], record.entryOriginal[key] = a, b
            record.values[key], record.original[key] = a, b
        else
            record.values[key], record.original[key] = value, value
        end
    end
    target[field] = record.proxy
end

---@param record table
local function PrepareArray(record)
    for _, value in ipairs(record.values) do
        record.retained[value] = true
        if not record.original[value] then record.added[#record.added + 1] = value end
    end
    for value in pairs(record.original) do
        if not record.retained[value] then record.removed[value] = true end
    end
end

---@param record table
local function PublishArray(record)
    local live, count = record.owner[record.field], 0
    local length = #live
    for index = 1, length do
        local value = live[index]
        if not record.removed[value] and not (record.reject and record.reject(value)) then
            count = count + 1;live[count] = value
        else Records.ReleaseRecord(value) end
    end
    for index = count + 1, length do live[index] = nil end
    for _, value in ipairs(record.added) do
        if not (record.reject and record.reject(value)) then
            count = count + 1;live[count] = value
        else Records.ReleaseRecord(value) end
    end
    if record.limit and count > record.limit then
        local trim = count - record.limit
        for index = 1, trim do Records.ReleaseRecord(live[index]) end
        for index = 1, count - trim do live[index] = live[index + trim] end
        for index = count, count - trim + 1, -1 do live[index] = nil end
    end
end

---@param record table
local function PublishMap(record)
    local live = record.owner[record.field]
    if record.entries then
        for key, value in pairs(record.values) do
            local original = record.original[key]
            if type(original) == "table" and live[key] and record.writes[key] == nil then
                for field, old in pairs(original) do
                    if value[field] ~= old then live[key][field] = value[field] end
                end
                for field, new in pairs(value) do
                    if original[field] == nil then live[key][field] = new end
                end
            end
        end
    end
    for key, value in pairs(record.writes) do
        local nextValue = Unwrap(value)
        if live[key] ~= nextValue then Records.ReleaseRecord(live[key]) end
        live[key] = nextValue
    end
end

-- Called on normal return, errors and coroutine.close after cancellation.
function Workspace:Close()
    self.busy, self.pin = false, nil
    for _, record in ipairs(self.arrays) do
        Clear(record.values);Clear(record.original);Clear(record.removed);Clear(record.added);Clear(record.retained)
        record.owner, record.reject = nil, nil
    end
    for _, record in ipairs(self.maps) do
        Clear(record.values);Clear(record.original);Clear(record.writes);Clear(record.merged)
        for _, row in pairs(record.entryValues) do Clear(row) end
        for _, row in pairs(record.entryOriginal) do Clear(row) end
        record.owner = nil
    end
    Clear(self.feedback);Clear(self.flashes);Clear(self.coins)
    Clear(self.forgotten);Clear(self.batches)
    Clear(self.staged)
end
Workspace.__close = Workspace.Close

---@param board table
---@return table
local function GetWorkspace(board)
    local workspace = workspaces[board]
    if not workspace then
        workspace = setmetatable({arrays = {}, maps = {}, feedback = {}, flashes = {}, coins = {},
            forgotten = {}, batches = {}, staged = setmetatable({}, {__index = board})}, Workspace)
        workspaces[board] = workspace
    end
    assert(not workspace.busy, "同一Board不能嵌套未提交的表现事务")
    workspace.busy, workspace.arrayCount, workspace.mapCount = true, 0, 0
    return workspace
end

---@param board BottleBoard
---@param work fun(staged:BottleBoard)
function Stage.Apply(board, work, physicsSnapshot)
    local workspace <close> = GetWorkspace(board)
    local pin <close> = Records.Pin()
    workspace.pin = pin
    local staged = workspace.staged
    staged.physics = physicsSnapshot or board.physics
    for _, field in ipairs(BOARD_ARRAYS) do Array(workspace, board, staged, field) end
    for _, field in ipairs(BOARD_MAPS) do Map(workspace, board, staged, field, field == "residue") end
    local beforeCoins, beforeShake = board.coinsInFlight, board.shakeCoinsInFlight
    staged.coinsInFlight, staged.shakeCoinsInFlight = beforeCoins, beforeShake
    staged.displayScore, staged.ppu = board.displayScore, board.ppu
    local feedback, flashes, coins = board.itemFeedback, board.consumeFlash, board.coinPickups
    staged.itemFeedback, staged.consumeFlash, staged.coinPickups =
        Copy(feedback, workspace.feedback), Copy(flashes, workspace.flashes), Copy(coins, workspace.coins)
    local feedbackSerial, coinSerial = staged.itemFeedback.serial, staged.coinPickups.serial
    Array(workspace, feedback, staged.itemFeedback, "effects", feedback.MAX_EFFECTS)
    local feedbackParticles = Array(workspace, feedback, staged.itemFeedback, "particles", feedback.MAX_PARTICLES)
    Map(workspace, feedback, staged.itemFeedback, "stars", true)
    Map(workspace, feedback, staged.itemFeedback, "seen")
    Array(workspace, flashes, staged.consumeFlash, "flashes")
    Array(workspace, flashes, staged.consumeFlash, "popups")
    Map(workspace, flashes, staged.consumeFlash, "rebounds", true)
    Map(workspace, flashes, staged.consumeFlash, "seen")
    Array(workspace, coins, staged.coinPickups, "coins")
    Array(workspace, coins, staged.coinPickups, "waiting")
    local forgotten = workspace.forgotten
    local forgetStar = feedback.ForgetStar
    if forgetStar then
        staged.itemFeedback.ForgetStar = function(self, uid)
            forgotten[uid] = true
            forgetStar(self, uid)
        end
    end
    feedbackParticles.reject = function(value) return forgotten[value.ownerUid] == true end
    for _, record in ipairs(workspace.arrays) do
        if record.owner == board and record.field == "dashTrails" then
            record.reject = function(value)
                for _, map in ipairs(workspace.maps) do
                    if map.owner == board and map.field == "dashEmitters" then
                        return map.writes[value.uid] == ABSENT
                    end
                end
                return false
            end
        end
    end
    local batches = workspace.batches
    staged.coinPickups.Burst = function(_, amount, x, y, source, height)
        if amount > 0 then batches[#batches + 1] = {amount = amount, x = x, y = y, source = source, height = height} end
    end
    staged.GetAbsoluteLayout = function() return board:GetAbsoluteLayout() end
    work(staged)
    for _, record in ipairs(workspace.arrays) do PrepareArray(record) end
    -- From this point there is no yield: drop/recycle only actual live removals.
    pin:Commit()
    for _, record in ipairs(workspace.arrays) do PublishArray(record) end
    for _, record in ipairs(workspace.maps) do PublishMap(record) end
    board.coinsInFlight = board.coinsInFlight + staged.coinsInFlight - beforeCoins
    board.shakeCoinsInFlight = board.shakeCoinsInFlight + staged.shakeCoinsInFlight - beforeShake
    if board.displayScore == nil then board.displayScore = rawget(staged, "displayScore") end
    feedback.serial = (feedback.serial + staged.itemFeedback.serial - feedbackSerial) % 65521
    coins.serial = coins.serial + staged.coinPickups.serial - coinSerial
    for _, batch in ipairs(batches) do coins:Burst(batch.amount, batch.x, batch.y, batch.source, batch.height) end
    for _, record in ipairs(workspace.arrays) do pin:KeepDeep(record.owner[record.field]) end
    for _, record in ipairs(workspace.maps) do pin:KeepDeep(record.owner[record.field]) end
end

return Stage
