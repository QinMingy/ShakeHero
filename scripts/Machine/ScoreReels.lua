-- The score uses animated numeral strips; the target is a fixed brass plaque.
-- A new score retargets the moving strips in place; it never restarts a queued tween.
local Orientation=require("Machine.RenderOrientation")

local Reels={}
Reels.__index=Reels
local WIDTH,HEIGHT=800,320
local MIN_REELS=8

local function numericLiteral(value)
    value=tonumber(value) or 0
    if value==math.floor(value) and math.abs(value)<=9007199254740991 then
        return string.format("%.0f",value)
    end
    local literal=string.format("%.10g",value)
    if #literal>10 then return string.format("%.4e",value) end
    return literal
end

local function formatted(value)
    local literal=numericLiteral(value)
    -- Keep all eight physical windows present, including leading zeroes.
    -- Additional places remain available when the score outgrows them.
    local sign,integer,suffix=literal:match("^([+-]?)(%d+)(.*)$")
    if not integer then return literal end
    return sign..string.rep("0",math.max(0,MIN_REELS-#integer))..integer..suffix
end

local function plane(scene,name,x,texture)
    local node=scene:CreateChild(name)
    local geometry=node:CreateComponent("CustomGeometry")
    geometry:BeginGeometry(0,TRIANGLE_LIST)
    for _,uv in ipairs({{0,0},{1,0},{0,1},{1,0},{1,1},{0,1}}) do
        geometry:DefineVertex(Vector3((x+(uv[1]-.5)*150-210)/100,
            (420-115-(uv[2]-.5)*58)/100,-.236))
        geometry:DefineNormal(Vector3(0,0,-1))
        local tc=Vector2();tc.x,tc.y=uv[1],uv[2]
        geometry:DefineTexCoord(tc)
    end
    geometry:Commit()
    local material=Material:new()
    assert(material:SetSurfaceShader("Shaders/BLGL/MachineKey.shader"))
    assert(material:SetSurfaceTexture("label_map",texture))
    material:SetShaderParameter("flip_y",Variant(Orientation.Current() and 1.0 or 0.0))
    material:SetShaderParameter("pulse",Variant(0.0))
    geometry:SetMaterial(material)
    geometry.castShadows=false
    return node,material
end

function Reels.New(cabinet)
    local self=setmetatable({},Reels)
    self:init(cabinet)
    return self
end

function Reels:init(cabinet)
    self.cabinet=cabinet
    self.entries={}
    self.fontWarmupFrames=120
    self.vg=nvgCreate(1)
    nvgSetRenderOrder(self.vg,-95)
    self.font=nvgCreateFont(self.vg,"machine-display","Fonts/SmileySans-Oblique.ttf")
    assert(self.font~=-1,"Machine reel font unavailable")
    for _,spec in ipairs({{"score",121,"得分"},{"target",299,"目标"}}) do
        local entry={kind=spec[1],label=spec[3],text="",digits={},dirty=true,value=0}
        entry.texture=Texture2D:new()
        entry.texture:SetNumLevels(1)
        assert(entry.texture:SetSize(WIDTH,HEIGHT,Graphics:GetRGBAFormat(),TEXTURE_RENDERTARGET))
        entry.texture:SetFilterMode(FILTER_BILINEAR)
        entry.node,entry.material=plane(cabinet.scene,"Live"..spec[1].."Reels",spec[2],entry.texture)
        self.entries[spec[1]]=entry
    end
end

function Reels:SetValues(score,target)
    for name,value in pairs({score=score,target=target}) do
        local entry=self.entries[name]
        local nextText=name=="score" and formatted(value) or numericLiteral(value)
        local oldValue=entry.value
        entry.value=value
        if nextText~=entry.text then
            local previous=entry.text
            local direction=value>=oldValue and 1 or -1
            entry.text=nextText
            -- The target plaque has no moving digit state.
            -- Score positions are numbered from the least significant end.
            for place=1,(name=="score" and #nextText or 0) do
                local char=nextText:sub(#nextText-place+1,#nextText-place+1)
                if char:match("%d") then
                    local numeral=assert(tonumber(char))
                    local digit=entry.digits[place]
                    if not digit or not previous:sub(#previous-place+1,#previous-place+1):match("%d") then
                        entry.digits[place]={position=numeral,target=numeral,velocity=0}
                    elseif previous:sub(#previous-place+1,#previous-place+1)~=char then
                        local current=digit.position
                        local destination=math.floor(current/10)*10+numeral
                        -- A flat, one-direction numeral belt. Keep current
                        -- position/velocity even when retargeted mid-spin.
                        if direction>0 then
                            while destination<=current+.05 do destination=destination+10 end
                        else
                            while destination>=current-.05 do destination=destination-10 end
                        end
                        digit.target=destination
                    end
                end
            end
            entry.dirty=true
        end
    end
end

function Reels:Tick(dt)
    dt=math.min(math.max(dt or 0,0),1/30)
    if self.fontWarmupFrames>0 then
        self.fontWarmupFrames=self.fontWarmupFrames-1
        -- The first texture draw can precede font-atlas preparation. Redraw
        -- the same face after startup so it matches later value changes.
        if self.fontWarmupFrames%30==0 then
            self.entries.score.dirty=true
            self.entries.target.dirty=true
        end
    end
    for _,entry in pairs(self.entries) do
        for _,digit in pairs(entry.digits) do
            local distance=digit.target-digit.position
            if math.abs(distance)>.003 or math.abs(digit.velocity)>.015 then
                -- Damped spring: interruption changes only the destination.
                digit.velocity=(digit.velocity+distance*145*dt)*math.exp(-19*dt)
                digit.position=digit.position+digit.velocity*dt
                entry.dirty=true
            else
                if digit.position~=digit.target or digit.velocity~=0 then
                    entry.dirty=true -- finish on the same fully rendered glyph
                end
                digit.position=digit.target
                digit.velocity=0
            end
        end
    end
end

local function fill(vg,x,y,w,h,color)
    nvgBeginPath(vg);nvgRect(vg,x,y,w,h)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],color[4] or 255));nvgFill(vg)
end

local function circle(vg,x,y,r,color)
    nvgBeginPath(vg);nvgCircle(vg,x,y,r)
    nvgFillColor(vg,nvgRGBA(color[1],color[2],color[3],color[4] or 255));nvgFill(vg)
end

local function renderTarget(vg,entry,fontId)
    -- Warm enamel plate, distinct from the score's black mechanical drums.
    fill(vg,20,58,760,240,{73,55,31})
    fill(vg,28,66,744,224,{183,151,88})
    fill(vg,35,73,730,210,{127,108,70})
    fill(vg,43,81,714,194,{161,140,96})
    fill(vg,52,88,696,4,{210,177,106})
    fill(vg,52,265,696,4,{72,55,31})
    for _,x in ipairs({73,727}) do
        for _,y in ipairs({117,238}) do
            circle(vg,x,y,16,{62,46,24})
            circle(vg,x-3,y-3,8,{166,133,74})
            fill(vg,x-7,y-1,14,2,{42,31,17})
        end
    end
    nvgFontFaceId(vg,fontId)
    nvgTextAlign(vg,NVG_ALIGN_LEFT|NVG_ALIGN_MIDDLE)
    nvgFontSize(vg,85)
    nvgFillColor(vg,nvgRGBA(43,35,21,255))
    nvgText(vg,111,181,"目标",nil)
    nvgFontSize(vg,math.min(190,760/math.max(2,#entry.text)))
    nvgTextAlign(vg,NVG_ALIGN_CENTER|NVG_ALIGN_MIDDLE)
    nvgFillColor(vg,nvgRGBA(36,28,17,255))
    nvgText(vg,530,184,entry.text,nil)
    nvgText(vg,532,184,entry.text,nil)
end

local function renderNumeral(vg,x,y,number)
    local glyph=tostring(number)
    -- One face for moving and settled digits; a narrow shadow and duplicate
    -- face give the same sturdy print throughout the belt animation.
    nvgFillColor(vg,nvgRGBA(41,29,12,255))
    nvgText(vg,x+2,y+2,glyph,nil)
    nvgFillColor(vg,nvgRGBA(237,211,145,255))
    nvgText(vg,x-1,y,glyph,nil)
    nvgText(vg,x+1,y,glyph,nil)
end

local function renderScore(vg,entry,fontId)
    nvgFontFaceId(vg,fontId)
    nvgTextAlign(vg,NVG_ALIGN_LEFT|NVG_ALIGN_MIDDLE)
    nvgFontSize(vg,80)
    nvgFillColor(vg,nvgRGBA(181,174,102,255))
    nvgText(vg,48,42,entry.label,nil)

    local count=#entry.text
    local gap=math.min(138,700/math.max(1,count))
    local left=(WIDTH-gap*count)/2
    local font=math.min(150,gap*1.7)
    nvgFontSize(vg,font)
    nvgTextAlign(vg,NVG_ALIGN_CENTER|NVG_ALIGN_MIDDLE)
    for column=1,count do
        local char=entry.text:sub(column,column)
        local x=left+(column-.5)*gap
        if char:match("%d") then
            local place=count-column+1
            local digit=entry.digits[place]
            local slotX,slotW=x-gap*.48,gap*.96
            fill(vg,slotX,104,slotW,177,{76,57,29})
            fill(vg,slotX+3,108,slotW-6,169,{9,9,6})
            fill(vg,slotX+7,111,slotW-14,17,{42,31,15})
            fill(vg,slotX+11,113,slotW-22,4,{194,142,57})
            fill(vg,slotX+7,130,slotW-14,126,{6,7,5})
            nvgSave(vg)
            nvgScissor(vg,slotX+7,130,slotW-14,126)
            local base=math.floor(digit.position)
            local fraction=digit.position-base
            local moving=math.abs(digit.position-digit.target)>.003
                or math.abs(digit.velocity)>.015
            for offset=moving and -1 or 0,moving and 2 or 0 do
                renderNumeral(vg,x,193+(offset-fraction)*132,(base+offset)%10)
            end
            nvgRestore(vg)
            fill(vg,slotX+7,259,slotW-14,13,{37,26,13})
            fill(vg,slotX+10,263,slotW-20,3,{136,97,43})
            fill(vg,slotX+slotW-4,110,2,164,{116,85,38})
        else
            nvgFillColor(vg,nvgRGBA(212,198,110,255))
            nvgText(vg,x,193,char,nil)
        end
    end
    fill(vg,48,291,WIDTH-96,3,{88,80,40})
end

function Reels:Render()
    local vg=self.vg
    for _,entry in pairs(self.entries) do
        if entry.dirty then
            nvgSetRenderTarget(vg,entry.texture)
            nvgBeginFrame(vg,WIDTH,HEIGHT,1)
            fill(vg,0,0,WIDTH,HEIGHT,{2,4,2})
            if entry.kind=="target" then renderTarget(vg,entry,self.font)
            else renderScore(vg,entry,self.font) end
            nvgEndFrame(vg)
            entry.dirty=false
            self.cabinet.surface:QueueUpdate()
        end
    end
end

function Reels:Dispose()
    for _,entry in pairs(self.entries) do
        entry.node:Remove()
        entry.texture:Dispose()
    end
    nvgDelete(self.vg)
end

return Reels
