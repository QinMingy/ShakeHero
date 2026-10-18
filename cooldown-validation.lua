-- 冷却显示验收：仅由 -validate-test 加载，不参与游戏构建。
local Items = require("Bottle.Items")
local Game = require("Bottle.Game")
local Art = require("Bottle.Art")
local stage = "prepare"
local draws = {prepare = 0, countdown = 0, waiting = 0, triggered = 0, ended = 0}
local grayColors, colorColors = 0, 0
local wrongState, wrongGray = false, false
local grayMode, colorMode = false, false
local originalItem, originalRGBA = Art.Item, nvgRGBA
local fixtureGame

nvgRGBA = function(r, g, b, a)
    if grayMode then
        grayColors = grayColors + 1
        if r ~= g or g ~= b then wrongGray = true end
    elseif colorMode and (r ~= g or g ~= b) then
        colorColors = colorColors + 1
    end
    return originalRGBA(r, g, b, a)
end
Art.Item = function(vg, id, x, y, r, angle, grayed)
    if grayed ~= nil then
        local expected = stage == "countdown" or stage == "triggered"
            or (stage == "waiting" and id ~= "orange")
        if grayed ~= expected then wrongState = true end
        draws[stage] = draws[stage] + 1
    end
    grayMode = grayed == true
    colorMode = id == "orange" and not grayed
    originalItem(vg, id, x, y, r, angle, grayed)
    grayMode, colorMode = false, false
end

local function Screenshot(name)
    local image = Image()
    V.assert(graphics:TakeScreenShot(image), "截取实际画面：" .. name)
    V.assert(image:SavePNG(name .. ".png"), "保存内部验收图：" .. name)
    image:Dispose()
end

V.atFrame(20, function()
    local api = BottleValidationGet()
    local snapshot = Game.New(7):Snapshot()
    snapshot.instances, snapshot.deck, snapshot.drawn = {}, {}, {}
    snapshot.nextUid = 4
    for uid, id in ipairs({"apple", "banana", "orange"}) do
        snapshot.instances[uid] = {uid = uid, id = id, bonus = 0, mult = 1,
            remaining = Items.byId[id].cooldown, location = "bottle", temporary = false}
        snapshot.deck[uid], snapshot.drawn[uid] = uid, uid
    end
    fixtureGame = assert(Game.Restore(snapshot))
    local view, physics = api.GetView(), api.GetPhysics()
    physics:Sync(fixtureGame:BottleItems(), true)
    view:Rebind(fixtureGame)
    -- 只冻结主玩法推进，保留UI、后效和方向校准的真实渲染事件。
    HandleUpdate = function() end
    for uid, record in pairs(physics.bodies) do
        record.node:SetPosition2D((uid - 2) * 1.4, 3.5)
        record.node.rotation2D = 0
    end
end)

V.atFrame(30, function()
    Screenshot("prepare")
    V.assert(fixtureGame:Start(), "测试回合正常开始")
    fixtureGame:Step(.5)
    V.assert(fixtureGame:Get(3).remaining > 0, "冷却计时正常推进")
    stage = "countdown"
    BottleValidationGet().GetView():Update(true)
end)

V.atFrame(40, function()
    Screenshot("countdown")
    -- 只有橘子冷却满且未触底，其他物品仍在计时。
    fixtureGame:Get(3).remaining = 0
    fixtureGame:Step(0, {bottom = {}})
    V.assert(fixtureGame:Get(3).remaining == 0 and fixtureGame.roundScore == 0,
        "橘子冷却满未触底保持就绪且不计分")
    stage = "waiting"
end)

V.atFrame(50, function()
    Screenshot("ready")
    fixtureGame:Step(0, {bottom = {[3] = true}})
    V.assert(fixtureGame.roundScore == 3 and fixtureGame:Get(3).remaining == Items.byId.orange.cooldown,
        "满足触底条件后计分并重置冷却")
    stage = "triggered"
end)

V.atFrame(60, function()
    Screenshot("triggered")
    fixtureGame:Step(9.5)
    V.assert(fixtureGame.phase == "draft" and fixtureGame.elapsed == 10, "10秒回合结束流程不变")
    stage = "ended"
    BottleValidationGet().GetView():Update(true)
end)

V.atFrame(70, function()
    for name, count in pairs(draws) do
        if name == "ended" then
            V.assert(count == 0, "回合结束物品离瓶，不残留冷却灰图")
        else
            V.assert(count > 0, "已绘制状态：" .. name)
        end
    end
    V.assert(not wrongState, "准备与非运行阶段彩色，冷却中置灰，就绪彩色，触发后再次置灰")
    V.assert(grayColors > 0 and not wrongGray, "冷却图案所有填充均为真实灰度")
    V.assert(colorColors > 0, "准备与冷却就绪的橘子图案使用原彩色")
    Art.Item, nvgRGBA = originalItem, originalRGBA
    V.finish()
end)
