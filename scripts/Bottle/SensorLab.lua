-- PC 开发态的本地文件输入桥；不使用客户端禁用的 HTTP，也不读写玩家存档。
local Input = require("Bottle.SensorLabInput")
local PublishConfig = require("PublishConfig")
local Platform = require("urhox-libs.Platform.PlatformUtils")

---@class BottleSensorLab
---@field input BottleSensorLabInput
---@field enabled boolean
---@field configured boolean
---@field error string
---@field pollWait number
---@field configWait number
---@field hadData boolean
local Lab = {}
Lab.__index = Lab

local function allowed()
    return PublishConfig.PUBLISH_MODE == false and Platform.IsDesktopPlatform()
end

---@param name string
---@return table?
---@return string?
local function readJson(name)
    if not cache:Exists(name) then return nil end
    ---@type File?
    local file = nil
    local ok, value = pcall(function()
        file = cache:GetFile(name)
        if not file or file.size > 131072 then error("输入文件不可读或过大") end
        return cjson.decode(file:ReadLine())
    end)
    if file then file:Dispose() end
    if not ok then return nil, tostring(value) end
    if type(value) ~= "table" then return nil, "输入格式无效" end
    return value
end

---@return BottleSensorLab
function Lab.New()
    local self = setmetatable({}, Lab)
    self.input = Input.New()
    self.enabled = allowed()
    self.configured, self.error, self.pollWait, self.configWait, self.hadData = false, "", 0, 0, false
    if self.enabled then self:Configure() end
    return self
end

function Lab:Configure()
    if not allowed() then return false end
    local value, message = readJson("SensorLab/connection.json")
    if not value then self.error = message or ""; return false end
    local directory = type(value.directory) == "string" and value.directory:gsub("\\", "/"):gsub("/+$", "") or ""
    if value.format ~= "shakehero-sensor-connection/v1" or #directory > 1024
        or not directory:match("/dev/sensor%-lab/%.local/game%-bridge$")
        or directory:find("/../", 1, true) then
        self.error = "本地输入桥配置无效"; return false
    end
    local ok, mounted = pcall(cache.AddResourceDir, cache, directory, true)
    self.configured = ok and mounted == true
    self.error = self.configured and "" or "无法打开本地输入桥"
    return self.configured
end

function Lab:SetEnabled(value)
    if not allowed() then return false end
    self.enabled = value == true
    self:Reset()
    if self.enabled and not self.configured then self:Configure() end
    return not self.enabled or self.configured
end

function Lab:Reset()
    self.input:Reset()
end

---@param dt number
---@param canApply boolean
---@param touchHolding boolean
function Lab:Update(dt, canApply, touchHolding)
    local permitted = allowed()
    self.input:Update(dt, permitted and self.enabled and self.configured and canApply, touchHolding)
    if not permitted or not self.enabled then return end
    if not self.configured then
        self.configWait = self.configWait - dt
        if self.configWait <= 0 then self.configWait = 1; self:Configure() end
        return
    end
    self.pollWait = self.pollWait - dt
    if self.pollWait > 0 then return end
    self.pollWait = 1 / 30
    local value, message = readJson("shakehero-sensor-bridge.json")
    if not value then self.error = message or ""; return end
    local ok, errorText = pcall(self.input.Ingest, self.input, value)
    self.error = ok and "" or tostring(errorText)
end

function Lab:IsAvailable()
    return allowed() and self.enabled and self.configured and self.input:IsAvailable()
end

function Lab:TakeSettings()
    return self.input:TakeSettings()
end

function Lab:GetState()
    local available = self:IsAvailable()
    self.hadData = self.hadData or available
    return { enabled = self.enabled and allowed(), configured = self.configured, available = available,
        error = self.error, status = not self.enabled and "disabled" or not self.configured and "missing"
            or available and "online" or (self.hadData or self.error ~= "") and "stale" or "waiting" }
end

function Lab:Dispose()
    self.enabled = false
    self:Reset()
end

return Lab
