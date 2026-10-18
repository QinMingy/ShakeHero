-- 真实Box2D旋转/重建专项；沿用已有2D物理脚手架，不读写玩家存档。
-- 隔离验收：本文件同时作入口与validate-test；主agent统一执行，不参与正常入口。
-- 碰撞设计：单实体置瓶心(0,3)，无重力自由旋转；培根五段位于同一中心，
-- 不放其他实体，避免把接触响应误当强制角误差；另测幽灵动态sensor直立豁免。
-- 检测目的：真实Step前后自然角/强制角分账；重建不伪造自然进度或覆盖显式坐标。
local Physics = require("Bottle.Physics")
---@type BottlePhysics[]
local worlds = {}
local PI, DT = math.pi, 1 / 60
local cases = {}

local function case(name, run) cases[#cases + 1] = {name = name, run = run} end
local function near(a, b, epsilon) return math.abs(a - b) <= (epsilon or 1e-5) end
local function angleNear(a, b) return math.abs((a - b + PI) % (2 * PI) - PI) < 1e-4 end

local function make(id)
    local sim = Physics.New()
    worlds[#worlds + 1] = sim
    local item = {uid = 1, id = id, location = "bottle", scale = 1, weight = 1, woolCount = 0} --[[@as any]]
    ---@type ItemInstance[]
    local items = {item}
    sim:Sync(items, true, 173)
    local record = assert(sim.bodies[1])
    local center = record.node.position2D
    for _, part in ipairs(record.parts) do
        local p = part.node.position2D
        part.node:SetPosition2D(p.x - center.x, p.y - center.y + 3)
        part.body.gravityScale = 0
        part.body.linearDamping, part.body.angularDamping = 0, 0
        part.body.linearVelocity = Vector2(0, 0)
        part.body.angularVelocity = 0
        part.body.awake = true
    end
    record.newbornRemaining = 0
    sim.expansion:State(record).angle = record.node.rotation2D * PI / 180
    return sim, items
end

local function command(sim, items, delta, duration)
    sim:RememberEvents({{kind = "rotate", uid = 1, delta = delta, duration = duration}})
    sim:Sync(items)
end
local function steps(sim, count) for _ = 1, count do sim:Step(DT) end end
local function clean()
    for _, sim in ipairs(worlds) do sim:Dispose() end
    worlds = {}
end

case("持续命令不瞬转并在60固定步完成", function(check)
    local sim, items = make("apple")
    local start = sim:Contacts().angles[1]
    command(sim, items, -PI / 2, 1)
    check(angleNear(sim:Contacts().angles[1], start)
        and sim:Contacts().rotateOffsets[1] == 0, "Flush只排任务，不瞬转或预记完整角差")
    local previous, smooth = 0, true
    for step = 1, 60 do
        sim:Step(DT)
        local offset = sim:Contacts().rotateOffsets[1]
        smooth = smooth and near(offset, -PI / 2 * step / 60, 1e-8)
            and near(offset - previous, -PI / 120, 1e-8)
        previous = offset
    end
    local contacts = sim:Contacts()
    check(smooth and #sim.expansion.states[1].rotations == 0, "60步匀速完成，无浮点尾帧")
    check(angleNear(contacts.angles[1], start - PI / 2) and contacts.angularTravel[1] < 1e-5,
        "顺时针90度全部为强制角，不计自然绝对进度")
end)

case("自然正反转独立且指南针仍瞬转", function(check)
    local sim, items = make("apple")
    local record = sim.bodies[1]
    record.body.angularVelocity = 2
    local start = sim:Contacts().angles[1]
    command(sim, items, -PI / 2, 1)
    steps(sim, 30)
    local half = sim:Contacts()
    check(near(half.angularTravel[1], 1, 1e-4)
        and near(half.rotateOffsets[1], -PI / 4), "同方向/反方向混合也只计真实自然1弧度")
    record.body.angularVelocity = -2
    command(sim, items, -PI / 2)
    check(near(sim:Contacts().rotateOffsets[1], -3 * PI / 4)
        and near(sim:Contacts().angularTravel[1], half.angularTravel[1]), "无duration指南针立即完成且不回灌进度")
    steps(sim, 30)
    local result = sim:Contacts()
    check(near(result.angularTravel[1], 2, 2e-4)
        and near(result.rotateOffsets[1], -PI), "反转自然绝对值继续累计，持续任务未被瞬转覆盖")
    check(angleNear(result.angles[1], start - PI), "自然正反转抵消，保留两次强制角")
end)

case("多齿轮同帧和错峰动作独立叠加", function(check)
    local sim, items = make("apple")
    command(sim, items, -PI / 2, 1)
    command(sim, items, -PI, 1)
    steps(sim, 30)
    check(near(sim:Contacts().rotateOffsets[1], -3 * PI / 4), "同帧两任务半秒叠加")
    command(sim, items, -PI / 2, 1)
    steps(sim, 30)
    check(near(sim:Contacts().rotateOffsets[1], -7 * PI / 4)
        and #sim.expansion.states[1].rotations == 1, "先两任务满秒完成，错峰任务只完成一半")
    steps(sim, 30)
    check(near(sim:Contacts().rotateOffsets[1], -2 * PI)
        and #sim.expansion.states[1].rotations == 0, "错峰任务按自己的满秒完成")
end)

case("resize保留任务自然累计姿态速度和首段", function(check)
    local sim, items = make("apple")
    command(sim, items, -PI / 2, 1)
    steps(sim, 24)
    local record = sim.bodies[1]
    -- 在Sync前留一段尚未采样自然角，覆盖原先漏首段的回归。
    record.node.rotation2D = record.node.rotation2D + 12
    record.body.linearVelocity = Vector2(.4, .2)
    record.body.angularVelocity = 1.3
    local angle, node = record.node.rotation2D, record.node
    local offset = sim:Contacts().rotateOffsets[1]
    items[1].scale = .85
    sim:RememberEvents({{kind = "resize", uid = 1, value = .85}})
    sim:Sync(items)
    local rebuilt, motion = sim.bodies[1], sim.expansion.states[1]
    check(rebuilt.node ~= node and near(rebuilt.node.rotation2D, angle, 1e-4)
        and near(rebuilt.body.linearVelocity.x, .4)
        and near(rebuilt.body.angularVelocity, 1.3), "事件_removed尺寸重建保角度和两种速度")
    check(near(motion.angularTravel, 12 * PI / 180, 1e-4)
        and near(motion.rotateOffset, offset) and #motion.rotations == 1,
        "同步前自然首段未丢，已应用角和剩余任务不断档")
    rebuilt.body.gravityScale = 0
    rebuilt.body.linearDamping, rebuilt.body.angularDamping = 0, 0
    steps(sim, 36)
    check(near(sim:Contacts().rotateOffsets[1], -PI / 2)
        and #motion.rotations == 0, "重建后仅继续剩余0.6秒，不重放或丢失任务")
    local oldTravel = sim:Contacts().angularTravel[1]
    items[1].scale = 1
    sim:Sync(items)
    check(near(sim:Contacts().angularTravel[1], oldTravel), "无resize事件的直接scale重建也保累计")
end)

case("shape转化及remove同uid累计连续且不继承不兼容动作", function(check)
    local sim, items = make("sheep")
    command(sim, items, -PI / 2, 1)
    steps(sim, 12)
    local record = sim.bodies[1]
    record.node.rotation2D = record.node.rotation2D + 15
    local before = sim.expansion:SampleAngle(record)
    local travel, offset = before.angularTravel, before.rotateOffset
    items[1].woolCount = 5
    local oldNode = record.node
    sim:Sync(items)
    check(sim.bodies[1].node ~= oldNode and near(sim:Contacts().angularTravel[1], travel)
        and near(sim:Contacts().rotateOffsets[1], offset), "羊形态重建保自然与强制累计")
    sim:RememberEvents({{kind = "dash", uid = 1, dx = 1, dy = 0, duration = .3}})
    sim:Sync(items)
    check(sim.expansion.states[1].dashRemaining > 0, "旧类型已建立dash状态")
    items[1].id = "apple"
    sim:RememberEvents({{kind = "transform", uid = 1}})
    sim:Sync(items)
    local state = sim.expansion.states[1]
    check(near(state.angularTravel, travel) and near(state.rotateOffset, offset)
        and #state.rotations == 1 and state.dashRemaining == 0 and not state.flight,
        "跨类型只继承累计/剩余强制任务，不继承旧dash/flight")
    local angle = sim.bodies[1].node.rotation2D
    sim:RememberEvents({{kind = "remove", uid = 1}})
    sim:Sync(items)
    check(near(sim.expansion.states[1].angularTravel, travel)
        and near(sim.bodies[1].node.rotation2D, angle, 1e-4), "remove但uid仍在场重建不清累计或角度")
end)

case("respawn及teleport坐标优先且累计不归零", function(check)
    local sim, items = make("apple")
    command(sim, items, -PI / 2, 1)
    steps(sim, 15)
    local offset = sim:Contacts().rotateOffsets[1]
    sim:RememberEvents({{kind = "respawn", uid = 1, x = -.4, y = 5, exact = true},
        {kind = "resize", uid = 1, value = .9}})
    items[1].scale = .9
    sim:Sync(items)
    local x, y = sim:GetPose(1)
    check(near(x, -.4) and near(y, 5) and near(sim:Contacts().rotateOffsets[1], offset),
        "respawn+resize不被旧中心覆盖，累计连续")
    sim:RememberEvents({{kind = "teleport", uid = 1, x = .65, y = 4.3}})
    sim:Sync(items)
    x, y = sim:GetPose(1)
    check(near(x, .65) and near(y, 4.3) and near(sim:Contacts().rotateOffsets[1], offset),
        "teleport使用精确坐标且不清累计")
    sim:Sync(items, true, 29)
    local contacts = sim:Contacts()
    check(contacts.angularTravel[1] == 0 and contacts.rotateOffsets[1] == 0
        and #sim.expansion.states[1].rotations == 0, "reset=true才清回合累计与任务")
end)

case("五段整体持续旋转保持关节与自然平移", function(check)
    local sim, items = make("bacon")
    local record, poses = sim.bodies[1], {}
    local center = record.node.position2D
    for index, part in ipairs(record.parts) do
        local p = part.node.position2D
        poses[index] = {x = p.x - center.x, y = p.y - center.y, angle = part.node.rotation2D}
        part.body.linearVelocity = Vector2(.1, 0)
    end
    command(sim, items, -PI / 2, 1)
    steps(sim, 60)
    local final = record.node.position2D
    local rigid = true
    for index, part in ipairs(record.parts) do
        local p, pose = part.node.position2D, poses[index]
        rigid = rigid and near(p.x - final.x, pose.y, .002)
            and near(p.y - final.y, -pose.x, .002)
            and angleNear(part.node.rotation2D * PI / 180, pose.angle * PI / 180 - PI / 2)
    end
    check(rigid and #record.soft.joints == 4, "每帧五段同角差共同转动，真实关节不重建")
    check(near(final.x - center.x, .1, .002) and near(final.y, center.y, .002),
        "强制角不旋转整物体平移速度，真实自然运动仍积分")
    check(sim:Contacts().angularTravel[1] < .002, "软体强制角也不灌自然角路程")
end)

case("幽灵直立豁免与便便sensor切换累计连续", function(check)
    local ghost, ghostItems = make("ghost")
    command(ghost, ghostItems, -PI / 2, 1)
    steps(ghost, 60)
    check(ghost:Contacts().angles[1] == 0 and ghost:Contacts().rotateOffsets[1] == 0
        and #ghost.expansion.states[1].rotations == 0, "幽灵不转且不积攒补转任务")
    local sim, items = make("poop")
    command(sim, items, -PI / 2)
    local offset = sim:Contacts().rotateOffsets[1]
    sim:Sync(items, false, nil, {ghostPoop = true})
    local record = sim.bodies[1]
    check(record.sensor and record.ghostLike and record.body.fixedRotation
        and record.node.rotation2D == 0 and near(sim:Contacts().rotateOffsets[1], offset),
        "打开便便sensor时直立但累计不清")
    sim:Sync(items, false, nil, {ghostPoop = false})
    check(not sim.bodies[1].sensor and not sim.bodies[1].body.fixedRotation
        and near(sim:Contacts().rotateOffsets[1], offset), "关闭sensor恢复实体且累计连续")
end)

local V = _G["V"]
if V then
    V.atFrame(2, function()
        for _, entry in ipairs(cases) do
            local ok, err = pcall(entry.run, function(condition, message) V.assert(condition, message) end)
            V.assert(ok, "旋转专项完成: " .. entry.name .. (ok and "" or " | " .. tostring(err)))
            clean()
        end
        V.finish()
    end)
end
function Start() print("[MotionRotationValidation] 真实Box2D旋转与重建专项就绪") end
function Stop() clean() end
