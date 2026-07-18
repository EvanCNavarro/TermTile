#!/usr/bin/env bash
# build-app.sh - assemble the SPM binary into a signed distributable TermTile.app.
#
# #13a (ADAPTs RememBar's build-remembar-app.sh - audit sec 2/sec 3). Everything env-overridable so
# e2e/CI reuse the SAME build path (no drift). Menu-bar-only (LSUIElement); Sparkle is embedded,
# so signing is an inside-out pass with hardened runtime enabled and NO --deep on sign operations
# (audit sec 2: --deep can corrupt nested signatures), then verified --deep --strict.
# CFBundleVersion is the monotonic commit count by default, NEVER dots-stripped (audit sec 8.5:
# 0.10.1->0101 collides). TERMTILE_BUILD_NUMBER is reserved for local downgrade/update-indicator
# verification builds that must compare below an already-published Sparkle appcast.
set -euo pipefail

APP_NAME="${APP_NAME:-TermTile}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.termtile}"
CONFIGURATION="${CONFIGURATION:-release}"
SHORT_VERSION="${SHORT_VERSION:-0.1.0}"
DIST_DIR="${DIST_DIR:-dist}"
ICON_SRC="${ICON_SRC:-Sources/TermTile/Resources/AppIcon.png}"
# Sparkle appcast URL (Info.plist SUFeedURL) - 404s until the first release publishes appcast.xml.
SU_FEED_URL="${SU_FEED_URL:-https://github.com/EvanCNavarro/TermTile/releases/latest/download/appcast.xml}"
# Sparkle EdDSA PUBLIC key - safe to commit. The matching private key lives in the login Keychain
# (svce https://sparkle-project.org) and signs each update via sign_update; a bad/missing signature
# is refused by Sparkle.
SU_PUBLIC_ED_KEY="${SU_PUBLIC_ED_KEY:-mIAUkTNj+kRPNqkAX1Z1EaqFqyLaFQ37pwEIGduj4Zs=}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Monotonic build number from commit count - padded-safe, never dots-stripped (audit sec 8.5).
if [ -n "${TERMTILE_BUILD_NUMBER:-}" ]; then
	if [ "${GITHUB_ACTIONS:-false}" = "true" ]; then
		echo "TERMTILE_BUILD_NUMBER is local-only and cannot be used in GitHub Actions" >&2
		exit 1
	fi
	[[ "$TERMTILE_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || {
		echo "TERMTILE_BUILD_NUMBER must be a positive integer (got: $TERMTILE_BUILD_NUMBER)" >&2
		exit 1
	}
	BUILD_NUMBER="$TERMTILE_BUILD_NUMBER"
else
	BUILD_NUMBER="$(git rev-list --count HEAD)"
fi

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

# Menu-bar template glyph -> Contents/Resources (a plain file, loaded via Bundle.main, sealed by the
# app signature). NOT an SPM resource bundle: a flat .bundle in Contents/MacOS breaks codesign.
GLYPH_SRC="$ROOT/Resources/TermTileMenuGlyph.pdf"
[ -f "$GLYPH_SRC" ] || { echo "menu-bar glyph not found at $GLYPH_SRC" >&2; exit 1; }
cp "$GLYPH_SRC" "$APP/Contents/Resources/TermTileMenuGlyph.pdf"

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
	<key>SUFeedURL</key><string>$SU_FEED_URL</string>
	<key>SUPublicEDKey</key><string>$SU_PUBLIC_ED_KEY</string>
	<key>SUEnableAutomaticChecks</key><false/>
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
	# Also drop the raw PNG in Contents/Resources so the shared update dialog resolves it via
	# Bundle.packagedResourceURL("AppIcon","png") in the shipped app (Bundle.main), not just DEBUG.
	cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.png" >&2
fi

# Embed Sparkle.framework - REQUIRED whenever the binary links Sparkle: a linked
# @rpath/Sparkle.framework with nothing in Contents/Frameworks dyld-crashes at launch (audit sec 1).
# `ditto` preserves the framework's version symlinks.
SPARKLE_FRAMEWORK="$ROOT/Vendor/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
[ -d "$SPARKLE_FRAMEWORK" ] || "$(dirname "${BASH_SOURCE[0]}")/fetch-sparkle.sh" >&2
[ -d "$SPARKLE_FRAMEWORK" ] || { echo "Sparkle.framework missing (run scripts/fetch-sparkle.sh)" >&2; exit 1; }
FRAMEWORKS_DIR="$APP/Contents/Frameworks"
SPARKLE_DST="$FRAMEWORKS_DIR/Sparkle.framework"
SPARKLE_V="$SPARKLE_DST/Versions/B"
mkdir -p "$FRAMEWORKS_DIR"
ditto "$SPARKLE_FRAMEWORK" "$SPARKLE_DST"

# Inside-out sign (no --deep). Sign the deepest nested Sparkle code FIRST (its XPC services /
# helpers individually - --deep can corrupt those signatures, per Sparkle's docs), then the
# framework, then the app binary, then the bundle; verify strict.
# Signing identity. A STABLE keychain identity keeps the app's code identity constant across rebuilds,
# so macOS TCC grants (Accessibility, Input Monitoring) survive - ad-hoc ("-") gets a fresh cdhash every
# build and silently resets every grant (#13c). Resolution order: explicit TERMTILE_SIGN_IDENTITY wins;
# else auto-use the local "TermTile Dev Signing" identity IF it's in the keychain (so a dev machine that
# ran scripts/setup-dev-signing.sh gets stable grants with zero ceremony); else fall back to ad-hoc (CI /
# a fresh clone without the cert). This default is why grants no longer break on every local rebuild.
DEFAULT_DEV_IDENTITY="TermTile Dev Signing"
if [ -n "${TERMTILE_SIGN_IDENTITY:-}" ]; then
	SIGN_IDENTITY="$TERMTILE_SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$DEFAULT_DEV_IDENTITY"; then
	SIGN_IDENTITY="$DEFAULT_DEV_IDENTITY"
else
	SIGN_IDENTITY="-"
fi
echo "build-app.sh: signing with identity: $SIGN_IDENTITY" >&2
xattr -cr "$APP"
DISABLE_LIBRARY_VALIDATION="${TERMTILE_DISABLE_LIBRARY_VALIDATION:-auto}"
case "$DISABLE_LIBRARY_VALIDATION" in
	auto)
		case "$SIGN_IDENTITY" in
			"Developer ID Application:"*) DISABLE_LIBRARY_VALIDATION=0 ;;
			*) DISABLE_LIBRARY_VALIDATION=1 ;;
		esac
		;;
	1|true|TRUE|yes|YES) DISABLE_LIBRARY_VALIDATION=1 ;;
	0|false|FALSE|no|NO) DISABLE_LIBRARY_VALIDATION=0 ;;
	*)
		echo "TERMTILE_DISABLE_LIBRARY_VALIDATION must be auto, 1, or 0 (got: $DISABLE_LIBRARY_VALIDATION)" >&2
		exit 1
		;;
