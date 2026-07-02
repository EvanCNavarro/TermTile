#!/usr/bin/env bash
# TRAP-2 hardening: cycle_close.py's il_capture_deferrals maps deferral `→ #N` refs to
# task-refs.json entries via int(key) — a non-integer key (e.g. a sub-task label like "12a")
# makes int() raise and silently empties/breaks the map. Splitting a task into #Na/#Nb/#Nc
# sub-tasks (as #12 → #12a/#12b/#12c) is exactly when this trap gets tripped. Record sub-task
# state by UPDATING the parent integer key (e.g. "12"), never by adding a fractional key.
#
# Exit non-zero iff any key in .engine/state/task-refs.json is not a bare base-10 integer.
# Absent file = pass (nothing to violate).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
refs="$root/.engine/state/task-refs.json"
[ -f "$refs" ] || exit 0

python3 - "$refs" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    keys = list(json.load(f).keys())
bad = [k for k in keys if not re.fullmatch(r"-?[0-9]+", k)]
if bad:
    print(f"TRAP-2 violation: non-integer task-refs.json key(s): {bad}", file=sys.stderr)
    print("Record sub-task state on the parent integer key (e.g. '12'), not a '12a' key.",
          file=sys.stderr)
    sys.exit(1)
PY
exit 0
