# ADR 0006 — Session-state tinting: AX for state, OSC for colour

Status: proposed (2026-08-28). Amended 2026-08-31 — finding 6 CORRECTED and finding 6b added
after a measurement disproved the pane-geometry claim. Supersedes nothing. Binding for #37a–#37f. Tier 2
(Apple Events) is explicitly OUT of scope here and tracked as #38; adopting it requires
an amendment to this ADR, because it changes the app's permission surface.

## Context

An out-of-tree toolchain currently tints iTerm2 sessions by agent state: green when the
agent is idle/ready, amber when it is blocked on the user, normal while working. It is
three coupled pieces living outside any repo:

- `~/.local/bin/claude-window-state` — 242 lines of bash; reads every iTerm session over
  AppleScript, classifies it, writes `background color of session`.
- `~/Library/LaunchAgents/com.evancnavarro.claude-window-state.plist` — runs it every 5s.
- `~/.claude/hooks/window-state-flag.sh` — wired into Claude Code's `settings.json`;
  drops tty-keyed flag files so the poller can tell "blocked on you" from "finished".

The third piece exists ONLY because, from outside the terminal, a finished session and a
session waiting on a human both render the same `✳` glyph. Everything about the hook —
the parent-chain tty walk, the stale-flag pruning, the `turn.*` false-green fix — is a
workaround for not being able to see the screen.

Bringing this into TermTile was investigated on 2026-08-28. The findings below are all
from runs on this Mac against live iTerm2 windows, not from reading docs.

## Findings (measured, not assumed)

1. **AX can read session state.** Each iTerm session's `AXTextArea` exposes its full
   scrollback (17k–44k chars observed) plus `AXDocument` (cwd) and `AXDescription: shell`.
   The blocked-state signal is literal visible text — a live session's tail read
   `⧉  waiting-on-a-person`. TermTile's EXISTING Accessibility grant covers this. No
   AppleScript, no hooks.

2. **Colour can be set without Apple Events.** `printf '\033]1337;SetColors=bg=RRGGBB\a'
   > /dev/ttysNNN` changes the session background. Verified by AppleScript readback inside
   the poller's 5s window: `427250206014` → `24415036595`. Values differ from the literal
   hex because iTerm converts through its own colour space.

3. **The join key is the window-number badge.** AX exposes an `AXStaticText` child on the
   window reading `⌥⌘N`, where N = the `ITERM_SESSION_ID` window index + 1. All six live
   windows matched. The badge is STABLE while AX window order is NOT — order is z-order and
   was observed shuffling between two probes seconds apart.

4. **The badge ceiling is exactly 9.** At 11 open windows, precisely 9 carried a badge;
   windows 10 and 11 reported none. Hard limit, confirmed by run.

5. **The badge is a default, not a user setting.** No window-number key is present in
   `com.googlecode.iterm2.plist`, so it renders from iTerm2's shipped default. It remains
   user-disableable, so a fallback is still required.

6. **Background tabs are invisible to AX.** A window with 3 sessions across 2 tabs showed
   2 text areas to AX (active tab only) and 3 sessions to AppleScript.

   ~~Panes WITHIN the active tab are resolvable by geometry: `area[0] x=578` = p0 = ttys006,
   `area[1] x=738` = p1 = ttys007.~~ **CORRECTED 2026-08-31 — see finding 6b. That two-pane
   result coincided with creation order and did not establish what it appeared to.**

