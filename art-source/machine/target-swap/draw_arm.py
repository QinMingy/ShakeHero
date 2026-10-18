"""Install the user's replacement sprites for the target plaque gesture.

The original blue-sleeve drawing function is retained as source history.
Production sprites come from user-hand-v2, copied byte-for-byte without repainting.
The shared source pivot is (25, 36), with the user-sprite angle set in TargetSwap.lua.
"""

from pathlib import Path
from shutil import copyfile

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[3]
DEST = ROOT / "assets" / "image" / "machine-layered"
SIZE = (160, 80)
PALETTE = {
    "ink": "#191B18",
    "deep": "#283539",
    "sleeve_shadow": "#354A50",
    "sleeve": "#4C6167",
    "sleeve_light": "#60767A",
    "sleeve_edge": "#748585",
    "cuff_shadow": "#394B4D",
    "cuff": "#657878",
    "cuff_light": "#87918A",
    "skin_shadow": "#86694D",
    "skin": "#A3815F",
    "skin_light": "#B99A74",
    "skin_edge": "#C5A680",
    "nail": "#C7AE89",
}


def make_arm(gripping: bool) -> Image.Image:
    image = Image.new("RGBA", SIZE)
    draw = ImageDraw.Draw(image)

    def poly(points, color):
        draw.polygon(points, fill=PALETTE[color])

    def line(points, color, width=1):
        draw.line(points, fill=PALETTE[color], width=width)

    def rect(box, color):
        draw.rectangle(box, fill=PALETTE[color])

    # A soft cloth sleeve, with stepped silhouette and a few broad fold planes.
    # Polygon endpoints exceed the canvas so the screen edge has no end cap.
    poly([(48, 29), (57, 26), (68, 25), (68, 24), (89, 24),
          (89, 25), (112, 25), (112, 26), (137, 26), (137, 27),
          (163, 27), (163, 74), (138, 74), (138, 73), (119, 73),
          (119, 72), (99, 72), (99, 70), (81, 70), (81, 68),
          (67, 68), (67, 64), (56, 64), (56, 59), (48, 56)], "ink")
    poly([(50, 31), (59, 28), (70, 27), (90, 27), (90, 28),
          (114, 28), (114, 29), (139, 29), (139, 30), (163, 30),
          (163, 71), (139, 71), (139, 70), (120, 70), (120, 69),
          (100, 69), (100, 67), (82, 67), (82, 65), (69, 65),
          (69, 61), (58, 61), (58, 56), (50, 54)], "sleeve")
    poly([(55, 31), (71, 28), (89, 28), (89, 29), (113, 29),
          (113, 30), (138, 30), (138, 31), (163, 31), (163, 39),
          (130, 38), (115, 37), (93, 37), (80, 36), (68, 38),
          (57, 40)], "sleeve_light")
    line([(70, 28), (88, 28)], "sleeve_edge")
    line([(92, 29), (109, 29)], "sleeve_edge")
    poly([(60, 48), (71, 55), (83, 57), (100, 60), (122, 62),
          (142, 62), (163, 63), (163, 71), (139, 71), (139, 70),
          (120, 70), (120, 69), (100, 69), (100, 67), (82, 67),
          (82, 65), (69, 65), (69, 61), (58, 61)], "sleeve_shadow")
    poly([(73, 35), (79, 35), (74, 40), (73, 45), (75, 50),
          (79, 54), (72, 52), (68, 47), (69, 41)], "sleeve_shadow")
    line([(75, 37), (72, 43), (72, 47)], "deep")
    poly([(91, 49), (98, 48), (106, 49), (111, 51), (123, 52),
          (141, 53), (163, 53), (163, 56), (139, 56), (121, 55),
          (110, 54), (102, 51)], "sleeve_light")
    line([(115, 64), (134, 65), (144, 65)], "deep")
    line([(148, 66), (163, 66)], "deep")

    # The cuff is a single folded band rather than jewelry or gold trim.
    poly([(44, 28), (51, 27), (57, 30), (59, 36), (58, 48),
          (56, 58), (53, 61), (46, 59), (42, 54), (43, 38)], "ink")
    poly([(46, 30), (50, 29), (55, 32), (57, 37), (56, 48),
          (54, 57), (52, 59), (47, 57), (44, 53), (45, 38)], "cuff")
    poly([(46, 31), (50, 30), (54, 33), (55, 38), (53, 49),
          (51, 55), (48, 55), (46, 52)], "cuff_light")
    poly([(55, 35), (57, 38), (56, 48), (54, 57), (52, 59),
          (49, 57), (52, 51), (54, 42)], "cuff_shadow")
    line([(47, 33), (47, 42)], "cuff")
    line([(46, 47), (46, 52)], "cuff_shadow")

    # Wrist and palm remain narrow enough to keep the plaque digits visible.
    poly([(16, 23), (25, 22), (31, 24), (36, 27), (40, 31),
          (46, 32), (49, 36), (48, 49), (45, 54), (38, 54),
          (31, 50), (24, 48), (17, 43), (12, 36)], "ink")
    poly([(17, 25), (25, 24), (30, 26), (35, 29), (39, 33),
          (45, 34), (47, 37), (46, 48), (44, 52), (39, 52),
          (32, 48), (25, 46), (19, 41), (14, 35)], "skin")
    poly([(32, 39), (37, 41), (45, 40), (45, 47), (42, 50),
          (38, 48), (32, 45), (26, 43), (25, 40)], "skin_shadow")
    poly([(18, 25), (25, 25), (30, 27), (33, 30), (30, 33),
          (23, 33), (18, 30)], "skin_light")
    line([(19, 25), (24, 25)], "skin_edge")
    line([(39, 35), (44, 36)], "skin_light")
    line([(37, 37), (40, 38)], "skin_light")

    # The left silhouette resolves into four staggered curled fingertips.
    # Their lower facets and short dark creases show a grip at native scale.
    fingers = [
        ([(7, 24), (15, 23), (21, 25), (22, 30), (17, 32),
          (11, 31), (9, 33), (9, 39), (7, 42), (3, 40),
          (2, 35), (3, 28)],
         [(7, 26), (14, 25), (19, 27), (20, 29), (16, 30),
          (10, 29), (7, 32), (7, 38), (6, 40), (4, 38),
          (4, 34), (5, 29)]),
        ([(12, 32), (19, 33), (20, 40), (18, 47), (15, 50),
          (11, 49), (8, 45), (8, 38)],
         [(12, 34), (17, 35), (18, 40), (16, 46), (14, 48),
          (12, 47), (10, 44), (10, 38)]),
        ([(20, 35), (26, 37), (27, 44), (24, 52), (20, 55),
          (16, 53), (14, 49), (16, 42)],
         [(20, 38), (24, 39), (25, 44), (22, 50), (20, 53),
          (18, 51), (16, 48), (18, 42)]),
        ([(28, 40), (32, 42), (34, 48), (31, 55), (28, 58),
          (24, 57), (22, 53), (25, 47)],
         [(28, 42), (30, 44), (32, 48), (29, 54), (27, 56),
          (25, 55), (24, 53), (27, 47)]),
    ]
    for outline, fill in fingers:
        poly(outline, "ink")
        poly(fill, "skin")
    poly([(5, 28), (8, 26), (14, 26), (17, 27), (17, 28),
          (9, 28), (6, 31), (5, 34)], "skin_light")
    line([(4, 37), (6, 39)], "skin_shadow")
    line([(11, 39), (11, 44), (13, 46)], "skin_light")
    line([(16, 40), (17, 42)], "skin_shadow")
    line([(18, 44), (18, 48), (20, 50)], "skin_light")
    line([(23, 44), (23, 46)], "skin_shadow")
    line([(26, 50), (26, 53), (27, 54)], "skin_light")
    rect((5, 34, 6, 36), "nail")
    rect((12, 43, 14, 45), "nail")
    rect((19, 47, 21, 49), "nail")
    rect((27, 51, 28, 53), "nail")

    if gripping:
        # Thumb closes over the top edge. Its contact tip is (25, 36).
        poly([(39, 28), (34, 27), (30, 28), (27, 31), (24, 33),
              (22, 37), (22, 41), (25, 44), (29, 44), (32, 41),
              (33, 37), (37, 36), (41, 36), (43, 33)], "ink")
        poly([(38, 30), (34, 29), (31, 30), (29, 33), (26, 35),
              (24, 38), (24, 40), (26, 42), (28, 42), (30, 40),
              (31, 36), (36, 34), (40, 34), (41, 33)], "skin")
        poly([(34, 30), (37, 31), (38, 32), (33, 33), (30, 36),
              (27, 36), (28, 33), (31, 31)], "skin_light")
        line([(25, 38), (25, 40), (27, 41)], "skin_light")
        rect((25, 37, 27, 39), "nail")
        line([(32, 37), (31, 40)], "skin_shadow")
    else:
        # The lifted thumb provides a distinct anticipation/open silhouette.
        poly([(38, 31), (33, 28), (31, 24), (29, 19), (25, 16),
              (21, 16), (19, 19), (20, 24), (24, 28), (27, 34),
              (31, 38), (36, 37), (40, 35)], "ink")
        poly([(37, 32), (32, 29), (29, 25), (27, 20), (24, 18),
              (22, 18), (21, 20), (22, 23), (26, 27), (29, 33),
              (32, 36), (35, 35), (38, 34)], "skin")
        poly([(22, 19), (24, 19), (26, 21), (27, 24), (26, 25),
              (23, 22)], "skin_light")
        line([(29, 28), (31, 31), (34, 33)], "skin_light")
        rect((22, 19, 24, 21), "nail")
        line([(29, 32), (31, 34)], "skin_shadow")

    # A wrist crease is deliberately one source pixel, matching plaque ink.
    line([(41, 45), (43, 47), (43, 49)], "skin_shadow")
    return image


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    for suffix, name in (("open", "hand_open_160x80.png"), ("grip", "hand_grab_160x80.png")):
        path = DEST / f"target-arm-{suffix}.png"
        copyfile(Path(__file__).parent / "user-hand-v2" / name, path)
        print(path)


if __name__ == "__main__":
    main()
