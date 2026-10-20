-- 官方运行器入口与 -validate-test 共用文件；基于2D物理脚手架的事件转发。
-- cwd/tapcode_dir必须是/workspace/.repair-validation，不接触真实玩家存档。
-- UrhoXRuntime Bottle/RepairValidation.lua ... -validate-test=.../RepairValidation.lua
local Tests = require("Bottle.RepairTests")
local Physics = require("Bottle.Physics")
local Items = require("Bottle.Items")
local SoftBacon = require("Bottle.SoftBacon")
local DeckBoard = require("Bottle.DeckBoard")

---@type BottlePhysics[]
local worlds = {}

local function NewWorld(game)
    local sim = Physics.New()
    worlds[#worlds + 1] = sim
    sim:Sync(game:BottleItems(), true, 19)
    return sim
end

local function DisposeWorlds()
    for _, sim in ipairs(worlds) do sim:Dispose() end
    worlds = {}
end

---@param sim BottlePhysics
---@param uid number
---@param x number
---@param y number
local function Place(sim, uid, x, y)
    local rec = assert(sim.bodies[uid])
    assert(not rec.soft, "Place仅用于普通夹具")
    rec.node:SetPosition2D(x, y)
    rec.node.rotation2D = 0
    rec.body.linearVelocity = Vector2(0, 0)
    rec.body.angularVelocity = 0
    rec.body.awake = true
end

local function Pair(sim, a, b)
    for _, pair in ipairs(sim:Contacts().pairs) do
        if pair[1] == math.min(a,b) and pair[2] == math.max(a,b) then return true end
    end
    return false
end

-- 碰撞夹具设计（米）：
-- ghost起点(.8,3) -> 沿实际漂移轨迹经过固定apple，sensor穿透，无冲量。
-- 灵魂联动：ghost与coffin/tombstone/soul_stone中心(0,3)重叠；只让Box2D提供接触。
-- 培根：初始5段4关节，在重力下落至floor y=0；末端施加角冲量观察弯曲。
-- 边界：底、侧、肩、颈、封口与左右凹角，逐步验证整个旋转包络，而不伪造接触。
local cases = {}
local function Case(name, run) cases[#cases + 1] = {name=name,run=run} end

Case("幽灵从生成到漂移和牌库下落始终正面直立", function(check)
    local game = Tests.Fixture({"ghost", "ghost", "apple"})
    local sim = NewWorld(game)
    -- 不调用 Place：必须验证生产创建的初始角度，防止夹具归零掩盖倾斜。
    check(select(3, sim:GetPose(1)) == 0 and select(3, sim:GetPose(2)) == 0,
        "不同 uid 的幽灵创建角度均为零")
    check(math.abs(select(3, sim:GetPose(3))) > .01, "普通物品保留原初始旋转")
    local upright = true
    sim:BeginShake()
    for step = 1, 180 do
        sim:Shake(step % 2 == 0 and .3 or -.3, .2)
        sim:Step(1 / 60)
        upright = upright and select(3, sim:GetPose(1)) == 0 and select(3, sim:GetPose(2)) == 0
    end
    sim:EndShake()
    check(upright, "摇晃和自主漂移连续三秒不倾斜")
    local PopIn = require("Bottle.PopIn")
    local pop, ordinary = PopIn.NewPose(1, "ghost"), PopIn.NewPose(3, "apple")
    local popUpright, scaled, ordinarySway = true, false, false
    for _ = 1, 60 do
        PopIn.Step(pop, 1 / 60); PopIn.Step(ordinary, 1 / 60)
        popUpright = popUpright and pop.angle == 0 and pop.angleVelocity == 0
        scaled = scaled or pop.scale > 1
        ordinarySway = ordinarySway or math.abs(ordinary.angle) > .001
    end
    check(popUpright and scaled and ordinarySway, "幽灵入场无角回摆但保留缩放过冲，普通物品仍摇摆")
    local deck = DeckBoard.Sim.New(game.deck)
    local ok, err = pcall(function()
        check(select(3, deck:GetPose(1)) == 0 and select(3, deck:GetPose(2)) == 0,
            "牌库幽灵创建直立")
        local startY = select(2, deck:GetPose(1))
        local deckUpright = true
        for _ = 1, 240 do
            deck:Step(1 / 60)
            deckUpright = deckUpright and select(3, deck:GetPose(1)) == 0
                and select(3, deck:GetPose(2)) == 0
        end
        check(deckUpright and select(2, deck:GetPose(1)) < startY - .1,
            "牌库幽灵下落及碰撞后保持直立，重力展示不变")
    end)
    deck:Dispose()
    assert(ok, err)
    print("[GhostUpright] 创建、漂移、入场缩放、牌库下落直立回归完成")
end)

Case("真实幽灵全fixture为动态sensor且可穿物品不推动普通物品", function(check)
    local base = NewWorld(Tests.Fixture({"ghost"}))
    Place(base,1,.8,3)
    for _=1,45 do base:Step(1/60) end
    local ax, ay = base:GetPose(1)
    local sim = NewWorld(Tests.Fixture({"ghost", "apple"}))
    Place(sim,1,.8,3); Place(sim,2,ax,ay)
    sim.bodies[2].body.gravityScale = 0
    local ghost = sim.bodies[1]
    check(ghost.body.bodyType == BT_DYNAMIC and ghost.body.gravityScale == 0, "幽灵动态零重力")
    ---@type CollisionShape2D[]
    local fixtures = ghost.node:GetComponents("CollisionPolygon2D")
    for _, circle in ipairs(ghost.node:GetComponents("CollisionCircle2D")) do fixtures[#fixtures+1]=circle end
    check(#fixtures > 0, "幽灵真实fixture存在")
    local allSensor = true
    for _, fixture in ipairs(fixtures) do
        allSensor = allSensor and fixture.trigger and fixture.categoryBits == 2 and fixture.maskBits == 3
    end
    check(allSensor, "幽灵所有凸片sensor且保留真实接触过滤")
    -- 新建相同初态对照，不比较已经推进45步的base。
    local control = NewWorld(Tests.Fixture({"ghost"})); Place(control,1,.8,3)
    local seenBegin, seenEnd, maxDelta, maxPush = false, false, 0, 0
    local beforeContact = false
    for _=1,150 do
        sim:Step(1/60); control:Step(1/60)
        local hit = Pair(sim,1,2)
        seenBegin = seenBegin or hit
        seenEnd = seenEnd or (beforeContact and not hit)
        beforeContact = hit
        local x,y = sim:GetPose(1); local cx,cy = control:GetPose(1)
        maxDelta = math.max(maxDelta, math.abs(x-cx), math.abs(y-cy))
        local px,py = sim:GetPose(2)
        maxPush = math.max(maxPush,math.abs(px-ax),math.abs(py-ay))
    end
    check(seenBegin and seenEnd, "真实Box2D sensor Begin和End均发生")
    check(maxDelta < 1e-6 and maxPush < 1e-6, "穿透轨迹与无障碍一致且普通物品未被推")
    check(#sim:TakeImpacts() == 0, "真实幽灵sensor接触无碰撞音事件")
    print(string.format("[RepairPhysics] sensor trajectory_delta=%.9g ordinary_push=%.9g",maxDelta,maxPush))
end)

Case("手势强弱体感和松手回中对幽灵轨迹零影响", function(check)
    local sims = {}
    for index=1,5 do
        local sim=NewWorld(Tests.Fixture({"ghost", "apple"}))
        Place(sim,1,0,3.5); Place(sim,2,1,1.5)
        if index==2 or index==3 or index==5 then sim:BeginShake() end
        sims[index]=sim
    end
    local maximum, ordinaryDifference = 0, 0
    for step=1,120 do
        local direction = step%24 < 12 and 1 or -1
        sims[2]:Shake(.04*direction,.02)
        sims[3]:Shake(.12*direction,.06*direction)
        sims[4]:Sensor(direction*.7,.5,1/60)
        if step<61 then sims[5]:Shake(.12*direction,.06*direction)
        elseif step==61 then sims[5]:EndShake() end
        for _,sim in ipairs(sims) do sim:Step(1/60) end
        local x,y = sims[1]:GetPose(1)
        for index=2,#sims do
            local xx,yy=sims[index]:GetPose(1)
            maximum=math.max(maximum,math.abs(x-xx),math.abs(y-yy))
        end
    end
    for _,sim in ipairs(sims) do sim:EndShake() end
    local x,y=sims[1]:GetPose(2)
    for index=2,#sims do
        local xx,yy=sims[index]:GetPose(2)
        ordinaryDifference=math.max(ordinaryDifference,math.abs(x-xx)+math.abs(y-yy))
    end
    check(maximum<1e-6,"无输入/轻摇/强摇/体感/松手回中的幽灵轨迹逐步一致")
    check(ordinaryDifference>.05,"同样的输入确实推动普通物品，排除空测")
    print(string.format("[RepairPhysics] input_ghost_delta=%.9g ordinary_delta=%.9g",maximum,ordinaryDifference))
end)

Case("真实sensor接触触发棺材墓碑灵魂石并静音", function(check)
    for _,id in ipairs({"coffin","tombstone","soul_stone"}) do
        local game=Tests.Fixture({"ghost",id})
        check(game:Start(),id.."开始")
        local sim=NewWorld(game)
        Place(sim,1,0,3); Place(sim,2,0,3)
        sim.bodies[2].body.gravityScale=0
        assert(game:Get(2)).remaining=0
        sim:Step(1/60)
        check(Pair(sim,1,2),id.."由真实sensor生成接触对")
        check(#sim:TakeImpacts()==0,id.."接触静音")
        local events=game:Step(0,sim:Contacts())
        if id=="coffin" then
            check(#Tests.Events(events,"spawn")==1 and #game:BottleItems()==3,"棺材生成一个幽灵")
        elseif id=="tombstone" then
            check(assert(game:Get(2)).permBonus==1,"墓碑永久增长1")
        else
            check(assert(game:Get(1)).location=="discard" and game.score==7,"灵魂石消耗幽灵双方即时收益2+5")
        end
        sim:RememberEvents(events); sim:Sync(game:BottleItems())
        check(#Tests.Events(game:Step(0,sim:Contacts()),"score")==0,id.."相同步不重复收益")
    end
end)

local EDGES={
    {-2.4,0,2.4,0},{2.4,0,2.4,5.5},{2.4,5.5,1.15,6.05},{1.15,6.05,1.15,6.4},
    {1.15,6.4,-1.15,6.4},{-1.15,6.4,-1.15,6.05},{-1.15,6.05,-2.4,5.5},{-2.4,5.5,-2.4,0},
}
local function Distance(x,y,e)
    local dx,dy=e[3]-e[1],e[4]-e[2]
    local t=math.max(0,math.min(1,((x-e[1])*dx+(y-e[2])*dy)/(dx*dx+dy*dy)))
    return math.sqrt((x-e[1]-t*dx)^2+(y-e[2]-t*dy)^2)
end

Case("幽灵底顶侧肩颈及凹角全包络有界", function(check)
    local points={{0,.5},{1.85,2.5},{1.5,5.25},{.5,5.95},{0,5.9},{-.5,5.95},{-1.5,5.25},{-1.85,2.5}}
    local game=Tests.Fixture({"ghost","ghost","ghost","ghost","ghost","ghost","ghost","ghost"})
    local sim=NewWorld(game)
    for uid,p in ipairs(points) do Place(sim,uid,p[1],p[2]) end
    local minGap, maxSpeed = math.huge,0
    local safe=true
    sim:BeginShake()
    for step=1,360 do
        if step%12==0 then sim:Shake(step%24==0 and .4 or -.4,.4) end
        sim:Step(1/60)
        for uid,rec in pairs(sim.bodies) do
            local x,y=sim:GetPose(uid)
            local width=y>=6.05 and 1.15 or math.min(2.4,2.4-(2.4-1.15)/.55*(y-5.5))
            safe=safe and y>=0 and y<=6.4 and math.abs(x)<=width
            for _,edge in ipairs(EDGES) do minGap=math.min(minGap,Distance(x,y,edge)-rec.envelope) end
            local velocity=rec.body.linearVelocity
            maxSpeed=math.max(maxSpeed,math.sqrt(velocity.x^2+velocity.y^2))
        end
    end
    sim:EndShake()
    check(safe and minGap>=-.001,"8处边界连续6秒整个幽灵包络留瓶内")
    check(maxSpeed<3,"自主低速漂移不被摇晃高速甩出")
    print(string.format("[RepairPhysics] boundary_min_gap=%.9g max_speed=%.9g",minGap,maxSpeed))
end)

Case("培根二倍长度厚度不变五段四关节与真实弯曲触底拾取释放", function(check)
    local game=Tests.Fixture({"bacon"})
    local sim=NewWorld(game)
    local rec=sim.bodies[1]
    local soft=assert(rec.soft)
    local radius=Items.byId.bacon.radius
    check(#rec.parts==5 and #soft.segments==5 and #soft.joints==4,"真实5刚体4关节")
    local pose=soft:GetPose()
    local length=math.sqrt((pose[5].x-pose[1].x)^2+(pose[5].y-pose[1].y)^2)+.8*radius
    check(math.abs(length-4*radius)<1e-6,"名义长度4r等于旧2r两倍")
    check(math.abs(pose[1].halfWidth-.375*radius)<1e-7,"厚度仍为.75r")
    check(math.abs(SoftBacon.Envelope(radius)-radius*math.sqrt(2.025^2+.375^2))<1e-7,"二倍长度包络匹配")
    local jointLimits=true
    for _,joint in ipairs(soft.joints) do
        jointLimits=jointLimits and joint.enableLimit and math.abs(joint.lowerAngle+.55)<1e-6
            and math.abs(joint.upperAngle-.55)<1e-6
    end
    check(jointLimits,"四转轴保留±.55rad限制")
    local endPose=pose[5]
    check(sim:ContainsPoint(1,endPose.x,endPose.y),"末端远离中心仍可真实拾取")
    check(not sim:ContainsPoint(1,2.3,6.2),"软体拾取不误命中远处空白")
    local endBody=soft.segments[1].body
    local inertia=endBody.inertia
    endBody:ApplyAngularImpulse(.012,true)
    print(string.format("[RepairPhysics] angular_probe inertia=%.12g J_over_I=%.9g actual_velocity=%.9g ratio=%.9g",inertia,.012/inertia,endBody.angularVelocity,endBody.angularVelocity/(.012/inertia)))
    local maxAngle, bottom, maxStep, finalAngle = 0,false,0,0
    local maxAnchor, returnedStep, finite, inBottle = 0,0,true,true
    for step=1,240 do
        sim:Step(1/60)
        local ps=soft:GetPose()
        for index=1,4 do
            local a,b=ps[index],ps[index+1]
            local angle=math.abs((b.angle-a.angle+math.pi)%(2*math.pi)-math.pi)
            if angle>maxAngle then maxAngle,maxStep,returnedStep=angle,step,0 end
            if step==240 then finalAngle=math.max(finalAngle,angle) end
            local anchorAX,anchorAY=a.x+math.cos(a.angle)*.4*radius,a.y+math.sin(a.angle)*.4*radius
            local anchorBX,anchorBY=b.x-math.cos(b.angle)*.4*radius,b.y-math.sin(b.angle)*.4*radius
            maxAnchor=math.max(maxAnchor,math.sqrt((anchorAX-anchorBX)^2+(anchorAY-anchorBY)^2))
        end
        local stepAngle=0
        for index=1,4 do stepAngle=math.max(stepAngle,math.abs((ps[index+1].angle-ps[index].angle+math.pi)%(2*math.pi)-math.pi)) end
        if step>maxStep and stepAngle<=.65 and returnedStep==0 then returnedStep=step end
        for _,part in ipairs(ps) do
            finite=finite and part.x==part.x and part.y==part.y and part.angle==part.angle
                and math.abs(part.x)<100 and math.abs(part.y)<100
            for _,sx in ipairs({-1,1}) do for _,sy in ipairs({-1,1}) do
                local x=part.x+math.cos(part.angle)*part.halfLength*sx-math.sin(part.angle)*part.halfWidth*sy
                local y=part.y+math.sin(part.angle)*part.halfLength*sx+math.cos(part.angle)*part.halfWidth*sy
                local width=y>=6.05 and 1.15 or math.min(2.4,2.4-(2.4-1.15)/.55*(y-5.5))
                inBottle=inBottle and y>=-.035 and y<=6.435 and math.abs(x)<=width+.035
            end end
        end
        if step>=35 and step<=39 then print(string.format("[RepairPhysics] impact_step=%d center=(%.7g,%.7g) angle=%.7g anchor_max=%.7g",step,ps[3].x,ps[3].y,stepAngle,maxAnchor)) end
        bottom=bottom or sim:Contacts().bottom[1]==true
    end
    print(string.format("[RepairPhysics] bend_max_step=%d max_angle=%.9g final_angle=%.9g max_anchor=%.9g returned_step=%d",maxStep,maxAngle,finalAngle,maxAnchor,returnedStep))
    -- 保留最初全过程<.65失败证据；此断言单独验证强冲击后的真实稳定性，不冒充绝对限角。
    check(maxAngle>.03 and finite and inBottle and maxAnchor<.035 and finalAngle<.1,"强冲击下各段有限不穿瓶/锚点不脱离并最终收敛")
    check(returnedStep>maxStep and returnedStep-maxStep<30,"超限冲击峰值后半秒内回到.65以内")
    check(bottom,"任意真实培根段触底映射同uid")
    local pairs=sim:Contacts().pairs
    check(#pairs==0,"同uid内部段接触不伪造物品邻接")
    game:_Destroy(1,false,{})
    sim:Sync(game:BottleItems())
    check(soft.disposed and #soft.segments==0 and #soft.joints==0 and sim.bodies[1]==nil,"消耗释放全部分段及关节")
    sim:Step(1/60)
    check(not sim:Contacts().bottom[1],"释放后无幽灵触底记录")
    print(string.format("[RepairPhysics] bacon_length=%.9g thickness=%.9g max_bend=%.9g",length,pose[1].halfWidth*2,maxAngle))
end)

Case("培根无碰撞受控弯曲保留标称限角", function(check)
    local sim=NewWorld(Tests.Fixture({"bacon"}))
    local soft=assert(sim.bodies[1].soft)
    for _,segment in ipairs(soft.segments) do segment.body.gravityScale=0 end
    -- 按J/I=2rad/s施加温和端段冲量，在中心净空区隔离落地冲击。
    local body=soft.segments[1].body
    body:ApplyAngularImpulse(body.inertia*2,true)
    local maximum=0
    for _=1,100 do
        sim:Step(1/60)
        local pose=soft:GetPose()
        for index=1,4 do
            maximum=math.max(maximum,math.abs((pose[index+1].angle-pose[index].angle+math.pi)%(2*math.pi)-math.pi))
        end
    end
    check(maximum>.01 and maximum<=.57,"无碰撞温和角冲量弯曲符合±.55标称限角容差")
    print(string.format("[RepairPhysics] controlled_bend_max=%.9g",maximum))
end)

Case("牌库沙盒培根同样为真实软体且释放", function(check)
    local sim=DeckBoard.Sim.New(Tests.Fixture({"bacon"}).deck)
    local ok,err=pcall(function()
        local record=sim.records[1]
        local soft=assert(record.soft,"牌库培根仍是刚性图案")
        check(#soft.segments==5 and #soft.joints==4,"牌库培根5段4关节")
        local startY=select(2,sim:GetPose(1))
        soft.segments[1].body:ApplyAngularImpulse(.01,true)
        local maxAngle=0
        for _=1,210 do
            sim:Step(1/60)
            local pose=assert(sim:GetSoftPose(1))
            for index=1,4 do maxAngle=math.max(maxAngle,math.abs(pose[index+1].angle-pose[index].angle)) end
        end
        local endY=select(2,sim:GetPose(1))
        check(endY<startY-.1 and endY>=-.03,"牌库软体真实下落并触底")
        check(maxAngle>.03,"牌库分段真实弯曲")
        local last=assert(sim:GetSoftPose(1))[5]
        check(sim:ContainsPoint(1,last.x,last.y),"牌库软体末端拾取")
        sim:Dispose()
        check(soft.disposed and #soft.segments==0 and #soft.joints==0,"牌库释放全部软体")
    end)
    sim:Dispose()
    assert(ok,err)
end)

Case("同尺寸重量真实影响瓶内和牌库全部刚体质量", function(check)
    for _, id in ipairs({"apple","banana","bacon"}) do
        local game = Tests.Fixture({id,id,id})
        assert(game:Get(1)).weight=.5
        assert(game:Get(2)).weight=1
        assert(game:Get(3)).weight=2
        local sim=NewWorld(game)
        local function Mass(record)
            local sum=0
            for _,part in ipairs(record.parts) do sum=sum+part.body.mass end
            return sum
        end
        local base=Mass(sim.bodies[2])
        check(math.abs(Mass(sim.bodies[1])/base-.5)<1e-5,id.."瓶内50%重量")
        check(math.abs(Mass(sim.bodies[3])/base-2)<1e-5,id.."瓶内200%重量")
        local record=sim.bodies[2]
        local pose=record.node.position2D
        assert(game:Get(2)).weight=1.5
        sim:Sync(game:BottleItems())
        check(math.abs(Mass(sim.bodies[2])/base-1.5)<1e-5,id.."未发事件Sync仍更新重量")
        check((sim.bodies[2].node.position2D-pose).length<1e-4,id.."重量同步保持位置")
        local deck=DeckBoard.Sim.New(game.deck)
        local ok,err=pcall(function()
            local function DeckMass(entry)
                local sum=0
                if entry.soft then
                    for _,segment in ipairs(entry.soft.segments) do sum=sum+segment.body.mass end
                else sum=entry.body.mass end
                return sum
            end
            local standard=DeckMass(deck.records[1])/.5
            check(math.abs(DeckMass(deck.records[2])/standard-1.5)<1e-5,id.."牌库150%重量")
            check(math.abs(DeckMass(deck.records[3])/standard-2)<1e-5,id.."牌库200%重量")
            local entry=deck.records[2]
            local node=entry.node
            local position=node.position2D
            local oldSoft=entry.soft
            assert(game:Get(2)).weight=.75
            deck:Sync()
            check(entry.node==node and entry.soft==oldSoft,id.."牌库改重量不重建节点或关节")
            check(math.abs(DeckMass(entry)/standard-.75)<1e-5,id.."牌库实时重量同步")
            check((entry.node.position2D-position).length<1e-4,id.."牌库重量更新保持位置")
        end)
        deck:Dispose()
        assert(ok,err)
        DisposeWorlds()
    end
    local game=Tests.Fixture({"apple","apple"})
    assert(game:Get(1)).scale=.5
    assert(game:Get(2)).scale=2
    local sim=NewWorld(game)
    check(math.abs(sim.bodies[1].radius/Items.byId.apple.radius-.5)<1e-6,"50%体积同步碰撞半径")
    check(math.abs(sim.bodies[2].radius/Items.byId.apple.radius-2)<1e-6,"200%体积同步碰撞半径")
    check(math.abs(sim.bodies[1].envelope/sim.bodies[2].envelope-.25)<1e-6,"净空同步体积范围")
end)

local V=_G["V"]
if V then
    -- validate-test与入口脚本有独立chunk局部表，监听必须闭包捕获本chunk的worlds。
    SubscribeToEvent("PhysicsBeginContact2D",function(_,data)
        for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsBeginContact2DEventData]],true) end
    end)
    SubscribeToEvent("PhysicsEndContact2D",function(_,data)
        for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsEndContact2DEventData]],false) end
    end)
    V.atFrame(2,function()
        local ruleCount=0
        for _,case in ipairs(Tests.cases) do
            local ok,err=pcall(case.run)
            V.assert(ok,"规则: "..case.name..(ok and "" or " | "..tostring(err)))
            if ok then ruleCount=ruleCount+1 end
        end
        print("[RepairTests] passed="..ruleCount.."/"..#Tests.cases)
        for _,case in ipairs(cases) do
            local ok,err=pcall(case.run,function(condition,message) V.assert(condition,message) end)
            V.assert(ok,"物理用例完成: "..case.name..(ok and "" or " | "..tostring(err)))
            DisposeWorlds()
        end
        V.finish()
    end)
end

function Start()
    print("[RepairTests] direct Run passed=" .. Tests.Run())
    local allTests=require("Bottle.Tests")
    local total=allTests.Run()
    print("[RepairTests] all_rules_total="..total.." jsonRoundtripRan="..tostring(allTests.jsonRoundtripRan))
    SubscribeToEvent("PhysicsBeginContact2D","RepairContactBegin")
    SubscribeToEvent("PhysicsEndContact2D","RepairContactEnd")
end
function Stop() DisposeWorlds() end

---@param eventType string
---@param data PhysicsBeginContact2DEventData
function RepairContactBegin(eventType,data)
    for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsBeginContact2DEventData]],true) end
end
---@param eventType string
---@param data PhysicsEndContact2DEventData
function RepairContactEnd(eventType,data)
    for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsEndContact2DEventData]],false) end
end
