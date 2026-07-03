#!/usr/bin/env bash
# install-app.sh - build (stable identity if TERMTILE_SIGN_IDENTITY is set) and install
# TermTile.app to ~/Applications/TermTile/ (RememBar convention). Relaunches the app.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(./scripts/build-app.sh | tail -1)"
DEST="$HOME/Applications/TermTile"
mkdir -p "$DEST"
pkill -x TermTile 2>/dev/null || true
rm -rf "$DEST/TermTile.app"
ditto "$APP" "$DEST/TermTile.app"
open "$DEST/TermTile.app"
echo "$DEST/TermTile.app"
