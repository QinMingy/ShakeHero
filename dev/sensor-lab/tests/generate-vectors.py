"""Read live game Lua via Lua 5.4 and emit standalone lab parity vectors.

No game files are changed. Run: python dev/sensor-lab/tests/generate-vectors.py
"""
from __future__ import annotations

import json
import math
from pathlib import Path

from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parents[1] / ".local" / "oracle-vectors.json"
OUT.parent.mkdir(exist_ok=True)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path = " + json.dumps(str(ROOT / "scripts" / "?.lua").replace("\\", "/")) + " .. ';' .. package.path")
Motion, _ = lua.eval('require("Bottle.ShakeMotion")')
FIELDS = (
    "targetX", "targetY", "x", "y", "vx", "vy", "holding",
    "sensorBaseX", "sensorBaseY", "sensorX", "sensorY", "sensorReady",
    "sensorHolding", "sensorGain",
)


def encoded(value):
    if isinstance(value, float) and not math.isfinite(value):
        return {"special": "nan" if math.isnan(value) else "infinity" if value > 0 else "-infinity"}
    return value


def make_case(name, actions):
    motion = Motion.New()
    records = []
    for op, *args in actions:
        if op == "sample":
            dx, dy = motion.Sensor(motion, *args)
            motion.Move(motion, dx, dy)
            ix, iy = motion.Step(motion, args[2])
            result = [dx, dy, ix, iy]
        else:
            method = {
                "sensor": "Sensor", "step": "Step", "move": "Move", "begin": "Begin",
                "end": "End", "reset": "Reset", "resetSensor": "ResetSensor", "setGain": "SetSensorGain",
            }[op]
            result = motion[method](motion, *args)
            result = list(result) if isinstance(result, tuple) else result
        records.append({"op": op, "args": [encoded(a) for a in args], "returns": result,
                        "state": {key: motion[key] for key in FIELDS}})
    return {"name": name, "actions": records}


dt = 1 / 60
cases = [
    make_case("baseline-pulse-4x", [
        ("sensor", .2, -.4, dt), ("sensor", .8, -.4, dt),
        ("move", .52, 0), ("step", dt), ("resetSensor",), ("step", dt),
    ]),
    make_case("sustained-input-adapts-and-centers", [
        ("sample", .2, -.4, dt),
        *[("sample", .8, -.4, dt) for _ in range(300)],
    ]),
    make_case("gain-1x-linear-range", [("setGain", 1), ("sample", 0, 0, dt), ("sample", .2, .1, dt)]),
    make_case("gain-4x-linear-range", [("setGain", 4), ("sample", 0, 0, dt), ("sample", .2, .1, dt)]),
    make_case("gain-quantization", [("setGain", v) for v in [-100, 0, .25, .374999, .375, 4.124999, 4.125, 19.999, 100, float("nan"), float("inf"), -float("inf")]]),
    make_case("radial-deadzone-and-axis-saturation", [
        ("sample", .2, -.4, dt),
        *[("sample", .2 + .01 * math.sin(i), -.4, dt) for i in range(1, 121)],
        ("sample", 1e6, -1e6, dt), ("reset",), ("sample", 0, 0, dt), ("sample", .07, .07, dt),
    ]),
    make_case("touch-takes-priority-and-sensor-recalibrates", [
        ("sample", 0, 0, dt), ("sample", .8, -.3, dt), ("begin",), ("move", .1, .1),
        ("sensor", -1, 1, dt), ("move", 0, 0), ("step", dt), ("resetSensor",),
        ("end",), ("sample", .7, -.4, dt), ("sample", .9, -.1, dt),
    ]),
    make_case("pause-boundary", [
        ("sample", 0, 0, dt), ("sample", .2, .1, .15),
        ("sample", -.2, -.1, .150000001), ("sample", .2, .1, dt),
    ]),
    make_case("nonfinite-does-not-change-state", [
        ("sample", 0, 0, dt), ("sample", .2, .1, dt),
        *[(op, *args) for value in [float("nan"), float("inf"), -float("inf")]
          for op, args in [("sensor", (value, 1, dt)), ("sensor", (1, value, dt)),
                           ("sensor", (1, 1, value)), ("move", (value, 1)),
                           ("move", (1, value)), ("step", (value,))]],
        ("sensor", 1, 1, 0), ("sensor", 1, 1, -dt), ("step", 0), ("step", -dt),
    ]),
    make_case("waveform-and-return-to-center", [
        *[("sample", .2 + .7 * math.sin(i / 8), -.4 + .5 * math.sin(i / 11), dt) for i in range(1, 361)],
        ("resetSensor",), *[("step", dt) for _ in range(120)],
    ]),
]
payload = {
    "source": "scripts/Bottle/ShakeMotion.lua + scripts/Bottle/SensorTuning.lua (direct Lua 5.4 oracle)",
    "absoluteTolerance": 1e-10,
    "sampleContract": "Sensor(ax,ay,dt) -> (dx,dy); Move(dx,dy); Step(dt) -> (impulseX,impulseY)",
    "sampleReturnOrder": ["dragDx", "dragDy", "inertiaDvx", "inertiaDvy"],
    "cases": cases,
}
OUT.write_text(json.dumps(payload, ensure_ascii=False, indent=2, allow_nan=False), encoding="utf-8")
print(f"{OUT}: {len(cases)} cases, {sum(len(c['actions']) for c in cases)} operation snapshots")
for case in cases[:4]:
    print(case["name"], json.dumps(case["actions"][-1], ensure_ascii=False, separators=(",", ":")))
