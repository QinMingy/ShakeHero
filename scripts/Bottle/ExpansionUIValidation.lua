-- 官方运行器真实main隔离UI验收入口，同时作为-validate-test脚本。
-- 启动先mock玩家存档；建议360x780、26帧、截图第20帧，不修改现有Tests。
-- 默认截图扩展画廊；-expansion-ui-sheep展示绵羊三档，-expansion-ui-pig保留猪详情。
-- -expansion-ui-relics展示25–37号遗物徽记；-expansion-ui-dash展示真实冲刺残影。
---@type any
local Storage = require("Bottle.Storage")
local V = _G["V"]
if not V then
    Storage.Load = function() return nil end
    Storage.Save = function() Storage.status="98件UI专项内存存档"; return true end
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
local PointerEvent = require("urhox-libs.UI.Core.PointerEvent")
-- 与最终源表独立对照，不从生产赠品表反向生成期望。
local acquisitionGrants = {
    {id="coin_rain",gifts={"cloud"}}, {id="in_groups",gifts={"rabbit"}},
    {id="cheat_dice",gifts={"die_d6"}}, {id="upgrade_coin_machine",gifts={"coin_machine"}},
    {id="tomato_tycoon",gifts={"tomato"}}, {id="scramble_recipe",gifts={"egg","tomato"}},
    {id="see_you_tomorrow",gifts={"enoki"}}, {id="teach_all",gifts={"teacher"}},
    {id="jungle_hunt",gifts={"killer"}}, {id="cherry_plus",gifts={"cherry"}},
    {id="wash_hands",gifts={"thief"}}, {id="chef_hat",gifts={"chef"}},
    {id="credit_line",gifts={"credit_card"}}, {id="bacon_network",gifts={"bacon"}},
    {id="ghost_sport",gifts={"ghost"}}, {id="lucky_roulette",gifts={"roulette"}},
}
local pigScreenshot, relicScreenshot, sheepScreenshot, dashScreenshot = false, false, false, false
for _, argument in ipairs(GetArguments()) do
    if argument == "-expansion-ui-pig" then pigScreenshot = true end
    if argument == "-expansion-ui-relics" then relicScreenshot = true end
    if argument == "-expansion-ui-sheep" then sheepScreenshot = true end
    if argument == "-expansion-ui-dash" then dashScreenshot = true end
end
---@type any
local view = {}
---@type any
local game = {}
---@type any
local physics = {}
local firstPigUid, secondPigUid, bodyguardUid, eggUid = 0, 0, 0, 0

