-- 自适应bullet选择器的纯Lua数学/状态回归；真实CCD接触由独立Box2D专项验收。
local CCD = require("Bottle.AdaptiveCCD")
local Shapes = require("Bottle.Shapes")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param work fun()
local function Test(name,work) cases[#cases+1]={name=name,run=work} end

---@param uid number
---@param x number
---@param vx number?
---@param shape string?
---@param radius number?
---@return BottleBody
local function Body(uid,x,vx,shape,radius)
    local body={bullet=true,linearVelocity={x=vx or 0,y=0},angularVelocity=0,gravityScale=1}
    return {uid=uid,node={position2D={x=x,y=2}},body=body,parts={{body=body}},
        shape=shape or "circle",radius=radius or .2,envelope=radius or .2,
        newbornRemaining=0,ccdGuardRemaining=0,sensor=false} --[[@as BottleBody]]
end

---@param records BottleBody[]
---@return BottlePhysics
local function World(records)
    local bodies,states={},{}
    for _, record in ipairs(records) do
        bodies[record.uid]=record
        states[record.uid]={anchored=false,rotations={},dashRemaining=0}
    end
    return {bodies=bodies,world={gravity={x=0,y=-9.81},continuousPhysics=true,
        velocityIterations=12,positionIterations=8},expansion={states=states}} --[[@as BottlePhysics]]
end

Test("真实凸片最小厚度含缩放与未知形状保守回退",function()
    assert(math.abs(assert(CCD.Thickness("circle",.3))-.6)<1e-12)
    Shapes.profiles.ccd_test_thin={polygons={{0,7,16,7,16,9,0,9}}}
    local thin=CCD.Thickness("ccd_test_thin",.4)
    assert(thin and math.abs(thin-.1)<1e-12)
    assert(math.abs(assert(CCD.Thickness("ccd_test_thin",.2))-.05)<1e-12)
    assert(CCD.Thickness("missing_shape",.3)==nil and CCD.Thickness("circle",-1)==nil)
    Shapes.profiles.ccd_test_thin=nil
end)

Test("共同高速平移和相同重力不把全瓶变成bullet",function()
    local records={}
    for uid=1,100 do records[uid]=Body(uid,(uid%10)*.2,50) end
    local sim=World(records)
    CCD.Update(sim,1/60)
    assert(sim.ccdEnabledCount==0 and sim.ccdBodyCount==100)
    assert(sim.world.continuousPhysics and sim.world.velocityIterations==12 and sim.world.positionIterations==8)
end)

Test("相向高速近邻至少一侧开启，远方物体不额外开启",function()
    local a,b,far=Body(1,-.25,12),Body(2,.25,-12),Body(3,30,100)
    local sim=World({b,far,a})
    CCD.Update(sim,1/60)
    assert((a.body.bullet or b.body.bullet) and not (a.body.bullet and b.body.bullet))
    assert(not far.body.bullet and sim.ccdEnabledCount==1)
    assert(sim.ccdState.samples[1].uid==1 and sim.ccdState.samples[2].uid==2)
end)

Test("角点扫掠直接使用弧度每秒且优先旋转风险源",function()
    local a,b=Body(1,0),Body(2,.35)
    a.body.angularVelocity=math.rad(180)
    local sim=World({a,b})
    CCD.Update(sim,1/60)
    assert(not a.body.bullet and not b.body.bullet,"输入180度意图须先转换为rad/s")
    a.body.angularVelocity=math.rad(3600)
    CCD.Update(sim,1/60)
    assert(a.body.bullet and not b.body.bullet)
    assert(math.abs(sim.ccdState.samples[1].spin-math.pi/15)<1e-12)
end)

Test("原始1rad每秒按真实包络精确计算角点扫掠",function()
    local a=Body(1,0)
    a.body.angularVelocity=1
    local sim=World({a})
    CCD.Update(sim,1/60)
    assert(math.abs(sim.ccdState.samples[1].spin-.2/60)<1e-12,
        "原生1rad/s不可再乘pi/180低估扫掠")
end)

Test("薄fixture与scale使相同相对运动保持保守",function()
    Shapes.profiles.ccd_test_thin={polygons={{0,7,16,7,16,9,0,9}}}
    local a,b=Body(1,0,3,"ccd_test_thin",.4),Body(2,.5,0)
    local sim=World({a,b})
    CCD.Update(sim,1/60)
    assert(not a.body.bullet and not b.body.bullet)
    a.radius,a.envelope=.2,.2
    b.node.position2D.x=.35
    CCD.Update(sim,1/60)
    assert(a.body.bullet or b.body.bullet)
    Shapes.profiles.ccd_test_thin=nil
end)

Test("实际重力倍率差的本步相对加速度扫掠参与风险",function()
    local a,b=Body(1,0,0,"circle",.01),Body(2,.025,0,"circle",.01)
    b.body.gravityScale=10
    local sim=World({a,b})
    CCD.Update(sim,1/60)
    assert(a.body.bullet or b.body.bullet)
end)

Test("新生重建软体穿透体与动作保护，短保护可自然到期",function()
    local a,b,c,d,e=Body(1,0),Body(2,2),Body(3,4),Body(4,6),Body(5,8)
    a.newbornRemaining=.1
    b.soft={} --[[@as BottleSoftBacon]]
    c.sensor=true
    local sim=World({a,b,c,d,e})
    sim.expansion.states[d.uid].dashRemaining=.2
    CCD.Guard(e)
    CCD.Update(sim,1/60)
    assert(a.body.bullet and b.body.bullet and c.body.bullet and d.body.bullet and e.body.bullet)
    a.newbornRemaining=0
    for _=1,8 do CCD.Update(sim,1/60) end
    assert(not a.body.bullet and b.body.bullet and c.body.bullet and d.body.bullet and not e.body.bullet)
end)

Test("运动学邻居不能代替动态体承担bullet，非法采样保守开启",function()
    local a,b,c=Body(1,0,0),Body(2,.35,30),Body(3,20,0,"missing_shape")
    local sim=World({a,b,c})
    sim.expansion.states[b.uid].anchored=true
    CCD.Guard(b)
    CCD.Update(sim,1/60)
    assert(a.body.bullet and c.body.bullet)
    a.body.linearVelocity.x=0/0
    CCD.Update(sim,1/60)
    assert(a.body.bullet and sim.ccdState.samples[1].reason=="unknown")
end)

Test("同向高速本步触侧壁和底部时保护反弹后的新相对碰撞",function()
    for _, floor in ipairs({false,true}) do
        local a,b=Body(1,1.95,80,"circle",.15),Body(2,1.35,80,"circle",.15)
        local sim=World({a,b})
        sim.world.gravity={x=0,y=0} --[[@as Vector2]]
        if floor then
            a.node.position2D={x=0,y=.45};b.node.position2D={x=0,y=1.05}
            a.body.linearVelocity={x=0,y=-80};b.body.linearVelocity={x=0,y=-80}
            sim.ccdWalls={{ax=-2.64,ay=0,bx=2.64,by=0,nx=0,ny=-1}}
        else
            sim.ccdWalls={{ax=2.4,ay=-.24,bx=2.4,by=5.74,nx=1,ny=0}}
        end
        CCD.Update(sim,1/60)
        assert(a.body.bullet and b.body.bullet)
        assert(sim.ccdState.samples[1].reason=="wall" and sim.ccdState.samples[2].reason=="wall")
    end
end)

Test("贴壁静止微旋低速或离壁运动不因墙保护全部开启",function()
    local a=Body(1,2.21,0,"circle",.2)
    local sim=World({a})
    sim.world.gravity={x=0,y=0} --[[@as Vector2]]
    sim.ccdWalls={{ax=2.4,ay=-.24,bx=2.4,by=5.74,nx=1,ny=0}}
    for _, speed in ipairs({0,.01,-80}) do
        a.body.linearVelocity.x=speed
        a.body.angularVelocity=math.rad(1)
        CCD.Update(sim,1/60)
        assert(not a.body.bullet,"静止、微旋、低速、离壁不应开启")
    end
    a.body.linearVelocity.x=0
    a.body.angularVelocity=math.rad(3600)
    CCD.Update(sim,1/60)
    assert(a.body.bullet and sim.ccdState.samples[1].reason=="wall")
end)

Test("墙扫掠使用有限线段并覆盖斜肩和真实重力倍率",function()
    local a=Body(1,2.3,80,"circle",.05)
    local sim=World({a})
    sim.world.gravity={x=0,y=0} --[[@as Vector2]]
    sim.ccdWalls={{ax=2.4,ay=0,bx=2.4,by=5.5,nx=1,ny=0}}
    a.node.position2D.y=5.9
    CCD.Update(sim,1/60)
    assert(not a.body.bullet,"不能将侧壁无限延长到瓶肩")
    a.node.position2D={x=1.7,y=5.5};a.body.linearVelocity={x=0,y=40}
    sim.ccdWalls={{ax=2.4,ay=5.5,bx=1.15,by=6.05,nx=.4,ny=.9}}
    CCD.Update(sim,1/60)
    assert(a.body.bullet)
    a.node.position2D={x=0,y=.1};a.body.linearVelocity={x=0,y=0}
    a.body.gravityScale=100
    sim.world.gravity={x=0,y=-9.81} --[[@as Vector2]]
    sim.ccdWalls={{ax=-2.4,ay=0,bx=2.4,by=0,nx=0,ny=-1}}
    CCD.Update(sim,1/60)
    assert(a.body.bullet,"加速积分中的真实gravityScale不可漏算")
end)

Test("薄体星形风险图由中心覆盖，避免逐边把所有宽邻居设为bullet",function()
    local records={Body(1,0,0,"gecko",.3)}
    for uid=2,21 do records[uid]=Body(uid,.1+uid*.001,6) end
    local sim=World(records)
    CCD.Update(sim,1/60)
    assert(records[1].body.bullet and sim.ccdEnabledCount==1)
    local state,neighbors=sim.ccdState,sim.ccdState.neighbors[1]
    CCD.Update(sim,1/60)
    assert(sim.ccdEnabledCount==1 and sim.ccdState==state and state.neighbors[1]==neighbors,
        "邻接缓存应复用且旧边不能污染下步")
end)

Test("运动学星心不能覆盖动态风险边，已有动态保护及sensor保持原语义",function()
    local records={Body(1,0,0,"gecko",.3)}
    for uid=2,8 do records[uid]=Body(uid,.1+uid*.001,6) end
    local sim=World(records)
    sim.expansion.states[1].anchored=true
    CCD.Guard(records[1])
    CCD.Update(sim,1/60)
    for uid=2,8 do assert(records[uid].body.bullet,"运动学端不能代替动态端") end
    sim.expansion.states[1].anchored=false
    CCD.Update(sim,1/60)
    assert(sim.ccdEnabledCount==1,"已有动态guard应覆盖全部星形边")
    records[1].sensor=true
    CCD.Update(sim,1/60)
    assert(sim.ccdEnabledCount==1,"sensor不能制造实体风险边")
end)

Test("全风险边均有动态端保护，确定性且开启数量不超过旧选择",function()
    local function Evaluate(reverse)
        local records={}
        for index=1,32 do
            local uid=reverse and 33-index or index
            local record=Body(uid,(uid%8)*.17,(uid%7-3)*5,uid%4==0 and "gecko" or "circle",.18+(uid%3)*.02)
            record.node.position2D.y=2+math.floor(uid/8)*.19
            record.body.linearVelocity.y=(uid%5-2)*3
            record.body.angularVelocity=math.rad(uid%3*720)
            record.body.gravityScale=uid%4+1
            records[index]=record
        end
        local sim=World(records)
        sim.expansion.states[5].anchored=true
        sim.bodies[2].ccdGuardRemaining=.1
        sim.bodies[7].sensor=true
        sim.bodies[9].shape="missing_shape"
        sim.expansion.states[11].dashRemaining=.2
        CCD.Update(sim,1/60)
        local samples=sim.ccdState.samples
        local old={}
        for _,sample in ipairs(samples) do old[sample.uid]=sample.uid==2 or sample.uid==7 or sample.uid==9 or sample.uid==11 end
        for first=1,#samples do
            local a=samples[first]
            for second=first+1,#samples do
                local b=samples[second]
                local sweep=math.sqrt((a.vx-b.vx)^2+(a.vy-b.vy)^2)/60+a.spin+b.spin
                    +9.81*math.abs(a.gravity-b.gravity)/3600
                local reach=a.envelope+b.envelope+sweep
                if not a.sensor and not b.sensor and (a.dynamic or b.dynamic)
                    and (a.x-b.x)^2+(a.y-b.y)^2<=reach^2
                    and sweep>.5*math.min(a.thickness,b.thickness) then
                    assert((a.enabled and a.dynamic) or (b.enabled and b.dynamic),"风险边存在未保护的动态端")
                    if not (old[a.uid] and a.dynamic) and not (old[b.uid] and b.dynamic) then
                        local chosen=a
                        if not a.dynamic or (b.dynamic and a.spin+a.travel<b.spin+b.travel) then chosen=b end
                        old[chosen.uid]=true
                    end
                end
            end
        end
        local oldCount,enabled=0,{}
        for _,sample in ipairs(samples) do
            if old[sample.uid] then oldCount=oldCount+1 end
            if sample.enabled then enabled[#enabled+1]=sample.uid end
        end
        assert(#enabled<=oldCount,"保留旧覆盖保险不能增加开启数量")
        return table.concat(enabled,",")
    end
    local random=math.random
    math.random=function() error("CCD选择不可读取玩法随机流") end
    local ok,a,b=pcall(function() return Evaluate(false),Evaluate(true) end)
    math.random=random
    assert(ok,a)
    assert(a==b,"相同UID状态的结果不可依赖表插入顺序")
end)

Test("聚合NaN校验逐字段保守回退并拒绝无穷和错误类型",function()
    local setters={
        function(a,_,v) a.node.position2D.x=v end,function(a,_,v) a.node.position2D.y=v end,
        function(a,_,v) a.body.linearVelocity.x=v end,function(a,_,v) a.body.linearVelocity.y=v end,
        function(a,_,v) a.body.angularVelocity=v end,function(a,_,v) a.body.gravityScale=v end,
        function(a,_,v) a.envelope=v end,
        function(_,sim,v) sim.world.gravity.x=v end,function(_,sim,v) sim.world.gravity.y=v end,
    }
    for _,value in ipairs({0/0,math.huge,-math.huge,"invalid"}) do
        for _,setter in ipairs(setters) do
            local a=Body(1,0)
            local sim=World({a})
            setter(a,sim,value)
            CCD.Update(sim,1/60)
            assert(a.body.bullet and sim.ccdState.samples[1].reason=="unknown","每个非法字段均应保守开启")
        end
    end
    for _,dt in ipairs({0/0,math.huge,-math.huge,"invalid"}) do
        local a=Body(1,0)
        local sim=World({a})
        -- 刻意越过静态契约，验证运行态仍保守处理损坏输入。
        CCD.Update(sim,dt --[[@as number]])
        assert(a.body.bullet and sim.ccdState.samples[1].reason=="unknown","非法dt不可推进保护计时")
    end
end)

Test("L1粗筛在原欧氏包络边界两侧保持相同风险真假",function()
    for index=0,16 do
        for _,factor in ipairs({.5,1-1e-10,1,1+1e-10,2,100}) do
            local angle=index*math.pi/8
            local a,b=Body(1,0,30*math.cos(angle)),Body(2,0)
            a.body.linearVelocity.y=30*math.sin(angle)
            local sweep=math.sqrt(a.body.linearVelocity.x^2+a.body.linearVelocity.y^2)*(1/60)
            local reach=.4+sweep
            b.node.position2D={x=reach*factor*math.cos(angle),y=2+reach*factor*math.sin(angle)}
            local expected=(a.node.position2D.x-b.node.position2D.x)^2
                +(a.node.position2D.y-b.node.position2D.y)^2<=reach^2 and sweep>.2
            local sim=World({a,b})
            CCD.Update(sim,1/60)
            assert((a.body.bullet or b.body.bullet)==expected,"粗筛不得更改最终风险结果")
        end
    end
end)

Test("未知运动学端不能把NaN或错误类型送入风险算术并遗漏动态邻居",function()
    local setters={
        function(a,v) a.node.position2D.x=v end,
        function(a,v) a.body.linearVelocity.y=v end,
        function(a,v) a.body.angularVelocity=v end,
        function(a,v) a.body.gravityScale=v end,
        function(a,v) a.envelope=v end,
    }
    for _,value in ipairs({0/0,math.huge,"invalid"}) do
        for _,setter in ipairs(setters) do
            local a,b=Body(1,0),Body(2,100)
            local sim=World({a,b})
            sim.expansion.states[1].anchored=true
            setter(a,value)
            CCD.Update(sim,1/60)
            assert(a.body.bullet and b.body.bullet,"无法界定未知端运动时远方动态端亦须保守保护")
            assert(sim.ccdState.samples[2].reason=="unknown-neighbor")
        end
    end
    local a,b=Body(1,0,0,"missing_shape"),Body(2,.3)
    local sim=World({a,b})
    sim.expansion.states[1].anchored=true
    CCD.Update(sim,1/60)
    assert(b.body.bullet,"未知几何的运动学端不能代替动态邻居承担bullet")
end)

Test("Vector2位置速度及世界重力每字段每微步只读取一次",function()
    local a=Body(1,0)
    local sim=World({a})
    local counts={}
    local function Vector(name,x,y)
        return setmetatable({}, {__index=function(_,key)
            local field=name..key
            counts[field]=(counts[field] or 0)+1
            return key=="x" and x or y
        end}) --[[@as Vector2]]
    end
    a.node.position2D=Vector("p",0,2)
    a.body.linearVelocity=Vector("v",0,0)
    sim.world.gravity=Vector("g",0,-9.81)
    CCD.Update(sim,1/120)
    for _,field in ipairs({"px","py","vx","vy","gx","gy"}) do assert(counts[field]==1,"tolua字段不可重复读取") end
end)

Test("L1扫掠阈值粗筛保留边界两侧的线性角点和重力风险",function()
    local dt=1/120
    for index=0,8 do
        for _,factor in ipairs({.01,.5,1-1e-10,1,1+1e-10,1.5,10}) do
            for _,angular in ipairs({0,180}) do
                local angle=index*math.pi/4
                local a,b=Body(1,0),Body(2,.1)
                local speed=.2/dt*factor
                a.body.linearVelocity.x=speed*math.cos(angle)
                a.body.linearVelocity.y=speed*math.sin(angle)
                a.body.angularVelocity=math.rad(angular)
                b.body.gravityScale=index%3+1
                local vx,vy=a.body.linearVelocity.x,a.body.linearVelocity.y
                local sweep=math.sqrt(vx*vx+vy*vy)*dt+math.abs(math.rad(angular))*.2*dt
                    +9.81*math.abs(1-b.body.gravityScale)*dt*dt
                local sim=World({a,b})
                CCD.Update(sim,dt)
                assert((a.body.bullet or b.body.bullet)==(sweep>.2),"低扫掠粗筛不能漏掉阈值边界的真实风险")
            end
        end
    end
end)

function Tests.Run()
    for _,case in ipairs(cases) do
        local ok,err=pcall(case.run)
        assert(ok,"Bottle.AdaptiveCCDTests ["..case.name.."] "..tostring(err))
    end
    return #cases
end

return Tests
