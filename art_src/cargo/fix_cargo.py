"""Strip baked-in background, centre and frame a cargo pod sprite.

    python art_src/cargo/fix_cargo.py <src.png> <out.png> [size]

The pod rotates around its centre and is drawn at a fixed size
(`CargoBody._spriteHalf`), so every cargo sprite follows the rule of
`assets/cargo.png`: a square canvas with the pod's solid part (alpha >= 128)
filling 80% of it, centred. `test/theme_assets_test.dart` checks this.
"""
import sys
from collections import deque
from PIL import Image

SRC, OUT = sys.argv[1], sys.argv[2]
SIZE = int(sys.argv[3]) if len(sys.argv) > 3 else 128
FILL = 0.80


def is_bg(p):
    # Light grey / white checkerboard or flat backdrop (as in fix_ships.py).
    r, g, b = p[:3]
    return max(r, g, b) - min(r, g, b) <= 22 and min(r, g, b) >= 105


def strip_background(im):
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        q.append((x, 0))
        q.append((x, h - 1))
    for y in range(h):
        q.append((0, y))
        q.append((w - 1, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        # Flood through backdrop colours and already-transparent pixels.
        if bg[i] or not (px[x, y][3] == 0 or is_bg(px[x, y])):
            continue
        bg[i] = 1
        if x > 0: q.append((x - 1, y))
        if x < w - 1: q.append((x + 1, y))
        if y > 0: q.append((x, y - 1))
        if y < h - 1: q.append((x, y + 1))
    for y in range(h):
        for x in range(w):
            if bg[y * w + x]:
                px[x, y] = (0, 0, 0, 0)
    return im, sum(bg) / (w * h)


src = Image.open(SRC).convert('RGBA')
if src.getpixel((0, 0))[3] == 0:
    im, removed = src, 0.0  # already transparent: light rims stay
else:
    im, removed = strip_background(src)
solid = im.getchannel('A').point(lambda v: 255 if v >= 128 else 0)
bbox = solid.getbbox()
if bbox is None:
    sys.exit(f'{SRC}: nothing left after removing the background')
x0, y0, x1, y1 = bbox
cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
scale = SIZE * FILL / max(x1 - x0, y1 - y0)
# Crop a square around the pod's centre with room for soft edges / glow.
half = SIZE / 2 / scale
square = im.crop((round(cx - half), round(cy - half), round(cx + half), round(cy + half)))
# Resize premultiplied so transparent edges don't pick up dark fringes.
out = square.convert('RGBa').resize((SIZE, SIZE), Image.LANCZOS).convert('RGBA')
out.save(OUT, optimize=True)
print(f'{SRC.split("/")[-1]}: bg removed {removed:.0%}, pod bbox {bbox} -> {SIZE}px, {FILL:.0%} fill')
