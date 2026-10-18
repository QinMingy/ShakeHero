-- 官方运行器真实main隔离UI验收入口，同时作为-validate-test脚本。
-- 启动先mock玩家存档；建议360x780、26帧、截图第20帧，不修改现有Tests。
-- 默认截图扩展画廊；传-expansion-ui-pig保留猪详情，-expansion-ui-relics展示九遗物徽记。
local Storage = require("Bottle.Storage")
local V = _G["V"]
if not V then
    Storage.Load = function() return nil end
    Storage.Save = function() Storage.status="93件UI专项内存存档"; return true end
    Storage.expansionUIIsolated = true
    require("Bottle.ExpansionUITests").Run()
    require("main")
    return
end

local UI = require("urhox-libs/UI")
local Core = require("urhox-libs.UI.Core.UI")
local Items = require("Bottle.Items")
local Art = require("Bottle.Art")
local Shapes = require("Bottle.Shapes")
local DeckBoard = require("Bottle.DeckBoard")
local Tests = require("Bottle.ExpansionUITests")
local Audio = require("Bottle.Audio")
local Relics = require("Bottle.Relics")
local ItemText = require("Bottle.ItemText")
local pigScreenshot, relicScreenshot = false, false
for _, argument in ipairs(GetArguments()) do
    if argument == "-expansion-ui-pig" then pigScreenshot = true end
    if argument == "-expansion-ui-relics" then relicScreenshot = true end
end
---@type any
local view, game, physics = {}, {}, {}
local firstPigUid, secondPigUid, bodyguardUid, eggUid = 0, 0, 0, 0

local function Check(condition, message) V.assert(condition, message) end
local function Contains(text, fragment) return text:find(fragment,1,true)~=nil end
local function Guard(frame, callback)
    V.atFrame(frame,function()
        local ok,err=pcall(callback)
        Check(ok,"ExpansionUI frame"..frame..(ok and "完成" or " | "..tostring(err)))
    end)
end
local function Button(root,id)
    local button=assert(root:FindById(id),"找不到按钮"..id) --[[@as Button]]
    return button
end
-- 缩短离线验收帧数：只令页面表现弹簧走到稳定，不推进玩法物理/冷却。
local function Press(root,id)
    for _=1,180 do view.machineSkin.pageMotion:Tick(1/60) end
    local button=Button(root,id)
    assert(not button:IsDisabled(),"专项不可点击禁用按钮"..id)
    local callback = button.props.onClick
    assert(callback, "按钮未接线" .. id)
    if callback then callback(button, nil) end
end
local function Prose(root,id)
    local widget=assert(root:FindById(id),"找不到说明"..id) --[[@as BottleDescription]]
    return widget:GetText()
end
local function Ready()
    game.phase="prepare"
    view.modal:Hide();view.draft:Hide();view:CloseDefinition();view:CloseItemDetail()
    view:Update(true)
    UI.Layout()
end

