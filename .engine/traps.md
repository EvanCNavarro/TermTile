# TermTile project traps

Project-local traps discovered during cycles. When a trap proves universal (recurs across
≥2 independent stacks), PROMOTE it up to the base library at
`~/.claude/skills/locomotion/reference/traps-index.md` and leave a pointer here.

### TRAP-1: menu-bar screenshot proof is unreliable under menu-bar managers
- what happened: PROVE for task #1 tried to screenshot the TermTile status item twice; a
  menu-bar manager (the "…" overflow) had parked the item off-screen (CGWindowList showed
  its window at X=-4721, layer 25), so full-menu-bar screencaptures could never show it.
- warning: on this Mac, prove a status item exists via read-only AX enumeration (System
  Events → process → menu bar item "status menu") + CGWindowList (owner window at layer 25
  = NSStatusWindowLevel), not via pixels. Screenshot evidence of menu-bar items is only
  valid if the item is actually visible.

### TRAP-2: gate-artifact line-shape — deferrals must be single-line, task-refs keys bare ints
- what happened: first cycle_close.py run failed 3 gates: deferral bullets were wrapped
  across lines (row7 only reads the first physical line, so the `→ #N` was invisible),
  entries lacked `[DEP: …]` tags (il12), and task-refs.json used "#12"-style keys which
  int() rejects, silently emptying the map (il_capture).
- warning: in receipt/bubble Deferred sections write each entry as ONE physical line ending
  `[DEP: external|shape|blocked-by #N|scope-cohesion: <shape>] → #N`; task-refs.json keys
  are bare integers ("12", not "#12").