local function Check(condition, message) V.assert(condition, message) end
local function Contains(text, fragment) return text:find(fragment,1,true)~=nil end
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
-- Description的公开文本是名称展开；同时保留原模板、引用顺序和真实点击接线检查。
---@param prose BottleDescription
---@param template string
---@param label string
local function DescriptionMatches(prose,template,label)
    local readable=template:gsub("@",""):gsub("%[%[([%w_]+)%]%]",function(id)
        return assert(Items.byId[id]).name
    end)
    Check(prose.props.text==template and prose:GetText()==readable,label.."原模板和可读名称展开完全一致")
    local references={}
    for id in template:gmatch("%[%[([%w_]+)%]%]") do references[#references+1]=id end
    local seen=0
    for _,segment in ipairs(prose:GetSegments()) do
        if segment.kind=="item" then
            seen=seen+1
            Check(segment.itemId==references[seen],label.."引用顺序"..seen)
        end
    end
    Check(seen==#references,label.."内联图案数量完整")
end
---@param prose BottleDescription
---@param id string
---@param label string
local function InspectLink(prose,id,label)
    prose:Update(10) -- 只推进真实逐字呈现，GetLinkBounds仅返回已完全出现的链接。
    UI.Layout()
    local links=prose:GetLinkBounds()
    ---@type BottleDescriptionRun?
    local target=nil
    for _,link in ipairs(links) do if link.itemId==id then target=link end end
    Check(target~=nil,label.."有已呈现的"..id.."引用命中框")
    if not target then return end
    local data={pointerId=701,pointerType="mouse",x=target.x+target.w/2,y=target.y+target.h/2,
        button=MOUSEB_LEFT,buttons=1 << MOUSEB_LEFT,isPrimary=true,target=prose}
    prose:OnPointerDown(PointerEvent.new(PointerEvent.Types.PointerDown,data))
    prose:OnPointerUp(PointerEvent.new(PointerEvent.Types.PointerUp,data))
    prose:OnClick(PointerEvent.new(PointerEvent.Types.PointerUp,data))
    Check(view.definitionModal:IsVisible() and view.definitionId==id,
        label.."真实Description点击打开正确物品定义"..id)
    Check(view.definitionTitle:GetText()==Items.byId[id].name.." · "..Items.rarityNames[Items.byId[id].rarity],
        label.."链接弹窗标题和品质正确")
    view:CloseDefinition()
end
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
    game.relicDraft,game.pendingRelicDraft,game.relicRefreshes=false,false,0
    view.modal:Hide();view.draft:Hide();view:CloseDefinition();view:CloseItemDetail()
    view:Update(true)
    UI.Layout()
end

-- 原图案按实际Art.Item绘制，不导出替代图；同时列出羊的三档库存表现。
local function Gallery()
    view:CloseInventory()
    local panel=view:Modal("98件扩展 · 图案实绘")
    local grid=UI.Panel {width="100%",flexGrow=1,flexBasis=0,gap=2}
    ---@type {id:string,label:string,woolCount:number?}[]
    local entries={}
    for number=71,98 do entries[#entries+1]={id=Items.byNumber[number].id,label=tostring(number)} end
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
    for number=71,98 do
        local def=assert(Items.byNumber[number])
        Check(Art.HasSprite(def.id),"新增图案已接线"..def.id)
        Check(Shapes.profiles[def.shape]~=nil or def.shape=="circle","新增碰撞轮廓已接线"..def.id)
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
    game.drawn={}
    for _,item in ipairs(game.deck) do item.location="deck" end
    game.refreshes=2;game.refreshUsed=true;game.revision=game.revision+1
    view:Update(true);UI.Layout()
    local refresh=Button(view.draft,"draftRefresh")
    Check(refresh.props.text=="刷新 · 2 次" and not refresh:IsDisabled(),"LayeredSkin物品刷新显示累计可用次数")
    local beforeKey=view.machineSkin.draftMotionKey
    Press(view.draft,"draftRefresh")
    Check(game.refreshes==1 and not Button(view.draft,"draftRefresh"):IsDisabled(),"物品刷新成功扣1可再次刷新")
    Check(beforeKey~=view.machineSkin.draftMotionKey,"多次刷新重置候选动画生命周期")
    -- 走真实main跳过物品候选入口创建遗物draft，不手工补独立免费次数。
    local Game=require("Bottle.Game")
    game.round,game.stage,game.target=5,2,Game.GetTarget(2)
    game.refreshes=0;game.pendingRelicDraft=true;view:Update(true)
    Press(view.draft,"draftSkip")
    Check(game.relicDraft and game.refreshes==0,"普通共享余额0仍正常进入遗物选择")
    local relicRefresh=Button(view.draft,"draftRefresh")
    local relicHint=assert(view.draft:FindById("refreshPoolHint")) --[[@as Label]]
    Check(not relicRefresh:IsDisabled() and relicRefresh.props.text=="免费刷新 · 1 次"
        and Contains(relicHint:GetText(),"遗物") and Contains(relicHint:GetText(),"每次遗物三选一重置"),
        "真实遗物按钮显示本次免费1次且共享0仍可用")
    Press(view.draft,"draftRefresh")
    Check(game.relicRefreshes==0 and game.refreshes==0 and Button(view.draft,"draftRefresh"):IsDisabled(),
        "遗物刷新只扣独立池且第二次按钮禁用")
    Check(Button(view.draft,"draftRefresh").props.text=="免费刷新 · 0 次","真实遗物按钮耗尽后显示免费剩余0次")
    local spent=game:Snapshot()
    local restored=require("Bottle.Game").Restore(spent)
    Check(restored.relicRefreshes==0 and restored.refreshes==0 and Equal(spent,restored:Snapshot()),
        "遗物免费次数耗尽存档恢复0、不因重新载入补发")
    Check(not restored:DraftRefresh() and Equal(spent,restored:Snapshot()),
        "恢复后再次刷新失败且候选RNG普通余额均不变")
    Press(view.draft,"draftSkip")
    Check(game.phase=="prepare" and game.round==6 and game.relicRefreshes==0,
        "离开遗物选择后独立池归0不跨回合累积")
    -- 下一次考核的物品draft仍走真实main跳过按钮，再次进入才补本次免费1。
    game.round,game.stage,game.target=10,3,Game.GetTarget(3)
    game.phase,game.relicDraft,game.pendingRelicDraft="draft",false,true
    game.options={"knife","teacher","gear"};game.drawn={};game.refreshUsed=false
    for _,item in ipairs(game.deck) do item.location="deck" end
    view:Update(true);Press(view.draft,"draftSkip")
    Check(game.relicDraft and game.relicRefreshes==1 and game.refreshes==0
        and not Button(view.draft,"draftRefresh"):IsDisabled(),
        "下一次遗物draft重新免费1次、普通余额仍0且真实按钮可用")
    game.refreshes=1;view:Update(true)
    Press(view.draft,"draftRefresh")
    Check(game.relicRefreshes==0 and game.refreshes==1 and Button(view.draft,"draftRefresh"):IsDisabled(),
        "下一次遗物draft仍只能免费刷新一次、保留物品余额且不借用普通池")
    Press(view.draft,"draftSkip")
    Check(game.round==11 and game.phase=="prepare" and game.relicRefreshes==0 and game.refreshes==1,
        "完成下一考核遗物选择后回到合法准备阶段，免费池不保留")
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
    Check(view.definitionEffect.props.text==Items.byId.hay.effect
        and Contains(view.definitionEffect:GetText(),"价值永久-1"),"真实定义弹窗不混入幸运符效果")
    view:CloseDefinition()
    view:OpenGm()
    local field=assert(view.modal:FindById("gmItemId")) --[[@as TextField]]
    Check(Contains(field.props.placeholder,"1–98"),"GM入口提示98个固定ID")
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
    Check(#Relics.list==37,"真实main加载37遗物目录")
    for number=25,37 do
        local def=Relics.byNumber[number]
        game.phase="draft";game.relicDraft=true;game.options={def.id,"lucky_charm","credit_line"}
        view.draftSelected=1;view:Update(true);UI.Layout()
        local prose=assert(view.draft:FindById("draftDescription_1"))
        Check(prose.props.text==def.effect,"新增遗物候选描述实际接线#"..number)
        local icon=assert(view.draft:FindById("draftPreviewIcon")) --[[@as any]]
        Check(icon.isRelic and icon.itemId==def.id,"新增遗物候选徽记实际接线#"..number)
    end
    for number=94,98 do
        local def=assert(Items.byNumber[number])
        Check(view:InspectDefinition(def.id),"新增物品定义可打开#"..number)
        local dynamic=ItemText.Effect(game --[[@as BottleGame]],def.id)
        local readable=dynamic:gsub("@",""):gsub("%[%[([%w_]+)%]%]",function(id)
            return assert(Items.byId[id]).name
        end)
        Check(view.definitionEffect.props.text==dynamic and view.definitionEffect:GetText()==readable,
            "新增物品真实定义原模板及可读名称展开与动态入口一致#"..number)
        local references={}
        for id in dynamic:gmatch("%[%[([%w_]+)%]%]") do references[#references+1]=id end
        local seen=0
        for _,segment in ipairs(view.definitionEffect:GetSegments()) do
            if segment.kind=="item" then
                seen=seen+1
                Check(segment.itemId==references[seen],"新增物品定义引用按原序接线#"..number.."/"..seen)
            end
        end
        Check(seen==#references,"新增物品定义内联图案数量完整#"..number)
        view:CloseDefinition()
    end
    for _,entry in ipairs({
        {id="cactus",text="自身倍率增加对应数值（本回合）"},
        {id="fitness_coach",text="自身价值永久+1"},
    }) do
        view:InspectDefinition(entry.id)
        Check(Contains(view.definitionEffect:GetText(),entry.text),"真实定义说明同步最新规则："..entry.id)
        view:CloseDefinition()
    end
    game.relics.food_comfort=true;game.relics.tomato_tycoon=true;game.relics.ghost_poop=true
    game.relics.premium_grass=true;game.relics.wool_market=true;game.relics.coin_rain=true
    game.phase="draft";game.relicDraft=false;game.options={"apple","tomato","sheep"}
    view.draftSelected=1;view:Update(true)
    local appleProse=assert(view.draft:FindById("draftDescription_1"))
    Check(ItemText.InitialValue(game --[[@as BottleGame]],"apple")==4 and appleProse.props.text==Items.byId.apple.effect,
        "真实食物候选价值保留遗物加成且正文不混入遗物效果")
    view:InspectDefinition("poop")
    Check(view.definitionEffect.props.text==Items.byId.poop.effect and Items.IsPiercing("poop",game)
        and Contains(view.definitionEffect:GetText(),"被相邻植物消耗"),"真实便便定义正文独立于遗物穿透效果")
    view:CloseDefinition()
    view:InspectDefinition("cloud")
    Check(view.definitionEffect.props.text==Items.byId.cloud.effect
        and Contains(view.definitionEffect:GetText(),"水珠"),
        "真实云定义保持基础水珠说明")
    view:CloseDefinition()
    game.relics.food_comfort=nil;game.relics.tomato_tycoon=nil;game.relics.ghost_poop=nil
    game.relics.premium_grass=nil;game.relics.wool_market=nil;game.relics.coin_rain=nil
    view:InspectDefinition("pig")
    local pigDescription=view.definitionEffect
    DescriptionMatches(pigDescription,ItemText.Effect(game --[[@as BottleGame]],"pig"),"六目标小猪定义")
    local pigReferences={}
    for _,segment in ipairs(pigDescription:GetSegments()) do
        if segment.kind=="item" then pigReferences[segment.itemId]=true end
    end
    for _,id in ipairs({"apple","orange","banana","banana_peel","enoki","tomato_egg"}) do
        Check(pigReferences[id] and Contains(pigDescription:GetText(),Items.byId[id].name),
            "小猪真实Description列出六类消费目标"..id)
    end
    Check(Contains(pigDescription:GetText(),"×2") and Contains(pigDescription:GetText(),"金币"),
        "小猪真实说明保留消费前价值两倍金币")
    view:CloseDefinition()
    for _,id in ipairs({"golden_poop","diamond_poop","rainbow_poop"}) do
        view:InspectDefinition(id)
        DescriptionMatches(view.definitionEffect,ItemText.Effect(game --[[@as BottleGame]],id),"高品质便便"..id)
        Check(Contains(view.definitionEffect:GetText(),"植物") and Contains(view.definitionEffect:GetText(),"消耗"),
            "高品质便便真实Description明确植物可消费"..id)
        view:CloseDefinition()
    end
    for _,id in ipairs({"gambling_token","spin_reward"}) do
        local def=Relics.byId[id]
        game.phase="draft";game.relicDraft=true;game.options={id};view.draftSelected=1
        view:Update(true);UI.Layout()
        local prose=assert(view.draft:FindById("draftDescription_1")) --[[@as BottleDescription]]
        DescriptionMatches(prose,def.effect,"最终概率遗物"..id)
        if id=="gambling_token" then
            Check(Contains(prose:GetText(),"25%") and not Contains(prose:GetText(),"50%"),
                "令牌真实候选说明25%而非旧50%")
        else
            Check((Contains(prose:GetText(),"3圈") or Contains(prose:GetText(),"三圈"))
                and Contains(prose:GetText(),"30%"),"转圈圈真实候选说明三圈独立30%")
        end
    end
    for _,entry in ipairs(acquisitionGrants) do
        local def=Relics.byId[entry.id]
        game.phase="draft";game.relicDraft=true;game.options={entry.id};view.draftSelected=1
        view:Update(true);UI.Layout()
        local prose=assert(view.draft:FindById("draftDescription_1")) --[[@as BottleDescription]]
        DescriptionMatches(prose,def.effect,"赠品遗物"..entry.id)
        Check(Contains(prose:GetText(),"立即获得"),"赠品遗物真实说明有立即获得"..entry.id)
        local giftText=def.effect:match("立即获得(.*)") or ""
        for _,id in ipairs(entry.gifts) do
            Check(Contains(giftText,"[["..id.."]]"),"赠品条款引用正确物品"..entry.id.."/"..id)
            InspectLink(prose,id,"赠品遗物"..entry.id)
        end
    end
    Ready();view:OpenInventory();view:ShowDeckItem(firstPigUid)
end)

Guard(10,function()
    if sheepScreenshot then
        view:CloseInventory()
        local panel=view:Modal("绵羊 · 羊毛数量三档")
        for index,stock in ipairs({0,1,5}) do
            local row=UI.Panel {width="100%",flexGrow=1,flexBasis=0,flexDirection="row",gap=12,
                alignItems="center"}
            local icon=UI.Widget {width="55%",height="100%",pointerEvents="none"}
            function icon:Render(vg)
                local b=self:GetAbsoluteLayout()
                Art.Item(vg,"sheep",b.x+b.w/2,b.y+b.h/2,math.min(b.w,b.h)*.45,0,false,nil,stock)
            end
            row:AddChild(icon)
            row:AddChild(UI.Label {text=({"0 · 贴身短绒","1–4 · 蓬松卷绒","5+ · 厚卷毛"})[index],
                fontSize=16,textMotionDisabled=true,fontColor={245,242,224,255},pointerEvents="none"})
            panel:AddChild(row)
        end
        UI.Layout()
    elseif relicScreenshot then
        view:CloseInventory()
        local panel=view:Modal("新增遗物 · 25–37")
        local grid=UI.Panel {width="100%",flexGrow=1,flexBasis=0,gap=8}
        for first=25,37,3 do
            local row=UI.Panel {width="100%",flexGrow=1,flexBasis=0,flexDirection="row",gap=6}
            for number=first,math.min(first+2,37) do
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
        Check(#transient.scoreQueue==0 and transient.shakeCoinsInFlight+transient.roundScore.shakeTotal==24,
            "running的24笔即时收益当场飞币并累计左上角、不重复排入结算队列")
        for _=1,1200 do
            transient:Update(1/120)
            if not transient:CoinPickupsBusy() then break end
        end
        Check(not transient:CoinPickupsBusy() and transient.shakeCoinsInFlight==0
            and transient.roundScore.shakeTotal==24,"即时收益全部到达左上角，不被下一帧清空")
        local finishing=probe:Finish()
        for _,event in ipairs(finishing) do if event.kind=="score" then event.x,event.y=0,3 end end
        transient:Effects(finishing)
        local count=#transient.scoreQueue
        Check(count==4 and probe._revealPopCount>=count+24,
            "仅4笔最终结算进入队列，Game总事件预算仍覆盖24笔即时与最终收益")
        local expected=math.min(probe.REVEAL_SCORE_INTERVAL,
            math.max(probe.REVEAL_SCORE_MIN_INTERVAL,probe.REVEAL_SCORE_BUDGET/probe._revealPopCount))
        local elapsed,lastPop,lastBusy,stable=0,0,0,true
        for _=1,2400 do
            local before=#transient.scoreQueue
            local busy=transient:CoinPickupsBusy()
            if busy then lastBusy=elapsed end
            probe:RevealStep(1/120,busy)
            transient:Update(1/120)
            elapsed=elapsed+1/120
            if #transient.scoreQueue<before then lastPop=elapsed end
            if probe.phase~="reveal" then break end
            if math.abs((transient.scorePopInterval or 0)-expected)>1e-9 then stable=false end
        end
        Check(stable,"整段reveal节拍固定不随剩余数变慢")
        Check(probe.phase=="draft" and #transient.scoreQueue==0 and not transient:CoinPickupsBusy(),
            "即时转入与逐件结算飞币均播完、不被阶段提前截断")
        Check(elapsed-lastPop>=probe.REVEAL_DELAY-1/60
            and elapsed-lastBusy>=probe.REVEAL_DELAY-1/60,"最后浮字与全部飞币后至少停留2秒")
        Check(probe.roundScore==35,"24笔即时加4件最终收益（2+6+1+2）只入账一次、表现不改规则总分")
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
    local snapshot=Game.New(9041):Snapshot()
    snapshot.round,snapshot.stage,snapshot.phase=5,2,"draft"
    snapshot.target,snapshot.drawn,snapshot.options=Game.GetTarget(2),{},{}
    snapshot.relicDraft,snapshot.refreshes=false,4
    for _,item in ipairs(snapshot.instances) do item.location="deck" end
    local exam=Game.Restore(snapshot)
    exam.options=exam:_DraftOptions()
    local function NoCommon()
        for _,id in ipairs(exam.options) do
            if not Items.byId[id] or Items.byId[id].rarity==1 then return false end
        end
        return #exam.options>0
    end
    Check(NoCommon(),"第5回合物品候选不出现普通品质")
    Check(exam:DraftRefresh() and NoCommon(),"第5回合物品刷新仍不出现普通品质")
    rawset(exam,"_RandomInt",function() return 1 end)
    exam.pendingRelicDraft=true
    Check(exam:Skip() and exam.relicDraft and exam.relicRefreshes==1,
        "正常结束物品选择后独立发放1次免费遗物刷新")
    local function CommonRelics()
        if #exam.options~=3 then return false end
        for _,id in ipairs(exam.options) do
            if not Relics.byId[id] or Relics.byId[id].rarity~=1 then return false end
        end
        return true
    end
    Check(CommonRelics(),"第5回合追加遗物按原概率可出现普通品质")
    Check(exam:DraftRefresh() and CommonRelics(),"第5回合普通遗物刷新保持原普通档概率")
    Check(exam.refreshes==3 and exam.relicRefreshes==0,"考核物品扣普通池、遗物只扣独立免费池")
    local persisted=Game.Restore(exam:Snapshot())
    Check(persisted.options[1]==exam.options[1] and persisted.refreshes==3 and persisted.relicRefreshes==0,
        "普通遗物候选存档保序且耗尽独立池不补发")
    local exhausted=persisted:Snapshot()
    Check(not persisted:DraftRefresh() and Equal(exhausted,persisted:Snapshot()),
        "即使普通共享剩余3次也不能替代已用尽的遗物免费次数")
    local common=persisted.options[1]
    Check(persisted:Choose(1) and persisted.relics[common] and persisted.round==6,
        "考核后普通遗物选择成功并推进下回合")
    Check(Game.Restore(persisted:Snapshot()).relics[common],"正常获取普通遗物永久存档保留")
end)

-- 独立真Game走正常Choose；不Rebind主View，保留第10帧建好的最终画廊／猪／羊截图。
Guard(14,function()
    local Game=require("Bottle.Game")
    local giftCount=0
    for _,entry in ipairs(acquisitionGrants) do giftCount=giftCount+#entry.gifts end
    Check(#acquisitionGrants==16 and giftCount==17,"最终源表共有16件遗物赠品条款、共17份赠品")
    for _,entry in ipairs(acquisitionGrants) do
        local snapshot=Game.New(19041):Snapshot()
        snapshot.round,snapshot.stage,snapshot.phase=5,2,"draft"
        snapshot.target,snapshot.drawn,snapshot.options=Game.GetTarget(2),{},{entry.id}
        snapshot.relicDraft,snapshot.pendingRelicDraft=true,true
        snapshot.relicRefreshes,snapshot.refreshUsed=1,false
        snapshot.relics.small_savings=true -- 创建新实例才奖励；Restore不准重发该奖励。
        for _,item in ipairs(snapshot.instances) do item.location="deck" end
        local probe=Game.Restore(snapshot)
        Check(Equal(snapshot,probe:Snapshot()),"遗物候选Restore不提前赠品或消费RNG"..entry.id)
        local previousUid=snapshot.nextUid
        local previousCount,previousScore=#probe.deck,probe.score
        local advance=probe._AdvanceRound
        local advanced=0
        rawset(probe,"_AdvanceRound",function(self)
            advanced=advanced+1
            Check(self.relics[entry.id]==true,"正常Choose先获得遗物再推进"..entry.id)
            Check(#self.deck==previousCount+#entry.gifts and self._nextUid==previousUid+#entry.gifts,
                "正常Choose先永久创建全部赠品再推进"..entry.id)
            for index,id in ipairs(entry.gifts) do
                local gift=assert(self:Get(previousUid+index-1))
                Check(gift.id==id and gift.location=="deck" and not gift.temporary and not gift.generatedTemporary,
                    "推进前赠品永久在牌库、未直接进瓶"..entry.id.."/"..id)
                if id=="credit_card" then
                    Check(self:_Value(gift)==25 and gift.permBonus==15,
                        "贷款额度先持有后赠信用卡，初始有效价值25而非10")
                end
            end
            advance(self)
        end)
        Check(probe:Choose(1),"正常Game.Choose获得赠品遗物"..entry.id)
        rawset(probe,"_AdvanceRound",nil)
        Check(advanced==1 and probe.round==6 and probe.phase=="prepare" and probe.relics[entry.id],
            "获得遗物与赠品只推进下一回合一次"..entry.id)
        Check(#probe.deck==previousCount+#entry.gifts and #probe:AllInstances()==previousCount+#entry.gifts,
            "准备阶段赠品不丢失、不重复生成"..entry.id)
        Check(probe.score==previousScore+#entry.gifts,"真实_Create每份赠品只触发一次积少成多"..entry.id)
        for index,id in ipairs(entry.gifts) do
            local gift=assert(probe:Get(previousUid+index-1))
            Check(gift.id==id and (gift.location=="deck" or gift.location=="bottle")
                and not gift.temporary and not gift.generatedTemporary,
                "下一回合正常抽取后仍拥有永久赠品"..entry.id.."/"..id)
        end
        if entry.id=="scramble_recipe" then
            Check(assert(probe:Get(previousUid)).id=="egg" and assert(probe:Get(previousUid+1)).id=="tomato",
                "炒蛋秘籍确实赠鸡蛋和西红柿各一，不是现成炒蛋")
        end
        local acquired=probe:Snapshot()
        Check(not probe:Choose(1) and Equal(acquired,probe:Snapshot()),
            "旧遗物候选重复点击不补赠、不推进、不改分数与RNG"..entry.id)
        local restored=Game.Restore(acquired)
        Check(Equal(acquired,restored:Snapshot()) and #restored:AllInstances()==#probe:AllInstances(),
            "Save/Restore已拥有遗物保留全部赠品且不再次发放"..entry.id)
        local restoredAgain=Game.Restore(restored:Snapshot())
        Check(Equal(acquired,restoredAgain:Snapshot()),"连续第二次读档也不赠品"..entry.id)
    end
end)

-- 冲刺视觉专项：复用真实main/Board/Box2D，存档仍全程内存隔离。
Guard(15,function()
    local fixture = require("Bottle.RepairTests").Fixture({"calf", "grass", "jelly", "apple"})
    for key in pairs(game) do game[key] = nil end
    for key,value in pairs(fixture) do game[key] = value end
    game.phase = "running"
    rawset(game, "_RandomInt", function() return 1 end) -- 草无产物，隔离入场粒子。
    physics:Sync(game:BottleItems(),true,123)
    local function Place(uid,x,y)
        local record=assert(physics.bodies[uid])
        record.node:SetPosition2D(x,y);record.node.rotation2D=0
        record.body.gravityScale,record.body.linearDamping=0,0
        record.body.linearVelocity=Vector2(0,0);record.body.angularVelocity=0
    end
    Place(1,-1.5,3.7);Place(2,-1.2,3.7);Place(3,-1,1.5);Place(4,1,1.5)
    view:Rebind(game);view:CloseInventory();view:CloseItemDetail();view:CloseDefinition()
    view.modal:Hide();view.draft:Hide()
    UI.Layout()
    local board=view.board
    board.pops,board.popByUid,board.bursts={},{},{}
    board.presentUids={}
    for _,item in ipairs(game:BottleItems()) do board.presentUids[item.uid]=true end
    game._lastPositions=physics:Contacts().positions
    local events={}
    Check(game:_Destroy(2,false,events,assert(game:Get(1)),"consume"),"真实成功吃草触发冲刺")
    board:Effects(events);physics:RememberEvents(events);physics:Sync(game:BottleItems())
    Check(board.dashEmitters[1]~=nil and #board.dashTrails==0,"冲刺事件只开启采样，不伪造旧位置")
    for _=1,12 do physics:Step(1/60);board:UpdateDashTrails(1/60) end
    Check(#board.dashTrails>=3 and #board.dashTrails<=5,"少量真实轨迹残影，0.2秒内最多5张")
    local before=game:_Value(assert(game:Get(1)))
    local lastX=-math.huge
    for _,trail in ipairs(board.dashTrails) do
        Check(trail.uid==1 and trail.x>lastX and math.abs(trail.y-3.7)<1e-5,
            "残影顺序沿真实冲刺方向，不受默认事件坐标污染")
        Check(trail.age>=0 and trail.age<.2 and trail.radius==Items.byId.calf.radius,
            "残影保存原尺寸且有短生命周期")
        lastX=trail.x
    end
    local oldItem,oldAlpha=Art.Item,_G["nvgGlobalAlpha"]
    local drawn,alphas={},{}
    Art.Item=function(vg,id,x,y,r,angle,cooling,rollValue,woolCount)
        drawn[#drawn+1]={id=id,x=x,y=y,radius=r,angle=angle}
        oldItem(vg,id,x,y,r,angle,cooling,rollValue,woolCount)
    end
    _G["nvgGlobalAlpha"]=function(vg,alpha)
        alphas[#alphas+1]=alpha
        oldAlpha(vg,alpha)
    end
    local ok,err=pcall(function() board:Render(Core.GetNVGContext()) end)
    Art.Item,_G["nvgGlobalAlpha"]=oldItem,oldAlpha
    Check(ok,"真实NanoVG渲染残影无错误"..(ok and "" or tostring(err)))
    Check(#alphas==#board.dashTrails and #drawn>=#board.dashTrails+3,
        "每张残影真实提交原小牛图案，其他实体仍绘制")
    local ox,oy,ppu=board:GetBottleTransform()
    for index,trail in ipairs(board.dashTrails) do
        local draw=drawn[index]
        Check(draw and draw.id=="calf" and math.abs(draw.x-ox-trail.x*ppu)<1e-5
            and math.abs(draw.y-oy+trail.y*ppu)<1e-5 and math.abs(draw.angle+trail.angle)<1e-5,
            "残影在全部实体前绘制并复用米制变换和真实角度")
        Check(alphas[index]>0 and alphas[index]<=.32
            and (index==1 or alphas[index]>=alphas[index-1]),"旧残影更淡，最大32%不遮住本体")
    end
    for _=1,25 do physics:Step(1/60);board:UpdateDashTrails(1/60) end
    Check(#board.dashTrails==0 and next(board.dashEmitters)==nil,"冲刺结束后残影和计时全部回收")
    Check(game:_Value(assert(game:Get(1)))==before,"采样与绘制不改变任何价值奖励")
    board:Effects({{kind="dash",uid=1,duration=.35}})
    board:UpdateDashTrails(.1);board:UpdateDashTrails(.1)
    Check(#board.dashTrails==0,"顶墙或原地未移动不堆残影")
    Place(1,0,3.7);board:UpdateDashTrails(.05)
    Check(#board.dashTrails==1,"再次真实位移才追加残影")
    board:Effects({{kind="remove",uid=1}})
    Check(#board.dashTrails==0 and next(board.dashEmitters)==nil,"移除即时清残影与发射器")
    board:Effects({{kind="dash",uid=1,duration=.35}})
    Place(1,.3,3.7);board:UpdateDashTrails(.05)
    board:ResetEffects()
    Check(#board.dashTrails==0 and next(board.dashEmitters)==nil,"重摆或换局ResetEffects不遗留轨迹")
    if dashScreenshot then
        -- 确定性受控展示：12个真实物理步后冻结表现，不拿软件渲染wall time猜动作进度。
        game.phase="prepare";view:Update(true)
        game.phase="running"
        Place(1,-1.5,3.7)
        local dash={{kind="dash",uid=1,dx=1,dy=0,duration=.35}}
        board:Effects(dash);physics:RememberEvents(dash);physics:Sync(game:BottleItems())
        for _=1,12 do physics:Step(1/60);board:UpdateDashTrails(1/60) end
        game.phase="prepare"
        board.UpdateDashTrails=function() end -- 仅验收实例冻结，生产方法不改。
        Check(#board.dashTrails>=3,"截图冻结前仍有真实冲刺轨迹")
        UI.Layout()
    else
        game.phase="prepare"
    end
end)

Guard(19,function()
    Check(not view.startScreen:IsActive(),"专项最终截图不含开始页")
    Check(Storage.expansionUIIsolated==true,"全程不读写玩家存档")
end)

-- 截图在20帧自动退出；无截图运行由23帧明确结束。
Guard(23,function() V.finish() end)
