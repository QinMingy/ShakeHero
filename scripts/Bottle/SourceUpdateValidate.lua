-- 最新源表真实界面验收：沿既有独立View入口，不加载或保存玩家对局。
local UI = require("urhox-libs/UI")
local Core = require("urhox-libs.UI.Core.UI")
local Game = require("Bottle.Game")
local Physics = require("Bottle.Physics")
local View = require("Bottle.View")
local Items = require("Bottle.Items")
local Relics = require("Bottle.Relics")
local ItemText = require("Bottle.ItemText")
local Art = require("Bottle.Art")
local Repair = require("Bottle.RepairTests")
---@type any
local view = nil
local frame, checks, badgeDraws = 0, 0, 0
---@type BottlePhysics?
local knifePhysics = nil
local function Check(value, message)
    assert(value, "[源表界面验收] " .. message)
    checks = checks + 1
end

function Start()
    input.mouseMode = MM_ABSOLUTE
    UI.Init({theme=require("Bottle.Theme"),scale=UI.Scale.DEFAULT})
    require("Machine.Palette").Init()
    require("Bottle.ButtonMotion").Init()
    local game = Repair.Fixture({"chef","soul_stone","soldier","star","knife","apple"},
        {secret_recipe=true,meteor_shower=true})
    local physics = Physics.New()
    physics:Sync(game:BottleItems(),true,game.revision)
    local function noop() end
    view = View.New(game,physics,{shake=noop,start=noop,reroll=noop,refresh=noop,
        choose=noop,skip=noop,newrun=noop,import=noop,sensor=noop,sensorGain=noop,
        sensorLab=noop,atmosphere=noop,remove=noop,gmadd=noop,juicer=noop})
    view.machineSkin.litScene:ToggleCameraMotion()
    local badges = UI.Widget {position="absolute",left=12,top=220,width=110,height=110,
        pointerEvents="none",zIndex=36}
    function badges:Render(vg)
        local b=self:GetAbsoluteLayout()
        Art.Relic(vg,"secret_recipe",b.x+28,b.y+28,22)
        Art.Relic(vg,"meteor_shower",b.x+78,b.y+28,22)
        badgeDraws=badgeDraws+1
    end
    view.root:AddChild(badges)
    SubscribeToEvent("Update","HandleSourceUpdateValidation")
    SubscribeToEvent("PostUpdate","PrepareSourceUpdateValidation")
    print("[源表界面验收] 独立内存场景启动，发布权限未变")
end

