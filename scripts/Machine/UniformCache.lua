-- Avoid allocating Variant/vector wrappers when a material parameter is unchanged.
-- Cached numbers are separate from caller-owned vectors and never mutate them.
---@class MachineUniformCache
---@field materials table<any, table<string, any>>
local Cache = {}
Cache.__index = Cache

function Cache.New()
    return setmetatable({materials = setmetatable({}, {__mode = "k"})}, Cache)
end

---@param material Material
---@return table
function Cache:Values(material)
    local values = self.materials[material]
    if not values then values = {};self.materials[material] = values end
    return values
end

---@param material Material
---@param name string
---@param value number
function Cache:Scalar(material, name, value)
    local values = self:Values(material)
    if values[name] == value then return false end
    material:SetShaderParameter(name, Variant(value))
    values[name] = value
    return true
end

---@param material Material
---@param name string
---@param x number
---@param y number
function Cache:Vector2(material, name, x, y)
    local values = self:Values(material)
    local previous = values[name]
    if previous and previous[1] == x and previous[2] == y then return false end
    material:SetShaderParameter(name, Variant(Vector2(x, y)))
    if not previous then previous = {};values[name] = previous end
    previous[1], previous[2] = x, y
    return true
end

---@param material Material
---@param name string
---@param x number
---@param y number
---@param z number
---@param w number
function Cache:Vector4(material, name, x, y, z, w)
    local values = self:Values(material)
    local previous = values[name]
    if previous and previous[1] == x and previous[2] == y
        and previous[3] == z and previous[4] == w then return false end
    material:SetShaderParameter(name, Variant(Vector4(x, y, z, w)))
    if not previous then previous = {};values[name] = previous end
    previous[1], previous[2], previous[3], previous[4] = x, y, z, w
    return true
end

return Cache
