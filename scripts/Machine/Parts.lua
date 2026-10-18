local UI = require("urhox-libs/UI")
local Projection=require("Machine.Projection")
local Parts = {text={236,231,119,255}, muted={182,176,108,255}, fonts={}}
function Parts.Scale()
    local insets = UI.GetSafeAreaInsets()
    return math.min((UI.GetWidth()-insets.left-insets.right)/420,
        (UI.GetHeight()-insets.top-insets.bottom)/840,1.65)
end
function Parts.Rect(x,y,w,h,depth)
    local px,py,pw,ph=Projection.Rect(x,y,w,h,depth)
    return {position="absolute",left=(px/420*100).."%",top=(py/840*100).."%",
        width=(pw/420*100).."%",height=(ph/840*100).."%"}
end
function Parts.FontScale(y)
    return Projection.ScaleAt(y)
end
function Parts.Label(text,size,color)
    local label = UI.Label {text=text,fontSize=size*Parts.Scale()*Projection.cos,fontColor=color or Parts.text,
        fontFamily=text:find("[\128-\255]") and "sans" or "display",fontWeight="normal",
        textAlign="center",width="100%",flexShrink=1,pointerEvents="none",
        textShadow={offsetX=0,offsetY=0,blur=5,color={203,222,70,65}}}
    Parts.fonts[#Parts.fonts+1]={widget=label,size=size}
    return label
end
function Parts.ResizeFonts()
    for _, entry in ipairs(Parts.fonts) do entry.widget:SetStyle({fontSize=entry.size*Parts.Scale()*Projection.cos}) end
end
return Parts
