#!/usr/bin/env bash
# TRAP-17 guard: the TermTile env-selftest emits live-PROVE markers a harness captures from a
# process it later KILLS. print()/stdout to a pipe is block-buffered and is LOST on SIGTERM, so
# markers MUST go to unbuffered FileHandle.standardError. Fail-closed: exit non-zero iff any
# `print(` line mentioning SELFTEST appears in TermTileApp.swift (a buffered-stdout marker).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 3
FILE="Sources/TermTile/TermTileApp.swift"

# Absent file → nothing to guard (the selftest may be refactored away); pass.
[ -f "$FILE" ] || exit 0

if grep -nE 'print\(.*SELFTEST' "$FILE" >/dev/null 2>&1; then
  echo "TRAP-17: SELFTEST marker uses buffered print()/stdout in $FILE — use FileHandle.standardError" >&2
  grep -nE 'print\(.*SELFTEST' "$FILE" >&2
  exit 1
fi
exit 0
