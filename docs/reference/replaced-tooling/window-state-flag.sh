#!/bin/bash
# window-state-flag.sh — mark THIS Claude window as needing Bobby's input, or clear it.
#
# Usage (from settings.json hooks):
#   window-state-flag.sh set     <- Notification / PermissionRequest
#   window-state-flag.sh clear   <- UserPromptSubmit / PreToolUse
#
# HOW IT KNOWS WHICH WINDOW IT IS
# Claude Code hooks get NO $TMUX, NO $TMUX_PANE and no controlling tty — measured
# 2026-08-14, which is why an earlier design that shelled out to `tmux`/`osascript`
# would have coloured whichever session was most recently attached (all nine resolved
# to the same one). $CLAUDE_PROJECT_DIR is no good either: sessions share directories.
#
# But the hook's PARENT is the claude process, and THAT has a tty. Verified: hook pid
# 10999 tty=?? -> parent claude pid 77967 tty=ttys013, matching the real window.
# So walk up until a process has a real tty, and key the flag on it. The poller maps
# tty -> iTerm session, which it already does for Codex.
#
# Fails silent and exits 0 always: a cosmetic tint must never block a tool call.

FLAG_DIR="${TMPDIR:-/tmp}/claude-window-state-flags"
mode="${1:-set}"

# Read (don't just drain) stdin: Notification fires for BOTH "needs your permission" and a
# plain idle nudge after ~60s. Flagging blindly would turn every finished-green window amber
# a minute later and collapse the green/amber distinction entirely. So only amber when the
# payload actually looks like a block on Bobby. PermissionRequest passes `--force` because it
# is unambiguous by definition.
payload=""
# Explicit if/else, not `a && b || c`: in that form c also runs whenever b returns
# non-zero, which is a trap waiting to fire. stdin must ALWAYS be drained either way —
# a hook that leaves it unread can make Claude block on a full pipe.
if [ "$mode" = "set" ]; then
  payload=$(cat 2>/dev/null | head -c 2000)
else
  cat > /dev/null 2>&1
fi

if [ "$mode" = "set" ] && [ "${2:-}" != "--force" ]; then
  # Log EVERY notification, matched or not — the previous version only logged misses, so
  # when a window went amber for no reason there was no evidence of what caused it.
  # Log the MESSAGE field explicitly. A previous version logged the first 300 chars of the
  # raw payload — but real notifications carry session_id/transcript_path/cwd first, so the
  # message was truncated away and the log recorded everything EXCEPT the thing being matched.
  msg=$(printf '%s' "$payload" | sed -n 's/.*"message"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  printf '%s  SEEN msg=[%s]  raw=%s\n' "$(date '+%F %T')" "${msg:-<no message field>}" \
    "$(printf '%s' "$payload" | tr -d '\n' | head -c 160)" >> "$FLAG_DIR/.seen.log" 2>/dev/null
  # Cap the log. It is an evidence trail, not an archive — an unbounded file in TMPDIR
  # that nothing ever reads is how a debugging aid turns into a disk leak.
  if [ "$(wc -l < "$FLAG_DIR/.seen.log" 2>/dev/null || echo 0)" -gt 400 ]; then
    tail -200 "$FLAG_DIR/.seen.log" > "$FLAG_DIR/.seen.log.tmp" 2>/dev/null \
      && mv "$FLAG_DIR/.seen.log.tmp" "$FLAG_DIR/.seen.log" 2>/dev/null
  fi
  # "waiting for your input" was in this list and MUST NOT BE: that is Claude's ~60s IDLE
  # nudge, not a block. Including it contradicted the whole point of this gate and turned
  # a finished window amber seconds after Stop fired — observed 2026-08-14 13:32.
  # Only genuine blocks: permission prompts. AskUserQuestion / ExitPlanMode /
  # PermissionRequest all pass --force and never reach this branch.
  if ! printf '%s' "$payload" | grep -qiE 'permission|needs your approval|approve this|confirm this'; then
    # No separate .unmatched.log: .seen.log above records EVERY notification with its
    # message field, so a second file recording a subset was pure duplication — two
    # places to look, two places to rotate, one of them always stale.
    exit 0
  fi
fi

resolve_tty() {
  local cur=$$ pp t
  for _ in 1 2 3 4 5 6 7 8; do
    t=$(ps -o tty= -p "$cur" 2>/dev/null | tr -d ' ')
    case "$t" in ttys*) printf '/dev/%s' "$t"; return 0 ;; esac
    pp=$(ps -o ppid= -p "$cur" 2>/dev/null | tr -d ' ')
    [ -z "$pp" ] && break
    cur=$pp
    [ "$cur" -le 1 ] && break
  done
  return 1
}

tty_path="$(resolve_tty)" || exit 0
mkdir -p "$FLAG_DIR" 2>/dev/null || exit 0
flag="$FLAG_DIR/$(basename "$tty_path")"

turn="$FLAG_DIR/turn.$(basename "$tty_path")"

case "$mode" in
  set)   : > "$flag" 2>/dev/null ;;
  clear) rm -f "$flag" 2>/dev/null ;;
  # turn-start / turn-end fix the ✳ false-green: "finished" and "waiting on a dynamic
  # workflow" both render as ✳, so the glyph cannot separate them. But Stop only fires
  # when the turn actually ends — it does NOT fire while a workflow is still running.
  # So an open turn marker means WORKING no matter what the glyph says.
  turn-start) : > "$turn" 2>/dev/null; rm -f "$flag" 2>/dev/null ;;
  turn-end)   rm -f "$turn" 2>/dev/null ;;
esac
exit 0
