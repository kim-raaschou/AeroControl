# AGENTS.md — working notes for AI agents on AeroControl

AeroControl is a **one-shot, Mission-Control-style overview for
[AeroSpace](https://github.com/nikitabobko/AeroSpace)**, a macOS tiling WM. AeroSpace does
all the real window management; AeroControl draws the workspaces once per summon and
forwards one action (focus / move / merge / close) over AeroSpace's Unix socket.

## How we work: the crew (governing principle)

**We operate as a crew, not a single author. Every task — design, code, refactor, docs,
cleanup — is verified, discussed and reviewed by the crew before it is considered done.**

- **Discuss before deciding.** For any non-trivial choice, convene specialised sub-agents
  (an advocate and a sceptic, plus domain reviewers), let them cross-examine, surface the
  disagreements, and take the call under KISS / YAGNI.
- **Review every change** with a pass independent of the author, aimed at real bugs, logic
  and design flaws — not style.
- **Verify, don't assume.** Check claims against the code, the tests, and the real AeroSpace
  source when relevant. Verify UI changes **on screen** before committing: a change installed
  unseen has broken the app before.
- **One reviewable change at a time.** Small commits; refactors and features in separate
  commits.

## Build, test, install

Plain `swift build` does not work on a Command Line Tools-only machine (CLT 27 ships a
macOS 27 SDK whose SwiftUI macros need Xcode). The Makefile fixes that; always use it:

- `make build` · `make test` · `make install` (builds, signs, installs to `/Applications`,
  kills and relaunches the agent).
- Targeted tests: `swift test --filter <Suite>` works once `SDKROOT` is set as the Makefile does.
- Line endings are **LF**, enforced by `.gitattributes`.
- After `make install`, confirm the process is newer than the binary before testing
  (`ps -o lstart= -p $(pgrep -x AeroControl)` vs. `stat -f %Sm /Applications/AeroControl.app/Contents/MacOS/AeroControl`).

### Rule: code metrics stay within baseline +1% — verified at every commit

- Tracked Swift **code lines and approximate complexity may not rise more than 1% above**
  `scripts/metrics-baseline.json`. Tests count towards the line total. Ceiling per metric is
  `floor(baseline × 1.01)`.
- `.githooks/pre-commit` runs `python3 scripts/code_metrics.py --check` and fails the commit
  when a ceiling is exceeded. Enable once per clone: `git config core.hooksPath .githooks`.
- When you **reduce** code, ratchet down: `python3 scripts/code_metrics.py --update-baseline`
  and commit `scripts/metrics-baseline.json` (with `scripts/metrics-history.json` and
  `docs/code-metrics.html`, which the script regenerates).
- Default answer to "the metric went up" is **make it smaller**, not raise the baseline. Raise
  it only as a deliberate, explained exception in its own commit.

### Rule: `Sources/Common/` stays UI-framework-free — enforced

Files under `Sources/Common/` **must not import AppKit, SwiftUI, Cocoa or UIKit**; `--check`
fails on any violation.

## Gates

- **`.githooks/pre-commit`** — the metrics guard, every commit.
- **`.githooks/pre-push`** — `make test` before every push.
- **`.github/workflows/ci.yml`** — a `macos-26` runner (Xcode 26.2) builds, tests and runs the
  same metrics guard on push/PR to `main`. Green CI is what proves `main` holds.

## Architecture

- `Sources/Common/` — **pure domain**. `OverviewModel`, the reducer
  `updateOverview(_:_:) -> (model, [effect])` (`OverviewUpdate.swift`), type-to-filter
  (`OverviewFilter.swift`: matching, `FilterKey`, `filterKeyAction`), AeroSpace command argv and
  response decoding (`Aerospace/`), the `AerospaceProcessRunner` port.
- `Sources/AeroControlKit/` — **adapters, state, UI**. `AerospaceSocketRunner` speaks the
  socket protocol; `OverviewStore` (`@MainActor @Observable`) owns the model, runs the
  reducer, interprets effects, and holds the UI-only filter state (`filter`, `selection`,
  `filterMatches`, `ringWindowId`); SwiftUI views `AeroControlPanel → WorkspaceCard → AppTile`.
- `Sources/AeroControlEntry/` — the executable: `OverlayWindowManager` (summon / hide),
  `OverviewWindow` (the non-activating panel and its key handling), `MenuBarController`.
- Do **not** merge the reducer into the store. The store's size is the effects it owns.

### The one-shot model

Summon → `reload()` reads AeroSpace's whole state → previews are captured → the overlay
appears. **While visible** the store follows AeroSpace's event stream (`subscribe`,
`--no-send-initial`); every event means "read again" (`.changed` → `.refresh`). **On hide** the
subscription stops, previews are dropped, the filter is cleared. Nothing keeps the model in
sync while hidden — nothing reads it. Events carry **no data**; all state comes from commands.

### Load-bearing defensive code (do not delete as "paranoia")

- `requestRefresh` cancel-and-reload with `refreshGeneration`: every event or completed
  action re-derives truth from AeroSpace; the generation counter drops stale results. There is
  **no optimistic local state**.
- Reload after reconnect in the subscribe loop: `--no-send-initial` means a dropped stream
  loses whatever happened meanwhile.
- `captureGeneration`: a preview capture that finishes after `clearPreviews()` is discarded.
- `AerospaceSocketRunner`: protocol-version handshake, per-command timeout, `SocketHandle` fd
  ownership; blocking syscalls on a private queue, never the cooperative pool.
- `TolerantInt`: `NULL-MONITOR*` string sentinels are valid runtime values for monitor ids.
- `FilterKey(event:)` rules out Cmd/Ctrl/Option; `performKeyEquivalent` intersects only the
  meaningful modifier flags (the raw set carries `.numericPad`, `.function` and the like).

### Trust boundary

AeroSpace is trusted at the **parsing boundary**: the fields AeroControl explicitly requests
(`AerospaceCommand.listWindowsFields` etc.) are decoded strictly, and the **initial
`loadOverview`** fails loudly with a visible `Load error:` banner. Steady-state reloads use
`try?`, unknown events parse to `.other`, and there is **no runtime version check** — the
minimum (**AeroSpace ≥ 0.21.1**) is documentation. `Tests/Common/AerospaceContractTests`
pins argv and event names; if you add or rename a field or event, update both sides.

### Permissions

Only **Screen Recording**, and only for window previews (`CGRequestScreenCaptureAccess` in
`NativeApiBridgeAdapter`; the menu offers it). Without it the overview draws app icons. No
Accessibility, Input Monitoring or Automation: window actions go through AeroSpace, the summon
keybind lives in AeroSpace's config, and the overlay is a `.nonactivatingPanel`. macOS ties the
grant to the **signing identity** — see README "Build from source" and `script/release.sh`.

### Versioning

AeroControl versions independently of AeroSpace (currently **v0.1.1**;
`Packaging/Info.plist` holds `CFBundleShortVersionString` and the `v`-prefixed
`ACReleaseVersion`; `script/release.sh` stamps both). The compatibility range is shown as a
separate menu line. Bump AeroControl's version for AeroControl changes only.

## Workflow conventions

- Smallest targeted test for the change; full `make test` before declaring done.
- Never read the user's dotfiles or execute config; AeroControl is public and Homebrew-distributed.
- Never send synthetic keystrokes to verify the overlay unless it is confirmed on screen
  (`lsof -p $(pgrep -x AeroControl) | grep -c unix` ≥ 2) — they land in whatever is focused.
- Never push; the user pushes.
- Commit trailer: `Co-Authored-By:` naming the model that wrote the change.
