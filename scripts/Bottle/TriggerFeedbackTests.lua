-- 触发收益表现回归：走真实 Game.Step，确认标签/数值与入账保持一致。
-- 纯 Lua 内存夹具，不创建引擎对象，不读写玩家存档。
local Game = require("Bottle.Game")
local Repair = require("Bottle.RepairTests")
local Feedback = require("Bottle.TriggerFeedback")
local Tests = {}
local TURN = math.pi * 2

---@param actual number?
---@param expected number
local function Close(actual, expected)
    assert(type(actual) == "number" and math.abs(actual - expected) < 1e-7,
        "expected=" .. expected .. " actual=" .. tostring(actual))
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game, uid) return assert(game:Get(uid)) end

---@param ids string[]
---@param relics table<string,boolean>?
---@return BottleGame
local function Fixture(ids, relics)
    local game = Repair.Fixture(ids, relics)
    assert(game:Start())
    for _, item in ipairs(game:BottleItems()) do item.remaining = 0 end
    return game
end

---@param events GameEvent[]
---@param kind string
---@param uid integer?
---@return GameEvent[]
local function Events(events, kind, uid) return Repair.Events(events, kind, uid) end

---@return BottleStepContacts
local function EmptyContacts()
    return {pairs={}, bottom={}, top={}, wall={}, positions={}, side={}, angles={},
        rotateOffsets={}, angularTravel={}, flightArrived={}, flightHits={}}
end

