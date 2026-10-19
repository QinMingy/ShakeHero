-- 最新源表16项遗物立即附赠：正常Choose真实路径、内存快照，不读写玩家存档。
-- 附赠必须先永久入牌库，再由下一回合的正常抽取进入瓶中；不走当前瓶的生成FIFO。
local Game = require("Bottle.Game")
local Relics = require("Bottle.Relics")
local Effects = require("Bottle.RelicEffects")
local Repair = require("Bottle.RepairTests")
local PublishConfig = require("PublishConfig")
local Tests = {}

---@type {id:string, items:string[]}[]
local GRANTS = {
    {id="coin_rain",items={"cloud"}},
    {id="in_groups",items={"rabbit"}},
    {id="cheat_dice",items={"die_d6"}},
    {id="upgrade_coin_machine",items={"coin_machine"}},
    {id="tomato_tycoon",items={"tomato"}},
    {id="scramble_recipe",items={"egg","tomato"}},
    {id="see_you_tomorrow",items={"enoki"}},
    {id="teach_all",items={"teacher"}},
    {id="jungle_hunt",items={"killer"}},
    {id="cherry_plus",items={"cherry"}},
    {id="wash_hands",items={"thief"}},
    {id="chef_hat",items={"chef"}},
    {id="credit_line",items={"credit_card"}},
    {id="bacon_network",items={"bacon"}},
    {id="ghost_sport",items={"ghost"}},
    {id="lucky_roulette",items={"roulette"}},
}

