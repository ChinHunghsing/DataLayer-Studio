#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT_DIR="$(cd "$PROJECT_DIR/.." && pwd)"
SOURCE_DIR="$ROOT_DIR/assets/marketing/video"
WEBSITE_ASSETS="$ROOT_DIR/landing-page/assets"
GENERATED_DIR="$PROJECT_DIR/public/generated"

mkdir -p "$GENERATED_DIR"

for command in ffmpeg ffprobe; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "缺少依赖：$command" >&2
    exit 1
  fi
done

ffmpeg -y -hide_banner -loglevel error \
  -i "$SOURCE_DIR/无数据层跑步视频.mp4" \
  -map 0:v:0 -vf 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,format=yuv420p' \
  -an -c:v libx264 -preset medium -crf 16 -movflags +faststart \
  "$GENERATED_DIR/run-before.mp4"

ffmpeg -y -hide_banner -loglevel error \
  -i "$SOURCE_DIR/有数据层跑步视频.mp4" \
  -map 0:v:0 -vf 'scale=1920:1080:force_original_aspect_ratio=increase,crop=1920:1080,fps=30,format=yuv420p' \
  -an -c:v libx264 -preset medium -crf 16 -movflags +faststart \
  "$GENERATED_DIR/run-after.mp4"

ffmpeg -y -hide_banner -loglevel error \
  -i "$SOURCE_DIR/app操作录屏.mov" \
  -map 0:v:0 -vf 'scale=1920:-2,fps=30,format=yuv420p' \
  -an -c:v libx264 -preset medium -crf 17 -movflags +faststart \
  "$GENERATED_DIR/app-demo.mp4"

cp "$SOURCE_DIR/AppIcon.png" "$GENERATED_DIR/app-icon.png"
cp "$WEBSITE_ASSETS/app-editor-714.webp" "$GENERATED_DIR/editor.webp"
cp "$WEBSITE_ASSETS/app-components-714.webp" "$GENERATED_DIR/components.webp"
cp "$WEBSITE_ASSETS/app-export-714.webp" "$GENERATED_DIR/export.webp"

# 原始素材没有独立音乐或音效；这里使用 FFmpeg 合成克制的原创电子氛围声轨。
ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i 'sine=frequency=55:duration=30:sample_rate=48000' \
  -f lavfi -i 'sine=frequency=110:duration=30:sample_rate=48000' \
  -f lavfi -i 'sine=frequency=164.81:duration=30:sample_rate=48000' \
  -f lavfi -i 'sine=frequency=220:duration=30:sample_rate=48000' \
  -f lavfi -i 'anoisesrc=color=pink:duration=30:sample_rate=48000' \
  -filter_complex "[0:a]lowpass=f=120,apulsator=hz=2:amount=0.82,volume=0.10[bass];[1:a]tremolo=f=0.22:d=0.48,volume=0.026[p1];[2:a]tremolo=f=0.17:d=0.42,volume=0.020[p2];[3:a]apulsator=hz=4:amount=0.92,volume=0.010[arp];[4:a]highpass=f=5200,apulsator=hz=4:amount=0.96,volume=0.006[air];[bass][p1][p2][arp][air]amix=inputs=5:normalize=0,loudnorm=I=-23:TP=-6:LRA=4,afade=t=in:st=0:d=1.2,afade=t=out:st=27:d=3,alimiter=limit=0.8[music]" \
  -map '[music]' -c:a pcm_s16le -ar 48000 "$GENERATED_DIR/music.wav"

ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i 'anoisesrc=color=pink:duration=0.8:sample_rate=48000' \
  -af 'highpass=f=900,lowpass=f=7600,afade=t=in:st=0:d=0.08,afade=t=out:st=0.22:d=0.58,volume=0.22' \
  -c:a pcm_s16le -ar 48000 "$GENERATED_DIR/whoosh.wav"

ffmpeg -y -hide_banner -loglevel error \
  -f lavfi -i 'aevalsrc=0.12*sin(2*PI*(260*t+680*t*t)):s=48000:d=0.55' \
  -af 'afade=t=in:st=0:d=0.04,afade=t=out:st=0.18:d=0.37,volume=0.35' \
  -c:a pcm_s16le -ar 48000 "$GENERATED_DIR/accent.wav"

echo "素材已准备：$GENERATED_DIR"
