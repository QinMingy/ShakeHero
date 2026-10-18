-- 基于2D物理脚手架的隔离真实Box2D专项，不读写玩家存档、不推进游戏收益。
-- 用法：以本文件作入口及validate-test；cwd/tapcode_dir使用独立验收目录。
local Physics = require("Bottle.Physics")
local Items = require("Bottle.Items")
local Shapes = require("Bottle.Shapes")
local Art = require("Bottle.Art")
---@type BottlePhysics[]
local worlds = {}
local IDS = {"chick","sheep","pig","calf","grass","hay","poop","golden_poop",
    "diamond_poop","rainbow_poop","gecko","cactus","abacus","bodyguard","chicken_keeper",
    "splitter","discus_athlete","discus","compass","jelly","wool","sweater",
    "spinning_top","windmill","gear","roulette","removal_coin"}

local function make(ids)
    local sim = Physics.New()
    worlds[#worlds + 1] = sim
    local items = {}
    for uid, id in ipairs(ids) do
        items[#items + 1] = {uid=uid,id=id,location="bottle",scale=1,weight=1}
    end
    sim:Sync(items, true, 337)
    return sim, items
end
local function clean()
    for _, sim in ipairs(worlds) do sim:Dispose() end
    worlds = {}
end
local function place(sim, uid, x, y)
    local rec = assert(sim.bodies[uid])
    assert(not rec.soft)
    rec.node:SetPosition2D(x,y)
    rec.node.rotation2D = 0
    rec.body.linearVelocity = Vector2(0,0)
    rec.body.angularVelocity = 0
    rec.body.awake = true
end
local function pair(sim,a,b)
    for _,p in ipairs(sim:Contacts().pairs) do
        if p[1]==math.min(a,b) and p[2]==math.max(a,b) then return true end
    end
    return false
end
local cases = {}
local function case(name, run) cases[#cases+1]={name=name,run=run} end

-- 夹具示意：独立凸片/真圆在中央自由下落；凹口只由分片表示，不交给Box2D凹多边形。
case("新增图案与全部凸片及真圆轮廓合法", function(check)
    local sim = make(IDS)
    local fingerprints = {}
    for uid,id in ipairs(IDS) do
        check(Art.HasSprite(id), id.."有专用图案")
        local rec=assert(sim.bodies[uid])
        local shape=id=="sheep" and Shapes.Variant(id,0) or Items.byId[id].shape
        -- 移除币使用内置完整圆；其余新增图案使用显式专用轮廓。
        local profile=assert(Shapes.profiles[shape] or (shape=="circle" and {circles={{x=8,y=8,radius=8}}}))
        local polygons, circles = profile.polygons or {}, profile.circles or {}
        check(#polygons+#circles>0,id.."至少有一个凸片或真圆轮廓")
        check(rec.shape==shape and #rec.shapes==#polygons+#circles,id.."使用专用真实fixture")
        check(rec.body.mass>0 and rec.body.mass<math.huge,id.."质量有限正数")
        for index,polygon in ipairs(polygons) do
            local convex,area=true,0
            local n=#polygon//2
            for v=1,n do
                local j=v%n+1
                local k=j%n+1
                local ax,ay=polygon[v*2-1],polygon[v*2]
                local bx,by=polygon[j*2-1],polygon[j*2]
                local cx,cy=polygon[k*2-1],polygon[k*2]
                if (bx-ax)*(cy-by)-(by-ay)*(cx-bx)<-1e-8 then convex=false end
                area=area+ax*by-ay*bx
            end
            check(n>=3 and n<=8 and area>0 and convex,id.."凸片"..index.."为正绕序凸片")
        end
        for index,circle in ipairs(circles) do
            local finite=circle.x==circle.x and circle.y==circle.y and circle.radius==circle.radius
                and math.abs(circle.x)<math.huge and math.abs(circle.y)<math.huge
                and circle.radius>0 and circle.radius<math.huge
            check(finite,id.."真圆"..index.."圆心及半径有限且半径为正")
            check(finite and math.abs(circle.x-circle.radius)<math.huge
                and math.abs(circle.x+circle.radius)<math.huge
                and math.abs(circle.y-circle.radius)<math.huge
                and math.abs(circle.y+circle.radius)<math.huge,id.."真圆"..index.."边界有限")
            local fixture=assert(rec.shapes[#polygons+index]) --[[@as CollisionCircle2D]]
            local radius=Items.byId[id].radius
            check(fixture:GetTypeName()=="CollisionCircle2D",id.."真圆使用实际CollisionCircle2D")
            check(math.abs(fixture.radius-circle.radius*radius/8)<1e-6
                and math.abs(fixture.center.x-(circle.x-8)*radius/8)<1e-6
                and math.abs(fixture.center.y-(8-circle.y)*radius/8)<1e-6,
                id.."真圆"..index.."实际半径和圆心匹配像素转米轮廓")
        end
        local colors=Art.ItemColors(id)
        local chunks={}
        for _,color in ipairs(colors) do chunks[#chunks+1]=table.concat(color,",") end
        table.sort(chunks)
        fingerprints[id]=table.concat(chunks,";")
    end
    check(Art.HasSprite("juice") and Art.HasSprite("ghost") and Art.HasSprite("die_d6_6"),"既有果汁幽灵骰面图案保留")
    check(fingerprints.poop~=fingerprints.golden_poop and fingerprints.diamond_poop~=fingerprints.rainbow_poop,
        "四类便便独立色纹")
end)

-- 夹具：飞盘(-1.2,3)->(1.2,3)，静止苹果(0,3.45)；实际sensor重叠不推动。
case("飞盘动态sensor穿透且路径真实弧线和路程", function(check)
    local sim,items=make({"discus","apple"})
    place(sim,1,-1.2,3);place(sim,2,0,3.45)
    sim.bodies[2].body.gravityScale=0
    local disc=sim.bodies[1]
    check(disc.body.bodyType==BT_DYNAMIC and disc.body.gravityScale==0,"飞盘动态零重力")
    local sensors=true
    for _,shape in ipairs(disc.shapes) do sensors=sensors and shape.trigger and shape.maskBits==3 end
    check(sensors,"飞盘全部fixture为sensor并保留物品/墙过滤")
    sim:RememberEvents({{kind="flight",uid=1,x=-1.2,y=3,toX=1.2,toY=3,duration=1}})
    sim:Sync(items)
    local x,y=sim:GetPose(1)
    local distance,maxY,hit,ended=0,y,false,false
    for _=1,75 do
        sim:Shake(.08,.08);sim:Step(1/60)
        local xx,yy=sim:GetPose(1)
        distance=distance+math.sqrt((xx-x)^2+(yy-y)^2);x,y=xx,yy
        maxY=math.max(maxY,y)
        hit=hit or pair(sim,1,2)
        ended=ended or sim:Contacts().flightArrived[1]==true
    end
    local ax,ay=sim:GetPose(2)
    -- 苹果不受摇晃测试单独隔离，受控飞盘路径则应不受输入改变。
    check(maxY>3.25 and distance>2.4,"弧线高于直线且累计真实路程大于弦长")
    check(math.abs(x-1.2)<.001 and math.abs(y-3)<.001 and ended,"飞行到终点并反馈到达")
    check(hit,"穿透仍生成真实Box2D接触")
    check(ax==ax and ay==ay,"普通物品状态有限")
    local control=make({"discus","apple"})
    place(control,1,-1.2,3);place(control,2,0,3.45);control.bodies[2].body.gravityScale=0
    control:RememberEvents({{kind="flight",uid=1,toX=1.2,toY=3,duration=1}})
    local seen,was=false,false
    for _=1,90 do
        control:Step(1/60)
        local touching=pair(control,1,2)
        seen=seen or touching
        was=was or (seen and not touching)
    end
    local px,py=control:GetPose(2)
    check(seen and was and math.abs(px)<1e-7 and math.abs(py-3.45)<1e-7,"真实Begin/End且sensor不推动苹果")
    check(#control:TakeImpacts()==0,"穿透不产生碰撞音")
end)

case("飞盘命中事实与精确闪回清旧接触", function(check)
    local sim,items=make({"discus","bodyguard"})
    place(sim,1,-1.2,3);place(sim,2,1.1,3)
    sim.bodies[2].body.gravityScale=0
    sim:RememberEvents({{kind="flight",uid=1,targetUid=2,toX=1.1,toY=3,duration=.8}})
    local hit=false
    for _=1,80 do
        sim:Step(1/60)
        local contacts=sim:Contacts()
        if contacts.flightHits[1]==2 then
            hit=pair(sim,1,2);break
        end
    end
    check(hit,"flightHits仅由目标真实接触提供")
    sim:RememberEvents({{kind="teleport",uid=1,x=-.63,y=2.17}});sim:Sync(items)
    local x,y=sim:GetPose(1)
    local contacts=sim:Contacts()
    check(math.abs(x+.63)<1e-6 and math.abs(y-2.17)<1e-6,"flash使用精确坐标而非瓶顶/近源搜索")
    check(not contacts.flightArrived[1] and not contacts.flightHits[1] and not pair(sim,1,2),"闪回清除旧命中与旧接触")
end)

-- 夹具：壁虎触左右/肩/颈时side真；触floor/top时只有对应底顶和wall。
case("side准确分类与壁虎anchor稳定固定及重入解除", function(check)
    local sim,items=make({"gecko","apple"})
    place(sim,1,2.15,3);place(sim,2,0,1)
    sim.bodies[1].body.gravityScale=0
    sim.bodies[1].body.linearVelocity=Vector2(2,0)
    local side=false
    for _=1,30 do sim:Step(1/60);side=side or sim:Contacts().side[1]==true end
    check(side,"真实左右侧壁接触映射side")
    local x,y=sim:GetPose(1)
    sim:RememberEvents({{kind="anchor",uid=1,x=x,y=y}});sim:Sync(items)
    check(sim.bodies[1].body.bodyType==BT_KINEMATIC,"anchor改为kinematic")
    for _=1,90 do sim:Shake(.4,.4);sim:Step(1/60) end
    local xx,yy=sim:GetPose(1)
    check(math.abs(xx-x)<1e-6 and math.abs(yy-y)<1e-6,"重力和摇瓶不改变锚定位置")
    sim:Sync(items,true,19)
    check(sim.bodies[1].body.bodyType==BT_DYNAMIC,"重新入瓶恢复动态")
    place(sim,1,0,.15)
    sim.bodies[1].body.gravityScale=0
    for _=1,5 do sim:Step(1/60) end
    local contacts=sim:Contacts()
    check(contacts.bottom[1] and contacts.wall[1] and not contacts.side[1],"瓶底不属于side")
    place(sim,1,0,6.28)
    for _=1,5 do sim:Step(1/60) end
    contacts=sim:Contacts()
    check(contacts.top[1] and contacts.wall[1] and not contacts.side[1],"瓶顶不属于side")
end)

case("全场顺时针90包含培根五段且排除指南针强制角路程", function(check)
    local sim,items=make({"bacon","ghost","compass","apple"})
    local bacon=sim.bodies[1]
    local center=bacon.node.position2D
    local before={}
    for i,part in ipairs(bacon.parts) do
        local p=part.node.position2D
        before[i]={x=p.x-center.x,y=p.y-center.y,angle=part.node.rotation2D}
    end
    local cx,cy,angle=sim:GetPose(3)
    local travel=sim:Contacts().angularTravel[3]
    local Game=require("Bottle.Game")
    local Rules=require("Bottle.ExpansionEffects")
    local ruleGame=Game.New(337) --[[@as any]]
    ruleGame._instances,ruleGame.deck,ruleGame.discard,ruleGame.drawn={},{},{},{}
    ruleGame._nextUid=1
    for _,id in ipairs({"bacon","ghost","compass","apple"}) do
        local item=ruleGame:_Create(id)
        item.location="bottle"
        ruleGame.drawn[#ruleGame.drawn+1]=item.uid
    end
    local compassItem=assert(ruleGame:Get(3))
    compassItem.compassProgress=math.pi*2
    local rotationEvents={}
    assert(Rules.Apply(ruleGame,compassItem,sim:Contacts(),rotationEvents))
    check(#rotationEvents==3,"真实指南针为非幽灵每件发一条rotate")
    sim:RememberEvents(rotationEvents);sim:Sync(items)
    local rigid=true
    for i,part in ipairs(bacon.parts) do
        local p=part.node.position2D
        rigid=rigid and math.abs(p.x-center.x-before[i].y)<1e-5
            and math.abs(p.y-center.y+before[i].x)<1e-5
            and math.abs(((part.node.rotation2D-before[i].angle+90+180)%360)-180)<1e-4
    end
    check(rigid and #bacon.soft.joints==4,"五段位置与角度整体刚性旋转且关节保留")
    local x,y,a=sim:GetPose(3)
    check(math.abs(x-cx)<1e-6 and math.abs(y-cy)<1e-6
        and math.abs((a-angle+math.pi/2+math.pi)%(2*math.pi)-math.pi)<1e-5,"指南针原地顺时针90")
    local contacts=sim:Contacts()
    check(contacts.angularTravel[3]==travel and math.abs(contacts.rotateOffsets[3]+math.pi/2)<1e-8,"强制旋转不累计自然角路程")
    check(select(3,sim:GetPose(2))==0 and sim.bodies[2].body.fixedRotation,"幽灵仍直立锁转")
    local compass=sim.bodies[3]
    compass.body.gravityScale=0;compass.body.angularDamping=0;compass.body.angularVelocity=3
    for _=1,30 do sim:Step(1/60) end
    check(sim:Contacts().angularTravel[3]>1,"真实自然转动仍累计")
    -- 无关uid不可被单条目标rotate连带旋转。
    local appleAngle=select(3,sim:GetPose(4))
    sim:RememberEvents({{kind="rotate",uid=3,delta=-math.pi/2}});sim:Sync(items)
    check(math.abs(select(3,sim:GetPose(4))-appleAngle)<1e-6,"单条rotate只作用目标uid")
end)

case("冲量弹开与小牛短冲刺遵循实体CCD", function(check)
    local sim,items=make({"apple","jelly","calf"})
    place(sim,1,0,3);place(sim,2,-1,3);place(sim,3,-1.5,4)
    for _,record in pairs(sim.bodies) do record.body.gravityScale=0 end
    local before=sim.bodies[1].body.linearVelocity
    sim:RememberEvents({{kind="impulse",uid=1,sourceUid=2,dx=1,dy=0,strength=3},
        {kind="dash",uid=3,dx=1,dy=0,duration=.35}});sim:Sync(items)
    check(math.abs(sim.bodies[1].body.linearVelocity.x-before.x-3)<1e-5,"方向冲量产生3米每秒速度增量")
    for _=1,21 do sim:Step(1/60) end
    local x,y=sim:GetPose(3)
    check(x>-.3 and x<.1 and math.abs(y-4)<.01,"0.35秒短冲刺约1.4米，非3秒")
    check(sim.expansion.states[3].dashRemaining<1e-7,"冲刺到期停止主动速度覆盖")
    sim:RememberEvents({{kind="dash",uid=3,dx=1,dy=0,duration=.35}})
    for _=1,90 do sim:Step(1/60) end
    check(select(1,sim:GetPose(3))<2.4,"实体短冲刺不会穿出瓶壁")
end)

case("独立飞盘匀速自动移动与肩颈侧壁分类", function(check)
    local sim=make({"discus"})
    place(sim,1,-1,3)
    for _=1,12 do sim:Step(1/60) end
    local x,y=sim:GetPose(1)
    check(math.abs(x+.4)<.002 and math.abs(y-3)<.002,"独立飞盘自动3米每秒直飞，非幽灵流场")
    check(not sim:Contacts().flightArrived[1],"独立飞盘不冒充运动员飞行到达")
    for _,point in ipairs({{1.8,5.8},{-1.8,5.8},{1.1,6.18},{-1.1,6.18}}) do
        local wall=make({"gecko"})
        place(wall,1,point[1],point[2])
        wall.bodies[1].body.gravityScale=0
        local side=false
        for _=1,5 do wall:Step(1/60);side=side or wall:Contacts().side[1]==true end
        check(side,"肩颈真实接触属于side："..point[1]..","..point[2])
    end
end)

case("contact回调事件只排队并在世界解锁后生效", function(check)
    local sim,items=make({"gecko"})
    local record=sim.bodies[1]
    sim._updating=true
    sim:RememberEvents({{kind="anchor",uid=1}})
    sim:Sync(items)
    check(record.body.bodyType==BT_DYNAMIC and #sim.expansion.pending==1,"锁定世界期间不改原生body")
    sim._updating=false
    sim:Step(0)
    check(record.body.bodyType==BT_KINEMATIC and #sim.expansion.pending==0,"零时间安全屏障执行事件")
end)

case("气球密度35%及原有重量幽灵软体回归", function(check)
    local sim,items=make({"balloon","apple","bacon","ghost"})
    local balloon=sim.bodies[1]
    check(balloon.weight==1 and math.abs(balloon.shapes[1].density-.35)<1e-6
        and balloon.body.gravityScale==1,"公开weight100%，气球密度35%而非改重力")
    local mass=balloon.body.mass
    items[1].weight=2;items[2].weight=.5;items[3].weight=2
    local node,soft=balloon.node,sim.bodies[3].soft
    sim:Sync(items)
    check(balloon.node==node and math.abs(balloon.body.mass/mass-2)<1e-6,"气球重量更新沿基准不重复相乘")
    check(sim.bodies[3].soft==soft and #soft.segments==5 and #soft.joints==4,"重量更新保留培根五段四关节")
    local correct=true
    for _,segment in ipairs(soft.segments) do correct=correct and math.abs(segment.shape.density-segment.baseDensity*2)<1e-6 end
    check(correct and math.abs(sim.bodies[2].shapes[1].density-.5)<1e-6,"普通与全部软体段密度口径不变")
    local ghost=sim.bodies[4]
    check(ghost.body.bodyType==BT_DYNAMIC and ghost.body.gravityScale==0 and ghost.body.fixedRotation,
        "幽灵保持动态sensor零重力锁转")
    local all=true
    for _,shape in ipairs(ghost.shapes) do all=all and shape.trigger end
    check(all and select(3,sim:GetPose(4))==0,"幽灵全部sensor且初始直立")
end)

case("小羊零一五档真实轮廓和强摇脉冲", function(check)
    local sim,items=make({"sheep","wool"})
    place(sim,1,0,3)
    local rec=sim.bodies[1]
    check(rec.shape=="sheep_0" and Art.HasSprite("sheep_0") and Art.HasSprite("sheep_5"),"零羊毛瘦羊与胖羊有独立图案")
    local x,y=sim:GetPose(1)
    items[1].woolCount=1;sim:Sync(items)
    local middle=sim.bodies[1]
    check(middle.shape=="sheep" and middle.node~=rec.node,"一份羊毛重建中档真实fixture")
    local xx,yy=sim:GetPose(1)
    check(math.abs(xx-x)<1e-6 and math.abs(yy-y)<1e-6 and items[1].scale==1 and items[1].weight==1,
        "跨档保持中心且不改公开体积重量")
    items[1].woolCount=4;sim:Sync(items)
    check(sim.bodies[1].node==middle.node,"一至四份同档不重复重建")
    local middleMass=middle.body.mass
    items[1].woolCount=5;sim:Sync(items)
    local fat=sim.bodies[1]
    check(fat.shape=="sheep_5" and fat.body.mass>middleMass,"五份胖档碰撞覆盖更宽")
    items[2].woolExtraEntry=true;sim:Sync(items,true,123)
    check(select(2,sim:GetPose(2))>5.8,"额外羊毛准备入瓶从瓶顶布置")
    sim:SetMode(1);sim:Shake(.4,0);sim:Step(1/60)
    check(sim:Contacts().shakeStrength>=4,"真实强摇输入dv提供强摇信号")
    for _=1,5 do sim:Step(1/60) end
    check(sim:Contacts().shakeStrength==0,"无输入不重复强摇，碰撞不伪造信号")
    sim:Shake(.4,0);sim:Step(1/60)
    check(sim:Contacts().shakeStrength==0,"0.35秒防抖不重复脱毛")
    for _=1,25 do sim:Step(1/60) end
    sim:Shake(.4,0);sim:Step(1/60)
    check(sim:Contacts().shakeStrength>=4,"防抖结束后新强摇可再次触发")
end)

-- 压力夹具：100件包含每种新轮廓/幽灵/培根，持续10秒输入；逐段检测有限与瓶内。
case("100物品600步不穿瓶且原生对象安全释放", function(check)
    local ids={}
    local catalog={table.unpack(IDS)}
    catalog[#catalog+1]="ghost";catalog[#catalog+1]="bacon";catalog[#catalog+1]="banana"
    for i=1,100 do ids[i]=catalog[(i-1)%#catalog+1] end
    local sim=make(ids)
    local safe=true
    local maxY,minY,maxX=-math.huge,math.huge,0
    for step=1,600 do
        if step%20==0 then sim:Shake(step%40==0 and .12 or -.12,.08) end
        sim:Step(1/60)
        for _,record in pairs(sim.bodies) do
            local position=record.node.position2D
            for _,part in ipairs(record.parts) do
                local p=part.node.position2D
                local width=p.y>=6.05 and 1.15 or math.min(2.4,2.4-(2.4-1.15)/.55*(p.y-5.5))
                if safe and not(p.x==p.x and p.y==p.y and p.y>-.08 and p.y<6.48 and math.abs(p.x)<width+.08) then
                    print(string.format("[ExpansionPhysics] 首次越界 step=%d uid=%d kind=%s center=(%.4f,%.4f) part=(%.4f,%.4f)",
                        step,record.uid,record.kind,position.x,position.y,p.x,p.y))
                end
                safe=safe and p.x==p.x and p.y==p.y and p.y>-.08 and p.y<6.48 and math.abs(p.x)<width+.08
                maxY,minY,maxX=math.max(maxY,p.y),math.min(minY,p.y),math.max(maxX,math.abs(p.x))
            end
        end
    end
    print(string.format("[ExpansionPhysics] stress minY=%.6f maxY=%.6f maxX=%.6f",minY,maxY,maxX))
    check(safe,"100件全真实刚体/软体段600步均有限不穿瓶")
    sim:Clear()
    check(next(sim.bodies)==nil and #sim._retired==0 and next(sim.expansion.states)==nil,"清理后没有悬空物体或运动状态")
end)

case("真实Game和Box2D完整生态固定步长至reveal", function(check)
    local Game=require("Bottle.Game")
    local game=Game.New(927153) --[[@as any]]
    game._instances,game.deck,game.discard,game.drawn={},{},{},{}
    game._lastPositions,game._nextUid={},1
    game.phase,game.elapsed,game.score="prepare",0,0
    local ids={"sheep","grass","knife","pig","apple","calf","grass","discus_athlete",
        "compass","hay","chick","chicken_keeper","egg","bodyguard","jelly","wool"}
    for _,id in ipairs(ids) do
        local item=game:_Create(id)
        item.location,item.remaining="bottle",0
        game.drawn[#game.drawn+1]=item.uid
    end
    game:Get(1).woolCount=5
    local started=game:Start()
    check(started,"真实生态从prepare开始")
    local sim=Physics.New();worlds[#worlds+1]=sim
    sim:Sync(game:BottleItems(),true,443)
    sim:RememberEvents(game.startEvents);sim:Sync(game:BottleItems())
    place(sim,1,-1.5,3);place(sim,2,-1.5,3)
    place(sim,3,-1.6,3.15);place(sim,4,0,3);place(sim,5,.2,3)
    place(sim,6,1.4,3);place(sim,7,1.4,3)
    place(sim,8,0,4.2);place(sim,9,-.5,4.4)
    sim.bodies[9].body.angularDamping=0
    sim.bodies[9].body.angularVelocity=7
    sim:SetMode(1)
    local counts={}
    local maxCount,finiteAll,hasDiscus=0,true,false
    local function consume(events)
        for _,event in ipairs(events) do counts[event.kind]=(counts[event.kind] or 0)+1 end
        sim:RememberEvents(events);sim:Sync(game:BottleItems())
        maxCount=math.max(maxCount,#game:BottleItems())
        for _,item in ipairs(game:BottleItems()) do hasDiscus=hasDiscus or item.id=="discus" end
        for _,record in pairs(sim.bodies) do
            local p=record.node.position2D
            finiteAll=finiteAll and p.x==p.x and p.y==p.y and math.abs(p.x)<3 and p.y>-.1 and p.y<6.5
        end
    end
    for step=1,600 do
        if step==12 or step==240 then sim:Shake(.4,.05) end
        sim:Step(1/60)
        consume(game:Step(1/60,sim:Contacts()))
    end
    check(game.phase=="settle" and math.abs(game.elapsed-10)<1e-6,"真实600步恰好进入settle")
    check(hasDiscus and (counts.flight or 0)>0,"生态规则真实创建并抛出临时飞盘")
    check((counts.rotate or 0)>0,"生态真实旋转累计触发指南针事件")
    check((counts.dash or 0)>0 and (counts.remove or 0)>0,"真实消费接触触发小牛冲刺与移除")
    check((game:Get(1).woolCount or 0)==0,"真实输入或刀接触触发整批脱毛")
    for _=1,120 do
        sim:Step(1/60)
        consume(game:SettleStep(1/60,sim:Contacts()))
    end
    check(game.phase=="reveal","120步settle完成进入reveal")
    local tempBottle=false
    for _,item in ipairs(game:AllInstances()) do
        if item.generatedTemporary and item.location=="bottle" then tempBottle=true end
    end
    check(not tempBottle and #game:BottleItems()==0,"结算回收瓶内及临时产物")
    check(maxCount<=100 and finiteAll,"生态全程数量不超100且物理姿态有限在瓶内")
    print(string.format("[ExpansionPhysics] ecology maxCount=%d flight=%d rotate=%d dash=%d phase=%s",
        maxCount,counts.flight or 0,counts.rotate or 0,counts.dash or 0,game.phase))
end)

-- 遗物碰撞设计：四便便与苹果真实重叠 -> sensor Begin/End；苹果不能被推动。
-- 加速对照两个同种子真实世界，固定dt完全相同；不以改时钟或手写位移代替积分。
case("幽灵便便获取即时重建及真实穿透接触", function(check)
    for _,id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        local sim,items=make({id,"apple"})
        place(sim,1,0,3);place(sim,2,0,3)
        sim.bodies[2].body.gravityScale=0
        sim:Step(1/60)
        local old=sim.bodies[1].node
        local x,y=sim:GetPose(1)
        sim:Sync(items,false,nil,{ghostPoop=true})
        local rec=sim.bodies[1]
        local xx,yy=sim:GetPose(1)
        check(rec.node~=old and math.abs(xx-x)<1e-6 and math.abs(yy-y)<1e-6,
            id.."获取遗物即重建且保持精确中心")
        local triggers=true
        for _,shape in ipairs(rec.shapes) do triggers=triggers and shape.trigger and shape.maskBits==3 end
        check(rec.sensor and rec.ghostLike and rec.body.bodyType==BT_DYNAMIC
            and rec.body.gravityScale==0 and rec.body.fixedRotation and triggers,id.."动态sensor零重力直立")
        place(sim,1,0,3);place(sim,2,0,3)
        local seen,ended=false,false
        local ax,ay=sim:GetPose(2)
        for _=1,180 do
            sim:Shake(.4,.4);sim:Step(1/60)
            local touching=pair(sim,1,2)
            seen=seen or touching;ended=ended or (seen and not touching)
        end
        local px,py=sim:GetPose(2)
        check(seen and ended,id.."穿透仍产生真实Begin与End")
        -- 隔离实体摇晃：上一段仅验证sensor事实，静止苹果另开无输入世界。
        local quiet,quietItems=make({id,"apple"})
        quiet:Sync(quietItems,false,nil,{ghostPoop=true})
        place(quiet,1,0,3);place(quiet,2,0,3);quiet.bodies[2].body.gravityScale=0
        for _=1,120 do quiet:Step(1/60) end
        local qx,qy=quiet:GetPose(2)
        check(math.abs(qx)<1e-7 and math.abs(qy-3)<1e-7 and #quiet:TakeImpacts()==0,
            id.."不推动静止苹果且不输出碰撞音")
        check(px==px and py==py and ax==ax and ay==ay,id.."穿透输入后姿态有限")
        sim:Sync(items,false,nil,{ghostPoop=false})
        check(not sim.bodies[1].sensor and not sim.bodies[1].shapes[1].trigger
            and sim.bodies[1].body.gravityScale==1,id.."移除遗物恢复实体重力")
    end
    local a,items=make({"poop"})
    local b,bItems=make({"poop"})
    a:Sync(items,false,nil,{ghostPoop=true});b:Sync(bItems,false,nil,{ghostPoop=true})
    place(a,1,0,3);place(b,1,0,3);a:SetMode(1);b:SetMode(1)
    for _=1,60 do a:Shake(.4,.4);a:Step(1/60);b:Step(1/60) end
    local ax,ay=a:GetPose(1);local bx,by=b:GetPose(1)
    check(math.abs(ax-bx)<1e-6 and math.abs(ay-by)<1e-6,"幽灵便便自主流场完全免摇晃")
    a:RememberEvents({{kind="rotate",uid=1,delta=-math.pi/2}});a:Sync(items)
    check(select(3,a:GetPose(1))==0,"幽灵便便强制旋转仍保持直立")
    a._updating=true;a:Sync(items,false,nil,{accelerator=true,ghostPoop=false})
    check(a.ghostPoop and a.speedMultiplier==1,"锁定世界中遗物变化只排队")
    a._updating=false;a:Step(0)
    check(not a.ghostPoop and a.speedMultiplier==1.2 and not a.bodies[1].sensor,"解锁安全屏障应用遗物配置")
end)

case("分裂器命中四幽灵便便真实sensor并保持复制体态", function(check)
    local Game=require("Bottle.Game")
    local Rules=require("Bottle.ExpansionEffects")
    for _,id in ipairs({"poop","golden_poop","diamond_poop","rainbow_poop"}) do
        local game=Game.New(885) --[[@as any]]
        game._instances,game.deck,game.discard,game.drawn={},{},{},{}
        game._nextUid=1;game.relics={ghost_poop=true}
        for _,kind in ipairs({id,"splitter"}) do
            local item=game:_Create(kind);item.location="bottle"
            game.drawn[#game.drawn+1]=item.uid
        end
        local sim=Physics.New();worlds[#worlds+1]=sim
        sim:Sync(game:BottleItems(),true,885,{ghostPoop=true})
        place(sim,1,0,3);place(sim,2,0,3);sim.bodies[2].body.gravityScale=0
        sim:Step(1/60)
        local contacts=sim:Contacts()
        check(pair(sim,1,2),id.."与分裂器产生真实sensor接触")
        local events={}
        check(Rules.Apply(game,game:Get(2),contacts,events),id.."真实接触可驱动规则分裂")
        sim:RememberEvents(events);sim:Sync(game:BottleItems())
        local copy=game:Get(3)
        local rec=sim.bodies[3]
        check(copy and copy.id==id and rec and rec.sensor and rec.ghostLike
            and rec.body.gravityScale==0 and rec.shapes[1].trigger,id.."复制体仍真实动态穿透且零重力")
    end
end)

case("加速器固定步线性运动自由落体软体与真实回弹", function(check)
    local function moving(id,fast,gravity)
        local sim,items=make({id})
        sim:Sync(items,false,nil,{accelerator=fast})
        local rec=sim.bodies[1]
        local center=rec.node.position2D
        for _,part in ipairs(rec.parts) do
            local p=part.node.position2D
            part.node:SetPosition2D(p.x-center.x,p.y-center.y+4)
            part.body.linearVelocity=Vector2(.8,0)
            part.body.angularVelocity=0;part.body.gravityScale=gravity
            part.body.linearDamping=0;part.body.angularDamping=0
        end
        return sim
    end
    for _,id in ipairs({"apple","bacon"}) do
        local normal,fast=moving(id,false,0),moving(id,true,0)
        local starts={}
        for i,part in ipairs(normal.bodies[1].parts) do starts[i]=part.node.position2D.x end
        for _=1,60 do normal:Step(1/60);fast:Step(1/60) end
        local ratio=true
        for i,part in ipairs(fast.bodies[1].parts) do
            local baseline=normal.bodies[1].parts[i].node.position2D.x-starts[i]
            local actual=part.node.position2D.x-starts[i]
            ratio=ratio and math.abs(actual-baseline*1.2)<.0005
                and math.abs(part.body.linearVelocity.x-.8)<.001 and part.body.gravityScale==0
        end
        check(ratio,id.."每段真实位移120%且基准速度不指数增大")
        check(math.abs(normal.clock-1)<1e-6 and math.abs(fast.clock-1)<1e-6,id.."固定dt时钟完全相同")
    end
    local normal,fast=moving("apple",false,1),moving("apple",true,1)
    for _=1,30 do normal:Step(1/60);fast:Step(1/60) end
    local _,ny=normal:GetPose(1);local _,fy=fast:GetPose(1)
    check(math.abs((4-fy)-(4-ny)*1.2)<.001,"自由落体实际位移120%而非只初速加成")
    check(math.abs(normal.bodies[1].body.linearVelocity.y-fast.bodies[1].body.linearVelocity.y)<.001
        and fast.bodies[1].body.gravityScale==1,"积分后恢复原重力参数与基准重力速度")
    place(fast,1,1.7,3);fast.bodies[1].body.gravityScale=0
    fast.bodies[1].body.linearVelocity=Vector2(4,0)
    local bounced,bounded,maxSpeed=false,true,0
    for _=1,180 do
        fast:Step(1/60)
        local p,v=fast.bodies[1].node.position2D,fast.bodies[1].body.linearVelocity
        bounced=bounced or v.x<-.1
        bounded=bounded and math.abs(p.x)<2.4 and p.y>0 and p.y<6.4
        maxSpeed=math.max(maxSpeed,math.abs(v.x))
    end
    check(bounced and bounded and maxSpeed<4.01,"加速器真实CCD回弹不穿墙不指数增能")
end)

case("加速器覆盖幽灵便便飞盘冲刺且排除锚定闪现", function(check)
    for _,id in ipairs({"ghost","poop","golden_poop","diamond_poop","rainbow_poop","discus"}) do
        local a,items=make({id});local b,bItems=make({id})
        a:Sync(items,false,nil,{ghostPoop=true})
        b:Sync(bItems,false,nil,{accelerator=true,ghostPoop=true})
        place(a,1,0,3);place(b,1,0,3)
        a:Step(1/60);b:Step(1/60)
        local ax,ay=a:GetPose(1);local bx,by=b:GetPose(1)
        check(math.abs(bx-ax*1.2)<1e-5 and math.abs(by-3-(ay-3)*1.2)<1e-5,
            id.."受控自主运动实际位移120%")
    end
    local a,items=make({"discus","calf","gecko"})
    local b,bItems=make({"discus","calf","gecko"})
    b:Sync(bItems,false,nil,{accelerator=true})
    for _,sim in ipairs({a,b}) do
        place(sim,1,-1.2,3);place(sim,2,-1.2,4.5);place(sim,3,-1,1)
        sim.bodies[2].body.gravityScale=0;sim.bodies[2].body.linearDamping=0
        sim:RememberEvents({{kind="flight",uid=1,toX=1.2,toY=3,duration=1},
            {kind="dash",uid=2,dx=1,dy=0,duration=.35},{kind="anchor",uid=3,x=-1,y=1}})
    end
    for _=1,21 do a:Step(1/60);b:Step(1/60) end
    local ax=a:GetPose(2);local bx=b:GetPose(2)
    check(math.abs((bx+1.2)-(ax+1.2)*1.2)<.002,"小牛短冲刺实际路程120%")
    check(a.expansion.states[2].dashRemaining<1e-7 and b.expansion.states[2].dashRemaining<1e-7,
        "加速器不缩短0.35秒冲刺计时")
    local fa=assert(a.expansion.states[1].flight);local fb=assert(b.expansion.states[1].flight)
    check(math.abs(fa.elapsed-fb.elapsed)<1e-7 and math.abs(fb.progress-fa.progress*1.2)<1e-7,
        "飞盘弧线空间进度120%且真实飞行时间相同")
    for _=1,40 do a:Step(1/60);b:Step(1/60) end
    check(a:Contacts().flightArrived[1] and b:Contacts().flightArrived[1],"加速弧线仍可到达真实终点")
    local gx,gy=b:GetPose(3)
    check(math.abs(gx+1)<1e-6 and math.abs(gy-1)<1e-6,"加速器不移动锚定壁虎")
    b:RememberEvents({{kind="teleport",uid=1,x=-.63,y=2.17}});b:Sync(bItems)
    b:Step(1/60)
    local tx,ty=b:GetPose(1)
    check(math.abs(tx+.63)<1e-6 and math.abs(ty-2.17)<1e-6,"闪现精确坐标不乘移动倍率")
    b:Sync(bItems,false,nil,{accelerator=false,ghostPoop=false})
    check(b.speedMultiplier==1 and not b.ghostPoop,"关闭遗物不残留速度倍率")
end)

-- 原202条无遗物回归完整保留；下方额外用真Game重跑遗物组合生态。
case("加速器幽灵便便真实Game生态不偷跑计时", function(check)
    local Game=require("Bottle.Game")
    local game=Game.New(927153) --[[@as any]]
    game._instances,game.deck,game.discard,game.drawn={},{},{},{}
    game._lastPositions,game._nextUid={},1
    game.phase,game.elapsed,game.score="prepare",0,0
    game.relics={accelerator=true,ghost_poop=true}
    for _,id in ipairs({"sheep","grass","knife","pig","apple","calf","grass","discus_athlete",
        "compass","hay","chick","chicken_keeper","egg","bodyguard","jelly","poop",
        "golden_poop","diamond_poop","rainbow_poop","splitter","bacon"}) do
        local item=game:_Create(id)
        item.location,item.remaining="bottle",0
        game.drawn[#game.drawn+1]=item.uid
    end
    game:Get(1).woolCount=5
    assert(game:Start())
    local sim=Physics.New();worlds[#worlds+1]=sim
    local options={accelerator=true,ghostPoop=true}
    sim:Sync(game:BottleItems(),true,443,options)
    sim:RememberEvents(game.startEvents);sim:Sync(game:BottleItems(),false,nil,options)
    place(sim,1,-1.5,3);place(sim,2,-1.5,3)
    place(sim,3,-1.6,3.15);place(sim,4,0,3);place(sim,5,.2,3)
    place(sim,6,1.4,3);place(sim,7,1.4,3)
    place(sim,8,0,4.2);place(sim,9,-.5,4.4)
    sim.bodies[9].body.angularDamping=0;sim.bodies[9].body.angularVelocity=7
    sim:SetMode(1)
    local maxCount,safe,sensors=0,true,true
    local function consume(events)
        sim:RememberEvents(events);sim:Sync(game:BottleItems(),false,nil,options)
        maxCount=math.max(maxCount,#game:BottleItems())
        for _,rec in pairs(sim.bodies) do
            if rec.kind=="poop" or rec.kind=="golden_poop" or rec.kind=="diamond_poop" or rec.kind=="rainbow_poop" then
                sensors=sensors and rec.sensor and rec.ghostLike and rec.body.gravityScale==0
            end
            for _,part in ipairs(rec.parts) do
                local p=part.node.position2D
                safe=safe and p.x==p.x and p.y==p.y and math.abs(p.x)<2.5 and p.y>-.1 and p.y<6.5
            end
        end
    end
    for step=1,600 do
        if step==12 or step==240 then sim:Shake(.4,.05) end
        sim:Step(1/60);consume(game:Step(1/60,sim:Contacts()))
    end
    check(game.phase=="settle" and math.abs(game.elapsed-10)<1e-6
        and math.abs(sim.clock-10)<1e-6,"遗物生态600步仍仅10秒且恰到settle")
    for _=1,120 do sim:Step(1/60);consume(game:SettleStep(1/60,sim:Contacts())) end
    check(game.phase=="reveal" and #game:BottleItems()==0,"遗物生态120步settle清瓶进入reveal")
    local lingering=false
    for _,item in ipairs(game:AllInstances()) do
        lingering=lingering or (item.generatedTemporary and item.location=="bottle")
    end
    check(not lingering and safe and sensors and maxCount<=100,"遗物生态全段有限/便便真实sensor/临时清理/上限100")
    print(string.format("[ExpansionPhysics] relicEcology maxCount=%d phase=%s",maxCount,game.phase))
end)

local V=_G["V"]
if V then
    SubscribeToEvent("PhysicsBeginContact2D",function(_,data)
        for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsBeginContact2DEventData]],true) end
    end)
    SubscribeToEvent("PhysicsEndContact2D",function(_,data)
        for _,sim in ipairs(worlds) do sim:Contact(data --[[@as PhysicsEndContact2DEventData]],false) end
    end)
    V.atFrame(2,function()
        for _,entry in ipairs(cases) do
            local ok,err=pcall(entry.run,function(condition,message) V.assert(condition,message) end)
            V.assert(ok,"专项完成: "..entry.name..(ok and "" or " | "..tostring(err)))
            clean()
        end
        V.finish()
    end)
end
function Start() print("[ExpansionPhysics] 隔离真实Box2D专项就绪") end
function Stop() clean() end
