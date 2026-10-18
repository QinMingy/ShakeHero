-- Retain the upstream board, widgets and callbacks. Only its rendering/picking
-- changes: NanoVG -> render texture -> perspective CRT plane in the cabinet.
local UI=require("urhox-libs/UI")
local Mapping=require("Machine.ScreenMapping")
local Orientation=require("Machine.RenderOrientation")
---@type {SetOffscreenContext:fun(vg:NVGContextWrapper,enabled:boolean)}
local Art=require("Bottle.Art")
---@type any
local Screen={}
Screen.__index=Screen

function Screen.New(view,cabinet)
    local self=setmetatable({},Screen)
    self.view,self.board,self.cabinet=view,view.board,cabinet
    self.width,self.height=672,896
    self.texture=Texture2D:new()
    self.texture:SetNumLevels(1)
    assert(self.texture:SetSize(self.width,self.height,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
    self.texture:SetFilterMode(FILTER_BILINEAR)
    self.vg=nvgCreate(1)
    Art.SetOffscreenContext(self.vg,true)
    nvgSetRenderTarget(self.vg,self.texture)
    nvgSetRenderOrder(self.vg,-100)
    -- Fixed offscreen design resolution; no window DPR in the texture pass.
    local theme=require("Bottle.Theme") --[[@as any]]
    for _,font in ipairs(theme.fonts) do
        for weight,path in pairs(font.weights) do
            nvgCreateFont(self.vg,UI.Theme.FontFace(font.family,weight),path)
        end
    end
    self.material=Material:new()
    assert(self.material:SetSurfaceShader("Shaders/BLGL/MachineCRT.shader"),"CRT surface shader unavailable")
    assert(self.material:SetSurfaceTexture("content_map",self.texture))
    self.material:SetShaderParameter("curvature",Variant(Mapping.curvature))
    self.material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    self:SetAtmosphere(cabinet.atmosphere)
    self.node=cabinet.scene:CreateChild("LiveCRTScreen")
    local geometry=self.node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((Mapping.x+uv[1]*Mapping.w-210)/100,
            (420-Mapping.y-uv[2]*Mapping.h)/100,-Mapping.depth))
        geometry:DefineNormal(Vector3(0,0,-1))
        local texcoord=Vector2()
        texcoord.x,texcoord.y=uv[1],uv[2]
        geometry:DefineTexCoord(texcoord)
    end
    geometry:Commit()
    geometry:SetMaterial(self.material)
    geometry.castShadows=false
    self:BindBoard()
    print("[Machine.CRT] 棋盘纹理已接入透视屏幕：扫描线、曲面采样、局部 bloom")
    return self
end

function Screen:SetAtmosphere(style)
    local c=style.screenGlow
    self.material:SetShaderParameter("mood_glow",Variant(Color(c[1],c[2],c[3],c[4])))
    self.cabinet.surface:QueueUpdate()
end

function Screen:CanvasPoint(x,y)
    local u,v,inside=Mapping.ScreenUV(x,y,self.view.container:GetAbsoluteLayout())
    local l=self.board:GetAbsoluteLayout()
    return l.x+u*l.w,l.y+v*l.h,inside
end

function Screen:DisplayPoint(x,y)
    local l=self.board:GetAbsoluteLayout()
    return Mapping.ScreenPoint((x-l.x)/l.w,(y-l.y)/l.h,self.view.container:GetAbsoluteLayout())
end

function Screen:Gesture(event)
    -- Leave x/y in screen space for the original menu/primary-pointer guards.
    local mapped={}
    for key,value in pairs(event) do mapped[key]=value end
    local x,y=self:CanvasPoint(event.x,event.y)
    local px,py=self:CanvasPoint(event.x-(event.deltaX or 0),event.y-(event.deltaY or 0))
    local sx,sy=self:CanvasPoint(event.x-(event.totalDeltaX or 0),event.y-(event.totalDeltaY or 0))
    mapped.deltaX,mapped.deltaY=x-px,y-py
    mapped.totalDeltaX,mapped.totalDeltaY=x-sx,y-sy
    return setmetatable(mapped,getmetatable(event))
end

function Screen:BindBoard()
    local board=self.board
    self.renderBoard=board.Render
    board.Render=function() self:Render() end
    -- The existing physics menu and its buttons are included in the CRT texture.
    board.CustomRenderChildren=function() end
    local function bindHits(widget)
        local hit=widget.HitTest
        widget.HitTest=function(w,x,y)
            local px,py,inside=self:CanvasPoint(x,y)
            return inside and hit(w,px,py)
        end
        for _,child in ipairs(widget:GetChildren()) do bindHits(child) end
    end
    bindHits(board)
    local pick=board.PickItem
    board.PickItem=function(b,x,y)
        local px,py,inside=self:CanvasPoint(x,y)
        if not inside then return 0 end
        return pick(b,px,py)
    end
    local bounds=board.GetItemBounds
    board.GetItemBounds=function(b,uid)
        local r=bounds(b,uid)
        local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
        for _,point in ipairs({{r.x,r.y},{r.x+r.w,r.y},{r.x,r.y+r.h},{r.x+r.w,r.y+r.h}}) do
            local x,y=self:DisplayPoint(point[1],point[2])
            minX,minY,maxX,maxY=math.min(minX,x),math.min(minY,y),math.max(maxX,x),math.max(maxY,y)
        end
        return {x=minX,y=minY,w=maxX-minX,h=maxY-minY}
    end
    local start,move=board.OnPanStart,board.OnPanMove
    board.OnPanStart=function(b,event) return start(b,self:Gesture(event)) end
    board.OnPanMove=function(b,event) return move(b,self:Gesture(event)) end
end

function Screen:Render()
    local l=self.board:GetAbsoluteLayout()
    if l.w<=0 or l.h<=0 then return end
    nvgBeginFrame(self.vg,self.width,self.height,1)
    nvgScale(self.vg,self.width/l.w,self.height/l.h)
    nvgTranslate(self.vg,-l.x,-l.y)
    self.renderBoard(self.board,self.vg)
    for _,child in ipairs(self.board:GetRenderChildren()) do UI.RenderWidgetSubtree(child,self.vg) end
    nvgEndFrame(self.vg)
    -- The cabinet now contains live content, rather than a static background.
    self.cabinet.surface:QueueUpdate()
end

function Screen:Dispose()
    self.node:Remove()
    Art.SetOffscreenContext(self.vg,false)
    nvgDelete(self.vg)
    self.texture:Dispose()
end

return Screen
