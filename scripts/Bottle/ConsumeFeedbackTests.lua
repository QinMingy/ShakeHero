-- 框架回归：真实规则事件选型、收益来源、保护拒绝、消灭退场与吞食互不串用。
local Repair = require("Bottle.RepairTests")
local Styles = require("Bottle.ConsumeStyles")
local Player = require("Bottle.ConsumeFeedback")
local Feedback = require("Bottle.TriggerFeedback")
local Smoke = require("Bottle.ConsumeSmoke")
local T = {}
local CONTACTS = {pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}}

---@param ids string[]
---@return BottleGame
local function Fixture(ids)
    local game=Repair.Fixture(ids)
    assert(game:Start())
    for _,item in ipairs(game:BottleItems()) do item.remaining=0 end
    return game
end
---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game,uid) return assert(game:Get(uid)) end
---@type {name:string,run:fun()}[]
local cases={}
---@param name string
---@param run fun()
local function Test(name,run) cases[#cases+1]={name=name,run=run} end

---@param a any
---@param b any
---@return boolean
local function Equal(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do if not Equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end

Test("策略按语义分派，不把回收工具或系统消耗当成吞食",function()
    local rows={{"pig","eat"},{"glutton","eat"},{"diner","eat"},{"monkey","eat"},
        {"calf","eat"},{"sheep","eat"},{"trash_can","recycle"},{"chef","use"},
        {"soul_stone","absorb"},{"cactus","absorb"},{"chicken_keeper","collect"},
        {"sweater","collect"},{"unknown_item","consume"}}
    for _,row in ipairs(rows) do
        local event={kind="consume",uid=1,id="apple",reason="consume",consumerId=row[1]}
        assert(Styles.Resolve(event)==row[2],row[1])
    end
    assert(Styles.Resolve({kind="consume",uid=1,reason="consume"})=="consume")
    for reason,expected in pairs({eliminate="eliminate",merge_checked="merge",burst="burst",remove="remove"}) do
        assert(Styles.Resolve({kind="consume",uid=1,reason=reason,consumerId="pig"})==expected)
    end
    assert(require("Bottle.ConsumeFlash")==Player,"旧入口保持同一实现")
end)

Test("杀手和警察真实消灭走原地烟雾，金币即时且表现不改规则",function()
    for _,row in ipairs({{"killer","student",7},{"police","killer",4}}) do
        local game=Fixture({row[1],row[2]})
        local expected=game:_Value(Item(game,2))*row[3]
        local events=game:Step(0,CONTACTS)
        local event=assert(Repair.Events(events,"consume",2)[1])
        local score=assert(Repair.Events(events,"score",1)[1])
        assert(event.reason=="eliminate" and event.consumerUid==1)
        assert(score.value==expected and game.roundScore==expected and Item(game,2).location=="discard")
        assert(Styles.RewardLabel(score)=="消灭")
        local before=game:Snapshot()
        local fx=Player.New()
        assert(fx:Capture(event,{bodies={}} --[[@as any]]))
        local pose=fx.flashes[1]
        assert(pose.animation=="smoke" and pose.style=="eliminate" and not pose.consumerUid)
        assert(#fx.popups==0 and pose.lifetime==Smoke.LIFETIME)
        fx:Update(Smoke.HIT+Smoke.FADE)
        local x,y,_,alpha=Player.VisualPose(pose)
        assert(math.abs(x-.5)<1e-7 and y==1 and alpha<1e-7,"原位退场，不飞入消灭者")
        fx:Update(1)
        assert(#fx.flashes==0 and next(fx.rebounds)==nil)
        assert(Equal(before,game:Snapshot()),"动效不得推进玩法、计分或随机数")
    end
end)

Test("吞食与吸收收益携带明确来源，碰撞本身仍用碰撞文案",function()
    for _,row in ipairs({{"diner","apple","吞食"},{"pig","apple","吞食"},
        {"monkey","banana","吞食"},{"soul_stone","ghost","吸收"}}) do
        local game=Fixture({row[1],row[2]})
        local events=game:Step(0,CONTACTS)
        local score=assert(Repair.Events(events,"score",1)[1],row[1])
        assert(Styles.RewardLabel(score)==row[3],row[1])
        local prefix,amount=Feedback.Content(score.value or 0,score.trigger,nil,Styles.RewardLabel(score))
        assert(prefix==row[3] and amount:sub(1,1)=="+")
        if row[1]=="soul_stone" then
            local ghostScore=assert(Repair.Events(events,"score",2)[1])
            assert(not Styles.RewardLabel(ghostScore),"被消耗者自身结算不能冒充主动吸收收益")
        end
    end
    local game=Fixture({"ball"})
    local events=game:Step(0,{wall={[1]=true},positions={[1]={x=0,y=1}}})
    local reward=assert(Repair.Events(events,"triggerReward",1)[1])
    assert(not Styles.RewardLabel(reward))
    local prefix=Feedback.Content(reward.value or 0,reward.trigger,reward.rewardKind,Styles.RewardLabel(reward))
    assert(prefix=="碰撞")
end)

Test("永久收益继承本次消耗来源，不能污染其他物品或下次触发",function()
    for _,row in ipairs({{"glutton","apple","吞食"},{"trash_can","banana_peel","回收"}}) do
        local game=Fixture({row[1],row[2],"ball"})
        local events=game:Step(0,CONTACTS)
        local reward=assert(Repair.Events(events,"triggerReward",1)[1])
        assert(Styles.RewardLabel(reward)==row[3] and reward.rewardKind=="permanent")
        local later=game:Step(0,{wall={[3]=true},positions={[3]={x=.2,y=1}}})
        local other=assert(Repair.Events(later,"triggerReward",3)[1])
        assert(not Styles.RewardLabel(other),"原因限定在真实消耗效果范围内")
    end
end)

Test("回收沿轨迹但没有吃饱回弹，收取与工具使用同样可复用",function()
    for _,id in ipairs({"trash_can","chef","soul_stone","cactus","chicken_keeper","sweater"}) do
        local fx=Player.New()
        local physics={bodies={[1]={kind="apple"},[2]={kind=id}},
            GetPose=function(_,uid) return uid==1 and .5 or 0,1,0,.3 end,
            GetSoftPose=function() return nil end}
        local event={kind="consume",uid=1,id="apple",reason="consume",consumerUid=2,consumerId=id}
        assert(fx:Capture(event,physics --[[@as any]]))
        assert(fx.flashes[1].animation=="absorb" and not fx.flashes[1].rebound)
        fx:Update(Player.ABSORB_LIFETIME,physics --[[@as any]])
        assert(next(fx.rebounds)==nil,id)
    end
end)

Test("小猪变培根后的最后一餐仍显示吞食，护盾拒绝不伪造消灭",function()
    local game=Fixture({"pig","apple"})
    Item(game,1).scale=1.95
    local events=game:Step(0,CONTACTS)
    assert(Item(game,1).id=="bacon")
    local score=assert(Repair.Events(events,"score",1)[1])
    assert(score.consumerId=="pig" and Styles.RewardLabel(score)=="吞食")
    local protected=Fixture({"killer","student"})
    Item(protected,2).shielded=true
    local rejected=protected:Step(0,CONTACTS)
    assert(#Repair.Events(rejected,"consume",2)==0 and #Repair.Events(rejected,"score",1)==0)
    assert(Item(protected,2).location=="bottle")
end)

---@return integer
function T.Run()
    for _,case in ipairs(cases) do
        local ok,err=pcall(case.run)
        assert(ok,"ConsumeFeedbackTests ["..case.name.."] "..tostring(err))
    end
    return #cases
end
return T
