# AeroControl — Plan (open work)

The single source of truth for **remaining, actionable work**. Everything that was
already implemented or made obsolete by the all-floating rewrite has been removed —
that history lives in git and the durable architecture/principles live in `AGENTS.md`.

> Consolidates and retires nine earlier planning docs (see *Retired plans* below).

> **How we work:** every item below is executed the crew way — discussed, verified and
> reviewed by the crew before it ships (see *How we work: the crew* in `AGENTS.md`).

---

## 1. Homebrew distribution — pipeline built; awaiting first publish

Ship AeroControl via `brew install --cask kim-raaschou/tap/aerocontrol`, mirroring
AeroSpace's release model (own tap → GitHub Release → cask bump).

**Versioning — independent (own SemVer) + compatibility metadata.** AeroControl versions on
its **own SemVer** (currently **v0.1.0**); the number describes AeroControl's own changes.
Compatibility is a *range* — currently **AeroSpace ≥ 0.21.1** — shown as a separate line in
the menu, NOT encoded in the version number. Crew decision (2026-07-13): aligning the number
to AeroSpace gives a *false* safety signal, and lockstep creates release-engineering
awkwardness (AC-only fixes, AeroSpace version jumps). **Compatibility protection is partial and
honest about it** (crew audit 2026-07-14): the *only* runtime check is the throwing decoder on
the initial `loadOverview`, which fails loudly on structural breaks to the required
`list-windows`/`list-workspaces` fields; the event stream, steady-state reloads, `loadMonitors`
and `TolerantInt` all degrade *silently* by design, and there is **no runtime version gate** (a
startup gate was considered and rejected as false-confidence — see YAGNI section). `Info.plist`
→ `CFBundleShortVersionString 0.1.0`; `ACReleaseVersion v0.1.0` (menu display string). Bump
AeroControl's version for AeroControl changes; bump the compatibility range only when the
supported AeroSpace floor moves.

**Model:** own tap (no homebrew-cask gatekeeping); artifact = zipped `.app` on a GitHub
Release with `version`/`sha256`/`url`; **no notarization** — ad-hoc sign (`codesign -s -`)
and strip the Gatekeeper quarantine in the cask `postflight` (`xattr -dr
com.apple.quarantine`). Default build is **arm64-only** (macOS 26 is Apple-Silicon-era);
set `ARCHS="arm64 x86_64"` for a universal build.

**Done (in this repo):**
- `script/release.sh` + `make release VERSION=x.y.z [PUBLISH=1]`: tests → release build →
  version-stamped, ad-hoc-signed `.app` bundle → zip → sha256 → generated cask, all into the
  git-ignored `.release/`. `--publish`/`PUBLISH=1` also tags and cuts the GitHub Release via
  `gh`. The script is the single version source of truth (stamps `Info.plist`).
- `Packaging/aerocontrol.rb.tmpl` — the cask template (`__VERSION__`/`__SHA256__` filled in).
- README "Install" leads with the brew cask; `make install` kept as the from-source path.
- Removed the stale, broken `Formula/aerocontrol.rb` (referenced a non-existent `TUIOverlay`
  product and the wrong homepage/OS).
- Verified end-to-end with a dry run (build → bundle → zip → sha256 → cask all succeed).

**Remaining (external — needs the maintainer):**
1. Create the tap repo `kim-raaschou/homebrew-tap`.
2. Run `make release VERSION=0.1.0 PUBLISH=1` to cut the first GitHub Release.
3. Commit the generated `.release/aerocontrol.rb` to the tap as `Casks/aerocontrol.rb`.
4. Then `brew install --cask kim-raaschou/tap/aerocontrol` works.

**Open decisions (deferred, sensible defaults chosen):** arm64-only vs universal (default
arm64, override via `ARCHS`); local `make release` vs CI automation (local for now, mirroring
AeroSpace's manual publish step).

---

## 2. Optional visual polish (Liquid Glass) — backlog, low priority

The Liquid-Glass rework is essentially done (frosted `.regular` cards, single focus plate,
`GlassEffectContainer`, reduce-transparency a11y fallback, specular sheen). Only optional
items remain, each a design call rather than a fix:

- **`glass-effect-id`** — morph the selection plate when focus moves between cards
  (`.glassEffectID` matched geometry). Purely aesthetic.
- **`glass-empty-intent`** — render empty, non-focused workspaces as *badge only* (closer to
  Cmd-Tab). **Gated** — a larger visual-design decision; confirm before implementing.

Guiding principle (unchanged): each workspace reads as a Cmd-Tab panel — frosted glass, icons
in a row, focused element gets a light selection plate, no drawn borders.

---

## 3. Dead-tile on window close — push fix (in progress)

**Problem:** AeroSpace emits **no** window-closed event, so a background window closing
without a focus change leaves a stale tile in the overview. Confirmed empirically: closing a
background window produces *zero* `subscribe` events, yet `list-windows` drops it. AeroSpace
stays the source of truth — the fix only needs a push "doorbell" → `requestRefresh()`.
**No polling** (firm constraint).

Two complementary tracks:

- **Upstream event (done, PR open).** Added a native `window-closed` subscribe event to
  AeroSpace, broadcast from the single removal point `MacWindow.garbageCollect()` (covers every
  close path: close command, AX destruction, refresh reconciliation). PR to
  `nikitabobko/AeroSpace`: **#2181** (branch `feature/window-closed-event` on the fork). Once
  merged/released, AeroControl maps `window-closed` → `requestRefresh()` for full push coverage
  — no permission, no polling.
- **Local fix (chosen, pending) — works today against stock AeroSpace.**
  - Permission-free `NSEvent.addGlobalMonitorForEvents(.leftMouseUp)` doorbell →
    `requestRefresh()` (exactly what AeroSpace does internally). Covers closing a background
    window with the mouse.
  - One-shot ~150ms retry after `.appTerminated` for the app-quit race where AeroSpace hasn't
    reaped the window yet (event-triggered, fires once — not polling).
  - Files: `NativeApiBridge` (+adapter), `OverviewStore`, `OverviewStoreTests` (FakeBridge).
  - Not covered by the local fix alone: keyboard-only (Cmd-W) close of a background window —
    rare, self-corrects on the next event; fully covered once the upstream event lands.