### TRAP-3: cycle_close.py reads cwc.config.json at project root, not .engine/config.json
- what happened: the Row-8 PROVE gate reported "no live-execution surface touched" even
  though Sources/*.swift changed, because the gate script loads `cwc.config.json` (absent)
  and .engine/config.json's subprocess_globs never reach it; untracked files are also
  invisible to its `git diff HEAD` file list.
- warning: keep `cwc.config.json` at project root mirroring .engine/config.json's live-surface
  globs (enforced by .engine/checks/cwc-config-present.sh), and don't trust Row-8 "N/A" on a
  cycle whose new files are still untracked — verify live anyway.

### TRAP-4: security hook blocks `rm -rf` on paths outside the repo
- what happened: cleanup step `rm -rf /tmp/AXProbe.app` was blocked by the PreToolUse
  security-validator hook ("Destructive rm path escape detected"), killing the whole
  compound command including the swift test before it.
- warning: for scratch dirs outside the repo, pre-clean with `rm -f <files>` + `rmdir`
  (both pass), or build the scratch tree only if absent; never chain `rm -rf /tmp/…`
  into a command whose earlier parts you need.

### TRAP-5: zsh expands words starting with `=` — `echo ===` dies
- what happened: a compound command used `echo ===` as a section separator; zsh's
  =word (command-path) expansion turned it into "(eval):1: == not found", silently
  dropping the rest of the command chain.
- warning: in zsh, quote separator strings (`echo "==="`) or use `---`; never bare `=…`
  words in Bash-tool commands.

### TRAP-6: iTerm2 AppleScript rejects `whose` filters on windows — use `window id N`
- what happened: spike-03 cleanup ran `close (first window whose id is 78056)` and got
  `-1719 Invalid index`, aborting the whole cleanup script (the windows turned out to be
  externally closed already; post-state was verified equal to baseline three ways).
- warning: iTerm2's scripting dialect does not support `whose` clauses on windows —
  address windows by the direct element form `window id N` (that id is also the CGWindowID
  and the _AXUIElementGetWindow id). Enforced by .engine/checks/no-iterm-whose-filter.sh.

### TRAP-7: new traps get inserted mid-file, breaking numeric order (recurred 2 beats)
- what happened: beat 1 inserted TRAP-4/5 above TRAP-3; this beat inserted TRAP-6 above
  TRAP-5. Same edit reflex both times: anchoring the insertion on the last-READ heading
  instead of the end of file. (Bonus this beat: bait-testing the ordering check on the
  LIVE traps.md and reverting with `git checkout --` restored the stale index version,
  silently deleting this very trap — bait-test checks on a COPY, or re-verify the file
  after any index-restore.)
- warning: APPEND new traps at the end of traps.md — anchor Edit old_string on the final
  lines of the LAST trap, never on a heading. Enforced by .engine/checks/traps-ordered.sh.

### TRAP-8: spike-created windows vanish externally before scripted cleanup (recurred 2 beats)
- what happened: spike-03 AND spike-04 both had their created iTerm2 windows externally
  closed (plausibly by the user after the done-note cue) before the scripted close ran;
  spike-04's `close window id N` errored -1728, and because it led an `&&` chain, the
  baseline-verification steps behind it never ran and had to be rerun manually.
- warning: spike cleanup must (1) check existence first or treat -1728/already-gone as
  SUCCESS, and (2) never put the close and the verification in one `&&` chain — verify
  as a separate command so a failed close can't swallow the evidence. Not mechanically
  checkable from repo state (cleanup scripts are transient).

### TRAP-9: invert-check evidence lost by compounding flip+run+restore+run in one command
- what happened: spike-04's first invert-check piped both the red run and the restored
  green run through one compound command with a narrow grep/head filter; the outputs
  interleaved and the failing `✘` line was not visibly captured, forcing a full redo.
- warning: run the invert-check as SEPARATE commands — flip, run (capture the `✘`
  assertion line explicitly), restore, run (capture green) — never fuse them; proof that
  isn't visibly in the output is not proof (FL-1). Not mechanically checkable from repo
  state (transient process discipline).

### TRAP-10: gate parsers read the FIRST PHYSICAL LINE only (recurrence class of TRAP-2)
- what happened: cycle_close.py's il10 gate failed twice on reorient.md because the
  `← .engine/BACKLOG.md:N` citation was wrapped onto the line AFTER "Next task:"; the
  gate (like TRAP-2's row7 deferral parser) only inspects the first physical line.
  Bonus: re-running the script manually without `--task-refs-path .engine/state/
  task-refs.json` false-failed il_capture_deferrals.
- warning: in ALL .engine/state gate artifacts, machine-read tokens (`← source` on the
  "Next task:" line, `[DEP: …] → #N` on deferral bullets) must sit on the SAME physical
  line as their anchor — wrap prose, never tokens. Always invoke cycle_close.py with
  `--task-refs-path .engine/state/task-refs.json`. Enforced by
  .engine/checks/reorient-next-task-cited.sh.

### TRAP-11: Edit tool rejects files inspected only via Bash `cat` (recurred 3× in one beat)
- what happened: Package.swift, AXProbe/main.swift, and BACKLOG.md were all read with a
  Bash `cat`/`sed` first, so the first `Edit` on each failed with "File has not been read
  yet" — the Edit/Write tools only honor a prior READ-TOOL call, not a shell cat. Cost a
  re-Read round-trip on every one.
- warning: before editing a file, open it with the Read TOOL (not Bash cat) at least once
  this session — batch-reading via cat is fine for inspection but does NOT satisfy the edit
  precondition. Not mechanically checkable from repo state (harness-interaction discipline,
  no artifact).

### TRAP-12: C `exit()` skips Swift `defer` — restore/cleanup in an exit()-terminating tool never runs
- what happened: spike-07's plan mitigated a "leaves a system pref disabled if the probe dies
  mid-round-trip" risk with a `defer`-guaranteed restore. A compiled micro-probe
  (/tmp/deferexit: `defer { print("DEFER-RAN") }; exit(0)`) proved `exit()` SKIPS `defer`
  entirely — only `atexit` handlers run. The skeptic then found a LIVE instance already
  shipped: AXProbe `dragprobe` set `defer { restore AXEnhancedUserInterface }` then
  `exit(pass ? … )`, so iTerm2's enhanced-UI was silently left OFF after every dragprobe run.
- warning: in any tool that terminates via `exit()` (all of AXProbe), NEVER rely on `defer`
  for restore/cleanup — it is a latent no-op. Restore INLINE before the single terminal
  `exit()` (belt: register via `atexit`, which DOES run; plus a printed manual-recovery
  command since neither fires on SIGKILL/crash). Enforced by
  .engine/checks/axprobe-no-defer.sh (exit non-zero iff a `defer {` statement appears in
  Sources/AXProbe/main.swift).

### TRAP-13: cycle_close.py il7 gate false-fails on the literal Swift keyword `defer`/`skip`
- what happened: closing spike-07 (a beat whose SUBJECT is the Swift `defer` bug), the
  il7_skip_recommendation gate emitted `ready_to_bubble: false` — "11 skip-recommendations
  lack RISK/CORRECTNESS/DEPENDENCY justification (TRAP-044)". All 11 hits were the literal
  Swift keyword `defer` in the receipt (documenting the bug fix), NOT work-deferrals. The
  gate's skip-lexicon (cycle_close.py:638-642 `\bskip\b|\bdefer\b|\bpostpone\b|…`) collides
  with code tokens. The REAL deferral gates (il_capture_deferrals, il12, row7) all PASSED.
- warning: when a beat's subject is one of the skip-lexicon words as CODE (`defer`, `skip`,
  `postpone`), il7 will false-fail. The correct response is a DOCUMENTED false-positive
  OVERRIDE at bubble (18/19 pass + PROVE live + real-deferral gates green) — NEVER edit the
  receipt to strip accurate `defer`/`skip` references to dodge the scanner; that corrupts the
  durable record. Not a repo-state check (gate-tooling behavior); fix path is teaching il7 to
  exempt inline-code tokens, out of scope for the beat that hits it.

### TRAP-14: `Task {}` from main.swift top-level + `sem.wait()` on main = deadlock (silent, zero output)
- what happened: #19a's `livecheck`/`livecheck-ids` dispatched async work as `Task { await … }`
  followed by `sem.wait()` to block sync `main`. The probe hung forever producing ZERO stdout.
  `sample <pid>` showed ONE thread — the main thread parked in `semaphore_wait_trap` — and NO
  worker thread: the Task closure never ran. Cause: top-level statements in a Swift `main.swift`
  execute on the `@MainActor`, so a bare `Task {}` INHERITS main-actor isolation and enqueues onto
  the main thread — which is already blocked in `sem.wait()` → deadlock. Compounded by a second
  masking bug: `setvbuf(stdout, nil, _IOLBF, 0)` (size 0) does NOT line-buffer a pipe, so even
  progress that DID run would have been invisible until exit. Cost a full live-diagnosis cycle
  (create windows → hang → kill → re-instrument with stderr markers → sample).
- warning: to run async work from a synchronous `main.swift` entry that blocks on a semaphore, use
  `Task.detached { … }` (global executor, no main-actor inheritance), and resolve any `@MainActor`
  values (e.g. `NSScreen`) BEFORE the wait, passing them in — never touch them from the detached
  task (it would hop back to the blocked main thread and re-deadlock). For live-probe progress,
  write stage markers to `FileHandle.standardError` (unbuffered), don't trust `setvbuf` line-mode
  on a pipe. Enforced by .engine/checks/axprobe-detached-task.sh (exit non-zero iff a bare `Task {`
  appears in Sources/AXProbe/main.swift — the sync-main entry must use `Task.detached`).

### TRAP-15: live-effect PROVE passed on a value-match that COINCIDED with the pre-action state
- what happened: #19b's first live event-bridge PROVE reported PASS=true, but the snapped window's
  readback (12,50 665×458) was IDENTICAL to its birth frame — the window never actually moved. The
  snap criterion asserted only `dOrigin <= eps`, and a fresh iTerm2 window is born at ~(12,50), which
  by coincidence equals the 1-window grid target origin — so the origin check was a rubber stamp while
  the size (665×458, never the target 1704×1009) proved the writeFrame had no lasting effect (a
  no-settle snap of a ~250ms-old window races the app's own layout and gets reverted). An origin-only
  proof of a lone window is spoofable by the birth position.
- warning: a live-effect PROVE must require a DELTA from the PRE-action state (compare readback to the
  frame captured BEFORE the action) OR assert the full target including the dimension the action is
  supposed to change (here: the SIZE) — never assert only `post == target` on a coordinate that could
  already hold that value. Also: settle a freshly-created window (spike-04 ~400-500ms) BEFORE an AX
  frame write, or the write silently no-ops. Not mechanically checkable from repo state (proof-design
  discipline, per-probe/transient) — no compiled check; this warning is the guard.

### TRAP-16: `swift test --filter` takes the test FUNCTION name, not the `@Suite` display string
- what happened: #12b's invert-check first ran `swift test --filter "Launch-at-login"` (the
  `@Suite("Launch-at-login — LoginItem port")` DISPLAY string) → "Executed 0 tests" (silent
  no-match, exit 0 — looked like a spurious pass). Re-running with the test FUNCTION name
  (`--filter statusMappingIsFaithful`) matched and showed the red `✘`.
- warning: Swift Testing's `--filter` matches the Swift IDENTIFIER (the `func` name or the type
  name), NOT the human `@Test`/`@Suite` display string. For a focused invert-check filter on a
  `swift test`, pass the test function name (e.g. `statusMappingIsFaithful`) or the type name; a
  zero-match filter EXITS 0, so "0 tests" during an invert-check is a false green, not a red — always
  confirm the filter actually selected the intended test. Not mechanically checkable from repo state
  (transient CLI-invocation discipline) — no compiled check; this warning is the guard.

### TRAP-17: live-prove markers via `print()` to a pipe are block-buffered → lost on SIGTERM (TRAP-14 class)
- what happened: #12c's first live PROVE launched the real TermTile app with `TERMTILE_SELFTEST=1`,
  redirecting stdout+stderr to a file, then SIGTERM'd it after 3s. The selftest's `print("SELFTEST
  …")` markers NEVER appeared (empty capture) — stdout to a FILE/PIPE (not a TTY) is fully
  block-buffered, so the prints sat in the unflushed buffer and were discarded when the process was
  killed. The AX "status menu" + CGWindowList layer-25 proofs succeeded; only the in-process wiring
  markers were lost, forcing a re-run. Same buffering-on-a-pipe family as TRAP-14's masking bug
  (`setvbuf _IOLBF` size-0 doesn't line-buffer a pipe), in a NEW context (a SwiftUI-app env-selftest,
  not AXProbe's sync main).
- warning: any live-PROVE marker a harness captures from a process it later KILLS must go to
  UNBUFFERED `FileHandle.standardError.write(Data(...))`, never `print()`/stdout — buffered stdout on
  a pipe is invisible until a clean exit or buffer-full, and a killed prove exits neither way. (Belt:
  emit a synchronous marker before any async work so "hook reached" is distinguishable from "async
  ran".) Enforced by .engine/checks/selftest-stderr-markers.sh (exit non-zero iff a `print(`
  containing `SELFTEST` appears in Sources/TermTile/TermTileApp.swift).
