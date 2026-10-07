"""Strip baked-in checkerboard, crop, and frame ship sprites like ship.png."""
import sys
from collections import deque
from PIL import Image

SRC, OUT, REF = sys.argv[1], sys.argv[2], sys.argv[3]

def is_bg(p):
    r, g, b = p[:3]
    return max(r, g, b) - min(r, g, b) <= 22 and min(r, g, b) >= 105

def strip_background(im):
    im = im.convert('RGBA')
    w, h = im.size
    px = im.load()
    bg = bytearray(w * h)
    q = deque()
    for x in range(w):
        for y in (0, h - 1):
            q.append((x, y))
    for y in range(h):
        for x in (0, w - 1):
            q.append((x, y))
    while q:
        x, y = q.popleft()
        i = y * w + x
        if bg[i] or not is_bg(px[x, y]):
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

ref = Image.open(REF).convert('RGBA')
rx0, ry0, rx1, ry1 = ref.getchannel('A').getbbox()
box_w, box_h = rx1 - rx0, ry1 - ry0
cx = (rx0 + rx1) / 2

im, removed = strip_background(Image.open(SRC))
bbox = im.getchannel('A').getbbox()
ship = im.crop(bbox)
scale = min(box_w / ship.width, box_h / ship.height)
size = (max(1, round(ship.width * scale)), max(1, round(ship.height * scale)))
# Resize premultiplied so transparent edges don't pick up dark fringes.
ship = ship.convert('RGBa').resize(size, Image.LANCZOS).convert('RGBA')

canvas = Image.new('RGBA', ref.size, (0, 0, 0, 0))
x = round(cx - size[0] / 2)
# Bottom-align to the reference nozzle line: the engine plume starts there.
y = ry1 - size[1]
canvas.alpha_composite(ship, (x, y))
canvas.save(OUT, optimize=True)
print(f'{SRC.split("/")[-1]}: bg removed {removed:.0%}, hull bbox {bbox} -> {size} at ({x},{y})')
