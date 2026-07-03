#!/usr/bin/env bash
# test-packaged-app.sh - prove the packaged .app is well-formed AND actually launches.
#
# #13a (COPYs RememBar's test-packaged-app.sh - audit sec 2, "highest-value transferable script").
# Asserts the bundle invariants (plist keys, signature, no stray Bundle.module resource path), then
# launches the bundled inner executable and polls liveness with `kill -0` - a foreign-path launch
# proof (the 0.3.0 bug class: a locally-built .app can look healthy while a packaged resource is
# missing). SAFETY: only ever `kill`s the ONE pid it spawned - never pkill/killall (RememBar
# invariant, pinned by PackagingScriptsTests).
set -euo pipefail

APP="${1:-${APP:-dist/TermTile.app}}"
APP_NAME="${APP_NAME:-TermTile}"
BUNDLE_ID="${BUNDLE_ID:-dev.ecn.apps.termtile}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }

# --- Structural invariants -------------------------------------------------------------------
[ -d "$APP" ] || fail "bundle not found: $APP"
BIN="$APP/Contents/MacOS/$APP_NAME"
[ -x "$BIN" ] || fail "bundle executable missing/not executable: $BIN"

PLIST="$APP/Contents/Info.plist"
[ "$(plutil -extract CFBundleIdentifier raw "$PLIST")" = "$BUNDLE_ID" ] \
	|| fail "CFBundleIdentifier != $BUNDLE_ID"
[ "$(plutil -extract LSUIElement raw "$PLIST")" = "true" ] \
	|| fail "LSUIElement must be true (menu-bar only)"
plutil -extract CFBundleVersion raw "$PLIST" >/dev/null || fail "CFBundleVersion missing"

# Signature must verify strict (ad-hoc is fine; #13c upgrades to a stable identity).
codesign --verify --deep --strict "$APP" || fail "codesign --verify --deep --strict failed"

# Regression guard (audit 0.3.0 bug class): no source uses Bundle.module outside a DEBUG guard.
# TermTile has zero runtime resources, so this must be empty; it guards a future resource regression.
if grep -rn 'Bundle.module' Sources 2>/dev/null | grep -v '#if DEBUG' | grep -q .; then
	fail "Bundle.module used outside a DEBUG guard - packaged resource path would be baked in"
fi

# --- Launch proof ----------------------------------------------------------------------------
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
before="$(ls "$CRASH_DIR" 2>/dev/null | grep -c "^$APP_NAME" || true)"

"$BIN" >/dev/null 2>&1 &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT

# Poll liveness ~4s (accessory menu-bar app runs indefinitely; a crash makes kill -0 fail).
alive=0
for _ in 1 2 3 4 5 6 7 8; do
	if kill -0 "$PID" 2>/dev/null; then alive=$((alive+1)); else break; fi
	sleep 0.5
done
[ "$alive" -ge 8 ] || fail "process died within ~4s (alive=$alive/8)"

after="$(ls "$CRASH_DIR" 2>/dev/null | grep -c "^$APP_NAME" || true)"
[ "$after" -le "$before" ] || fail "a new crash report appeared for $APP_NAME"

echo "OK: $APP launched and stayed alive (pid=$PID, alive=$alive/8, crash-reports ${before}->${after})"
