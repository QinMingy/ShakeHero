"""Paint two original pixel-art cabinet layers at the fixed 420x840 layout.

The live CRT, counters and moving buttons remain separate geometry.
Run: python art-source/machine/paint_body.py
"""
from pathlib import Path
import random
import struct
import zlib

W, H = 420, 840
OUT = Path(__file__).resolve().parents[2] / "assets/image"
RNG = random.Random(211047)
pixels = bytearray(W * H * 4)

INK = (5, 12, 12, 255)
SHADOW = (10, 19, 18, 255)
RECESS = (17, 29, 27, 255)
STEEL = (37, 53, 48, 255)
STEEL_TOP = (46, 60, 54, 255)
STEEL_LOW = (35, 49, 45, 255)
EDGE = (95, 105, 85, 255)
COOL_GLINT = (139, 145, 111, 255)
BRASS = (167, 132, 77, 255)


def put(x, y, color):
    if 0 <= x < W and 0 <= y < H:
        at = (y * W + x) * 4
        pixels[at:at + 4] = bytes(color)


def rect(x, y, w, h, color):
    for yy in range(max(0, int(y)), min(H, int(y + h))):
        for xx in range(max(0, int(x)), min(W, int(x + w))):
            put(xx, yy, color)


def line(x0, y0, x1, y1, color, width=1):
    x0, y0, x1, y1 = map(int, (x0, y0, x1, y1))
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = 1 if x0 < x1 else -1, 1 if y0 < y1 else -1
    err = dx + dy
    while True:
        rect(x0, y0, width, width, color)
        if x0 == x1 and y0 == y1:
            break
        twice = 2 * err
        if twice >= dy:
            err += dy
            x0 += sx
        if twice <= dx:
            err += dx
            y0 += sy


def stepped(x, y, w, h, color, cut=4):
    rect(x + cut, y, w - cut * 2, h, color)
    rect(x, y + cut, w, h - cut * 2, color)
    rect(x + cut // 2, y + cut // 2, w - cut, h - cut, color)


def panel(x, y, w, h, fill=STEEL, cut=4):
    """Five flat pixel values supply authored depth, not a PBR bevel."""
    stepped(x + 4, y + 5, w, h, INK, cut)
    stepped(x, y, w, h, SHADOW, cut)
    stepped(x + 2, y + 2, w - 5, h - 5, EDGE, cut)
    stepped(x + 4, y + 4, w - 9, h - 9, fill, cut)
    line(x + cut + 3, y + 3, x + w - cut - 4, y + 3, COOL_GLINT)
    line(x + 3, y + cut + 3, x + 3, y + h - cut - 5, EDGE)
    line(x + cut + 4, y + h - 4, x + w - cut - 3, y + h - 4, INK, 2)
    line(x + w - 4, y + cut + 3, x + w - 4, y + h - cut - 4, INK, 2)


def well(x, y, w, h):
    panel(x, y, w, h, RECESS)
    stepped(x + 8, y + 8, w - 17, h - 17, SHADOW, 3)
    rect(x + 9, y + 9, w - 19, 2, (58, 74, 62, 255))
    rect(x + 9, y + h - 13, w - 19, 3, INK)


def bolt(x, y):
    rect(x - 5, y - 4, 11, 10, INK)
    rect(x - 4, y - 4, 8, 7, (71, 81, 67, 255))
    rect(x - 2, y - 2, 4, 4, (20, 31, 27, 255))
    put(x - 4, y - 4, BRASS)
    line(x - 1, y + 1, x + 2, y - 1, INK)


def png_bytes():
    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data +
                struct.pack(">I", zlib.crc32(kind + data) & 0xffffffff))
    scanlines = b"".join(b"\x00" + pixels[y * W * 4:(y + 1) * W * 4]
                         for y in range(H))
    return (b"\x89PNG\r\n\x1a\n" +
            chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)) +
            chunk(b"IDAT", zlib.compress(scanlines, 9)) + chunk(b"IEND", b""))


# Stepped base silhouette and three differently inked sheet-metal panels.
stepped(8, 12, 405, 814, INK, 7)
stepped(12, 9, 396, 807, SHADOW, 6)
stepped(17, 15, 386, 793, STEEL, 5)
rect(20, 18, 380, 177, STEEL_TOP)
rect(20, 196, 380, 474, STEEL)
rect(20, 672, 380, 132, STEEL_LOW)


def on_metal(x, y):
    if 34 < x < 387 and 208 < y < 663:
        return False
    if 35 < x < 389 and 78 < y < 158:
        return False
    if 30 < x < 393 and 674 < y < 745:
        return False
    return 19 < x < 400 and 17 < y < 805


