#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$ROOT/build"
TEMPORARY="$(/usr/bin/mktemp -d "$ROOT/build/package.XXXXXX")"
trap '/bin/rm -rf "$TEMPORARY"' EXIT
STAGE="$TEMPORARY/Codex Dragon for Mac"
mkdir -p "$STAGE"
/usr/bin/ditto "$ROOT/dist/Codex Dragon.app" "$STAGE/Codex Dragon.app"
if [[ -d "$ROOT/dist/ChatGPT.app" ]]; then /usr/bin/ditto "$ROOT/dist/ChatGPT.app" "$STAGE/ChatGPT.app"; fi
cp "$ROOT/Preview.command" "$STAGE/Preview.command"
cp "$ROOT/README.md" "$STAGE/README.md"
cp "$ROOT/VERIFICATION.md" "$STAGE/VERIFICATION.md"
cp "$ROOT/config.example.json" "$STAGE/config.example.json"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ROOT/dist/Codex-Dragon-macOS-universal.zip"
echo "已打包：$ROOT/dist/Codex-Dragon-macOS-universal.zip"
