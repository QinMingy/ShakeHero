-- A quiet pixel bottle frame; the entire centre stays transparent behind the items.
local Glass = {}
---@type table<any, integer>
local images = {}
local IMAGE_WIDTH, IMAGE_HEIGHT = 1086, 1448
-- The frame bounds exclude the generated PNG's transparent margins.
-- Draw once at the original 4.8 x 6.4 metre size, without slicing its details.
local SOURCE_LEFT, SOURCE_TOP, SOURCE_WIDTH, SOURCE_HEIGHT = 120, 82, 846, 1286

---@param vg NVGContextWrapper
---@param x number Bottle centre in the caller's UI coordinates
---@param floorY number
---@param ppu number Pixels per metre, already scaled by the board
function Glass.Draw(vg, x, floorY, ppu)
    if ppu <= 0 then return end
    local handle = images[vg]
    if not handle then
        handle = nvgCreateImage(vg, "image/bottle/bottle-frame-v2.png", NVG_IMAGE_NEAREST)
        assert(handle > 0, "Missing bottle: image/bottle/bottle-frame-v2.png")
        images[vg] = handle
    end
    local left, top = x - 2.4 * ppu, floorY - 6.4 * ppu
    local width, height = 4.8 * ppu, 6.4 * ppu
    local scaleX, scaleY = width / SOURCE_WIDTH, height / SOURCE_HEIGHT
    nvgSave(vg)
    nvgShapeAntiAlias(vg, 0)
    nvgBeginPath(vg)
    nvgRect(vg, left, top, width, height)
    nvgFillPaint(vg, nvgImagePattern(vg, left - SOURCE_LEFT * scaleX,
        top - SOURCE_TOP * scaleY, IMAGE_WIDTH * scaleX, IMAGE_HEIGHT * scaleY, 0, handle, 1))
    nvgFill(vg)
    nvgRestore(vg)
end

---@param vg NVGContextWrapper
function Glass.Release(vg)
    local handle = images[vg]
    if handle then nvgDeleteImage(vg, handle) end
    images[vg] = nil
end

return Glass
