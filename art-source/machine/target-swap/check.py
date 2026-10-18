"""Offline Lua 5.4 checks and native pixel-art contracts; no preview or save writes."""
import json
import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.tmp/lua-check'))
from lupa.lua54 import LuaRuntime, lua_type

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path")


def to_python(value):
    if lua_type(value) != 'table':
        return value
    keys = list(value.keys())
    if keys and set(keys) == set(range(1, len(keys) + 1)):
        return [to_python(value[i]) for i in range(1, len(keys) + 1)]
    return {str(k): to_python(value[k]) for k in keys}


def to_lua(value):
    if isinstance(value, dict):
        return lua.table_from({k: to_lua(v) for k, v in value.items()})
    if isinstance(value, list):
        return lua.table_from([to_lua(v) for v in value])
    return value


# Engine cjson is unavailable outside UrhoX; exercise a real JSON roundtrip
# through Python at that boundary, including the existing save/repair tests.
lua.globals().json_encode = lambda value: json.dumps(to_python(value), ensure_ascii=False, allow_nan=False)
lua.globals().json_decode = lambda value: to_lua(json.loads(value))
lua.execute('cjson={encode=function(v)return json_encode(v)end,decode=function(v)return json_decode(v)end}')
syntax = lua.eval('function(s,n) local f,e=load(s,n);return f~=nil,e end')
files = list((ROOT / 'scripts').rglob('*.lua'))
for path in files:
    ok, error = syntax(path.read_text(encoding='utf-8-sig'), str(path))
    assert ok, error

rules, json_roundtrip = lua.execute("local T=require('Bottle.Tests');return T.Run(),T.jsonRoundtripRan")
gesture = lua.execute("return dofile('art-source/machine/target-swap/checks.lua').Run()")
assets = []
for name in ['open', 'grip']:
    image = Image.open(ROOT / f'assets/image/machine-layered/target-arm-{name}.png')
    assert image.size == (160, 80) and image.mode == 'RGBA'
    assert set(image.getchannel('A').tobytes()) == {0, 255}, 'soft alpha would blur the outline'
    # The user's requested overlap is hidden by the opaque plaque in front.
    # Only unoccluded hand pixels may be compared with the UI text rectangles.
    hits = 0
    contact = 0
    occluded = 0
    for y in range(image.height):
        for x in range(image.width):
            if not image.getpixel((x, y))[3]:
                continue
            c, s = math.cos(-.70), math.sin(-.70)
            xx = 342 + c * (x - 25) - s * (y - 36)
            yy = 142 + s * (x - 25) + c * (y - 36)
            behind_plate = 270 <= xx < 378 and 130 <= yy < 184
            occluded += int(behind_plate)
            if not behind_plate:
                hits += int(316 <= xx < 378 and 142 <= yy < 172)
                hits += int(270 <= xx < 314 and 144 <= yy < 170)
            contact += int(258 <= xx < 390 and 130 <= yy < 142)
    assert hits == 0, 'hand overlaps UI label pixels'
    assert contact > 20, 'fingers must visibly hold the plaque top edge'
    assert occluded > 20, 'plaque must overlap the fingers to show a grip'
    assets.append({'pose': name, 'label_overlap_pixels': hits, 'edge_contact_pixels': contact,
                   'fingers_behind_plaque_pixels': occluded})

result = {'lua_version': lua.eval('_VERSION'), 'lua_syntax_files': len(files),
          'game_rule_checks': rules, 'json_roundtrip_executed': json_roundtrip,
          'target_swap_checks': gesture, 'sprites': assets,
          'runtime_visual_verification': 'PENDING: existing preview is stopped'}
out = ROOT / 'outputs/target-swap'
out.mkdir(parents=True, exist_ok=True)
(out / 'checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
