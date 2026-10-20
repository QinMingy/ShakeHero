-- 基于既有2D物理验收脚手架：固定600步校准位移，不读写玩家存档。
-- 碰撞区域沿生产瓶体：4.8m × 6.4m；兔子与普通物品真实互撞及撞壁。
-- 检测目的：统计正常／强摇10秒真实累计路程，禁止把瞬移或界面像素当米。
local Physics = require("Bottle.Physics")
local Repair = require("Bottle.RepairTests")
local DT = 1 / 60
local Validation = {}

---@param count integer
---@param seed integer
---@param amplitude number
---@param id string?
---@return number
local function Measure(count, seed, amplitude, id)
    local subject = id or "rabbit"
    local ids = {subject}
    local pool = subject == "glutton" and {"soldier", "doctor", "ball"}
        or {"apple", "orange", "ball", "soldier", "banana"}
    for i = 2, count do ids[i] = pool[(i - 2) % #pool + 1] end
    local game = Repair.Fixture(ids)
    if subject == "glutton" then assert(game:Get(1)).scale = 1.5 end
    local sim = Physics.New()
    sim:Sync(game:BottleItems(), true, seed)
    sim:BeginShake()
    assert(game:Start())
    game:Step(0, sim:Contacts())
    local previous = sim.bodies[1].node.position2D
    local distance, lastX, lastY = 0.0, 0.0, 0.0
    local resizeCount = 0
    for step = 1, 600 do
        local t = step * DT
        local x = amplitude * math.sin(t * 2 * math.pi * 2)
        local y = amplitude * .6 * math.sin(t * 2 * math.pi * 1.7)
        sim:Shake(x - lastX, y - lastY)
        lastX, lastY = x, y
        sim:Step(DT)
        local position = sim.bodies[1].node.position2D
        local stepDistance = math.sqrt((position.x - previous.x)^2 + (position.y - previous.y)^2)
        -- 与生产采样相同：>=1m的单步跳变不是有效位移，重建后的姿态不计路程。
        if stepDistance < 1 then distance = distance + stepDistance end
        local events = game:Step(DT, sim:Contacts())
        for _, event in ipairs(events) do
            if event.kind == "resize" and event.uid == 1 then resizeCount = resizeCount + 1 end
        end
        sim:RememberEvents(events)
        sim:Sync(game:BottleItems())
        previous = sim.bodies[1].node.position2D
    end
    local item = assert(game:Get(1))
    local threshold = subject == "glutton" and 50 or 100
    local distanceTriggers = math.floor(distance / threshold)
    -- 夹具大胃王从150%缩回100%最多5次；路程达标但已到下限不再触发resize。
    local expected = subject == "glutton" and math.min(distanceTriggers, 5) or distanceTriggers
    local triggers = subject == "glutton" and resizeCount or item.permBonus
    print(string.format("[DistanceValidation] count=%d seed=%d amplitude=%.2f meters=%.5f subject=%s threshold=%d triggers=%d expected=%d resizes=%d",
        count, seed, amplitude, distance, subject, threshold, triggers, expected, resizeCount))
    assert(triggers == expected, "实际触发次数必须匹配真实路程/阈值及体积下限：" .. subject)
    if subject == "glutton" then
        assert(math.abs(item.scale - math.max(1, 1.5 - expected * .1)) < 1e-7, "大胃王实际缩幅匹配次数")
    end
    if subject ~= "glutton" or distanceTriggers < 5 then
        assert(math.abs(item.distance - (distance - distanceTriggers * threshold)) < 1e-7,
            "余程必须匹配真实路程：" .. subject)
    end
    assert(game.phase == "settle", "600固定步准确结束10秒摇晃")
    sim:EndShake()
    sim:Dispose()
    return distance
end

local function MeasureAutonomous(id, relics)
    local game = Repair.Fixture(id == "ghost" and {"ghost", "apple", "orange", "soldier"}
        or {"discus_athlete", "soldier", "doctor", "apple"}, relics)
    local sim = Physics.New()
    sim:Sync(game:BottleItems(), true, 337)
    assert(game:Start())
    sim:RememberEvents(game.startEvents)
    sim:Sync(game:BottleItems())
    game:Step(0, sim:Contacts())
    local scoreEvents, distance = 0, 0.0
    for _ = 1, 600 do
        ---@type table<number, {x:number,y:number}>
        local previous = {}
        for _, item in ipairs(game:BottleItems()) do
            local record = sim.bodies[item.uid]
            -- 首次入场尚无规则采样，闪回已清基线；二者都不能计成飞行路程。
            if item.id == id and record and game._lastPositions[item.uid] then
                local position = record.node.position2D
                previous[item.uid] = {x = position.x, y = position.y}
            end
        end
        sim:Step(DT)
        local contacts = sim:Contacts()
        for uid, before in pairs(previous) do
            local position = contacts.positions and contacts.positions[uid]
            if position then
                local stepDistance = math.sqrt((position.x - before.x)^2 + (position.y - before.y)^2)
                if stepDistance < 1 then distance = distance + stepDistance end
            end
        end
        local events = game:Step(DT, contacts)
        for _, event in ipairs(events) do
            if event.kind == "score" and event.id == id then scoreEvents = scoreEvents + 1 end
        end
        sim:RememberEvents(events)
        sim:Sync(game:BottleItems())
    end
    local threshold = id == "ghost" and 30 or 5 -- 幽灵运动每30m，飞盘仍每5m，不限定10秒次数。
    local expected = math.floor(distance / threshold)
    print(string.format("[DistanceValidation] autonomous=%s meters=%.5f threshold=%d triggers=%d expected=%d",
        id, distance, threshold, scoreEvents, expected))
    assert(scoreEvents == expected, "自主物品结算次数必须匹配真实路程/阈值：" .. id)
    assert(game.phase == "settle", "自主物品600固定步准确结束10秒摇晃")
    sim:Dispose()
end

function Validation.Run()
    for _, count in ipairs({4, 20}) do
        for _, amplitude in ipairs({.25, .5, .8}) do
            for _, seed in ipairs({137, 337, 739}) do Measure(count, seed, amplitude) end
        end
    end
    for _, count in ipairs({4, 20}) do
        for _, seed in ipairs({137, 337, 739}) do Measure(count, seed, .5, "glutton") end
    end
    MeasureAutonomous("ghost", {ghost_sport = true})
    MeasureAutonomous("discus", {})
end

function Start()
    local ok, err = pcall(function()
        Validation.Run()
        local total = require("Bottle.DistanceTests").Run()
        print("[DistanceValidation] PASS 26组真实物理场景；规则专项=" .. total)
    end)
    if not ok then print("[DistanceValidation] FAIL " .. tostring(err)) end
    engine:Exit()
end

return Validation
