-- 保留全局CCD；仅对本步可能跨过对方真实最薄fixture的动态体启用bullet。
-- 共同平移远离瓶壁时不构成相对扫掠；预测触壁体保留bullet覆盖同一步反弹后的新接触。
local Shapes = require("Bottle.Shapes")
local CCD = {}
local GUARD_SECONDS = .1
local SWEEP_FRACTION = .5

---@class BottleCCDWall
---@field ax number
---@field ay number
---@field bx number
---@field by number
---@field nx number 外法线
---@field ny number

---@class BottleCCDSample
---@field record BottleBody
---@field uid number
---@field x number
---@field y number
---@field vx number
---@field vy number
---@field spin number 本步角点扫掠长度，米
---@field travel number 本步中心扫掠长度，米
---@field envelope number
---@field thickness number
---@field gravity number
---@field enabled boolean
---@field dynamic boolean
---@field sensor boolean
---@field valid boolean 采样与几何是否可用于有界数值风险判断
---@field shape string
---@field radius number
---@field reason string 只读诊断：本步开启原因
---@field partnerUid number?
---@field pairSweep number?

---@class BottleCCDState
---@field samples BottleCCDSample[]
---@field records table<BottleBody,BottleCCDSample>
---@field neighbors integer[][]
---@field lengths integer[]
---@field degree integer[]
---@field selected boolean[]
---@field oldSelected boolean[]
---@field selectedEdge integer[]
---@field oldEdge integer[]
---@field edgeLeft integer[]
---@field edgeRight integer[]
---@field edgeSweep number[]
local State = {}
State.__index = State

---@return BottleCCDState
local function NewState()
    return setmetatable({samples={},records=setmetatable({}, {__mode="k"}),neighbors={},lengths={},degree={},
        selected={},oldSelected={},selectedEdge={},oldEdge={},edgeLeft={},edgeRight={},edgeSweep={}}, State)
end

---@param value number?
---@return boolean
local function Number(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

---@param value number?
---@return boolean
local function Finite(value)
    -- 当前Windows Runtime实测NaN==NaN可返回true；字符串兜底与ShakeMotion保持一致。
    return Number(value) and not tostring(value):lower():find("nan",1,true)
end

-- 凸片沿每条边法线的最小投影宽度；圆用直径。不能用整个图案的包络代替细枝/刀柄厚度。
---@param shape string
---@param radius number
---@return number?
function CCD.Thickness(shape, radius)
    if not Finite(radius) or radius<=0 then return nil end
    if shape=="circle" then return 2*radius end
    local profile = Shapes.profiles[shape]
    if not profile then return nil end
    local minimum = math.huge
    for _, polygon in ipairs(profile.polygons or {}) do
        if #polygon<6 or #polygon%2~=0 then return nil end
        for index=1,#polygon,2 do
            local following=index+2
            if following>#polygon then following=1 end
            local ax,ay=polygon[index],polygon[index+1]
            local dx,dy=polygon[following]-ax,polygon[following+1]-ay
            local length=math.sqrt(dx*dx+dy*dy)
            if length>1e-12 then
                local low,high=math.huge,-math.huge
                for vertex=1,#polygon,2 do
                    local projection=(-dy*polygon[vertex]+dx*polygon[vertex+1])/length
                    low,high=math.min(low,projection),math.max(high,projection)
                end
                minimum=math.min(minimum,(high-low)*radius/8)
            end
        end
    end
    for _, circle in ipairs(profile.circles or {}) do
        minimum=math.min(minimum,2*circle.radius*radius/8)
    end
    if not Finite(minimum) or minimum<=1e-9 then return nil end
    return minimum
end

---@param record BottleBody
function CCD.Guard(record)
    record.ccdGuardRemaining=math.max(record.ccdGuardRemaining or 0,GUARD_SECONDS)
end

---@param x number
---@param y number
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@return number,number,number
local function SegmentDistance(x,y,ax,ay,bx,by)
    local dx,dy=bx-ax,by-ay
    local lengthSquared=dx*dx+dy*dy
    local along=lengthSquared>0 and math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy)/lengthSquared)) or 0
    local nearX,nearY=ax+along*dx,ay+along*dy
    return (x-nearX)^2+(y-nearY)^2,nearX,nearY
end

