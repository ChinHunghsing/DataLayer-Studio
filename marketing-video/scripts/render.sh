#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
REMOTION_OUTPUT="$OUTPUT_DIR/promo-30s-16x9.remotion.mp4"
FINAL_OUTPUT="$OUTPUT_DIR/promo-30s-16x9.mp4"

mkdir -p "$OUTPUT_DIR"

"$PROJECT_DIR/scripts/prepare-assets.sh"

cd "$PROJECT_DIR"
npx remotion render src/index.ts Promo30s "$REMOTION_OUTPUT" \
  --codec=h264 \
  --crf=17 \
  --pixel-format=yuv420p \
  --audio-codec=aac \
  --overwrite

# FFmpeg 做最终响度控制、去除多余元数据并生成可直接发布的 MP4。
ffmpeg -y -hide_banner -loglevel error \
  -i "$REMOTION_OUTPUT" \
  -map 0:v:0 -map 0:a:0 \
  -t 30 \
  -vf 'scale=in_range=full:out_range=tv,format=yuv420p' \
  -c:v libx264 -preset slow -crf 17 -color_range tv -r 30 \
  -af 'loudnorm=I=-20:TP=-3:LRA=5' \
  -c:a aac -b:a 192k -ar 48000 \
  -map_metadata -1 -write_tmcd 0 -movflags +faststart -shortest \
  "$FINAL_OUTPUT"

echo "$FINAL_OUTPUT"
