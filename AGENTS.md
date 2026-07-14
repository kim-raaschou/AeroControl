# AGENTS.md — working notes for AI agents on AeroControl

AeroControl is a **thin floating overview/companion for [AeroSpace](https://github.com/nikitabobko/AeroSpace)**,
a macOS tiling WM. AeroSpace does all the real window management; AeroControl only
visualizes workspaces and forwards user actions (focus/move/close) to the AeroSpace CLI.

## How we work: the crew (governing principle)

**We operate as a crew, not a single author. Every task — design, code, refactor,
docs, cleanup — is verified, discussed and reviewed by the crew before it is considered
done.** Concretely:

- **Discuss before deciding.** For any non-trivial choice, convene a crew of specialized
  sub-agents / models (e.g. an advocate vs. a skeptic, plus domain reviewers) and let them
  debate and cross-examine. Surface disagreements explicitly; the facilitator takes the
  final call under the project's KISS/YAGNI and trust-boundary ethos.
- **Review every change.** No task ships without a review pass by the crew (a
  `code-review`/`rubber-duck` agent or a second model), independent of the author. Reviews
  target real bugs, logic/design flaws and regressions — not style.
- **Verify, don't assume.** Claims are checked against the actual code (and against the real
  AeroSpace source when relevant), and against the test suite. "It should work" is not done.
- **Test-first where it bites** — especially the concurrency/runner code, which has only
  real-process tests.
- **One reviewable change at a time.** Small, logically-scoped commits so each decision is
  auditable in history.

This is deliberate: AeroControl's past reviews (architecture, complexity, config, simplify,
Liquid Glass) were all produced by multi-model crews with a cross-examination round. Keep
that bar.

## Build, test, metrics

- Build: `swift build` · Test: `swift test` (102 tests, swift-testing + a little XCTest).
- Targeted: `swift test --filter <SuiteOrName>`.
- The `warning: input verification failed` / `note: while processing …` lines during
  build/test are **benign** (strict-memory-safety tooling noise), not errors.
- Line endings are **LF**, enforced by `.gitattributes`. Don't reintroduce CRLF.
- Code-size/complexity dashboard: `python3 scripts/code_metrics.py` → `docs/code-metrics.html`.
  Regenerate it after notable structural changes.

### Rule: code metrics stay within baseline +1% — verified at every commit

- The tracked-Swift **code-line count and approximate complexity must not rise more than
  1% above the baseline** in `scripts/metrics-baseline.json`. The baseline stores the raw
  totals; the enforced ceiling for each metric is `floor(baseline × 1.01)` (small-refactor
  headroom so trivial churn doesn't block commits — the intent is still *don't grow*).
- This is **enforced on every commit** by `.githooks/pre-commit`, which runs
  `python3 scripts/code_metrics.py --check` and **fails the commit** if either metric
  exceeds its ceiling. Enable the hook once per clone: `git config core.hooksPath .githooks`.
- When you legitimately **reduce** code, ratchet the baseline down:
  `python3 scripts/code_metrics.py --update-baseline` and commit the new baseline (this also
  lowers the ceiling, keeping the 1% band from drifting upward).
- Sustained growth beyond the 1% band is only allowed when genuinely justified: reduce
  elsewhere to stay under the ceiling, or (as a deliberate, explained exception) run
  `--update-baseline` to re-anchor it and commit that change so the increase is reviewable in
  history. Default answer to "the metric went up" is **make it smaller**, not raise the baseline.
- The headroom lives in one constant, `MARGIN` in `scripts/code_metrics.py`.

### Rule: `Sources/Common/` stays UI-framework-free — enforced

- Files under `Sources/Common/` are the pure domain and **must not import AppKit, SwiftUI,
  Cocoa, or UIKit**. `--check` fails (blocking commit + CI) on any violation, independent of
  the size/complexity ceiling. This keeps the domain portable and testable without a UI host.

### Extra health metrics (reported, not all gated)

`scripts/code_metrics.py` / `docs/code-metrics.html` also surface, for insight: per-function
complexity (top 15) and the single longest function, max brace-nesting depth per file, and the
test-to-production code ratio. These are informational; only code/complexity ceilings and the
Common purity rule fail the build.

## Git hooks & CI (verification gates)

- **`.githooks/pre-commit`** — runs the code-metrics guard (`--check`); fast, every commit.
- **`.githooks/pre-push`** — runs `swift test` (the full 102-test suite) before every push, so
  a broken build/test never leaves the machine. Commits stay fast; the suite runs here instead.
- Enable both once per clone: `git config core.hooksPath .githooks`. Bypass in a true emergency
  with `--no-verify` (discouraged).
- **`.github/workflows/ci.yml`** — the server-side backstop the hooks can't guarantee (hooks are
  per-clone and `--no-verify`-bypassable). On push/PR to `main`, a `macos-26` runner (Xcode 26.2)
  builds, runs `swift test`, and runs the **same metrics guard**. The README CI badge shows its
  status. This is the authoritative gate: green CI, not a local hook, is what proves `main` holds.

- `Sources/Common/` — **pure domain**, no AppKit. `OverviewModel` + the pure reducer
  `updateOverview(_:_:) -> (model, [effect])` (`OverviewUpdate.swift`), CLI parsing/commands.
- `Sources/AeroControlKit/` — **adapters + the effect interpreter**. `OverviewStore`
  (`@MainActor @Observable`) owns the model, runs the reducer, and interprets effects
  (runs the CLI via the `AerospaceProcessRunner` port, loads icons, manages task lifecycles).
- `Sources/AeroControlEntry/` — the executable: windows, overlay placement, lifecycle.
- Do **not** merge the reducer into the store, and do not split `OverviewStore` just to
  satisfy a linter — its size is a symptom of the effects it owns, not accidental sprawl.

