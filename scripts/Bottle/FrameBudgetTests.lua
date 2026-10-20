-- 协作式帧预算的纯 Lua 回归；不创建引擎对象、不读取系统时钟。
-- 独立入口：require("Bottle.FrameBudgetTests").Run()
local FrameBudget = require("Bottle.FrameBudget")
local Tests = {}

---@type {name:string, run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end

---@param work fun()
---@param text string
local function Reject(work, text)
    local ok, message = pcall(work)
    assert(not ok and tostring(message):find(text, 1, true), "未传播预期异常：" .. tostring(message))
end

-- 仅测试读取私有 owner 注册表，以直接验证异常路径没有遗留所有权。
-- 不修改 upvalue；debug.getupvalue 是标准 Lua API，不依赖引擎或外部执行器。
---@return table<thread, BottleFrameBudget>
local function Owners()
    for index = 1, 20 do
        local name, value = debug.getupvalue(FrameBudget.Checkpoint, index)
        if not name then break end
        if name == "owners" then return value end
    end
    error("Checkpoint 未暴露预期的 owner 注册表")
end

Test("预算到期让出，同帧禁止二次resume，下一帧从断点继续", function()
    local clock = {now=0}
    local budget = FrameBudget.New(4, function() return clock.now end, 100)
    local visits = {}
    budget:BeginFrame()
    budget:Start(function()
        visits[#visits + 1] = "before"
        clock.now = 4 -- 恰好达到预算也必须让出。
        FrameBudget.Checkpoint()
        visits[#visits + 1] = "after"
    end)
    assert(budget:Busy() and not budget:Resume())
    assert(#visits == 1 and visits[1] == "before")
    assert(budget.yielded and budget.slices == 1 and budget.totalYields == 1)
    assert(budget.lastElapsedMs == 4 and budget:Expired())
    assert(not budget:Resume() and not budget:Resume())
    assert(#visits == 1 and budget.slices == 1, "同帧不得再次执行协程")
    budget:BeginFrame()
    assert(not budget.yielded and budget.checkpoints == 0)
    assert(budget:Resume() and not budget:Busy())
    assert(#visits == 2 and visits[2] == "after" and budget.slices == 2)
    assert(budget:Resume() and budget.slices == 2, "空闲resume必须无副作用")
end)

Test("预算内Checkpoint不会让出", function()
    local budget = FrameBudget.New(4, function() return 0 end, 10)
    local calls = 0
    budget:BeginFrame()
    budget:Start(function()
        for _ = 1, 3 do FrameBudget.Checkpoint(); calls = calls + 1 end
    end)
    assert(budget:Resume() and calls == 3)
    assert(budget.checkpoints == 3 and budget.totalYields == 0 and not budget.yielded)
end)

Test("FIFO工作跨帧逐项执行一次，不重做或跳项", function()
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    local queue, visits = {11, 22, 33, 44, 55}, {}
    budget:Start(function()
        while #queue > 0 do
            FrameBudget.Checkpoint()
            visits[#visits + 1] = table.remove(queue, 1)
        end
    end)
    for frame = 1, 6 do
        budget:BeginFrame()
        local completed = budget:Resume()
        assert(#visits == frame - 1, "断点恢复不应重复当前队首")
        for i, uid in ipairs(visits) do assert(uid == i * 11, "FIFO顺序改变") end
        assert(completed == (frame == 6))
        if not completed then
            local slices = budget.slices
            assert(not budget:Resume() and budget.slices == slices)
        end
    end
    assert(#queue == 0 and #visits == 5 and budget.totalYields == 5)
end)

Test("同步调用和非owner协程Checkpoint保持同步且不污染预算", function()
    local budget = FrameBudget.New(4, function() return 100 end, 1)
    budget:BeginFrame()
    budget:Start(function() FrameBudget.Checkpoint() end)
    for _ = 1, 20 do FrameBudget.Checkpoint() end
    assert(budget.checkpoints == 0 and budget.slices == 0)
    local finished = false
    local foreign = coroutine.create(function()
        for _ = 1, 20 do FrameBudget.Checkpoint() end
        finished = true
    end)
    assert(coroutine.resume(foreign) and coroutine.status(foreign) == "dead" and finished)
    assert(budget.checkpoints == 0, "无owner协程不得归入别的任务")
    budget:Cancel()
end)

Test("异常原样传播并清worker及owner，之后可以启动新任务", function()
    local budget = FrameBudget.New(4, function() return 0 end, 100)
    budget:BeginFrame()
    budget:Start(function() error("frame-budget-test-sentinel", 0) end)
    local worker = assert(budget.worker)
    assert(Owners()[worker] == budget)
    Reject(function() budget:Resume() end, "[分帧任务] frame-budget-test-sentinel")
    assert(not budget:Busy() and budget.worker == nil and Owners()[worker] == nil)
    assert(coroutine.status(worker) == "dead")
    local finished = false
    budget:BeginFrame()
    budget:Start(function() FrameBudget.Checkpoint(); finished = true end)
    assert(budget:Resume() and finished and budget.totalYields == 0)
end)

Test("cancel移除owner且不续旧任务，空闲cancel幂等", function()
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    local visits = {}
    budget:BeginFrame()
    budget:Start(function()
        FrameBudget.Checkpoint()
        visits[#visits + 1] = "old"
        FrameBudget.Checkpoint()
        visits[#visits + 1] = "old-end"
    end)
    local old = assert(budget.worker)
    assert(not budget:Resume())
    budget:Cancel()
    assert(not budget:Busy() and Owners()[old] == nil)
    budget:Cancel()
    budget:BeginFrame()
    assert(budget:Resume() and #visits == 0, "cancel之后不得恢复旧任务")
    budget:Start(function() visits[#visits + 1] = "new" end)
    assert(budget:Resume() and #visits == 1 and visits[1] == "new")
    -- 取消会关闭协程并释放跨yield的作用域，外部旧句柄也不能复活任务。
    assert(not coroutine.resume(old) and coroutine.status(old) == "dead")
    assert(#visits == 1 and visits[1] == "new")
end)

Test("尚有任务时Start拒绝覆盖且原任务仍能完成", function()
    local budget = FrameBudget.New(4, function() return 0 end, 1)
    local finished = false
    budget:Start(function() FrameBudget.Checkpoint(); finished = true end)
    local worker = budget.worker
    Reject(function() budget:Start(function() error("不应运行") end) end, "不能覆盖")
    assert(budget.worker == worker)
    budget:BeginFrame(); assert(not budget:Resume())
    budget:BeginFrame(); assert(budget:Resume() and finished)
end)

Test("冻结时钟由Checkpoint上限兜底，每帧仍取得进展", function()
    local budget = FrameBudget.New(4, function() return 123 end, 3)
    local visits = 0
    budget:Start(function()
        for _ = 1, 8 do FrameBudget.Checkpoint(); visits = visits + 1 end
    end)
    local expected = {2, 5, 8}
    for frame, count in ipairs(expected) do
        budget:BeginFrame()
        assert(budget:Resume() == (frame == 3))
        assert(visits == count and budget.lastElapsedMs == 0)
    end
    assert(budget.totalYields == 2 and not budget:Busy())
end)

Test("倒退时钟保守让出且耗时不为负，下帧继续不丢工作", function()
    local clock = {now=20}
    local budget = FrameBudget.New(4, function() return clock.now end, 10)
    local finished = false
    budget:BeginFrame()
    budget:Start(function()
        clock.now = 19
        FrameBudget.Checkpoint()
        finished = true
    end)
    assert(not budget:Resume() and not finished and budget:Expired())
    assert(budget.lastElapsedMs == 0 and budget.checkpoints == 1)
    budget:BeginFrame()
    assert(budget:Resume() and finished and budget.lastElapsedMs == 0)
end)

---@return integer passed
function Tests.Run()
    local passed = 0
    for _, case in ipairs(cases) do
        local ok, message = pcall(case.run)
        assert(ok, "Bottle.FrameBudgetTests [" .. case.name .. "] " .. tostring(message))
        passed = passed + 1
    end
    return passed
end

return Tests
