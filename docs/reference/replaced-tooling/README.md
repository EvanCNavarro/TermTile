# The tooling ADR 0006 replaces

Preserved 2026-08-31. These three files are the out-of-tree system that TermTile's **Session tint**
feature replaces. They are kept here because backlog task `#37g` will DELETE them from the machine
they live on, and its own wording is "keep the script recoverable until then" — which was not true
of anything until this directory existed. The originals exist on exactly one Mac and in no version
control.

| file | original location | role |
|---|---|---|
| `claude-window-state.sh` | `~/.local/bin/claude-window-state` | the 242-line poller: reads every iTerm session, classifies it, sets `background color` over AppleScript |
| `com.evancnavarro.claude-window-state.plist` | `~/Library/LaunchAgents/` | ran it `--apply` every 5 seconds |
| `window-state-flag.sh` | `~/.claude/hooks/` | wired into Claude Code's `settings.json`; dropped tty-keyed flags so the poller could tell "blocked on you" from "finished" |

## Verbatim, except one line

Everything is byte-for-byte as it ran, with a **single** exception: the plist's `ProgramArguments`
path is placeholdered to `/Users/YOUR-USERNAME/.local/bin/claude-window-state`. launchd does not
expand `$HOME`, so an absolute path is required for the file to work — restoring it needs that one
edit. The substitution is stated here rather than left for a reader to trip over. The script and the
hook needed no changes; both already used `$HOME` / `~` throughout.

Checked for credentials before committing: zero secret-shaped matches across all three.

## Why keep them at all

**They are the specification.** ADR 0006 cites this system constantly — its colours (`#143C22`,
`#4A320F`, `#111417`), its `subtle`/`louder`/`loudest` presets, its 5-second cadence, its
`✳`-versus-spinner state model. TermTile carries those values deliberately so a user who already
picked one does not have to re-find it. Deleting the source would leave the ADR citing a thing
nobody can read.

**They record measurements TermTile did not have to repeat.** The poller's comments carry findings
bought with real debugging: that Claude Code hooks receive no `$TMUX`, no `$TMUX_PANE` and no
controlling tty; that `$CLAUDE_PROJECT_DIR` cannot identify a session because six of nine shared a
directory; that `lsof` is 8.5x the cost of a `stat` so the pid→rollout map must be cached; that
Codex's spinner animates even while parked, making its title useless.

**The hook is the honest record of a problem TermTile solved differently.** `window-state-flag.sh`
exists only because, from outside the terminal, "finished" and "waiting on you" both render as `✳`.
Its parent-chain tty walk, its stale-flag pruning and its `turn.*` false-green fix are all
workarounds for not being able to see the screen. TermTile reads the screen, so it needs none of
them — but that comparison is only legible while both halves survive.

## Before running `#37g`

The sequencing in the backlog is deliberate: prove the replacement in daily use FIRST, remove the
original SECOND. Nothing here authorises the removal; it only makes the removal safe to attempt.
