-- Handheld Noise A position channels, sharedassets0:4183 / level0:9033.
-- Same layered gradient-noise mechanism; portrait amplitude is in design pixels.
local M={}
-- Keep the residual on the presentation side of the low-resolution render.
-- A half-design-pixel raster step preserves crisp sprites; its remainder moves
-- continuously when the scene texture is composed at the window resolution.
function M.Split(value)
    local raster=math.floor(value*2+.5)*.5
    return raster,value-raster
end
local function fade(t) return t*t*t*(t*(t*6-15)+10) end
local function gradient(i,seed)
    local h=((i+seed)*0x45d9f3b)&0xffffffff
    h=((h~(h>>16))*0x45d9f3b)&0xffffffff
    return (h&1)==0 and 1 or -1
end
function M.Noise(t,seed)
    local i=math.floor(t);local f=t-i
    local a=gradient(i,seed)*f
    local b=gradient(i+1,seed)*(f-1)
    return a+(b-a)*fade(f)
end
function M.Sample(seconds)
    -- 镜头时间倍率提高20%、摆幅提高10%；保留各噪声通道的比例。
    local t=seconds*.36
    local multipler = 1
    local x= multipler*6*(.7*M.Noise(t+13.37,17)+.8*M.Noise(t*.8+13.37,17))
    local y= multipler*6*(1.1*M.Noise(t*.7+71.63,31)+.9*M.Noise(t*.9+71.63,31))
    local settle=math.min(1,math.max(0,seconds))
    settle=settle*settle*(3-2*settle)
    return x*settle,y*settle
end
return M
