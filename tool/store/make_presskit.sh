#!/usr/bin/env bash
# Builds the press kit served at https://zafrk.com/narrow-haul/press from the
# store art (macOS sips + zip; ffmpeg for the loop). Writes website/press/:
#   shot_01…08.jpg          1280 px screenshots shown on the page
#   icon_512.png, feature.jpg, poster.jpg
#   loop.mp4                8 s silent gameplay loop (from youtube_1080.mp4)
#   trailer.mp4             the App Preview cut (1920×886, with sound)
#   narrow-haul-presskit.zip  full-size screenshots, icons, feature graphic,
#                           poster and facts.txt
# The mp4s and the zip are gitignored; website/deploy.sh runs this when they're
# missing. Re-run it after new screenshots or videos.
#
# Usage: tool/store/make_presskit.sh
set -euo pipefail
cd "$(dirname "$0")/../.."

STORE=art_src/store
SHOTS=$STORE/screenshots/play_1080
OUT=website/press
mkdir -p "$OUT"

# Page screenshots, in the order the page shows them.
PICKS=(01_alien_05 04_lava_03 05_orbit_02 06_redoubt_02 07_alien_03 02_mine_03 11_garage 10_level_complete)
i=1
for name in "${PICKS[@]}"; do
  sips -s format jpeg -s formatOptions 78 --resampleWidth 1280 \
    "$SHOTS/$name.png" --out "$(printf '%s/shot_%02d.jpg' "$OUT" "$i")" >/dev/null
  i=$((i + 1))
done
cp art_src/icon/play_icon_512.png "$OUT/icon_512.png"
sips -s format jpeg -s formatOptions 82 "$STORE/feature_graphic_1024x500.png" --out "$OUT/feature.jpg" >/dev/null
sips -s format jpeg -s formatOptions 80 --resampleWidth 1280 "$STORE/video/poster.png" --out "$OUT/poster.jpg" >/dev/null

if command -v ffmpeg >/dev/null && [ -f "$STORE/video/youtube_1080.mp4" ]; then
  ffmpeg -v error -y -ss 2 -t 8 -i "$STORE/video/youtube_1080.mp4" -an -vf "fps=30,scale=960:-2" \
    -c:v libx264 -pix_fmt yuv420p -crf 26 -movflags +faststart "$OUT/loop.mp4"
fi
if [ -f "$STORE/video/upload/preview_iphone.mp4" ]; then
  cp "$STORE/video/upload/preview_iphone.mp4" "$OUT/trailer.mp4"
fi

# Download zip: full-size art, no store-review (IAP) screenshots and not
# ice_03 (it is a pause screen).
TMP=$(mktemp -d)
KIT="$TMP/narrow-haul-presskit"
mkdir -p "$KIT/screenshots_1920x1080" "$KIT/screenshots_2868x1320" "$KIT/logo"
for f in "$SHOTS"/*.png; do
  case "$(basename "$f")" in *_iap.png | 03_ice_03.png) continue ;; esac
  cp "$f" "$KIT/screenshots_1920x1080/"
done
for f in "$STORE"/screenshots/ios_69/*.png; do
  case "$(basename "$f")" in *_iap.png | 03_ice_03.png) continue ;; esac
  cp "$f" "$KIT/screenshots_2868x1320/"
done
cp art_src/icon/icon_1024.png art_src/icon/icon_dark_1024.png "$KIT/logo/"
cp "$STORE/feature_graphic_1024x500.png" "$STORE/video/poster.png" "$KIT/"
cat > "$KIT/facts.txt" <<'EOF'
Narrow Haul — press facts

Developer:  Zafrk (solo indie studio)
Platforms:  iOS, Android
Release:    Late 2026
Price:      Free to play with light ads. Full Game unlock $4.99 (all Expeditions,
            no ads between missions). Optional Fleet Pass and ammo packs.
Website:    https://zafrk.com/narrow-haul/
Press page: https://zafrk.com/narrow-haul/press
Contact:    contact@zafrk.com (promo codes on request)

Pitch
A physics cave-flying game in the spirit of Thrust and Gravitar. Hook a cargo
pod on a line, swing it through narrow caverns and land both on the pad.
68 hand-built missions in 7 worlds plus 8 multi-leg Expeditions, six ships that
each fly differently, a story told by radio, and mystery salvage that can save
your run or put a bee in the engine.
EOF
rm -f "$OUT/narrow-haul-presskit.zip"
(cd "$TMP" && zip -qr -X "narrow-haul-presskit.zip" "narrow-haul-presskit")
mv "$TMP/narrow-haul-presskit.zip" "$OUT/"
rm -rf "$TMP"

ls -lh "$OUT"
