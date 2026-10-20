-- 目标牌下缘伸出的像素分段条；结算展示时跟随滚轮逐件递增，
-- 每次增加在条的前沿迸发受重力的像素粒子，并给机台一个轻微屏幕震动。
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local RecordPool=require("Bottle.RecordPool")
local UniformCache=require("Machine.UniformCache")
local uniforms=UniformCache.New()
local burstPools=setmetatable({}, {__mode="k"})
local function burstPool(view)
    local pool=burstPools[view]
    if not pool then pool=RecordPool.New(256);burstPools[view]=pool end
    return pool
end
---@type any
local Progress={count=21}
local yellow={244,193,80,255}
local green={115,222,104,255}

-- 私有随机源：纯表现粒子，不碰玩法随机序列。
local seed=(os.time()*7919+1337)%2147483646+1
local function rand()
    seed=(seed*16807)%2147483647
    return seed/2147483647
end

---@param game BottleGame
---@param displayScore number? 结算展示期间的逐件暂显值；nil 时读真实余额
---@return number value
---@return boolean complete
function Progress.State(game,displayScore)
    local score=displayScore or game.score
    local target=math.max(1,game.target)
    return math.max(0,math.min(1,score/target)),score>=target
end

function Progress.Segment(b,s,index,value)
    local width=(b.w-18*s-2*s*(Progress.count-1))/Progress.count
    local x=b.x+8*s+(index-1)*(width+2*s)
    local left=b.x+8*s
    local filled=left+(b.w-18*s)*value
    local endX=math.min(x+width,filled)
    return {x=x,y=b.y+7*s,w=width,h=12*s,fillX=x,fillW=math.max(0,endX-x)}
end

-- 在进度条前沿迸发一小簇像素粒子；颜色跟随当前黄/绿状态。
---@param view BottleView
---@param x number
---@param y number
---@param complete boolean
---@param delta number 本次增加的分数
function Progress.Burst(view,x,y,complete,delta)
    local list=view.targetBursts
    if not list then list={};view.targetBursts=list end
    local pool=burstPool(view)
    local color=complete and green or yellow
    local count=math.min(26,14+math.floor((delta or 1)*.8))
    for _=1,count do
        local p=pool:Acquire()
        p.x,p.y=x+(rand()*2-1)*6,y+(rand()*2-1)*4
        p.vx,p.vy=(rand()*2-1)*110,-40-rand()*100
        p.size=2+math.floor(rand()*3)
        p.age,p.life,p.color=0,.7+rand()*.5,color
        list[#list+1]=p
    end
end

---@param view BottleView
---@param dt number
function Progress.Update(view,dt)
    local list=view.targetBursts
    if not list then return end
    local pool=burstPool(view)
    dt=math.max(0,dt)
    local count,write=#list,1
    for i=1,count do
        local p=list[i]
        p.age=p.age+dt
        if p.age>=p.life then
            pool:Release(p)
        else
            p.vy=p.vy+360*dt
            p.x=p.x+p.vx*dt
            p.y=p.y+p.vy*dt
            list[write]=p;write=write+1
        end
    end
    for i=write,count do list[i]=nil end
end

function Progress.GetPoolStats(view)
    return burstPool(view):GetStats()
end

---@param view BottleView
---@param vg NVGContextWrapper
function Progress.RenderBurst(view,vg)
    local list=view.targetBursts
    if not list or #list==0 then return end
    nvgSave(vg)
    nvgShapeAntiAlias(vg,0)
    for _,p in ipairs(list) do
        local k=p.age/p.life
        -- 前 60% 保持全亮，后 40% 淡出；加长生命后粒子仍清晰可见。
        local fade=k<.6 and 1 or math.max(0,(1-k)/.4)
        local alpha=math.floor(235*fade)
        nvgBeginPath(vg)
        nvgRect(vg,math.floor(p.x),math.floor(p.y),p.size,p.size)
        nvgFillColor(vg,nvgRGBA(p.color[1],p.color[2],p.color[3],alpha))
        nvgFill(vg)
    end
    nvgRestore(vg)
end

function Progress.Attach(view)
    local m=view.machineSkin
    if view.targetBursts then burstPool(view):ClearActive(view.targetBursts)
    else view.targetBursts={} end
    local bar=UI.ProgressBar{id="targetProgress",value=0,max=1,showLabel=false,
        pointerEvents="none",zIndex=2,borderWidth=0,borderRadius=0} --[[@as any]]
    local lastScore=view.board.displayScore or view.game.score
    function bar:Render(vg)
        local b=self:GetAbsoluteLayout()
        local display=view.board.displayScore
        local value,complete=Progress.State(view.game,display)
        self.props.value=value
        self.props.variant=complete and "success" or "warning"
        local color=complete and green or yellow
        local score=display or view.game.score
        -- 每件收益弹出使暂显值增加一次：前沿粒子 + 轻微屏幕震动。
        if display~=nil and score>lastScore+.000001 then
            local s=m.scale
            local edge=b.x+8*s+(b.w-18*s)*value
            Progress.Burst(view,edge,b.y+13*s,complete,score-lastScore)
            local scene=m.litScene
            if scene and scene.AddShake then
                scene:AddShake((rand()*2-1)*2.6,(rand()*2-1)*2.0)
            end
        end
        lastScore=score
        -- 原大底板-.05 → 独立窄底板-.065 → 亮格-.08 → 目标牌-.11。
        -- 小底板右端也伸到目标牌后面，九宫格与亮格都由真实深度遮挡。
        m.sprites:Panel(vg,"metal",b.x,b.y,b.w,b.h,m.scale,false,-.065)
        local scene=m.litScene
        scene:Layer(-.08)
        scene:Quad("target-progress",b.x,b.y,b.w,b.h)
        local material=scene.materials["target-progress"]
        uniforms:Scalar(material,"progress_value",value)
        uniforms:Vector4(material,"progress_color",color[1]/255,color[2]/255,color[3]/255,1)
    end
    m.targetProgress=bar
    m.placements[#m.placements+1]={widget=bar,rect=L.targetProgress}
    view.container:AddChild(bar)
    local burst=UI.Widget{id="targetBurst",position="absolute",left=0,top=0,
        width="100%",height="100%",pointerEvents="none",zIndex=4} --[[@as any]]
    function burst:Render(vg) Progress.RenderBurst(view,vg) end
    view.container:AddChild(burst)
    return bar
end
return Progress