## The trust boundary (most important principle here)

"AeroSpace is trusted" applies to AeroSpace's **logical/semantic contract at the parsing
boundary** — decode what it explicitly emits strictly. It does **NOT** eliminate:

- **macOS/AppKit timing & races** (window-teardown latency, CGWindowList-vs-AeroSpace lag)
- **CLI transport** (brew symlink swap / login race at startup, a hung process)
- **CLI output-format drift** across AeroSpace versions

Defensive code guarding those three is **load-bearing — do not delete it as "paranoia":**

- `OverviewStore.suppressingDeadWindows` (+ its empty-live-set guard) — dead-tile race.
- `pendingCloseIds` suppression + the bounded close-grace poll — optimistic-close vs teardown.
- `requestRefresh` coalescing loop — ordered, storm-collapsing reloads.
- `initialLoad` retry/backoff — transient CLI unavailability at startup.
- Runner `run()` timeout + non-zero-exit handling.
- `TolerantInt` — `NULL-MONITOR*` string sentinels are **valid runtime values** on any
  version, so integer *value* tolerance stays.

What IS safe to trust away: tolerance for **fields AeroSpace always emits and the app
explicitly requests**. AeroControl documents a **minimum AeroSpace version** (README /
requirements; **≥ 0.21.1**) and stays within ~1 release, so those fields are decoded
strictly. **Scope of "fail loud" (be precise — it is partial, not global):** only the
**initial `loadOverview`** fails loudly — a rename/removal/retype of a *required* `list-windows`
/ `list-workspaces` field (window-id, app-name, app-bundle-id, workspace,
window-parent-container-layout) makes the throwing decoder fail and, after retries, surfaces a
visible `error = "Load error: …"` banner. Everything else degrades **silently by design**: the
`subscribe` event listener swallows decode failures (`AerospaceEvent.parse` → nil/`.other`,
empty `catch {}`), steady-state reloads and `loadMonitors` use `try?`, `TolerantInt` falls back
to 0, and semantic value shifts (e.g. the `"floating"` layout string) just flip a bool. There
is **no runtime version check** — the minimum is documentation, not an enforced gate. (This is
also why the generic `Fallback`/`DecodableDefault` machinery was removed.)

**Versioning policy.** AeroControl versions **independently** (its own SemVer, currently
**v0.1.0**) — the version number describes AeroControl's own changes, not AeroSpace's. A
matching number would give a *false* sense of compatibility safety: the version string never
proves the CLI field/event contract is intact. The **only** real compatibility check is the
throwing decoder on the initial load (see the trust-boundary note above), which catches
structural breaks in the required `list-windows`/`list-workspaces` fields — it does **not**
cover event-stream renames or steady-state reloads, and there is no runtime version gate.
Compatibility is a *range* (currently **AeroSpace ≥ 0.21.1**), shown as a separate line in the
menu-bar menu, not encoded in the version number. The numeric version lives in
`Packaging/Info.plist` (`CFBundleShortVersionString`); `ACReleaseVersion` holds the
`v`-prefixed display string; `script/release.sh` stamps both from the `VERSION` argument.
When AeroSpace ships a new version, verify the CLI `--format` fields still decode and bump the
compatibility range if the floor moves — bump AeroControl's own version only for AeroControl
changes.

**Permissions (none).** AeroControl requires **no macOS TCC permissions of its own** — no
Accessibility, no Screen Recording, no Input Monitoring, no Automation. All window actions go
through the `aerospace` CLI → the AeroSpace **server**, which does the AX work under *its own*
grant; AeroControl calls **no** privileged AX API (verified 2026-07-14, crew + rubber-duck
audit). It only reads window *numbers* (`kCGWindowNumber`, no titles → no Screen Recording),
draws its own `.nonactivatingPanel` overlay, and toggles via SIGUSR1 (the summon keybind lives
in AeroSpace's config, so there is **no** global hotkey/event monitor). A former startup
`AXIsProcessTrusted` prompt was removed: it targeted the wrong app (AeroSpace owns that grant)
and gave false assurance. Do not re-add a permission request without an actual privileged API.

## CLI contract & parsing

- Requested field tokens live in `AerospaceCommand` (`listWindowsFields` etc.); decoder keys
  live in `AerospaceCliParser`. **Contract tests pin tokens ↔ keys** (drift guard) and pin
  the `_event` names ↔ parser cases. If you add/rename a CLI field or event, update both
  sides or the contract test will (correctly) fail.
- `AerospaceEvent.parse` returns `.other` for unknown/unusable events; the contract test
  uses `!= .other` as its "is this handled?" probe — keep that in mind before collapsing it.

## Concurrency: the CLI runner

`AerospaceProcessRunnerCli.run` uses **drain-both-pipes-to-EOF, then `reap` off the
cooperative pool** (so `terminationStatus` is valid), inside a task group that races a
timeout. Do **not** reintroduce a `terminationHandler`→continuation bridge or a
`OneShotResumer`-style single-resume guard — that was the fragile machinery this pattern
replaced. There are real-process tests (`AerospaceProcessRunnerCliTests`); the `timeout`
is an injectable init seam for fast tests.

## Workflow conventions

- Prefer the smallest targeted test that covers the change; run the full suite before
  declaring done.
- Test-first for anything touching the concurrency/runner code — it has no fake, only
  real-process tests.
- Keep the user's uncommitted WIP separate from agent commits (commit with explicit paths).
- Before committing, the metrics guard runs automatically (see the "code metrics must not
  rise" rule). If it blocks you, reduce code or ratchet the baseline deliberately — don't
  bypass it with `--no-verify`.
- Commit trailer: `Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>`.