---@param a BottleCCDSample
---@param edges BottleCCDWall[]?
---@param dt number
---@param gx number
---@param gy number
---@param threshold number
---@return boolean
local function WallRisk(a,edges,dt,gx,gy,threshold)
    if not edges then return false end
    -- Box2D半隐式积分：重力先改变速度再积分位置，不能漏掉加速器的实际gravityScale。
    local dx,dy=a.vx*dt+gx*a.gravity*dt*dt,a.vy*dt+gy*a.gravity*dt*dt
    local endX,endY=a.x+dx,a.y+dy
    local radius=a.envelope+a.spin
    for _, edge in ipairs(edges) do
        local distance,nearX,nearY=SegmentDistance(a.x,a.y,edge.ax,edge.ay,edge.bx,edge.by)
        local toward=(nearX-a.x)*dx+(nearY-a.y)*dy
        if distance<1e-18 then toward=dx*edge.nx+dy*edge.ny
        else toward=toward/math.sqrt(distance) end
        -- 不给贴壁静止或正离壁的物体开启；角点本步仍可能扫入墙体。
        if 2*(math.max(0,toward)+a.spin)>threshold then
            local ex,ey=edge.bx-edge.ax,edge.by-edge.ay
            local cross=dx*ey-dy*ex
            local touching=false
            if math.abs(cross)>1e-18 then
                local qx,qy=edge.ax-a.x,edge.ay-a.y
                local t,u=(qx*ey-qy*ex)/cross,(qx*dy-qy*dx)/cross
                touching=t>=0 and t<=1 and u>=0 and u<=1
            end
            if not touching then
                distance=math.min(distance,SegmentDistance(endX,endY,edge.ax,edge.ay,edge.bx,edge.by),
                    SegmentDistance(edge.ax,edge.ay,a.x,a.y,endX,endY),
                    (SegmentDistance(edge.bx,edge.by,a.x,a.y,endX,endY)))
                touching=distance<=radius*radius
            end
            if touching then return true end
        end
    end
    return false
end

---@param a BottleCCDSample
---@param b BottleCCDSample
---@param dt number
---@param gravityLength number
---@return boolean,number
local function Risk(a,b,dt,gravityLength)
    -- 未知动态端已强制bullet；未知运动学端仍须保护动态邻居。
    -- 缺失可靠运动/几何时无法证明距离上界，不能对NaN或错误类型继续算术。
    if a.valid==false or b.valid==false then return true,0 end
    local vx,vy=a.vx-b.vx,a.vy-b.vy
    local speedSquared=vx*vx+vy*vy
    local extra=a.spin+b.spin+gravityLength*math.abs(a.gravity-b.gravity)*dt*dt
    local linearUpper=(math.abs(vx)+math.abs(vy))*dt
    -- 若连L1扫掠上界都达不到原厚度阈值，原欧氏扫掠必定无风险。
    -- 裕量只防粗筛舍入；平方溢出仍走原sqrt路径，不改变其数值行为。
    if speedSquared<math.huge and (linearUpper+extra)*(1+1e-12)<=SWEEP_FRACTION*math.min(a.thickness,b.thickness) then
        return false,0
    end
    local upperReach=(a.envelope+b.envelope+linearUpper+extra)*(1+1e-12)
    local dx,dy=a.x-b.x,a.y-b.y
    local distanceSquared=dx*dx+dy*dy
    -- L1界及舍入裕量仅粗筛远对，最终仍用原式；平方溢出时保留原sqrt路径。
    if speedSquared<math.huge and distanceSquared>upperReach*upperReach then return false,0 end
    local sweep=math.sqrt(speedSquared)*dt+a.spin+b.spin
        +gravityLength*math.abs(a.gravity-b.gravity)*dt*dt
    local reach=a.envelope+b.envelope+sweep
    if distanceSquared>reach*reach then return false,sweep end
    return sweep>SWEEP_FRACTION*math.min(a.thickness,b.thickness),sweep
end

---@param state BottleCCDState
---@param samples BottleCCDSample[]
---@param index integer
---@param edge integer
local function Select(state,samples,index,edge)
    if state.selected[index] then return end
    state.selected[index],state.selectedEdge[index]=true,edge
    local neighbors=state.neighbors[index]
    for cursor=1,state.lengths[index] do
        ---@type integer
        local current=neighbors[cursor]
        ---@type integer
        local other=state.edgeLeft[current]==index and state.edgeRight[current] or state.edgeLeft[current]
        if samples[other].dynamic and not state.selected[other] then state.degree[other]=state.degree[other]-1 end
    end
    state.degree[index]=0
end

