-- Lighting moods for one fixed cabinet. Game state and material identity stay put.
local Atmosphere = {}

Atmosphere.order = {"auto", "brass", "slate", "ember"}
Atmosphere.names = {auto = "默认", brass = "暖灯", slate = "冷夜", ember = "余烬"}
Atmosphere.styles = {
    brass = {
        ambient = {0.21, 0.205, 0.18}, key = {1, 0.88, 0.66},
        lamp = {1, 0.86, 0.62}, cool = {0.48, 0.72, 0.78}, bounce = {1, 0.58, 0.30},
        keyPower = 2.2, lampPower = 12, coolPower = 8, bouncePower = 3.7,
        beacon = {0.28, 0.59, 0.60}, screenGlow = {0.18, 0.10, 0.04, 0.22},
        bodyTint = {1.0, 0.98, 0.91},
    },
    slate = {
        ambient = {0.17, 0.195, 0.205}, key = {0.76, 0.86, 0.94},
        lamp = {0.66, 0.82, 0.92}, cool = {0.42, 0.72, 0.86}, bounce = {0.98, 0.62, 0.37},
        keyPower = 1.85, lampPower = 9, coolPower = 12, bouncePower = 2.8,
        beacon = {0.42, 0.72, 0.82}, screenGlow = {0.05, 0.16, 0.23, 0.34},
        bodyTint = {0.86, 0.96, 1.0},
    },
    ember = {
        ambient = {0.22, 0.18, 0.16}, key = {1, 0.82, 0.68},
        lamp = {1, 0.71, 0.51}, cool = {0.55, 0.66, 0.70}, bounce = {1, 0.38, 0.23},
        keyPower = 2.05, lampPower = 10, coolPower = 4, bouncePower = 6.2,
        beacon = {0.86, 0.37, 0.18}, screenGlow = {0.23, 0.07, 0.035, 0.32},
        bodyTint = {1.0, 0.90, 0.80},
    },
}

function Atmosphere.Valid(mode)
    return mode == "auto" or Atmosphere.styles[mode] ~= nil
end

-- No enemy/environment state yet; auto keeps the authored default.
function Atmosphere.Resolve(mode)
    return mode ~= "auto" and Atmosphere.styles[mode] and mode or "brass"
end

return Atmosphere
