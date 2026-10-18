"""Render production DeductionNote.Draw with a tiny rectangle-only NVG adapter.

Offline pixel/timing evidence; this is not a Maker runtime screenshot.
"""
import copy
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.tmp/lua-check'))
from lupa.lua54 import LuaRuntime

OUT = ROOT / 'outputs/deduction'
S = 3
SIZE = (402 * S, 156 * S)
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("package.path='scripts/?.lua;'..package.path;package.loaded['urhox-libs/UI']={}")
note = lua.execute("return require('Machine.DeductionNote').New()")
state = {}
stack = []
pending = []
canvas = None


def save(_):
    stack.append(copy.deepcopy(state))


def restore(_):
    state.clear()
    state.update(stack.pop())


def translate(_, x, y):
    state['x'] += x * state['sx']
    state['y'] += y * state['sy']


def scale(_, x, y):
    state['sx'] *= x
    state['sy'] *= y


def rectangle(_, x, y, w, h):
    pending.append((state['x'] + x * state['sx'], state['y'] + y * state['sy'],
                    state['x'] + (x + w) * state['sx'], state['y'] + (y + h) * state['sy']))


def fill(_):
    layer = Image.new('RGBA', SIZE)
    draw = ImageDraw.Draw(layer)
    clip = state['clip']
    color = tuple(state['color'][:3]) + (round(state['color'][3] * state['alpha']),)
    for box in pending:
        x0, y0 = max(box[0], clip[0]), max(box[1], clip[1])
        x1, y1 = min(box[2], clip[2]), min(box[3], clip[3])
        if x1 > x0 and y1 > y0:
            pixels = (round(x0*S), round(y0*S), round(x1*S)-1, round(y1*S)-1)
            if pixels[2] >= pixels[0] and pixels[3] >= pixels[1]:
                draw.rectangle(pixels, fill=color)
    canvas.alpha_composite(layer)


def scissor(_, x, y, w, h):
    old = state['clip']
    state['clip'] = (max(old[0], x), max(old[1], y), min(old[2], x + w), min(old[3], y + h))


lua.globals().nvgSave = save
lua.globals().nvgRestore = restore
lua.globals().nvgIntersectScissor = scissor
lua.globals().nvgTranslate = translate
lua.globals().nvgScale = scale
lua.globals().nvgShapeAntiAlias = lambda *_: None
lua.globals().nvgGlobalAlpha = lambda _, a: state.update(alpha=a)
lua.globals().nvgBeginPath = lambda _: pending.clear()
lua.globals().nvgRect = rectangle
lua.globals().nvgRGBA = lambda *c: lua.table_from(c)
lua.globals().nvgFillColor = lambda _, c: state.update(color=[c[i] for i in range(1, 5)])
lua.globals().nvgFill = fill


def frame(t, amount=40):
    global canvas
    canvas = Image.new('RGBA', SIZE, (27, 34, 29, 255))
    state.clear()
    state.update(x=0, y=0, sx=1, sy=1, alpha=1, clip=(0, 0, 402, 156), color=(0, 0, 0, 0))
    stack.clear()
    # A schematic balance display marks the production reel's exact rectangle.
    draw = ImageDraw.Draw(canvas)
    draw.rectangle((32*S, 74*S, 324*S-1, 152*S-1), fill=(74, 86, 76, 255))
    draw.rectangle((36*S, 78*S, 320*S-1, 148*S-1), fill=(35, 47, 40, 255))
    glyphs = {'0': [14,17,19,21,25,17,14], '1': [4,12,4,4,4,4,14],
              '4': [2,6,10,18,31,2,2]}
    for index, char in enumerate('00000140'):
        x = 48 + index * 32.5
        draw.rectangle((round(x*S), 92*S, round((x+30.5)*S)-1, 132*S-1), fill=(11,19,16,255))
        for row, bits in enumerate(glyphs[char]):
            for col in range(5):
                if bits & (1 << (4-col)):
                    xx, yy = round((x+5+col*4)*S), (98+row*4)*S
                    draw.rectangle((xx,yy,xx+4*S-1,yy+4*S-1), fill=(226,214,174,255))
    note.Show(note, amount)
    note.Tick(note, t)
    note.Draw(note, None, lua.table_from({'x':0,'y':0,'w':402,'h':156}), 1)
    return canvas.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    frame(1).save(OUT / 'deduction-note.png')
    times = [.25, .7, 5.7, 6.6, 7.6, 8.3]
    sheet = Image.new('RGB', (SIZE[0]*2, (SIZE[1]+28)*3), (18,22,19))
    draw = ImageDraw.Draw(sheet)
    for i, t in enumerate(times):
        x, y = (i%2)*SIZE[0], (i//2)*(SIZE[1]+28)
        sheet.paste(frame(t), (x,y+28))
        draw.text((x+10,y+8), f'{t:.2f} s - production Lua drawing / schematic reels', fill='white')
    sheet.save(OUT / 'contact-sheet.png')
    frames = [frame(i/12) for i in range(math.ceil(8.3*12)+1)]
    frames[0].save(OUT / 'deduction-preview.gif',save_all=True,append_images=frames[1:],
                   duration=83,loop=0,optimize=False)
    print(OUT / 'contact-sheet.png')


if __name__ == '__main__':
    main()
