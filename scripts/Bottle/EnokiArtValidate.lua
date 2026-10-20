-- 金针菇美术隔离验收：不加载主程序、不访问玩家存档、不开放发布GM。
-- 上排左为游戏图集、右为已确认PNG；中排为灰阶／白闪／选中外边；下排为小图。
local Art = require("Bottle.Art")
local Items = require("Bottle.Items")
local PixelCache = require("Bottle.PixelCache")
local Atlas = require("Bottle.PixelAtlasData")
---@type NVGContextWrapper?
local vg = nil
local reference = 0

function Start()
    print("[金针菇验收] 开始独立图标检查，不加载无关玩法套件")
    ---@type table<string,BottlePixelSprite>
    local sprites = {}
    for index = 1, 100 do
        local name, value = debug.getupvalue(Art.Item, index)
        if name == "SPRITES" then sprites = value; break end
        if not name then break end
    end
    local sprite = assert(sprites.enoki, "金针菇原稿未注册")
    assert(sprite.width == 16 and sprite.height == 16, "金针菇不是16×16原稿")
    local region = assert(Atlas.regions[PixelCache.Fingerprint(sprite)], "金针菇图集指纹失配")
    assert(region[3] == 16 and region[4] == 16, "图集区域尺寸错误")
    assert(Items.byId.enoki.shape == "circle" and math.abs(Items.byId.enoki.radius - .3) < 1e-8,
        "金针菇物理或显示尺寸发生变化")
    local checks = 0
    for _, angle in ipairs({0, math.pi / 2, -math.pi / 3}) do
        for row = 0, 15 do
            for column = 0, 15 do
                local solid = false
                for _, group in ipairs(sprite.groups) do
                    for i = 1, #group.rects, 4 do
                        local rects = group.rects
                        if column >= rects[i] and column < rects[i] + rects[i + 2]
                            and row >= rects[i + 1] and row < rects[i + 1] + rects[i + 3] then
                            solid = true
                        end
                    end
                end
                local x, y = (column + .5 - 8) * 2, (row + .5 - 8) * 2
                local dx = x * math.cos(angle) - y * math.sin(angle)
                local dy = x * math.sin(angle) + y * math.cos(angle)
                assert(Art.HitItem("enoki", dx, dy, 16, angle) == solid, "透明或旋转拾取不一致")
                checks = checks + 1
            end
        end
    end
    print("[金针菇验收] 新指纹、16×16尺寸、圆形半径及透明旋转拾取" .. checks .. "点通过")
    ---@type table<string,BottlePixelSprite>
    local relicSprites = {}
    for index = 1, 100 do
        local name, value = debug.getupvalue(Art.Relic, index)
        if name == "RELIC_SPRITES" then relicSprites = value; break end
        if not name then break end
    end
    local relic = assert(relicSprites.see_you_tomorrow, "seeYouTomorrow原稿未注册")
    assert(relic.width == 16 and relic.height == 16, "seeYouTomorrow不是16×16原稿")
    local relicRegion = assert(Atlas.regions[PixelCache.Fingerprint(relic)], "遗物图集指纹失配")
    assert(relicRegion[3] == 16 and relicRegion[4] == 16, "遗物图集区域尺寸错误")
    local relicChecks = 0
    for _, angle in ipairs({0, math.pi / 2, -math.pi / 3}) do
        for row = 0, 15 do
            for column = 0, 15 do
                local solid = false
                for _, group in ipairs(relic.groups) do
                    for i = 1, #group.rects, 4 do
                        local rects = group.rects
                        if column >= rects[i] and column < rects[i] + rects[i + 2]
                            and row >= rects[i + 1] and row < rects[i + 1] + rects[i + 3] then solid = true end
                    end
                end
                local x, y = (column + .5 - 8) * 2, (row + .5 - 8) * 2
                local dx = x * math.cos(angle) - y * math.sin(angle)
                local dy = x * math.sin(angle) + y * math.cos(angle)
                assert(Art.HitRelic("see_you_tomorrow", dx, dy, 16, angle) == solid,
                    "遗物透明或旋转拾取不一致")
                relicChecks = relicChecks + 1
            end
        end
    end
    print("[seeYouTomorrow验收] 16×16图集与透明旋转拾取" .. relicChecks .. "点通过")
    vg = nvgCreate(0)
    assert(vg, "验收NanoVG上下文创建失败")
    reference = nvgCreateImage(vg,
        "image/enoki-redraw-preview-20261020/enoki-final-16x16.png", NVG_IMAGE_NEAREST)
    assert(reference > 0, "已确认PNG加载失败")
    SubscribeToEvent(vg, "NanoVGRender", "EnokiValidateRender")
end

function EnokiValidateRender()
    if not vg then return end
    local dpr = graphics:GetDPR()
    local width, height = graphics:GetWidth() / dpr, graphics:GetHeight() / dpr
    nvgBeginFrame(vg, width, height, dpr)
    nvgBeginPath(vg)
    nvgRect(vg, 0, 0, width, height)
    nvgFillColor(vg, nvgRGBA(100, 82, 56, 255))
    nvgFill(vg)
    local scale = math.min(width / 480, height / 680)
    nvgTranslate(vg, (width - 480 * scale) / 2, (height - 680 * scale) / 2)
    nvgScale(vg, scale, scale)
    Art.Item(vg, "enoki", 120, 110, 80, 0)
    nvgBeginPath(vg)
    nvgRect(vg, 280, 30, 160, 160)
    nvgFillPaint(vg, nvgImagePattern(vg, 280, 30, 160, 160, 0, reference, 1))
    nvgFill(vg)
    Art.Item(vg, "enoki", 80, 300, 48, 0, true)
    Art.Item(vg, "enoki", 240, 300, 48, 0, false, nil, nil, true)
    Art.ItemOutline(vg, "enoki", 400, 300, 48, 0, nil, nil, 3)
    Art.Item(vg, "enoki", 400, 300, 48, 0)
    Art.Item(vg, "enoki", 90, 455, 12, 0)
    Art.Item(vg, "enoki", 190, 455, 18, 0)
    Art.Item(vg, "enoki", 290, 455, 24, 0)
    Art.Item(vg, "enoki", 390, 455, 24, math.pi / 3)
    Art.Relic(vg, "see_you_tomorrow", 80, 600, 40)
    Art.Relic(vg, "see_you_tomorrow", 240, 600, 40, true)
    Art.RelicOutline(vg, "see_you_tomorrow", 400, 600, 40, 0, 3)
    Art.Relic(vg, "see_you_tomorrow", 400, 600, 40)
    nvgEndFrame(vg)
end

function Stop()
    if vg then
        Art.ReleaseContext(vg)
        if reference > 0 then nvgDeleteImage(vg, reference) end
        nvgDelete(vg)
        vg = nil
    end
end
