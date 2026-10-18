-- 屏幕专用装配：3D受光外壳／背线／投影灯串，UI前景玻璃。
local UI=require("urhox-libs/UI")
local L=require("Machine.LayeredLayout")
local LampBloomMask=require("Machine.LampBloomMask")
---@type any
local Display={halfPeriod=.24,pitch=28,lamps={},top={33,196,28,13},sides={11,391,224,16},
    housingDepth=-.155,socketDepth=-.215,bulbDepth=-.255}
for i=1,Display.top[4] do
    Display.lamps[#Display.lamps+1]={x=Display.top[1]+(i-1)*Display.pitch,y=Display.top[2],group=(i-1)%2}
end
for row=1,Display.sides[4] do
    Display.lamps[#Display.lamps+1]={x=Display.sides[1],y=Display.sides[3]+(row-1)*Display.pitch,group=row%2}
    Display.lamps[#Display.lamps+1]={x=Display.sides[2],y=Display.sides[3]+(row-1)*Display.pitch,group=(row+1)%2}
end

-- 只读回合时钟；开始即从第一组起亮，结束立即低亮，不积累装饰计时或随机数。
function Display.LampLevel(index,phase,elapsed)
    if phase~="running" then return .13 end
    local t=type(elapsed)=="number" and elapsed==elapsed and elapsed<math.huge and math.max(0,elapsed) or 0
    return Display.lamps[index].group==math.floor(t/Display.halfPeriod)%2 and 1 or .08
end
local function rect(vg,x,y,w,h,r,g,b,a)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(r,g,b,a or 255));nvgFill(vg)
end
local function polygon(vg,points,r,g,b,a)
    nvgBeginPath(vg);nvgMoveTo(vg,points[1],points[2])
    for i=3,#points,2 do nvgLineTo(vg,points[i],points[i+1]) end
    nvgClosePath(vg);nvgFillColor(vg,nvgRGBA(r,g,b,a));nvgFill(vg)
end
local function attach(view,id,z,area,render)
    local widget=UI.Widget{id=id,pointerEvents="none",zIndex=z} --[[@as any]]
    widget.Render=render
    view.machineSkin.placements[#view.machineSkin.placements+1]={widget=widget,rect=area}
    view.container:AddChild(widget)
    return widget
end
function Display.Attach(view)
    local m=view.machineSkin
    local state={}
    m.screenAssembly=state
    -- 独立灯面遮罩与 UI capture 同方向，由后处理采样实际亮部。
    state.wiring=attach(view,"screenWiring",1,{0,0,L.width,L.height},function(widget,vg)
        local b=widget:GetAbsoluteLayout()
        m.litScene:Layer(.6)
        m.sprites:Draw(vg,"crt-wiring",b.x,b.y,b.w,b.h)
    end)
    state.housing=attach(view,"screenHousing",4,{0,178,402,500},function(widget,vg)
        local b=widget:GetAbsoluteLayout()
        m.litScene:Layer(Display.housingDepth)
        m.sprites:Draw(vg,"crt-housing",b.x,b.y,b.w,b.h)
    end)
    state.lamps=attach(view,"screenBulbs",5,{0,0,L.width,L.height},function(widget,vg)
        local b=widget:GetAbsoluteLayout();local s=m.scale
        -- 灯座与玻璃灯面均为抬离外壳的独立3D sprite，参与深度、受光和真实投影。
        for index,lamp in ipairs(Display.lamps) do
            local x,y=b.x+lamp.x*s,b.y+lamp.y*s
            m.litScene:Layer(Display.socketDepth)
            m.sprites:Draw(vg,"crt-bulb-socket",x-5*s,y-5*s,10*s,10*s)
            m.litScene:Layer(Display.bulbDepth)
            local name=lamp.group==0 and "crt-bulb-a" or "crt-bulb-b"
            m.sprites:Draw(vg,name,x-3*s,y-3*s,6*s,6*s)
            m.litScene.materials[name]:SetShaderParameter("lamp_level",
                Variant(Display.LampLevel(index,view.game.phase,view.game.elapsed)))
        end
    end)
    state.glass=attach(view,"screenGlass",25,L.board,function(widget,vg)
        -- 玻璃只在内容矩形内叠加极淡反射，弹窗在其上；不跟随瓶子运动。
        if view.modal:IsVisible() or view.definitionModal:IsVisible() then return end
        local b=widget:GetAbsoluteLayout();local s=m.scale
        local w,h=b.w/s,b.h/s
        nvgSave(vg);nvgIntersectScissor(vg,b.x,b.y,b.w,b.h)
        nvgTranslate(vg,b.x,b.y);nvgScale(vg,s,s);nvgShapeAntiAlias(vg,0)
        rect(vg,0,0,w,3,1,13,10,180)
        rect(vg,0,3,w,4,1,13,10,65)
        rect(vg,0,0,3,h,1,13,10,130)
        rect(vg,w-2,5,2,h-7,159,201,151,40)
        rect(vg,3,h-2,w-6,2,161,193,133,52)
        polygon(vg,{8,8,109,8,37,75,8,94},190,218,174,9)
        polygon(vg,{119,8,132,8,8,126,8,113},210,231,188,8)
        rect(vg,8,8,68,1,205,225,174,59)
        rect(vg,8,9,1,29,205,225,174,43)
        -- 边缘扫描线只落在窄边带，避免给文字和重要数值增加条纹。
        for y=12,h-8,4 do
            rect(vg,4,y,3,1,152,194,133,13)
            rect(vg,w-7,y,3,1,152,194,133,13)
        end
        nvgRestore(vg)
    end)
    local mask=LampBloomMask.New(view,Display,m.litScene.post)
    local destroy=state.lamps.Destroy
    state.lamps.Destroy=function(widget) mask:Dispose();destroy(widget) end
    print("[Machine.Screen] 3D外壳／背线／45组独立投影灯座与灯面，间距28，running每0.24秒交替，自发光＋Bloom")
end
return Display
