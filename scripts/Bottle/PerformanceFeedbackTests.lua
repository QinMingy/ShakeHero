-- 表现分配回归：无引擎对象、无存档；原生运行时或提供UI类桩的Lua54均可执行。
local Records = require("Bottle.RecordPool")
local Pickup = require("Bottle.CoinPickup")
local Feedback = require("Bottle.ItemFeedback")
local Consume = require("Bottle.ConsumeFeedback")
local PopIn = require("Bottle.PopIn")
local Motion = require("Bottle.TextMotion")
local RelicView = require("Bottle.RelicView")
local RelicLighting = require("Machine.RelicLighting")
local Relics = require("Bottle.Relics")
local UI = require("urhox-libs/UI")
local Tests = {}
---@type {name:string,run:fun()}[]
local cases = {}
local function case(name, run) cases[#cases + 1] = {name=name, run=run} end
local function close(actual, expected) assert(math.abs(actual-expected) < 1e-8, actual.." ~= "..expected) end

---@return BottleCoinPickup
local function pickup()
    return setmetatable({coins={},waiting={},serial=0,targetX=185,targetY=128,
        shakeTargetX=32,shakeTargetY=28}, {__index=Pickup}) --[[@as BottleCoinPickup]]
end

case("coin arrays persist and released records are reused without stale fields", function()
    local p = pickup()
    local coins, waiting = p.coins, p.waiting
    p:Burst(3, 100, 100, "running", 400)
    local previous = {}
    for _, coin in ipairs(p.coins) do previous[coin] = true;rawset(coin,"testStale",42) end
    local departed, arrived = 0, 0
    local function depart(amount) departed=departed+amount end
    local function arrive(amount) arrived=arrived+amount end
    p:Step(10, depart, arrive)
    assert(p.coins==coins and p.waiting==waiting and not p:Busy())
    close(departed,3);close(arrived,3)
    p:Burst(3, 70, 90, "item", 400)
    for _, coin in ipairs(p.coins) do assert(previous[coin] and rawget(coin,"testStale")==nil and not coin.departed) end
    p:Reset()
    assert(p.coins==coins and p.waiting==waiting and not p:Busy())
end)

case("coin capacity queues complete amounts and callbacks retain birth order", function()
    local p = pickup()
    for _=1,8 do p:Burst(1000,100,100,"running",400) end
    assert(#p.coins==120 and #p.waiting==2)
    local departed,arrived=0,0
    local function depart(amount) departed=departed+amount end
    local function arrive(amount) arrived=arrived+amount end
    p:Step(10,depart,arrive)
    assert(#p.coins==40 and #p.waiting==0)
    p:Step(10,depart,arrive);p:Step(10,depart,arrive)
    close(departed,8000);close(arrived,8000);assert(not p:Busy())
    local order={}
    p:Burst(3,100,100,"item",400)
    p:Step(10,function(amount) order[#order+1]="d"..amount end,
        function(amount) order[#order+1]="a"..amount end)
    assert(table.concat(order,",")=="d1,a1,d1,a1,d1,a1")
end)

case("idle coin stepping allocates no new records and keeps container identity", function()
    local p=pickup()
    local coins,waiting=p.coins,p.waiting
    local before=Pickup.PoolStats()
    for _=1,120 do p:Step(1/60,function() end,function() end) end
    local after=Pickup.PoolStats()
    assert(before.acquired==after.acquired and before.created==after.created)
    assert(p.coins==coins and p.waiting==waiting)
end)

case("item effect and particle records recycle while event identity remains deduplicated", function()
    local f=Feedback.New()
    local effects,particles=f.effects,f.particles
    local event={kind="itemFeedback",action="produce",uid=1,id="chick",x=0,y=1,count=1}
    f:Events({event});local oldEffect=f.effects[1]
    local previous={};for _,p in ipairs(f.particles) do previous[p]=true end
    local count=#f.particles
    f:Events({event});assert(#f.effects==1 and #f.particles==count)
    f:Update(1)
    assert(#f.effects==0 and #f.particles==0)
    f:Events({{kind="itemFeedback",action="produce",uid=2,id="chick",x=1,y=2,count=1}})
    assert(f.effects[1]==oldEffect)
    for _,p in ipairs(f.particles) do assert(previous[p] and p.ownerUid==nil and p.age==0) end
    f:Reset();assert(f.effects==effects and f.particles==particles)
end)

case("warmed feedback bursts keep pool creation counts flat", function()
    local f=Feedback.New()
    local function burst(uid)
        f:Events({{kind="itemFeedback",action="produce",uid=uid,id="chick",x=0,y=1,count=1}})
        f:Update(1)
    end
    burst(1);burst(2)
    local particles,effects=Feedback.PoolStats()
    for index=3,102 do burst(index) end
    local afterParticles,afterEffects=Feedback.PoolStats()
    assert(afterParticles.created==particles.created and afterEffects.created==effects.created)
    assert(afterParticles.reused>particles.reused and afterEffects.reused>effects.reused)
    f:Reset()
end)

case("star samplers and scratch arrays update in place and disappear cleanly", function()
    local f=Feedback.New()
    local y=2.0
    local physics={bodies={[1]={kind="star"}},GetPose=function() return 0,y end} --[[@as any]]
    f:SampleStars(physics,.016)
    local sample,present,ids=f.stars[1],f._present,f._ids
    y=1.7;f:SampleStars(physics,.016)
    assert(f.stars[1]==sample and f._present==present and f._ids==ids and #f.particles>0)
    physics.bodies[1]=nil;f:SampleStars(physics,.016)
    assert(f.stars[1]==nil and #f.particles==0)
    f:Reset()
end)

case("consume records and nested soft poses remain readable while another coroutine pins them", function()
    local f=Consume.New()
    local event={kind="consume",uid=1,id="bacon",reason="consume"}
    local soft={{x=1,y=2,angle=.3,halfLength=.1,halfWidth=.2,u0=0,u1=1}}
    assert(f:CapturePose(event,1,2,.3,soft))
    local old=assert(f.flashes[1])
    local parts=assert(old.soft)
    local part=assert(parts[1])
    local thread=coroutine.create(function()
        local guard <close> = Records.Pin()
        guard:BorrowDeep(f.flashes)
        coroutine.yield()
        guard:Commit();guard:KeepDeep(f.flashes);guard:KeepDeep(f.popups)
    end)
    assert(coroutine.resume(thread))
    f:Update(3)
    assert(#f.flashes==0 and old.id=="bacon" and old.soft==parts and parts[1]==part and part.x==1)
    assert(f:CapturePose({kind="consume",uid=2,id="bacon",reason="consume"},2,3,0,soft))
    local nextFlash=assert(f.flashes[1])
    local nextSoft=assert(nextFlash.soft)
    assert(nextFlash~=old and nextSoft[1]~=part)
    assert(coroutine.resume(thread))
    assert(next(old)==nil and next(part)==nil and next(parts)==nil)
    f:Reset()
end)

case("consume active containers persist through expiry and reset", function()
    local f=Consume.New()
    local flashes,popups,rebounds=f.flashes,f.popups,f.rebounds
    assert(f:CapturePose({kind="consume",uid=4,id="apple",reason="consume"},0,1,0))
    f:Update(3)
    assert(f.flashes==flashes and f.popups==popups and f.rebounds==rebounds)
    assert(#flashes==0 and #popups==0)
    f:Reset();assert(f.flashes==flashes and f.popups==popups and f.rebounds==rebounds)
end)

case("PopIn reuses batch and particle records without changing deterministic burst data", function()
    local first=PopIn.Burst(0,1,"apple",123)
    local identities,expected={},{}
    for i,p in ipairs(first) do identities[p]=true;expected[i]={p.x,p.y,p.vx,p.vy,p.life,p.size} end
    PopIn.StepParticles(first,3);assert(#first==0)
    PopIn.ReleaseBatch(first)
    local second=PopIn.Burst(0,1,"apple",123)
    assert(second==first and #second==11)
    for i,p in ipairs(second) do
        assert(identities[p]);local e=expected[i]
        close(p.x,e[1]);close(p.y,e[2]);close(p.vx,e[3]);close(p.vy,e[4]);close(p.life,e[5]);close(p.size,e[6])
    end
    PopIn.ClearParticles(second);PopIn.ReleaseBatch(second)
end)

case("returning only a PopIn batch leaves transferred active particles intact", function()
    local batch=PopIn.Explosion(0,1,"balloon",321,.4)
    local active={}
    for _,p in ipairs(batch) do active[#active+1]=p end
    local first=active[1]
    PopIn.ReleaseBatch(batch)
    assert(#active==32 and first.x~=nil and first.age==0)
    PopIn.StepParticles(active,.1);assert(active[1]==first and first.age==.1)
    PopIn.ClearParticles(active)
end)

case("PopIn pose and inflation records clear their previous optional fields", function()
    local pose=PopIn.NewPose(1,"apple",.2);pose.x,pose.y=1,2
    PopIn.ReleasePose(pose)
    local nextPose=PopIn.NewPose(2,"ghost",0)
    assert(nextPose==pose and nextPose.x==nil and nextPose.y==nil and nextPose.angleVelocity==0)
    PopIn.ReleasePose(nextPose)
    local inflation=PopIn.NewInflation(.2,.6)
    assert(PopIn.StepInflation(inflation,1))
    PopIn.ReleaseInflation(inflation)
    local other=PopIn.NewInflation(.1,.3)
    assert(other==inflation and other.radius==.1 and other.age==0)
    PopIn.ReleaseInflation(other)
end)

-- 临时替换绘制函数只用于这一同步测试；无论断言是否失败均还原全局。
local function textFixture(work)
    local names={"nvgText","nvgTextBox","nvgTextAlign","nvgFontSize","nvgTextBounds","nvgFontFace",
        "nvgTranslate","nvgRotate","nvgScale",
        "nvgSave","nvgRestore","nvgGlobalAlpha","nvgFillColor","nvgRGBA",
        "NVG_ALIGN_LEFT","NVG_ALIGN_MIDDLE","NVG_ALIGN_CENTER_VISUAL","NVG_ALIGN_CENTER",
        "NVG_ALIGN_RIGHT","NVG_ALIGN_TOP","NVG_ALIGN_BOTTOM","NVG_ALIGN_BASELINE"}
    local saved={}
    for _,name in ipairs(names) do saved[name]=_G[name] end
    local originalVersion,originalScale=UI.GetFontVersion,UI.GetScale
    local version,scale,boundsCalls=1,1,0
    local function noop() end
    nvgText,nvgTextBox,nvgTextAlign,nvgFontSize=noop,noop,noop,noop
    nvgSave,nvgRestore,nvgGlobalAlpha,nvgFillColor,nvgRGBA=noop,noop,noop,noop,noop
    nvgFontFace,nvgTranslate,nvgRotate,nvgScale=noop,noop,noop,noop
    nvgTextBounds=function(_,_,_,value) boundsCalls=boundsCalls+1;return #value*8,{0,0,#value*8,16} end
    NVG_ALIGN_LEFT,NVG_ALIGN_MIDDLE,NVG_ALIGN_CENTER_VISUAL,NVG_ALIGN_CENTER=1,2,4,8
    NVG_ALIGN_RIGHT,NVG_ALIGN_TOP,NVG_ALIGN_BOTTOM,NVG_ALIGN_BASELINE=16,32,64,128
    UI.GetFontVersion=function() return version end
    UI.GetScale=function() return scale end
    local fixture={calls=function() return boundsCalls end,version=function(v) version=v end,
        scale=function(v) scale=v end,text=nvgText,box=nvgTextBox,align=nvgTextAlign,size=nvgFontSize}
    local ok,message=pcall(work,fixture)
    for _,name in ipairs(names) do _G[name]=saved[name] end
    UI.GetFontVersion,UI.GetScale=originalVersion,originalScale
    assert(ok,message)
end

case("TextMotion reuses wrappers and glyph geometry until layout dependencies change", function()
    textFixture(function(fixture)
        local wrappers={}
        local widget={_className="Label",props={text="A+12"},GetChildren=function() return {} end,
            Render=function(self,vg)
                wrappers[#wrappers+1]=nvgText
                nvgFontSize(vg,16);nvgText(vg,0,0,self.props.text)
            end}
        Motion.AttachTree(widget)
        widget:Render(1)
        local count,glyph=fixture.calls(),widget.textMotionCache.glyphs[1]
        widget:Render(1)
        assert(fixture.calls()==count and wrappers[1]==wrappers[2])
        assert(widget.textMotionCache.glyphs[1]==glyph and widget.textMotionCache.glyphs[2].fixed)
        widget.props.text="B+34";widget:Render(1)
        assert(widget.textMotionCache.glyphs[1]==glyph and fixture.calls()>count)
        count=fixture.calls();fixture.version(2);widget:Render(1);assert(fixture.calls()>count)
        assert(nvgText==fixture.text and nvgTextBox==fixture.box and nvgTextAlign==fixture.align and nvgFontSize==fixture.size)
    end)
end)

case("TextMotion restores engine globals when the underlying render fails", function()
    textFixture(function(fixture)
        local widget={_className="Label",props={},GetChildren=function() return {} end,
            Render=function() error("expected render failure") end} --[[@as any]]
        Motion.AttachTree(widget)
        assert(not pcall(widget.Render,widget,1))
        assert(nvgText==fixture.text and nvgTextBox==fixture.box and nvgTextAlign==fixture.align and nvgFontSize==fixture.size)
    end)
end)

case("TextMotion cache-hit renders have bounded transient allocation", function()
    textFixture(function()
        local widget={_className="Label",props={text="A+12"},GetChildren=function() return {} end,
            Render=function(self,vg) nvgFontSize(vg,16);nvgText(vg,0,0,self.props.text) end}
        Motion.AttachTree(widget)
        for _=1,10 do widget:Render(1) end
        collectgarbage("collect")
        local wasRunning=collectgarbage("isrunning")
        collectgarbage("stop")
        local before=collectgarbage("count")
        local ok,message=pcall(function() for _=1,2000 do widget:Render(1) end end)
        local growth=collectgarbage("count")-before
        if wasRunning then collectgarbage("restart") end
        assert(ok,message)
        assert(growth<8,"cache-hit text allocated "..growth.." KiB / 2000 renders")
    end)
end)

case("consume popup text width is cached and invalidated by font version/scale", function()
    textFixture(function(fixture)
        local Art=require("Bottle.Art")
        local originalItem,originalExtent=Art.Item,Art.ItemExtent
        Art.Item=function() end;Art.ItemExtent=function(_,radius) return radius end
        local f=Consume.New()
        local vg=1 --[[@as any]]
        local ok,message=pcall(function()
            assert(f:CapturePose({kind="consume",uid=1,id="apple",reason="consume"},0,1,0))
            assert(#f.popups==1)
            f:RenderPopups(vg,0,0,50)
            local count=fixture.calls()
            f:RenderPopups(vg,0,0,50);assert(fixture.calls()==count)
            fixture.version(2);f:RenderPopups(vg,0,0,50);assert(fixture.calls()==count+1)
            fixture.scale(2);f:RenderPopups(vg,0,0,50);assert(fixture.calls()==count+2)
        end)
        Art.Item,Art.ItemExtent=originalItem,originalExtent
        f:Reset()
        assert(ok,message)
    end)
end)

-- 使用真正 RelicView 方法；假控件仅替代引擎布局/创建边界，不复制反馈算法。
local function relicFixture()
    local game = {phase="running",elapsed=2,score=11,revision=3,
        relics={spin_reward=true,jungle_hunt=true}}
    local container = {}
    local scroll = {props={},parent=container,visible=true,scrolls=0}
    function scroll:SetVisible(visible) self.visible=visible end
    function scroll:GetAbsoluteLayout() return {x=0,y=0,w=200,h=100} end
    function scroll:GetScroll() return 0,0 end
    local icons,buttons,owned = {},{},{}
    for _,def in ipairs(Relics.list) do
        if game.relics[def.id] then
            owned[#owned+1]=def.id
            local icon={props={width=44,height=44,pointerEvents="none",scale=1,rotate=0},parent=scroll}
            function icon:GetAbsoluteLayout() return {x=0,y=0,w=44,h=44} end
            icons[def.id]=icon
            local button={props={disabled=false}}
            function button:SetDisabled(disabled) self.props.disabled=disabled end
            buttons[#buttons+1]=button
        end
    end
    local view={game=game,relicFeedbackOwner=game,container=container,machineSkin={
        relicGridKey=table.concat(owned,"|"),relicGridScroll=scroll,
        relicIcons=icons,relicButtons=buttons,relicFeedback={},relicTriggerSeen={},
        relicFeedbackVisible=true}}
    RelicView.Reset(view)
    return view,icons,scroll,game
end

case("relic committed events animate each owned icon once including uid zero and delayed settle",function()
    local view,icons,scroll,game=relicFixture()
    game.phase="settle"
    local count=RelicView.Trigger(view,{
        {kind="relicTrigger",id="spin_reward",uid=0},
        {kind="relicTrigger",id="spin_reward",uid=5},
        {kind="relicTrigger",id="jungle_hunt",uid=2},
        {kind="score",id="spin_reward",uid=2},
        {kind="relicTrigger",id="lucky_charm",uid=2},
        {kind="relicTrigger",id="unknown",uid=0}})
    assert(count==2 and icons.spin_reward.props.scale>1 and icons.jungle_hunt.props.scale>1)
    assert(game.elapsed==2 and game.score==11 and game.revision==3)
    assert(scroll.visible and scroll.scrolls==0)
    assert(icons.spin_reward.props.width==44 and icons.spin_reward.props.height==44
        and icons.spin_reward.props.pointerEvents=="none","icon transform leaves layout and input unchanged")
end)

case("relic feedback uses render dt and expires exactly without another rule batch",function()
    local view,icons,_,game=relicFixture()
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    RelicView.Update(view,.045)
    assert(icons.spin_reward.props.scale>1.2 and math.abs(icons.spin_reward.props.rotate)>2)
    local age=view.machineSkin.relicFeedback.spin_reward
    RelicView.Update(view);RelicView.Update(view,0);RelicView.Update(view,-1)
    RelicView.Update(view,0/0);RelicView.Update(view,math.huge)
    assert(view.machineSkin.relicFeedback.spin_reward==age,"sync calls do not double-advance animation")
    RelicView.Update(view,3)
    assert(next(view.machineSkin.relicFeedback)==nil)
    close(icons.spin_reward.props.scale,1);close(icons.spin_reward.props.rotate,0)
    assert(game.elapsed==2,"presentation cannot advance the game clock")
end)

case("rapid relic events restart bounded motion without accumulated zoom or historical queue",function()
    local view,icons=relicFixture()
    for _=1,300 do
        assert(RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0},
            {kind="relicTrigger",id="spin_reward",uid=1}})==1)
        RelicView.Update(view,.015)
        assert(icons.spin_reward.props.scale>=.9 and icons.spin_reward.props.scale<=1.35)
        assert(math.abs(icons.spin_reward.props.rotate)<=12)
        local count=0;for _ in pairs(view.machineSkin.relicFeedback) do count=count+1 end
        assert(count==1)
    end
    RelicView.Update(view,.5)
    assert(next(view.machineSkin.relicFeedback)==nil and icons.spin_reward.props.scale==1)
end)

case("hidden relic holder clears active feedback and never replays invisible events",function()
    local view,icons,scroll=relicFixture()
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    RelicView.Update(view,.06)
    RelicView.SetVisible(view,false)
    assert(not scroll.visible and next(view.machineSkin.relicFeedback)==nil)
    assert(icons.spin_reward.props.scale==1 and icons.spin_reward.props.rotate==0)
    assert(RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})==0)
    RelicView.SetVisible(view,true);RelicView.Update(view,.02)
    assert(scroll.visible and icons.spin_reward.props.scale==1 and next(view.machineSkin.relicFeedback)==nil)
end)

case("relic feedback survives worker presentation swaps and resets on new game or import",function()
    local view,icons,_,game=relicFixture()
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    RelicView.Update(view,.04)
    view.game={phase="running",relics={spin_reward=true,jungle_hunt=true}}
    RelicView.Update(view,.02)
    close(view.machineSkin.relicFeedback.spin_reward,.06)
    view.game=game
    RelicView.Update(view)
    close(view.machineSkin.relicFeedback.spin_reward,.06)
    game.relics={spin_reward=true,jungle_hunt=true}
    RelicView.Update(view)
    assert(next(view.machineSkin.relicFeedback)==nil and icons.spin_reward.props.scale==1)
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    local nextGame={phase="prepare",relics={spin_reward=true,jungle_hunt=true}}
    view.game,view.relicFeedbackOwner=nextGame,nextGame
    RelicView.Update(view,.01)
    assert(next(view.machineSkin.relicFeedback)==nil and icons.spin_reward.props.scale==1)
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    RelicView.Reset(view)
    assert(next(view.machineSkin.relicFeedback)==nil and icons.spin_reward.props.rotate==0)
end)

case("lit relic geometry reads the same centered elastic transform as the icon",function()
    local view,icons=relicFixture()
    RelicView.Trigger(view,{{kind="relicTrigger",id="spin_reward",uid=0}})
    RelicView.Update(view,.06)
    local icon=icons.spin_reward --[[@as Widget]]
    local matrix=assert(RelicLighting.Transform({reference=view.container},icon))
    local scale=icon.props.scale
    assert(math.abs(matrix[2])>.01,"lit geometry must also shake")
    close(matrix[1]*matrix[4]-matrix[2]*matrix[3],scale*scale)
    close(matrix[1]*22+matrix[3]*22+matrix[5],22)
    close(matrix[2]*22+matrix[4]*22+matrix[6],22)
    RelicView.Update(view,1)
    matrix=assert(RelicLighting.Transform({reference=view.container},icon))
    close(matrix[1],1);close(matrix[4],1);close(matrix[2],0);close(matrix[3],0)
end)

---@return integer passed
function Tests.Run()
    local passed=0
    for _,entry in ipairs(cases) do
        local ok,message=pcall(entry.run)
        assert(ok,"Bottle.PerformanceFeedbackTests ["..entry.name.."] "..tostring(message))
        passed=passed+1
    end
    return passed
end

return Tests
