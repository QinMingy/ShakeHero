-- Small Lua data records only. Engine nodes/resources keep their own lifetimes.
-- A pinned event transaction cannot recycle records still referenced by its snapshot.
local Records = {}
---@class BottleRecordPool
---@field capacity number
---@field free table[]
---@field pending table[]
---@field states table<table,number>
---@field created number
---@field reused number
---@field acquired number
---@field released number
---@field active number
---@field peak number
local Pool = {}
Pool.__index = Pool
local Scope = {}
Scope.__index = Scope

---@type table<table,table>
local owners = setmetatable({}, {__mode = "k"})
---@type table<table,boolean>
local pools = setmetatable({}, {__mode = "k"})
---@type table<thread,table>
local scopes = setmetatable({}, {__mode = "k"})
local pinCount = 0

---@param record table
local function clear(record)
    for key in pairs(record) do record[key] = nil end
    setmetatable(record, nil)
end

---@param pool table
---@param record table
local function recycle(pool, record)
    clear(record)
    if #pool.free < pool.capacity then
        pool.states[record] = 3
        pool.free[#pool.free + 1] = record
    else
        pool.states[record], owners[record] = nil, nil
    end
end

---@return table?
local function currentScope()
    local thread = coroutine.running()
    return thread and scopes[thread] or nil
end

---@param pool table
---@param record table
---@return boolean
local function releasable(pool, record)
    if owners[record] ~= pool or pool.states[record] ~= 1 then return false end
    local scope = currentScope()
    while scope do
        if not scope.committing and scope.borrowed[record] and not scope.created[record] then return false end
        scope = scope.previous
    end
    return true
end

---@param capacity integer? Maximum retained free records, never an active-object limit.
---@return BottleRecordPool
function Records.New(capacity)
    capacity = capacity or 256
    assert(capacity >= 0 and capacity % 1 == 0, "record pool capacity must be a nonnegative integer")
    local pool = setmetatable({capacity = capacity, free = {}, pending = {},
        states = setmetatable({}, {__mode = "k"}), created = 0, reused = 0,
        acquired = 0, released = 0, active = 0, peak = 0}, Pool)
    pools[pool] = true
    return pool
end

---@return any
function Pool:Acquire()
    local count = #self.free
    local record
    if count > 0 then
        record = self.free[count]
        self.free[count] = nil
        self.reused = self.reused + 1
    else
        record = {}
        self.created = self.created + 1
    end
    owners[record], self.states[record] = self, 1
    self.acquired, self.active = self.acquired + 1, self.active + 1
    self.peak = math.max(self.peak, self.active)
    local scope = currentScope()
    if scope then scope.created[record] = true end
    return record
end

---@param record table?
---@return boolean released
function Pool:Release(record)
    if not record or not releasable(self, record) then return false end
    self.released, self.active = self.released + 1, self.active - 1
    if pinCount > 0 then
        self.states[record] = 2
        self.pending[#self.pending + 1] = record
    else
        recycle(self, record)
    end
    return true
end

---@param record table?
---@return boolean
function Records.IsBorrowed(record)
    local scope = currentScope()
    while record and scope do
        if not scope.committing and scope.borrowed[record] and not scope.created[record] then return true end
        scope = scope.previous
    end
    return false
end

-- Walk with weak stamped marks instead of allocating a visited set per release.
local releaseStamp = 0
---@type table<table,number>
local releaseSeen = setmetatable({}, {__mode = "k"})
---@param value table
---@param stamp number
local function releaseChildren(value, stamp)
    if releaseSeen[value] == stamp then return end
    releaseSeen[value] = stamp
    for _, child in pairs(value) do
        if type(child) == "table" and releaseSeen[child] ~= stamp then
            local pool = owners[child]
            if not pool or releasable(pool, child) then
                releaseChildren(child, stamp)
                if pool then pool:Release(child) end
            end
        end
    end
end

---@param record table?
---@return boolean released
function Records.ReleaseRecord(record)
    local pool = record and owners[record]
    if not pool or not releasable(pool, record) then return false end
    releaseStamp = releaseStamp + 1
    releaseChildren(record, releaseStamp)
    return pool:Release(record)
end

---@param array table[]
function Pool:ClearActive(array)
    for index = #array, 1, -1 do
        Records.ReleaseRecord(array[index])
        array[index] = nil
    end
end

---@return table
function Pool:GetStats()
    return {created = self.created, reused = self.reused, acquired = self.acquired,
        released = self.released, active = self.active, peak = self.peak,
        free = #self.free, pending = #self.pending, capacity = self.capacity}
end

---@param value any
---@param target table
---@param seen table
local function markDeep(value, target, seen)
    if type(value) ~= "table" or seen[value] then return end
    seen[value] = true
    if owners[value] then target[value] = true end
    for _, child in pairs(value) do markDeep(child, target, seen) end
end

---@param value any
function Scope:BorrowDeep(value)
    markDeep(value, self.borrowed, self.borrowSeen)
end

---@param value any
function Scope:KeepDeep(value)
    markDeep(value, self.kept, self.keepSeen)
end

function Scope:Commit()
    self.committing = true
end

function Scope:Close()
    if self.closed then return end
    self.closed = true
    scopes[self.thread] = self.previous
    for record in pairs(self.created) do
        -- Every new child is tracked independently. Deep release here could retire
        -- a child already published through another live container.
        if not self.kept[record] then
            local pool = owners[record]
            if pool then pool:Release(record) end
        elseif self.previous then self.previous.created[record] = true end
    end
    pinCount = pinCount - 1
    if pinCount == 0 then
        for pool in pairs(pools) do
            for index = #pool.pending, 1, -1 do
                local record = pool.pending[index]
                pool.pending[index] = nil
                recycle(pool, record)
            end
        end
    end
end
Scope.__close = Scope.Close

---@return table guard Close explicitly or use Lua 5.4 local guard <close> = Records.Pin().
function Records.Pin()
    local thread = assert(coroutine.running())
    local scope = setmetatable({thread = thread, previous = scopes[thread],
        created = {}, borrowed = {}, kept = {}, borrowSeen = {}, keepSeen = {}}, Scope)
    scopes[thread] = scope
    pinCount = pinCount + 1
    return scope
end

---@return number
function Records.PinnedCount() return pinCount end

return Records
