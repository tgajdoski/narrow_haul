"""Build the Narrow Haul app icon layers from the in-game sprites.

Fallback icon that needs no image generator: the Kestrel (assets/ship.png)
towing a cargo pod on its rope through a cave gap.

    python tool/store/make_icon.py            # writes art_src/icon/*.png

Outputs (all 1024x1024 unless noted):
  icon_1024.png        full icon, opaque (App Store, iOS, macOS, legacy Android)
  icon_bg_1024.png     adaptive-icon background layer (backdrop + rock walls)
  icon_fg_1024.png     adaptive-icon foreground (ship + rope + pod, transparent,
                       inside the 66/108 safe zone) - also the iOS dark icon
  icon_mono_1024.png   white silhouette of the foreground (Android 13 themed)
  icon_tinted_1024.png grayscale foreground on black (iOS 18 tinted icon)
  splash_logo.png      foreground scaled for the launch screen (transparent)
  play_icon_512.png    Google Play listing icon (32-bit PNG)

If you have AI art instead, run tool/store/prepare_icon.py on it; it writes
the same file names, so flutter_launcher_icons doesn't need to change.
"""
import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, 'art_src', 'icon')
SS = 2  # supersampling
N = 1024 * SS

BACKDROP_TOP = (0x13, 0x22, 0x4A)
BACKDROP_BOT = (0x0B, 0x13, 0x2B)
ROCK_FILL = (0x1D, 0x34, 0x61)
ROCK_EDGE = (0x0B, 0x19, 0x29)
RIM = (0x00, 0xB4, 0xD8)
ROPE = (0xE8, 0xD9, 0xB0)
OUTLINE = (0x14, 0x1E, 0x2E)


