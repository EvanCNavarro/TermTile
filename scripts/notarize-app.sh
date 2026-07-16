#!/usr/bin/env bash
# notarize-app.sh - submit a signed .app to Apple Notary, staple, validate, and Gatekeeper-assess it.
set -euo pipefail

APP="${1:-${APP:-}}"
[ -n "$APP" ] || { echo "usage: scripts/notarize-app.sh path/to/App.app" >&2; exit 2; }
[ -d "$APP" ] || { echo "notarize-app.sh: app bundle not found: $APP" >&2; exit 1; }

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

KEY_PATH="${TERMTILE_NOTARY_KEY_PATH:-}"
KEY_ID="${TERMTILE_NOTARY_KEY_ID:-}"
ISSUER_ID="${TERMTILE_NOTARY_ISSUER_ID:-}"
TIMEOUT="${TERMTILE_NOTARY_TIMEOUT:-60m}"

if [ -z "$KEY_PATH" ]; then
	test -n "${TERMTILE_NOTARY_KEY_P8_BASE64:-}" || {
		echo "notarize-app.sh: TERMTILE_NOTARY_KEY_PATH or TERMTILE_NOTARY_KEY_P8_BASE64 is required" >&2
		exit 1
	}
	KEY_PATH="$WORK/AuthKey.p8"
	printf '%s' "$TERMTILE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$KEY_PATH"
	chmod 600 "$KEY_PATH"
fi
test -f "$KEY_PATH" || { echo "notarize-app.sh: notary key not found: $KEY_PATH" >&2; exit 1; }
test -n "$KEY_ID" || { echo "notarize-app.sh: TERMTILE_NOTARY_KEY_ID is required" >&2; exit 1; }
test -n "$ISSUER_ID" || { echo "notarize-app.sh: TERMTILE_NOTARY_ISSUER_ID is required" >&2; exit 1; }

ZIP="$WORK/$(basename "${APP%.app}")-notary.zip"
RESULT_JSON="$WORK/notary-submit.json"
ditto -c -k --keepParent "$APP" "$ZIP"

set +e
xcrun notarytool submit "$ZIP" \
	--key "$KEY_PATH" \
	--key-id "$KEY_ID" \
	--issuer "$ISSUER_ID" \
	--wait \
	--timeout "$TIMEOUT" \
	--output-format json | tee "$RESULT_JSON"
SUBMIT_STATUS="${PIPESTATUS[0]}"
set -e

STATUS="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        print(json.load(fh).get("status", ""))
except Exception:
    print("")
PY
)"
JOB_ID="$(python3 - "$RESULT_JSON" <<'PY'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        print(json.load(fh).get("id", ""))
except Exception:
    print("")
PY
)"
if [ "$SUBMIT_STATUS" -ne 0 ]; then
	if [ -n "$JOB_ID" ]; then
		xcrun notarytool info "$JOB_ID" \
			--key "$KEY_PATH" \
			--key-id "$KEY_ID" \
			--issuer "$ISSUER_ID" || true
		xcrun notarytool log "$JOB_ID" \
			--key "$KEY_PATH" \
			--key-id "$KEY_ID" \
			--issuer "$ISSUER_ID" || true
	fi
	echo "notarize-app.sh: notarization did not complete (exit=$SUBMIT_STATUS, status=${STATUS:-unknown}, id=${JOB_ID:-unknown})" >&2
	exit "$SUBMIT_STATUS"
fi

if [ "$STATUS" != "Accepted" ]; then
	if [ -n "$JOB_ID" ]; then
		xcrun notarytool log "$JOB_ID" \
			--key "$KEY_PATH" \
			--key-id "$KEY_ID" \
			--issuer "$ISSUER_ID" || true
	fi
	echo "notarize-app.sh: notarization failed with status: $STATUS" >&2
	exit 1
fi

xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl --assess --type execute --verbose=4 "$APP"