function HandleSourceUpdateValidation()
    frame=frame+1
    if frame==12 then
        local game=view.game
        Check(#Items.list==98 and #Relics.list==39,"目录98／39")
        Check(Items.byId.soldier.name=="炊事兵","旧ID显示新职业名称")
        Check(game:CooldownOf("chef")==4 and game:CooldownOf("soul_stone")==4,"新明示冷却")
        Check(Items.HasCooldown("chef") and Items.HasCooldown("soul_stone"),"新冷却环白名单")
        Check(ItemText.Effect(game,"chef"):find("永久增加1价值",1,true),"厨师说明为永久加值")
        Check(not ItemText.Effect(game,"chef"):find("切成",1,true),"厨师说明不再切果")
        game.relics.chef_hat=true
        Check(game:CooldownOf("chef")==4,"厨师帽不改变本体4秒冷却")
        local chef=assert(game:Get(1))
        -- 用真实消费路径取得强化，不直接伪造详情中的累计数值。
        local knife=assert(game:Get(5))
        local apple=assert(game:Get(6))
        assert(game:Start())
        game:Step(0,{pairs={{chef.uid,knife.uid},{chef.uid,apple.uid}}})
        game:Step(1,{pairs={{chef.uid,apple.uid}}})
        Check(apple.permBonus==2 and chef.remaining==3,"1秒时仍在本体冷却内")
        game:Step(2.99,{pairs={{chef.uid,apple.uid}}})
        Check(chef.chefBoost==1 and apple.permBonus==2,"3.99秒时仍未提前触发")
        game:Step(.01,{pairs={{chef.uid,apple.uid}}})
        Check(chef.chefBoost==1 and apple.permBonus==4,"4秒边界就绪后下一批仍永久+2")
        Check(game:_Value(chef)==4,"强化不改变厨师本体价值")
        game:Finish(); game:RevealStep(100)
        Check(Game.Restore(game:Snapshot()):Get(1).chefBoost==1,"跨回合快照保留强化")
        game.phase,game.relicDraft,game.options="draft",true,{"secret_recipe","meteor_shower","chef_hat"}
        view.draftSelected=1
        view:Update(true); Core.Layout()
        Check(view.draft~=nil,"新遗物真实候选已构建")
    elseif frame==15 then
        view:ShowItemNote(assert(view.game:Get(1)),"deck")
        Core.Layout()
        Check(view.detailEffect.plainText:find("当前：+1",1,true),"共用详情显示本厨师累计+1")
        Check(view.detailEffect.plainText:find("永久增加2价值",1,true),"共用详情显示每批实际+2")
        Check(view.detailEffect.plainText:find("冷却：4秒",1,true)
            and not view.detailEffect.plainText:find("冷却：1秒",1,true),"详情保持本体4秒、不显示帽子1秒")
    elseif frame==18 then
        Check(badgeDraws>0,"两种徽记已提交真实NanoVG绘制")
        Check(view.game.relics.secret_recipe and view.game.relics.meteor_shower,"拥有栏保留两遗物")
        Check(require("PublishConfig").PUBLISH_MODE==true,"未开放发布GM权限")
        print("[源表界面验收] PASS 断言="..checks.." 徽记绘制帧="..badgeDraws)
        local game=Repair.Fixture({"knife","chick"})
        assert(game:Start())
        local sim=Physics.New()
        knifePhysics=sim
        SubscribeToEvent("PhysicsBeginContact2D",function(_,data)
            sim:Contact(data --[[@as PhysicsBeginContact2DEventData]],true)
        end)
        SubscribeToEvent("PhysicsEndContact2D",function(_,data)
            sim:Contact(data --[[@as PhysicsEndContact2DEventData]],false)
        end)
        sim:Sync(game:BottleItems(),true,game.revision)
        -- 沿真实Box2D夹具：刀圆半径0.30米，鸡用既有凸片；中心间隔0.20米确保重叠。
        --   刀(0,3) ○[鸡(.2,3)] → 真接触才消费；接触回调只采样，Step返回后再删刚体。
        for uid=1,2 do
            local record=assert(sim.bodies[uid])
            record.node:SetPosition2D((uid-1)*.2,3)
            record.node.rotation2D=0
            record.body.gravityScale=0
            record.body.linearVelocity=Vector2(0,0)
            record.body.angularVelocity=0
            record.body.awake=true
        end
        sim:Step(1/60)
        local contacts=sim:Contacts()
        local touching=false
        for _,pair in ipairs(contacts.pairs) do
            if pair[1]==1 and pair[2]==2 then touching=true end
        end
        Check(touching,"小刀与鸡产生真实Box2D接触")
        local events=game:Step(1/60,contacts)
        Check(assert(game:Get(2)).location=="discard" and game.roundScore==6,"真接触消费鸡并给6金币")
        local remaining=assert(game:Get(1)).remaining
        Check(remaining<=4 and remaining>=4-1/60-1e-7,"真接触后共用4秒冷却并扣本步已过时间")
        sim:RememberEvents(events); sim:Sync(game:BottleItems())
        Check(sim.bodies[2]==nil and sim.bodies[1]~=nil,"消费后鸡刚体移除且刀保留")
        view:CloseItemDetail()
        local noteKnife=view.game:_Create("knife")
        view:ShowItemNote(noteKnife,"deck")
        Core.Layout()
        local effect=view.detailEffect.plainText
        Check(effect:find("小鸡价值×2",1,true) and effect:find("冷却：4秒",1,true),"实例详情显示新鸡收益与4秒")
        Check(not effect:find("羊毛",1,true) and not effect:find("5秒",1,true),"实例详情不残留旧脱毛或5秒")
        Check(view:InspectDefinition("chick"),"小鸡引用图鉴可打开")
        view:CloseDefinition()
        Check(view:InspectDefinition("knife"),"小刀图鉴可打开")
        Check(view.definitionEffect.plainText:find("冷却：4秒",1,true),"图鉴详情同源4秒")
        view:CloseDefinition()
        print("[小刀原生验收] PASS 追加断言="..(checks-18).." 总断言="..checks)
    end
end

function PrepareSourceUpdateValidation()
    if view then view.machineSkin.litScene.post:PrepareFrame() end
end

function Stop()
    if knifePhysics then knifePhysics:Dispose(); knifePhysics=nil end
    if view then UI.SetRoot(nil); view.root:Destroy(); view.physics:Clear() end
    UI.Shutdown()
end
