#!/usr/bin/env bash
# Build identity, shared by build-app.sh and test-packaged-app.sh so they can never disagree.
#
# Signing identity. A STABLE keychain identity keeps the app's code identity constant across rebuilds, so macOS TCC
# grants (Accessibility, Input Monitoring) survive - ad-hoc ("-") gets a fresh cdhash every build and silently
# resets every grant (#13c). Resolution order: explicit TERMTILE_SIGN_IDENTITY wins; else the local "TermTile Dev
# Signing" identity IF it's in the keychain; else ad-hoc (CI / a fresh clone without the cert).
#
# Bundle ID (TRAP-23). Only a Developer ID build defaults to the production ID. A local build launched under it makes
# macOS pin the user's Accessibility row to THAT build's code identity, and the signed release then stays untrusted
# with the toggle visibly on. Every other build defaults to "<production>.local". An explicit BUNDLE_ID always wins.

TERMTILE_PRODUCTION_BUNDLE_ID="dev.ecn.apps.termtile"
TERMTILE_DEV_SIGNING_IDENTITY="TermTile Dev Signing"

termtile_sign_identity() {
	if [ -n "${TERMTILE_SIGN_IDENTITY:-}" ]; then
		echo "$TERMTILE_SIGN_IDENTITY"
	elif security find-identity -v -p codesigning 2>/dev/null | grep -q "$TERMTILE_DEV_SIGNING_IDENTITY"; then
		echo "$TERMTILE_DEV_SIGNING_IDENTITY"
	else
		echo "-"
	fi
}

# termtile_default_bundle_id <sign identity>
termtile_default_bundle_id() {
	if [ -n "${BUNDLE_ID:-}" ]; then
		echo "$BUNDLE_ID"
	else
		case "${1:-}" in
			"Developer ID Application:"*) echo "$TERMTILE_PRODUCTION_BUNDLE_ID" ;;
			*) echo "$TERMTILE_PRODUCTION_BUNDLE_ID.local" ;;
		esac
	fi
}
