#!/usr/bin/env bash
# notary-auth.sh - shared Notary credential preparation for TermTile scripts.
# shellcheck shell=bash

termtile_notary_prepare_auth() {
	local work_dir="${1:?work directory required}"

	test -n "${TERMTILE_NOTARY_KEY_ID:-}" || {
		echo "notary-auth.sh: TERMTILE_NOTARY_KEY_ID is required" >&2
		return 1
	}
	test -n "${TERMTILE_NOTARY_ISSUER_ID:-}" || {
		echo "notary-auth.sh: TERMTILE_NOTARY_ISSUER_ID is required" >&2
		return 1
	}

	TERMTILE_NOTARY_AUTH_KEY_PATH="${TERMTILE_NOTARY_KEY_PATH:-}"
	if [ -z "$TERMTILE_NOTARY_AUTH_KEY_PATH" ]; then
		test -n "${TERMTILE_NOTARY_KEY_P8_BASE64:-}" || {
			echo "notary-auth.sh: TERMTILE_NOTARY_KEY_PATH or TERMTILE_NOTARY_KEY_P8_BASE64 is required" >&2
			return 1
		}
		mkdir -p "$work_dir"
		TERMTILE_NOTARY_AUTH_KEY_PATH="$work_dir/AuthKey.p8"
		printf '%s' "$TERMTILE_NOTARY_KEY_P8_BASE64" | base64 --decode > "$TERMTILE_NOTARY_AUTH_KEY_PATH"
		chmod 600 "$TERMTILE_NOTARY_AUTH_KEY_PATH"
	fi

	test -f "$TERMTILE_NOTARY_AUTH_KEY_PATH" || {
		echo "notary-auth.sh: notary key not found: $TERMTILE_NOTARY_AUTH_KEY_PATH" >&2
		return 1
	}

	TERMTILE_NOTARY_ARGS=(
		--key "$TERMTILE_NOTARY_AUTH_KEY_PATH"
		--key-id "$TERMTILE_NOTARY_KEY_ID"
		--issuer "$TERMTILE_NOTARY_ISSUER_ID"
	)
}
