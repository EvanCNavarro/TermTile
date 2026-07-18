#!/usr/bin/env bash
# install-app.sh - build (stable identity if the dev cert is present) and install TermTile.app, then
# relaunch. Installs to /Applications (the standard, reliably Spotlight-indexed + LaunchServices-known
# location - so the app is findable in Open panels / the Privacy permission pickers, exactly where a
# user who followed the README "drag to /Applications" would put it). ~/Applications is NOT reliably
# indexed, which made the app invisible in those pickers. Set TERMTILE_INSTALL_DIR to override.
# After copying, we force a Spotlight import + LaunchServices registration so a freshly-built bundle
# shows up immediately rather than after Spotlight eventually notices it.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$(./scripts/build-app.sh | tail -1)"
DEST="${TERMTILE_INSTALL_DIR:-/Applications}"
LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

mkdir -p "$DEST"
pkill -x TermTile 2>/dev/null || true
# Clean up the old ~/Applications location if we're migrating away from it.
rm -rf "$HOME/Applications/TermTile" 2>/dev/null || true
rm -rf "$DEST/TermTile.app"
ditto "$APP" "$DEST/TermTile.app"

# Make it immediately findable in Open/permission pickers (not after Spotlight eventually catches up).
"$LSREG" -f "$DEST/TermTile.app" 2>/dev/null || true
mdimport "$DEST/TermTile.app" 2>/dev/null || true

open "$DEST/TermTile.app"
echo "$DEST/TermTile.app"
