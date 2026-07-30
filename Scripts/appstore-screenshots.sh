#!/usr/bin/env bash
set -euo pipefail

# Captures screenshots from the booted iOS Simulator and resizes them to
# App Store Connect's legacy "6.5" Display" pixel requirements. Current
# Xcode simulators (iPhone 15+) no longer ship device types that render
# natively at these sizes, so we capture at whatever the booted sim's
# native resolution is and force-resize — the aspect ratio drift versus
# the required sizes is under 0.5%, imperceptible in practice.
#
# Accepted sizes per App Store Connect: 1242x2688, 2688x1242, 1284x2778, 2778x1284
#
# Usage:
#   Scripts/appstore-screenshots.sh [output_dir] [width] [height]
#
# Defaults: output_dir=AppStoreScreenshots  width=1284  height=2778
#
# Run it, then for each screen: navigate the app in Simulator, switch back
# to this terminal, press Enter to capture. Type 'q' to stop.

OUT_DIR="${1:-AppStoreScreenshots}"
WIDTH="${2:-1284}"
HEIGHT="${3:-2778}"

mkdir -p "$OUT_DIR"

BOOTED_ID=$(xcrun simctl list devices booted | grep -Eo '[0-9A-F-]{36}' | head -n1)
if [[ -z "$BOOTED_ID" ]]; then
  echo "No booted simulator found. Boot one in Simulator.app first." >&2
  exit 1
fi

DEVICE_NAME=$(xcrun simctl list devices booted | grep "$BOOTED_ID" | sed -E 's/^ *(.*) \([0-9A-F-]{36}\).*/\1/')
echo "Capturing from: $DEVICE_NAME"
echo "Target size:    ${WIDTH}x${HEIGHT}"
echo "Output dir:     $OUT_DIR"
echo

index=1
while true; do
  read -rp "Navigate the app to the next screen, then press Enter to capture (or 'q' to quit): " ans
  if [[ "$ans" == "q" || "$ans" == "Q" ]]; then
    break
  fi

  num=$(printf '%02d' "$index")
  raw="$OUT_DIR/raw_${num}.png"
  final="$OUT_DIR/screenshot_${num}_${WIDTH}x${HEIGHT}.png"

  xcrun simctl io "$BOOTED_ID" screenshot "$raw" >/dev/null
  sips -z "$HEIGHT" "$WIDTH" "$raw" --out "$final" >/dev/null
  rm "$raw"

  echo "Saved $final"
  index=$((index + 1))
done

echo "Done. $((index - 1)) screenshot(s) saved to $OUT_DIR"
