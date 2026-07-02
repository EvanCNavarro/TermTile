#!/usr/bin/env bash
# ADR-0001 fail-closed guard: TermTileCore is the PURE functional core. It may import
# CoreGraphics/Foundation domain types only — never AppKit or ApplicationServices (the
# side-effect surfaces that belong in TermTileKit). Exit non-zero iff any file under
# Sources/TermTileCore/ imports a forbidden module.
#
# F3 (stoke-plan-8 audit): the match must catch attribute-prefixed / submodule import
# forms, e.g. `@preconcurrency import ApplicationServices` — anchoring on `^import`
# fails OPEN for exactly the form AccessibilityTrust.swift uses. Match `import` anywhere
# on the line, tolerant of leading attributes and trailing `.Submodule`.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
core_dir="$root/Sources/TermTileCore"

# No core dir yet = nothing to violate (pre-split safety).
[ -d "$core_dir" ] || exit 0

if grep -REn '(^|[[:space:]])import[[:space:]]+(AppKit|ApplicationServices)([.[:space:]]|$)' "$core_dir"; then
    echo "core-purity: FORBIDDEN import in Sources/TermTileCore/ (AppKit/ApplicationServices belong in TermTileKit)" >&2
    exit 1
fi
exit 0
