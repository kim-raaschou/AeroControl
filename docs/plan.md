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

## 3. App version visible in the menu — DONE

The menu-bar (status item) menu leads with a disabled row showing `AeroControl <version>`
(from `ACReleaseVersion`, falling back to `v` + `CFBundleShortVersionString`, then `dev` when
run unbundled via `swift run`), followed by a second disabled row `Compatible with AeroSpace ≥
0.21.1`. Since `script/release.sh` stamps the version keys, the shipped app shows its real
release version. `Sources/AeroControlEntry/QuitTriggerController.swift`.

---

## 4. Verification gates (hooks + CI) — DONE

- `.githooks/pre-commit`: code-metrics guard (fast, every commit).
- `.githooks/pre-push`: full `swift test` suite before every push.
- `.github/workflows/ci.yml`: `macos-26` runner (Xcode 26.2) builds, tests and re-runs the
  metrics guard on push/PR to `main` — the authoritative, non-bypassable backstop (local hooks
  are per-clone and `--no-verify`-bypassable). README carries the CI status badge.

---

## Considered but not planned (YAGNI)

- **Split the AeroSpace CLI contract into its own `AerospaceClient` module.** The parser lives
  in `Sources/Common/Aerospace/` and is already pinned by drift-guard contract tests; a new
  module adds structure without removing code, against the current reduce-code ethos.
- **`PrivateApi` C-shim for AX symbols.** No `@_silgen_name` private-symbol linkage remains in
  the tree, so there is nothing to isolate.
- **Startup AeroSpace version gate** (run `aerospace --version`, parse `v0.21.2-Beta`, block if
  below the floor). Crew audit 2026-07-14 rejected it: a version *number* never proves the CLI
  field/event contract is intact (false confidence), a genuinely-too-old AeroSpace that drops a
  required field already fails loud on the initial load, and parsing AeroSpace's evolving
  version string is permanent maintenance surface for a weak signal — poor value against the
  ~50-line metrics headroom. Only pursue if real users hit confusing stale-HUD behavior.
- **Loud event-stream / steady-state reload** (options B/C from the same audit). Deferred: the
  silent paths are low-blast-radius (AeroSpace itself keeps working; the HUD merely goes stale),
  and making reloads loud risks transient-error banner spam without a consecutive-failure guard.
  Revisit only if stale-HUD confusion is observed in practice.

---

## Retired plans (folded in or made obsolete)

All removed from `docs/`; git history keeps the full text.

| Retired doc | Why |
|---|---|
| `architecture-review-plan.md` | Done: `Common` purity, TEA completion, AppDelegate decomposition, Kit role-folders, and Swift-6 + `strictMemorySafety` all landed. |
| `complexity-review-2026-07.md` | Its top items (runner rewrite, `initialFloatingSize` removal, `refreshTask` bug, CRLF→LF) are all done. |
| `full-app-review-2026-07.md` | Layout-subsystem deletion, serialized refresh, small bug fixes and comment polish all landed. |
| `code-review-simplification-plan.md` | Wins done or obsoleted; `GapConfig`-based items (S3/S11) reference removed code. |
| `config-parameters-assessment.md` | Self-marked superseded by the all-floating model; most flags described no longer exist. |
| `config-parameters-assessment-plan.md` | Meta-plan for the assessment above; its deliverable shipped. |
| `floating-overview-plan.md` | Implemented (the current all-floating widget). |
| `liquid-glass-rework-plan.md` | Implemented; the two surviving optional items are captured in §2. |
