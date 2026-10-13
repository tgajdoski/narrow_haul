#!/usr/bin/env bash
# Store videos straight from the game, no screen recording: runs
# integration_test/store_video_test.dart on macOS (slow-motion frame capture
# of the storyboard), then cuts them with assemble_store_video.py.
#
# Usage: tool/store/make_store_video.sh [iphone|ipad|youtube ...]   (default: all)
#   Reuse captured frames instead of running the test:
#   FRAMES_iphone=<dir> FRAMES_ipad=<dir> FRAMES_youtube=<dir> tool/store/make_store_video.sh
#   Recapture some scene groups into the existing frames, then re-cut:
#   SCENE_GROUP_LIST="radio,alien,mine redoubt,expedition" tool/store/make_store_video.sh ipad
# Writes art_src/store/video/:
#   preview_iphone.mp4  1920×886   App Store iPhone App Preview (< 30 s)
#   preview_ipad.mp4    1600×1200  App Store 13" iPad App Preview (< 30 s)
#   youtube_1080.mp4    1920×1080  Google Play promo video (upload to YouTube)
#   poster.png          App Preview poster frame (2 s in)
#
# Keep the test app's window visible while it runs: macOS stops drawing a
# covered or minimised window and the capture stalls. The scenes run in small
# groups; a group that stops making frames for STALL seconds is retried.
# Frames (~2 GB a target) go to art_src/store/video/frames/<target>/
# (gitignored); delete them when the videos are final.
set -euo pipefail
cd "$(dirname "$0")/../.."

FFMPEG="${FFMPEG:-$(command -v ffmpeg || echo /opt/homebrew/opt/ffmpeg/bin/ffmpeg)}"
[ -x "$FFMPEG" ] || { echo "ffmpeg missing: brew install ffmpeg" >&2; exit 1; }
export FFMPEG
OUT=art_src/store/video
STALL="${STALL:-180}"
mkdir -p "$OUT"

# Scene groups, one test run each (the intro only plays on the first).
SCENE_GROUPS=(
  intro,hangar,missions,chapter
  radio,alien,mine
  orbit,ice,lava
  redoubt,expedition
  complete,garage
)
# Recapture only some groups: SCENE_GROUP_LIST="radio,alien,mine redoubt,expedition".
[ -z "${SCENE_GROUP_LIST:-}" ] || read -r -a SCENE_GROUPS <<<"$SCENE_GROUP_LIST"

frame_count() { find "$1" -name 'f_*.png' 2>/dev/null | wc -l | tr -d ' '; }

run_group() { # <target> <scenes> <dest dir> → 0 when done
  local log dir pid last=0 still=0 n
  log=$(mktemp)
  caffeinate -dims flutter test integration_test/store_video_test.dart -d macos \
    --dart-define=STORE_CAPTURE=true --dart-define=STORE_VIDEO_TARGET="$1" \
    --dart-define=STORE_VIDEO_SCENES="$2" >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 10
    dir=$(grep -o 'VIDEO_DIR=.*' "$log" | tail -1 | cut -d= -f2 || true)
    [ -n "$dir" ] || continue
    n=$(frame_count "$dir")
    if [ "$n" -gt "$last" ]; then last=$n; still=0; else still=$((still + 10)); fi
    if [ "$still" -ge "$STALL" ]; then
      echo "  stalled at $n frames: retrying $2" >&2
      pkill -f 'narrow_haul.app/Contents/MacOS/narrow_haul' || true
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
  done
  wait "$pid" || { tail -20 "$log" >&2; return 1; }
  grep 'SCENE ' "$log" >&2 || true
  dir=$(grep -o 'VIDEO_DIR=.*' "$log" | tail -1 | cut -d= -f2)
  for s in "$dir"/*/; do
    rm -rf "$3/$(basename "$s")"
    mv "$s" "$3/"
  done
  rm -rf "$(dirname "$dir")"
}

capture() { # <target> → frames dir
  local dest="$OUT/frames/$1" g
  mkdir -p "$dest"
  for g in "${SCENE_GROUPS[@]}"; do
    echo "$1: $g" >&2
    run_group "$1" "$g" "$dest" || run_group "$1" "$g" "$dest" ||
      { echo "$1: $g failed twice" >&2; exit 1; }
  done
  echo "$dest"
}

frames_for() { # <target>
  local var="FRAMES_$1"
  if [ -n "${!var:-}" ]; then echo "${!var}"; else capture "$1"; fi
}

targets=("$@")
[ ${#targets[@]} -gt 0 ] || targets=(iphone ipad youtube)
for t in "${targets[@]}"; do
  dir=$(frames_for "$t")
  case "$t" in
    iphone)
      python3 tool/store/assemble_store_video.py "$dir" preview 1920x886 "$OUT/preview_iphone.mp4"
      "$FFMPEG" -y -v error -ss 2 -i "$OUT/preview_iphone.mp4" -frames:v 1 "$OUT/poster.png"
      ;;
    ipad) python3 tool/store/assemble_store_video.py "$dir" preview 1600x1200 "$OUT/preview_ipad.mp4" ;;
    youtube) python3 tool/store/assemble_store_video.py "$dir" youtube 1920x1080 "$OUT/youtube_1080.mp4" ;;
    *) echo "unknown target $t" >&2; exit 1 ;;
  esac
done