---@param state BottleCCDState
---@param samples BottleCCDSample[]
---@param count integer
---@param dt number
---@param gravityLength number
local function Cover(state,samples,count,dt,gravityLength)
    for index=1,count do
        state.neighbors[index]=state.neighbors[index] or {}
        state.lengths[index],state.degree[index]=0,0
        state.selected[index],state.oldSelected[index]=samples[index].enabled,samples[index].enabled
        state.selectedEdge[index],state.oldEdge[index]=0,0
    end
    local edges=0
    for first=1,count do
        local a=samples[first]
        for second=first+1,count do
            local b=samples[second]
            if not (a.enabled and a.dynamic) and not (b.enabled and b.dynamic)
                and not a.sensor and not b.sensor and (a.dynamic or b.dynamic) then
                local risk,sweep=Risk(a,b,dt,gravityLength)
                if risk then
                    edges=edges+1
                    state.edgeLeft[edges],state.edgeRight[edges],state.edgeSweep[edges]=first,second,sweep
                    state.lengths[first],state.lengths[second]=state.lengths[first]+1,state.lengths[second]+1
                    state.neighbors[first][state.lengths[first]]=edges
                    state.neighbors[second][state.lengths[second]]=edges
                    if a.dynamic then state.degree[first]=state.degree[first]+1 end
                    if b.dynamic then state.degree[second]=state.degree[second]+1 end
                end
            end
        end
    end
    -- 运动学端不承担动态CCD保护；先处理这些必须选择动态端的风险边。
    for edge=1,edges do
        ---@type integer,integer
        local left,right=state.edgeLeft[edge],state.edgeRight[edge]
        if not samples[left].dynamic then Select(state,samples,right,edge)
        elseif not samples[right].dynamic then Select(state,samples,left,edge) end
        -- 同一风险图按原UID顺序重放旧选择；风险边不再求值或分配pair表。
        if not (state.oldSelected[left] and samples[left].dynamic)
            and not (state.oldSelected[right] and samples[right].dynamic) then
            local a,b=samples[left],samples[right]
            local chosen=left
            if not a.dynamic or (b.dynamic and a.spin+a.travel<b.spin+b.travel) then chosen=right end
            state.oldSelected[chosen],state.oldEdge[chosen]=true,edge
        end
    end
    for _=1,count do
        local best,bestDegree,bestRatio=0,0,-1
        for index=1,count do
            local degree=state.degree[index]
            if not state.selected[index] and degree>0 then
                local sample=samples[index]
                local ratio=(sample.spin+sample.travel)/sample.thickness
                -- UID已升序；完全相同时自然保留较小UID。
                if degree>bestDegree or (degree==bestDegree and ratio>bestRatio) then
                    best,bestDegree,bestRatio=index,degree,ratio
                end
            end
        end
        if best==0 then break end
        local edge=0
        for cursor=1,state.lengths[best] do
            ---@type integer
            local candidate=state.neighbors[best][cursor]
            ---@type integer
            local other=state.edgeLeft[candidate]==best and state.edgeRight[candidate] or state.edgeLeft[candidate]
            if not (state.selected[other] and samples[other].dynamic) then edge=candidate;break end
        end
        Select(state,samples,best,edge)
    end
    local selectedCount,oldCount=0,0
    for index=1,count do
        if state.selected[index] then selectedCount=selectedCount+1 end
        if state.oldSelected[index] then oldCount=oldCount+1 end
    end
    -- 最大度贪心并非最优覆盖；同采样不比旧策略更多，相等时保持旧选择。
    local selected,selectedEdge=state.selected,state.selectedEdge
    if selectedCount>=oldCount then selected,selectedEdge=state.oldSelected,state.oldEdge end
    for index=1,count do
        local sample=samples[index]
        if selected[index] and not sample.enabled then
            ---@type integer
            local edge=selectedEdge[index]
            ---@type integer
            local other=state.edgeLeft[edge]==index and state.edgeRight[edge] or state.edgeLeft[edge]
            sample.reason=samples[other].valid==false and "unknown-neighbor" or "relative"
            sample.partnerUid,sample.pairSweep=samples[other].uid,state.edgeSweep[edge]
        end
        sample.enabled=selected[index]
    end
end

