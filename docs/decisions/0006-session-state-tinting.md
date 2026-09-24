# ADR 0006 — Session-state tinting: AX for state, OSC for colour

Status: proposed (2026-08-28). Amended 2026-08-31 — finding 6 CORRECTED and finding 6b added
after a measurement disproved the pane-geometry claim. Supersedes nothing. Binding for backlog tasks `#37a`–`#37f` (`.engine/BACKLOG.md`). Tier 2
(Apple Events) is explicitly OUT of scope here and tracked as EvanCNavarro/TermTile#12; adopting it requires
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
   TermTile's EXISTING Accessibility grant covers this. No AppleScript, no hooks.

   ~~The blocked-state signal is literal visible text — a live session's tail read
   `⧉  waiting-on-a-person`.~~ **RETRACTED 2026-08-31 — see finding 10. That string is a
   task LABEL, not a state, and reading it as one was a defect that shipped.**

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

   This is the strongest argument yet for Tier 2 (EvanCNavarro/TermTile#12), which has no
   pane problem at all.

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

7b. **iTerm's AX text carries NUL where padding sits.** The rendered "shift+tab to cycle"
   arrives as `shift+tab\0to\0cycle` (U+0000, measured on a live pane 2026-08-31). Every marker
   containing a SPACE therefore matched only intermittently, which is why the hyphenated
   `waiting-on-a-person` always worked while the others flapped. The classifier now normalizes
   padding to single spaces, preserving newlines so a marker's words on two rows cannot fabricate
   a phrase that was never rendered.

8. **THE GREEN STATE DOES NOT CURRENTLY WORK, and the obvious marker is a false green.**
   `shift+tab to cycle` was used as the READY marker until 2026-08-31. Measured on a window that
   was ACTIVELY RUNNING a command:

   ```
   contains 'esc to interrupt'   : false
   contains 'shift+tab to cycle' : true
   ```

   It indicates "the input box is rendered", not "the agent is idle". As a READY marker it paints
   a window green while work is still running — and green invites the user to interrupt live work,
   which makes it worse than no signal at all. It has been REMOVED with no replacement guessed at.

   **Consequence, and it is a real reduction in what Tier 1 delivers:** blocked (amber) and working
   (normal) classify; READY does not, so idle sessions read `.unknown` and stay untinted. The
   feature currently cannot turn a window green. Shipping the coordinator (backlog `#37e`) before this is
   solved would deliver a tinter that never shows the state the user most wants to see.

   Note this is the SAME ambiguity the out-of-tree hook existed to work around, arriving from the
   other direction: that tool could not separate "finished" from "waiting on you" and solved it with
   a hook; reading the screen solves THAT, but cannot yet separate "finished" from "working". The
   session-name glyph the old poller reads (`✳` idle vs spinner) remains a candidate — it is
   AX-readable as `AXTitle`, but is suppressed on windows with a manual title override, which is
   most of the real ones. Tracked as EvanCNavarro/TermTile#6.

9. **Ready detection, solved by MEASUREMENT rather than a marker.** Finding 8 removed the false
   green and left no ready signal. Three candidates were then measured against ground truth from
   the session-name glyph (`✳` idle, spinner working) — 4 samples across 6 live sessions,
   24 observations:

   | candidate | caught working | misfired on idle |
   |---|---|---|
   | `AXTitle` glyph | 1 of 6 windows only | — |
   | character-count moved | 2 of 8 | 0 of 16 |
   | wider (~2k) tail has interrupt affordance | 7 of 8 | 0 of 16 |
   | **EITHER of the last two** | **8 of 8** | **0 of 16** |

   The `AXTitle` glyph is out: it carries the state only on windows WITHOUT a manual title
   override, and 5 of the 6 real windows have one. That is worth stating plainly — the signal the
   old poller relies on is present in the session NAME, and only Apple Events reads that when the
   window title is overridden. It is the strongest argument yet for Tier 2 (EvanCNavarro/TermTile#12).

   The two surviving signals are complementary, not redundant: a Claude session redrawing in place
   holds its character count steady while a Codex session's interrupt affordance sits outside the
   short tail. Each alone missed a different working session; together they missed none.

   **The count delta can be NEGATIVE** (an observed sample moved -18 as scrollback re-rendered), so
   the test is `!= 0`. A `> 0` test scores that session idle and paints a working window green.

   **READY requires a MEASURED delta.** On the first poll of a session there is no previous sample,
   so stillness has not been observed, only assumed — that classifies `.unknown`. "We have not
   looked twice yet" and "this session is idle" are different claims and only one is safe to paint.

   **Consequence:** the reader becomes STATEFUL. The coordinator (backlog `#37e`) must hold the previous
   character count per session between polls. That is the one architectural requirement this
   finding adds.

10. **`⧉ <text>` is a task LABEL slot, and reading it as a state was wrong.**
   `waiting-on-a-person` was taken from a live tail on 2026-08-28 and shipped as the sole blocked
   marker. Re-measured across five live sessions on 2026-08-31:

   | session | `⧉` slot | session-name glyph |
   |---|---|---|
   | invela-marketing-suite | `waiting-on-a-person` | `✳` IDLE |
   | pushtext | `icon-marks` | `✳` IDLE |
   | portfolio | `portfolio-roster` | `✳` IDLE |
   | termtile | *(no slot)* | working |
   | ChangeFabric | *(no slot)* | `✳` IDLE |

   Three different values in the same slot, all on IDLE sessions, and two sessions with no slot at
   all. If the first meant "blocked on a human", the other two would mean the same thing in other
   words. It is whatever the user named their task.

   The marker reported one session as blocked in EVERY pass for hours while it sat idle. **A false
   amber is worse than a missing one** — it calls the user to a window where nothing is wrong, and
   a signal that cries wolf stops being read.

   **This also retracts a comparison.** PR bodies and the verification doc claimed TermTile beat
   the out-of-tree poller because it reported `blocked` where the poller's glyph said idle. The
   poller was RIGHT and this was wrong. The `✳`-versus-blocked ambiguity that the old hook exists
   to resolve is real, and nothing here has resolved it.

   **Consequence:** blocked-detection is ABSENT. Those sessions classify `.unknown` and stay
   untinted; amber never fires. A real marker needs a captured sample of a genuinely blocked
   session — rare under `--dangerously-skip-permissions` — tracked as EvanCNavarro/TermTile#6.
   The ordering guard in `TintingDriverTests` is weakened by the same retraction and is named for
   what it now proves; restoring it depends on that marker too.

11. **A real blocked marker, produced deliberately: `Esc to cancel`.**
   Finding 10 left blocked-detection absent. Rather than wait to stumble on a blocked session, one
   was CREATED: a scratch Claude session driven into an `AskUserQuestion`, which blocks on a human
   regardless of permission mode. Its tail was read through the same ranged AX read the production
   adapter uses — not a separate dump, since tails move between reads.

   A/B at the window the blocked matcher actually uses (400 chars), 1 blocked vs 6 non-blocked:

   | session | `Esc to cancel` |
   |---|---|
   | the blocked scratch session | **YES** |
   | the other six | no, all six |

   Measured at 2000 chars, one non-blocked session DID match — because the probe's own output was
   sitting in its scrollback. The 400-char window scopes the match to the live UI footer and
   excluded it. **That is mitigation, not immunity**: a session DISPLAYING the string still matches,
   which is inherent to text markers and is recorded in the code.

   `Esc to cancel` was chosen over `Enter to select` as the footer's common half. The
   trust-this-folder prompt renders `Enter to confirm · Esc to cancel` — READ from a screenshot,
   NOT captured live, so that second shape is expected-not-verified.

   **The earned version of a claim finding 10 retracted.** Live, the blocked session's
   session-name glyph reads `✳` — IDLE — while it is definitively waiting on a human. TermTile
   reads it as blocked and is right, verifiably, because the block was created on purpose. Full
   pass, 7 of 7 correct against ground truth. That IS the `✳` ambiguity the out-of-tree hook exists
   to resolve, and reading the screen now resolves it — which the earlier false positive only
   appeared to do.

12. **WezTerm ignores OSC 1337 `SetColors` — the portability argument was wrong.**
   Measured with WezTerm installed and running. Writing `\033]1337;SetColors=bg=6A1B9A\a` to its
   tty left the background BLACK.

   The instrument was checked first, because "nothing happened" and "the write never arrived" look
   identical: plain text written to the SAME tty (`WEZTERM-CHANNEL-CHECK-12345`) rendered in the
   window. The channel works; WezTerm consumes the sequence and does nothing with it.

   **This reverses an argument made in this ADR's own Consequences and repeated to the user.** The
   claim was that OSC is a terminal PROTOCOL rather than an app API, so Tier 1's write path was the
   more portable route and Tier 2's iTerm2-only nature counted against it. Measured, Tier 1 is
   **also iTerm2-only** — portability is not a discriminator between the tiers at all. The original
   objection, that this feature works for only one of TermTile's two supported terminals, was
   CORRECT; calling it "wrong, and backwards" was itself wrong.

   Only the WRITE path was measured. The read path on WezTerm — AX text areas, a window-number
   badge, a session-id environment variable — was NOT tested, and is moot for tinting while the
   write path fails. That is an untested gap, not a verified absence.

   **Consequence:** Session tint is iTerm2-only. The README advertised "iTerm2 or WezTerm" as
   targets and described the feature without scoping it, which over-promised.

13. **The OSC and AppleScript write paths disagree because they use DIFFERENT COLOUR SPACES.
    An OSC 1337 `SetColors` triple is read as Display P3; `background color` sets and reports
    Generic RGB.** (2026-09-01, EvanCNavarro/TermTile#29.) Finding 12's measurement — `#143C22`
    over OSC reading back as `#003018` — was correct but undiagnosed, and two of my own
    explanations for it were wrong before this one.

    Wrong twice, both recorded because the errors are instructive:
    - "The red channel surviving `#FF0000` rules out a gamut conversion." It does not. A pure
      primary clamps back to itself under exactly the conversion it appeared to rule out.
    - "The profile says `Color Space = sRGB`, so the source cannot be P3." Those 78 keys describe
      how each STORED PROFILE COLOUR is encoded; they say nothing about how an escape sequence is
      interpreted. The config read predicted the opposite of the measurement, and the measurement
      won.

    Identified, not guessed. Five OSC writes were read back from a scratch window with no agent
    (so the poller would not overwrite them mid-measurement — an earlier run was contaminated
    exactly that way), then every pairing of macOS's RGB spaces was applied to the requests and
    scored. `displayP3 -> genericRGB` reproduced all five to the 8-bit round with no free
    parameters; the nearest rival was out by 9.

    Then CONFIRMED on held-out colours, because an exact fit on the data that produced it is not
    evidence. Two colours were computed to split `displayP3 -> genericRGB` from
    `sRGB -> genericRGB` by 92 and 98 points, and predictions for both models were written down
    before the run:

    | write | Display P3 model | sRGB model | terminal said |
    |---|---|---|---|
    | `#6CF6FC` | `#03FBFE` | `#5FF6FB` | `#03FBFE` |
    | `#6EFF00` | `#00FF00` | `#62FF07` | `#00FF00` |

    AppKit's conversion agrees with the terminal at full precision — 13.434/255 predicted against
    13.432/255 measured — so the transform is the platform's own, not a fitted curve.

    ~~**Consequence:** `OSCColorWriter` converts Generic RGB to Display P3 before formatting the
    escape sequence.~~ **SUPERSEDED THE SAME DAY — see finding 14.** That fix worked and was
    live-proven, but it was the wrong shape: it compensated for a default instead of overriding
    it.

14. **`SetColors` takes an explicit colour space, and naming it removes the problem rather than
    correcting for it.** (2026-09-01, EvanCNavarro/TermTile#29.) The escape accepts
    `cs:RRGGBB` where `cs` is `srgb`, `rgb` (the device space) or `p3` — documented since iTerm
    3.3, and absent from every measurement in finding 13 because I characterised the protocol's
    BEHAVIOUR without reading its SPECIFICATION. Doing the second first would have skipped the
    entire space-identification exercise.

    Finding 13's measurement was not wasted and was not wrong — it is what makes the default
    legible. Confirmed directly this time rather than inferred: `p3:143C22` and bare `143C22`
    read back byte-identically (`0,12253,6093`), which pins the unprefixed default to Display P3.

    The load-bearing surprise was `rgb:`. I predicted it would read back `#112F1A`, the same as
    `srgb:`; it read back `5139,15419,8737` — **exactly the value the AppleScript poller writes.**
    iTerm's device space and AppleScript's `background color` space are the same one, so the
    palette hex needs no conversion at all.

    **Consequence:** `OSCSequence.setBackground` emits `bg=rgb:HEX` and nothing converts. All six
    palette colours render as exactly the hex they request, drift 0 including `readySubtle`,
    whose 1/255 residual was an artefact of the conversion and not of the colour. Three
    dependencies disappear with the arithmetic: on iTerm's undocumented default, on AppKit
    agreeing with iTerm about Generic RGB's primaries, and on the transform being
    display-independent — `rgb:` and AppleScript name the SAME space, so they cannot diverge on
    any display. That resolves EvanCNavarro/TermTile#31, and returns the write path to the pure
    core with no AppKit in it.

    Residual risk: an iTerm older than 3.3 would not parse the prefix. Untested — this machine
    runs 3.6.11.

15. **A text marker needs a POSITION, not just a window. The blocked marker now matches only on
    the final line.** (2026-09-01, EvanCNavarro/TermTile#34.) Finding 11 shipped `Esc to cancel`
    with a stated known limit — a session that DISPLAYS the string matches — and named the
    400-character window as the mitigation. That was too weak, and the issue's own wording
    ("unlikely, not impossible") was too generous: an idle session asked to print the string ONCE
    was scored `blocked` and would have been painted amber. 400 characters is several screen rows.

    The discriminator was measured, not reasoned about. A real blocking prompt REPLACES the status
    footer, so its marker is the last text in the pane; text that merely mentions the phrase is
    followed by the footer still being drawn.

    | pane | marker position | what follows | status footer |
    |---|---|---|---|
    | blocked — AskUserQuestion | final line | nothing | absent |
    | blocked — plan-mode question | final line | one newline | absent |
    | blocked — Bash permission prompt | final line, at its START | nothing | absent |
    | displayed, NOT blocked | ~150 chars from end | `──── / [Opus 5…] / …/rc` | present |

    The third row is the one that matters, because it was captured AFTER the rule was chosen and
    is a different UI family. Getting it needed a project-local `permissions.ask` rule: the global
    config is `defaultMode: auto` with an empty allowlist, which is why three earlier attempts
    produced no prompt at all.

    **It confirms two decisions that were otherwise only arguments.** A co-occurrence rule keyed
    on `Enter to select` — the more semantic option, and the one I nearly took — would have
    returned a false NEGATIVE on every permission prompt, whose footer reads `Tab to amend` and
    `ctrl+e to explain` instead. And "final LINE" beats "end of tail": here the marker sits at the
    START of its line.

    **Consequence:** `AgentStateClassifier.markerOnFinalLine` gates both classify entry points.
    The whole state space was enumerated as a table and run against the old code first — exactly
    four rows moved, eight read identically. Proven live in both directions on real panes: the
    displayed-marker pane went blocked → ready, a real block still reads blocked and still paints
    `#4A320F`.

    Residual: an unreproduced prompt shape that renders its marker above a footer would be missed.
    That is a false NEGATIVE — an unpainted window rather than a wrong one, which is the safe
    direction for this feature.

16. **Green meant "finished" and was painted on sessions that were not finished. There is now a
    fourth state.** (2026-09-23, EvanCNavarro/TermTile#47.) A turn that ENDED while a shell it
    launched was still running showed neither of `WorkingSignal`'s tells — the interrupt affordance
    goes with the turn, the character count is static because nothing renders — so it fell through
    to `.ready`. That is finding 8's false green, the failure this feature can least afford,
    reached by a route finding 8 did not anticipate.

    Observed live twice before any code changed: a Codex session reading `2 background terminals
    running` and a Claude Code session reading `1 shell`, both tinted `5139,15419,8737`.

    The marker was battle-tested rather than assumed, by starting exactly one background shell and
    letting it end:

    ```
    BEFORE   bypass permissions on (shift+tab to cycle) · 1 agent     no count
    DURING   bypass permissions on · 1 shell · 1 agent                marker present
    AFTER    bypass permissions on (shift+tab to cycle) · 1 agent     no count
    ```

    Absent to present to absent on one controlled variable. These counts are TOOL-rendered, the
    quality bar of finding 9, not model prose like finding 10.

    **The final-line rule from finding 15 could not be reused.** Measured, this marker never sits
    on the final line: the status line is three to four lines up, above the `/rc` line and the task
    slot. The guard is instead three-part — a NUMBER before the phrase, chrome that only the real
    footer carries on the SAME line, and that line inside the last five non-blank lines.

    All three parts were proven load-bearing by planting each defect in turn and watching a named
    row go red. **The first version of that test caught none of them**: its false-positive fixture
    ran to ~560 characters, so `tail.suffix(400)` removed the quoted text before any guard saw it,
    and the truncation passed the test on the guard's behalf. The footer window was also inert at
    eight lines, since a 400-character tail rarely holds more than that. Both were found only by
    planting, and the suite now asserts that its own fixtures survive truncation.

    **Consequence:** `AgentState.pending`, painted `#1C2E3C`. Precedence is blocked > working >
    pending > ready, and pending sits AFTER the baseline guard so a session seen for the first time
    still paints nothing. Verified on the real coordinator against live panes: three sessions that
    were being painted green now paint blue, each corresponding to a real count in its footer, and
    the genuinely idle ones stayed green.

    **AMENDED 2026-09-23, same day.** The first value, `#163A56`, was too loud and the ADR carried
    its separations PERMUTED — the measuring script's column headers did not match its iteration
    order, so "27.5 from normal" was really 27.5 from ready. True figures for that value: 16.5 from
    normal, 27.5 from ready, 31.3 from blocked.

    The substantive error the wrong labels hid: at lightness 23.2 and chroma 20.8, against green's
    21.9 and 24.3, the blue was the BRIGHTER of the two. It out-shone the state it exists to defer
    to. Green is what a user wants to catch across a screen of windows; blue only says "nothing for
    you yet", so it must be the quieter of the pair.

    `#1C2E3C` sits under green on every axis that draws the eye — lightness 18.0, chroma 11.5, and
    dE2000 10.4 from `normal` against green's 22.3, so 47% as prominent. It stays unmistakably a
    colour rather than a lighter `normal`, which is itself a near-neutral blue-grey at chroma 2.4:
    this carries 4.7x that, sits 23.1 from `ready` and 26.7 from `blocked`, and its text contrast
    of 8.3:1 is better than green's 7.3:1.

    NOT fixed: a session whose footer is hidden behind a scroll overlay shows no marker, and an
    agent that says it is waiting on a deploy with no background shell has no observable signal at
    all. This reduces false greens; it does not eliminate them. The prose convention `WAITING ON X`
    is deliberately NOT matched — it is model-written, which is what findings 8 and 10 were both
    about.

17. **Loop state cannot be read off the screen, so it is DECLARED.** (2026-09-23,
    EvanCNavarro/TermTile#51.) A session running a long `/loop` alternates between running a cycle
    and waiting for a scheduled wakeup, so it flickered between `working` and `ready`/`pending`.
    Bobby asked for one colour held until the loop ends.

    **The dormant stretch is why this needed a new mechanism rather than a new marker.** Measured
    on a live `/loop /goal` session: during one, the pane is idle by every observable signal — no
    interrupt affordance, static character count, and the tool's own session registry reporting
    `idle`. It painted GREEN, meaning finished, while the session was mid-task and about to resume
    on its own. That is a false green on a session doing work, which is worse than the flicker.

    Everything derivable was measured and ruled out:

    | source | why not |
    |---|---|
    | scrollback markers | `/loop`, `Claude resuming`, `Cycle N` sat 100+ lines back; the classifier reads ~400 chars. All HISTORICAL — the nearest belonged to a finished cycle, so matching it paints purple forever after any loop ever ran |
    | the `⧉` task label | NOT user-settable. pushtext's label reads `icon-marks` while its branch is `master`; portfolio's reads `portfolio-roster` on `main`. Not branch, worktree, or registry name |
    | `~/.claude/sessions/<pid>.json` | tool-maintained and tty-mappable, but `status` is only `busy`/`idle`/`shell` — 10-minute sample across 7 sessions, and the looping session read `busy` like any other |
    | `scheduled_tasks.lock` | one session id for whoever holds the scheduler lock, not pending wakeups |
    | `WAITING ON SCHEDULED WAKEUP` prose | model-written, the class findings 8 and 10 were both about — and present only BETWEEN cycles, so it could not hold one steady colour anyway |

    **Consequence:** `AgentState.looping`, painted `#2A2438`, driven by a flag the session writes at
    `~/.claude/termtile-loop/<tty>` containing its pid. `LoopFlagReading` is a port; the core stays
    pure and takes `StateEvidence.isLooping` as an answer (ADR-0001). Precedence is
    blocked > looping > working > pending > ready — blocked outranks it because a loop waiting on a
    human needs the user NOW, and purple says "leave it alone". It sits ABOVE the baseline guard,
    unlike `ready` and `pending`: those infer stillness and need a previous sample, while this is
    declared and is evidence on the first poll.

    **The pid is the entire safety story.** A flag left by a killed loop would strand a window
    purple — finding 10's shape exactly, a durable marker outliving its state. TermTile ignores AND
    deletes a flag whose process is gone, so it self-heals. Proven on the real path: a live flag
    produced `looping` and `#2A2438`; killing the owner produced `ready` and the file was reaped.

    **This reintroduces an out-of-tree flag of the kind #27 just removed, and that is a real cost.**
    The distinction claimed: those flags existed because TermTile could not see the screen and died
    the moment it could; this one exists because the screen does not carry the answer and cannot be
    made to. A signal that is underivable is a different case from one that was inconvenient.

    NOT automatic on its own — something must call `scripts/loop-flag.sh set` and `clear`. A
    tool-side loop indicator, in the footer or the session registry, would replace this entirely.

18. **The standing watch found a real false negative — by DRIVING the states instead of waiting for
    one.** (2026-09-23, EvanCNavarro/TermTile#39.) The watch had been framed as needing a
    real-world sighting: something only daily use could surface. Bobby asked whether each open item
    could be triggered deliberately in a terminal. It could, and doing so found the defect in about
    four minutes.

    Six blocked shapes were produced on demand from one scratch project with a
    `permissions.ask` rule — AskUserQuestion, a plan-mode clarifying question, and Bash, Edit,
    Write and WebFetch approvals. Five carry `Esc to cancel` on the final line and classify
    correctly. **WebFetch carries it nowhere:**

    ```
    Do you want to allow Claude to fetch this content?
    > 1. Yes
      2. Yes, and don't ask again for example.com
      3. No, and tell Claude what to do differently (esc)
    ```

    The escape affordance renders inline as `(esc)` inside the decline option. Measured on the live
    pane: zero occurrences of the marker in the 400-character tail, and the window painted
    `#143C22` — GREEN, meaning finished — while genuinely waiting for an answer. Worse than the
    missed amber the watch anticipated: finding 8's false green, on a session blocked on the user.

    **Consequence:** a second marker, `tell Claude what to do differently`, which sits on the final
    line and so obeys finding 15's rule unchanged. Proven on the real path — the same live pane
    that read green then read `blocked` and `#4A320F`.

    **The method is the durable part.** A watch that waits is a watch that reports nothing; the
    same scratch-project technique produces any of these shapes in minutes, and it is what should
    be run against a new marker rather than a fixture written from memory.

    A vacuous green nearly shipped inside this fix: the first three tests injected a marker set
    through the test seam, so they passed whether or not PRODUCTION carried the new marker. The
    test that calls the production overload is the one that went red.

19. **Tier 2's central claim is MEASURED, and Tier 1's ceilings are measured as NOT-YET-HIT.**
    (2026-09-24, EvanCNavarro/TermTile#12.) Tier 2 had been argued for from its ceilings alone —
    "Apple Events has no pane problem at all" was an inference nobody had run. It needed no
    prototype: `osascript` reaches iTerm2 from an ordinary shell, so both halves are one command.

    **The real workload is not hitting any ceiling.** Census of every agent session, read through
    the app's own `ProcessTTYProbe` and `AXSessionReader`:

    ```
    CENSUS sessions=8 visiblePanes=8
    CEILINGS windows=8 multiSessionWindows=0 cwdCollidingWindows=0 beyondBadgeCeiling=[]
    ```

    Eight single-session windows, no cwd collision inside any window, nothing past badge 9, and
    `sessions == visiblePanes` so no background tab is hidden. The trigger clause "Tier 1's
    ceilings prove annoying in daily use" is measurably not firing.

    **Planted the ceiling rather than trusting that zero.** A split in the TermTile window with a
    second agent process `cd`-ed to the same directory:

    ```
    WINDOW w5 badge=6 sessions=2 collidingCwd=true
        t0p0 tty=/dev/ttys005 cwd=termtile
        t0p1 tty=/dev/ttys008 cwd=termtile
    CEILINGS ... multiSessionWindows=1 cwdCollidingWindows=1
    VERDICT unknown wrote=false tty=- ambiguity=multipleCandidates cwd=termtile
    VERDICT unknown wrote=false tty=- ambiguity=multipleCandidates cwd=evancnavarro
    WOULD-PAINT 8            (9 with the window resolved, 10 with it split but cwds distinct)
    ```

    So the instrument can say both yes and no. And the **cost is larger than the ADR states**:
    finding 6b says such a window "is left untinted", which reads as the new pane losing its
    colour. Both panes go unresolved, so a window that was correctly tinted a second earlier goes
    dark — a split costs the tint of the session that was already working. With DISTINCT cwds the
    same split resolves cleanly: both panes tinted, no ambiguity.

    **Apple Events resolves exactly that case, by tty, with no join at all:**

    ```
    AS-w1t0p0 tty=/dev/ttys005 name=◑ iTerm2 color integration in termtile (node)
    AS-w1t0p1 tty=/dev/ttys008 name=claude
    ```

    It also carries the state glyph in the session NAME on windows whose `AXTitle` is overridden
    (`✳` idle, `◐`/`◑` working, observed live across all eight windows) — finding 9's premise,
    confirmed on the real set rather than argued from one window.

    **Two things Tier 2 must not assume.** AppleScript window order is NOT the
    `ITERM_SESSION_ID` window index — AS `w0` was `ttys007`, whose id says `w7` — so ordering is
    z-order and cannot be used as identity; the tty must be. And the absence of a >9-window
    ceiling for Apple Events is INFERRED, not measured: it enumerates `windows` directly, but only
    eight were open.

    **Trap, for whoever plants this next.** `/bin/sleep` is SIP-protected and macOS blanks a
    restricted binary's environment block — 11 bytes against 39,015 for a real session — so
    `ITERM_SESSION_ID` is unreadable and the plant simply does not register, looking like a probe
    bug. A copy of the binary is SIGKILLed for a broken signature. Plant with a non-restricted
    interpreter; `node` is what the real agent runs anyway.

    **The decision is unchanged.** Every cost in EvanCNavarro/TermTile#12 is still unpaid — a
    third TCC prompt, a permanent iTerm2-only binding, a weaker README privacy story, and the ADR
    amendment this document requires. What has changed is that the case for it rests on
    measurement now, and the case against it is stronger: the ceiling it removes is one the real
    workload does not reach.

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
Tier 1; that is Tier 2's job (EvanCNavarro/TermTile#12).

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
- ~~Portable in principle beyond iTerm2: OSC 1337 is a terminal protocol, not an app API, so
  the write path has a route to WezTerm (already a TermTile target) that AppleScript never
  had.~~ **DISPROVEN 2026-08-31 — see finding 12. WezTerm ignores OSC 1337 `SetColors`, so
  Tier 1 is iTerm2-only in practice, exactly like Tier 2.**
- Ceilings accepted in Tier 1: >9 windows lose the badge and fall back to cwd; background
  tabs are unreadable; sessions sharing a cwd with no badge are ambiguous and stay untinted;
  and per finding 6b any multi-session window whose sessions share a cwd is likewise untinted.
- The README privacy section must be rewritten in the shipping change, not after it.

## Alternatives rejected

- **Apple Events (Tier 2).** Exact mapping with no join problem, handles background tabs,
  >9 windows and splits, and `text of session` supplies state hook-free. Rejected as the
  DEFAULT because it needs `com.apple.security.automation.apple-events`, a usage string, and
  a third TCC prompt, and it locks the feature to iTerm2 permanently. Deferred to EvanCNavarro/TermTile#12 as an
  opt-in upgrade for users who hit a Tier 1 ceiling.
- **iTerm2 Python/WebSocket API.** `EnableAPIServer` is on and the socket is live. Full
  fidelity, but it means a protobuf websocket client for a job two simpler mechanisms
  already do.
- **Nonce-probe join.** Fails on window-title overrides (finding 7).
- **tty-side-only, no AX.** Fails for Claude Code (finding 8).
