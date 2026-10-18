-- Offline observable-contract checks. No engine, preview, saves or filesystem writes.
local source=debug.getinfo(1,"S").source:gsub("^@",""):gsub("\\","/")
local root=source:match("^(.*)/art%-source/machine/deduction/checks%.lua$") or "."
package.path=root.."/scripts/?.lua;"..package.path

local Game=require("Bottle.Game")
local Reels=require("Machine.FlatReelState")
local Layout=require("Machine.LayeredLayout")
local Checks={}
local cases={}
local function near(a,b) return math.abs(a-b)<1e-7 end
local function case(name,run) cases[#cases+1]={name=name,run=run} end

-- Only constructor registration is substituted. Draw and the entire timeline
-- are the production module, using the same native NanoVG call boundaries.
local Note=assert(loadfile(root.."/scripts/Machine/DeductionNote.lua","t",
    setmetatable({require=function(name)
        if name=="urhox-libs/UI" then return {} end
        return require(name)
    end},{__index=_G})))()

local function skipDraft(game)
    local attempts=0
    while game.phase=="draft" do
        attempts=attempts+1
        assert(attempts<=2 and game:Skip(),"could not complete item/relic drafts")
    end
    assert(game.phase=="prepare","draft did not return to preparation")
end

local function settleRound(game)
    assert(game:Start(),"fixture did not start a real round")
    game:Step(game:Duration())
    assert(game.phase=="settle","natural round timer skipped settlement")
    game:SettleStep(Game.SETTLE_DELAY)
    assert(game.phase=="reveal","settlement skipped score presentation")
end

local function beforeFifthReveal()
    local game=Game.New(733)
    for _=1,4 do
        game.score=1000
        settleRound(game)
        assert(#game:RevealStep(100)==0,"ordinary round emitted a payment")
        skipDraft(game)
    end
    game.score=1000
    settleRound(game)
    assert(game.round==5 and game.stage==1 and game.target==40)
    return game
end

case("real rounds 1..10 emit exactly one old-target payment on rounds 5 and 10",function()
    local game=Game.New(953)
    local payments={}
    for round=1,10 do
        game.score=1000
        assert(game.round==round)
        settleRound(game)
        local balance,target=game.score,game.target
        local events=game:RevealStep(100)
        if round%5==0 then
            assert(#events==1 and events[1].kind=="deduction" and events[1].uid==0,
                "successful assessment did not emit one unambiguous payment")
            assert(events[1].value==target,"receipt used the upgraded target")
            assert(near(game.score,balance-target),"event differs from the actual balance debit")
            payments[#payments+1]=events[1].value
        else
            assert(#events==0 and near(game.score,balance),"ordinary reveal charged the player")
        end
        assert(game.phase=="draft")
        assert(#game:RevealStep(100)==0 and near(game.score,balance-(round%5==0 and target or 0)),
            "repeated reveal charged or emitted twice")
        if round<10 then skipDraft(game) end
    end
    assert(#payments==2 and payments[1]==40 and payments[2]==80,
        "round-five/round-ten receipts must show -40 and -80")
    assert(game.stage==3 and game.target==140)
end)

case("insufficient fifth-round balance ends the run without a payment",function()
    local game=beforeFifthReveal()
    game.score=39
    local events=game:RevealStep(100)
    assert(#events==0 and game.phase=="over" and game.score==39,
        "failed assessment emitted a receipt or removed money")
    assert(game.stage==1 and game.target==40)
    assert(#game:RevealStep(100)==0 and game:_FinishReveal()==0,
        "an ended assessment can charge again")
end)

case("exactly enough balance pays once and safely reaches zero",function()
    local game=beforeFifthReveal()
    game.score=40
    local events=game:RevealStep(100)
    assert(#events==1 and events[1].value==40 and game.score==0 and game.phase=="draft")
    local restored=Game.Restore(game:Snapshot())
    assert(restored.score==0 and restored.target==80 and #restored:RevealStep(100)==0,
        "loading the paid draft replayed a transient payment")
end)

case("pending flying coins preserve the full final reveal pause before payment",function()
    local game=beforeFifthReveal()
    local balance=game.score
    for _=1,4 do
        assert(#game:RevealStep(100,true)==0 and game.phase=="reveal" and game.score==balance,
            "busy visual credit allowed an early assessment")
    end
    assert(#game:RevealStep(1.99,false)==0 and game.phase=="reveal",
        "payment omitted the final two-second readable pause")
    local events=game:RevealStep(.02,false)
    assert(#events==1 and events[1].value==40 and game.phase=="draft")
    assert(#game:RevealStep(100,false)==0,"drained presentation emitted twice")
end)

case("receipt rises, remains fully readable for five seconds, then slowly falls",function()
    local note=Note.New()
    assert(not note.active)
    note:Show(40)
    assert(note.active and note.amount==40 and note.text=="-40")
    local start=note:Pose()
    assert(start.y>50 and start.alpha==1)
    note:Tick(.35)
    local rising=note:Pose()
    assert(rising.y>0 and rising.y<start.y,"receipt did not visibly rise")
    note:Tick(.35)
    assert(near(note:Pose().y,0) and note:Pose().alpha==1)
    note:Tick(4.99)
    assert(note.active and near(note:Pose().y,0) and note:Pose().alpha==1,
        "receipt moved or faded before five seconds at the top")
    note:Tick(.01)
    assert(note.active and near(note:Pose().y,0) and note:Pose().alpha==1)
    note:Tick(.5)
    assert(note.active and note:Pose().y>0 and note:Pose().alpha==1,
        "receipt did not begin a readable, slow descent")
    note:Tick(2)
    assert(note.active and note:Pose().y>50 and note:Pose().alpha<1,
        "receipt disappeared before its descent completed")
    note:Tick(.2)
    assert(not note.active,"receipt remained after the fall completed")
end)

case("reset, invalid payments, interrupted receipts and long frames are safe",function()
    local note=Note.New()
    for _,amount in ipairs({0,-40,math.huge,"40"}) do
        note:Show(amount)
        assert(not note.active,"invalid money created a receipt")
    end
    note:Show(0/0)
    assert(not note.active,"NaN created a receipt")
    note:Show(40);note:Tick(3)
    local elapsed=note.elapsed
    note:Tick(-1)
    assert(note.elapsed==elapsed,"negative frame time rewound the receipt")
    note:Show(80)
    assert(note.text=="-80" and note.elapsed==0 and note:Pose().y>50,
        "a new deduction retained the previous amount or phase")
    note:Reset()
    assert(not note.active and note.elapsed==0 and note.text=="" and note.amount==0,
        "new-run reset left a stale receipt")
    note:Show(40);note:Tick(100)
    assert(not note.active and note.elapsed<10,"a suspended frame left the receipt stuck")
end)

-- Record the exact production draw calls, including clipping and hard pixels.
-- The caller can inspect or rasterize this trace without opening a game window.
function Checks.Capture(amount,elapsed)
    local trace={rects={},saves=0,restores=0}
    local path,color,alpha={},nil,1
    local overrides={
        nvgSave=function() trace.saves=trace.saves+1 end,
        nvgRestore=function() trace.restores=trace.restores+1 end,
        nvgIntersectScissor=function(_,x,y,w,h) trace.clip={x=x,y=y,w=w,h=h} end,
        nvgTranslate=function(_,x,y) trace.translation={x=x,y=y} end,
        nvgScale=function(_,x,y) trace.scale={x=x,y=y} end,
        nvgShapeAntiAlias=function(_,value) trace.anti_alias=value end,
        nvgGlobalAlpha=function(_,value) alpha=value;trace.alpha=value end,
        nvgBeginPath=function() path={} end,
        nvgRect=function(_,x,y,w,h) path[#path+1]={x=x,y=y,w=w,h=h} end,
        nvgRGBA=function(r,g,b,a) return {r,g,b,a} end,
        nvgFillColor=function(_,value) color=value end,
        nvgFill=function()
            for _,rect in ipairs(path) do
                trace.rects[#trace.rects+1]={x=rect.x,y=rect.y,w=rect.w,h=rect.h,
                    color={color[1],color[2],color[3],color[4]},alpha=alpha}
            end
        end,
    }
    local original={}
    for name,value in pairs(overrides) do original[name]=_G[name];_G[name]=value end
    local note=Note.New()
    local ok,err=pcall(function()
        note:Show(amount);note:Tick(elapsed)
        note:Draw({}, {x=0,y=0,w=Layout.width,h=Layout.height},1)
    end)
    for name in pairs(overrides) do _G[name]=original[name] end
    assert(ok,err)
    trace.active,trace.text,trace.pose=note.active,note.text,note:Pose()
    return trace
end

case("production drawing uses hard square red glyphs and a wrinkled paper silhouette",function()
    local trace=Checks.Capture(40,.7)
    assert(trace.active and trace.text=="-40" and trace.anti_alias==0,
        "deduction text was smoothed or lost its minus sign")
    assert(trace.saves==1 and trace.restores==1 and trace.scale.x==1 and trace.scale.y==1)
    assert(trace.clip.y==0 and trace.clip.h<=Layout.score[2]+1,
        "receipt is allowed to obscure the balance reel")
    local red,folds=0,0
    local widths={}
    for _,rect in ipairs(trace.rects) do
        assert(rect.w>0 and rect.h>0,"invalid production drawing rectangle")
        local c=rect.color
        if c[1]>200 and c[2]<70 and c[3]<70 then
            red=red+1
            assert(near(rect.w,rect.h) and rect.w<=3,"red glyph pixels are not small square blocks")
        else
            folds=folds+1
            widths[rect.w]=true
        end
    end
    local varying=0
    for _ in pairs(widths) do varying=varying+1 end
    assert(red>30 and folds>=20 and varying>=8,
        "missing visible pixel digits, jagged paper edges or folded highlights")
    assert(#Checks.Capture(40,100).rects==0,"completed receipts still draw")
end)

-- Evaluate the complete current Skin.Update, replacing unrelated engine-backed
-- dependencies only. This catches the original stale-displayScore regression.
local function loadSkin()
    local deps={
        ["Machine.LayeredLayout"]=Layout,["Machine.FlatReelState"]=Reels,
        ["Bottle.Items"]=require("Bottle.Items"),
        ["Machine.Clock"]={Centiseconds=function() return 0 end},
        ["Machine.TargetSwap"]={Sync=function() end},
        ["Bottle.RelicView"]={Update=function() end},
        ["Bottle.Audio"]={SetReels=function() end},
    }
    return assert(loadfile(root.."/scripts/Machine/LayeredSkin.lua","t",
        setmetatable({require=function(name) return deps[name] or {} end},{__index=_G})))()
end

local function skinFixture()
    local hidden={IsVisible=function() return false end,Hide=function() end}
    return {
        game={phase="reveal",score=140,elapsed=0,settleElapsed=0,Duration=function() return 10 end},
        board={displayScore=180},currentPhase="reveal",choiceHidden=true,inventoryOpen=false,
        machineSkin={reels=Reels.New(),clock={phase="reveal",flashElapsed=-1},
            pageMotion={Clear=function() end},presentationMenu={Hide=function() end}},
        modal=hidden,definitionModal=hidden,physicsMenu=hidden,
        physicsButton={props={text="物理"}},draft={IsVisible=function() return true end},
    }
end

case("actual skin follows income during play and the real balance in draft/over/prepare",function()
    local skin=loadSkin()
    local view=skinFixture()
    for _,phase in ipairs({"running","settle","reveal"}) do
        view.game.phase=phase;skin.Update(view)
        assert(view.machineSkin.reels.value==180,phase.." stopped following visible income")
    end
    for _,phase in ipairs({"draft","over","prepare"}) do
        view.game.phase=phase;skin.Update(view)
        assert(view.machineSkin.reels.value==140,
            phase.." retained the stale pre-deduction displayScore")
    end
    view.game.phase="reveal";view.board.displayScore=0;skin.Update(view)
    assert(view.machineSkin.reels.value==0,"zero display balance fell through to game balance")
    view.board.displayScore=nil;skin.Update(view)
    assert(view.machineSkin.reels.value==140,"missing temporary balance did not use game balance")
end)

case("180 to 140 payment reaches real reel targets, rolls backwards and settles",function()
    local skin=loadSkin()
    local view=skinFixture()
    skin.Update(view)
    local reels=view.machineSkin.reels
    assert(reels.value==180 and not reels:Spinning())
    view.game.phase="draft";skin.Update(view)
    assert(reels.value==140 and reels:Spinning(),"payment failed to start a real reel animation")
    local changed=0
    for _,digit in pairs(reels.digits) do
        if digit.target~=digit.position then
            changed=changed+1
            assert(digit.target<digit.position,"a deduction rolled a digit in the income direction")
        end
    end
    assert(changed>0,"no changed reel digit was animated")
    local start=reels.digits[2].position
    reels:Tick(1/60)
    assert(reels.digits[2].position<start,"deduction target did not cause physical reverse motion")
    for _=1,600 do reels:Tick(1/60) end
    assert(not reels:Spinning() and reels.text=="00000140","payment reels did not settle at 140")
    for _,digit in pairs(reels.digits) do
        assert(near(digit.position,digit.target) and near(digit.velocity,0),"settled digit retained motion")
    end
end)

function Checks.Run()
    local names={}
    for _,test in ipairs(cases) do
        local ok,err=pcall(test.run)
        assert(ok,test.name..": "..tostring(err))
        names[#names+1]=test.name
    end
    return #cases,names
end

return Checks
