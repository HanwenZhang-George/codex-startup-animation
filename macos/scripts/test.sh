#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
/usr/bin/xcrun swiftc -swift-version 5 -parse-as-library \
  -framework AppKit -framework AVFoundation \
  "$ROOT/Sources/Core.swift" "$ROOT/tests/CoreTests.swift" -o "$ROOT/build/CoreTests"
"$ROOT/build/CoreTests"
APP="$ROOT/dist/Codex Dragon.app"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$APP"
ARCHITECTURES="$(/usr/bin/lipo -archs "$APP/Contents/MacOS/CodexDragon")"
[[ "$ARCHITECTURES" == *arm64* && "$ARCHITECTURES" == *x86_64* ]]
if [[ "${1:-}" == --offline ]]; then
  "$APP/Contents/MacOS/CodexDragon" --diagnose-media
else
  "$APP/Contents/MacOS/CodexDragon" --diagnose
fi
