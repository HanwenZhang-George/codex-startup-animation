#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/dist/ChatGPT.app"
OFFICIAL="${1:-}"
if [[ -z "$OFFICIAL" ]]; then
  for CANDIDATE in /Applications/Codex.app "$HOME/Applications/Codex.app" /Applications/ChatGPT.app "$HOME/Applications/ChatGPT.app"; do
    [[ -f "$CANDIDATE/Contents/Info.plist" ]] || continue
    ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CANDIDATE/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$ID" == com.openai.codex ]]; then OFFICIAL="$CANDIDATE"; break; fi
  done
fi
[[ -n "$OFFICIAL" ]] || { echo "未找到官方应用，请将安装路径作为第一个参数传入。" >&2; exit 1; }
mkdir -p "$ROOT/build" "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  /usr/bin/xcrun swiftc -swift-version 5 -O -parse-as-library \
    -target "$ARCH-apple-macosx13.0" -framework AppKit -framework AVFoundation \
    "$ROOT/Sources/Core.swift" "$ROOT/Sources/ChatGPTEntry.swift" \
    -o "$ROOT/build/ChatGPTEntry-$ARCH"
done
/usr/bin/lipo -create "$ROOT/build/ChatGPTEntry-arm64" "$ROOT/build/ChatGPTEntry-x86_64" \
  -output "$APP/Contents/MacOS/ChatGPTEntry"
/usr/bin/python3 - "$APP" "$OFFICIAL" <<'PY'
import pathlib,plistlib,shutil,sys
app,official=map(pathlib.Path,sys.argv[1:])
metadata=plistlib.loads((official/'Contents/Info.plist').read_bytes())
if metadata.get('CFBundleIdentifier') != 'com.openai.codex':
    raise SystemExit('官方应用身份不符，已停止。')
icon=metadata.get('CFBundleIconFile','')
if not icon.endswith('.icns'): icon += '.icns'
shutil.copy2(official/'Contents/Resources'/icon,app/'Contents/Resources/ChatGPT.icns')
metadata={
 'CFBundleExecutable':'ChatGPTEntry',
 'CFBundleIdentifier':'local.codex-dragon.chatgpt-entry',
 'CFBundleName':'ChatGPT','CFBundleDisplayName':'ChatGPT',
 'CFBundlePackageType':'APPL','CFBundleIconFile':'ChatGPT.icns',
 'CFBundleShortVersionString':'1.1.0','CFBundleVersion':'2',
 'LSMinimumSystemVersion':'13.0','LSUIElement':True,
 'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication'
}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
PY
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
echo "已构建 ChatGPT 动画入口：$APP"
