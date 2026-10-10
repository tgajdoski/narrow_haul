"""Store images for the in-app purchases: the ammo packs (nh_demo_kit,
nh_arsenal_crate), the Fleet Pass (nh_fleet_pass), the Full Game
(nh_full_game) and the Supporter Pack (nh_supporter_pack).

    python tool/store/make_pack_images.py

Ammo packs: the in-game supply crate (amber box, red chevron). Fleet Pass:
the six ship sprites (assets/ship*.png) in formation. Full Game: the
Kestrel flying past a struck-out AD badge. Supporter Pack: the Kestrel in
the Supporter Livery with a gem and coins. Each on the game's
backdrop with its name, in 1024x1024 (App Store promotional image) and
512x512 (Play), RGB without alpha. Writes art_src/store/iap/<id>_<size>.png.
"""
import math
import os

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'art_src', 'store', 'iap')
FONT = os.path.join(ROOT, 'assets', 'fonts', 'RussoOne-Regular.ttf')
S = 1024

BACK = (11, 19, 43)
AMBER = (255, 200, 87)
RED = (255, 82, 82)
CRATE = (59, 51, 38)

PACKS = {
    'nh_demo_kit': ('DEMOLITION KIT', '10 CHARGES · 10 BOMBS · 60s LASER', 1),
    'nh_arsenal_crate': ('ARSENAL CRATE', '30 OF EVERY WEAPON · 3 MIN LASER', 3),
}


def glow(size, center, radius, color, alpha):
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse((cx - radius, cy - radius, cx + radius, cy + radius), fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(radius * 0.45))


def crate(d, cx, cy, w):
    h = w * 0.72
    r = w * 0.06
    box = (cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2)
    d.rounded_rectangle(box, r, fill=CRATE, outline=AMBER, width=max(4, int(w * 0.05)))
    band = cy - h * 0.17
    d.line((cx - w / 2, band, cx + w / 2, band), fill=AMBER, width=max(4, int(w * 0.05)))
    # Corner rivets.
    for sx in (-1, 1):
        for sy in (-1, 1):
            px, py = cx + sx * w * 0.38, cy + sy * h * 0.36
            d.ellipse((px - w * 0.025, py - w * 0.025, px + w * 0.025, py + w * 0.025), fill=AMBER)
    # Warning chevron.
    cw = w * 0.2
    top = cy + h * 0.0
    d.line(
        [(cx - cw, top + cw * 0.95), (cx, top), (cx + cw, top + cw * 0.95)],
        fill=RED, width=max(5, int(w * 0.06)), joint='curve',
    )


def bomb(d, cx, cy, r):
    # Fuse with a spark, so it reads as a bomb (not a wheel).
    fx, fy = cx + r * 0.75, cy - r * 0.75
    d.line((cx + r * 0.5, cy - r * 0.5, fx, fy), fill=AMBER, width=max(3, int(r * 0.2)))
    burst(d, fx + r * 0.2, fy - r * 0.2, r * 0.45)
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(43, 48, 59), outline=AMBER, width=max(3, int(r * 0.22)))
    d.ellipse((cx - r * 0.35, cy - r * 0.35, cx + r * 0.35, cy + r * 0.35), fill=RED)


def burst(d, cx, cy, r):
    pts = []
    for k in range(16):
        a = k * math.pi / 8
        rr = r if k % 2 == 0 else r * 0.45
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, fill=(255, 232, 176))


CYAN = (51, 214, 255)
ASSETS = os.path.join(ROOT, 'assets')

# (sprite, x, y, width) as fractions of the canvas: two rows of three, the
# armed Talon and heavy Mule behind, the Kestrel leading the front row.
FLEET = [
    ('ship_mule.png', 0.19, 0.19, 0.21),
    ('ship_talon.png', 0.5, 0.17, 0.22),
    ('ship_vector.png', 0.81, 0.19, 0.20),
    ('ship_hopper.png', 0.19, 0.47, 0.17),
    ('ship.png', 0.5, 0.46, 0.20),
    ('ship_skate.png', 0.81, 0.47, 0.19),
]


TEAL = (51, 214, 201)  # Supporter Livery (kLiveryTints, 0x7733D6C9)