---@param sim BottlePhysics
---@param dt number
function CCD.Update(sim,dt)
    local state=sim.ccdState
    if not state then state=NewState();sim.ccdState=state end
    local samples=state.samples
    local gravity=sim.world.gravity
    local gx,gy=gravity.x,gravity.y
    local gravityLength=Number(gx) and Number(gy) and math.sqrt(gx*gx+gy*gy) or 0
    local timeValid=Finite(dt) and dt>0
    local worldValid=timeValid and Finite(gx) and Finite(gy) and Finite(gravityLength)
    local count,minimumThickness=0,math.huge
    for _, record in pairs(sim.bodies) do
        local sample=state.records[record]
        if not sample then
            sample={record=record} --[[@as BottleCCDSample]]
            state.records[record]=sample
        end
        if sample.shape~=record.shape or sample.radius~=record.radius then
            sample.shape,sample.radius=record.shape,record.radius
            sample.thickness=CCD.Thickness(record.shape,record.radius) or 0
        end
        local position,velocity=record.node.position2D,record.body.linearVelocity
        -- tolua Vector2成员访问跨Lua/C++；每微步每字段只读取一次。
        local x,y,vx,vy=position.x,position.y,velocity.x,velocity.y
        local motion=sim.expansion.states[record.uid]
        local angular=record.body.angularVelocity
        local scale=record.body.gravityScale
        -- 先逐字段保留类型/无穷检查，再对传播和做一次字符串NaN兜底；不再每字段格式化。
        local valid=worldValid and Number(x) and Number(y)
            and Number(vx) and Number(vy) and Number(angular)
            and Number(scale) and Number(record.envelope)
            and record.envelope>0 and sample.thickness>0
            and not tostring(x+y+vx+vy+angular+scale+record.envelope)
                :lower():find("nan",1,true)
        sample.uid,sample.x,sample.y=record.uid,x,y
        sample.valid=valid
        sample.vx,sample.vy=vx,vy
        sample.envelope,sample.gravity=record.envelope,scale
        sample.dynamic=not (motion and motion.anchored)
        sample.sensor=record.sensor==true
        if valid and not sample.sensor then minimumThickness=math.min(minimumThickness,sample.thickness) end
        -- 原生实测angularVelocity为rad/s；node.rotation2D才使用度，不能在此重复换算。
        sample.spin=valid and math.abs(angular)*record.envelope*dt or 0
        sample.travel=valid and math.sqrt(vx*vx+vy*vy)*dt or 0
        local guarded=(record.newbornRemaining or 0)>0 or (record.ccdGuardRemaining or 0)>0
        sample.enabled=record.soft~=nil or record.sensor or not valid or guarded
            or (motion~=nil and (motion.flight~=nil or motion.dashRemaining>0 or #motion.rotations>0))
        sample.reason=not valid and "unknown" or record.soft~=nil and "soft"
            or record.sensor and "sensor" or guarded and "guard"
            or sample.enabled and "motion" or "slow"
        sample.partnerUid,sample.pairSweep=nil,nil
        record.ccdGuardRemaining=math.max(0,(record.ccdGuardRemaining or 0)-(timeValid and dt or 0))
        count=count+1;samples[count]=sample
    end
    for index=#samples,count+1,-1 do samples[index]=nil end
    -- 瓶内最多100个物品；UID顺序仅用于确定风险边两端中选哪一个，不读玩法随机数。
    table.sort(samples,function(a,b) return a.uid<b.uid end)
    for _, sample in ipairs(samples) do
        -- 反弹最多把本体扫掠反向，因而以两倍绝对扫掠保守界定新相对运动。
        -- 使用所有实体最薄fixture，避免宽体撞壁反弹后漏掉旁边细枝；与Risk共用同一阈值。
        if not sample.enabled and sample.dynamic and not sample.sensor then
            local reboundSweep=2*(sample.travel+sample.spin+gravityLength*math.abs(sample.gravity)*dt*dt)
            if reboundSweep>SWEEP_FRACTION*minimumThickness
                and WallRisk(sample,sim.ccdWalls,dt,gx,gy,SWEEP_FRACTION*minimumThickness) then
                sample.enabled,sample.reason=true,"wall"
            end
        end
    end
    Cover(state,samples,count,dt,gravityLength)
    local enabled=0
    for _, sample in ipairs(samples) do
        if sample.enabled then enabled=enabled+1 end
        for _, part in ipairs(sample.record.parts) do
            if part.body.bullet~=sample.enabled then part.body.bullet=sample.enabled end
        end
    end
    sim.ccdEnabledCount,sim.ccdBodyCount=enabled,count
end

return CCD
