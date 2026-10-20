-- 大数组分块排序与稳定归并：只在安全边界让出，不改变比较器、数组成员或顺序规则。
-- 小数组继续使用原生table.sort；大数组在相等键时保留输入顺序。
local FrameBudget = require("Bottle.FrameBudget")
local BudgetSort = {}
local CHUNK_SIZE = 128
local CHECK_EVERY = 64

---@generic T
---@param array T[] 连续1-based数组；排序期间由调用方独占
---@param less fun(a:T,b:T):boolean 严格弱序比较器
function BudgetSort.Sort(array, less)
    local count = #array
    if count < 2 then return end
    FrameBudget.Checkpoint()
    if count <= CHUNK_SIZE then
        table.sort(array, less)
        return
    end
    ---@type number[]
    local indices = {}
    ---@type T[]
    local source = {}
    -- 仅排序小块的整数索引，不为每个值分配装饰table；原索引作为相等键的稳定次序。
    local function IndexLess(a, b)
        if less(array[a], array[b]) then return true end
        if less(array[b], array[a]) then return false end
        return a < b
    end
    for first = 1, count, CHUNK_SIZE do
        FrameBudget.Checkpoint()
        local last = math.min(count, first + CHUNK_SIZE - 1)
        local length = last - first + 1
        for index = #indices, length + 1, -1 do indices[index] = nil end
        for index = 1, length do indices[index] = first + index - 1 end
        table.sort(indices, IndexLess)
        for index = 1, length do source[first + index - 1] = rawget(array, indices[index]) end
    end
    local destination = array
    local width = CHUNK_SIZE
    while width < count do
        for first = 1, count, width * 2 do
            local middle = math.min(count + 1, first + width)
            local last = math.min(count, first + width * 2 - 1)
            local left, right = first, middle
            for index = first, last do
                if index % CHECK_EVERY == 0 then FrameBudget.Checkpoint() end
                -- 相等时先取左半，保持块间稳定次序。
                if right > last or (left < middle and not less(source[right], source[left])) then
                    destination[index] = source[left]
                    left = left + 1
                else
                    destination[index] = source[right]
                    right = right + 1
                end
            end
        end
        source, destination = destination, source
        width = width * 2
    end
    if source ~= array then
        for index = 1, count do
            if index % CHECK_EVERY == 0 then FrameBudget.Checkpoint() end
            array[index] = source[index]
        end
    end
end

return BudgetSort
