#!/usr/bin/env python3
"""Achievement kit for Play Games Services and Game Center.

Reads the achievements from lib/game/services/achievement_service.dart and
writes art_src/achievements/:
  icons/<id>.png                 512x512 badge (dark disc, tier ring, emoji)
  play_import.zip                Play Console → Play Games Services →
                                 Achievements → Import achievements
  game_center.csv                one row per achievement for App Store
                                 Connect (id, title, points, hidden,
                                 descriptions, icon)

The emoji art is Google's Noto Emoji (Apache 2.0, github.com/googlefonts/
noto-emoji, tag v2.047), downloaded once into art_src/achievements/.noto/
(not committed). Never Apple's emoji: their artwork isn't licensed for this.
Needs Pillow and a network connection on the first run.
  python3 tool/store/make_achievements.py
"""
import csv
import io
import math
import os
import re
import urllib.request
import zipfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, 'lib/game/services/achievement_service.dart')
OUT = os.path.join(ROOT, 'art_src/achievements')
NOTO = 'https://raw.githubusercontent.com/googlefonts/noto-emoji/v2.047/png/512/'
NOTO_CACHE = os.path.join(OUT, '.noto')


def noto_png(emoji):
    """The Noto Emoji 512 px PNG for [emoji] (FE0F dropped, like Noto's
    file names)."""
    name = 'emoji_u' + '_'.join(f'{ord(ch):04x}' for ch in emoji
                               if ord(ch) != 0xFE0F) + '.png'
    path = os.path.join(NOTO_CACHE, name)
    if not os.path.exists(path):
        os.makedirs(NOTO_CACHE, exist_ok=True)
        urllib.request.urlretrieve(NOTO + name, path)
    return Image.open(path).convert('RGBA')

# Points (multiples of 5; Play caps a game at 1000 in all, Game Center at
# 1000 and 100 each). Unlisted achievements are worth 25.
POINTS = {
    'first_haul': 10, 'daily_pilot': 10, 'opened_the_box': 10,
    'weapons_hot': 10, 'rank_commercial': 10,
    'rank_captain': 50, 'week_on_duty': 50,
    'gambler': 50, 'fleet_qualified': 50, 'level_20': 50,
    'rank_chief': 50, 'salvage_collector': 50,
    'perfect_pilot': 75,
}
# Salvage curse jokes stay a surprise until earned.
HIDDEN = {'ghost_protocol', 'bee_lieve_it', 'bad_trip', 'shake_it_off'}

TIER = {10: (0x5C, 0xE1, 0xFF), 25: (0x00, 0xB4, 0xD8), 50: (0x9B, 0x8C, 0xFF),
        75: (0xFF, 0xD1, 0x66)}
BG = (0x05, 0x08, 0x16)
PANEL = (0x0D, 0x1B, 0x2A)


def read_achievements():
    s = open(SRC, encoding='utf-8').read()
    ids = dict(re.findall(r"static const (\w+) = '(\w+)';", s))
    q = r"""(?:'((?:[^'\\]|\\.)*)'|"((?:[^"\\]|\\.)*)")"""
    pat = re.compile(
        r"id: AchievementIds\.(\w+),\s*title: " + q +
        r",\s*description:\s*" + q + r",\s*icon: '([^']*)'")
    out = []
    for m in pat.finditer(s):
        key, t1, t2, d1, d2, icon = m.groups()
        unq = lambda x: (x or '').replace("\\'", "'")
        out.append({
            'id': ids[key],
            'title': unq(t1 or t2),
            'description': unq(d1 or d2),
            'icon': icon,
        })
    return out


def plain(text):
    """Play forbids commas in names and descriptions."""
    return text.replace(', ', ' ').replace(',', '')


def badge(emoji, accent):
    size = 512
    img = Image.new('RGBA', (size, size), BG + (255,))
    c = size / 2
    # Soft radial glow in the accent colour.
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    for r in range(240, 0, -6):
        a = int(70 * (1 - r / 240) ** 1.6)
        gd.ellipse((c - r, c - r, c + r, c + r), fill=accent + (a,))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    # Hex plate.
    hexr = 200
    pts = [(c + hexr * math.cos(math.radians(60 * i + 30)),
            c + hexr * math.sin(math.radians(60 * i + 30))) for i in range(6)]
    d.polygon(pts, fill=PANEL + (235,), outline=accent + (255,), width=10)
    inner = [(c + (hexr - 22) * math.cos(math.radians(60 * i + 30)),
              c + (hexr - 22) * math.sin(math.radians(60 * i + 30))) for i in range(6)]
    d.polygon(inner, outline=accent + (90,), width=3)
    e = noto_png(emoji)
    bbox = e.getbbox()
    if bbox:
        e = e.crop(bbox)
    scale = 230 / max(e.size)
    e = e.resize((round(e.width * scale), round(e.height * scale)),
                 Image.LANCZOS)
    shadow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 150), (round(c - e.width / 2) + 6,
                                  round(c - e.height / 2) + 10), e)
    img.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(8)))
    img.alpha_composite(e, (round(c - e.width / 2), round(c - e.height / 2)))
    return img.convert('RGB')


def main():
    items = read_achievements()
    assert len(items) == 34, f'expected 34 achievements, found {len(items)}'
    total = sum(POINTS.get(a['id'], 25) for a in items)
    assert total <= 1000, total
    os.makedirs(os.path.join(OUT, 'icons'), exist_ok=True)

    meta, icons = io.StringIO(), io.StringIO()
    mw, iw = csv.writer(meta, lineterminator='\n'), csv.writer(icons, lineterminator='\n')
    gc_rows = []
    zbuf = io.BytesIO()
    with zipfile.ZipFile(zbuf, 'w', zipfile.ZIP_DEFLATED) as z:
        for order, a in enumerate(items, start=1):
            pts = POINTS.get(a['id'], 25)
            png = os.path.join(OUT, 'icons', f"{a['id']}.png")
            badge(a['icon'], TIER[pts]).save(png, optimize=True)
            z.write(png, f"{a['id']}.png")
            name = plain(a['title'])
            mw.writerow([name, plain(a['description']), 'False', '',
                         'Hidden' if a['id'] in HIDDEN else 'Revealed', pts, order])
            iw.writerow([name, f"{a['id']}.png"])
            gc_rows.append([f"nh.{a['id']}", a['title'], pts,
                            'yes' if a['id'] in HIDDEN else 'no',
                            a['description'], a['description'],
                            f"icons/{a['id']}.png"])
        z.writestr('AchievementsMetadata.csv', meta.getvalue())
        z.writestr('AchievementsIconsMappings.csv', icons.getvalue())
    open(os.path.join(OUT, 'play_import.zip'), 'wb').write(zbuf.getvalue())
    with open(os.path.join(OUT, 'game_center.csv'), 'w', newline='', encoding='utf-8') as f:
        w = csv.writer(f)
        w.writerow(['achievement_id', 'title', 'points', 'hidden',
                    'pre_earned_description', 'earned_description', 'image'])
        w.writerows(gc_rows)
    print(f'{len(items)} achievements, {total} points → {OUT}')


if __name__ == '__main__':
    main()
