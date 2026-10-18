-- The CRT shader and pointer mapping share this screen plane and barrel warp.
local Projection=require("Machine.Projection")
local Mapping={x=42,y=210,w=336,h=448,depth=.304,curvature=.04}

-- Display UV -> original canvas UV (the same sampling equation as CRT.shader).
function Mapping.SourceUV(u,v)
    local x,y=u*2-1,v*2-1
    local scale=1+Mapping.curvature*(x*x+y*y)
    return (x*scale+1)*.5,(y*scale+1)*.5
end

-- Original canvas UV -> displayed UV, for item-detail anchors.
function Mapping.DisplayUV(u,v)
    local x,y=u*2-1,v*2-1
    local radius=math.sqrt(x*x+y*y)
    if radius<1e-9 then return .5,.5 end
    local r=radius
    for _=1,7 do
        r=r-(r+Mapping.curvature*r*r*r-radius)/(1+3*Mapping.curvature*r*r)
    end
    local scale=r/radius
    return (x*scale+1)*.5,(y*scale+1)*.5
end

function Mapping.ScreenUV(x,y,container)
    local px=(x-container.x)*420/container.w
    local py=(y-container.y)*840/container.h
    local dx,dy=Projection.LiveUnproject(px,py,Mapping.depth)
    local u,v=(dx-Mapping.x)/Mapping.w,(dy-Mapping.y)/Mapping.h
    local su,sv=Mapping.SourceUV(u,v)
    return su,sv,u>=0 and u<=1 and v>=0 and v<=1 and su>=0 and su<=1 and sv>=0 and sv<=1
end

function Mapping.ScreenPoint(u,v,container)
    local du,dv=Mapping.DisplayUV(u,v)
    local x,y=Projection.LivePoint(Mapping.x+du*Mapping.w,Mapping.y+dv*Mapping.h,Mapping.depth)
    return container.x+x*container.w/420,container.y+y*container.h/840
end

return Mapping
