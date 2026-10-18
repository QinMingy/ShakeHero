-- A desk receipt made of independently exported paper and ink meshes.
-- Their common pivot is on the upper edge, while its contact shadow stays put.
local PaperSway={}

function PaperSway.New(scene,nodes)
    local pivot=scene:CreateChild("ReceiptWindPivot")
    -- Blender: receipt centre (99,-100) in a 420x840 design, shifted .5m
    -- back with the rest of the desk. Its upper edge stays pinned.
    local px,py,pz=-1.11,5.79,1.145
    -- Leave room for the free edge to tilt toward the desk without crossing
    -- the fixed contact-shadow slab beneath it.
    pivot.position=Vector3(px,py,pz-.09)
    local offset=Vector3(-px,-py,-pz)
    local count=0
    for name,node in pairs(nodes) do
        if name=="desk_receipt" or name:find("^receipt_") then
            node:SetParent(pivot)
            node.position=offset
            count=count+1
        end
    end
    return {pivot=pivot,time=0,parts=count}
end

function PaperSway.Tick(note,dt)
    note.time=note.time+math.min(math.max(dt or 0,0),.1)
    local t=note.time
    -- Tiny pitch and roll are enough to lift the loose end from its shadow.
    -- Two frequencies avoid the regular pendulum motion of a UI tween.
    local pitch=3.1*math.sin(t*1.55)+1.0*math.sin(t*2.71+.4)
    local roll=1.5*math.sin(t*1.18+.8)
    note.pivot.rotation=Quaternion(pitch,roll,0)
end

return PaperSway
