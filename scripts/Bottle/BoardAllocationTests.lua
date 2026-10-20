-- 实际Board方法的分配/所有权集成回归；不创建引擎对象，不读写玩家存档。
-- 独立入口 require("Bottle.BoardAllocationTests").Run()；Lua54 runner只替换引擎边界。
local Board = require("Bottle.Board")
local Records = require("Bottle.RecordPool")
local PopIn = require("Bottle.PopIn")
local Consume = require("Bottle.ConsumeFeedback")
local Feedback = require("Bottle.ItemFeedback")
local Items = require("Bottle.Items")
local UI = require("urhox-libs/UI")
local Audio = require("Bottle.Audio")
local Art = require("Bottle.Art")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}
local function case(name, run) cases[#cases+1] = {name=name,run=run} end
local function close(actual, expected) assert(math.abs(actual-expected)<1e-8, actual.." ~= "..expected) end

-- 输入fixture仅提供物品成员和真实姿态；排序、动画触发、缓存和回收均执行产品方法。
local function boardFixture()
    local rows, order, poses, targets = {}, {}, {}, {}
    local game={phase="running",revision=3,score=0,roundScore=0}
    function game:Get(uid) return rows[uid] end
    function game:BottleItems(target)
        target=target or {}
        targets[#targets+1]=target
        for index=#target,1,-1 do target[index]=nil end
        for _,uid in ipairs(order) do
            local item=rows[uid]
            if item and item.location=="bottle" then target[#target+1]=item end
        end
        return target
    end
    local physics={bodies={}}
    function physics:GetPose(uid)
        local pose=assert(poses[uid],"fixture has no pose "..uid)
        return pose.x,pose.y,pose.angle or 0,pose.radius or .3
    end
    function physics:GetSoftPose() return nil end
    local function reset(self) self.calls=(self.calls or 0)+1 end
    local board=setmetatable({game=game,physics=physics,ppu=50,visualX=0,visualY=0,
        coinPickups={Reset=reset},reelCoins={Reset=reset},roundScore={Reset=reset},
        consumeFlash=Consume.New(),itemFeedback=Feedback.New(),
        _appearanceItems={},_presentScratch={},_appearedScratch={},_originsX={},_originsY={}},
        {__index=Board}) --[[@as any]]
    board:ResetEffects();board:ResetPopState()
    local function add(uid,id,x,y)
        rows[uid]={uid=uid,id=id,location="bottle",scale=1}
        order[#order+1]=uid
        poses[uid]={x=x or 0,y=y or 2,angle=0,radius=Items.byId[id].radius}
        physics.bodies[uid]={kind=id}
    end
    return board,rows,poses,targets,add
end

-- 任何fake context都只进入这些Lua替身；保存并恢复所有可达NVG入口。
local function boundary(work)
    local names={"nvgSave","nvgRestore","nvgIntersectScissor","nvgFontFace","nvgTextAlign",
        "nvgFontSize","nvgTextBounds","nvgTranslate","nvgRotate","nvgScale","nvgFillColor","nvgRGBA","nvgText",
        "NVG_ALIGN_LEFT","NVG_ALIGN_MIDDLE"}
    local saved={}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    local pop,resetPitch,itemEvents,statIcon=Audio.Pop,Audio.ResetPopPitch,Audio.ItemEvents,Art.StatIcon
    local fontFace,fontSize,fontVersion=UI.Theme.FontFace,UI.Theme.FontSize,UI.GetFontVersion
    local state={pops=0,pitchResets=0,bounds=0,texts=0,icons=0,version=1,scale=1,face="first",depth=0}
    local function noop() end
    nvgSave=function() state.depth=state.depth+1 end
    nvgRestore=function() state.depth=state.depth-1;assert(state.depth>=0) end
    nvgIntersectScissor,nvgFontFace,nvgTextAlign,nvgTranslate,nvgRotate,nvgScale,nvgFillColor,nvgRGBA=
        noop,noop,noop,noop,noop,noop,noop,noop
    local currentSize=16
    nvgFontSize=function(_,size) currentSize=size end
    nvgTextBounds=function(_,_,_,text) state.bounds=state.bounds+1;return #text*currentSize*.5 end
    nvgText=function() state.texts=state.texts+1 end
    NVG_ALIGN_LEFT,NVG_ALIGN_MIDDLE=1,2
    Audio.Pop=function() state.pops=state.pops+1 end
    Audio.ResetPopPitch=function() state.pitchResets=state.pitchResets+1 end
    Audio.ItemEvents=noop
    Art.StatIcon=function() state.icons=state.icons+1 end
    UI.Theme.FontFace=function(family,weight) return state.face..family..weight end
    UI.Theme.FontSize=function(size) return size*state.scale end
    UI.GetFontVersion=function() return state.version end
    local ok,message=pcall(work,state)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    Audio.Pop,Audio.ResetPopPitch,Audio.ItemEvents,Art.StatIcon=pop,resetPitch,itemEvents,statIcon
    UI.Theme.FontFace,UI.Theme.FontSize,UI.GetFontVersion=fontFace,fontSize,fontVersion
    assert(ok,message)
    assert(state.depth==0,"unbalanced NVG state in actual Board render")
end

case("ResetEffects/ResetPopState preserve containers and return all owned records",function()
    boundary(function()
        local board=boardFixture()
        local pool=Records.New(24)
        local fields={"particles","residue","scoreQueue","bursts","burstRings","inflations","dashTrails","dashEmitters"}
        local containers,records={},{}
        for _,field in ipairs(fields) do
            local record=pool:Acquire();record.marker=field
            containers[field]=board[field];board[field][1]=record;records[#records+1]=record
        end
        local maps={"feedbackPopMute","pulses","explodedUids"}
        for _,field in ipairs(maps) do containers[field]=board[field];board[field][1]=true end
        local pop=PopIn.NewPose(1,"apple",0)
        local pops,byUid,present=board.pops,board.popByUid,board.presentUids
        board.pops[1],board.popByUid[1],board.presentUids[1]=pop,pop,true
        board:ResetEffects()
        for _,field in ipairs(fields) do assert(board[field]==containers[field] and next(board[field])==nil) end
        for _,field in ipairs(maps) do assert(board[field]==containers[field] and next(board[field])==nil) end
        for _,record in ipairs(records) do assert(next(record)==nil) end
        assert(pool:GetStats().active==0 and pool:GetStats().free==#fields)
        assert(board.pops[1]==pop and pop.id=="apple","phase refresh must not restart existing item appearance")
        board:ResetPopState()
        assert(board.pops==pops and board.popByUid==byUid and board.presentUids==present)
        assert(next(pops)==nil and next(byUid)==nil and next(present)==nil and next(pop)==nil)
    end)
end)

case("UpdateAppearance reuses scratch and pops once per actual membership change",function()
    boundary(function(state)
        local board,rows,_,targets,add=boardFixture()
        add(3,"apple",.3,2);add(1,"apple",.1,2);add(2,"apple",.2,2)
        local items,appeared,byUid,pops,bursts=board._appearanceItems,board._appearedScratch,board.popByUid,board.pops,board.bursts
        local first,second=board.presentUids,board._presentScratch
        board:UpdateAppearance(.016)
        assert(board.pops[1].uid==1 and board.pops[2].uid==2 and board.pops[3].uid==3)
        board:UpdateAppearance(.1);board:UpdateAppearance(.1)
        assert(state.pops==3 and state.pitchResets==1)
        local poseStats,particleStats=PopIn.PoolStats()
        for _=1,70 do board:UpdateAppearance(.016) end
        local afterPose,afterParticle=PopIn.PoolStats()
        assert(afterPose.acquired==poseStats.acquired and afterParticle.acquired==particleStats.acquired)
        assert(state.pops==3 and #board.pops==0 and #board.bursts==0)
        assert(board._appearanceItems==items and board._appearedScratch==appeared)
        assert(board.popByUid==byUid and board.pops==pops and board.bursts==bursts)
        assert((board.presentUids==first and board._presentScratch==second)
            or (board.presentUids==second and board._presentScratch==first))
        for _,target in ipairs(targets) do assert(target==items) end
        rows[2].location="deck";board:UpdateAppearance(.016)
        rows[2].location="bottle";board:UpdateAppearance(.016)
        assert(state.pops==4 and state.pitchResets==2)
        board:ResetEffects();board:ResetPopState()
    end)
end)

case("DashTrail expiry keeps survivor order and returns records/emitters",function()
    boundary(function()
        local board,_,_,_,add=boardFixture()
        add(1,"calf");add(2,"calf");add(3,"calf")
        local pool=Records.New(8)
        local a,b,c=pool:Acquire(),pool:Acquire(),pool:Acquire()
        a.uid,a.age=1,.19;b.uid,b.age=2,.01;c.uid,c.age=3,.03
        local trails=board.dashTrails
        trails[1],trails[2],trails[3]=a,b,c
        local emitter=pool:Acquire()
        emitter.remaining,emitter.sampleAge,emitter.lastX,emitter.lastY=.1,0,0,0
        board.dashEmitters[1]=emitter
        board.game.phase="settle"
        board:UpdateDashTrails(.02)
        assert(board.dashTrails==trails and #trails==2 and trails[1]==b and trails[2]==c)
        assert(next(a)==nil and next(emitter)==nil and board.dashEmitters[1]==nil)
        board:UpdateDashTrails(.2)
        assert(#trails==0 and next(b)==nil and next(c)==nil and pool:GetStats().active==0)
        board:ResetEffects();board:ResetPopState()
    end)
end)

case("RenderPopups caches measurements and invalidates content/font/context changes",function()
    boundary(function(state)
        local board=boardFixture()
        board:AddRefreshPopup(1,0,1)
        local popup=board.particles[1]
        local vg,otherVG={},{}
        local layout={x=0,y=0,w=370,h=460}
        board:RenderPopups(vg,layout)
        local calls=state.bounds
        assert(calls==2 and state.texts>0)
        board:RenderPopups(vg,layout);assert(state.bounds==calls)
        popup.age,popup.x=.2,.3
        board:RenderPopups(vg,layout);assert(state.bounds==calls)
        popup.value=123
        board:RenderPopups(vg,layout);calls=calls+2;assert(state.bounds==calls)
        state.scale=1.5
        board:RenderPopups(vg,layout);calls=calls+2;assert(state.bounds==calls)
        state.version=2
        board:RenderPopups(vg,layout);calls=calls+2;assert(state.bounds==calls)
        state.face="second"
        board:RenderPopups(vg,layout);calls=calls+2;assert(state.bounds==calls)
        board:RenderPopups(otherVG,layout);calls=calls+2;assert(state.bounds==calls)
        popup.trigger,popup.rewardKind,popup.label="move","permanent",nil
        board:RenderPopups(otherVG,layout);calls=calls+2;assert(state.bounds==calls and state.icons>0)
        board:RenderPopups(otherVG,layout);assert(state.bounds==calls)
        board:ResetEffects();board:ResetPopState()
    end)
end)

case("consecutive balloon resize resumes from the current visual radius before pool reuse",function()
    boundary(function()
        local board,_,poses,_,add=boardFixture()
        add(1,"balloon")
        local base=Items.byId.balloon.radius
        local previous=PopIn.NewInflation(base,base*2)
        PopIn.StepInflation(previous,.2)
        local visual=previous.radius
        assert(visual>base and visual<base*2)
        board.inflations[1]=previous
        poses[1].radius=base*2 -- 刚体已同步最终尺寸，屏幕仍处于膨胀中段。
        board:ApplyEffects({{kind="resize",uid=1,id="balloon",value=3}})
        local current=board.inflations[1]
        close(current.fromRadius,visual);close(current.radius,visual);close(current.age,0)
        close(current.targetRadius,base*3)
        assert(current.fromRadius~=poses[1].radius)
        PopIn.StepInflation(current,.1)
        assert(current.radius>visual and current.radius<base*3)
        board:ResetEffects();board:ResetPopState()
    end)
end)

---@return integer passed
function Tests.Run()
    local passed=0
    for _,entry in ipairs(cases) do
        local ok,message=pcall(entry.run)
        assert(ok,"Bottle.BoardAllocationTests ["..entry.name.."] "..tostring(message))
        passed=passed+1
    end
    return passed
end

return Tests
