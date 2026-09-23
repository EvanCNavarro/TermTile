#!/usr/bin/env bash
# loop-flag.sh — declare that THIS terminal session is running a long autonomous loop, so
# TermTile's Session tint holds one colour for it (EvanCNavarro/TermTile#51).
#
#   scripts/loop-flag.sh set     <- on entering a loop
#   scripts/loop-flag.sh clear   <- on leaving it
#
# WHY A FLAG AND NOT A READ OF THE SCREEN. Loop state is the one thing in this feature that is not
# derivable from the terminal. Measured 2026-09-23 on a live `/loop /goal` session: the `/loop`
# command and every cycle marker sat 100+ lines back and were HISTORICAL — the nearest belonged to
# a cycle that had already finished, so matching it would paint a window purple forever after any
# loop ever ran. The tool's own session registry reports only busy/idle/shell. And during a dormant
# stretch between cycles the pane is indistinguishable from one that has genuinely finished, which
# is the case that matters most: without this, such a session paints GREEN, meaning done.
#
# THE PID IS THE SAFETY. The file contains the owning process id; TermTile ignores — and deletes —
# a flag whose process is gone. A loop that is killed therefore cannot strand a window purple,
# which is the `waiting-on-a-person` failure shape (ADR-0006 finding 10): a durable marker
# outliving the state it describes.
#
# Fails silent and exits 0 always: a cosmetic tint must never break the thing it is describing.
set -uo pipefail

DIR="$HOME/.claude/termtile-loop"

# HOW IT FINDS ITS OWN TTY. A hook or subprocess has no controlling terminal of its own, so walk up
# the process tree until one does — the same technique the retired window-state hook used, kept
# because it was the part of that tool that actually worked.
resolve_tty() {
  local cur=$$ pp t
  for _ in 1 2 3 4 5 6 7 8; do
    t=$(ps -o tty= -p "$cur" 2>/dev/null | tr -d ' ')
    case "$t" in ttys*) printf '%s' "$t"; return 0 ;; esac
    pp=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && break
    cur=$pp
    [ "$cur" -le 1 ] && break
  done
  return 1
}

# The pid recorded must be the SESSION's, not this short-lived script's — a script that has already
# exited would look stale the instant it wrote the flag.
resolve_owner() {
  local cur=$$ pp t
  for _ in 1 2 3 4 5 6 7 8; do
    t=$(ps -o tty= -p "$cur" 2>/dev/null | tr -d ' ')
    case "$t" in ttys*) printf '%s' "$cur"; return 0 ;; esac
    pp=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && break
    cur=$pp
    [ "$cur" -le 1 ] && break
  done
  return 1
}

tty_name="$(resolve_tty)" || exit 0
owner="$(resolve_owner)" || exit 0

case "${1:-}" in
  set)
    mkdir -p "$DIR" 2>/dev/null || exit 0
    printf '%s\n' "$owner" > "$DIR/$tty_name" 2>/dev/null || true
    ;;
  clear)
    rm -f "$DIR/$tty_name" 2>/dev/null || true
    ;;
  *)
    echo "usage: $(basename "$0") set|clear" >&2
    ;;
esac
exit 0
