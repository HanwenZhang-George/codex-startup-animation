#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/Codex Dragon.app"
BUILD="$ROOT/build"
if [[ "$(uname -s)" != Darwin ]]; then
  echo "请在 Mac 上构建。" >&2
  exit 1
fi
/usr/bin/xcrun --find swiftc >/dev/null
/usr/bin/python3 "$ROOT/scripts/fetch-media.py" "$@"
mkdir -p "$BUILD" "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  /usr/bin/xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$ARCH-apple-macosx13.0" \
    -framework AppKit -framework AVFoundation \
    "$ROOT/Sources/Core.swift" "$ROOT/Sources/WallpaperBridge.swift" "$ROOT/Sources/Launcher.swift" \
    -o "$BUILD/CodexDragon-$ARCH"
done
/usr/bin/lipo -create "$BUILD/CodexDragon-arm64" "$BUILD/CodexDragon-x86_64" \
  -output "$APP/Contents/MacOS/CodexDragon"
cp "$ROOT/media/"*.mp4 "$APP/Contents/Resources/"
cp "$ROOT/Runtime/bridge.mjs" "$APP/Contents/Resources/bridge.mjs"
cp "$ROOT/Runtime/renderer.js" "$APP/Contents/Resources/renderer.js"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/README.md" "$APP/Contents/Resources/README.md"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo "构建完成：$APP"
