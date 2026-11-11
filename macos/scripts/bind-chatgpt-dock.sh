#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTRY="$HOME/Applications/ChatGPT.app"
STATE="$HOME/Library/Application Support/Codex Dragon/dock-binding.plist"
if [[ "${1:-}" == --restore ]]; then
  /usr/bin/xcrun swift "$ROOT/scripts/dock-entry.swift" restore "$ENTRY" "$STATE"
else
  [[ -d "$ROOT/dist/ChatGPT.app" ]] || "$ROOT/scripts/build-entry.sh"
  [[ ! -L "$ENTRY" ]] || { echo "安装位置是符号链接，未覆盖。" >&2; exit 1; }
  if /usr/bin/pgrep -x ChatGPTEntry >/dev/null; then echo "ChatGPT 动画入口正在运行，请稍后重试。" >&2; exit 1; fi
  if [[ -e "$ENTRY" ]]; then
    ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$ENTRY/Contents/Info.plist")"
    [[ "$ID" == local.codex-dragon.chatgpt-entry ]] || { echo "目标位置已有其他 ChatGPT，未覆盖。" >&2; exit 1; }
  fi
  mkdir -p "$HOME/Applications"
  STAGE="$(/usr/bin/mktemp -d "$HOME/Applications/.chatgpt-entry-update.XXXXXX")"
  trap '/bin/rm -rf "$STAGE"' EXIT
  /usr/bin/ditto "$ROOT/dist/ChatGPT.app" "$STAGE/ChatGPT.app"
  /usr/bin/codesign --verify --deep --strict "$STAGE/ChatGPT.app"
  ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGE/ChatGPT.app/Contents/Info.plist")"
  [[ "$ID" == local.codex-dragon.chatgpt-entry ]] || { echo "构建入口身份不符，已停止。" >&2; exit 1; }
  if [[ -e "$ENTRY" ]]; then
    BACKUPS="$HOME/Library/Application Support/Codex Dragon/Backups"
    mkdir -p "$BACKUPS"
    BACKUP="$BACKUPS/ChatGPT-$(/usr/bin/uuidgen).app"
    /bin/mv "$ENTRY" "$BACKUP"
    if ! /bin/mv "$STAGE/ChatGPT.app" "$ENTRY"; then /bin/mv "$BACKUP" "$ENTRY"; exit 1; fi
  else
    /bin/mv "$STAGE/ChatGPT.app" "$ENTRY"
  fi
  /usr/bin/xcrun swift "$ROOT/scripts/dock-entry.swift" bind "$ENTRY" "$STATE"
fi
/usr/bin/killall Dock || true