---@param a any
---@param b any
---@return boolean
local function Equal(a,b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= "table" then return a == b end
    for key,value in pairs(a) do if not Equal(value,b[key]) then return false end end
    for key in pairs(b) do if a[key] == nil then return false end end
    return true
end

---@param id string
---@param ids string[]?
---@param relics table<string,boolean>?
---@return BottleGame
local function Draft(id,ids,relics)
    local snapshot = Repair.Fixture(ids or {"apple"},relics):Snapshot()
    snapshot.phase,snapshot.round,snapshot.stage = "draft",5,2
    snapshot.target = Game.GetTarget(2)
    snapshot.drawn,snapshot.options = {},{id}
    snapshot.relicDraft,snapshot.pendingRelicDraft = true,false
    snapshot.relicRefreshes,snapshot.refreshUsed = 1,false
    for _,item in ipairs(snapshot.instances) do item.location = "deck" end
    return Game.Restore(snapshot)
end

---@param game BottleGame
---@param uid integer
---@return ItemInstance
local function Item(game,uid)
    return (assert(game:Get(uid))) --[[@as ItemInstance]]
end

---@type {name:string,run:fun()}[]
local cases = {}
---@param name string
---@param run fun()
local function Test(name,run) cases[#cases+1]={name=name,run=run} end

for _,row in ipairs(GRANTS) do
    Test("正常遗物Choose一次永久附赠："..row.id,function()
        -- 已有同类也仍赠一份；不能误把“立即获得”实现为只在没有同类时补齐。
        local game = Draft(row.id,row.items)
        local before = game:Snapshot()
        ---@type ItemInstance[]
        local created = {}
        rawset(game,"_Create",function(self,id,temporary)
            assert(self.relics[row.id],"遗物标记必须先于附赠创建")
            local item = Game._Create(self,id,temporary)
            assert(item.location == "deck" and not item.temporary and not item.generatedTemporary,
                "附赠创建时必须是永久牌库物品，不是瓶内/临时生成")
            assert(#self.spawnQueue == 0,"附赠不能走瓶满FIFO")
            created[#created+1]=item
            return item
        end)
        assert(game:Choose(1) and game.relics[row.id] and #created == #row.items)
        rawset(game,"_Create",nil)
        assert(game.round == 6 and game.phase == "prepare")
        assert(#game.deck == #before.deck+#row.items and #game:AllInstances() == #before.instances+#row.items)
        for index,id in ipairs(row.items) do
            local item = assert(created[index],"缺少对应附赠实例")
            assert(item.id == id and item.uid == before.nextUid+index-1 and game:Get(item.uid) == item)
            -- 小牌库下一回合全部正常抽入，不是创建时直接入当前瓶。
            assert(item.location == "bottle")
            assert(Relics.byId[row.id].effect:find("立即获得",1,true))
        end
        local acquired = game:Snapshot()
        assert(not game:Choose(1) and Equal(acquired,game:Snapshot()))
        for _=1,3 do Effects.Maintain(game) end
        Effects.OnAcquire(game,row.id) -- 原接口仅维护，不附赠。
        assert(#game.deck == #before.deck+#row.items)
        local restored = Game.Restore(game:Snapshot())
        assert(Equal(game:Snapshot(),restored:Snapshot()),"读档不得补发或更改候选/RNG")
        -- 再次伪造已拥有遗物候选也必须由Choose拒绝，且不修改任意状态。
        restored.phase,restored.relicDraft,restored.options = "draft",true,{row.id}
        restored.relicRefreshes = 1
        local duplicate = restored:Snapshot()
        assert(not restored:Choose(1) and Equal(duplicate,restored:Snapshot()))
    end)
end

Test("21项无附赠遗物不创建物品、16项源表文字和映射完整",function()
    local giftIds = {}
    for _,row in ipairs(GRANTS) do giftIds[row.id]=true end
    local noGiftCount, giftItemCount = 0, 0
    for _,row in ipairs(GRANTS) do giftItemCount=giftItemCount+#row.items end
    for _,def in ipairs(Relics.list) do
        if not giftIds[def.id] then
            noGiftCount=noGiftCount+1
            assert(not def.effect:find("立即获得1个",1,true)
                and not def.effect:find("立即获得1张",1,true))
            local game = Draft(def.id)
            local count,nextUid = #game.deck,game._nextUid
            assert(game:Choose(1) and #game.deck == count and game._nextUid == nextUid)
        end
    end
    assert(#GRANTS == 16 and noGiftCount == 21 and giftItemCount == 17)
end)

Test("附赠创建每件正常触发积少成多、维护读档和GM不重复送",function()
    for _,row in ipairs(GRANTS) do
        local game = Draft(row.id,nil,{small_savings=true})
        local score,total,nextUid = game.score,game.totalScore,game._nextUid
        assert(game:Choose(1))
        assert(game.score-score == #row.items and game.totalScore-total == #row.items)
        assert(game._nextUid-nextUid == #row.items)
        for _=1,3 do Effects.Maintain(game) end
        local restored = Game.Restore(game:Snapshot())
        assert(restored._nextUid == game._nextUid and restored.score == game.score)
        local count = #restored.deck
        local beforeGm = restored:Snapshot()
        local ok, message = restored:GmAddItem("ball")
        if PublishConfig.PUBLISH_MODE ~= false then
            assert(ok == false and message == "发布模式已禁用 GM")
            assert(Equal(beforeGm, restored:Snapshot()), "发布GM拒绝不得添加实例、发金币或补送遗物附赠")
        else
            assert(ok)
        end
        Effects.Maintain(restored)
        if PublishConfig.PUBLISH_MODE ~= false then
            assert(Equal(beforeGm, restored:Snapshot()), "拒绝后的维护也不补送遗物附赠")
        else
            assert(#restored.deck == count+1 and restored.score-game.score == 1,
                "GM只添加指定物品，不重发已持遗物的附赠")
        end
    end
end)

Test("贷款额度先持有再送信用卡25、原有信用卡仍10且以后获取仍25",function()
    local game = Draft("credit_line",{"credit_card"})
    assert(game:_Value(Item(game,1)) == 10)
    assert(game:Choose(1))
    assert(game:_Value(Item(game,1)) == 10 and game:_Value(Item(game,2)) == 25)
    assert(Item(game,2).permBonus == 15)
    local card = game:_Create("credit_card")
    game.revision = game.revision + 1
    assert(game:Get(card.uid) == card and Item(game,3) == card and game:_Value(card) == 25)
    assert(#game.deck == 3 and game._nextUid == 4)
    Game.Restore(game:Snapshot())
end)

Test("旧档已有附赠遗物不追溯补发、单纯设置遗物和维护也不送",function()
    for _,row in ipairs(GRANTS) do
        local game = Repair.Fixture({"apple"})
        game.relics[row.id]=true
        local count,nextUid = #game.deck,game._nextUid
        Effects.Maintain(game)
        Effects.OnAcquire(game,row.id)
        assert(#game.deck == count and game._nextUid == nextUid)
        local snapshot = game:Snapshot()
        local restored = Game.Restore(snapshot)
        assert(Equal(snapshot,restored:Snapshot()) and #restored.deck == count)
    end
end)

Test("有教无类先附赠后维护追杀、原老师目标失效且新老师也受保护",function()
    local game = Draft("teach_all",{"teacher","doctor"},{jungle_hunt=true})
    game.huntTargetUid=1
    local calls = 0
    rawset(game,"_RandomInt",function(_,maximum)
        calls=calls+1
        assert(maximum>=1)
        return 1
    end)
    assert(game:Choose(1))
    rawset(game,"_RandomInt",nil)
    assert(calls>0 and #game.deck == 3 and Item(game,3).id == "teacher")
    assert(game.huntTargetUid == 2,"只能标记旧doctor，不可标记受保护新旧teacher")
end)

Test("Choose失败或Skip不赠、仅正常遗物成功获取会附赠",function()
    local game = Draft("coin_rain")
    local before = game:Snapshot()
    assert(not game:Choose(0) and not game:Choose(2) and Equal(before,game:Snapshot()))
    assert(game:Skip() and not game.relics.coin_rain and #game.deck == 1)
    local ordinary = Draft("coin_rain")
    ordinary.relicDraft=false
    before = ordinary:Snapshot()
    assert(not ordinary:Choose(1) and Equal(before,ordinary:Snapshot()))
    local missing = Repair.Fixture({"apple"})
    Effects.OnAcquired(missing,"coin_rain")
    assert(#missing.deck == 1,"未先持有遗物的误调用不得赠送")
end)

---@return integer
function Tests.Run()
    local passed,failures = 0,{}
    for _,case in ipairs(cases) do
        local ok,message=pcall(case.run)
        if ok then passed=passed+1 else failures[#failures+1]=case.name.."："..tostring(message) end
    end
    assert(#failures == 0,"Bottle.RelicGrantTests "..passed.."/"..#cases.." 通过\n"..table.concat(failures,"\n"))
    return passed
end
return Tests
