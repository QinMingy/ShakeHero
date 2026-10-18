-- Contract smoke test only: minimal widget doubles, NOT Yoga/engine/input validation.
local W={};W.__index=W
local function widget(props)
    local w=setmetatable({props=props or {},children={},state={},id=props and props.id},W)
    for _,c in ipairs(w.props.children or {}) do w:AddChild(c) end
    return w
end
function W:SetStyle(p) for k,v in pairs(p) do self.props[k]=v end end
function W:AddChild(c)
    if c.parent then c.parent:RemoveChild(c) end
    self.children[#self.children+1]=c;c.parent=self;return self
end
function W:RemoveChild(c)
    for i,x in ipairs(self.children) do if x==c then table.remove(self.children,i);break end end
    c.parent=nil
end
function W:GetChildren() return self.children end
function W:ClearChildren() self.children={} end
function W:Destroy()
    for i=#self.children,1,-1 do self.children[i]:Destroy() end
    if self.parent then self.parent:RemoveChild(self) end
end
function W:Hide() self.props.visible=false end
function W:Show() self.props.visible=true end
function W:IsVisible() return self.props.visible~=false end
function W:SetVisible(v) self.props.visible=v end
function W:SetDisabled(v) self.props.disabled=v end
function W:SetText(v) self.props.text=v end
function W:SetWidth(v) self.props.width=v end
function W:Render() end
function W:Update() end
function W:FindById(id)
    if self.id==id then return self end
    for _,c in ipairs(self.children) do local w=c:FindById(id);if w then return w end end
end
local function size(value,parent,fallback)
    if type(value)=='number' then return value end
    if type(value)=='string' and value:find('%%') then return tonumber(value:match('[%d.]+'))*parent/100 end
    return fallback or 0
end
function W:GetAbsoluteLayout()
    local p=self.parent and self.parent:GetAbsoluteLayout() or {x=0,y=0,w=402,h=874}
    return {x=p.x+size(self.props.left,p.w),y=p.y+size(self.props.top,p.h),
        w=size(self.props.width,p.w,p.w),h=size(self.props.height,p.h,32)}
end
local viewport={w=402,h=874}
local UI={Widget=widget,Panel=widget,Label=widget,Button=widget,ScrollView=widget,
    GetWidth=function() return viewport.w end,GetHeight=function() return viewport.h end,
    GetSafeAreaInsets=function() return {left=0,right=0,top=0,bottom=0} end}
package.loaded['urhox-libs/UI']=UI
package.loaded['urhox-libs/Platform/PlatformUtils']={GetPlatform=function() return 'Windows' end}
NVG_IMAGE_NEAREST=32;NVG_IMAGE_REPEATX=2;NVG_IMAGE_REPEATY=4
local images,loaded,deleted={},0,0
function nvgCreateImage(_,path)
    local f=assert(io.open('assets/'..path,'rb'),path);f:close()
    loaded=loaded+1;images[loaded]=path;return loaded
end
function nvgDeleteImage(_,id) assert(images[id]);images[id]=nil;deleted=deleted+1 end
function nvgRGBA(r,g,b,a)
    assert(type(r)=='number' and type(g)=='number' and type(b)=='number' and type(a)=='number')
    return {r,g,b,a}
end
function nvgImagePattern(_,x,y,w,h,angle,id) assert(images[id]);assert(w>0 and h>0);return {} end
function nvgRect(_,x,y,w,h) assert(x==x and y==y and w>=0 and h>=0) end
function nvgLinearGradient(_,x1,y1,x2,y2,c1,c2)
    assert(x1==x1 and y1==y1 and x2==x2 and y2==y2 and c1 and c2);return {}
end
function nvgRadialGradient(_,x,y,inner,outer,c1,c2)
    assert(x==x and y==y and inner>=0 and outer>inner and c1 and c2);return {}
end
local nesting=0
function nvgSave() nesting=nesting+1 end
function nvgRestore() nesting=nesting-1;assert(nesting>=0) end
for _,name in ipairs({'nvgBeginPath','nvgFillColor','nvgFill','nvgFillPaint','nvgIntersectScissor',
    'nvgShapeAntiAlias','nvgTranslate'}) do _G[name]=function() end end
-- Scene is a contract double here; actual light/shadow acceptance uses the live window.
local sceneDisposed=false
package.loaded['Machine.LitSpriteScene']={New=function() return {
    motionX=.75,motionY=-.5,
    Begin=function(self) self.count=0 end,
    Quad=function(self) self.count=self.count+1 end,
    Layer=function() end,Finish=function() end,Tick=function() end,
    Dispose=function() sceneDisposed=true end,
} end}
local Skin=require('Machine.LayeredSkin')
local Game=require('Bottle.Game')
local Items=require('Bottle.Items')
local game=Game.New(123)
local view={game=game,physics={mode=2},choiceHidden=false,currentPhase='prepare',inventoryOpen=false}
local total=0
local function check(v,message) assert(v,message);total=total+1 end
local safe=widget{width=402,height=874}
view.container=widget{width=402,height=874};safe:AddChild(view.container)
for _,name in ipairs({'board','roundLabel','goalLabel','deckButton','footer','detail','draft','modal',
    'physicsButton','physicsMenu','scoreLabel','progress','timer','badgeLabel','statusLabel'}) do
    view[name]=widget{};view.container:AddChild(view[name])
end
view.draft:Hide();view.modal:Hide();view.detail:Hide();view.physicsMenu:Hide()
local clicked=0
local reroll=widget{text='重抽',onClick=function() clicked=clicked+1 end}
local start=widget{text='开始摇晃',onClick=function() clicked=clicked+10 end}
view.footer:AddChild(widget{children={reroll,start}})
view.footer:AddChild(widget{text='hint'})
local title,help,save,gm=widget{},widget{},widget{},widget{}
for _,w in ipairs({title,help,save,gm}) do view.container:AddChild(w) end
local helpRender=help.Render
Skin.Apply(view,title,help,save,gm)
Skin.Update(view)
check(view.container.props.width==402 and view.container.props.height==874,'design aspect ratio')
check(help.Render==helpRender and gm.Render==helpRender,'developer tools retain UI rendering')
check(view.container:FindById('scoreSummary')~=nil,'summary anchor retained')
check(view.board.layered and view.board.parent==view.container,'board uses direct coordinates')
check(reroll.props.top~=start.props.top and reroll.props.height~=start.props.height,'staggered buttons')
reroll.props.onClick();start.props.onClick();check(clicked==11,'action callbacks unchanged')
local function draw(w)
    if not w:IsVisible() then return end
    w:Render(1)
    for _,c in ipairs(w.children) do draw(c) end
end
draw(view.container);view.board:RenderFullBackground(1)
local firstLoad=loaded;draw(view.container)
check(loaded==firstLoad,'images cached rather than loaded every frame')
check(nesting==0,'all paint scopes restored')
local bg=view.container.children[1]
game.phase='running';game.elapsed=4.125;Skin.Update(view);bg:Update(1/60)
check(view.container.props.translateX==.75 and view.container.props.translateY==-.5,'UI follows camera reference plane through hit-test-aware transform')
check(view.machineSkin.clock.centis==588,'clock remains centisecond based')
game.phase='draft';game.options={'apple','banana','orange'};game.elapsed=10
Skin.Update(view)
check(view.machineSkin.clock.flashElapsed==0,'round end starts flash gate')
view.machineSkin.clock:Tick(.84)
check(view.machineSkin.clock.flashElapsed<0,'three flashes finish')
local chosen=0
view.actions={choose=function(i) chosen=i end,refresh=function() end,skip=function() end}
local function draftValue(_,id) return id,Items.byId[id].base end
function view:BuildDraft() Skin.BuildDraft(self,widget,widget,draftValue,function() return widget{} end) end
view:BuildDraft()
check(#view.draft.children==8,'one display, three slots and four detached actions')
check(not view.footer:IsVisible() and not view.board:IsVisible(),'draft hides bottle page and its hit targets')
local display=assert(view.draft:FindById('draftDisplay'))
local function hasAction(w)
    if w.props.onClick then return true end
    for _,child in ipairs(w.children) do if hasAction(child) then return true end end
    return false
end
check(not hasAction(display),'CRT has no confirm/refresh/skip/hide buttons')
check(view.draft:FindById('draftEffectScroll').props.height>0,'description gets an explicit viewport')
local first=view.draft:FindById('draftSlot_1').props
for i=2,3 do
    local p=view.draft:FindById('draftSlot_'..i).props
    check(p.top==first.top and p.width==first.width and p.height==first.height,
        'candidate size and elevation must not imply a recommendation')
end
check(view.container:FindById('machineOptics').props.pointerEvents=='none','optical overlay never intercepts clicks')
for _,id in ipairs({'draftHide','draftConfirm','draftRefresh','draftSkip','draftSlot_1','draftSlot_2','draftSlot_3'}) do
    local rect=assert(view.draft:FindById(id)).props
    check(rect.top>=660 and rect.top+rect.height<=874,id..' stays outside screen and inside canvas')
end
check(view.draft:FindById('draftRefresh').props.top~=view.draft:FindById('draftConfirm').props.top
    and view.draft:FindById('draftSkip').props.top~=view.draft:FindById('draftConfirm').props.top,
    'action buttons have staggered heights')
local slot=view.draft:FindById('draftSlot_2')
check(slot.props.top>=674,'choices stay outside CRT')
slot.props.onClick()
check(view.draftSelected==2 and chosen==0,'previewing does not choose immediately')
view.inventoryOpen=true
view.draft:FindById('draftSlot_3').props.onClick()
check(view.draftSelected==2,'inventory preserves pending selection')
view.inventoryOpen=false
draw(view.draft)
-- Exercise optical rendering with selected/hovered candidates and lit lamps.
view.draft:FindById('draftSlot_3').state.hovered=true
game.score=game.target
bg:Update(.125);draw(view.container)
check(nesting==0,'selection/CRT/lamp clipping scopes restored')
view.draft:FindById('draftHide').props.onClick()
check(view.choiceHidden and not view.draft:IsVisible() and view.footer:IsVisible() and view.board:IsVisible(),
    'collapse restores bottle page and reopen action')
Skin.SetDraftOpen(view,true)
check(not view.choiceHidden and view.draft:IsVisible() and not view.footer:IsVisible(),
    'reopen hides old footer immediately')
view.draft:FindById('draftConfirm').props.onClick()
check(chosen==2,'physical confirm chooses selected preview')
local modalPanel=widget{}
Skin.Modal(view,modalPanel,true)
check(view.modal.props.left==16 and view.modal.props.top==202 and view.modal.props.height==458,'inventory fits CRT')
Skin.Modal(view,modalPanel,false)
check(view.modal.props.left==0 and view.modal.props.height==874,'developer modal returns to full canvas')
viewport.w=320;viewport.h=700;Skin.Update(view)
check(math.abs(view.container.props.width-320)<.01,'resize keeps uniform contain scale')
draw(view.container)
view.container:Destroy()
check(deleted==loaded,'image resources released')
check(sceneDisposed,'scene render target lifetime follows UI skin lifetime')
check(nesting==0,'paint scopes restored after every phase')
return total
