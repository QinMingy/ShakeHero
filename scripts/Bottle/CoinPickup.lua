-- 纯表现：先重力散落，再沿曲线吸向回合金币。每枚携带一份收益，不按金币数创建对象。
local UI = require("urhox-libs/UI")
local Coin = require("Bottle.CoinIcon")

---@class BottlePickupCoin
---@field age number
---@field delay number
---@field drop number
---@field flight number
---@field x number
---@field y number
---@field vx number
---@field floor number
---@field credit number
---@field source string
---@field index integer
---@field departed boolean

---@class BottlePickupBatch
---@field amount number
---@field x number
---@field y number
---@field source string
---@field height number

---@class BottleCoinPickup : Widget
---@field coins BottlePickupCoin[]
---@field waiting BottlePickupBatch[]
---@field serial integer
---@field targetX number
---@field targetY number
---@field shakeTargetX number
---@field shakeTargetY number
---@overload fun(props:WidgetProps): BottleCoinPickup
local Pickup = UI.Widget:Extend("BottleCoinPickup") --[[@as BottleCoinPickup]]
Pickup.REEL_COUNT = 36

---@param amount number
---@return integer
function Pickup.Count(amount)
    if amount <= 0 then return 0 end
    if amount < 5 then return 3 end
    if amount < 20 then return 5 end
    if amount < 50 then return 8 end
    if amount < 200 then return 11 end
    if amount < 1000 then return 15 end
    return 20
end

function Pickup:Init(props)
    UI.Widget.Init(self, props)
    self.coins, self.waiting, self.serial = {}, {}, 0
    self.targetX, self.targetY = 185, 128
    self.shakeTargetX, self.shakeTargetY = 32, 28
end

function Pickup:Reset()
    self.coins, self.waiting, self.serial = {}, {}, 0
end

function Pickup:Busy()
    return #self.coins > 0 or #self.waiting > 0
end

---@param amount number
---@param x number 370宽设计空间
---@param y number
---@param source string
---@param height number
function Pickup:Burst(amount, x, y, source, height)
    if amount <= 0 then return end
    self.waiting[#self.waiting + 1] = {amount = amount, x = x, y = y, source = source, height = height}
    self:LaunchWaiting()
end

function Pickup:LaunchWaiting()
    -- 忙碌时保留批次，最多128个飞币；收益不会因视觉限流而丢失。
    while #self.waiting > 0 and #self.coins < 128 do
        local count = self.waiting[1].source == "reels" and Pickup.REEL_COUNT or Pickup.Count(self.waiting[1].amount)
        if #self.coins + count > 128 then break end
        local batch = table.remove(self.waiting, 1)
        ---@type number
        local credited = 0
        self.serial = self.serial + 1
        for i = 1, count do
            local reels = batch.source == "reels"
            -- 两段飞币都按整币分摊，最后一枚补齐真实批次金额，保证抵达总额守恒。
            local nextCredit = i == count and batch.amount
                or (reels and math.min(batch.amount, math.ceil(batch.amount * (i / count)))
                    or math.floor(batch.amount * (i / count)))
            self.coins[#self.coins + 1] = {
                age = 0, delay = (i - 1) * (reels and .022 or .026),
                drop = .25 + (i % 3) * .018,
                flight = reels and .72 or .37 + (i % 4) * .022,
                x = math.max(12, math.min(358, batch.x)),
                y = math.max(12, math.min(batch.height - 18, batch.y)),
                vx = (((i * 37 + self.serial * 19) % 101) - 50) * 1.3,
                floor = batch.height - 12, credit = nextCredit - credited,
                source = batch.source, index = i, departed = false,
            }
            credited = nextCredit
        end
    end
end

---@param coin BottlePickupCoin
---@param age number
---@param targetX number
---@param targetY number
---@return number x
---@return number y
---@return number scale
function Pickup.Pose(coin, age, targetX, targetY)
    local t = math.max(0, age - coin.delay)
    -- 物体收益和转轮长串共用生成／散落的短缓冲，之后才进入吸入曲线。
    local dropT = math.min(t, coin.drop)
    local dx = coin.x + coin.vx * dropT
    local dy = coin.y + 24 * dropT + 330 * dropT * dropT
    if dy > coin.floor then dy = coin.floor - (dy - coin.floor) * .3 end
    if t <= coin.drop then return dx, dy, math.min(1, .55 + t * 6) end
    local progress = math.min(1, (t - coin.drop) / coin.flight)
    local u = progress * progress -- 吸入阶段逐渐加速，先散落再收走。
    local v = 1 - u
    local controlX = dx + coin.vx * .16
    local x = v ^ 3 * dx + 3 * v * v * u * controlX
        + 3 * v * u * u * (targetX + (coin.index % 2 == 0 and 18 or -18)) + u ^ 3 * targetX
    local y = v ^ 3 * dy + 3 * v * v * u * (dy + 28)
        + 3 * v * u * u * (targetY + 60) + u ^ 3 * targetY
    return x, y, 1 - .45 * math.max(0, (progress - .75) / .25)
end

---@param dt number
---@param depart fun(amount:number,source:string)
---@param arrive fun(amount:number,source:string)
function Pickup:Step(dt, depart, arrive)
    self:LaunchWaiting()
    -- 按出生顺序触发回调，低帧率一次跨过落地与抵达也只入账一次。
    local keep = {}
    for _, coin in ipairs(self.coins) do
        coin.age = coin.age + math.max(0, dt)
        if not coin.departed and coin.age >= coin.delay + coin.drop then
            coin.departed = true
            depart(coin.credit, coin.source)
        end
        if coin.age >= coin.delay + coin.drop + coin.flight then
            arrive(coin.credit, coin.source)
        else
            keep[#keep + 1] = coin
        end
    end
    self.coins = keep
    self:LaunchWaiting()
end

function Pickup:Render(vg)
    local b = self:GetAbsoluteLayout()
    if b.w <= 0 or b.h <= 0 then return end
    local s = b.w / 370
    nvgSave(vg)
    nvgIntersectScissor(vg, b.x, b.y, b.w, b.h)
    for _, coin in ipairs(self.coins) do
        if coin.age >= coin.delay then
            -- 即时收益始终先进入左上角，即使飞行途中已开始结算也不突然改道。
            local targetX = coin.source == "running" and self.shakeTargetX or self.targetX
            local targetY = coin.source == "running" and self.shakeTargetY or self.targetY
            local x, y, scale = Pickup.Pose(coin, coin.age, targetX, targetY)
            Coin.Draw(vg, b.x + x * s, b.y + y * s, 8 * scale * s, coin.age * 13 + coin.index)
        end
    end
    nvgRestore(vg)
end

return Pickup
