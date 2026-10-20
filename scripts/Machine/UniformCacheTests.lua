local Cache = require("Machine.UniformCache")
local Tests = {}

function Tests.Run()
    local originalVariant, originalVector2, originalVector4 = Variant, Vector2, Vector4
    local variants, vectors, writes = 0, 0, 0
    Variant = function(value) variants = variants + 1;return value end
    Vector2 = function(x, y) vectors = vectors + 1;return {x, y} end
    Vector4 = function(x, y, z, w) vectors = vectors + 1;return {x, y, z, w} end
    local ok, message = pcall(function()
        ---@return any
        local function material()
            return {SetShaderParameter = function(self, name, value)
                writes = writes + 1;self[name] = value
            end}
        end
        local cache, a, b = Cache.New(), material(), material()
        assert(cache:Scalar(a, "time", 0))
        assert(not cache:Scalar(a, "time", 0) and variants == 1 and writes == 1)
        assert(cache:Scalar(b, "time", 0) and writes == 2)
        assert(cache:Scalar(a, "time", .1) and a.time == .1)
        assert(cache:Vector2(a, "pixels", 370, 458))
        assert(not cache:Vector2(a, "pixels", 370, 458))
        assert(cache:Vector2(a, "pixels", 370, 459))
        assert(cache:Vector4(a, "stir", .5, .5, 0, 0))
        local count, allocations = writes, vectors
        for _ = 1, 1000 do
            assert(not cache:Vector4(a, "stir", .5, .5, 0, 0))
        end
        assert(writes == count and vectors == allocations)
        assert(cache:Vector4(a, "stir", .5, .5, .2, -.1))
        assert(a.stir[3] == .2 and a.stir[4] == -.1)
        assert(cache:Vector4(a, "stir", .5, .5, 0, 0)) -- reset clears the GPU slot once
        assert(not cache:Vector4(a, "stir", .5, .5, 0, 0))
        local replacement = material()
        assert(cache:Vector4(replacement, "stir", .5, .5, 0, 0))
    end)
    Variant, Vector2, Vector4 = originalVariant, originalVector2, originalVector4
    assert(ok, tostring(message))
    return 6
end

return Tests
