"""Offline art/timing preview sampled from the production Lua timeline.

This is a flat sprite composition, not a capture of the lit Maker runtime.
Run with the project's existing Pillow and .tmp/lua-check/lupa installation.
"""
import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / '.tmp/lua-check'))
from lupa.lua54 import LuaRuntime

OUT = ROOT / 'outputs/target-swap'
ASSETS = ROOT / 'assets/image/machine-layered'
S = 2
SIZE = (402 * S, 220 * S)
INK = (226, 214, 174, 255)


def tiled(canvas, source, rect):
    x, y, w, h = (round(v * S) for v in rect)
    tile = source.resize((source.width * S, source.height * S), Image.Resampling.NEAREST)
    patch = Image.new('RGBA', (w, h))
    for yy in range(0, h, tile.height):
        for xx in range(0, w, tile.width):
            patch.alpha_composite(tile, (xx, yy))
    canvas.alpha_composite(patch, (x, y))


def panel(kind, w, h):
    source = Image.open(ASSETS / f'{kind}.png').convert('RGBA')
    image = Image.new('RGBA', (w * S, h * S))
    xs, ys = [0, 12, source.width - 12, source.width], [0, 12, source.height - 12, source.height]
    dx, dy = [0, 12, w - 12, w], [0, 12, h - 12, h]
    for row in range(3):
        for col in range(3):
            tile = source.crop((xs[col], ys[row], xs[col + 1], ys[row + 1]))
            tiled(image, tile, (dx[col], dy[row], dx[col + 1] - dx[col], dy[row + 1] - dy[row]))
    return image


def text(image, value, rect, size, color=INK):
    font = ImageFont.truetype(str(ROOT / 'assets/Fonts/SmileySans-Oblique.ttf'), round(size * S))
    x, y, w, h = rect
    draw = ImageDraw.Draw(image)
    draw.text(((x + w / 2) * S, (y + h / 2) * S), str(value), font=font, fill=color, anchor='mm')


def placed(image, pivot, dest, angle):
    c, s = math.cos(angle), math.sin(angle)
    px, py = dest[0] * S, dest[1] * S
    return image.transform(SIZE, Image.Transform.AFFINE,
                           (c, s, pivot[0] - c * px - s * py,
                            -s, c, pivot[1] + s * px - c * py),
                           Image.Resampling.NEAREST)


def background():
    image = Image.new('RGBA', SIZE, (18, 22, 19, 255))
    tiled(image, Image.open(ASSETS / 'desk.png').convert('RGBA'), (0, 0, 402, 220))
    for kind, x, y, w, h in [('wood', 12, 26, 168, 68), ('metal', 42, 144, 218, 48),
                             ('metal', 32, 74, 292, 78), ('metal', 42, 158, 226, 26)]:
        image.alpha_composite(panel(kind, w, h), (x * S, y * S))
    text(image, '回合 1/5', (44, 34, 132, 32), 20)
    glyphs = {'0': [14, 17, 19, 21, 25, 17, 14], '1': [4, 12, 4, 4, 4, 4, 14],
              '2': [14, 17, 1, 2, 4, 8, 31]}
    draw = ImageDraw.Draw(image)
    for index, char in enumerate('00000120'):
        x, y = 48 + index * 32.5, 92
        draw.rectangle((int(x * S), y * S, int((x + 30.5) * S) - 1, (y + 40) * S - 1), fill=(11, 19, 16, 255))
        for row, bits in enumerate(glyphs[char]):
            for col in range(5):
                if bits & (1 << (4 - col)):
                    xx, yy = round((x + 5 + col * 4) * S), (98 + row * 4) * S
                    draw.rectangle((xx, yy, xx + 4 * S - 1, yy + 4 * S - 1), fill=INK)
    for i in range(21):
        x = (50 + i * 10) * S
        draw.rectangle((x, 165 * S, x + 7 * S - 1, 177 * S - 1), fill=(54, 61, 46, 255))
    housing = Image.open(ASSETS / 'crt-housing.png').convert('RGBA').resize((402 * S, 500 * S), Image.Resampling.NEAREST)
    image.alpha_composite(housing, (0, 178 * S))
    return image


def frame(pose):
    image = background()
    if pose['visible']:
        plaque = panel('wood', 132, 54)
        text(plaque, '目标', (12, 14, 44, 26), 16)
        text(plaque, pose['value'], (58, 12, 62, 30), 22)
        layer = placed(plaque, (66 * S, 27 * S), (324 + pose['x'], 157 + pose['y']), pose['angle'])
    if pose['arm']:
        sprite = Image.open(ASSETS / ('target-arm-grip.png' if pose['grip'] else 'target-arm-open.png')).convert('RGBA')
        sprite = sprite.resize((160 * S, 80 * S), Image.Resampling.NEAREST)
        c, s = math.cos(pose['angle']), math.sin(pose['angle'])
        x = 324 + c * 18 + s * 15 + pose['x'] + pose['armX']
        y = 157 + s * 18 - c * 15 + pose['y'] + pose['armY']
        image.alpha_composite(placed(sprite, (25 * S, 36 * S), (x, y), -.70 + pose['angle']))
    # Runtime depth puts the hand behind the plaque, including its rim.
    if pose['visible']:
        image.alpha_composite(layer)
    return image.convert('RGB')


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("package.path='scripts/?.lua;'..package.path")
    lua.execute("game={target=40}; swap=require('Machine.TargetSwapState').New(game);game.target=80;swap:Sync(game)")
    pose_at = lua.eval('function(t) swap.elapsed=t;swap.active=t<swap.duration;swap.shown=swap.active and 40 or 80;return swap:Pose() end')
    frames = [frame(pose_at(0))] * 12
    frames += [frame(pose_at(i / 30)) for i in range(83)]
    frames += [frame(pose_at(3))] * 24
    frames[0].save(OUT / 'target-swap-preview.gif', save_all=True, append_images=frames[1:],
                   duration=33, loop=0, disposal=2, optimize=False)
    times = [0, .56, .82, 1.23, 1.67, 2.04]
    sheet = Image.new('RGB', (SIZE[0] * 3, SIZE[1] * 2))
    for index, t in enumerate(times):
        sheet.paste(frame(pose_at(t)), ((index % 3) * SIZE[0], (index // 3) * SIZE[1]))
    sheet.save(OUT / 'contact-sheet.png')
    print(OUT / 'target-swap-preview.gif')


if __name__ == '__main__':
    main()
