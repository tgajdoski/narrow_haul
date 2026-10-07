#!/usr/bin/env bash
# Cuts store videos from one gameplay recording (needs ffmpeg: brew install ffmpeg).
#
# Record on a real phone in release mode (smooth, full gravity):
#   flutter run --release -d "<your iPhone>"
#   then Control Centre → Screen Recording (or QuickTime → New Movie Recording
#   → pick the iPhone), fly 3–4 levels with deliveries, stop.
#   AirDrop the .mov to art_src/store/video/raw/.
#
# Usage: tool/store/make_videos.sh <raw.mov> [start_seconds] [length_seconds]
#   start/length pick the best stretch for the 15–30 s App Preview
#   (defaults 0 and 28). Writes art_src/store/video/:
#     preview_iphone.mp4  1920×886   App Store 6.9" App Preview
#     preview_ipad.mp4    1600×1200  App Store 13" iPad App Preview
#     youtube_1080.mp4    1920×1080  Google Play promo video (upload to YouTube)
#     poster.png          frame 5 s in, the App Preview poster frame
#     loop_web.mp4        8 s silent 960 px loop for the website/socials
set -euo pipefail
cd "$(dirname "$0")/../.."

SRC="${1:?usage: make_videos.sh <raw.mov> [start] [length]}"
START="${2:-0}"
LEN="${3:-28}"
OUT=art_src/store/video
mkdir -p "$OUT"
BG=0x0B132B # game backdrop: letterbox colour

command -v ffmpeg >/dev/null || { echo "ffmpeg missing: brew install ffmpeg" >&2; exit 1; }

# Silent stereo track when the recording has none (App Store requires audio).
if ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$SRC" | grep -q .; then
  AUDIO=(-map 0:a:0)
  AIN=()
else
  AIN=(-f lavfi -t "$LEN" -i anullsrc=channel_layout=stereo:sample_rate=44100)
  AUDIO=(-map 1:a:0)
fi

encode() { # <out> <w> <h> [extra -vf suffix]
  local w=$2 h=$3
  ffmpeg -y -ss "$START" -t "$LEN" -i "$SRC" "${AIN[@]}" \
    -map 0:v:0 "${AUDIO[@]}" -shortest \
    -vf "fps=30,scale=${w}:${h}:force_original_aspect_ratio=decrease,pad=${w}:${h}:(ow-iw)/2:(oh-ih)/2:color=${BG},setsar=1${4:-}" \
    -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -b:v 10M -maxrate 12M -bufsize 20M \
    -c:a aac -b:a 256k -ar 44100 -ac 2 -movflags +faststart "$1"
}

encode "$OUT/preview_iphone.mp4" 1920 886
encode "$OUT/preview_ipad.mp4" 1600 1200
encode "$OUT/youtube_1080.mp4" 1920 1080
ffmpeg -y -ss "$(echo "$START + 5" | bc)" -i "$SRC" -frames:v 1 \
  -vf "scale=1920:886:force_original_aspect_ratio=decrease,pad=1920:886:(ow-iw)/2:(oh-ih)/2:color=${BG}" \
  "$OUT/poster.png"
ffmpeg -y -ss "$START" -t 8 -i "$SRC" -an -vf "fps=30,scale=960:-2" \
  -c:v libx264 -pix_fmt yuv420p -crf 26 -movflags +faststart "$OUT/loop_web.mp4"

for f in "$OUT"/*.mp4; do
  printf '%-28s ' "$(basename "$f")"
  ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate:format=duration \
    -of compact=p=0:nk=1 "$f" | tr '\n' ' '
  echo
done
