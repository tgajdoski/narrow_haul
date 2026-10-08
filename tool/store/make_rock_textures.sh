#!/usr/bin/env bash
# Per-world rock textures from the cave wall tile sheet (needs ImageMagick 7).
#   tool/store/make_rock_textures.sh
# Source: art_src/tiles/rock_tiles_src.png (512×512, 8×8 cells of 64 px; not
# bundled). Only the solid interior cells are used: caves are smooth contours,
# so the sheet's edge/corner/slope pieces have nowhere to go. The cells are
# shaved to hide their outlines and laid out as a 4×4 mosaic (256 px = the
# default 8 m ThemeSpec.rockTextureMeters, tiles seamlessly), then recoloured
# to each world's ThemeSpec.rockFill.
# Output: assets/themes/<id>/rock.png, picked up by ThemeAssets.rock.
set -euo pipefail
cd "$(dirname "$0")/../.."
SRC=art_src/tiles/rock_tiles_src.png
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

magick "$SRC" -crop 64x64 +repage "$TMP/cell_%02d.png"
# Row 0 and row 7, columns 1–6 (cell 63 carries a watermark).
for i in 01 02 03 04 05 06 57 58 59 60 61 62; do
  magick "$TMP/cell_$i.png" -background '#1D3461' -flatten -shave 3x3 \
    -resize '64x64!' "$TMP/in_$i.png"
done
cells=()
for i in 01 57 03 60 58 05 61 02 62 04 59 06 59 61 02 57; do
  cells+=("$TMP/in_$i.png")
done
magick montage "${cells[@]}" -tile 4x4 -geometry 64x64+0+0 "$TMP/mosaic.png"

# world id : ThemeSpec.rockFill (lib/game/level/theme_spec.dart)
for w in tutorial:1D3461 alien:3B2166 mine:4A3524 ice:35617F lava:4A1B12 \
  orbit:2A2F45 redoubt:363C47; do
  id=${w%%:*}
  out=assets/themes/$id/rock.png
  mkdir -p "assets/themes/$id"
  magick "$TMP/mosaic.png" -colorspace gray -normalize \
    +level-colors "black,#${w##*:}" -modulate 170 -colors 256 \
    -define png:color-type=3 -strip "$out"
  rm -f "assets/themes/$id/.gitkeep"
  echo "$out $(wc -c < "$out") bytes"
done