-- 原图案按实际Art.Item绘制，不导出替代图；同时列出羊的三档库存表现。
local function Gallery()
    view:CloseInventory()
    local panel=view:Modal("93件扩展 · 图案实绘")
    local grid=UI.Panel {width="100%",flexGrow=1,flexBasis=0,gap=2}
    ---@type {id:string,label:string,woolCount:number?}[]
    local entries={}
    for number=71,93 do entries[#entries+1]={id=Items.byNumber[number].id,label=tostring(number)} end
    for _,stock in ipairs({0,1,5}) do entries[#entries+1]={id="sheep",woolCount=stock,label="毛"..stock} end
    for first=1,#entries,5 do
        local row=UI.Panel {width="100%",flexGrow=1,flexBasis=0,flexDirection="row",gap=2}
        for column=first,math.min(first+4,#entries) do
            local entry=entries[column]
            local cell=UI.Panel {flexGrow=1,flexBasis=0,minWidth=0,height="100%",
                alignItems="center",justifyContent="center",gap=1}
            local icon=UI.Widget {width="100%",flexGrow=1,flexBasis=0,pointerEvents="none"} --[[@as any]]
            function icon:Render(vg)
                local b=self:GetAbsoluteLayout()
                local radius=math.min(b.w,b.h)*.38
                Art.Item(vg,entry.id,b.x+b.w/2,b.y+b.h/2,radius,0,false,nil,entry.woolCount)
            end
            cell:AddChild(icon)
            cell:AddChild(UI.Label {text=entry.label,fontSize=9,textAlign="center",textMotionDisabled=true,
                fontColor={226,214,174,255},pointerEvents="none"})
            row:AddChild(cell)
        end
        grid:AddChild(row)
    end
    panel:AddChild(grid)
    UI.Layout()
end

Guard(2,function()
    local api=assert(_G["BottleValidationGet"]())
    view,game,physics=api.GetView(),api.GetGame(),api.GetPhysics()
    Check(Storage.expansionUIIsolated==true,"启动前隔离玩家存档读写")
    view.startScreen:Close();view.startScreen:Update(.41)
    Tests.Run(Check)
    for number=71,93 do
        local def=assert(Items.byNumber[number])
        Check(Art.HasSprite(def.id),"新增图案已接线"..def.id)
        Check(Shapes.profiles[def.shape]~=nil,"新增碰撞轮廓已接线"..def.id)
    end
    game.refreshes=3;game.rerollUsed=true;game.refreshUsed=true
    Ready()
    local reroll=Button(view.footer,"prepareReroll")
    Check(not reroll:IsDisabled() and reroll.props.text=="重抽 · 3 次","准备按钮只依赖共享次数")
    Check(view.footer:FindById("refreshPoolHint")~=nil,"机台准备区有刷新池提示")
    Press(view.footer,"prepareReroll")
    Check(game.refreshes==2 and not Button(view.footer,"prepareReroll"):IsDisabled(),"成功重抽一次扣1且按钮仍可用")
    Press(view.footer,"prepareReroll")
    Check(game.refreshes==1,"同回合第二次重抽可成功")
    game.refreshes=0;view:Update()
    Check(Button(view.footer,"prepareReroll"):IsDisabled(),"刷新池归零即禁用，不依赖revision")
end)

Guard(3,function()
    game.phase="draft";game.relicDraft=false;game.options={"pig","bodyguard","egg"}
    game.refreshes=2;game.refreshUsed=true;game.revision=game.revision+1
    view:Update(true);UI.Layout()
    local refresh=Button(view.draft,"draftRefresh")
    Check(refresh.props.text=="刷新 · 2 次" and not refresh:IsDisabled(),"LayeredSkin物品刷新显示累计可用次数")
    local beforeKey=view.machineSkin.draftMotionKey
    Press(view.draft,"draftRefresh")
    Check(game.refreshes==1 and not Button(view.draft,"draftRefresh"):IsDisabled(),"物品刷新成功扣1可再次刷新")
    Check(beforeKey~=view.machineSkin.draftMotionKey,"多次刷新重置候选动画生命周期")
    game.relicDraft=true;game.options={"chef_hat","wash_hands","lucky_charm"};view:Update(true)
    Check(Button(view.draft,"draftRefresh").props.text=="刷新 · 1 次","遗物三选一与物品共用剩余池")
    Press(view.draft,"draftRefresh")
    Check(game.refreshes==0 and Button(view.draft,"draftRefresh"):IsDisabled(),"遗物刷新耗尽共享池即禁用")
end)

Guard(4,function()
    Ready()
    local a,b=game:_Create("pig"),game:_Create("pig")
    a.scale,a.weight=1.2,1.7;b.scale,b.weight=1.8,.6
    local guard,egg=game:_Create("bodyguard"),game:_Create("egg")
    guard.counter,egg.bottleRounds,egg.counter=2,2,9
    firstPigUid,secondPigUid,bodyguardUid,eggUid=a.uid,b.uid,guard.uid,egg.uid
    for _,item in ipairs({a,b,guard,egg}) do item.location="bottle" end
    game.revision=game.revision+1
    physics:Sync(game:BottleItems(),true,19);view:Rebind(game)
    view.board.pops,view.board.popByUid={},{}
    view:InspectItem(firstPigUid)
    Check(Contains(view.detailEffect:GetText(),"体积（当前：120%）")
        and Contains(view.detailEffect:GetText(),"重量（当前：170%）"),"瓶内猪A说明读取自身倍率")
    view:InspectItem(secondPigUid)
    Check(Contains(view.detailEffect:GetText(),"体积（当前：180%）")
        and Contains(view.detailEffect:GetText(),"重量（当前：60%）"),"瓶内猪B不借用同名实例")
    view:InspectItem(bodyguardUid)
    Check(Contains(view.detailEffect:GetText(),"当前：2"),"瓶内保镖盾次数")
    view:InspectItem(eggUid)
    Check(Contains(view.detailEffect:GetText(),"当前：2"),"瓶内鸡蛋入瓶回合而非counter=9")
    view:OpenInventory();view:ShowDeckItem(firstPigUid)
    Check(Contains(Prose(view.modal,"deckDescription"),"重量（当前：170%）"),"牌库详情使用相同实例动态入口")
    view:CloseInventory()
end)

Guard(5,function()
    local pig=assert(game:Get(firstPigUid))
    game.phase="draft";game.relicDraft=false;game.options={pig,"bodyguard","egg"}
    view.draftSelected=1;game.refreshes=1;view:Update(true);UI.Layout()
    Check(Contains(Prose(view.draft,"draftDescription_1"),"重量（当前：170%）"),"LayeredSkin已有实例候选使用实例动态值")
    game.options={"pig","bodyguard","egg"};view:Update(true)
    Check(Contains(Prose(view.draft,"draftDescription_1"),"重量（当前：100%）"),"新候选不读取已有猪倍率")
    Ready()
    local oldRGBA=_G["nvgRGBA"]
    local bubbles=0
    _G["nvgRGBA"]=function(r,g,b,a)
        if r==167 and g==233 and b==247 and a==164 then bubbles=bubbles+1 end
        return oldRGBA(r,g,b,a)
    end
    local human=assert(game:Get(bodyguardUid))
    local ok,err=pcall(function()
        human.shielded=true
        view.board.pops,view.board.popByUid={},{}
        view.board:Render(Core.GetNVGContext())
        Check(bubbles==1,"真实Board提交透明护盾像素圈")
        bubbles=0;human.shielded=false
        view.board:Render(Core.GetNVGContext())
        Check(bubbles==0,"清盾后真实Board不再绘制泡泡")
    end)
    human.shielded=false;_G["nvgRGBA"]=oldRGBA
    assert(ok,err)
end)

Guard(6,function()
    ---@type any
    local balloon={uid=101,id="balloon",scale=1,weight=1,rollValue=nil}
    local sim=DeckBoard.Sim.New({balloon})
    local ok,err=pcall(function()
        local record=assert(sim.records[balloon.uid])
        Check(record.body.gravityScale==1,"牌库气球不改重力")
        for _,shape in ipairs(record.shapes) do Check(math.abs(shape.density-.35)<1e-6,"气球100%重量对应原型密度.35") end
        balloon.weight=1.7;sim:Sync()
        for _,shape in ipairs(record.shapes) do Check(math.abs(shape.density-.595)<1e-6,"气球实时重量乘原型密度") end
    end)
    sim:Dispose();assert(ok,err)
    game.relics.wash_hands=true;game.relics.teach_all=true;game.relics.lucky_charm=true
    view:InspectDefinition("hay")
    Check(Contains(view.definitionEffect:GetText(),"价值永久+1"),"真实定义弹窗幸运符草堆说明")
    view:CloseDefinition()
    view:OpenGm()
    local field=assert(view.modal:FindById("gmItemId")) --[[@as TextField]]
    Check(Contains(field.props.placeholder,"1–93"),"GM入口提示93个固定ID")
    view.modal:Hide()
    Ready();view:OpenInventory();view:ShowDeckItem(firstPigUid)
end)

Guard(7,function()
    local sound=cache:GetResource("Sound","audio/sfx/calf_moo.wav") --[[@as Sound?]]
    Check(sound~=nil,"牛冲刺短音频是真实可加载Sound资源")
    if sound then Check(math.abs(sound.length-.48)<.03,"牛叫资源长度约0.48秒") end
    Check(type(Audio.Calf)=="function","牛叫播放接口已接线")
    local ok=pcall(Audio.Calf)
    Check(ok,"实际调用牛叫SoundSource播放接口不报错（不代表已听音）")
    Ready()
    local sheep=game:_Create("sheep")
    sheep.woolCount=7;sheep.location="bottle";game.revision=game.revision+1
    physics:Sync(game:BottleItems(),true,33);view:Rebind(game);view:InspectItem(sheep.uid)
    Check(Contains(view.detailEffect:GetText(),"当前：7") and view.detailIcon.woolCount==7,"瓶内小羊库存及图案参数")
    view:CloseItemDetail();view:OpenInventory();view:ShowDeckItem(sheep.uid)
    Check(Contains(Prose(view.modal,"deckDescription"),"当前：7"),"牌库小羊库存说明")
    view:CloseInventory()
    game.phase="draft";game.relicDraft=false;game.options={sheep,"knife","wool"};view.draftSelected=1
    view:Update(true)
    local icon=assert(view.draft:FindById("draftPreviewIcon")) --[[@as any]]
    Check(icon.woolCount==7 and Contains(Prose(view.draft,"draftDescription_1"),"当前：7"),"实例候选小羊使用自己的毛量")
    game.options={"sheep","knife","wool"};view:Update(true)
    icon=assert(view.draft:FindById("draftPreviewIcon")) --[[@as any]]
    Check(icon.woolCount==nil and Contains(Prose(view.draft,"draftDescription_1"),"当前：0"),"新小羊候选默认无毛")
    Ready();view:OpenInventory();view:ShowDeckItem(firstPigUid)
end)

Guard(8,function()
    view:CloseInventory();Ready()
    local chef=game:_Create("chef");chef.location="bottle";chef.remaining=.5
    physics:Sync(game:BottleItems(),true,39);view:Rebind(game)
    game.phase="running";game.relics.chef_hat=nil
    view.board.pops,view.board.popByUid={},{}
    local original=game.CooldownOf
    local queried=0
    game.CooldownOf=function(self,id)
        if id=="chef" then queried=queried+1 end
        return original(self,id)
    end
    local ok,err=pcall(function()
        view.board:Render(Core.GetNVGContext())
        Check(queried==0,"无帽厨师内部5秒不显示冷却环")
        game.relics.chef_hat=true
        view.board:Render(Core.GetNVGContext())
        Check(queried>0 and game:CooldownOf("chef")==1,"持帽厨师显示实际1秒冷却环")
    end)
    game.CooldownOf=original
    assert(ok,err)
    Ready();view:OpenInventory();view:ShowDeckItem(firstPigUid)
end)

Guard(9,function()
    Ready();view:CloseInventory()
    Check(#Relics.list==33,"真实main加载33遗物目录")
    for number=25,33 do
        local def=Relics.byNumber[number]
        game.phase="draft";game.relicDraft=true;game.options={def.id,"lucky_charm","credit_line"}
        view.draftSelected=1;view:Update(true);UI.Layout()
        local prose=assert(view.draft:FindById("draftDescription_1"))
        Check(prose.props.text==def.effect,"新增遗物候选描述实际接线#"..number)
        local icon=assert(view.draft:FindById("draftPreviewIcon")) --[[@as any]]
        Check(icon.isRelic and icon.itemId==def.id,"新增遗物候选徽记实际接线#"..number)
    end
    game.relics.food_comfort=true;game.relics.tomato_tycoon=true;game.relics.ghost_poop=true
    game.relics.premium_grass=true;game.relics.wool_market=true;game.relics.coin_rain=true
    game.phase="draft";game.relicDraft=false;game.options={"apple","tomato","sheep"}
    view.draftSelected=1;view:Update(true)
    Check(ItemText.InitialValue(game --[[@as BottleGame]],"apple")==4 and Contains(Prose(view.draft,"draftDescription_1"),"当前价值+2"),
        "真实食物候选价值及持有说明一致")
    view:InspectDefinition("poop")
    Check(Contains(view.definitionEffect:GetText(),"自由飘动，可穿透物品"),"真实便便定义弹窗反映遗物穿透")
    view:CloseDefinition()
    view:InspectDefinition("cloud")
    Check(Contains(view.definitionEffect:GetText(),"6个临时") and not Contains(view.definitionEffect:GetText(),"水珠"),
        "真实云定义保持额外批临时并替换硬币")
    view:CloseDefinition()
    game.relics.food_comfort=nil;game.relics.tomato_tycoon=nil;game.relics.ghost_poop=nil
    game.relics.premium_grass=nil;game.relics.wool_market=nil;game.relics.coin_rain=nil
    Ready();view:OpenInventory();view:ShowDeckItem(firstPigUid)
end)

Guard(10,function()
    if relicScreenshot then
        view:CloseInventory()
        local panel=view:Modal("新增遗物 · 25–33")
        local grid=UI.Panel {width="100%",flexGrow=1,flexBasis=0,gap=8}
        for first=25,33,3 do
            local row=UI.Panel {width="100%",flexGrow=1,flexBasis=0,flexDirection="row",gap=6}
            for number=first,math.min(first+2,33) do
                local def=Relics.byNumber[number]
                local cell=UI.Panel {flexGrow=1,flexBasis=0,minWidth=0,height="100%",gap=4,alignItems="center"}
                local icon=UI.Widget {width="100%",flexGrow=1,flexBasis=0,pointerEvents="none"} --[[@as any]]
                function icon:Render(vg)
                    local b=self:GetAbsoluteLayout()
                    Art.Relic(vg,def.id,b.x+b.w/2,b.y+b.h/2,math.min(b.w,b.h)*.4)
                end
                cell:AddChild(icon)
                cell:AddChild(UI.Label {text=number.." "..def.name,fontSize=11,textMotionDisabled=true,
                    fontColor={226,214,174,255},textAlign="center",width="100%",whiteSpace="normal"})
                row:AddChild(cell)
            end
            grid:AddChild(row)
        end
        panel:AddChild(grid);UI.Layout()
    elseif not pigScreenshot then Gallery() end
end)

Guard(11,function()
    local Game=require("Bottle.Game")
    local Board=require("Bottle.Board")
    local probe=Game.New(12031)
    local item=assert(probe:BottleItems()[1])
    local transient=Board {game=probe,physics=physics,width=320,height=480}
    local ok,err=pcall(function()
        probe:Start()
        transient:Effects(probe.startEvents);probe.startEvents={}
        for _=1,24 do
            local events={}
            probe:_Score(events,item,1)
            for _,event in ipairs(events) do if event.kind=="score" then event.x,event.y=0,3 end end
            transient:Effects(events)
            transient:Update(1/60)
        end
        Check(#transient.scoreQueue>=24,"running多笔即时收益不被下一帧清空")
        local finishing=probe:Finish()
        for _,event in ipairs(finishing) do if event.kind=="score" then event.x,event.y=0,3 end end
        transient:Effects(finishing)
        local count=#transient.scoreQueue
        Check(count>=28 and probe._revealPopCount>=count,"Game展示预算覆盖running与统一结算的所有正收益")
        local expected=math.min(probe.REVEAL_SCORE_INTERVAL,
            math.max(probe.REVEAL_SCORE_MIN_INTERVAL,probe.REVEAL_SCORE_BUDGET/probe._revealPopCount))
        local elapsed,lastPop,stable=0,0,true
        for _=1,2000 do
            local before=#transient.scoreQueue
            probe:RevealStep(1/120)
            transient:Update(1/120)
            elapsed=elapsed+1/120
            if #transient.scoreQueue<before then lastPop=elapsed end
            if probe.phase~="reveal" then break end
            if math.abs((transient.scorePopInterval or 0)-expected)>1e-9 then stable=false end
        end
        Check(stable,"整段reveal节拍固定不随剩余数变慢")
        Check(#transient.scoreQueue==0,"20+浮字全部播完不被阶段提前截断")
        Check(elapsed-lastPop>=probe.REVEAL_DELAY-1/60,"最后浮字后至少停留2秒")
    end)
    transient:Destroy()
    assert(ok,err)
end)

Guard(12,function()
    if pigScreenshot then
        local prose=assert(view.modal:FindById("deckDescription")) --[[@as BottleDescription]]
        -- 慢速离屏渲染的wall time不等于Update dt；推进真实文字逐字出现，不改内容/布局。
        prose:Update(5)
        local scroll=assert(view.modal:FindById("deckEffectScroll"))
        local box=scroll:GetAbsoluteLayout()
        Check(box.h>150,"猪详情真实滚动视口有足够高度")
        Check(Contains(prose:GetText(),"体积（当前：120%）")
            and Contains(prose:GetText(),"重量（当前：170%）"),"最终截图猪详情语义保持精确实例")
    end
end)

Guard(13,function()
    local Game=require("Bottle.Game")
    local exam=Game.New(9041)
    exam.round=5;exam.stage=1;exam.phase="draft";exam.relicDraft=false;exam.refreshes=4
    exam.options=exam:_DraftOptions()
    local function NoCommon()
        for _,option in ipairs(exam.options) do
            local id=type(option)=="table" and option.id or option
            local def=exam.relicDraft and Relics.byId[id] or Items.byId[id]
            if not def or def.rarity==1 then return false end
        end
        return #exam.options>0
    end
    Check(NoCommon(),"第5回合物品候选不出现普通品质")
    exam:DraftRefresh();Check(NoCommon(),"第5回合物品刷新仍不出现普通品质")
    exam.relicDraft=true;exam.options=exam:_RelicDraftOptions()
    Check(NoCommon(),"第5回合追加遗物候选不出现普通品质")
    exam:DraftRefresh();Check(NoCommon(),"第5回合遗物刷新仍不出现普通品质")
    Check(exam.refreshes==2,"考核两类刷新仍共享原次数池")
end)

Guard(19,function()
    Check(not view.startScreen:IsActive(),"专项最终截图不含开始页")
    Check(Storage.expansionUIIsolated==true,"全程不读写玩家存档")
end)

-- 截图在20帧自动退出；无截图运行由23帧明确结束。
Guard(23,function() V.finish() end)
