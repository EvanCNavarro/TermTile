#!/bin/bash
# claude-window-state — tint each iTerm2 window by what its AI agent session is doing.
# Handles BOTH Claude Code and Codex, by different means, because they expose state differently.
#
# HOOKS: MOSTLY NOT, BUT ONE PLACE YES
# Measured 2026-08-14: Claude Code hooks receive no $TMUX / $TMUX_PANE, no controlling tty, and
# their `terminalSequence` output never reached the terminal (fired 15x, 0 hits in 25 polls).
# $CLAUDE_PROJECT_DIR is no good for identity either — 6 of 9 sessions shared a directory.
# So state is PULLED from outside the sandbox, not pushed by hooks.
#
# The one exception is NEEDS-INPUT, which is genuinely unobservable from outside: "finished" and
# "waiting on you" both render as ✳. For that, a hook walks its own PARENT chain until it finds a
# process with a real tty (the claude process itself) and drops a flag keyed on that tty —
# verified: hook pid 10999 tty=?? -> parent claude pid 77967 tty=ttys013, the correct window.
# See ~/.claude/hooks/window-state-flag.sh.
#
# HOW EACH AGENT IS READ
#   Claude — the session NAME carries its state glyph, written via the one escape sequence Claude
#            is allowed to emit (OSC title).  ✳ = idle.  ⠂⠐⠏⠙⠸⠹⠼⠇ / ◐◑ = working.
#            Sampled every 2s over 30s across 8 live sessions to establish this.
#            NEEDS-INPUT comes from the hook flag above and overrides the glyph.
#   Codex  — the name is USELESS: its spinner animates continuously even while parked at
#            "Goal blocked", and it never sets a descriptive title. Instead: find the codex
#            process on that tty, ask lsof which rollout files it holds open, and use the
#            freshest mtime. Verified: idle codex (cpu 0.0%) showed age climbing 809→825s,
#            while a working one fluctuated 0–14s.
#            Bonus: codex holds its SUBAGENTS' rollouts open too, so a session whose subagents
#            are still working correctly reads as working.
#
# USAGE
#   claude-window-state            # dry run: print intent, change nothing
#   claude-window-state --apply    # one pass
#   claude-window-state --watch    # loop
#   claude-window-state --reset    # restore everything to NORMAL
#
# TUNING (no need to edit this file)
#   CWS_NORMAL_BG / CWS_READY_BG / CWS_INPUT_BG   16-bit "r, g, b"
#   CWS_CODEX_IDLE_AFTER           seconds of rollout silence before Codex counts as idle (20)
#   CWS_INTERVAL                   seconds between passes in --watch

set -u

NORMAL_BG="${CWS_NORMAL_BG:-4273, 5020, 6015}"   # #111417 — read from the live sessions, not guessed
READY_BG="${CWS_READY_BG:-5140, 15420, 8738}"    # #143C22 — dark green, light text stays readable
INPUT_BG="${CWS_INPUT_BG:-19018, 13000, 3855}"   # #4A320F — amber: Claude is BLOCKED on you
FLAG_DIR="${TMPDIR:-/tmp}/claude-window-state-flags"
INTERVAL="${CWS_INTERVAL:-5}"
CODEX_IDLE_AFTER="${CWS_CODEX_IDLE_AFTER:-20}"

# Presets for CWS_READY_BG:
#   subtle   3600, 11000, 6200    #0E2B18
#   default  5140, 15420, 8738    #143C22
#   louder   6600, 22000, 11500   #185634
#   loudest  7700, 30000, 14500   #1D7538

MODE="dry"
case "${1:-}" in
  --apply) MODE="apply" ;;
  --watch) MODE="watch" ;;
  --reset) MODE="reset" ;;
  ""|--dry-run) MODE="dry" ;;
  -h|--help) awk 'NR>1 && /^#/{sub(/^# ?/,""); print; next} NR>1 && !/^#/{exit}' "$0"; exit 0 ;;
  *) echo "unknown flag: $1" >&2; exit 2 ;;
esac

