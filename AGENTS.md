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
  it only as a deliberate, explained exception — in the commit that earns it (a feature and
  its cost are one reviewable change), with the cost stated in the message.

### Rule: `docs/flow.html` is written by running the rules — `make flow`
- `make arch` draws the architecture from the code into `docs/arch.html` (`scripts/arch.py`): the
  layers and what names what, every type as a box with its lines, complexity, stored state and
  public members, the call flow in the host and the stores, and a table of where to look (the
  biggest types, the widest fan-out, arrows pointing up a layer, pairs naming each other, functions
  at complexity ≥ 8), and Robert C. Martin's coupling per layer (Ca, Ce, I, A, D, arrows up, cycles), drawn as
  rings — AeroSpace's model (all of Common) at the heart, darker the more stable, a red spoke per arrow up — which `make arch`
  prints as one line. Regenerate it with a review; `make arch-check` says when it is stale.

- `Tools/flowdoc/main.swift` runs the pure functions in `Common` (`Summon`, `AppSummon.decide`,
  `Summon.again`, `FilterKey`, `filterKeyAction`, `updateOverview`, `AerospaceEvent.parse`,
  `AppStripModel.action`/`start`/`summary`, the `Strip` transitions) against a fixture and
  writes what they answered as tables and decision trees. Nothing in a table is written by
  hand; the prose says only what cannot be run there (the host's order of operations) and
  where to look for it.
- `make flow` regenerates; `make flow-check` (CI) fails when the committed page is stale. A
  rule that moves into `Common` becomes part of the page; one that stays in the store or the
  host does not — that is a reason to move it.

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
  reducer, interprets effects, and holds the marking (`marking`, one `Strip` for the map and
  the strip, `filter`, `filterMatches`, `ringWindowId`); `PictureStore`, owned by it, keeps
  the windows' pictures and sizes and talks to the bridge for them; SwiftUI views
  `AeroControlPanel → WorkspaceCard → AppTile` draw from pure layouts (`mapLayout`,
  `stripLayout`) and hand the store the cards as drawn (`drawn`) for the keys.
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
- `PictureStore.generation`: a capture that finishes after `clear()` is discarded.
- `AerospaceSocketRunner`: protocol-version handshake, `SocketHandle` fd
  ownership; blocking syscalls on a private queue, never the cooperative pool.
- `TolerantInt`: `NULL-MONITOR*` string sentinels are valid runtime values for monitor ids.
- `FilterKey(event:)` rules out Cmd/Ctrl/Option; `performKeyEquivalent` intersects only the
  meaningful modifier flags (the raw set carries `.numericPad`, `.function` and the like).
- `recentWindows` / `noteFocus`: the order windows last had the focus, kept from AeroSpace's
  events for as long as the app runs. AeroSpace keeps no such order to ask for, so this is
  remembered on purpose — the one thing besides the strip's marking that is.

### Rule: read, don't infer — and remember nothing that can drift

Workspace and window data are **immutable values from one read** of AeroSpace (`WorkspaceInfo`,
`WindowInfo` are all `let`). The overview draws what AeroSpace said — its layout rects — or packs
tiles; it does not reconstruct a layout from sizes, and it keeps no remembered state between loads
that could drift from AeroSpace's answer (no learned capability, no remembered config value).
The load-bearing list above is the whole exception. An engine that inferred layouts from sizes
was built and removed in October 2026; see docs/aerospace-layout-data.md, "Review and cut".

### Trust boundary

AeroSpace is trusted at the **parsing boundary**: the fields AeroControl explicitly requests
(`AerospaceCommand.listWindowsFields` etc.) are decoded strictly, and the **initial
`loadOverview`** fails loudly with a visible `Load error:` banner. Steady-state reloads use
`try?`, unknown events parse to `.other`, and there is **no runtime version check** — the
minimum (**AeroSpace ≥ 0.21.0-Beta**, where `subscribe` and the public socket protocol
arrived) is documentation. `Tests/Common/AerospaceContractTests`
pins argv and event names; if you add or rename a field or event, update both sides.

### Permissions

Only **Screen Recording**, and only for window previews (`CGRequestScreenCaptureAccess` in
`NativeApiBridgeAdapter`; the menu offers it). Without it the tiles are plates with their app's icon and the window's title. No
Accessibility, Input Monitoring or Automation: window actions go through AeroSpace, the summon
keybind lives in AeroSpace's config, and the overlay is a `.nonactivatingPanel`. macOS ties the
grant to the **signing identity** — `script/sign-identity.sh` creates the stable one that
`make install` picks up and `script/release.sh` requires.

### Versioning

AeroControl versions independently of AeroSpace (currently **v0.3.1-Beta**;
`Packaging/Info.plist` holds `CFBundleShortVersionString` and the `v`-prefixed
`ACReleaseVersion`; `script/release.sh` stamps both). The compatibility range is shown as a
separate menu line. Bump AeroControl's version for AeroControl changes only.

Release strategy: AeroControl runs its own release cycle, fine-grained, in AeroSpace's form.

- **The form** is `0.MINOR.PATCH-Beta`, published as a GitHub pre-release (`release.sh` marks
  any suffixed version so), e.g. `v0.3.1-Beta`.
- **Every release is a patch**, however small or large: `0.3.1`, `0.3.2`, … as often as there is
  something to ship. The patch is a plain counter with no ceiling (`0.3.10` follows `0.3.9`;
  Homebrew, macOS and `git tag --sort=v:refname` compare it as a number).
- **The minor moves rarely**, for something users must notice: requiring a new AeroSpace minor,
  or a shift as large as `%{window-layout-rect}` reaching every user. It resets the patch.
- **Compatibility with AeroSpace is said in words**, not in the number: the menu line
  "Compatible with AeroSpace ≥ 0.21.0" (and the release title or notes). An AeroControl number
  that mirrored AeroSpace's would read as "made for that AeroSpace" and look like its patch.
- **Released versions are never renumbered or undercut**: versions up to v0.3.0 had no suffix
  and stay so; a lower version than one released would stop Homebrew upgrading.

### Workarounds for AeroSpace bugs

Each is marked `WORKAROUND` in the code with the AeroSpace issue it works around; remove it
when AeroSpace fixes the issue.

- **AeroSpace issue 101** (https://github.com/nikitabobko/AeroSpace/issues/101):
  `focus --window-id` on a window of an app with windows on more than one monitor often lands
  on the app's other window, because macOS hands the keyboard to the app's last key window as
  the activation completes. `OverviewStore.focusAgainIfMissed` asks once more if AeroSpace's
  focus is elsewhere 300 ms later. Measured with Ghostty across two screens: 3 of 5 right
  without it, 5 of 5 with it.

## Workflow conventions

- Smallest targeted test for the change; full `make test` before declaring done.
- No production code exists only for tests: no field, accessor or teardown that only a test reads or calls. A test derives what it needs from what production uses.
- Never read the user's dotfiles or execute config; AeroControl is public and Homebrew-distributed.
- Never send synthetic keystrokes to verify the overlay unless it is confirmed on screen
  (`lsof -p $(pgrep -x AeroControl) | grep -c unix` ≥ 2) — they land in whatever is focused.
- Never push; the user pushes.
- Commit trailer: `Co-Authored-By:` naming the model that wrote the change.
