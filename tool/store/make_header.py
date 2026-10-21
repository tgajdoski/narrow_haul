"""App Store product page header and search results art (iOS 27+).

    python tool/store/make_header.py [key_art.png] [--tag]

Source: a HUD-free 16:9 flight frame from `tool/store/capture_screenshots.sh`
(the `key_art` target, 5244x2950). Default: key_art/05_orbit_02.png.
--tag adds the "Thrust. Tow. Land." line, centred (the App Store draws the
icon and name under the header, so the title isn't needed).

Writes art_src/store/header/:
  header_3840x1646.jpg     product page header, 21:9
  search_3840x2560.jpg     search results, 3:2
  universal_5244x2950.png  one image for both ("Use header asset in search results")
  crop_check.png           the universal image with both crops outlined
No alpha anywhere (App Store Connect refuses it).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'art_src', 'store', 'header')
UNIVERSAL = (5244, 2950)
HEADER = (3840, 1646)
SEARCH = (3840, 2560)


def cover(im, w, h):
    """Scales [im] to cover w x h and crops the centre (the ship sits there)."""
    k = max(w / im.width, h / im.height)
    im = im.resize((round(im.width * k), round(im.height * k)), Image.LANCZOS)
    x = (im.width - w) // 2
    y = (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def centre_box(size, aspect):
    """The largest centred box of [aspect] (w / h) inside [size]."""
    w, h = size
    if w / h > aspect:
        cw, ch = round(h * aspect), h
    else:
        cw, ch = w, round(w / aspect)
    x, y = (w - cw) // 2, (h - ch) // 2
    return (x, y, x + cw, y + ch)


def vignette(img, strength=0.38):
    """Darkens the edges a little so the frame reads as one picture."""
    w, h = img.size
    small = Image.new('L', (64, 36), 0)
    d = ImageDraw.Draw(small)
    for i in range(18):
        t = i / 17
        d.ellipse((-10 + i * 1.6, -8 + i * 0.9, 74 - i * 1.6, 44 - i * 0.9), fill=int(255 * t))
    mask = small.filter(ImageFilter.GaussianBlur(4)).resize((w, h), Image.BICUBIC)
    dark = Image.new('RGB', (w, h), (5, 8, 22))  # SpaceColors.bg
    keep = mask.point(lambda v: int(255 - (255 - v) * strength))
    return Image.composite(img, dark, keep)


def add_tag(img):
    font = os.path.join(ROOT, 'assets', 'fonts', 'RussoOne-Regular.ttf')
    w, h = img.size
    f = ImageFont.truetype(font, round(h * 0.055))
    text = 'Thrust. Tow. Land.'
    d = ImageDraw.Draw(img)
    tw = d.textlength(text, font=f)
    # Inside both crops: centred, in the lower part of the 21:9 band.
    band = centre_box(img.size, 21 / 9)
    x, y = (w - tw) / 2, band[3] - h * 0.13
    glow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).text((x, y), text, font=f, fill=(0, 180, 216, 210))
    out = img.convert('RGBA')
    out.alpha_composite(glow.filter(ImageFilter.GaussianBlur(h * 0.006)))
    ImageDraw.Draw(out).text((x, y), text, font=f, fill=(255, 255, 255))
    return out.convert('RGB')


def save(img, name, size):
    assert img.size == size, (name, img.size)
    assert img.mode == 'RGB', (name, img.mode)
    path = os.path.join(OUT, name)
    if name.endswith('.jpg'):
        img.save(path, quality=92, subsampling=0)
    else:
        img.save(path, optimize=True)
    print('%s  %dx%d' % (path, *img.size))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    src = args[0] if args else os.path.join(
        ROOT, 'art_src', 'store', 'screenshots', 'key_art', '05_orbit_02.png')
    os.makedirs(OUT, exist_ok=True)
    base = vignette(cover(Image.open(src).convert('RGB'), *UNIVERSAL))
    if '--tag' in sys.argv:
        base = add_tag(base)

    save(base, 'universal_5244x2950.png', UNIVERSAL)
    save(base.crop(centre_box(UNIVERSAL, 21 / 9)).resize(HEADER, Image.LANCZOS),
         'header_3840x1646.jpg', HEADER)
    save(base.crop(centre_box(UNIVERSAL, 3 / 2)).resize(SEARCH, Image.LANCZOS),
         'search_3840x2560.jpg', SEARCH)

    check = base.copy()
    d = ImageDraw.Draw(check)
    for aspect, colour in ((21 / 9, (255, 196, 0)), (3 / 2, (0, 220, 255))):
        d.rectangle(centre_box(UNIVERSAL, aspect), outline=colour, width=12)
    check.resize((1311, 737), Image.LANCZOS).save(os.path.join(OUT, 'crop_check.png'))
    print(os.path.join(OUT, 'crop_check.png'))


if __name__ == '__main__':
    main()
