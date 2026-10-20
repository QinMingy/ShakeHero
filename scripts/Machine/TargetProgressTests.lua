local Progress = require("Machine.TargetProgress")
local Tests = {}

function Tests.Run()
    local view = {}
    Progress.Burst(view, 0, 0, false, 20)
    local list = view.targetBursts
    assert(#list == 26)
    local survivors = {}
    for index, particle in ipairs(list) do
        particle.age, particle.life = 0, index % 2 == 0 and .1 or 1
        if index % 2 == 1 then survivors[#survivors + 1] = particle end
    end
    Progress.Update(view, .2)
    assert(view.targetBursts == list and #list == 13)
    for index, particle in ipairs(survivors) do assert(list[index] == particle) end
    Progress.Update(view, 2)
    assert(#list == 0 and Progress.GetPoolStats(view).active == 0)

    local warm = {}
    Progress.Burst(warm, 0, 0, true, 20)
    Progress.Update(warm, 2)
    local created = Progress.GetPoolStats(warm).created
    for _ = 1, 100 do
        Progress.Burst(warm, 0, 0, true, 20)
        Progress.Update(warm, 2)
    end
    local stats = Progress.GetPoolStats(warm)
    assert(stats.created == created and stats.reused == 2600 and stats.active == 0)

    local dense = {}
    for _ = 1, 30 do Progress.Burst(dense, 0, 0, false, 20) end
    assert(#dense.targetBursts == 780) -- The cache limit cannot drop visible particles.
    Progress.Update(dense, 2)
    stats = Progress.GetPoolStats(dense)
    assert(stats.peak == 780 and stats.active == 0 and stats.free == 256)
    return 3
end

return Tests
