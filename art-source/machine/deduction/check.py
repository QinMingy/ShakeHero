"""Offline Lua 5.4 payment, timeline and production draw-call checks.

Never starts a preview or reads/writes player saves. PNGs rasterize the actual
NanoVG rectangle trace; they are isolated offline previews, not game screenshots.
"""
import json
import os
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'outputs/deduction'
sys.path.insert(0, str(ROOT / '.tmp/lua-check'))
from lupa.lua54 import LuaRuntime, lua_type

os.chdir(ROOT)
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


lua.globals().json_encode = lambda value: json.dumps(to_python(value), ensure_ascii=False, allow_nan=False)
lua.globals().json_decode = lambda value: to_lua(json.loads(value))
lua.execute('cjson={encode=function(v)return json_encode(v)end,decode=function(v)return json_decode(v)end}')
syntax = lua.eval('function(s,n) local f,e=load(s,n);return f~=nil,e end')
files = sorted((ROOT / 'scripts').rglob('*.lua'))
for path in files:
    ok, error = syntax(path.read_text(encoding='utf-8-sig'), str(path))
    assert ok, error

rules, json_roundtrip = lua.execute("local T=require('Bottle.Tests');return T.Run(),T.jsonRoundtripRan")
checks = lua.execute("return dofile('art-source/machine/deduction/checks.lua')")
count, names = checks.Run()
OUT.mkdir(parents=True, exist_ok=True)


def rasterize(trace):
    """Replay the production rectangles with a hard clip and nearest pixel fill."""
    canvas = Image.new('RGBA', (402, 100), (0, 0, 0, 0))
    if not trace['rects']:
        return canvas
    translate, scale = trace['translation'], trace['scale']
    for rect in trace['rects']:
        layer = Image.new('RGBA', canvas.size)
        draw = ImageDraw.Draw(layer)
        x = translate['x'] + rect['x'] * scale['x']
        y = translate['y'] + rect['y'] * scale['y']
        width, height = rect['w'] * scale['x'], rect['h'] * scale['y']
        color = tuple(rect['color'][:3]) + (round(rect['color'][3] * rect['alpha']),)
        # The native shape anti-alias flag is disabled; rasterize by pixel center.
        left, top = round(x), round(y)
        right, bottom = round(x + width) - 1, round(y + height) - 1
        draw.rectangle((left, top, right, bottom), fill=color)
        clip = trace['clip']
        clipped = Image.new('RGBA', canvas.size)
        box = (max(0, round(clip['x'])), max(0, round(clip['y'])),
               min(canvas.width, round(clip['x'] + clip['w'])),
               min(canvas.height, round(clip['y'] + clip['h'])))
        clipped.paste(layer.crop(box), box[:2])
        canvas = Image.alpha_composite(canvas, clipped)
    return canvas


traces = {}
for name, elapsed in [('rise', .35), ('hold', .7), ('fall', 7.0)]:
    trace = to_python(checks.Capture(40, elapsed))
    traces[name] = trace
    image = rasterize(trace)
    image.save(OUT / f'offline-note-{name}.png')
    # Largest native dimensions are retained as a separate nearest-neighbor view.
    if name == 'hold':
        left = round(trace['translation']['x']) - 8
        image.crop((left, 10, left + 132, 76)).resize((528, 264), Image.Resampling.NEAREST).save(
            OUT / 'offline-note-hold-4x.png')

hold = rasterize(traces['hold'])
pixels = hold.load()
red_pixels = sum(1 for y in range(hold.height) for x in range(hold.width)
                 if pixels[x, y][3] and pixels[x, y][0] > 200
                 and pixels[x, y][1] < 70 and pixels[x, y][2] < 70)
assert red_pixels > 200, 'production trace did not render readable red warning digits'
assert hold.getbbox()[3] <= 75, 'receipt renders across the balance reel upper boundary'

result = {
    'lua_version': lua.eval('_VERSION'),
    'lua_syntax_files': len(files),
    'game_rule_checks': rules,
    'json_roundtrip_executed': json_roundtrip,
    'deduction_contract_checks': count,
    'deduction_contract_cases': to_python(names),
    'production_draw_trace_red_pixels': red_pixels,
    'offline_draw_trace_pngs': [f'offline-note-{name}.png' for name in traces],
    'runtime_visual_verification': 'UNDETERMINED: existing preview is stopped; no preview was started',
    'offline_preview_scope': 'Exact production NanoVG rectangles; excludes native lighting, camera and full UI overlap',
}
(OUT / 'draw-traces.json').write_text(json.dumps(traces, ensure_ascii=False, indent=2), encoding='utf-8')
(OUT / 'checks.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