# ---- read every iTerm session: id, tty, name ---------------------------------
read_sessions() {
  # CWS_FAKE_SESSIONS=<file> substitutes synthetic "id<TAB>tty<TAB>name" rows for the
  # live iTerm read. It exists so the classification logic can be tested exhaustively
  # WITHOUT touching a single real window — every state combination, no clobbering.
  if [ -n "${CWS_FAKE_SESSIONS:-}" ] && [ -f "$CWS_FAKE_SESSIONS" ]; then
    cat "$CWS_FAKE_SESSIONS"; return
  fi
  osascript <<'A' 2>/dev/null
tell application "iTerm2"
  -- (ASCII character 9), NOT the bare word `tab`: through osascript the latter
  -- emitted the literal string "tab" and every field parsed as empty.
  set d to (ASCII character 9)
  set o to ""
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set o to o & (id of s) & d & (tty of s) & d & (name of s) & linefeed
      end repeat
    end repeat
  end repeat
  return o
end tell
A
}

# ---- Codex: freshest rollout mtime among the files its process holds open ----
# lsof is EXPENSIVE — measured, it took a pass from 0.08 to 0.68 CPU-seconds (8.5x).
# But which files a codex process holds open changes only when a session/subagent starts,
# so the pid->rollout mapping is cached and refreshed at most every CWS_LSOF_TTL seconds.
# Only the cheap stat() runs every pass.
CACHE_DIR="${TMPDIR:-/tmp}/claude-window-state-cache"
LSOF_TTL="${CWS_LSOF_TTL:-60}"

# ONE ps scan per pass builds tty->codex-pid, instead of `ps -t` per session. The old form
# ran ps for every non-Claude session including plain shells — ~24 needless ps calls a
# minute that could never return anything.
# MEASURED, then corrected: replacing per-session `ps -t` with one `ps -eo` scan was
# supposed to be cheaper and was actually 2.3x WORSE (0.21 -> 0.48 CPU-s), because -eo
# walks every process on the machine while -t looks at one tty. Codex processes almost
# never start or stop, so the map is cached on disk with a TTL and the scan runs about
# once a minute instead of twelve times.
CODEX_MAP=""
CODEX_MAP_TTL="${CWS_CODEX_MAP_TTL:-60}"
build_codex_map() {
  local mapfile="$CACHE_DIR/codexmap" age=$CODEX_MAP_TTL
  mkdir -p "$CACHE_DIR" 2>/dev/null
  [ -f "$mapfile" ] && age=$(( $(date +%s) - $(stat -f %m "$mapfile" 2>/dev/null || echo 0) ))
  if [ ! -f "$mapfile" ] || [ "$age" -ge "$CODEX_MAP_TTL" ]; then
    ps -eo tty=,pid=,args= 2>/dev/null \
      | grep -E 'codex-darwin|bin/codex' \
      | awk '{ if ($1 != "??") print $1"="$2 }' > "$mapfile" 2>/dev/null
  fi
  CODEX_MAP=$(cat "$mapfile" 2>/dev/null)
}

