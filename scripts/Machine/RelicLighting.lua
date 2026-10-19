-- 持有栏遗物进入机台现有受光场景；UI只保留布局、滚动和点击。
-- 同一主光、cookie、时间与alpha裁切材质，不能再把彩色图标提交到UI光照层。
local L = require("Machine.LayeredLayout")
local Atlas = require("Bottle.PixelAtlasData")
local PixelCache = require("Bottle.PixelCache")
local LoadRelics = require("Bottle.RelicSprites")
---@type any
local Lighting = {}
Lighting.__index = Lighting

-- 从同一像素原稿计算图集指纹，避免另存一份遗物id/UV表而随美术更新失配。
local function Sprite(rows, palette, mirror)
    local sprite = {width = #rows[1], height = #rows, groups = {}, mirror = mirror or false}
    local byKey = {}
    for key, color in pairs(palette) do
        local group = {color = color, rects = {}}
        byKey[key] = group
        sprite.groups[#sprite.groups + 1] = group
    end
    for y, row in ipairs(rows) do
        local x = 1
        while x <= #row do
            local key, right = row:sub(x, x), x + 1
            while right <= #row and row:sub(right, right) == key do right = right + 1 end
            if key ~= "." then
                local rects = assert(byKey[key]).rects
                rects[#rects + 1], rects[#rects + 2] = x - 1, y - 1
                rects[#rects + 1], rects[#rects + 2] = right - x, 1
            end
            x = right
        end
    end
    return sprite
end
local regions = {}
for id, sprite in pairs(LoadRelics(Sprite, {10, 10, 26, 255})) do
    local translucent = false
    for _, group in ipairs(sprite.groups) do
        if (group.color[4] or 255) < 255 then translucent = true end
    end
    regions[id] = {region = Atlas.regions[PixelCache.Fingerprint(sprite)], mirror = sprite.mirror,
        sprite = sprite, translucent = translucent}
end

local function Finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function ValidRect(rect)
    return type(rect) == "table" and Finite(rect.x) and Finite(rect.y)
        and Finite(rect.w) and Finite(rect.h) and rect.w > 0 and rect.h > 0
end

local function Multiply(a, b)
    return {a[1]*b[1]+a[3]*b[2], a[2]*b[1]+a[4]*b[2],
        a[1]*b[3]+a[3]*b[4], a[2]*b[3]+a[4]*b[4],
        a[1]*b[5]+a[3]*b[6]+a[5], a[2]*b[5]+a[4]*b[6]+a[6]}
end

local function Origin(origin, rect)
    if type(origin) == "table" then
        local x, y = origin[1] or .5, origin[2] or .5
        if not Finite(x) or not Finite(y) then return nil end
        return rect.x + x * rect.w, rect.y + y * rect.h
    end
    local x = (origin == "top-left" or origin == "left" or origin == "bottom-left") and 0
        or (origin == "top-right" or origin == "right" or origin == "bottom-right") and 1 or .5
    local y = (origin == "top-left" or origin == "top" or origin == "top-right") and 0
        or (origin == "bottom-left" or origin == "bottom" or origin == "bottom-right") and 1 or .5
    return rect.x + x * rect.w, rect.y + y * rect.h
end

-- 对齐UI.Core.UI.renderWidgetTree的变换次序，ScrollView进入子层后才平移。
-- 不依赖nvgCurrentTransform的float*出参回填（当前原生Lua绑定不会回填表）。
-- container的共有镜头变换不参与；同一位移已由LitSpriteScene相机处理。
function Lighting:Transform(widget)
    local chain, current = {}, widget
    while current and current ~= self.reference do
        if #chain >= 64 then return nil end
        chain[#chain + 1] = current
        current = current.parent
    end
    if not current or #chain == 0 then return nil end
    local matrix = {1, 0, 0, 1, 0, 0}
    for i = #chain, 1, -1 do
        local child = chain[i]
        if type(child.GetAbsoluteLayout) ~= "function" then return nil end
        local rect = child:GetAbsoluteLayout()
        if not ValidRect(rect) then return nil end
        ---@type table
        local props = child.props or {}
        ---@type table
        local rendered = child.renderProps_ or {}
        local scale = rendered.scale or props.scale or 1
        local rotate = rendered.rotate or props.rotate or 0
        local tx, ty = rendered.translateX or props.translateX or 0, rendered.translateY or props.translateY or 0
        if not Finite(scale) or not Finite(rotate) or not Finite(tx) or not Finite(ty) then return nil end
        local ox, oy = Origin(props.transformOrigin, rect)
        if not ox or not oy then return nil end
        local angle = math.rad(rotate)
        local a, b = math.cos(angle) * scale, math.sin(angle) * scale
        matrix = Multiply(matrix, {a, b, -b, a,
            ox + a*(tx-ox) - b*(ty-oy), oy + b*(tx-ox) + a*(ty-oy)})
        if i > 1 and type(child.GetScroll) == "function" then
            local sx, sy = child:GetScroll()
            if not Finite(sx) or not Finite(sy) then return nil end
            matrix = Multiply(matrix, {1, 0, 0, 1, -sx, -sy})
        end
    end
    for i = 1, 6 do if not Finite(matrix[i]) then return nil end end
    if math.abs(matrix[1]*matrix[4]-matrix[2]*matrix[3]) < .000001 then return nil end
    return matrix
end

---@return number[][]
local function ClippedPolygon(rect, clip, transform, mirror)
    ---@type number[][]
    local points = {}
    for _, uv in ipairs({{0, 0}, {1, 0}, {1, 1}, {0, 1}}) do
        local x, y = rect.x + uv[1] * rect.w, rect.y + uv[2] * rect.h
        points[#points + 1] = {transform[1] * x + transform[3] * y + transform[5],
            transform[2] * x + transform[4] * y + transform[6], mirror and 1 - uv[1] or uv[1], uv[2]}
    end
    for _, edge in ipairs({{1, clip.x, 1}, {1, clip.x + clip.w, -1},
        {2, clip.y, 1}, {2, clip.y + clip.h, -1}}) do
        if #points == 0 then break end
        ---@type number[][]
        local output = {}
        local previous = points[#points]
        local pd = (previous[edge[1]] - edge[2]) * edge[3]
        for _, point in ipairs(points) do
            local distance = (point[edge[1]] - edge[2]) * edge[3]
            if (distance >= 0) ~= (pd >= 0) then
                local amount = pd / (pd - distance)
                local hit = {}
                for i = 1, 4 do hit[i] = previous[i] + (point[i] - previous[i]) * amount end
                output[#output + 1] = hit
            end
            if distance >= 0 then output[#output + 1] = point end
            previous, pd = point, distance
        end
        points = output
    end
    return points
end

function Lighting.New(scene, reference)
    local self = setmetatable({scene = scene, reference = reference,
        entries = {}, textures = {}, materials = {}}, Lighting)
    local begin, dispose = scene.Begin, scene.Dispose
    scene.Begin = function(owner, vg, ...)
        begin(owner, vg, ...)
        -- 未被UI遍历的隐藏页、移出视口、弹窗重挂或新局图标立即失活。
        for _, entry in pairs(self.entries) do entry.node.enabled = false end
    end
    scene.Dispose = function(owner, ...)
        self:Dispose()
        return dispose(owner, ...)
    end
    return self
end

-- 半透明原稿不进入既有不透明图集。只在首次显示时按原像素生成小贴图，
-- 仍保留每组153/190/200等原始alpha；后续帧、翻页和新局复用。
function Lighting:SourceTexture(id, source)
    if self.textures[id] then return self.textures[id] end
    local sprite = source.sprite
    local image = Image()
    assert(image:SetSize(sprite.width, sprite.height, 4))
    image:Clear(Color(0, 0, 0, 0))
    for _, group in ipairs(sprite.groups) do
        local color, rects = group.color, group.rects
        local value = Color(color[1] / 255, color[2] / 255, color[3] / 255, (color[4] or 255) / 255)
        for i = 1, #rects, 4 do
            for y = rects[i + 1], rects[i + 1] + rects[i + 3] - 1 do
                for x = rects[i], rects[i] + rects[i + 2] - 1 do image:SetPixel(x, y, value) end
            end
        end
    end
    local texture = Texture2D:new()
    texture:SetSRGB(true)
    texture:SetNumLevels(1)
    texture:SetFilterMode(FILTER_NEAREST)
    assert(texture:SetData(image, false))
    self.textures[id] = texture
    return texture
end

function Lighting:Material(id, source)
    local scene = self.scene
    local key = source.region and "relic-holder" or "relic-holder-" .. id
    if self.materials[key] then return self.materials[key] end
    local material = Material:new()
    assert(material:SetSurfaceShader(source.translucent and "Shaders/BLGL/LayeredRelicAlphaLit.shader"
        or "Shaders/BLGL/LayeredSpriteLit.shader"))
    local texture = source.region and assert(cache:GetResource("Texture2D", Atlas.path))
        or self:SourceTexture(id, source)
    texture:SetFilterMode(FILTER_NEAREST)
    assert(material:SetSurfaceTexture("sprite_map", texture))
    assert(material:SetSurfaceTexture("cookie_map", scene.cookieTexture))
    material:SetShaderParameter("cookie_time", Variant(scene.time))
    -- LitSpriteScene.Tick统一推进cookie_time，不另开光照时钟。
    scene.materials[key] = material
    self.materials[key] = material
    return material
end

-- 返回true表示已接管图标（包括完整裁出视口），false才回退原UI像素。
function Lighting:Draw(key, id, rect, viewport)
    local scene = self.scene
    if self.disposed then return false end
    local source = regions[id]
    local transform = self:Transform(key)
    local clipTransform = self:Transform(viewport)
    local clip = viewport and viewport:GetAbsoluteLayout()
    if not source or not ValidRect(scene.bounds) or not ValidRect(rect) or not ValidRect(clip)
        or not Finite(scene.scale) or scene.scale <= 0 or not Finite(scene.distance) or scene.distance <= 0
        or not transform or not clipTransform then
        self:Release(key)
        return false
    end
    -- 持有栏viewport没有旋转；出现不受支持的倾斜裁剪时安全回到原UI绘制。
    if math.abs(clipTransform[2]) > .000001 or math.abs(clipTransform[3]) > .000001 then
        self:Release(key)
        return false
    end
    local left, right = clipTransform[1]*clip.x+clipTransform[5],
        clipTransform[1]*(clip.x+clip.w)+clipTransform[5]
    local top, bottom = clipTransform[4]*clip.y+clipTransform[6],
        clipTransform[4]*(clip.y+clip.h)+clipTransform[6]
    clip = {x = math.min(left, right), y = math.min(top, bottom),
        w = math.abs(right-left), h = math.abs(bottom-top)}
    local polygon = ClippedPolygon(rect, clip, transform, source.mirror)
    local entry = self.entries[key]
    if #polygon < 3 then
        if entry then entry.node.enabled = false end
        return true
    end
    if not entry then
        local node = self.scene.scene:CreateChild("OwnedRelic_" .. id)
        local geometry = node:CreateComponent("CustomGeometry")
        -- 半透明幽灵接收主光和阴影，但不投下不透明的硬影。
        geometry.viewMask, geometry.castShadows = 1, not source.translucent
        entry = {node = node, geometry = geometry}
        self.entries[key] = entry
    end
    entry.node.enabled = true
    local region = source.region or {0, 0, source.sprite.width, source.sprite.height}
    local textureWidth = source.region and Atlas.width or source.sprite.width
    local textureHeight = source.region and Atlas.height or source.sprite.height
    local values = {id, scene.bounds.x, scene.bounds.y, scene.scale, scene.distance}
    for _, point in ipairs(polygon) do
        for i = 1, 4 do values[#values + 1] = point[i] end
    end
    local signature = table.concat(values, ":")
    if entry.signature == signature then return true end
    entry.signature = signature
    local geometry, bounds, scale = entry.geometry, scene.bounds, scene.scale
    -- 贴在底部毡面的前方；透视补偿保持44px槽位和旧图标半径完全一致。
    local depth = -.13
    local perspective = (scene.distance + depth) / scene.distance
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    for i = 2, #polygon - 1 do
        for _, point in ipairs({polygon[1], polygon[i], polygon[i + 1]}) do
            geometry:DefineVertex(Vector3(((point[1] - bounds.x) / scale - L.width / 2) / 100 * perspective,
                (L.height / 2 - (point[2] - bounds.y) / scale) / 100 * perspective, depth))
            geometry:DefineNormal(Vector3(0, 0, -1))
            geometry:DefineTexCoord(Vector2((region[1] + point[3] * region[3]) / textureWidth,
                (region[2] + point[4] * region[4]) / textureHeight))
        end
    end
    geometry:Commit()
    geometry:SetMaterial(self:Material(id, source))
    return true
end

function Lighting:Release(key)
    local entry = self.entries[key]
    if not entry then return end
    entry.node:Remove()
    self.entries[key] = nil
end

function Lighting:Hide()
    for _, entry in pairs(self.entries) do entry.node.enabled = false end
end

function Lighting:Dispose()
    if self.disposed then return end
    self.disposed = true
    for key in pairs(self.entries) do self:Release(key) end
    for key in pairs(self.materials) do self.scene.materials[key] = nil end
    for _, texture in pairs(self.textures) do texture:Dispose() end
    self.materials, self.textures = {}, {}
end

return Lighting
