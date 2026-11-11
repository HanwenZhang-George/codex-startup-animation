#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/dist/Codex Dragon.app"
DESTINATION="$HOME/Applications/Codex Dragon.app"
if [[ ! -d "$SOURCE" ]]; then "$ROOT/scripts/build.sh"; fi
mkdir -p "$HOME/Applications"
if [[ -e "$DESTINATION" ]]; then
  [[ "${1:-}" == --update && ! -L "$DESTINATION" ]] || { echo "安装位置已存在，未覆盖：$DESTINATION" >&2; exit 1; }
  ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DESTINATION/Contents/Info.plist")"
  [[ "$ID" == local.codex-dragon.launcher ]] || { echo "已有应用身份不符，未覆盖。" >&2; exit 1; }
  if /usr/bin/pgrep -x CodexDragon >/dev/null; then echo "请先退出菜单栏的龙娘启动器，再升级。" >&2; exit 1; fi
fi
STAGE="$(/usr/bin/mktemp -d "$HOME/Applications/.codex-dragon-update.XXXXXX")"
trap '/bin/rm -rf "$STAGE"' EXIT
/usr/bin/ditto "$SOURCE" "$STAGE/Codex Dragon.app"
/usr/bin/codesign --verify --deep --strict "$STAGE/Codex Dragon.app"
if [[ -e "$DESTINATION" ]]; then
  BACKUPS="$HOME/Library/Application Support/Codex Dragon/Backups"
  mkdir -p "$BACKUPS"
  BACKUP="$BACKUPS/Codex Dragon-$(/usr/bin/uuidgen).app"
  /bin/mv "$DESTINATION" "$BACKUP"
  if ! /bin/mv "$STAGE/Codex Dragon.app" "$DESTINATION"; then /bin/mv "$BACKUP" "$DESTINATION"; exit 1; fi
else
  /bin/mv "$STAGE/Codex Dragon.app" "$DESTINATION"
fi
/usr/bin/open -Ra "$DESTINATION"
echo "已安装：$DESTINATION"
