# TermTile — Menu-bar App Feature Research (Deep Research, 2026-07-03)

Verified deep-research (93 agents, adversarial verification; 12 findings confirmed, 1 refuted).
Question: what a direct-download macOS menu-bar utility like TermTile should include — menu,
settings, uninstall, updates, onboarding. Cross-referenced with RememBar's shipped patterns.

## What TermTile has today (v0.1.0)

Menu: **Rearrange now** · Target-app picker · Launch at login · Accessibility fix-it row (conditional)
· Check for Updates… · Quit. Sparkle wired (`startingUpdater: true` → default 2nd-launch prompt).

## v1 gaps — the must-haves a proper utility ships

Priority order for the next build phase:

1. **About panel** — what it is, version number, author/credits, links (site, GitHub, license).
   RememBar ships an `AboutPopover`; every surveyed utility has one. Cheap, expected. *(new: #18)*
2. **Uninstall (clean self-removal)** — non-App-Store apps must offer this. RememBar's
   `RememBarUninstaller` is the exact template: trash the `.app` bundle, deregister the login item,
   trash *only* the app's own owned paths (`~/Library/Application Support/<App>/`, `Preferences/
   <bundleID>.plist`, `Caches/<bundleID>`), **exact-match, never prefix/glob** (so a neighbour dir is
   never caught; the trash op is injectable so tests prove the scope). **Cannot** silently revoke the
   TCC/Accessibility grant — must guide the user (System Settings toggle, or
   `sudo tccutil reset Accessibility dev.ecn.apps.termtile`). *(new: #19)*
3. **First-run Accessibility onboarding** — the whole app is gated on the grant, and the menu-bar
   icon can be hidden by menu-bar managers (Ice/Bartender). A first-launch walkthrough (what it is →
   grant Accessibility → find the icon) is a v1 must-have. The fix-it row exists; onboarding makes it
   discoverable on first run. *(new: #20)*
4. **Settings window (Cmd-,)** — Rectangle's precedent: a dedicated tabbed window (General +
   Shortcuts) is warranted *once options exceed a handful*. TermTile has few today, so **defer** the
   window until gap/padding + multi-display land — then move config out of the inline menu. *(ties to
   #15/#17)*

## v1.x / roadmap — nice-to-haves (cited precedent)

- **Gap/padding settings** (Rectangle) — already backlog #17.
- **Multi-display behavior** (Rectangle: windows traverse displays on repeat) — already #15.
- **Per-app profiles** (#17); **global hotkey** to trigger Rearrange (Rectangle/Loop first-class);
  **config import/export (JSON)** (Rectangle); **help/feedback links**; **Sparkle update channels /
  beta** (Sparkle 2 supports it).

## Robustness the research flagged (validate at build time)

- **Grant-break on path change / duplicate copies** — *verified today*: a moved or duplicated bundle
  makes the permission dialog never reappear and the grant silently fail (the ad-hoc scratchpad copy
  vs the cert-signed `~/Applications` copy). TermTile should detect "I'm not trusted but a grant row
  exists" and warn / offer a fix, and the uninstall/onboarding flows must account for it.
- **Sparkle**: `SUFeedURL` over HTTPS ✓ (have it); default background cadence 24h (min 1h in release);
  the 2nd-launch permission prompt is deliberate — keep it. Beta channels are later.
- **tccutil syntax** is macOS-version-sensitive and undocumented by Apple — verify the reset command
  against the shipping OS when building Uninstall.

## Refuted / caveats

- Refuted: "Ice ships layout profiles / light-dark configs" — it doesn't; don't cite it for profiles.
- Competitor feature claims are from product pages (advertised, not independently tested). Sparkle
  behaviors are from Sparkle's own docs (high confidence).

## Sources (primary)
Rectangle (github.com/rxhanson/Rectangle) · Rectangle Pro (rectangleapp.com/pro) · Ice
(github.com/jordanbaird/Ice) · Loop (github.com/MrKai77/Loop) · Sparkle docs
(sparkle-project.org/documentation) · RememBar (`RememBarUninstaller`, `AboutView`, `RememBarPaths`).