6b. **Pane index is a CREATION COUNTER, not a position — panes are NOT resolvable by geometry.**
   The two-pane observation in finding 6 was built left-then-right, so creation order and
   left-to-right order agreed and the case could not distinguish them. Re-measured with a 2x2
   grid built by splitting the RIGHT side BEFORE the left:

   | position | observed pane | row-major geometry predicts |
   |---|---|---|
   | left-top | p0 | p0 |
   | right-top | p1 | p1 |
   | right-bottom | **p2** | p3 |
   | left-bottom | **p3** | p2 |

   The `p` in `ITERM_SESSION_ID=w<W>t<T>p<P>` tracks the order panes were CREATED. Geometry
   cannot recover it, and no AX attribute carries it (the exhaustive attribute sweep in finding
   7's probe found no session identifier anywhere in the tree).

   **Consequence:** a window holding more than one session — splits, tabs, or both — is
   resolvable ONLY when cwd separates its sessions. Identical cwds are unresolvable and yield
   `.ambiguous`, so the window is left untinted. Single-session windows, which is the entire
   current real workload, are unaffected: the badge alone resolves them.

   This is the strongest argument yet for Tier 2 (#38), which has no pane problem at all.

7. **The nonce probe is not a viable fallback.** OSC 2 title writes DO reach `AXTitle` on
   ordinary windows. They do NOT pierce a window-title override: Claude Code writes OSC
   titles into the hand-named windows continuously and their `AXTitle` stays at the manual
   name. The probe therefore fails on precisely the windows most likely to be named.

8. **A tty-side-only design does not work for Claude Code.** Codex holds its rollout
   `.jsonl` open (which is why the existing poller can stat it); Claude Code does not — all
   six agent ttys returned no open jsonl. Its transcript is reachable only via
   cwd → project dir, which is ambiguous when sessions share a directory. AX is therefore
   load-bearing for state; it cannot be designed out.

9. **Writing to a live tty is safe under load.** 200 rapid `SetColors` writes during active
   TUI render left the scrollback byte-identical: 36652 → 36652 chars, 3937 → 3937 control
   characters. NOTE the blind spot: AX reads a RENDERED view, so this rules out buffer
   corruption, not a transient visual flicker.

## Decision

### Tier 1 — the default, and the only tier built here

State is read through the Accessibility API TermTile already holds. Colour is written as
an OSC 1337 escape to the session's tty. No new TCC permission, no entitlement, no launchd
job, and no Claude Code hook.

The join runs badge → cwd → pane geometry, and **tints only when the join is unambiguous.**
A session that cannot be resolved with confidence is LEFT AT ITS NORMAL COLOUR. A wrong
tint is worse than no tint: it reports the state of one window on another, which is a
silent lie of exactly the kind Tenet 8 forbids.

The background-tab ceiling is accepted rather than worked around, because a background
tab's background colour is not rendered to the user in the first place — the blind spot
coincides with what cannot be seen. The cost is that a tab-BAR indicator is impossible in
Tier 1; that is Tier 2's job (#38).

### Target graph (ADR 0001 rules hold unchanged)

```
TermTileCore   SessionJoin  — (badge?, cwd, geometry, ITERM_SESSION_ID) -> JoinResult
                              with an explicit `.ambiguous` case. Pure.
               AgentState   — scrollback tail -> .ready | .working | .blocked. Pure.
TermTileKit    AXSessionReader  — text areas, badges, AXDocument, geometry. Protocol-backed.
               TTYProbe         — ps/environ -> ITERM_SESSION_ID ONLY. Protocol-backed.
               OSCColorWriter   — tty write. Protocol-backed; no-op double in tests.
TermTile       TintingCoordinator — timer, settings, menu toggle, colour pickers.
```

Colour defaults carry over from the tool being replaced: ready `#143C22`, blocked
`#4A320F`, normal `#111417`, plus its `subtle` / `louder` / `loudest` presets.

### Privacy surface — this is a real expansion, and it is stated, not buried

Tier 1 requires TermTile to do two things the current README explicitly promises it does
not do. The README says: *"It only moves windows... It never reads window contents, your
keystrokes, or anything you type."* Under this ADR **both halves of that sentence stop
being true** and the README MUST be corrected in the same change that ships the feature:

- **It reads window contents.** Session scrollback, via AX, is the entire state signal.
- **It reads other processes' environment blocks.** `ITERM_SESSION_ID` is obtained from
  the environment of the agent process on each tty.

The second carries a hazard proven during this investigation: a process environment block
also contains secrets. An `ANTHROPIC_API_KEY` and a `SESSION_SECRET` were exposed in plain
text by a single unguarded environment read while probing this design.

Binding constraints, to be enforced by test, not by care:

1. `TTYProbe` extracts `ITERM_SESSION_ID` and discards the remainder of the environment
   block without returning it. Its return type MUST NOT be able to carry another variable.
2. No scrollback text and no environment value is logged, persisted, or written to disk.
   Classification consumes the tail in memory and returns an enum.
3. A red-first test asserts that no other environment variable can escape the parser —
   the leak path gets a failing test BEFORE the parser exists.

The "no telemetry, no network" promise is unaffected and stays true.

## Consequences

- Deletes the launchd job and `window-state-flag.sh` outright. The `✳` ambiguity that hook
  existed to solve dissolves once the screen is readable.
- Portable in principle beyond iTerm2: OSC 1337 is a terminal protocol, not an app API, so
  the write path has a route to WezTerm (already a TermTile target) that AppleScript never
  had. NOT verified against WezTerm — do not claim it until it is run.
- Ceilings accepted in Tier 1: >9 windows lose the badge and fall back to cwd; background
  tabs are unreadable; sessions sharing a cwd with no badge are ambiguous and stay untinted;
  and per finding 6b any multi-session window whose sessions share a cwd is likewise untinted.
- The README privacy section must be rewritten in the shipping change, not after it.

## Alternatives rejected

- **Apple Events (Tier 2).** Exact mapping with no join problem, handles background tabs,
  >9 windows and splits, and `text of session` supplies state hook-free. Rejected as the
  DEFAULT because it needs `com.apple.security.automation.apple-events`, a usage string, and
  a third TCC prompt, and it locks the feature to iTerm2 permanently. Deferred to #38 as an
  opt-in upgrade for users who hit a Tier 1 ceiling.
- **iTerm2 Python/WebSocket API.** `EnableAPIServer` is on and the socket is live. Full
  fidelity, but it means a protobuf websocket client for a job two simpler mechanisms
  already do.
- **Nonce-probe join.** Fails on window-title overrides (finding 7).
- **tty-side-only, no AX.** Fails for Claude Code (finding 8).
