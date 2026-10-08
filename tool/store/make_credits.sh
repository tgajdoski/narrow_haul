#!/usr/bin/env bash
# "Delivered by" head shots: square crop around each face, 512 px JPEG.
#   tool/store/make_credits.sh
# Sources (full-size photos) live in art_src/deliveredBy/ and are not bundled.
# The round mask is applied at runtime (ClipOval in delivered_by_screen.dart).
# Crop box per photo: side, top, left in source pixels — tune by eye.
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=art_src/deliveredBy
OUT=assets/credits
mkdir -p "$OUT"

crop() { # name side top left
  local name=$1 side=$2 top=$3 left=$4
  sips --cropToHeightWidth "$side" "$side" --cropOffset "$top" "$left" \
    "$SRC/$name.jpg" --out "$OUT/$name.jpg" >/dev/null
  sips -Z 512 -s format jpeg -s formatOptions 85 "$OUT/$name.jpg" \
    --out "$OUT/$name.jpg" >/dev/null
  echo "$OUT/$name.jpg $(wc -c < "$OUT/$name.jpg") bytes"
}

crop mare 940 191 95
crop mila 1480 0 740
crop nina 1850 412 746
