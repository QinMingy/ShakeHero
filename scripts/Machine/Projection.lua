-- Shared projection for the Blender cabinet, screen drawing and UI hit regions.
-- The game still uses its original 420x840 design and 4.8x6.4 metre board.
local Projection={tiltDegrees=30,fovDegrees=30,distance=15.8}
Projection.cos=math.cos(math.rad(Projection.tiltDegrees))
Projection.sin=math.sin(math.rad(Projection.tiltDegrees))
local focalPixels=420/math.tan(math.rad(Projection.fovDegrees)*.5)
local pose

-- The cabinet's projected widgets use the fixed reference camera below.
-- Only CRT picking follows the live camera sway, so touch stays on the image.
function Projection.SetCameraPose(cx,cy,cz,tx,ty,tz)
    local fx,fy,fz=tx-cx,ty-cy,tz-cz
    local length=math.sqrt(fx*fx+fy*fy+fz*fz)
    fx,fy,fz=fx/length,fy/length,fz/length
    local rx,rz=fz,-fx
    local rightLength=math.sqrt(rx*rx+rz*rz)
    rx,rz=rx/rightLength,rz/rightLength
    local ux,uy,uz=fy*rz,fz*rx-fx*rz,-fy*rx
    pose={cx=cx,cy=cy,cz=cz,fx=fx,fy=fy,fz=fz,
        rx=rx,rz=rz,ux=ux,uy=uy,uz=uz}
end

function Projection.LivePoint(x,y,depth)
    local p=pose
    local vx,vy,vz=(x-210)/100-p.cx,(420-y)/100-p.cy,-depth-p.cz
    local forward=vx*p.fx+vy*p.fy+vz*p.fz
    return 210+focalPixels*(vx*p.rx+vz*p.rz)/forward,
        420-focalPixels*(vx*p.ux+vy*p.uy+vz*p.uz)/forward
end

function Projection.LiveUnproject(x,y,depth)
    local p=pose
    local horizontal=(x-210)/focalPixels
    local vertical=(420-y)/focalPixels
    local dx=p.fx+horizontal*p.rx+vertical*p.ux
    local dy=p.fy+vertical*p.uy
    local dz=p.fz+horizontal*p.rz+vertical*p.uz
    local distance=(-depth-p.cz)/dz
    return 210+100*(p.cx+distance*dx),420-100*(p.cy+distance*dy)
end

Projection.SetCameraPose(0,-Projection.distance*Projection.sin,
    -Projection.distance*Projection.cos,0,0,0)

-- Matches PortraitCamera looking at the origin, with a 420 x 840 render target.
-- Blender design coordinates become world (x-210,420-y,-depth*100)/100.
function Projection.ScaleAt(y,depth)
    local worldY=(420-y)/100
    local cameraZ=Projection.distance+worldY*Projection.sin-(depth or .25)*Projection.cos
    return focalPixels/(100*cameraZ)
end

function Projection.Point(x,y,depth)
    local scale=Projection.ScaleAt(y,depth)
    return 210+(x-210)*scale,
        420+((y-420)*Projection.cos-(depth or .25)*100*Projection.sin)*scale
end

-- Ray/plane intersection for inverse perspective picking on a fixed-depth face.
function Projection.Unproject(x,y,depth)
    local d=depth or .25
    local viewY=(420-y)/focalPixels
    local worldY=(viewY*(Projection.distance-d*Projection.cos)-d*Projection.sin)
        /(Projection.cos-viewY*Projection.sin)
    local cameraZ=Projection.distance+worldY*Projection.sin-d*Projection.cos
    return 210+(x-210)*cameraZ/focalPixels*100,420-worldY*100
end

function Projection.Rect(x,y,w,h,depth)
    local leftTop,top=Projection.Point(x,y,depth)
    local rightTop=Projection.Point(x+w,y,depth)
    local leftBottom,bottom=Projection.Point(x,y+h,depth)
    local rightBottom=Projection.Point(x+w,y+h,depth)
    -- Widgets remain readable, axis-aligned controls inside the projected face.
    -- Their rendered bounds and hit regions share this same inset rectangle.
    local left,right=math.max(leftTop,leftBottom),math.min(rightTop,rightBottom)
    return left,top,right-left,bottom-top
end
return Projection
