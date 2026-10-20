-- 协作式帧预算：只在显式安全边界让出，不改变同步规则调用或丢弃积压工作。
-- 默认预算为4毫秒；原生不可拆分调用只能在返回后检查，不能被协程抢占。
---@class BottleFrameBudget
---@field budgetMs number
---@field maxCheckpoints integer
---@field clock fun():number
---@field startedAt number
---@field checkpoints integer
---@field yielded boolean
---@field worker thread?
---@field slices integer
---@field totalYields integer
---@field lastElapsedMs number
local FrameBudget = {}
FrameBudget.__index = FrameBudget

FrameBudget.DEFAULT_MS = 4
FrameBudget.DEFAULT_MAX_CHECKPOINTS = 4096
---@type table<thread, BottleFrameBudget>
local owners = setmetatable({}, {__mode = "k"})

-- 使用运行端os.clock的计数差，不用帧dt近似执行耗时；具体时钟语义依平台。
-- 当前Runtime的Time:GetSystemTime绑定实测不可调用（类型错误），因此不依赖该接口。
---@return number
local function Clock()
    return os.clock() * 1000
end

---@param budgetMs number?
---@param clock (fun():number)? 测试可注入确定时钟
---@param maxCheckpoints integer? 防止计时精度不足或时钟异常时单帧无限处理
---@return BottleFrameBudget
function FrameBudget.New(budgetMs, clock, maxCheckpoints)
    local self = setmetatable({}, FrameBudget)
    self:Init(budgetMs, clock, maxCheckpoints)
    return self
end

function FrameBudget:Init(budgetMs, clock, maxCheckpoints)
    self.budgetMs = budgetMs or FrameBudget.DEFAULT_MS
    self.maxCheckpoints = maxCheckpoints or FrameBudget.DEFAULT_MAX_CHECKPOINTS
    assert(self.budgetMs > 0 and self.budgetMs < math.huge, "帧预算必须为正有限毫秒数")
    assert(self.maxCheckpoints >= 1 and self.maxCheckpoints % 1 == 0, "分片检查上限必须为正整数")
    self.clock = clock or Clock
    self.startedAt, self.checkpoints = 0, 0
    self.yielded = false
    self.worker = nil
    self.slices, self.totalYields, self.lastElapsedMs = 0, 0, 0
end

function FrameBudget:BeginFrame()
    self.startedAt = self.clock()
    self.checkpoints = 0
    self.yielded = false
end

---@return boolean
function FrameBudget:Expired()
    local elapsed = self.clock() - self.startedAt
    self.lastElapsedMs = math.max(0, elapsed)
    -- 时钟倒退时保守让出；不猜测系统计数器的位宽或回绕周期。
    return self.yielded or elapsed < 0 or elapsed >= self.budgetMs
        or self.checkpoints >= self.maxCheckpoints
end

---@param work fun()
function FrameBudget:Start(work)
    assert(not self.worker, "不能覆盖尚未完成的分帧任务")
    self.worker = coroutine.create(work)
    owners[self.worker] = self
end

---@return boolean complete
function FrameBudget:Resume()
    if not self.worker then return true end
    if self.yielded then return false end
    local worker = self.worker
    self.slices = self.slices + 1
    local ok, message = coroutine.resume(worker)
    if not ok then
        owners[worker] = nil
        self.worker = nil
        coroutine.close(worker)
        error("[分帧任务] " .. tostring(message), 0)
    end
    if coroutine.status(worker) == "dead" then
        owners[worker] = nil
        self.worker = nil
        self.lastElapsedMs = math.max(0, self.clock() - self.startedAt)
        return true
    end
    self.yielded = true
    self.totalYields = self.totalYields + 1
    return false
end

---@return boolean
function FrameBudget:Busy()
    return self.worker ~= nil
end

-- 取消仅用于整局废弃/退出；不能丢掉半步后继续同一局，否则规则与物理会不一致。
function FrameBudget:Cancel()
    if self.worker then
        owners[self.worker] = nil
        -- Close Lua 5.4 guards held across a yield (notably pinned record snapshots).
        local ok, message = coroutine.close(self.worker)
        self.worker = nil
        if not ok then error("[取消分帧任务] " .. tostring(message), 0) end
    end
    self.worker = nil
end

-- 同步调用没有owner，保持原API一次返回；也不在引擎接触回调里隐式yield。
function FrameBudget.Checkpoint()
    local worker = coroutine.running()
    local owner = worker and owners[worker]
    if not owner then return end
    owner.checkpoints = owner.checkpoints + 1
    if owner:Expired() then coroutine.yield() end
end

return FrameBudget
