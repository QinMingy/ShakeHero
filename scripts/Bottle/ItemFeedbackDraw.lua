-- NanoVG局部像素特效；所有时间与世界坐标由ItemFeedback提供，渲染只读。
local Draw = {}

---@param vg NVGContextWrapper
---@param cx number
---@param cy number
---@param size number
---@param color number[]
---@param alpha number
---@param spark boolean?
local function Dot(vg, cx, cy, size, color, alpha, spark)
    local pixel = math.max(1, math.floor(size))
    local px, py = math.floor(cx-pixel/2), math.floor(cy-pixel/2)
    nvgBeginPath(vg)
    nvgRect(vg, px, py, pixel, pixel)
    if spark then
        nvgRect(vg, px-pixel, py, pixel*3, pixel)
        nvgRect(vg, px, py-pixel, pixel, pixel*3)
    end
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(alpha)))
    nvgFill(vg)
end

---@param vg NVGContextWrapper
---@param ax number
---@param ay number
---@param bx number
---@param by number
---@param width number
---@param color number[]
---@param alpha number
function Draw.PixelLine(vg, ax, ay, bx, by, width, color, alpha)
    local length = math.sqrt((bx-ax)^2+(by-ay)^2)
    local steps = math.max(1, math.min(36, math.ceil(length/math.max(1, width))))
    nvgBeginPath(vg)
    for index = 0, steps do
        local t = index/steps
        local size = math.max(1, width*(.35+.65*math.sin(t*math.pi)))
        nvgRect(vg, math.floor(ax+(bx-ax)*t-size/2), math.floor(ay+(by-ay)*t-size/2), size, size)
    end
    nvgFillColor(vg, nvgRGBA(color[1], color[2], color[3], math.floor(alpha)))
    nvgFill(vg)
end

---@param state BottleItemFeedback
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
---@param behind boolean
local function Particles(state, vg, x, y, ppu, behind)
    for _, particle in ipairs(state.particles) do
        if particle.behind == behind then
            local t = particle.age/particle.life
            local fade = (1-t)^1.4
            local cx, cy = x+particle.x*ppu, y-particle.y*ppu
            local size = math.max(1, particle.size*ppu*(1-.5*t))
            if particle.behind then
                -- 暖暗底衬托金色中心，控制在数个像素，不形成发光雾团。
                Dot(vg, cx, cy, size+1, {126,79,27}, 125*fade, false)
            end
            Dot(vg, cx, cy, size, particle.color, 235*fade, particle.shape == "spark")
            if particle.shape == "leaf" then
                Dot(vg, cx+size, cy-size, size, {192,232,117}, 180*fade)
            elseif particle.shape == "drop" then
                Dot(vg, cx, cy-size, math.max(1,size*.6), {218,249,255}, 220*fade)
            end
        end
    end
end

---@param state BottleItemFeedback
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
function Draw.Behind(state, vg, x, y, ppu)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    Particles(state, vg, x, y, ppu, true)
    nvgRestore(vg)
end

