"""Google Play feature graphic (1024x500, no alpha) from a gameplay frame.

    python tool/store/make_feature.py [background.png]

Default background: the Outer Ring store screenshot. Pass AI key art
(art_src/store/feature_src.png, prompt C in PROMPTS.md) to use that instead.
Writes art_src/store/feature_graphic_1024x500.png.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
W, H = 1024, 500
SS = 2


def cover(im, w, h, focus_x=0.5):
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x = round((im.width - w) * focus_x)
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def main():
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        ROOT, 'art_src', 'store', 'screenshots', 'play_1080', '05_orbit_02.png')
    bg = Image.open(src).convert('RGB')
    if 'screenshots' in src:
        # Drop the HUD strip and controls: keep the middle band of the frame.
        bg = bg.crop((int(bg.width * 0.12), int(bg.height * 0.13),
                      int(bg.width * 0.88), int(bg.height * 0.80)))
    img = cover(bg, W * SS, H * SS, focus_x=0.75).convert('RGBA')

    # Darken the left side for the title.
    shade = Image.new('L', img.size, 0)
    d = ImageDraw.Draw(shade)
    for x in range(img.width):
        t = max(0.0, 1 - x / (img.width * 0.62))
        d.line([(x, 0), (x, img.height)], fill=int(215 * t ** 1.2))
    img.paste((11, 19, 43, 255), (0, 0), shade)

    font = os.path.join(ROOT, 'assets', 'fonts', 'RussoOne-Regular.ttf')
    title = ImageFont.truetype(font, 92 * SS)
    tag = ImageFont.truetype(font, 30 * SS)
    x0, y0 = 56 * SS, 168 * SS
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.text((x0, y0), 'NARROW', font=title, fill=(0, 180, 216, 200))
    gd.text((x0, y0 + 96 * SS), 'HAUL', font=title, fill=(0, 180, 216, 200))
    img.alpha_composite(glow.filter(ImageFilter.GaussianBlur(14 * SS)))
    td = ImageDraw.Draw(img)
    td.text((x0, y0), 'NARROW', font=title, fill=(255, 255, 255))
    td.text((x0, y0 + 96 * SS), 'HAUL', font=title, fill=(255, 255, 255))
    td.text((x0 + 4 * SS, y0 + 206 * SS), 'Thrust. Tow. Land.', font=tag, fill=(148, 210, 189))

    out = os.path.join(ROOT, 'art_src', 'store', 'feature_graphic_1024x500.png')
    img.convert('RGB').resize((W, H), Image.LANCZOS).save(out)
    print('wrote', out)


if __name__ == '__main__':
    main()