def ship(im, sprite, cx, cy, w, tint=None):
    """Pastes a ship sprite (hull x 58-198 of 256) [w] wide, centred, with a
    plume glow under its nozzle (row 181)."""
    src = Image.open(os.path.join(ASSETS, sprite)).convert('RGBA')
    if tint is not None:
        # srcATop tint, as the game draws a livery.
        color, a = tint
        flat = Image.new('RGBA', src.size, color + (255,))
        mixed = Image.blend(src, flat, a)
        mixed.putalpha(src.getchannel('A'))
        src = mixed
    scale = w / (198 - 58)
    side = int(256 * scale)
    art = src.resize((side, side), Image.LANCZOS)
    x0 = int(cx - 128 * scale)
    y0 = int(cy - 120 * scale)
    nozzle = (int(cx), int(y0 + 181 * scale + w * 0.08))
    im.alpha_composite(glow(im.size[0], nozzle, int(w * 0.16), CYAN, 150))
    im.alpha_composite(art, (x0, y0))


def make_fleet(pid, title, line):
    ss = 2
    size = S * ss
    im = Image.new('RGBA', (size, size), BACK + (255,))
    im.alpha_composite(glow(size, (size // 2, int(size * 0.36)), int(size * 0.4), CYAN, 55))
    im.alpha_composite(glow(size, (size // 2, int(size * 0.24)), int(size * 0.18), AMBER, 45))
    d = ImageDraw.Draw(im)
    # A few stars behind the formation (fixed, so reruns match).
    for i in range(70):
        x = (i * 7919) % size
        y = (i * 104729) % int(size * 0.68)
        r = 2 + (i % 3) * 2
        d.ellipse((x - r, y - r, x + r, y + r), fill=(200, 220, 255, 90 + (i % 4) * 30))
    for sprite, fx, fy, fw in FLEET:
        ship(im, sprite, size * fx, size * fy, size * fw)
    d = ImageDraw.Draw(im)
    tf = ImageFont.truetype(FONT, int(size * 0.11))
    lf = ImageFont.truetype(FONT, int(size * 0.04))
    tw = d.textlength(title, font=tf)
    d.text(((size - tw) / 2, size * 0.71), title, font=tf, fill=(255, 255, 255))
    lw = d.textlength(line, font=lf)
    d.text(((size - lw) / 2, size * 0.86), line, font=lf, fill=AMBER)
    _save(pid, im)


def _backdrop(size, color):
    im = Image.new('RGBA', (size, size), BACK + (255,))
    im.alpha_composite(glow(size, (size // 2, int(size * 0.36)), int(size * 0.4), color, 55))
    d = ImageDraw.Draw(im)
    for i in range(70):
        x = (i * 7919) % size
        y = (i * 104729) % int(size * 0.68)
        r = 2 + (i % 3) * 2
        d.ellipse((x - r, y - r, x + r, y + r), fill=(200, 220, 255, 90 + (i % 4) * 30))
    return im


def _title(im, title, line, line_color=AMBER):
    size = im.size[0]
    d = ImageDraw.Draw(im)
    # Long titles shrink to keep a margin (≤ 84% of the width).
    pt = size * 0.105
    tf = ImageFont.truetype(FONT, int(pt))
    while d.textlength(title, font=tf) > size * 0.84:
        pt *= 0.96
        tf = ImageFont.truetype(FONT, int(pt))
    lf = ImageFont.truetype(FONT, int(size * 0.038))
    tw = d.textlength(title, font=tf)
    d.text(((size - tw) / 2, size * 0.71), title, font=tf, fill=(255, 255, 255))
    lw = d.textlength(line, font=lf)
    d.text(((size - lw) / 2, size * 0.86), line, font=lf, fill=line_color)


def make_full_game(pid):
    size = S * 2
    im = _backdrop(size, CYAN)
    d = ImageDraw.Draw(im)
    # A struck-out AD badge, left; the Kestrel flying clear of it, right.
    bx, by, bw, bh = size * 0.33, size * 0.34, size * 0.36, size * 0.24
    box = (bx - bw / 2, by - bh / 2, bx + bw / 2, by + bh / 2)
    d.rounded_rectangle(box, size * 0.03, fill=(22, 32, 60), outline=(150, 165, 190), width=int(size * 0.012))
    af = ImageFont.truetype(FONT, int(size * 0.13))
    aw = d.textlength('AD', font=af)
    d.text((bx - aw / 2, by - size * 0.085), 'AD', font=af, fill=(150, 165, 190))
    r = size * 0.19
    d.ellipse((bx - r, by - r, bx + r, by + r), outline=RED, width=int(size * 0.03))
    off = r * 0.707
    d.line((bx - off, by + off, bx + off, by - off), fill=RED, width=int(size * 0.03))
    ship(im, 'ship.png', size * 0.73, size * 0.30, size * 0.26)
    _title(im, 'FULL GAME', 'EVERY EXPEDITION · NO ADS')
    _save(pid, im)


def gem(d, cx, cy, w):
    h = w * 0.85
    top = cy - h * 0.45
    girdle = cy - h * 0.12
    pts = [(cx - w / 2, girdle), (cx - w * 0.28, top), (cx + w * 0.28, top), (cx + w / 2, girdle), (cx, cy + h * 0.55)]
    d.polygon(pts, fill=(40, 190, 200), outline=(200, 255, 250))
    d.line([(cx - w / 2, girdle), (cx + w / 2, girdle)], fill=(200, 255, 250), width=max(3, int(w * 0.03)))
    for x in (-0.28, 0.28):
        d.line([(cx + w * x, top), (cx, cy + h * 0.55)], fill=(150, 240, 240), width=max(2, int(w * 0.02)))
    d.polygon([(cx - w * 0.28, top), (cx, girdle), (cx + w * 0.28, top)], fill=(120, 235, 240))


def coin(d, cx, cy, r):
    d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(240, 180, 40), outline=(255, 225, 120), width=max(3, int(r * 0.14)))
    d.ellipse((cx - r * 0.62, cy - r * 0.62, cx + r * 0.62, cy + r * 0.62), outline=(200, 140, 20), width=max(2, int(r * 0.1)))


def make_supporter(pid):
    size = S * 2
    im = _backdrop(size, TEAL)
    im.alpha_composite(glow(size, (int(size * 0.5), int(size * 0.3)), int(size * 0.2), TEAL, 70))
    d = ImageDraw.Draw(im)
    for cx, cy, r in ((0.15, 0.5, 0.05), (0.22, 0.58, 0.045), (0.11, 0.6, 0.04), (0.86, 0.55, 0.05), (0.8, 0.62, 0.04)):
        coin(d, size * cx, size * cy, size * r)
    gem(d, size * 0.16, size * 0.24, size * 0.14)
    gem(d, size * 0.84, size * 0.27, size * 0.11)
    ship(im, 'ship.png', size * 0.5, size * 0.30, size * 0.32, tint=(TEAL, 0x77 / 255))
    _title(im, 'SUPPORTER PACK', 'FULL GAME · LIVERY · 500 COINS', line_color=TEAL)
    _save(pid, im)


def _save(pid, im):
    final = im.convert('RGB').resize((S, S), Image.LANCZOS)
    os.makedirs(OUT, exist_ok=True)
    for px in (1024, 512):
        path = os.path.join(OUT, f'{pid}_{px}.png')
        (final if px == S else final.resize((px, px), Image.LANCZOS)).save(path, optimize=True)
        print(path)


def make(pid, title, line, crates):
    ss = 2
    size = S * ss
    im = Image.new('RGBA', (size, size), BACK + (255,))
    im.alpha_composite(glow(size, (size // 2, int(size * 0.44)), int(size * 0.34), AMBER, 70))
    d = ImageDraw.Draw(im)

    cy = size * 0.44
    if crates == 1:
        burst(d, size * 0.8, size * 0.17, size * 0.08)
        crate(d, size / 2, cy, size * 0.46)
        bomb(d, size * 0.16, size * 0.36, size * 0.055)
        bomb(d, size * 0.85, size * 0.5, size * 0.045)
    else:
        burst(d, size * 0.2, size * 0.2, size * 0.07)
        burst(d, size * 0.82, size * 0.22, size * 0.06)
        crate(d, size * 0.33, cy + size * 0.06, size * 0.3)
        crate(d, size * 0.67, cy + size * 0.06, size * 0.3)
        crate(d, size * 0.5, cy - size * 0.13, size * 0.3)
        bomb(d, size * 0.1, size * 0.42, size * 0.045)
        bomb(d, size * 0.9, size * 0.42, size * 0.045)

    tf = ImageFont.truetype(FONT, int(size * 0.095))
    lf = ImageFont.truetype(FONT, int(size * 0.038))
    tw = d.textlength(title, font=tf)
    d.text(((size - tw) / 2, size * 0.73), title, font=tf, fill=(255, 255, 255))
    lw = d.textlength(line, font=lf)
    d.text(((size - lw) / 2, size * 0.86), line, font=lf, fill=AMBER)

    _save(pid, im)


if __name__ == '__main__':
    for pid, (title, line, crates) in PACKS.items():
        make(pid, title, line, crates)
    make_fleet('nh_fleet_pass', 'FLEET PASS', 'EVERY SHIP · NOW AND LATER')
    make_full_game('nh_full_game')
    make_supporter('nh_supporter_pack')