esac

ENTITLEMENTS=""
if [ "$DISABLE_LIBRARY_VALIDATION" = "1" ]; then
	ENTITLEMENTS="$APP/Contents/Resources/TermTile.entitlements"
	cat > "$ENTITLEMENTS" <<ENTITLEMENTS_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.cs.disable-library-validation</key>
	<true/>
</dict>
</plist>
ENTITLEMENTS_EOF
	plutil -lint "$ENTITLEMENTS" >&2
	echo "build-app.sh: disabling library validation for local embedded Sparkle load" >&2
else
	echo "build-app.sh: keeping hardened-runtime library validation enabled" >&2
fi
sign_code() {
	codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
}
sign_app_code() {
	if [ -n "$ENTITLEMENTS" ]; then
		codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$1" >&2
	else
		codesign --force --options runtime --sign "$SIGN_IDENTITY" "$1" >&2
	fi
}

sign_code "$SPARKLE_V/XPCServices/Downloader.xpc"
sign_code "$SPARKLE_V/XPCServices/Installer.xpc"
sign_code "$SPARKLE_V/Autoupdate"
sign_code "$SPARKLE_V/Updater.app"
sign_code "$SPARKLE_DST"
# NB: the SPM resource bundle (glyph) is a FLAT resource bundle (no Info.plist / no Mach-O), so it is
# NOT code-signed on its own - the outer app signature below seals it as a resource.
sign_app_code "$APP/Contents/MacOS/$APP_NAME"
sign_app_code "$APP"
codesign --verify --deep --strict "$APP" >&2

# Last stdout line = the .app path, so callers can `tail -1` (RememBar convention).
echo "$APP"
