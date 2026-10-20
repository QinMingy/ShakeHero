-- 不创建场景或窗口；真实 ShakeMotion + 假 Physics 入口验证文件桥的时间和路由边界。
local Input = require("Bottle.SensorLabInput")
local Motion = require("Bottle.ShakeMotion")
local Tests = {}
local cases = {}
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end
local function Close(a, b) assert(math.abs(a - b) < 1e-9, tostring(a) .. " ~= " .. tostring(b)) end
local function Physics()
    local physics = {motion=Motion.New(), sensorCalls=0, stepTime=0}
    local advance = Motion.Step --[[@as fun(motion: BottleShakeMotion, dt: number): number, number]]
    function physics.motion:Step(dt)
        physics.stepTime = physics.stepTime + dt
        return advance(self, dt)
    end
    function physics:Sensor(ax, ay, dt)
        self.sensorCalls = self.sensorCalls + 1
        local dx, dy = self.motion:Sensor(ax, ay, dt)
        self.motion:Move(dx, dy)
    end
    function physics:Step() error("桥不能调用 Physics:Step") end
    return physics
end
local function Sample(seq, ax, ay, dt)
    return {seq=seq, sampleId=seq, deviceId="phone", screenAngle=0, ax=ax or 0, ay=ay or 0, dt=dt or 1/60}
end
local function Snapshot(generation, samples, extra)
    local value = {format="shakehero-sensor-bridge/v1", sessionId="session-a", generation=generation,
        resetRevision=0, sampleAgeMs=0, settings={gain=4,invertX=false,invertY=false,revision=0}, samples=samples}
    for key, item in pairs(extra or {}) do value[key] = item end
    return value
end
local function Ready(dt)
    local input, physics = Input.New(), Physics()
    input:Update(0, true, false)
    assert(input:Ingest(Snapshot(1, {Sample(1, 0, 0, dt)})))
    input:Advance(dt or 1/60, physics)
    return input, physics
end
local function Compare(a, b)
    for _, key in ipairs({"x","y","vx","vy","targetX","targetY","sensorBaseX","sensorBaseY","sensorX","sensorY"}) do Close(a[key], b[key]) end
end

Test("首个ring仅最新样本校准；同generation不刷新断流计时", function()
    local input, physics = Input.New(), Physics()
    input:Update(0, true, false)
    local snapshot = Snapshot(1, {Sample(1,.4),Sample(2,-.4),Sample(3,.2)})
    assert(input:Ingest(snapshot)); input:Advance(1/60,physics)
    assert(physics.sensorCalls==1 and input.cursor==3 and physics.motion.sensorReady)
    Close(physics.motion.sensorBaseX,.2); Close(physics.motion.targetX,0)
    input:Update(.26,true,false)
    assert(not input:Ingest(snapshot) and not input:IsAvailable())
    input:Advance(1/60,physics); assert(not physics.motion.sensorReady)
end)

