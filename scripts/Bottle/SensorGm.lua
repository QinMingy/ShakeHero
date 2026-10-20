-- GM体感调参区；只控制摇晃惯性的传感器倍率，不接管手指拖动。
local UI = require("urhox-libs/UI")
local Audio = require("Bottle.Audio")
local Tuning = require("Bottle.SensorTuning")
local Overlay = require("Machine.DeveloperOverlay")
local Gm = {}

function Gm.Add(panel, view)
    local colors = require("Bottle.Theme").colors
    local section = UI.Panel {id = "gmSensorTuning", width = "100%", gap = 6, flexShrink = 0}
    local valueLabel = UI.Label {id = "gmSensorGainValue", text = "", fontSize = 14,
        fontColor = colors.primary, textMotionDisabled = true}
    local function current() return view.physics.motion.sensorGain end
    local function updateLabel()
        valueLabel:SetText(string.format("陀螺仪系数  %.2f×", current()))
    end
    ---@type Slider?
    local slider = nil
    local syncing = false
    local function syncGain()
        updateLabel()
        if slider then
            syncing = true
            slider:SetValue(current())
            syncing = false
        end
    end
    local function apply(value, persist)
        if not Overlay.IsAllowed(view) then return end
        if not view.actions.sensorGain(value, persist) then return end
        syncGain()
    end
    local function button(id, text, onClick)
        return Audio.Button {id = id, text = text, onClick = onClick, height = 38,
            fontSize = 12, textMotionDisabled = true, flexGrow = 1, flexBasis = 0, padding = 0}
    end
    slider = UI.Slider {id = "gmSensorGain", min = Tuning.MIN, max = Tuning.MAX,
        step = Tuning.STEP, value = current(), height = 40, thumbSize = 24,
        flexGrow = 1, flexBasis = 0,
        onChange = function(_, value) if not syncing then apply(value, false) end end,
        onChangeEnd = function(_, value) if not syncing then apply(value, true) end end}
    local less = button("gmSensorLess", "−", function() apply(current() - Tuning.STEP, true) end)
    local more = button("gmSensorMore", "+", function() apply(current() + Tuning.STEP, true) end)
    less:SetStyle({flexGrow = 0, flexBasis = "auto", width = 42})
    more:SetStyle({flexGrow = 0, flexBasis = "auto", width = 42})
    section:AddChild(valueLabel)
    section:AddChild(UI.Panel {width = "100%", flexDirection = "row", alignItems = "center",
        gap = 8, children = {less, slider, more}})
    local presets = UI.Panel {width = "100%", flexDirection = "row", gap = 6}
    for _, value in ipairs({1, 2, 6, 8, 16}) do
        presets:AddChild(button("gmSensorPreset" .. value, value .. "×", function() apply(value, true) end))
    end
    section:AddChild(presets)
    section:AddChild(UI.Label {text = "1×为原强度，范围0.25–20×，仅影响体感；即时生效，松手保存。",
        width = "100%", fontSize = 10.5, fontColor = colors.textSecondary, whiteSpace = "normal"})
    local labLabel = UI.Label {id = "gmSensorLabState", text = "", fontSize = 11.25,
        fontColor = colors.textSecondary, textMotionDisabled = true,
        whiteSpace = "normal", flexGrow = 1, flexBasis = 0}
    local labToggle = button("gmSensorLabToggle", "启用 Wi-Fi 体感", function()
        if not Overlay.IsAllowed(view) then return end
        if type(view.actions.sensorLab) ~= "function" then return end
        local info = view.sensorLabState or {enabled = false}
        view.actions.sensorLab(not info.enabled)
    end)
    labToggle:SetStyle({width = 136, flexGrow = 0, flexBasis = "auto", flexShrink = 0})
    section:AddChild(UI.Panel {id = "gmSensorLab", width = "100%", gap = 5,
        paddingTop = 5, children = {
            UI.Panel {width = "100%", flexDirection = "row", alignItems = "center", gap = 8,
                children = {labLabel, labToggle}},
            UI.Label {id = "gmSensorLabHint", text = "先运行 dev/sensor-lab/start-wifi.cmd，手机与电脑连同一 Wi-Fi，扫码并启用传感器即可摇晃瓶子。",
                width = "100%", fontSize = 10.5, fontColor = colors.textSecondary,
                whiteSpace = "normal", textMotionDisabled = true},
        }})
    local function syncLab()
        local info = view.sensorLabState or {enabled = false, status = "disabled"}
        local labels = {
            disabled = "Wi-Fi 体感：已停用",
            missing = "Wi-Fi 体感：实验台未配置",
            waiting = "Wi-Fi 体感：等待手机数据",
            online = "Wi-Fi 体感：已接通手机",
            stale = "Wi-Fi 体感：数据已中断",
        }
        local text = labels[info.status] or "Wi-Fi 体感：等待连接"
        if type(info.error) == "string" and info.error ~= "" then text = text .. "\n" .. info.error end
        labLabel:SetText(text)
        labLabel:SetFontColor(info.available and colors.success or colors.textSecondary)
        labToggle:SetText(info.enabled and "停用 Wi-Fi 体感" or "启用 Wi-Fi 体感")
        labToggle:SetDisabled(type(view.actions.sensorLab) ~= "function")
    end
    view.RefreshSensorGm = function()
        if not Overlay.IsAllowed(view) or not view.modalDeveloperUi or not view.modal:IsVisible() then return end
        -- Other modal pages destroy this GM subtree; never update its old controls.
        if view.modal:FindById("gmSensorTuning") ~= section then return end
        syncGain()
        syncLab()
    end
    syncGain()
    syncLab()
    panel:AddChild(section)
end

return Gm
