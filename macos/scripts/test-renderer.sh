#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export NODE_PATH="$ROOT/node_modules"
export CHROME_BIN="${CHROME_BIN:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
mkdir -p "$ROOT/build"
node "$ROOT/tests/modern-layout.mjs"
for TEST in ShellRoutes AsyncLifecycle Transitions; do
  node "$ROOT/../community-v34/tests/Test-Renderer$TEST.cjs" \
    "$ROOT/build/$TEST.json" "$ROOT/media/dragon-wallpaper-ambient-2k-144fps.mp4" "$ROOT/Runtime/renderer.js"
done
node "$ROOT/../community-v34/tests/Test-RendererMediaCycles.cjs" \
  "$ROOT/build/MediaCycles.json" "$ROOT/media/dragon-wallpaper-ambient-2k-144fps.mp4" \
  "$ROOT/media/dragon-wallpaper-particles-1440p48.mp4" "$ROOT/Runtime/renderer.js"
