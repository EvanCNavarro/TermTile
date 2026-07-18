#!/usr/bin/env bash
# TRAP-6 gate: iTerm2's AppleScript dialect rejects `whose` filters on windows
# (-1719 Invalid index) - windows must be addressed as `window id N`.
# Fails (exit 1) iff any committed source/script/doc-example uses a
# `window whose id` style filter. Findings notes may MENTION the trap (they
# describe the failure), so docs/research and .engine are excluded.
set -uo pipefail
cd "$(dirname "$0")/../.."

matches=$(grep -rniE 'window[s]? whose id' \
    --include='*.swift' --include='*.sh' --include='*.applescript' --include='*.scpt' \
    Sources Tests scripts 2>/dev/null || true)

if [ -n "$matches" ]; then
    echo "TRAP-6 violation: AppleScript 'whose id' filter on iTerm2 windows (use 'window id N'):" >&2
    echo "$matches" >&2
    exit 1
fi
exit 0