codex_state_for_tty() {
  local tty_short="${1#/dev/}"
  local pid
  pid=$(printf '%s\n' "$CODEX_MAP" | awk -F= -v t="$tty_short" '$1==t {print $2}' | tail -1)
  [ -z "$pid" ] && { printf 'NOTCODEX'; return; }

  mkdir -p "$CACHE_DIR" 2>/dev/null
  local cache="$CACHE_DIR/rollouts.$pid"
  local now; now=$(date +%s)
  local cache_age=$LSOF_TTL
  [ -f "$cache" ] && cache_age=$(( now - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
  if [ ! -f "$cache" ] || [ "$cache_age" -ge "$LSOF_TTL" ]; then
    lsof -p "$pid" 2>/dev/null | grep -oE '/[^ ]*\.codex/sessions/[^ ]*\.jsonl' | sort -u > "$cache"
  fi

  local newest=0 m
  while read -r f; do
    m=$(stat -f '%m' "$f" 2>/dev/null) || continue
    [ "$m" -gt "$newest" ] && newest=$m
  done < "$cache"
  [ "$newest" -eq 0 ] && { printf 'WORKING'; return; }   # unknown -> assume busy, never a false green
  if [ $(( now - newest )) -ge "$CODEX_IDLE_AFTER" ]; then printf 'READY'; else printf 'WORKING'; fi
}

# ---- prune flags whose tty no longer exists -----------------------------------
# A session that dies without SessionEnd firing (kill -9, terminal closed) leaves its
# flag behind. macOS recycles tty numbers, so a NEW session landing on that tty would
# inherit the dead one's state — a window stuck amber or dark for no reason. Cheap to
# prevent: drop any flag whose /dev/ttysNNN is no longer an open terminal.
prune_stale_flags() {
  [ -d "$FLAG_DIR" ] || return 0
  # In fake-session mode there are no real sessions to reconcile against, and the
  # synthetic ttys are deliberately non-existent — pruning would delete the very flags
  # under test. Skipped there; covered by its own section in claude-window-state-test.
  [ -n "${CWS_FAKE_SESSIONS:-}" ] && return 0
  local f base t
  for f in "$FLAG_DIR"/ttys* "$FLAG_DIR"/turn.ttys*; do
    [ -e "$f" ] || continue
    base="$(basename "$f")"; t="${base#turn.}"
    [ -e "/dev/$t" ] || { rm -f "$f" 2>/dev/null; continue; }
    # tty exists but nothing is running on it -> the session is gone
    ps -t "$t" >/dev/null 2>&1 || rm -f "$f" 2>/dev/null
  done
  # lsof cache files outlive the codex process they describe; drop dead ones.
  for c in "$CACHE_DIR"/rollouts.*; do
    [ -e "$c" ] || continue
    ps -p "${c##*.}" >/dev/null 2>&1 || rm -f "$c" 2>/dev/null
  done
}

# ---- one pass ----------------------------------------------------------------
pass() {
  local mode="$1" setcmds="" report=""
  prune_stale_flags
  build_codex_map
  while IFS=$'\t' read -r sid sess_tty name; do
    [ -z "${sid:-}" ] && continue
    local state="skip"
    if [[ "$name" == *"(node)" ]]; then
      # NEEDS-INPUT beats everything: a hook (Notification / PermissionRequest) dropped a
      # flag keyed on this tty, meaning Claude is BLOCKED on Bobby, not merely finished.
      # The glyph cannot tell those apart — both show ✳ — so the flag is the only signal.
      local base; base="$(basename "$sess_tty")"
      if [ -e "$FLAG_DIR/$base" ]; then
        state="INPUT"
      elif [ -e "$FLAG_DIR/turn.$base" ]; then
        # TURN STILL OPEN: UserPromptSubmit fired and Stop has not. This is the fix for
        # the ✳ false-green — a session waiting on a dynamic workflow shows the SAME ✳
        # as a finished one, but its turn has not ended, so Stop has not fired. Trusting
        # the glyph alone would paint it green while it is genuinely busy.
        state="WORKING"
      elif [[ "$name" == "✳"* ]]; then state="READY"; else state="WORKING"; fi
    else
      local c; c=$(codex_state_for_tty "$sess_tty")
      [ "$c" != "NOTCODEX" ] && state="$c"
    fi
    # Keyed on tty, not id: sessions are nested inside tabs inside windows, so there is
    # no global "session whose id is X" accessor — an id-based form silently only ever
    # searched the first window.
    local want=""
    [ "$state" = "READY" ]   && want="$READY_BG"
    [ "$state" = "INPUT" ]   && want="$INPUT_BG"
    [ "$state" = "WORKING" ] && want="$NORMAL_BG"
    [ "$mode" = "reset" ] && [ -n "$want" ] && want="$NORMAL_BG"
    [ -n "$want" ] && setcmds="$setcmds"$'\n'"        if tt is \"$sess_tty\" then set background color of s to {$want}"
    report="$report$(printf '%-8s %s\n' "$state" "$name")"$'\n'
  done < <(read_sessions)

  if [ "$mode" = "dry" ]; then printf '%s' "$report"; return; fi

  # ONE osascript call for the whole pass. The earlier version made 2 + one-per-codex
  # round-trips; each is ~0.2s of wall time, so this is the other half of the cost fix.
  [ -n "$setcmds" ] && osascript 2>/dev/null <<A
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        set tt to tty of s$setcmds
      end repeat
    end repeat
  end repeat
end tell
A
  return 0
}

case "$MODE" in
  dry)
    echo "DRY RUN — nothing changed."
    echo "  READY -> #143C22 green · INPUT -> #4A320F amber · WORKING -> #111417   codex idle after ${CODEX_IDLE_AFTER}s of rollout silence"
    echo
    pass dry
    ;;
  apply) pass apply >/dev/null; echo "applied one pass"; ;;
  reset) pass reset >/dev/null; echo "restored to normal"; ;;
  watch)
    echo "watching every ${INTERVAL}s — Ctrl-C to stop"
    trap 'echo; echo "stopped (--reset to restore)"; exit 0' INT TERM
    while true; do pass apply >/dev/null; sleep "$INTERVAL"; done
    ;;
esac
