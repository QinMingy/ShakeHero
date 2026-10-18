-- 官方运行器真实main隔离验收入口；同时作为-validate-test脚本。
-- 入口先替换Storage.Load/Save，再require main，绝不读取/写入玩家存档。
-- 在/workspace/.repair-validation作cwd，360x780，建议14帧、截图第9帧。
---@type any
local Storage=require("Bottle.Storage")
local V=_G["V"]
if not V then
    Storage.Load=function() return nil end
    Storage.Save=function() Storage.status="专项测试内存存档（未落盘）"; return true end
    Storage.repairIsolated=true
    require("main")
    return
end

local UI=require("urhox-libs/UI")
local Core=require("urhox-libs.UI.Core.UI")
local Art=require("Bottle.Art")
local Items=require("Bottle.Items")
local T=require("Bottle.RepairTests")
local Description=require("Bottle.Description")
---@type {id:string,radius:number,x:number,y:number,angle:number,cooling:boolean,gray:number,color:number,rollValue:number?,minAlpha:number?,maxAlpha:number?}[]
local records={}
---@type any
local api=nil
---@type any
local view=nil
---@type BottleGame
local game=nil
---@type BottlePhysics
local physics=nil
local oldItem=Art.Item
---@type any
local currentDraw=nil
local rgba=_G["nvgRGBA"]
local fill=_G["nvgFill"]
_G["nvgFill"]=function(vg)
    if currentDraw then
        if currentDraw.ink then
            currentDraw.inkRects=currentDraw.inkRects or {}
            for _,r in ipairs(currentDraw.rects or {}) do currentDraw.inkRects[#currentDraw.inkRects+1]=r end
        end
        currentDraw.rects={}
    end
    return fill(vg)
end
local rect=_G["nvgRect"]
_G["nvgRect"]=function(vg,x,y,w,h)
    if currentDraw then
        currentDraw.rects=currentDraw.rects or {}
        currentDraw.rects[#currentDraw.rects+1]={x=x,y=y,w=w,h=h}
    end
    return rect(vg,x,y,w,h)
end
_G["nvgRGBA"]=function(r,g,b,a)
    if currentDraw then currentDraw.ink=r==10 and g==10 and b==26 end
    if currentDraw and a>0 then
        currentDraw.minAlpha = math.min(currentDraw.minAlpha or 255, a)
        currentDraw.maxAlpha = math.max(currentDraw.maxAlpha or 0, a)
        if r==g and g==b then currentDraw.gray=currentDraw.gray+1
        else currentDraw.color=currentDraw.color+1 end
    end
    return rgba(r,g,b,a)
end
Art.Item=function(vg,id,x,y,r,angle,cooling,rollValue)
    local draw={id=id,radius=r,x=x,y=y,angle=angle or 0,cooling=cooling==true,gray=0,color=0,rollValue=rollValue}
    currentDraw=draw
    oldItem(vg,id,x,y,r,angle,cooling,rollValue)
    currentDraw=nil
    records[#records+1]=draw
end

local function Check(condition,message) V.assert(condition,message) end
local function Near(a,b) return math.abs(a-b)<1e-6 end
local function Collect(id)
    local found={}
    for _,record in ipairs(records) do if record.id==id then found[#found+1]=record end end
    return found
end
local function Last(id)
    local found=Collect(id)
    return assert(found[#found],"没有实际绘制"..id)
end
local function Use(ids)
    local fixture=T.Fixture(ids)
    for key in pairs(game) do game[key]=nil end
    for key,value in pairs(fixture) do game[key]=value end
    physics:Sync(game:BottleItems(),true,17)
    view:Rebind(game)
    Core.Layout()
    -- 测试只排除入场缩放，不排除真实Board/Art绘制。
    view.board.pops,view.board.popByUid={},{}
    view.board.presentUids={}
    for _,item in ipairs(game:BottleItems()) do view.board.presentUids[item.uid]=true end
    records={}
end
local function Stats(root,label)
    local stats=root:FindById("itemStats")
    Check(stats~=nil,label.."保留金币/tag属性行")
    Check(root:FindById("cooldownValue")==nil,label.."无冷却属性Widget")
    if stats then
        Check(stats:FindById("goldValue")~=nil,label.."有金币属性")
        Check(stats:FindById("itemTag")~=nil,label.."有分类tag属性")
    end
end
local function Guard(frame,fn)
    V.atFrame(frame,function()
        local ok,err=pcall(fn)
        Check(ok,"UI frame"..frame.."完成"..(ok and "" or " | "..tostring(err)))
    end)
end

-- 挂在真实UI树上持续绘制，避免atFrame直接画图被后续帧覆盖。
-- 用原始生产Art.Item，不让画廊提交混入下面对真实Board残影的记录。
local function DiceGallery()
    ---@type Widget[]
    local rows={UI.Label{text="DICE FACES / REAL Art.Item",fontSize=17,height=42},
        UI.Label{text="d4: 1..4     d6: 1..6",fontSize=14,height=30}}
    for row=1,5 do
        local cells={}
        for column=1,2 do
            local index=(row-1)*2+column
            local id=index<=4 and "die_d4" or "die_d6"
            local value=index<=4 and index or index-4
            local glyph=UI.Panel{width=84,height=84,backgroundColor={30,36,40,255}}
            function glyph:Render(vg)
                self:RenderFullBackground(vg)
                local box=self:GetAbsoluteLayout()
                oldItem(vg,id,box.x+box.w/2,box.y+box.h/2,32,0,false,value)
            end
            cells[#cells+1]=UI.Panel{width="50%",alignItems="center",children={
                UI.Label{text=id.."_"..value,fontSize=15,height=25},glyph}}
        end
        rows[#rows+1]=UI.Panel{width="100%",flexDirection="row",flexGrow=1,children=cells}
    end
    local gallery=UI.Panel{id="repairDiceGallery",position="absolute",left=0,top=0,
        width="100%",height="100%",zIndex=10000,padding=12,
        backgroundColor={16,20,24,255},children=rows}
    -- 仅专项运行的最后两帧替换根，确保不被生产模态层/3D机台遮挡。
    UI.SetRoot(gallery)
    Core.Layout()
end

Guard(2,function()
    api=assert(_G["BottleValidationGet"]())
    view,game,physics=api.GetView(),api.GetGame(),api.GetPhysics()
    Check(Storage.repairIsolated==true,"真实main启动前注入Storage.Load/Save mock隔离玩家存档")
    view.startScreen:Close(); view.startScreen:Update(.41)
    Check(not view.startScreen:IsActive(),"截图及绘制验收排除开始页")
    Use({"ball","star","soul_jar","soul_stone","fruit_tree","cloud","lucky_coin","ghost","orange"})
    Check(view.board.Render==require("Bottle.Board").Render,"真实View使用拆出的Bottle.Board")
end)

Guard(3,function()
    Check(#records>0,"至少一帧真实NanoVG画布提交")
    Check(Near(Last("ghost").angle, 0), "幽灵真实画布绘制角度为零、正面直立")
    local ghost = Last("ghost")
    Check(ghost.minAlpha == 153 and ghost.maxAlpha == 153, "幽灵身体、描边与五官实际绘制均60%不透明")
    Check(Last("ball").minAlpha == 255 and Last("ball").maxAlpha == 255, "其他物品保持完全不透明")
    for _,id in ipairs({"ball","star","soul_jar","soul_stone","fruit_tree","cloud","lucky_coin","ghost","orange"}) do
        Check(not Last(id).cooling,id.."准备阶段实际绘制保持原色")
    end
    Check(game:Start(),"开始真实规则运行")
    view:Update(true)
    view.board.pops,view.board.popByUid={},{}
    records={}
end)

Guard(4,function()
    local ball=Last("ball")
    Check(ball.cooling and ball.gray>0 and ball.color==0,"真正冷却的小球实际提交纯灰阶")
    for _,id in ipairs({"star","soul_jar","soul_stone","fruit_tree","cloud","lucky_coin","ghost","orange"}) do
        local drawn=Last(id)
        Check(not drawn.cooling and drawn.color>0,id.."内部计时/周期/无冷却实际绘制保持彩色")
    end
    -- 对真实Render检查环条件：临时包装CooldownOf观察生产环分支是否调用；不改predicate。
    local original=game.CooldownOf
    local queried={}
    game.CooldownOf=function(self,id) queried[id]=true; return original(self,id) end
    view.board:Render(Core.GetNVGContext())
    game.CooldownOf=original
    Check(queried.ball==true,"小球实际Render进入冷却环绘制分支")
    for _,id in ipairs({"star","soul_jar","soul_stone","fruit_tree","cloud","lucky_coin","ghost","orange"}) do
        Check(not queried[id],id.."实际Render不进入冷却环绘制")
    end
    Use({"balloon","apple"})
    Check(game:Start(),"气球结算准备")
    local events=game:Finish(physics:Contacts())
    physics:RememberEvents(events); view.board:Effects(events); physics:Sync(game:BottleItems())
    local board=view.board
    Check(board.residue[1]~=nil,"气球结算创建可见残留")
    local target=Items.byId.balloon.radius*1.1
    Check(Near(board.residue[1].radius,target),"残留保存最终scale半径而非已删除旧物理尺寸")
    local previous=board:VisualRadius(1,target)
    Check(previous<target,"膨胀从旧半径启动")
    local monotone=true
    for _=1,40 do
        board:Update(1/60)
        local value=board:VisualRadius(1,target)
        monotone=monotone and value>=previous-1e-8 and value<=target+1e-8
        previous=value
    end
    Check(monotone and Near(previous,target),"膨胀单调到最终尺寸无回缩")
    Check(board.inflations[1]==nil and Near(board.residue[1].radius,target),"动画结束清时钟但尺寸保持")
    records={}
end)

Guard(5,function()
    local balloon=Last("balloon")
    Check(Near(balloon.radius,Items.byId.balloon.radius*1.1*view.board.ppu),"真实残留绘制保持110%")
    -- 当前值：生产的瓶内／牌库／定义／分层候选共用同一格式化入口。
    Use({"glutton","diner","tomato_egg"})
    assert(game:Get(1)).scale=1.5
    assert(game:Get(2)).counter=3
    assert(game:Get(3)).counter=4
    physics:Sync(game:BottleItems(),true,17)
    for uid, expected in ipairs({"当前：150%","当前：3","当前：4"}) do
        view:InspectItem(uid)
        Check(view.detailEffect:GetText():find(expected,1,true)~=nil,"瓶内实际当前值uid"..uid)
        view:CloseItemDetail()
        view:OpenInventory(); view:ShowDeckItem(uid)
        local prose=assert(view.deckBody:FindById("deckDescription"))
        Check(prose:GetText():find(expected,1,true)~=nil,"牌库实际当前值uid"..uid)
        view:CloseInventory()
    end
    Check(view:InspectDefinition("glutton"),"大胃王定义详情可打开")
    Check(view.definitionEffect:GetText():find("当前：100%",1,true)~=nil,"定义显示默认100%而非拥有的150%")
    Check(not view.definitionEffect:GetText():find("当前：x",1,true),"定义无x占位")
    view:CloseDefinition()
    Check(game:Start(),"当前值候选准备")
    game:Finish(); game:RevealStep(10)
    game.options={"glutton","diner","tomato_egg"}; game.revision=game.revision+1
    view.draftSelected=1
    view:Update(true); view:BuildDraft()
    local function HasCurrent(root, expected)
        if root.GetText and root:GetText():find(expected,1,true) then return true end
        for _,child in ipairs(root:GetChildren()) do
            if HasCurrent(child,expected) then return true end
        end
        return false
    end
    Check(HasCurrent(view.draft,"当前：100%"),"真实分层三选一显示初始100%")
    Check(not HasCurrent(view.draft,"当前：x"),"真实三选一无x占位")
    -- 四个属性入口保留金币和tag，冷却整项不存在而非隐藏数字。
    Use({"bacon","ball"})
    view:InspectItem(1); Stats(view.detail,"瓶内实例详情")
    Check(view.detailCooldown==nil,"实例详情不存在旧冷却缓存")
    view:CloseItemDetail()
    Check(view:InspectDefinition("bacon"),"引用定义入口可打开")
    Stats(view.definitionModal,"物品定义详情")
    Check(view.definitionCooldown==nil,"定义详情不存在旧冷却缓存")
    view:CloseDefinition()
    view:OpenInventory(); view:ShowDeckItem(1)
    Stats(view.deckBody,"牌库实例详情")
    view:CloseInventory()
    -- 用合法流程进入draft，不伪造生产阶段。
    Check(game:Start(),"三选一入口准备")
    game:Finish(); game:RevealStep(10)
    game.options={"bacon","ball","apple"}
    game.revision=game.revision+1
    view:Update(true); view:BuildDraft()
    view.machineSkin.cabinet.clock.flashElapsed=-1
    view.draft:Show()
    Stats(view.draft,"三选一详情")
    Core.Layout()
    records={}
end)

Guard(6,function()
    local icon=assert(view.draft:FindById("draftPreviewIcon"))
    local slot=icon:GetAbsoluteLayout()
    local found=Collect("bacon")
    local fitted=false
    for _,draw in ipairs(found) do
        local extent=Art.ItemExtent("bacon",draw.radius,0)
        if math.abs(draw.x-(slot.x+slot.w/2))<2 and math.abs(draw.y-(slot.y+slot.h/2))<20 then
            fitted=extent<=math.min(slot.w,slot.h)*.5+1
        end
    end
    Check(fitted,"真实候选Icon绘制培根加长后仍fit固定slot")
    -- inline Description走同样真实渲染出口，固定点击区尺寸保持。
    local prose=Description{text="引用[[bacon]]",width=260,fontSize=13}
    view.root:AddChild(prose)
    prose:SetStyle({position="absolute",left=10,top=10,width=260,height=48})
    Core.Layout(); prose:Measure(260); prose:Update(2)
    records={}
    prose:Render(Core.GetNVGContext())
    local inline=Last("bacon")
    Check(Art.ItemExtent("bacon",inline.radius,0)<=16.001,"说明内联培根不溢出32px点击槽")
    prose:Destroy()
    Use({"balloon","apple"})
    assert(game:Get(1)).scale=1.9
    physics:Sync(game:BottleItems(),true,17)
    Check(game:Start(),"爆炸场景开始")
    local events=game:Finish(physics:Contacts())
    physics:RememberEvents(events); view.board:Effects(events); physics:Sync(game:BottleItems())
    local board=view.board
    Check(#T.Events(events,"burst",1)==1,"真实规则只发一次气球爆炸事件")
    Check(#board.burstRings==1 and #board.bursts==32,"爆炸专属像素环与32径向粒子存在")
    Check(board.residue[1]==nil and board.inflations[1]==nil and physics.bodies[1]==nil,"爆炸立即移除实体/残留/膨胀")
    Check(board.residue[2]~=nil and game.score==4,"其他物品双倍金币且保留结算残留")
    local first=board.bursts[1]
    local beforeVy=first.vy
    board:Update(1/60)
    Check(first.vy<beforeVy,"爆炸粒子受重力推进")
    records={}
end)

Guard(7,function()
    Check(#Collect("balloon")==0,"爆炸后一帧真实画布不绘制气球本体")
    Check(#Collect("apple")>0,"爆炸后仍绘制其他存活物品")
    local board=view.board
    -- 防御性同批score不得让已爆气球复活，即使顺序不理想。
    board:Effects({{kind="score",uid=1,id="balloon",value=3,x=0,y=3}})
    Check(board.residue[1]==nil,"晚到score不复活已爆气球残留")
    for _=1,66 do board:Update(1/60) end
    Check(#board.burstRings==0 and #board.bursts==0,"爆炸动画按生命周期完整释放")
    Check(board.residue[1]==nil and assert(game:Get(1)).mult==1,"动画结束气球不复活倍率已清")
    -- 为第9帧实际截图重建一次受控爆炸；不把验证事件人为重复发给同一批。
    Use({"balloon","apple"})
    assert(game:Get(1)).scale=1.9; physics:Sync(game:BottleItems(),true,23)
    assert(game:Start())
    local events=game:Finish(physics:Contacts())
    view.board:Effects(events); physics:RememberEvents(events); physics:Sync(game:BottleItems())
    view:Update()
    records={}
end)

-- 从实际提交的INK矩形重建16×16占用，连通域排除边框后计数独立骰点。
local function PipCount(draw)
    local pixels={}
    local unit=draw.radius/8
    for _,r in ipairs(draw.inkRects or {}) do
        local x0,y0=math.floor((r.x+draw.radius)/unit+.1),math.floor((r.y+draw.radius)/unit+.1)
        local w,h=math.floor(r.w/unit+.1),math.floor(r.h/unit+.1)
        for y=y0,y0+h-1 do for x=x0,x0+w-1 do pixels[y*16+x]=true end end
    end
    local count=0
    for key in pairs(pixels) do
        if pixels[key] then
            local queue={key};pixels[key]=nil
            local size=0
            for _,point in ipairs(queue) do
                size=size+1
                local x,y=point%16,math.floor(point/16)
                for _,delta in ipairs({{-1,0},{1,0},{0,-1},{0,1}}) do
                    local nx,ny=x+delta[1],y+delta[2]
                    local nextKey=ny*16+nx
                    if nx>=0 and nx<16 and ny>=0 and ny<16 and pixels[nextKey] then
                        pixels[nextKey]=nil;queue[#queue+1]=nextKey
                    end
                end
            end
            if size==4 then count=count+1 end
        end
    end
    return count
end

Guard(8,function()
    -- 画四面全部1..4、六面全部1..6；只记录真实NanoVG填充，不读sprite定义冒充绘制。
    for _,id in ipairs({"die_d4","die_d6"}) do
        local maximum=id=="die_d4" and 4 or 6
        for value=1,maximum do
            records={}
            Art.Item(Core.GetNVGContext(),id,40+value*20,40,16,0,false,value)
            local draw=Last(id)
            Check(PipCount(draw)==value,id.."实际提交独立点阵数量="..value)
            Check(Art.DiceValue(id,value)==value and Art.HasSprite(id.."_"..value),id.."合法面映射="..value)
        end
        records={};Art.Item(Core.GetNVGContext(),id,20,20,16,0,false)
        Check(PipCount(Last(id))==1,id.."未投掷默认1点且不抽随机")
    end
    Use({"die_d4","die_d6","gambler"})
    assert(game:Start())
    assert(game:Get(1)).permBonus=20
    assert(game:Get(2)).permBonus=30
    assert(game:Get(3)).remaining=0
    local events=game:Step(0,{pairs={{1,3},{2,3}}})
    for _,uid in ipairs({1,2}) do
        local item=assert(game:Get(uid))
        local event=T.Events(events,"score",uid)[1]
        Check(event and event.rollValue==item.rollValue,"赌徒重投score携带真实骰点uid"..uid)
        Check(game:_Value(item)>item.rollValue,"有效价值与骰点明确不同uid"..uid)
    end
    local d4,d6=assert(game:Get(1)).rollValue,assert(game:Get(2)).rollValue
    local settled=game:Finish(physics:Contacts())
    view.board:Effects(settled); physics:RememberEvents(settled); physics:Sync(game:BottleItems())
    Check(view.board.residue[1].rollValue==d4 and view.board.residue[2].rollValue==d6,"结算cleanup后残影保留最终重投骰点")
    records={}
end)

Guard(9,function()
    local d4,d6=Last("die_d4"),Last("die_d6")
    Check(d4.rollValue==view.board.residue[1].rollValue and d6.rollValue==view.board.residue[2].rollValue,
        "真实残影Art.Item第8参收到最后骰点")
    Check(PipCount(d4)==d4.rollValue and PipCount(d6)==d6.rollValue,"真实结算残影点阵数量匹配最后点数")
    -- 专项截图采用实际Widget.Render持久画廊，明确列出十个真实骰面。
    DiceGallery()
end)

Guard(10,function()
    Check(not view.startScreen:IsActive(),"最终截图已离开开始页")
    Check(#Collect("balloon")==0,"最终真实绘制无气球残影复活")
    Check(Storage.repairIsolated==true,"全程玩家存档读写mock仍有效")
    Art.Item=oldItem; _G["nvgRGBA"]=rgba; _G["nvgRect"]=rect; _G["nvgFill"]=fill
    V.finish()
end)