---@param effect BottleItemFeedbackPose
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
local function Action(effect, vg, x, y, ppu)
    local t = effect.age/effect.life
    local cx, cy = x+effect.x*ppu, y-effect.y*ppu
    local alpha = 255*(1-t)
    local radius = math.max(.23, math.min(.5, effect.radius))*ppu
    if effect.action == "cut" then
        local tx, ty = x+effect.tx*ppu, y-effect.ty*ppu
        local reach = radius*(.6+.7*math.min(1,t*3))
        Draw.PixelLine(vg, tx-reach, ty+reach*.65, tx+reach, ty-reach*.65,
            math.max(2,ppu*.045), {74,112,137}, alpha)
        Draw.PixelLine(vg, tx-reach, ty+reach*.65-1, tx+reach, ty-reach*.65-1,
            math.max(1,ppu*.022), {255,249,213}, alpha)
    elseif effect.action == "jelly" then
        local dx, dy = effect.tx-effect.x, effect.ty-effect.y
        local distance = math.sqrt(dx*dx+dy*dy)
        if distance < .001 then dx, dy, distance = 0, 1, 1 end
        local nx, ny = dx/distance, -dy/distance
        local start, finish = radius*.75, radius*(1.25+t*.7)
        for side = -1, 1, 2 do
            local offset = side*radius*.32
            Draw.PixelLine(vg, cx+nx*start-ny*offset, cy+ny*start+nx*offset,
                cx+nx*finish-ny*offset, cy+ny*finish+nx*offset,
                math.max(1,ppu*.025), {194,183,255}, alpha)
        end
    elseif effect.action == "grow" then
        -- 白色成团像素烟扩张上散，浅灰细沿保持在物品周围的局部范围。
        local puffs = {{-1,.2},{-.5,1},{.5,.85},{1,.1},{.35,-.6},{-.65,-.55}}
        local spread = radius*(.3+t*.95)
        local fade = math.min(1,t/.12)*(1-t)^.45
        for index, puff in ipairs(puffs) do
            local size = math.max(3, math.floor(radius*(.5+.08*math.sin(index+t*3))))
            local px = math.floor(cx+puff[1]*spread-size/2)
            local py = math.floor(cy-puff[2]*spread-t*radius*.3-size/2)
            nvgBeginPath(vg)
            nvgRect(vg, px-1, py, size+2, size)
            nvgRect(vg, px, py-1, size, size+2)
            nvgFillColor(vg, nvgRGBA(229,234,236, math.floor(220*fade)))
            nvgFill(vg)
            nvgBeginPath(vg)
            nvgRect(vg, px, py, size, size)
            nvgFillColor(vg, nvgRGBA(255,255,255, math.floor(255*fade)))
            nvgFill(vg)
        end
    elseif effect.action == "produce" then
        local bob = math.sin(t*math.pi)*radius*.34
        if effect.id == "cloud" then
            for index = -1, 1 do
                Dot(vg, cx+index*radius*.4, cy+radius*.6+t*radius*.6,
                    math.max(2, radius*.16), {151,222,255}, alpha)
            end
        elseif effect.id == "chick" then
            -- 一颗小蛋形提示源头；实际鸡蛋仍由既有spawn动画绘制。
            local size = math.max(3,radius*.24)
            Dot(vg, cx, cy+radius*.5+bob, size, {255,246,208}, alpha)
            Dot(vg, cx, cy+radius*.5+bob-size, size*.7, {255,255,241}, alpha)
        elseif effect.id == "coin_machine" then
            Draw.PixelLine(vg, cx-radius*.32, cy+radius*.1, cx+radius*.32, cy+radius*.1,
                math.max(2,ppu*.04), {255,220,120}, alpha)
        elseif effect.id == "fruit_tree" then
            for side = -1, 1, 2 do
                Dot(vg, cx+side*radius*.75, cy-radius*.5-bob,
                    math.max(2,radius*.18), {181,227,115}, alpha)
            end
        end
    elseif effect.action == "steal" and effect.value < 0 then
        -- 一枚清晰的金币沿短弧进入小偷，尾部保留小亮点；计分仍即时完成。
        local eased = t*t*(3-2*t)
        for index = 2, 1, -1 do
            local at = math.max(0, math.min(1, eased-index*.08))
            local px = effect.tx+(effect.x-effect.tx)*at
            local py = effect.ty+(effect.y-effect.ty)*at+math.sin(at*math.pi)*.17
            Dot(vg, x+px*ppu, y-py*ppu, math.max(1,ppu*.035)*(1-index*.18),
                {255,206,95}, alpha*(1-index*.2))
        end
        local px = effect.tx+(effect.x-effect.tx)*eased
        local py = effect.ty+(effect.y-effect.ty)*eased+math.sin(eased*math.pi)*.23
        -- 主金币直径为小偷当前直径的60%，最后一小段才缩入身体。
        local absorb = math.min(1,(1-t)/.14)
        local coinRadius = math.max(5,effect.radius*ppu*.6)*absorb
        require("Bottle.CoinIcon").Draw(vg,x+px*ppu,y-py*ppu,coinRadius)
    end
end

---@param state BottleItemFeedback
---@param vg NVGContextWrapper
---@param x number
---@param y number
---@param ppu number
function Draw.Front(state, vg, x, y, ppu)
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    Particles(state, vg, x, y, ppu, false)
    for _, effect in ipairs(state.effects) do Action(effect, vg, x, y, ppu) end
    nvgRestore(vg)
end

return Draw
