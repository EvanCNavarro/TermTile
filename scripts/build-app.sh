#!/usr/bin/env bash
# build-app.sh - assemble the SPM binary into a distributable, ad-hoc-signed TermTile.app.
#
# #13a (ADAPTs RememBar's build-remembar-app.sh - audit sec 2/sec 3). Everything env-overridable so
# e2e/CI reuse the SAME build path (no drift). Menu-bar-only (LSUIElement); no embedded frameworks
# (Sparkle deferred -> #16), so signing is a single inside-out ad-hoc pass, NO --deep (audit sec 2:
# --deep can corrupt nested signatures), verified --deep --strict. CFBundleVersion is the monotonic
# commit count, NEVER dots-stripped (audit sec 8.5: 0.10.1->0101 collides). A stable Developer-ID
# identity (so TCC grants survive rebuilds) is #13c - this ad-hoc build resets the grant per cdhash.
set -euo pipefail

APP_NAME="${APP_NAME:-TermTile}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.termtile}"
CONFIGURATION="${CONFIGURATION:-release}"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
DIST_DIR="${DIST_DIR:-dist}"
ICON_SRC="${ICON_SRC:-Resources/AppIcon.png}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Monotonic build number from commit count - padded-safe, never dots-stripped (audit sec 8.5).
BUILD_NUMBER="$(git rev-list --count HEAD)"

# Build, then locate the product via --show-bin-path (RememBar crown-jewel - never a hardcoded
# path; the flag must ride the SAME -c invocation or it prints the debug dir).
swift build -c "$CONFIGURATION" --product "$APP_NAME" >&2
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
BINARY="$BIN_DIR/$APP_NAME"
[ -x "$BINARY" ] || { echo "built binary not found at $BINARY" >&2; exit 1; }

APP="$DIST_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/$APP_NAME"

# Info.plist (heredoc -> plutil -lint gate). Accessibility (AXIsProcessTrusted) needs NO usage-string.
PLIST="$APP/Contents/Info.plist"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>$APP_NAME</string>
	<key>CFBundleDisplayName</key><string>$APP_NAME</string>
	<key>CFBundleExecutable</key><string>$APP_NAME</string>
	<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>$SHORT_VERSION</string>
	<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
	<key>LSMinimumSystemVersion</key><string>14.0</string>
	<key>LSUIElement</key><true/>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST_EOF
plutil -lint "$PLIST" >&2

# Optional icon (menu-bar app has no dock icon, so purely cosmetic - no-op if no source, YAGNI/#13a).
if [ -f "$ICON_SRC" ]; then
	ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
	for sz in 16 32 128 256 512; do
		sips -z "$sz" "$sz" "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}.png" >&2
		sips -z $((sz*2)) $((sz*2)) "$ICON_SRC" --out "$ICONSET/icon_${sz}x${sz}@2x.png" >&2
	done
	iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" >&2
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$PLIST" >&2 || true
fi

# Ad-hoc, inside-out sign (no --deep). Sign the inner Mach-O first, then the bundle; verify strict.
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/MacOS/$APP_NAME" >&2
codesign --force --sign - "$APP" >&2
codesign --verify --deep --strict "$APP" >&2

# Last stdout line = the .app path, so callers can `tail -1` (RememBar convention).
echo "$APP"
