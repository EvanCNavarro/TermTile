#!/usr/bin/env bash
# Fail-closed guard (#19a, TRAP-14): top-level statements in Sources/AXProbe/main.swift run on the
# @MainActor, so a BARE `Task { ... }` inherits main-actor isolation and enqueues onto the main
# thread. AXProbe's async modes then block sync `main` with `sem.wait()` - so a bare Task deadlocks
# (verified live: `sample` showed only the main thread parked in semaphore_wait_trap, the Task
# closure never ran, zero output). The sync-main entry must dispatch async work via `Task.detached`
# (global executor, no main-actor inheritance), resolving any @MainActor values before the wait.
#
# Exit non-zero iff a bare `Task {` (NOT `Task.detached`) appears in code (comments are OK).
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
file="$root/Sources/AXProbe/main.swift"

# No probe yet = nothing to violate.
[ -f "$file" ] || exit 0

# Strip line comments, then look for a `Task {` or `Task.init {` that is NOT `Task.detached`.
# `Task.detached {` and `Task<...>.detached` are allowed; a bare `Task {`/`Task.init {` is the bug.
if sed 's://.*$::' "$file" | grep -nE '(^|[^.[:alnum:]])Task[[:space:]]*(\.init[[:space:]]*)?\{'; then
    echo "axprobe-detached-task: FORBIDDEN bare 'Task {' in Sources/AXProbe/main.swift - top-level" >&2
    echo "  main is @MainActor, so a bare Task enqueues onto the main thread that sem.wait() blocks" >&2
    echo "  -> deadlock (TRAP-14). Use Task.detached { ... } and pre-resolve @MainActor values." >&2
    exit 1
fi
exit 0
