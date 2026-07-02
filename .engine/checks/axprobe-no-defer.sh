#!/usr/bin/env bash
# Fail-closed guard (spike-07 R1, TRAP-12): AXProbe terminates via C `exit()`, which SKIPS
# Swift `defer` blocks (verified: a compiled `defer { print("X") }; exit(0)` never prints X;
# only `atexit` handlers run). So ANY `defer` statement in Sources/AXProbe/main.swift is a
# latent no-op — its cleanup/restore never runs, silently leaking state (this exact bug left
# iTerm2's AXEnhancedUserInterface OFF after every dragprobe run until this beat). Restores in
# AXProbe must be INLINE before the terminal exit() (belt: atexit), never `defer`.
#
# Exit non-zero iff a `defer {` STATEMENT appears in code (comments mentioning "defer" are OK).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
file="$root/Sources/AXProbe/main.swift"

# No probe yet = nothing to violate.
[ -f "$file" ] || exit 0

# Strip line comments (everything from // to EOL), then look for a `defer {` statement.
# This tolerates comments that reference the word "defer" while catching the real statement.
if sed 's://.*$::' "$file" | grep -nE '(^|[[:space:]])defer[[:space:]]*\{'; then
    echo "axprobe-no-defer: FORBIDDEN 'defer' in Sources/AXProbe/main.swift — exit() skips defer;" >&2
    echo "  restore inline before the terminal exit() (belt: atexit), never defer (spike-07 R1)." >&2
    exit 1
fi
exit 0
