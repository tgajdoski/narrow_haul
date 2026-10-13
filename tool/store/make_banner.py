"""YouTube channel banner (2560x1440) from a gameplay frame.

    python tool/store/make_banner.py [background.png]

The title sits in YouTube's safe area (the middle 1546x423), the only part
every device shows. Default background: the Outer Ring store screenshot.
Writes art_src/store/youtube_banner_2560x1440.jpg.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from make_feature import ROOT

W, H = 2560, 1440
SAFE_W, SAFE_H = 1546, 423
ZOOM = 1.45


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, 'art_src', 'store', 'screenshots', 'play_1080', '05_orbit_02.png')
    bg = Image.open(src).convert('RGB')
    if 'screenshots' in src:
        # Drop the HUD strip and controls: keep the middle band of the frame.
        bg = bg.crop((int(bg.width * 0.12), int(bg.height * 0.13),
                      int(bg.width * 0.88), int(bg.height * 0.80)))
    # Zoom in and shift so the ship and pod sit right of and below the title.
    k = ZOOM * max(W / bg.width, H / bg.height)
    bg = bg.resize((round(bg.width * k), round(bg.height * k)), Image.LANCZOS)
    x, y = round((bg.width - W) * 0.0), bg.height - H
    img = bg.crop((x, y, x + W, y + H)).convert('RGBA')

    # Darken a soft horizontal band behind the title.
    shade = Image.new('L', img.size, 0)
    d = ImageDraw.Draw(shade)
    cy = H // 2
    for y in range(H):
        t = max(0.0, 1 - abs(y - cy) / (SAFE_H * 0.9))
        d.line([(0, y), (W, y)], fill=int(190 * t ** 1.1))
    img.paste((11, 19, 43, 255), (0, 0), shade)

    font = os.path.join(ROOT, 'assets', 'fonts', 'RussoOne-Regular.ttf')
    title = ImageFont.truetype(font, 176)
    tag = ImageFont.truetype(font, 64)
    text, sub = 'NARROW HAUL', 'Thrust. Tow. Land.'
    tw = title.getbbox(text)[2]
    sw = tag.getbbox(sub)[2]
    tx, ty = (W - tw) // 2, cy - 140
    sx, sy = (W - sw) // 2, cy + 80

    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((tx, ty), text, font=title, fill=(0, 180, 216, 200))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(28)))
    td = ImageDraw.Draw(img)
    td.text((tx, ty), text, font=title, fill=(255, 255, 255))
    td.text((sx, sy), sub, font=tag, fill=(148, 210, 189))

    out = os.path.join(ROOT, 'art_src', 'store', 'youtube_banner_2560x1440.jpg')
    img.convert('RGB').save(out, quality=90)
    print('wrote', out)


if __name__ == '__main__':
    main()
