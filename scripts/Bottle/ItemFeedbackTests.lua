-- 重点验证真实路径、瞬移断点、容量/大dt、表现与规则及绘制周期隔离。
local Feedback = require("Bottle.ItemFeedback")
local Consume = require("Bottle.ConsumeFeedback")
local Smoke = require("Bottle.ConsumeSmoke")
local T = {}
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases+1] = {name=name, run=run} end

---@return any
local function Physics()
    return {bodies={[1]={kind="star"}}, poses={[1]={0,5}},
        GetPose=function(self, uid)
            assert(self.bodies[uid], "缺失物体不得借用默认原点")
            local pose = self.poses[uid]
            return pose[1], pose[2], 0, .3
        end}
end

---@param extra table?
---@return any
local function Event(extra)
    local result = {kind="itemFeedback", action="jelly", uid=2, id="jelly",
        targetUid=3, targetId="apple", x=0, y=2, toX=.5, toY=2}
    for key, value in pairs(extra or {}) do result[key] = value end
    return result
end

Test("星星按真实下落路径插值，静止和向上时不喷粒子", function()
    local fx, physics = Feedback.New(), Physics()
    fx:Update(.016, physics)
    fx:Update(.016, physics)
    assert(#fx.particles == 0)
    physics.poses[1] = {.2,4.6}
    fx:Update(.016, physics)
    assert(#fx.particles >= 4 and #fx.particles <= 8)
    for _, particle in ipairs(fx.particles) do
        assert(particle.ownerUid == 1 and particle.behind)
        assert(particle.x >= -.03 and particle.x <= .23 and particle.y <= 5.03 and particle.y >= 4.57)
    end
    local count = #fx.particles
    physics.poses[1] = {.2,4.9}
    fx:Update(.016, physics)
    assert(#fx.particles == count, "向上移动不制造下落拖尾")
end)

Test("星星同uid顶部重生清除旧基线，不连接整瓶", function()
    local fx, physics = Feedback.New(), Physics()
    fx:Update(.016, physics)
    physics.poses[1] = {0,4.7}
    fx:Update(.016, physics)
    assert(#fx.particles > 0)
    local tail = #fx.particles
    fx:Events({{kind="respawn", uid=1, id="star", x=.1, y=6}}, physics)
    assert(fx.stars[1] == nil and #fx.particles == tail)
    physics.poses[1] = {.1,6}
    fx:Update(.016, physics)
    assert(#fx.particles == tail, "旧拖尾自然消散，不产生跨瓶连线")
    physics.poses[1] = {.1,5.7}
    fx:Update(.016, physics)
    for _, particle in ipairs(fx.particles) do
        if particle.age == 0 then assert(particle.y > 5.65) end
    end
end)

Test("无事件的长距离跳变、大dt不补发；刚体离场清理", function()
    local fx, physics = Feedback.New(), Physics()
    fx:Update(.016, physics)
    physics.poses[1] = {0,1}
    fx:Update(.016, physics)
    assert(#fx.particles == 0)
    physics.poses[1] = {0,.7}
    fx:Update(4, physics)
    assert(#fx.particles == 0, "大dt不累计历史喷发")
    physics.poses[1] = {0,.4}
    fx:Update(.016, physics)
    assert(#fx.particles > 0)
    physics.bodies[1] = nil
    fx:Update(.016, physics)
    assert(next(fx.stars) == nil and #fx.particles == 0)
end)

Test("仅star刚体参与拖尾，丢失物理系统不留陈旧发射器", function()
    local fx, physics = Feedback.New(), Physics()
    physics.bodies[1].kind = "apple"
    fx:Update(.016, physics)
    physics.poses[1] = {0,4.6}
    fx:Update(.016, physics)
    assert(next(fx.stars) == nil and #fx.particles == 0)
    physics.bodies[1].kind = "star"
    fx:Update(.016, physics)
    physics.poses[1] = {0,4.2}
    fx:Update(.016, physics)
    fx:Update(.016, nil)
    assert(next(fx.stars) == nil and #fx.particles == 0)
end)

Test("密集物品与同帧多事件均有总量上限", function()
    local fx, physics = Feedback.New(), Physics()
    for uid = 2, 100 do physics.bodies[uid] = {kind="star"}; physics.poses[uid] = {uid*.01,5} end
    fx:Update(.016, physics)
    for frame = 1, 30 do
        for uid = 1, 100 do physics.poses[uid] = {uid*.01,5-frame*.12} end
        local before = #fx.particles
        fx:Update(.016, physics)
        assert(#fx.particles <= Feedback.MAX_PARTICLES)
        assert(#fx.particles-before <= Feedback.STAR_STEP_LIMIT)
    end
    local events = {}
    for index = 1, 500 do events[index] = Event({action="produce", id="cloud", count=99}) end
    fx:Events(events, physics)
    assert(#fx.particles <= Feedback.MAX_PARTICLES and #fx.effects <= Feedback.MAX_EFFECTS)
end)

Test("动作事件去重、未知动作与缺失位置静默、复位可重播", function()
    local fx, physics = Feedback.New(), Physics()
    local event = Event()
    fx:Events({event,event}, physics)
    assert(#fx.effects == 1)
    fx:Events({Event({action="unknown"}), {kind="itemFeedback",action="cut",uid=999,id="knife"}}, physics)
    assert(#fx.effects == 1)
    fx:Reset()
    fx:Events({event}, physics)
    assert(#fx.effects == 1 and #fx.particles == 0)
end)

Test("密集星星轮流分配预算，每颗下落星星都能留下拖尾", function()
    local fx, physics, seen = Feedback.New(), Physics(), {}
    for uid = 1, 20 do
        physics.bodies[uid], physics.poses[uid] = {kind="star"}, {uid*.01,6}
    end
    fx:Update(.016, physics)
    for frame = 1, 12 do
        for uid = 1, 20 do physics.poses[uid][2] = 6-frame*.35 end
        fx:Update(.016, physics)
        local emitted = 0
        for _, particle in ipairs(fx.particles) do
            if particle.ownerUid and particle.age == 0 then
                seen[particle.ownerUid] = true
                emitted = emitted + 1
            end
        end
        assert(emitted <= Feedback.STAR_STEP_LIMIT)
    end
    for uid = 1, 20 do assert(seen[uid], "下落星星不得被预算永久饿死："..uid) end
end)

Test("果冻及生产仅局部弹性缩放，结束恢复1且不改变物理", function()
    local fx, physics = Feedback.New(), Physics()
    fx:Events({Event()}, physics)
    fx:Update(.045, physics)
    local sx, sy = fx:Transform(2)
    assert(sx > 1 and sy < 1 and physics.poses[1][2] == 5)
    local ox, oy = fx:Transform(99)
    assert(ox == 1 and oy == 1)
    fx:Update(1, physics)
    sx, sy = fx:Transform(2)
    assert(sx == 1 and sy == 1 and #fx.effects == 0)
end)

Test("切水果使用切前身份配色与目标位置，学生跟随新职业", function()
    local fx, physics = Feedback.New(), Physics()
    physics.bodies[2], physics.poses[2] = {kind="police"}, {.6,3}
    fx:Events({Event({action="cut", id="knife", targetId="orange", toX=1, toY=2}),
        Event({action="grow", id="student", targetId="police"})}, physics)
    assert(#fx.particles == 6 and fx.particles[1].color[1] == 247)
    assert(fx.particles[1].x == 1 and fx.particles[1].y == 2)
    fx:Update(.016, physics)
    assert(fx.effects[2].x == .6 and fx.effects[2].y == 3)
end)

Test("小偷实际负收益才出现价值迁移，正收益只产生友好增益点", function()
    local fx = Feedback.New()
    fx:Events({Event({action="steal", id="thief", value=-1}),
        Event({action="steal", id="thief", value=2}),
        Event({action="steal", id="thief", value=0})})
    assert(#fx.effects == 2 and #fx.particles == 4)
    for _, particle in ipairs(fx.particles) do
        assert(particle.x == .5 and particle.y == 2 and particle.color[2] == 224)
    end
end)

Test("偷钱金币飞行时至少半个小偷大，并随当前体型缩放", function()
    local globals = {"nvgSave","nvgRestore","nvgShapeAntiAlias","nvgBeginPath","nvgRect","nvgFillColor","nvgRGBA","nvgFill"}
    local old, oldCoin, drawn = {}, package.loaded["Bottle.CoinIcon"], 0
    for _, name in ipairs(globals) do old[name] = rawget(_G,name); _G[name] = function() end end
    package.loaded["Bottle.CoinIcon"] = {Draw=function(_,_,_,radius) drawn = radius end}
    -- 原生require有独立缓存：替换实际模块方法，不能只覆盖标准Lua的package.loaded。
    local coin = require("Bottle.CoinIcon")
    local oldDraw = coin.Draw
    coin.Draw = package.loaded["Bottle.CoinIcon"].Draw
    local ok, err = pcall(function()
        local fx, physics, ppu = Feedback.New(), Physics(), 80
        physics.bodies[2], physics.poses[2] = {kind="thief",radius=.8}, {0,2}
        fx:Events({Event({action="steal",id="thief",value=-1})}, physics)
        for _, radius in ipairs({.8,1.1,.5}) do
            physics.bodies[2].radius = radius
            fx:Update(.12, physics)
            drawn = 0
            fx:RenderFront({},100,700,ppu)
            assert(drawn*2 >= radius*ppu, "飞行主体金币不得小于小偷直径的一半")
        end
    end)
    coin.Draw = oldDraw
    package.loaded["Bottle.CoinIcon"] = oldCoin
    for _, name in ipairs(globals) do _G[name] = old[name] end
    assert(ok, err)
end)

Test("四种生产者明显压扁再回弹，动作完成恢复原尺寸", function()
    for _, id in ipairs({"fruit_tree","cloud","chick","coin_machine"}) do
        local fx = Feedback.New()
        fx:Events({Event({action="produce",id=id})})
        fx:Update(.08)
        local sx, sy = fx:Transform(2)
        assert(sx >= 1.2 and sy <= .8, id.."生产时需要明显蓄力")
        fx:Update(.25)
        sx, sy = fx:Transform(2)
        assert(sx < 1 and sy > 1, id.."压扁后需要纵向回弹")
        fx:Update(1)
        sx, sy = fx:Transform(2)
        assert(sx == 1 and sy == 1)
    end
end)

Test("外观独立确定，不调用全局玩法随机数", function()
    local random = math.random
    local ok, err = pcall(function()
        math.random = function() error("不得使用全局RNG") end
        local a, b = Feedback.New(), Feedback.New()
        local events = {Event({action="produce", id="fruit_tree"})}
        a:Events(events); b:Events(events)
        for index, p in ipairs(a.particles) do
            local q = b.particles[index]
            assert(p.vx == q.vx and p.vy == q.vy and p.life == q.life)
        end
    end)
    math.random = random
    assert(ok, err)
end)

Test("绘制只读；杀手有红交叉刀光，警察只有原有灰烟", function()
    local globals = {"nvgSave","nvgRestore","nvgShapeAntiAlias","nvgBeginPath","nvgRect","nvgFillColor","nvgRGBA","nvgFill"}
    local old, oldCoin, red, white = {}, package.loaded["Bottle.CoinIcon"], 0, 0
    package.loaded["Bottle.CoinIcon"] = {Draw=function() end}
    local coin = require("Bottle.CoinIcon")
    local oldDraw = coin.Draw
    coin.Draw = package.loaded["Bottle.CoinIcon"].Draw
    for _, name in ipairs(globals) do old[name] = rawget(_G,name); _G[name] = function() end end
    _G.nvgRGBA = function(r,g,b,a)
        if r >= 180 and g < 100 and b < 100 then red = red+1 end
        if r == 255 and g == 255 and b == 255 then white = white+1 end
        return {r,g,b,a}
    end
    local ok, err = pcall(function()
        local fx = Feedback.New()
        for _, row in ipairs({{"cut","knife"},{"jelly","jelly"},{"grow","student"},
            {"produce","fruit_tree"},{"produce","cloud"},{"produce","chick"},
            {"produce","coin_machine"},{"steal","thief"}}) do
            fx:Events({Event({action=row[1],id=row[2],value=-1})})
        end
        fx:Update(.07)
        local age, serial, count = fx.effects[1].age, fx.serial, #fx.particles
        fx:RenderBehind({},100,700,80); fx:RenderFront({},100,700,80)
        fx:RenderFront({},100,700,80)
        assert(fx.effects[1].age == age and fx.serial == serial and #fx.particles == count)
        assert(white > 0, "学生纯白烟团已绘制")
        local consumed = Consume.New()
        assert(consumed:CapturePose({kind="consume",uid=2,id="student",reason="eliminate",
            consumerUid=3,consumerId="killer"},0,2,0))
        local pose = consumed.flashes[1]
        assert(pose.consumerId == "killer" and not pose.consumerUid and pose.animation == "smoke")
        pose.age = .12
        red = 0
        Smoke.Render({},pose,100,700,80)
        assert(red == 2)
        pose.consumerId = "police"
        Smoke.Render({},pose,100,700,80)
        assert(red == 2, "警察不得出现杀手刀光")
    end)
    coin.Draw = oldDraw
    package.loaded["Bottle.CoinIcon"] = oldCoin
    for _, name in ipairs(globals) do _G[name] = old[name] end
    assert(ok, err)
end)

---@return integer
function T.Run()
    for _, case in ipairs(cases) do
        local ok, err = pcall(case.run)
        assert(ok, "Bottle.ItemFeedbackTests ["..case.name.."] "..tostring(err))
    end
    return #cases
end

return T
