#!/usr/bin/env bash
# Renders every store screenshot set into art_src/store/screenshots/:
#   ios_69/      2868×1320  App Store iPhone 6.9"
#   ios_ipad13/  2752×2064  App Store iPad 13"
#   play_1080/   1920×1080  Google Play phone + tablets
# Usage: tool/store/capture_screenshots.sh [macos|ipad]   (default: both)
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=art_src/store/screenshots
IPAD_SIM="${IPAD_SIM:-iPad Pro 13-inch (M5)}"
TEST=integration_test/store_screenshots_test.dart

run() { # <device> <targets> [extra flutter args]
  local log
  log=$(mktemp)
  flutter test "$TEST" -d "$1" \
    --dart-define=STORE_CAPTURE=true --dart-define=STORE_TARGETS="$2" "${@:3}" | tee "$log"
  local dir
  dir=$(grep -o 'SHOTS_DIR=.*' "$log" | tail -1 | cut -d= -f2)
  [ -n "$dir" ] || { echo "no SHOTS_DIR in output" >&2; exit 1; }
  for t in ${2//,/ }; do
    rm -rf "${OUT:?}/$t"
    mkdir -p "$OUT/$t"
    cp "$dir/$t"/*.png "$OUT/$t/"
    echo "→ $OUT/$t ($(ls "$OUT/$t" | wc -l | tr -d ' ') shots)"
  done
}

what="${1:-all}"
if [ "$what" = all ] || [ "$what" = macos ]; then
  run macos ios_69,play_1080
fi
if [ "$what" = all ] || [ "$what" = ipad ]; then
  udid=$(xcrun simctl list devices available | grep -F "$IPAD_SIM (" | head -1 | grep -oE '[0-9A-F-]{36}')
  [ -n "$udid" ] || { echo "simulator '$IPAD_SIM' not found" >&2; exit 1; }
  xcrun simctl boot "$udid" 2>/dev/null || true
  # The simulator deletes the app's container after the run: write to the host.
  run "$udid" ios_ipad13 --dart-define=STORE_OUT="$(mktemp -d)"
fi