def backdrop():
    im = Image.new('RGB', (N, N))
    d = ImageDraw.Draw(im)
    for y in range(N):
        t = y / (N - 1)
        d.line([(0, y), (N, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(BACKDROP_TOP, BACKDROP_BOT)))
    # Soft cyan glow behind the subject.
    glow = Image.new('L', (N, N), 0)
    ImageDraw.Draw(glow).ellipse([N * 0.18, N * 0.12, N * 0.82, N * 0.88], fill=70)
    glow = glow.filter(ImageFilter.GaussianBlur(N * 0.12))
    im = Image.composite(Image.new('RGB', (N, N), RIM), im, glow)
    return im


def wall(points):
    """Rock wall polygon with a dark edge and a cyan rim light."""
    layer = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    mask = Image.new('L', (N, N), 0)
    ImageDraw.Draw(mask).polygon(points, fill=255)
    rim = mask.filter(ImageFilter.MaxFilter(1 + 2 * (8 * SS // 2)))
    rim_glow = ImageChops.subtract(rim.filter(ImageFilter.GaussianBlur(14 * SS)), mask)
    layer.paste((*RIM, 255), (0, 0), rim_glow.point(lambda v: min(255, v * 2)))
    edge = mask.filter(ImageFilter.MaxFilter(1 + 2 * (5 * SS)))
    layer.paste((*ROCK_EDGE, 255), (0, 0), edge)
    inner = mask.filter(ImageFilter.MinFilter(1 + 2 * (2 * SS)))
    layer.paste((*ROCK_FILL, 255), (0, 0), inner)
    return layer


def lumpy(cx, side, seed):
    """Organic cave-wall outline hugging one side of the canvas."""
    pts = []
    steps = 28
    for i in range(steps + 1):
        y = -0.05 * N + i * 1.1 * N / steps
        t = i / steps
        x = cx + N * (0.07 * math.sin(t * 5.1 + seed) + 0.035 * math.sin(t * 13.7 + seed * 2.3))
        pts.append((x, y))
    edge = 0 if side < 0 else N
    return [(edge, -0.1 * N)] + pts + [(edge, 1.1 * N)]


def background():
    im = backdrop().convert('RGBA')
    im.alpha_composite(wall(lumpy(N * 0.13, -1, 0.4)))
    im.alpha_composite(wall(lumpy(N * 0.87, 1, 2.1)))
    return im


def cargo(r):
    """Orange spherical cargo pod like assets/cargo.png, drawn at size."""
    s = int(r * 2 + 16 * SS)
    im = Image.new('RGBA', (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = s / 2
    d.ellipse([c - r, c - r, c + r, c + r], fill=OUTLINE)
    r1 = r - 7 * SS
    d.ellipse([c - r1, c - r1, c + r1, c + r1], fill=(0xC9, 0x4A, 0x2A))
    # Lit upper-left half.
    hl = Image.new('L', (s, s), 0)
    ImageDraw.Draw(hl).ellipse([c - r1 * 1.05, c - r1 * 1.15, c + r1 * 0.75, c + r1 * 0.6], fill=255)
    hl = hl.filter(ImageFilter.GaussianBlur(r * 0.18))
    lit = Image.new('RGBA', (s, s), (0xEE, 0x6E, 0x3C, 255))
    mask = Image.new('L', (s, s), 0)
    ImageDraw.Draw(mask).ellipse([c - r1, c - r1, c + r1, c + r1], fill=255)
    im.paste(lit, (0, 0), ImageChops.multiply(hl, mask))
    # Panel band and bolts.
    band = 9 * SS
    d.arc([c - r1, c - r1 * 0.35, c + r1, c + r1 * 0.35], 0, 180, fill=OUTLINE, width=band // 2)
    d.line([(c, c - r1), (c, c - r1 * 0.32)], fill=OUTLINE, width=band // 2)
    for a in (200, 240, 300, 340):
        bx = c + math.cos(math.radians(a)) * r1 * 0.62
        by = c + math.sin(math.radians(a)) * r1 * 0.62
        d.ellipse([bx - 6 * SS, by - 6 * SS, bx + 6 * SS, by + 6 * SS], fill=(0x8E, 0x2E, 0x1C))
    # Specular dot.
    d.ellipse([c - r1 * 0.55, c - r1 * 0.62, c - r1 * 0.3, c - r1 * 0.38], fill=(0xFF, 0xC2, 0x9A))
    # Tow eye on top.
    d.ellipse([c - 11 * SS, c - r - 12 * SS, c + 11 * SS, c - r + 10 * SS], outline=OUTLINE, width=6 * SS)
    return im


def plume(length, width):
    im = Image.new('RGBA', (int(width * 2), int(length + width)), (0, 0, 0, 0))
    w, h = im.size
    for col, scale, a in (((0x00, 0xB4, 0xD8), 1.0, 150), ((0x9F, 0xF3, 0xFF), 0.62, 230), ((255, 255, 255), 0.3, 255)):
        m = Image.new('L', im.size, 0)
        hw = width * scale
        ImageDraw.Draw(m).polygon(
            [(w / 2 - hw / 2, 0), (w / 2 + hw / 2, 0), (w / 2, length * (0.55 + 0.45 * scale))], fill=a)
        ImageDraw.Draw(m).ellipse([w / 2 - hw / 2, -hw / 2, w / 2 + hw / 2, hw / 2], fill=a)
        m = m.filter(ImageFilter.GaussianBlur(width * 0.12))
        im.paste((*col, 255), (0, 0), ImageChops.lighter(m, Image.new('L', im.size, 0)))
    return im


def subject():
    """Ship + plume + taut rope + pod on a transparent canvas (cropped later)."""
    W = 2 * N
    out = Image.new('RGBA', (W, W), (0, 0, 0, 0))
    ship = Image.open(os.path.join(ROOT, 'assets', 'ship.png')).convert('RGBA')
    ship = ship.crop(ship.getbbox())  # hull 58..198, nose y 24, nozzle y 181
    sw = int(N * 0.46)
    sh = int(ship.height * sw / ship.width)
    ship = ship.resize((sw, sh), Image.LANCZOS)
    tilt = math.radians(14)  # nose to the right: banking through the gap

    # Ship-local frame: origin at the ship centre, y down, rotated by tilt.
    cx, cy = W * 0.52, W * 0.40

    def to_canvas(lx, ly):
        return (cx + lx * math.cos(tilt) - ly * math.sin(tilt),
                cy + lx * math.sin(tilt) + ly * math.cos(tilt))

    # Pod hangs below and slightly behind (left of) the ship.
    nozzle = to_canvas(0, sh * 0.5)
    pr = N * 0.13
    px, py = nozzle[0] - N * 0.13, nozzle[1] + N * 0.42

    # Rope from the ship rear (just above the nozzle) to the pod's tow eye.
    ax, ay = to_canvas(-sw * 0.06, sh * 0.40)
    rope = ImageDraw.Draw(out)
    end = (px, py - pr - 2 * SS)
    rope.line([(ax, ay), end], fill=(*OUTLINE, 255), width=16 * SS)
    rope.line([(ax, ay), end], fill=(*ROPE, 255), width=8 * SS)

    pod = cargo(pr)
    out.alpha_composite(pod, (int(px - pod.width / 2), int(py - pod.height / 2)))

    # Ship + plume in a local box, rotated about the ship centre.
    pl = plume(sh * 0.55, sw * 0.18)
    box = Image.new('RGBA', (sw * 3, sh * 3), (0, 0, 0, 0))
    bx, by = sw, sh  # ship top-left inside the box; box centre = ship centre + (0, sh/2)
    box.alpha_composite(pl, (int(bx + sw / 2 - pl.width / 2), int(by + sh * 0.95)))
    box.alpha_composite(ship, (bx, by))
    rot = box.rotate(-math.degrees(tilt), resample=Image.BICUBIC, center=(bx + sw / 2, by + sh / 2))
    out.alpha_composite(rot, (int(cx - bx - sw / 2), int(cy - by - sh / 2)))
    return out


def fit_center(im, frac):
    """Scale the opaque content of im to fit in frac of the canvas, centred."""
    bbox = im.split()[3].point(lambda v: 255 if v > 24 else 0).getbbox()
    crop = im.crop(bbox)
    k = frac * N / max(crop.width, crop.height)
    crop = crop.resize((round(crop.width * k), round(crop.height * k)), Image.LANCZOS)
    out = Image.new('RGBA', (N, N), (0, 0, 0, 0))
    out.alpha_composite(crop, ((N - crop.width) // 2, (N - crop.height) // 2))
    return out


def down(im, size=1024):
    return im.resize((size, size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    bg = background()
    subj = subject()
    full = bg.copy()
    full.alpha_composite(fit_center(subj, 0.80))
    down(full).convert('RGB').save(os.path.join(OUT, 'icon_1024.png'))
    down(full).resize((512, 512), Image.LANCZOS).save(os.path.join(OUT, 'play_icon_512.png'))
    down(bg).convert('RGB').save(os.path.join(OUT, 'icon_bg_1024.png'))

    # Adaptive icon: flutter_launcher_icons insets the foreground by 16% of the
    # 108dp canvas, leaving ~73dp; 66dp of that is always visible -> ~86%.
    fg = fit_center(subj, 0.86)
    down(fg).save(os.path.join(OUT, 'icon_fg_1024.png'))
    alpha = fg.split()[3]
    mono = Image.new('RGBA', (N, N), (255, 255, 255, 0))
    mono.putalpha(alpha.point(lambda v: 255 if v > 110 else 0))
    down(mono).save(os.path.join(OUT, 'icon_mono_1024.png'))

    tinted = Image.new('RGBA', (N, N), (0, 0, 0, 255))
    tinted.alpha_composite(fit_center(subj, 0.80).convert('LA').convert('RGBA'))
    down(tinted).convert('L').save(os.path.join(OUT, 'icon_tinted_1024.png'))
    dark = fit_center(subj, 0.80)
    down(dark).save(os.path.join(OUT, 'icon_dark_1024.png'))

    # Android 12 splash: icon inside a 2/3-diameter circle of a 288dp canvas.
    down(fit_center(subj, 0.60)).save(os.path.join(OUT, 'splash_logo.png'))
    print('wrote', OUT)


if __name__ == '__main__':
    main()
