-- 只保存本宏正时间物理步内已验证的真实Begin；End仍由Physics维护持续计数。
-- 调用方负责World、owned-node和真实瓶壁校验，不按位置/速度推测触碰。
local FrameBudget = require("Bottle.FrameBudget")

---@class BottleStepPairFact
---@field a number
---@field b number
---@field recordA BottleBody
---@field recordB BottleBody

---@class BottleStepWallFact
---@field record BottleBody
---@field bottom boolean?
---@field top boolean?
---@field side boolean?

---@class BottleStepContactFacts
---@field active boolean
---@field bodies table<number,BottleBody>?
---@field pairs table<string,BottleStepPairFact>
---@field walls table<number,BottleStepWallFact>
local Facts = {}
Facts.__index = Facts

---@param a number
---@param b number
---@return string
---@return integer
---@return integer
local function PairKey(a,b)
    -- CJSON可能恢复为1.0，节点解析则为1；严格归一整数，拒绝小数而不四舍五入。
    assert(type(a)=="number" and type(b)=="number","接触UID必须为数字")
    local first,second=math.tointeger(a),math.tointeger(b)
    assert(first and second and first>=1 and second>=1 and first<=2147483647
        and second<=2147483647,"接触UID必须为合法正整数")
    if first>second then first,second=second,first end
    return tostring(first) .. ":" .. tostring(second),first,second
end

---@return BottleStepContactFacts
function Facts.New()
    return setmetatable({active=false,bodies=nil,pairs={},walls={}},Facts)
end

-- 只在首个正dt Scene.Update前调用；零dt删除屏障不得打开窗口。
---@param bodies table<number,BottleBody>
function Facts:BeginStep(bodies)
    self:Clear()
    self.bodies,self.active=bodies,true
end

-- 最后一次Scene.Update返回后关窗；事实继续供After/Contacts读取。
function Facts:EndStep()
    self.active,self.bodies=false,nil
end

-- 回调入口不能yield；重复fixture Begin只保留一份物品对事实。
---@param recordA BottleBody
---@param recordB BottleBody
---@return boolean accepted
function Facts:Pair(recordA,recordB)
    local bodies=self.bodies
    if not self.active or not bodies or recordA.uid==recordB.uid
        or bodies[recordA.uid]~=recordA or bodies[recordB.uid]~=recordB then return false end
    if recordA.uid>recordB.uid then recordA,recordB=recordB,recordA end
    local key,a,b=PairKey(recordA.uid,recordB.uid)
    local previous=self.pairs[key]
    if not previous or previous.recordA~=recordA or previous.recordB~=recordB then
        self.pairs[key]={a=a,b=b,recordA=recordA,recordB=recordB}
    end
    return true
end

-- wallName来自调用方已验证属于本世界的静态瓶壁节点。
---@param record BottleBody
---@param wallName string
---@return boolean accepted
function Facts:Wall(record,wallName)
    local bodies=self.bodies
    if not self.active or not bodies or bodies[record.uid]~=record then return false end
    local fact=rawget(self.walls,record.uid)
    if not fact or fact.record~=record then
        fact={record=record}
        self.walls[record.uid]=fact
    end
    if wallName=="floor" then fact.bottom=true
    elseif wallName=="top" then fact.top=true
    else fact.side=true end
    return true
end

---@param uid number
---@param targetUid number
---@param bodies table<number,BottleBody>
---@return boolean
function Facts:HasPair(uid,targetUid,bodies)
    local fact=self.pairs[PairKey(uid,targetUid)]
    return fact~=nil and bodies[fact.a]==fact.recordA and bodies[fact.b]==fact.recordB
end

-- 与持续计数的快照取并集；不消费事实、不共享条目、不排序或改坐标/角度。
-- 调用方合并完成后统一按UID排序；大快照只在读取阶段允许协作式让出。
---@param result BottlePhysicsContacts
---@param bodies table<number,BottleBody>
---@param scratch {seen:table<string,boolean>,pairRows:number[][]}? Exclusive reader scratch.
function Facts:Merge(result,bodies,scratch)
    local seen=scratch and scratch.seen or {}
    for key in pairs(seen) do seen[key]=nil end
    local copied=0
    for _,pair in ipairs(result.pairs) do
        seen[PairKey(pair[1],pair[2])]=true
        copied=copied+1
        if copied%128==0 then FrameBudget.Checkpoint() end
    end
    copied=0
    for key,fact in pairs(self.pairs) do
        if bodies[fact.a]==fact.recordA and bodies[fact.b]==fact.recordB and not seen[key] then
            local index=#result.pairs+1
            local row=scratch and scratch.pairRows[index] or nil
            if not row then
                row={}
                if scratch then scratch.pairRows[index]=row end
            end
            row[1],row[2]=fact.a,fact.b
            result.pairs[index]=row
            seen[key]=true
        end
        copied=copied+1
        if copied%128==0 then FrameBudget.Checkpoint() end
    end
    copied=0
    for uid,fact in pairs(self.walls) do
        if bodies[uid]==fact.record then
            result.wall[uid]=true
            if fact.bottom then result.bottom[uid]=true end
            if fact.top then result.top[uid]=true end
            if fact.side then result.side[uid]=true end
        end
        copied=copied+1
        if copied%32==0 then FrameBudget.Checkpoint() end
    end
end

---@param uid number
function Facts:Forget(uid)
    self.walls[uid]=nil
    for key,fact in pairs(self.pairs) do
        if fact.a==uid or fact.b==uid then self.pairs[key]=nil end
    end
end

function Facts:Clear()
    self.active,self.bodies=false,nil
    for key in pairs(self.pairs) do self.pairs[key]=nil end
    for uid in pairs(self.walls) do self.walls[uid]=nil end
end

return Facts