Test("逐帧与每四样本批次的运动和惯性完全一致", function()
    local live, a = Ready()
    local batch, b = Ready()
    for first = 2, 118, 4 do
        local values = {}
        local ix, iy = 0, 0
        for index = first, first + 3 do
            local value = Sample(index,.7*math.sin(index/4),.35*math.cos(index/7))
            values[#values+1] = value
            live:Update(1/60,true,false)
            assert(live:Ingest(Snapshot(index,{value})))
            local x,y=live:Advance(1/60,a); ix,iy=ix+x,iy+y
        end
        batch:Update(0,true,false)
        assert(batch:Ingest(Snapshot(first,values)))
        local jx,jy=0,0
        for _=1,4 do local x,y=batch:Advance(1/60,b); jx,jy=jx+x,jy+y end
        Compare(a.motion,b.motion); Close(ix,jx); Close(iy,jy)
    end
    Close(a.stepTime,b.stepTime)
end)

Test("120Hz输入在60Hz物理步内拆分；每步时间和惯性守恒", function()
    local input, physics = Ready(1/120)
    local reference = Motion.New()
    reference:Sensor(0,0,1/120); reference:Step(1/120)
    for first=2,120,2 do
        local values, ix, iy = {}, 0, 0
        for index=first,first+1 do
            local value=Sample(index,.6*math.sin(index/6),.4*math.sin(index/9),1/120)
            values[#values+1]=value
            local dx,dy=reference:Sensor(value.ax,value.ay,value.dt); reference:Move(dx,dy)
            local x,y=reference:Step(value.dt); ix,iy=ix+x,iy+y
        end
        assert(input:Ingest(Snapshot(first,values)))
        local before=physics.stepTime
        local x,y=input:Advance(1/60,physics)
        Close(physics.stepTime-before,1/60); Close(x,ix); Close(y,iy); Compare(physics.motion,reference)
    end
end)

Test("跨物理步样本只Sensor一次，空队列也只推进所需时长", function()
    local input, physics=Ready()
    assert(input:Ingest(Snapshot(2,{Sample(2,.7,0,1/30)})))
    local before=physics.stepTime
    input:Advance(1/60,physics); input:Advance(1/60,physics)
    assert(physics.sensorCalls==2)
    input:Advance(.011,physics); Close(physics.stepTime-before,1/30+.011)
end)

Test("触摸拥有目标；按住期间游标继续前进，释放后不补播", function()
    local input, physics=Ready()
    physics.motion:Begin(); physics.motion:Move(.3,-.2)
    input:Update(0,true,true)
    assert(input:Ingest(Snapshot(2,{Sample(2,-1,.8),Sample(3,1,-.8)})))
    input:Advance(1/60,physics)
    Close(physics.motion.targetX,.3); Close(physics.motion.targetY,-.2)
    assert(input.cursor==3 and physics.sensorCalls==1)
    physics.motion:End(); input:Update(0,true,false)
    assert(input:Ingest(Snapshot(3,{Sample(2,-1),Sample(3,1)})))
    input:Advance(1/60,physics); assert(physics.sensorCalls==1)
    assert(input:Ingest(Snapshot(4,{Sample(4,.8)})))
    input:Advance(1/60,physics); Close(physics.motion.targetX,0)
    assert(input:Ingest(Snapshot(5,{Sample(5,-.8)})))
    input:Advance(1/60,physics); assert(physics.motion.targetX<0)
end)

Test("暂停和Reset清队列但保留cursor；新样本先校准", function()
    local input, physics=Ready()
    input:Update(0,false,false)
    assert(input:Ingest(Snapshot(2,{Sample(2,.7),Sample(3,-.7)})))
    assert(input.cursor==3 and #input.queue==0)
    input:Update(0,true,false)
    assert(input:Ingest(Snapshot(3,{Sample(2,.7),Sample(3,-.7)})))
    input:Advance(1/60,physics); assert(physics.sensorCalls==1)
    assert(input:Ingest(Snapshot(4,{Sample(4,.7)}))); input:Advance(1/60,physics)
    Close(physics.motion.targetX,0)
    input:Reset(); assert(input.cursor==4)
    assert(input:Ingest(Snapshot(5,{Sample(4,.7)}))); input:Advance(1/60,physics)
    assert(physics.sensorCalls==2)
end)

Test("断流回中保留当前位置速度，heartbeat不能伪造新样本", function()
    local input, physics=Ready()
    input:Ingest(Snapshot(2,{Sample(2,.8)})); input:Advance(1/60,physics)
    local x=physics.motion.x; assert(x>0)
    input:Update(.24,true,false); assert(input:IsAvailable())
    input:Ingest(Snapshot(3,{Sample(2,.8)},{sampleAgeMs=260}))
    assert(not input:IsAvailable())
    input:Advance(1/60,physics)
    assert(physics.motion.x>0 and not physics.motion.sensorReady); Close(physics.motion.targetX,0)
    for _=1,120 do input:Advance(1/60,physics) end
    Close(physics.motion.x,0)
    input:Ingest(Snapshot(4,{Sample(3,.4)},{sampleAgeMs=0})); input:Advance(1/60,physics)
    Close(physics.motion.targetX,0)
end)

Test("丢序号/设备/方向变化/resetRevision/session均重新校准", function()
    for _, kind in ipairs({"seq","sampleId","device","angle","reset","session"}) do
        local input,physics=Ready()
        input:Ingest(Snapshot(2,{Sample(2,.8)})); input:Advance(1/60,physics)
        local value,extra=Sample(3,-.8),{}
        if kind=="seq" then value.seq,value.sampleId=5,5
        elseif kind=="sampleId" then value.sampleId=5
        elseif kind=="device" then value.deviceId="other"
        elseif kind=="angle" then value.screenAngle=90
        elseif kind=="reset" then extra.resetRevision=1
        elseif kind=="session" then extra.sessionId="session-b";value.seq,value.sampleId=1,1 end
        assert(input:Ingest(Snapshot(3,{value},extra)))
        input:Advance(1/60,physics)
        Close(physics.motion.targetX,0); Close(physics.motion.sensorBaseX,-.8)
    end
end)

Test("重复sampleId不重复输入，序号仍前进避免下一样本假丢包", function()
    local input,physics=Ready()
    input:Ingest(Snapshot(2,{Sample(2,.7)})); input:Advance(1/60,physics)
    local duplicate=Sample(3,-.7); duplicate.sampleId=2
    input:Ingest(Snapshot(3,{duplicate})); input:Advance(1/60,physics)
    assert(input.cursor==3 and physics.sensorCalls==2)
    local nextValue=Sample(4,-.7);nextValue.sampleId=3
    input:Ingest(Snapshot(4,{nextValue}));input:Advance(1/60,physics)
    assert(physics.sensorCalls==3 and physics.motion.targetX<0)
end)

Test("积压超过150ms跳到最新校准，长dt不补算过去物理", function()
    local input,physics=Ready()
    local values={}
    for i=2,30 do values[#values+1]=Sample(i,i%2==0 and .8 or -.8) end
    input:Ingest(Snapshot(2,values));input:Advance(1/60,physics)
    assert(physics.sensorCalls==2 and input.cursor==30);Close(physics.motion.targetX,0)
    local before=physics.stepTime
    input:Ingest(Snapshot(3,{Sample(31,.4,0,3600)}));input:Advance(1/60,physics)
    Close(physics.stepTime-before,1/60);Close(physics.motion.targetX,0)
end)

Test("settings按revision仅交付一次，倍率独立，翻轴清旧基线", function()
    local input,physics=Ready()
    local value=input:TakeSettings();assert(value.gain==4 and value.revision==0 and not input:TakeSettings())
    input:Ingest(Snapshot(2,{Sample(2,.2,.1)}));assert(not input:TakeSettings());input:Advance(1/60,physics)
    local target=physics.motion.targetX
    input:Ingest(Snapshot(3,{}, {settings={gain=8.125,invertX=false,invertY=false,revision=1}}))
    value=input:TakeSettings();assert(value.gain==8.25 and value.revision==1 and not input:TakeSettings())
    physics.motion:SetSensorGain(value.gain);Close(physics.motion.targetX,target)
    input:Ingest(Snapshot(4,{Sample(3,.4)}, {settings={gain=8.25,invertX=true,invertY=false,revision=2}}))
    input:Advance(1/60,physics);Close(physics.motion.sensorBaseX,-.4);Close(physics.motion.targetX,0)
end)

Test("非法快照原子拒绝，不推进generation或cursor", function()
    local input,physics=Ready()
    local bad=Sample(2,.7);bad.ay=0/0
    assert(not input:Ingest(Snapshot(2,{bad})))
    assert(input.generation==1 and input.cursor==1)
    assert(not input:Ingest(Snapshot(2,{Sample(3,.7),Sample(2,.7)})))
    assert(not input:Ingest(Snapshot(2,{}, {settings={gain=math.huge,invertX=false,invertY=false,revision=1}})))
    assert(input:Ingest(Snapshot(2,{Sample(2,.7)})));input:Advance(1/60,physics)
    assert(physics.motion.targetX>0)
    local x,y=input:Advance(0/0,physics);Close(x,0);Close(y,0)
end)

Test("Node停止快照立即断流，不能继续保留摇晃目标", function()
    local input,physics=Ready()
    input:Ingest(Snapshot(2,{Sample(2,.8)}));input:Advance(1/60,physics)
    assert(physics.motion.targetX>0)
    input:Ingest(Snapshot(3,{}, {stopped=true}))
    assert(not input:IsAvailable() and input.reason=="stopped")
    input:Advance(1/60,physics);Close(physics.motion.targetX,0)
end)

Test("无WiFi时不会逐帧清掉原生体感基线", function()
    local input,physics=Input.New(),Physics()
    input:Update(0,true,false);input:Advance(1/60,physics)
    physics:Sensor(0,0,1/60);input:Update(1/60,true,false);input:Advance(1/60,physics)
    assert(physics.motion.sensorReady)
    physics:Sensor(.7,0,1/60);input:Update(1/60,true,false);input:Advance(1/60,physics)
    assert(physics.motion.targetX>0 and physics.motion.x>0)
end)

Test("长时间有余量的队列及时压缩，空age不提供可用输入", function()
    local input,physics=Ready(1/120)
    local seq=2
    input:Ingest(Snapshot(seq,{Sample(seq,.1,0,1/120)}))
    for _=1,300 do
        seq=seq+1
        input:Ingest(Snapshot(seq,{Sample(seq,.1,0,1/120)}))
        input:Advance(1/120,physics)
        assert(#input.queue<=130)
    end
    local value=Snapshot(seq+1,{Sample(seq,.1,0,1/120)});value.sampleAgeMs=nil
    input:Ingest(value);assert(not input:IsAvailable())
end)

Test("双轴反转只作用一次体感映射，正输入变负目标且触摸仍按原方向", function()
    local input,physics,reference=Input.New(),Physics(),Motion.New()
    local settings={gain=6,invertX=true,invertY=true,revision=1}
    input:Update(0,true,false)
    assert(input:Ingest(Snapshot(1,{Sample(1,0,0)},{settings=settings})))
    local received=input:TakeSettings()
    assert(received and received.invertX and received.invertY)
    physics.motion:SetSensorGain(received.gain);reference:SetSensorGain(received.gain)
    input:Advance(1/60,physics)
    reference:Sensor(0,0,1/60);reference:Step(1/60)
    assert(input:Ingest(Snapshot(2,{Sample(2,.18,.12)},{settings=settings})))
    input:Advance(1/60,physics)
    local dx,dy=reference:Sensor(-.18,-.12,1/60)
    reference:Move(dx,dy);reference:Step(1/60)
    assert(physics.motion.targetX<0 and physics.motion.targetY<0)
    Compare(physics.motion,reference)
    physics.motion:Begin();reference:Begin()
    physics.motion:Move(.08,.06);reference:Move(.08,.06)
    local targetX,targetY=physics.motion.targetX,physics.motion.targetY
    assert(targetX>0 and targetY>0)
    input:Update(0,true,true)
    assert(input:Ingest(Snapshot(3,{Sample(3,1,.8)},{settings=settings})))
    input:Advance(1/60,physics);reference:Step(1/60)
    assert(input.cursor==3 and physics.sensorCalls==2)
    Close(physics.motion.targetX,targetX);Close(physics.motion.targetY,targetY)
    Compare(physics.motion,reference)
end)

function Tests.Run()
    for _, case in ipairs(cases) do
        local ok, message=pcall(case.run)
        if not ok then error("[SensorLabInput] "..case.name.."："..tostring(message)) end
    end
    return #cases
end
return Tests
