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

---@return integer
function Tests.Run()
    for _, case in ipairs(cases) do
        local ok,err = pcall(case.run)
        assert(ok,"Bottle.TriggerFeedbackTests [" .. case.name .. "] " .. tostring(err))
    end
    return #cases
end

return Tests