# Clustered patina, confined to metal. It holds up at phone size and does not
# create floating particles or additional triangles.
for _ in range(11800):
    x, y = RNG.randrange(20, 400), RNG.randrange(18, 805)
    if not on_metal(x, y):
        continue
    lamp = (1 - x / W) * (1 - .55 * y / H)
    n = RNG.random()
    color = ((83, 93, 75, 255) if n > .88 and lamp > .38 else
             (65, 78, 65, 255) if n > .72 else
             (19, 34, 30, 255) if n < .26 else (40, 58, 50, 255))
    rect(x, y, 3 if n > .94 else 2, 2 if n < .94 else 3, color)
for _ in range(210):
    x = RNG.randrange(24, 396)
    y = RNG.choice((RNG.randrange(24, 69), RNG.randrange(677, 803)))
    rect(x, y, RNG.randrange(4, 15), 2,
         RNG.choice(((23, 38, 34, 255), (75, 88, 70, 255))))

# Asymmetric mechanical blocks. The dark wells remain behind live readouts.
panel(28, 24, 239, 42, (35, 50, 45, 255))
for x in range(45, 251, 15):
    rect(x, 41, 8, 3, SHADOW)
    rect(x + 1, 40, 6, 1, (84, 96, 79, 255))
well(29, 72, 179, 89)
well(211, 72, 179, 89)
panel(27, 164, 366, 31, (28, 42, 38, 255))
well(26, 198, 368, 476)
well(28, 669, 157, 46)
well(188, 669, 204, 46)
panel(26, 716, 367, 29, (35, 49, 44, 255))
panel(22, 747, 152, 72, (47, 52, 40, 255))
panel(176, 747, 220, 72, (43, 51, 42, 255))

# Sparse printed marks create graphic rhythm without adding static text.
for y in (170, 186, 724, 737):
    for x in range(39, 379, 11):
        if RNG.random() > .22:
            rect(x, y, 5, 1, (72, 91, 72, 255))
for x in (23, 394):
    for y in range(208, 657, 19):
        rect(x, y, 3, 9, SHADOW)
        rect(x, y + 1, 1, 5, (92, 104, 79, 255))

# Deep returns and deliberately broken warm edge glints.
rect(13, 22, 3, 785, (13, 27, 25, 255))
rect(17, 22, 2, 778, EDGE)
rect(21, 15, 372, 3, EDGE)
rect(399, 25, 3, 778, INK)
rect(396, 29, 2, 768, SHADOW)
rect(24, 802, 373, 4, INK)
for y in range(29, 795, 23):
    if RNG.random() > .24:
        rect(18, y, 1, RNG.randrange(4, 11), BRASS)
    if RNG.random() > .52:
        rect(395, y + 3, 1, RNG.randrange(2, 8), (72, 88, 70, 255))

OUT.mkdir(parents=True, exist_ok=True)
(OUT / "machine-body-2d.png").write_bytes(png_bytes())

# The ink plate sits 9 cm in front. Only frame lines and fasteners are opaque;
# the live CRT, counters, labels and button caps show through its apertures.
pixels = bytearray(W * H * 4)


def broken_horizontal(x, y, length, color, step=23):
    for xx in range(x, x + length, step):
        if RNG.random() > .20:
            rect(xx, y, min(step - RNG.randrange(3, 9), x + length - xx),
                 2, color)


def broken_vertical(x, y, length, color, step=17):
    for yy in range(y, y + length, step):
        if RNG.random() > .28:
            rect(x, yy, 2, min(step - RNG.randrange(3, 8), y + length - yy),
                 color)


broken_horizontal(22, 19, 375, COOL_GLINT)
broken_vertical(19, 23, 780, EDGE)
broken_vertical(398, 29, 768, INK)
broken_horizontal(24, 805, 372, SHADOW)
for x, y, w, h in ((28, 72, 180, 90), (211, 72, 180, 90),
                   (27, 164, 366, 31), (26, 198, 368, 476),
                   (28, 669, 157, 46), (188, 669, 204, 46),
                   (26, 716, 367, 29)):
    broken_horizontal(x + 7, y + 3, w - 15, COOL_GLINT, 27)
    broken_vertical(x + 3, y + 7, h - 15, EDGE, 19)
    broken_horizontal(x + 7, y + h - 5, w - 14, INK, 29)
    broken_vertical(x + w - 4, y + 6, h - 13, SHADOW, 19)
for x in (24, 395):
    for y in (27, 68, 159, 200, 666, 715, 810):
        bolt(x, y)
for x in range(31, 386, 24):
    if RNG.random() > .30:
        rect(x, 199, 5, 2, BRASS)
    if RNG.random() > .50:
        rect(x + 4, 671, 3, 1, EDGE)
for y in range(216, 656, 33):
    if RNG.random() > .25:
        rect(29, y, 2, 7, BRASS)
    if RNG.random() > .35:
        rect(389, y + 4, 2, 5, EDGE)

(OUT / "machine-ink-2d.png").write_bytes(png_bytes())
print(f"PAINTED_BODY {OUT} {W}x{H} base+ink")
