#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Codex Dragon.app"
if [[ ! -d "$APP" ]]; then APP="$ROOT/dist/Codex Dragon.app"; fi
if [[ ! -d "$APP" ]]; then APP="$HOME/Applications/Codex Dragon.app"; fi
/usr/bin/open -a "$APP" --args --preview