---@param events GameEvent[]
---@param uid integer
---@param amount number
---@param rewardKind string
---@param trigger string
local function Reward(events, uid, amount, rewardKind, trigger)
    local found = Events(events, "triggerReward", uid)
    assert(#found == 1, "每次收益只显示一次：uid=" .. uid .. " count=" .. #found)
    local event = found[1]
    Close(event.value, amount)
    assert(event.rewardKind == rewardKind and event.trigger == trigger,
        "收益类别/触发类别错误：" .. tostring(event.rewardKind) .. "/" .. tostring(event.trigger))
end

---@param events GameEvent[]
---@param id string
---@param expected integer
local function Relic(events,id,expected)
    local count=0
    for _,event in ipairs(Events(events,"relicTrigger")) do
        assert(event.uid==0,"遗物反馈不能伪装成瓶内物品")
        if event.id==id then count=count+1 end
    end
    assert(count==expected,id.." expected="..expected.." actual="..count)
end

-- 精确检查请求范围及次数，防止反馈增加随机数、重投或成功判定。
---@param game BottleGame
---@param requests integer[][] {maximum,result}
---@return fun()
local function Random(game,requests)
    local index=0
    rawset(game,"_RandomInt",function(_,maximum)
        index=index+1
        local request=assert(requests[index],"反馈不得追加随机判定")
        assert(maximum==request[1] and request[2]>=1 and request[2]<=maximum,"随机范围改变")
        return request[2]
    end)
    return function() assert(index==#requests,"预期随机判定未执行") end
end

---@generic T
---@param value T
---@return T
local function Copy(value)
    if type(value)~="table" then return value end
    local result={}
    for key,entry in pairs(value) do result[key]=Copy(entry) end
    return result --[[@as T]]
end

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

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name, run) cases[#cases + 1] = {name=name, run=run} end

Test("小球碰墙显示碰撞价值且不入金币、冷却内不重复", function()
    local game = Fixture({"ball"})
    local contacts = {wall={[1]=true},positions={[1]={x=.2,y=1.5}}}
    local events = game:Step(0, contacts)
    Reward(events, 1, 1, "value", "collision")
    Close(Item(game,1).bonus, 1)
    Close(game.roundScore, 0)
    assert(#Events(events,"score") == 0)
    assert(#Events(game:Step(0,contacts),"triggerReward") == 0)
    assert(#Events(game:Step(2,contacts),"triggerReward") == 0)
    Close(Item(game,1).bonus, 1)
end)

Test("兔子真实移动满100米显示移动永久且不入金币", function()
    local game = Fixture({"rabbit"})
    local all = {}
    for step = 0, 200 do
        for _, event in ipairs(game:Step(0,{positions={[1]={x=step*.5,y=1}}})) do
            all[#all+1] = event
        end
    end
    Reward(all, 1, 1, "permanent", "move")
    Close(Item(game,1).permBonus, 1)
    Close(Item(game,1).distance, 0)
    Close(game.roundScore, 0)
    assert(#Events(game:Step(0,{positions={[1]={x=100,y=1}}}),"triggerReward") == 0)
end)

Test("成群结队兔子收益标在每个实际受益者", function()
    local game = Fixture({"rabbit","rabbit"},{in_groups=true})
    Item(game,1).distance = 99.5
    game:Step(0,{positions={[1]={x=0,y=1},[2]={x=1,y=2}}})
    local events = game:Step(0,{positions={[1]={x=.5,y=1},[2]={x=1,y=2}}})
    for uid=1,2 do
        Reward(events, uid, 1, "permanent", "move")
        Close(Item(game,uid).permBonus,1)
    end
    Close(game.roundScore,0)
end)

Test("幽灵和飞盘移动金币沿用score单次入账且带移动标签", function()
    local game = Fixture({"ghost","discus"},{ghost_sport=true})
    local total = 0
    local seen = {[1]=0,[2]=0}
    for step=0,60 do
        local events = game:Step(0,{positions={
            [1]={x=step*.5,y=1},[2]={x=step*.5,y=2}}})
        assert(#Events(events,"triggerReward") == 0, "金币不追加第二条收益事件")
        for _, event in ipairs(Events(events,"score")) do
            assert(event.trigger == "move")
            seen[event.uid] = seen[event.uid] + 1
            total = total + (event.value or 0)
        end
    end
    assert(seen[1] == 1 and seen[2] == 6)
    Close(total, 1+6*game:_Value(Item(game,2)))
    Close(game.roundScore,total)
    Close(game.score,total)
    Close(game.totalScore,total)
end)

Test("转圈圈金币显示旋转、不重复角度领奖或计强制旋转", function()
    local game = Fixture({"apple"},{spin_reward=true})
    rawset(game, "_RandomInt", function(_, maximum) assert(maximum == 100); return 1 end)
    local contacts = {angularTravel={[1]=TURN*6+.4},positions={[1]={x=.3,y=2}}}
    local events = game:Step(0,contacts)
    local scores = Events(events,"score")
    assert(#scores == 2 and #Events(events,"triggerReward") == 0)
    for _, event in ipairs(scores) do
        assert(event.trigger == "rotate")
        Close(event.value,1)
    end
    Close(game.roundScore,2)
    assert(#Events(game:Step(0,contacts),"score") == 0)
    game:Step(0,{angularTravel={[1]=0}})
    assert(#Events(game:Step(0,{angularTravel={[1]=0},
        angles={[1]=math.pi/2},rotateOffsets={[1]=math.pi/2}}),"score") == 0)
    Close(game.roundScore,2)
end)

Test("大胃王消费遗漏buff时仍显示碰撞永久收益", function()
    local game = Fixture({"glutton","apple"})
    local contacts = {pairs={{1,2}},positions={[1]={x=.1,y=1},[2]={x=.5,y=1}}}
    local events = game:Step(0,contacts)
    Reward(events, 1, 1, "permanent", "collision")
    assert(Item(game,2).location ~= "bottle")
    Close(Item(game,1).permBonus,1)
    Close(Item(game,1).scale,1.1)
    Close(game.roundScore,0)
    assert(#Events(game:Step(0,contacts),"triggerReward") == 0)
end)

Test("食客碰撞金币带碰撞标签且不产生额外入账", function()
    local game = Fixture({"diner","apple"})
    local expected = game:_Value(Item(game,2))*2
    local events = game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    local scores = Events(events,"score",1)
    assert(#scores == 1 and scores[1].trigger == "collision")
    Close(scores[1].value,expected)
    Close(game.roundScore,expected)
    assert(#Events(events,"triggerReward") == 0)
end)

Test("草堆最后一次永久减值离场仍在原位置显示且不重复", function()
    local game = Fixture({"hay", "rabbit"})
    local hay = Item(game, 1)
    hay.permBonus = 1 - game:_Value(hay)
    Close(game:_Value(hay), 1)
    local contacts = {pairs={{1,2}}, positions={[1]={x=.1,y=1},[2]={x=.5,y=1}}}
    local events = game:Step(0, contacts)
    assert(hay.location == "discard")
    Reward(events, 1, -1, "permanent", "collision")
    local popup = Events(events, "triggerReward", 1)[1]
    Close(popup.x, .1)
    Close(popup.y, 1)
    local prefix, amount, icon = Feedback.Content(popup.value or 0, popup.trigger, popup.rewardKind)
    assert(prefix == "碰撞" and amount == "永久-1" and icon)
    Close(game.roundScore, 0)
    assert(#Events(game:Step(0, contacts), "triggerReward", 1) == 0)
end)

Test("大胃王位移缩体积使用位移标签且不改变价值", function()
    local game = Fixture({"glutton"})
    local item = Item(game,1)
    item.scale,item.distance = 1.5,49.5
    game:Step(0,{positions={[1]={x=0,y=1}}})
    local events = game:Step(0,{positions={[1]={x=.5,y=1}}})
    Reward(events,1,-10,"size","distance")
    Close(item.scale,1.4)
    Close(item.permBonus,0)
    Close(item.bonus,0)
    Close(game.roundScore,0)
end)

Test("橘子及半块橘子持续贴底不跳字且结算收益保留", function()
    for _, id in ipairs({"orange", "orange_half"}) do
        local game = Fixture({id})
        local item = Item(game,1)
        local base = game:_Value(item)
        for _, touching in ipairs({true,true,false,false,true}) do
            local events = game:Step(0,{bottom={[1]=touching},positions={[1]={x=0,y=0}}})
            assert(#Events(events,"triggerReward") == 0, "持续状态切换不显示收益跳字")
            assert(#Events(events,"score") == 0, "贴底不会即时发金币")
            Close(item.bonus,touching and 2 or 0)
        end
        local contacts = {bottom={[1]=true},positions={[1]={x=0,y=0}}}
        game:Step(game:Duration(),contacts)
        assert(game.phase == "settle")
        local events = game:SettleStep(2,contacts)
        assert(#Events(events,"triggerReward") == 0)
        local scores = Events(events,"score",1)
        assert(#scores == 1, "结算仍产出一次金币收益提示")
        Close(scores[1].value,base+2)
        Close(game.roundScore,base+2)
    end
end)

Test("橘子的离散永久增益与即时金币反馈不被屏蔽", function()
    local game = Fixture({"chef","orange"})
    local events = game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    local halves = 0
    for _, item in ipairs(game:BottleItems()) do
        if item.id == "orange_half" then
            halves = halves + 1
            local found = false
            for _, event in ipairs(Events(events,"triggerReward",item.uid)) do
                if event.rewardKind == "permanent" and event.value == 3 then found = true end
            end
            assert(found, "厨师切半的永久+3仍显示跳字")
        end
    end
    assert(halves == 2)
    local diner = Fixture({"diner","orange"})
    local expected = diner:_Value(Item(diner,2))*2
    local eaten = diner:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    local scores = Events(eaten,"score",1)
    assert(#scores == 1 and scores[1].trigger == "collision")
    Close(scores[1].value,expected)
end)

Test("持续接触光环不连续弹收益也不凭空发金币", function()
    local game = Fixture({"chef","orange_half"})
    local contacts = {pairs={{1,2}}}
    local previous = game:_Value(Item(game,2))
    local initial = game:Step(0,contacts)
    Reward(initial,2,previous,"value","collision")
    for _=1,4 do
        local events = game:Step(0,contacts)
        assert(#Events(events,"triggerReward") == 0)
        assert(#Events(events,"score") == 0)
    end
    Close(Item(game,2).mult,2)
    Close(game.roundScore,0)
end)

Test("金币价值永久与位移文案保持真实数字和图标标记", function()
    local prefix,amount,icon = Feedback.Content(5,"move")
    assert(prefix == "移动：" and amount == "+5" and not icon)
    prefix,amount,icon = Feedback.Content(1.2,"move")
    assert(prefix == "移动：" and amount == "+2" and not icon)
    prefix,amount,icon = Feedback.Content(-1.2,"move")
    assert(prefix == "移动：" and amount == "-1" and not icon)
    prefix,amount,icon = Feedback.Content(1.5,"collision","value")
    assert(prefix == "碰撞" and amount == "+2" and icon)
    prefix,amount,icon = Feedback.Content(3,"rotate","permanent")
    assert(prefix == "旋转：" and amount == "永久+3" and icon)
    prefix,amount,icon = Feedback.Content(-10,"distance","size")
    assert(prefix == "位移体积" and amount == "-10%" and not icon)
end)

Test("倍率收益比较取整后的价值且永久临时两段不重复", function()
    local game = Fixture({"hay"})
    local hay = Item(game, 1)
    hay.permBonus = -1
    Close(game:_Value(hay), 4)
    local before = Feedback.Capture(game)
    hay.permMult = 1.2
    local events = {}
    Feedback.Finish(game, before, events, 1, "collision", EmptyContacts())
    Close(game:_Value(hay), 5)
    Reward(events, 1, 1, "permanent", "collision")
    Close(hay.permMult, 1.2)
    Close(game.roundScore, 0)

    hay.permMult = 1
    before = Feedback.Capture(game)
    hay.permMult, hay.mult = 1.2, 1.5
    events = {}
    Feedback.Finish(game, before, events, 1, "collision", EmptyContacts())
    assert(#events == 2)
    Close(events[1].value, 1)
    assert(events[1].rewardKind == "permanent")
    Close(events[2].value, 3)
    assert(events[2].rewardKind == "value")
    Close(game:_Value(hay), 8)
    Close((events[1].value or 0) + (events[2].value or 0), 8 - 4)
end)

Test("加法跳字不额外放大且体积小数保留", function()
    local game = Fixture({"hay"})
    local hay = Item(game, 1)
    hay.permBonus, hay.mult = -1, 1.5
    Close(game:_Value(hay), 6)
    local before = Feedback.Capture(game)
    hay.bonus = hay.bonus + 1
    local events = {}
    Feedback.Finish(game, before, events, 1, "collision", EmptyContacts())
    Reward(events, 1, 1, "value", "collision")
    Close(game:_Value(hay), 8)
    Feedback.Reward(events, hay, -.2, "value", "collision")
    assert(#events == 1, "向上取整为0时不显示虚假收益")
    Feedback.Reward(events, hay, 2.5, "size", "distance")
    Close(events[2].value, 2.5)
    local prefix, amount, icon = Feedback.Content(2.5, "distance", "size")
    assert(prefix == "位移体积" and amount == "+2.5%" and not icon)
end)

Test("四类触发按金币价值和永久价值统一排版", function()
    for _, trigger in ipairs({"move", "rotate", "distance", "collision"}) do
        local expected = ({move="移动：", rotate="旋转：", distance="位移", collision="碰撞"})[trigger]
        local prefix, amount, icon = Feedback.Content(2, trigger)
        assert(prefix == expected and amount == "+2" and not icon, "金币仅显示触发名和+n")
        prefix, amount, icon = Feedback.Content(2, trigger, "value")
        assert(prefix == expected and amount == "+2" and icon, "价值图标位于触发名之后")
        prefix, amount, icon = Feedback.Content(2, trigger, "permanent")
        assert(prefix == expected and amount == "永久+2" and icon, "永久位于价值图标之后")
    end
    local prefix, amount, icon = Feedback.Content(2)
    assert(prefix == "" and amount == "+2" and not icon, "普通结算不添加触发类别")
end)

Test("表现事件只追加元数据、不改变玩家数值或结算队列", function()
    local game = Fixture({"ball"})
    local item = Item(game,1)
    local beforeScore,beforeTotal,beforeRound = game.score,game.totalScore,game.roundScore
    local beforeRevision,beforeRng,beforePop = game.revision,game._rngState,game._roundPopCount
    local events = {}
    Feedback.Reward(events,item,3,"permanent","collision",{x=.4,y=2})
    Reward(events,1,3,"permanent","collision")
    Close(events[1].x,.4)
    Close(events[1].y,2)
    assert(game.score == beforeScore and game.totalScore == beforeTotal and game.roundScore == beforeRound)
    assert(game.revision == beforeRevision and game._rngState == beforeRng and game._roundPopCount == beforePop)
    Close(item.permBonus,0)
    Close(item.bonus,0)
end)

Test("保镖拦下老师合成时保护金币仍标碰撞且不重复", function()
    local game = Fixture({"teacher","teacher","bodyguard"},{teacher_team=true})
    local contacts={pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1},[3]={x=1,y=2}}}
    local events=game:Step(0,contacts)
    local scores=Events(events,"score")
    assert(#scores==1 and scores[1].trigger=="collision")
    Close(game.roundScore,scores[1].value or 0)
    assert(#Events(game:Step(0,contacts),"score")==0)
    assert(Item(game,1).location=="bottle" and Item(game,2).location=="bottle")
end)

Test("满瓶厨师产物延后入场在原位置显示永久加值且只显示一次", function()
    local game=Fixture({"chef","apple","glutton","orange"})
    while #game:BottleItems()<100 do game:_Spawn("ball",{}) end
    local positions={[1]={x=0,y=1},[2]={x=.5,y=1},[3]={x=1,y=2},[4]={x=1.5,y=2}}
    local initial=game:Step(0,{pairs={{1,2}},positions=positions})
    assert(#game.spawnQueue==1)
    local uid=game.spawnQueue[1]
    assert(Item(game,uid).location=="queued" and Item(game,uid).permBonus==3)
    assert(#Events(initial,"triggerReward",uid)==0,"排队未入瓶时不显示无实体收益")
    local entered=game:Step(0,{pairs={{3,4}},positions=positions})
    assert(Item(game,uid).location=="bottle" and #game.spawnQueue==0)
    Reward(entered,uid,3,"permanent","collision")
    local popup=Events(entered,"triggerReward",uid)[1]
    Close(popup.x,.5)
    Close(popup.y,1)
    assert(#Events(game:Step(0,{pairs={{3,4}},positions=positions}),"triggerReward",uid)==0)
end)

Test("分裂器折入基础价值的永久加成和倍率不虚报负收益", function()
    local game=Fixture({"splitter","ghost"})
    local target=Item(game,2)
    target.permBonus,target.permMult,target.eventMult,target.mult=10,1.2,1.5,1.5
    local expected=math.ceil(game:_Value(target)/2)
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=1},[2]={x=.5,y=1}}})
    local ghosts=0
    for _,item in ipairs(game:BottleItems()) do
        if item.id=="ghost" then
            ghosts=ghosts+1
            Close(game:_Value(item),expected)
            Close(item.permBonus,0)
            Close(item.permMult,1)
        end
    end
    assert(ghosts==2 and #Events(events,"triggerReward")==0,
        "数值归一化不能显示永久-10或倍率损失")
    Close(game.roundScore,0)
end)

Test("偶数回合获得刷新发一次独立提示、重复结算不重发", function()
    for _, round in ipairs({1,2,3,4}) do
        local game = Fixture({"apple"})
        game.round = round
        local before = game.refreshes
        local events = game:Finish()
        local gains = Events(events, "refreshGain")
        assert(#gains == (round % 2 == 0 and 1 or 0))
        Close(game.refreshes, before + #gains)
        if #gains > 0 then assert(gains[1].uid == 0 and gains[1].value == 1) end
        assert(#Events(game:Finish(), "refreshGain") == 0)
        assert(#Events(game:RevealStep(100), "refreshGain") == 0)
        Close(game.roundScore, 2)
    end
end)

Test("鸡蛋刷新成功才提示且保留自耗前位置、多来源不丢失", function()
    local game = Fixture({"egg","egg","egg"})
    game.round = 2
    for _, egg in ipairs(game:BottleItems()) do egg.bottleRounds = 3 end
    local calls = 0
    rawset(game, "_RandomInt", function(_, maximum)
        assert(maximum == 2)
        calls = calls + 1
        return calls == 2 and 2 or 1
    end)
    local before = game.refreshes
    local events = game:Finish({positions={[1]={x=.4,y=1},[2]={x=-.2,y=2},[3]={x=.8,y=3}}})
    local gains = Events(events, "refreshGain")
    assert(#gains == 3 and calls == 3)
    assert(gains[1].uid == 1 and gains[2].uid == 3 and gains[3].uid == 0)
    Close(gains[1].x,.4); Close(gains[1].y,1)
    Close(gains[2].x,.8); Close(gains[2].y,3)
    Close(game.refreshes,before+3)
    assert(#Events(events,"score") == 3 and game.roundScore == 9)
    assert(#Events(game:Finish(),"refreshGain") == 0 and calls == 3)
end)

Test("未成熟或自耗被阻止的鸡蛋不提示、不抽概率", function()
    local Expansion = require("Bottle.ExpansionEffects")
    local game = Fixture({"egg"})
    local events = {}
    rawset(game, "_RandomInt", function() error("失败不得抽概率") end)
    Expansion.AfterSettle(game,events)
    assert(#Events(events,"refreshGain") == 0)
    Item(game,1).bottleRounds = 3
    rawset(game,"_Destroy",function() return false end)
    Expansion.AfterSettle(game,events)
    assert(#Events(events,"refreshGain") == 0 and game.refreshes == 1)
end)

Test("刷新提示不发金币不改RNG、无价值图标、恢复不重放", function()
    local game = Fixture({"apple"})
    local beforeRng,beforeScore,beforePop = game._rngState,game.score,game._roundPopCount
    local events = {}
    Feedback.Refresh(events)
    Feedback.Refresh(events,Item(game,1),{x=.2,y=1})
    assert(#events == 2 and #Events(events,"score") == 0)
    assert(game._rngState == beforeRng and game.score == beforeScore and game._roundPopCount == beforePop)
    local prefix,amount,icon = Feedback.Content(1,"refresh","refresh","刷新")
    assert(prefix == "刷新" and amount == "+1" and not icon)
    local restored = Game.Restore(Repair.Fixture({"apple"}):Snapshot())
    assert(#restored.startEvents == 0 and restored.refreshes == 1)
end)

Test("遗物反馈只追加running已拥有的元数据，同数组去重且不改变规则或随机状态",function()
    local game=Fixture({"apple"},{small_savings=true,credit_line=true})
    local before=Copy(game)
    local events={}
    Feedback.Relic(game,events,"small_savings")
    Feedback.Relic(game,events,"small_savings")
    Feedback.Relic(game,events,"credit_line")
    Feedback.Relic(game,events,"spin_reward")
    Feedback.Relic(game,nil,"small_savings")
    Relic(events,"small_savings",1);Relic(events,"credit_line",1);Relic(events,"spin_reward",0)
    assert(#events==2 and Equal(game,before),"表现不能改金币、实例、revision、pop或RNG")
    for _,phase in ipairs({"prepare","settle","reveal","draft","over"}) do
        game.phase=phase --[[@as BottlePhase]]
        local rejected={}
        Feedback.Relic(game,rejected,"small_savings")
        assert(#rejected==0,"非running不能播放摇晃反馈")
    end
    game.phase="running"
    local nextBatch={}
    Feedback.Relic(game,nextBatch,"small_savings")
    Relic(nextBatch,"small_savings",1)
end)

Test("真实创建信用卡与积少成多同批各反馈一次，不重复入账且旧无events调用兼容",function()
    local game=Fixture({"apple"},{small_savings=true,credit_line=true})
    local score,total,roundScore,rng=game.score,game.totalScore,game.roundScore,game._rngState
    local events={}
    local first=game:_Create("credit_card",false,events)
    local second=game:_Create("credit_card",false,events)
    Close(first.permBonus,15);Close(second.permBonus,15)
    Close(game:_Value(first),25);Close(game.score,score+2);Close(game.totalScore,total+2)
    Close(game.roundScore,roundScore);assert(game._rngState==rng)
    Relic(events,"credit_line",1);Relic(events,"small_savings",1)
    assert(not pcall(function() game:_Create("not_a_real_item",false,events) end))
    assert(#events==2 and game.score==score+2,"失败创建不能反馈或加钱")
    local legacy=game:_Create("credit_card")
    Close(legacy.permBonus,15);Close(game.score,score+3);assert(#events==2)
    game.phase="settle"
    local settled={}
    game:_Create("credit_card",false,settled)
    assert(#settled==0,"非running创建仍执行旧数值但不播摇晃反馈")
end)

Test("回合初始作弊骰子与六点大奖走真实Start事件且不增加随机调用",function()
    local game=Repair.Fixture({"die_d6"},{cheat_dice=true,dice_jackpot=true})
    local done=Random(game,{{5,5}})
    assert(game:Start());done()
    local die=Item(game,1)
    Close(die.rollValue,6);Close(die.scale,1.5);Close(die.jackpotBonus,.5)
    Relic(game.startEvents,"cheat_dice",1);Relic(game.startEvents,"dice_jackpot",1)
    local scores=Events(game.startEvents,"score",1)
    assert(#scores==1);Close(scores[1].value,game:_Value(die));Close(game.roundScore,scores[1].value or 0)
end)

Test("额外重投只在第二次实际投掷成功反馈，额度耗尽不再抽签或反馈",function()
    local game=Fixture({"gambler","die_d6"},{one_more_round=true,cheat_dice=true})
    local done=Random(game,{{5,2},{5,3}})
    local contacts={pairs={{1,2}}}
    local events=game:Step(0,contacts);done()
    assert(Item(game,1).rerolled[2]==2);Close(Item(game,1).permBonus,2)
    Relic(events,"one_more_round",1);Relic(events,"cheat_dice",1)
    local score,rng=game.score,game._rngState
    local exhausted=game:Step(0,contacts);done()
    assert(#Events(exhausted,"relicTrigger")==0 and game.score==score and game._rngState==rng)
end)

Test("赌神令牌真正转化才反馈，概率失败和已尝试状态不反馈",function()
    for _,roll in ipairs({1,2}) do
        local game=Fixture({"gambler"},{gambling_token=true})
        local gambler=Item(game,1)
        gambler.valueBase=50
        local done=Random(game,{{4,roll}})
        local events=game:Step(0,{});done()
        Relic(events,"gambling_token",roll==1 and 1 or 0)
        if roll==1 then assert(gambler.id=="gambling_god");Close(gambler.permBonus,50)
        else assert(gambler.id=="gambler" and gambler.tokenAttempted) end
        local again=game:Step(0,{});done()
        Relic(again,"gambling_token",0)
    end
end)

Test("精进刀法第三份水果生成才反馈，50%失败保留两份与原随机次数",function()
    for _,roll in ipairs({1,2}) do
        local game=Fixture({"knife","apple"},{knife_skill=true})
        local done=Random(game,{{2,roll}})
        local events=game:Step(0,{pairs={{1,2}},positions={[2]={x=.2,y=2}}});done()
        local count=0
        for _,item in ipairs(game:BottleItems()) do if item.id=="apple_half" then count=count+1 end end
        assert(count==(roll==1 and 3 or 2))
        Relic(events,"knife_skill",roll==1 and 1 or 0)
        Close(game.roundScore,0)
    end
end)

Test("水果成功被耗后转基因成功才反馈，创建收益只增加原定一金币",function()
    for _,success in ipairs({true,false}) do
        local game=Fixture({"glutton","apple"},{gm_fruit=true,small_savings=true})
        local before=game.score
        local done=Random(game,success and {{10,1},{4,1},{101,51}} or {{10,2}})
        local events=game:Step(0,{pairs={{1,2}},positions={[2]={x=.2,y=2}}});done()
        assert(Item(game,2).location=="discard");Close(Item(game,1).permBonus,1)
        Relic(events,"gm_fruit",success and 1 or 0)
        Relic(events,"small_savings",success and 1 or 0)
        assert(#Events(events,"spawn")== (success and 1 or 0))
        Close(game.score,before+(success and 1 or 0));Close(game.roundScore,0)
    end
end)

Test("羊毛合成两份独立回收但同批只反馈一次，概率失败不伪造羊毛",function()
    for _,success in ipairs({true,false}) do
        local game=Fixture({"wool","wool"},{wool_recycle=true})
        local done=Random(game,success and {{2,1},{101,51},{2,1},{101,51}} or {{2,2},{2,2}})
        local events=game:Step(0,{pairs={{1,2}}});done()
        assert(#Events(events,"merge")==1 and Item(game,1).location=="discard" and Item(game,2).location=="discard")
        local wool,merged=0,0
        for _,item in ipairs(game:BottleItems()) do
            if item.id=="wool" then
                if item.generatedTemporary then wool=wool+1
                else merged=merged+1;Close(game:_Value(item),2) end
            end
        end
        assert(merged==1 and wool==(success and 2 or 0));Relic(events,"wool_recycle",success and 1 or 0)
    end
end)

Test("老师同批两次成功合成只反馈一次，保镖阻挡合成不反馈遗物",function()
    local game=Fixture({"teacher","teacher","teacher","teacher"},{teacher_team=true})
    local events=game:Step(0,{pairs={{1,2},{3,4}}})
    assert(#Events(events,"merge")==2 and #game:BottleItems()==2)
    Relic(events,"teacher_team",1)
    local guarded=Fixture({"teacher","teacher","bodyguard"},{teacher_team=true,small_savings=true})
    local blocked=guarded:Step(0,{pairs={{1,2}}})
    assert(#Events(blocked,"merge")==0 and Item(guarded,1).shielded and Item(guarded,3).counter==1)
    assert(#Events(blocked,"score")==1,"原保镖保护收益须保留")
    Relic(blocked,"teacher_team",0)
    Relic(blocked,"small_savings",0)
    Close(guarded.score,Events(blocked,"score")[1].value or 0)
end)

Test("解锁高阶硬币合成成功才反馈，普通低阶合成不冒充2048遗物触发",function()
    for _,id in ipairs({"coin_1","coin_64"}) do
        local game=Fixture({id,id},{merge_2048=true,small_savings=true})
        local score,total=game.score,game.totalScore
        local events=game:Step(0,{pairs={{1,2}}})
        assert(#Events(events,"merge")==1)
        Relic(events,"merge_2048",id=="coin_64" and 1 or 0)
        Relic(events,"small_savings",1)
        Close(game.score,score+1);Close(game.totalScore,total+1);Close(game.roundScore,0)
    end
    local game=Fixture({"coin_64","coin_64"})
    local events=game:Step(0,{pairs={{1,2}}})
    assert(#Events(events,"merge")==0 and #game:BottleItems()==2)
    Relic(events,"merge_2048",0)
end)

Test("追杀成功击杀当前目标才奖励与反馈，被盾挡住不反馈",function()
    for _,blocked in ipairs({false,true}) do
        local game=Fixture(blocked and {"killer","gambler","bodyguard"} or {"killer","gambler"},
            {jungle_hunt=true})
        game.huntTargetUid=2
        local events=game:Step(0,{pairs={{1,2}}})
        Relic(events,"jungle_hunt",blocked and 0 or 1)
        Close(Item(game,1).permMult,blocked and 1 or 1.5)
        assert(Item(game,2).location==(blocked and "bottle" or "discard"))
        if blocked then assert(Item(game,2).shielded and Item(game,3).counter==1) end
    end
end)

Test("转圈圈只中奖才反馈，多个实际金币奖励同批合并且失败仍消耗三圈",function()
    for _,roll in ipairs({1,100}) do
        local game=Fixture({"apple","orange"},{spin_reward=true})
        local done=Random(game,{{100,roll},{100,roll}})
        local events=game:Step(0,{angularTravel={[1]=TURN*3,[2]=TURN*3}});done()
        assert(#Events(events,"score")== (roll==1 and 2 or 0))
        Close(game.roundScore,roll==1 and 2 or 0)
        for uid=1,2 do Close(Item(game,uid).spinProgress,0) end
        Relic(events,"spin_reward",roll==1 and 1 or 0)
    end
end)

Test("幸运转盘仅77大奖反馈，幸运符仅反转负分支反馈且概率次数不变",function()
    for _,case in ipairs({{rolls={{20,1}},value=77,permanent=false,wheel=1,charm=0},
        {rolls={{20,2},{2,1}},value=3,permanent=true,wheel=0,charm=0},
        {rolls={{20,2},{2,2}},value=1,permanent=true,wheel=0,charm=1}}) do
        local game=Fixture({"roulette"},{lucky_roulette=true,lucky_charm=true})
        local done=Random(game,case.rolls)
        local events=game:Step(0,{angularTravel={[1]=TURN}});done()
        Close(case.permanent and Item(game,1).permBonus or Item(game,1).bonus,case.value)
        Close(case.permanent and Item(game,1).bonus or Item(game,1).permBonus,0)
        Relic(events,"lucky_roulette",case.wheel);Relic(events,"lucky_charm",case.charm)
    end
end)

Test("成群结队须真的惠及另一兔，幽灵满30米金币才反馈",function()
    for _,multiple in ipairs({false,true}) do
        local game=Fixture(multiple and {"rabbit","rabbit"} or {"rabbit"},{in_groups=true})
        Item(game,1).distance=100
        local events=game:Step(0,{})
        Close(Item(game,1).permBonus,1)
        if multiple then Close(Item(game,2).permBonus,1) end
        Relic(events,"in_groups",multiple and 1 or 0)
    end
    local game=Fixture({"ghost"},{ghost_sport=true})
    local events=game:Step(0,{positions={[1]={x=0,y=2}},pathLengths={[1]=60},pathGeneration={[1]=1}})
    assert(#Events(events,"score",1)==2);Close(game.roundScore,2);Relic(events,"ghost_sport",1)
end)

Test("成功额外续命与金针菇永久加值才反馈，耗尽和护盾不伪报成功",function()
    for _,before in ipairs({0,4,9}) do
        local game=Fixture({"tomato_egg"},{scramble_recipe=true})
        Item(game,1).counter=before
        local events=game:Consume(1)
        assert(Item(game,1).counter==before+1)
        Relic(events,"scramble_recipe",before==4 and 1 or 0)
        assert(#Events(events,"respawn")== (before<9 and 1 or 0))
    end
    local game=Fixture({"enoki"},{see_you_tomorrow=true})
    local events=game:Consume(1)
    Close(Item(game,1).permBonus,1);assert(#Events(events,"respawn")==1)
    Relic(events,"see_you_tomorrow",1)
    Item(game,1).shielded=true
    local blocked=game:Consume(1)
    Close(Item(game,1).permBonus,1);Relic(blocked,"see_you_tomorrow",0)
end)

Test("厨师帽成功吃刀本身反馈，无水果也成功，被阻止消费则不反馈",function()
    for _,blocked in ipairs({false,true}) do
        local game=Fixture({"chef","knife"},{chef_hat=true})
        Item(game,2).shielded=blocked
        local events=game:Step(0,{pairs={{1,2}}})
        assert(Item(game,2).location==(blocked and "bottle" or "discard"))
        Relic(events,"chef_hat",blocked and 0 or 1)
        Close(Item(game,1).permBonus,0)
        if not blocked then Close(Item(game,1).remaining,1) end
    end
end)

Test("有教无类与金盘洗手只有实际转化和双向加值反馈，免疫过滤不反馈",function()
    local game=Fixture({"teacher","gambler"},{teach_all=true})
    local value=game:_Value(Item(game,2))
    local events=game:Step(0,{pairs={{1,2}}})
    assert(Item(game,2).id=="student");Close(Item(game,2).permBonus,value);Relic(events,"teach_all",1)
    local immune=Fixture({"killer","teacher"},{teach_all=true})
    Item(immune,2).remaining=100
    local protected=immune:Step(0,{pairs={{1,2}}})
    assert(Item(immune,2).id=="teacher" and Item(immune,2).location=="bottle");Relic(protected,"teach_all",0)
    local thief=Fixture({"thief","credit_card"},{wash_hands=true})
    local washed=thief:Step(0,{pairs={{1,2}}})
    Close(Item(thief,1).permBonus,1);Close(Item(thief,2).permBonus,1);Relic(washed,"wash_hands",1)
    local police=Fixture({"police","thief"},{wash_hands=true})
    Item(police,2).remaining=100
    local excluded=police:Step(0,{pairs={{1,2}}})
    assert(Item(police,2).location=="bottle");Relic(excluded,"wash_hands",0)
end)

Test("优质小草成功动物产物和牛冲刺反馈，羊毛集市零库存不反馈",function()
    local game=Fixture({"grass","calf"},{premium_grass=true,calf_rush=true})
    local done=Random(game,{{60,1}})
    local events=game:Step(0,{pairs={{1,2}},positions={[1]={x=0,y=2},[2]={x=.2,y=2}}});done()
    assert(Item(game,1).location=="discard" and #Events(events,"dash",2)==1)
    Close(Item(game,2).bonus,1);Close(Item(game,2).scale,1.2)
    Relic(events,"premium_grass",1);Relic(events,"calf_rush",1)
    local sheep=Fixture({"sheep"},{wool_market=true})
    local empty=sheep:Step(0,{shakeStrength=5});Relic(empty,"wool_market",0)
    Item(sheep,1).woolCount=3
    local counts=Random(sheep,{{101,51},{101,51},{101,51}})
    local produced=sheep:Step(0,{shakeStrength=5});counts()
    Close(Item(sheep,1).woolCount,0);assert(#Events(produced,"spawn")==3)
    for _,event in ipairs(Events(produced,"spawn")) do assert(event.id=="coin_1") end
    Relic(produced,"wool_market",1)
end)

Test("硬币雨替换成功与升级机真实四元产物反馈，普通产物不假报升级成功",function()
    local cloud=Fixture({"cloud"},{coin_rain=true})
    local rainDone=Random(cloud,{{5,2}})
    local rain=cloud:Step(0,{});rainDone()
    assert(#Events(rain,"spawn")==1 and Events(rain,"spawn")[1].id=="coin_1")
    Relic(rain,"coin_rain",1)
    for _,roll in ipairs({1,3}) do
        local game=Fixture({"coin_machine","student"},{upgrade_coin_machine=true})
        local done=Random(game,{{3,roll},{101,51}})
        local events=game:Step(0,{pairs={{1,2}}});done()
        assert(#Events(events,"spawn")==1)
        Relic(events,"upgrade_coin_machine",roll==3 and 1 or 0)
        assert(Events(events,"spawn")[1].id==(roll==3 and "coin_4" or "coin_1"))
    end
end)

Test("常驻遗物的价值冷却时长及邻接查询不会每帧触发反馈",function()
    local game=Fixture({"apple","thief","chef","soul_stone","tombstone","tomato","poop","cherry"},
        {soul_resonance=true,thief_handbook=true,tomato_tycoon=true,last_second=true,accelerator=true,
            ghost_poop=true,food_comfort=true,bacon_network=true,juicer=true,cherry_plus=true})
    local rng=game._rngState
    for _=1,5 do
        for _,item in ipairs(game:BottleItems()) do game:_Value(item);game:CooldownOf(item.id) end
        game:Duration()
        assert(#Events(game:Step(0,{}),"relicTrigger")==0)
    end
    assert(game._rngState==rng)
    game.phase="settle"
    local settled=game:SettleStep(2,{})
    assert(#Events(settled,"relicTrigger")==0 and game.phase=="reveal")
end)

Test("真实规则启用与关闭纯反馈时事件之外的完整状态及PRNG完全一致",function()
    local function Scene()
        return Fixture({"cloud","knife","apple","coin_64","coin_64"},
            {coin_rain=true,knife_skill=true,merge_2048=true,small_savings=true})
    end
    local actual,control=Scene(),Scene()
    local contacts={pairs={{2,3},{4,5}},positions={[1]={x=0,y=3},[3]={x=.4,y=2}}}
    local events=actual:Step(0,contacts)
    local original=Feedback.Relic
    Feedback.Relic=function() end
    local expected={}
    local ok,err=pcall(function() expected=control:Step(0,contacts) end)
    Feedback.Relic=original
    assert(ok,err)
    assert(Equal(actual,control),"遗物表现不能改变金额、实例、队列、冷却、revision、pop或RNG")
    local gameplay={}
    for _,event in ipairs(events) do if event.kind~="relicTrigger" then gameplay[#gameplay+1]=event end end
    assert(Equal(gameplay,expected),"原玩法事件内容及顺序不能被反馈改变")
    assert(#Events(events,"relicTrigger")>=3)
end)

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok,err = pcall(case.run)
        assert(ok,"Bottle.TriggerFeedbackTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end

return Tests
