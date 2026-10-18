local Motion=require("Bottle.TutorialHandMotion")
local Tests={}
local bounds={x=0,y=0,w=402,h=874}
local targets={{x=258,y=130,w=132,h=54},{x=230,y=814,w=160,h=48},
    {x=22,y=670,w=144,h=44},{x=32,y=74,w=292,h=78},{x=16,y=202,w=370,h=458}}
local function close(a,b) return math.abs(a-b)<.00001 end

function Tests.Run()
    local passed=0
    -- Screen-edge attachment, fingertip visibility, and no vertical overflow.
    for _,target in ipairs(targets) do
        local p=Motion.Layout({},bounds,target,1)
        local sleeve=p.x+p.flipX*p.w*.985
        assert(p.edge=="right" and sleeve>=402 or p.edge=="left" and sleeve<=0)
        assert(p.tipX>=0 and p.tipX<=402 and p.y>=0 and p.y+p.h<=874)
        passed=passed+1
    end
    local heart=Motion.Layout({hand="heart"},bounds,targets[1],1)
    assert(heart.edge=="bottom" and heart.y+heart.h>874 and heart.tipY<874)
    assert(heart.x+heart.w*.252>0 and heart.x+heart.w*.876<402)
    passed=passed+1
    local nails=Motion.Layout({hand="nails"},bounds,targets[1],1)
    assert(nails.asset=="nails" and nails.edge=="right" and nails.x+nails.w>402)
    assert(close(nails.w,nails.h*2) and nails.tipX<402 and nails.y+nails.h<874)
    assert(nails.offX>0 and nails.offY==0);passed=passed+1
    -- The two annotated arrows must retain their tip and connect to the requested edge.
    for _,case in ipairs({{edge="left",angle=-32,x=95,y=181},
        {edge="right",angle=35,x=280,y=700}}) do
        local p=Motion.Layout({handEdge=case.edge,handAngle=case.angle},bounds,
            {x=case.x,y=case.y,w=0,h=0},1)
        local ca,sa=math.cos(p.angle),math.sin(p.angle)
        local tx=p.x+ca*p.w*.125*p.flipX-sa*p.h*.327
        local ty=p.y+sa*p.w*.125*p.flipX+ca*p.h*.327
        assert(close(tx,case.x) and close(ty,case.y))
        assert(case.edge=="left" and p.sleeveX<0 or case.edge=="right" and p.sleeveX>402)
        assert(p.sleeveY>p.tipY) -- arm extends downward from the fingertip
        passed=passed+1
    end
    local orbit={handEdge="left",circle={cx=190,cy=420,rx=55,ry=60,period=2.2}}
    local demo=Motion.New();demo:Request("running",orbit);demo:Update(.55)
    local circleA=demo:Pose(bounds,targets[5],1)
    assert(close(circleA.tipX,190) and close(circleA.tipY,480))
    demo:Request("running",orbit);demo:Update(.55)
    local circleB=demo:Pose(bounds,targets[5],1)
    assert(close(circleB.tipX,135) and close(circleB.tipY,420))
    assert(close(circleA.w,circleB.w) and circleA.edge=="left")
    demo:Update(1.1);local circleC=demo:Pose(bounds,targets[5],1)
    assert(close(circleC.tipX,245) and close(circleC.tipY,420));passed=passed+1
    local m=Motion.New();m:Request("welcome",{hand="heart"});m:Update(.16)
    local before=m:Progress();m:Request("goal",{});assert(close(m:Progress(),before))
    m:Update(.11);assert(m.phase=="out" and m.current.key=="welcome" and m:Progress()<before)
    m:Update(.11);assert(m.phase=="in" and m.current.key=="goal" and m:Progress()==0)
    m:Update(.32);assert(m.phase=="idle" and m:Progress()==1);passed=passed+1
    m:Request("start",{});m:Update(.1);local t=m.time
    m:Request("latest",{});assert(m.time==t)
    m:Update(2);assert(m.phase=="idle" and m.current.key=="latest");passed=passed+1
    m:Hide();m:Update(.1);local progress=m:Progress()
    m:Hide();m:Hide();assert(close(m:Progress(),progress))
    m:Update(.12);assert(m.phase=="hidden" and not m.current);passed=passed+1
    m:Request("fresh",{});m:Update(.32)
    local p1=m:Pose(bounds,targets[3],1)
    local wide={x=250,y=10,w=402*.75,h=874*.75}
    local target={x=250+22*.75,y=10+670*.75,w=144*.75,h=44*.75}
    local p2=m:Pose(wide,target,.75)
    assert(close(p2.tipX,wide.x+p1.tipX*.75) and m.phase=="idle");passed=passed+1
    m:Hide();m:Request("pending",{});m:Reset();m:Update(2)
    assert(not m.current and not m.desired and m.phase=="hidden");passed=passed+1
    return passed
end
return Tests
