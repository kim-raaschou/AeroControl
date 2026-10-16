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
- Targeted tests: `swift test --filter <Suite> -Xswiftc -plugin-path -Xswiftc <TESTING_PLUGINS>` once
  `SDKROOT` is set as the Makefile does; both come from the Makefile, and without the plugin path the
  Testing macros fail to resolve.
- Line endings are **LF**, enforced by `.gitattributes`.
- After `make install`, confirm the process is newer than the binary before testing
  (`ps -o lstart= -p $(pgrep -x AeroControl)` vs. `stat -f %Sm /Applications/AeroControl.app/Contents/MacOS/AeroControl`).

### Rule: code metrics stay within baseline +1% — verified at every commit

- Tracked Swift **code lines and approximate complexity may not rise more than 1% above**
  `scripts/metrics-baseline.json`. Tests count towards the line total. Ceiling per metric is
  `floor(baseline × 1.01)`.
- `.githooks/pre-commit` runs `python3 scripts/code_metrics.py --check` and fails the commit
  when a ceiling is exceeded. Enable once per clone: `git config core.hooksPath .githooks`.
- When you **reduce** code, ratchet down: `python3 scripts/code_metrics.py --update-baseline`,
  which writes `scripts/metrics-baseline.json` and a point in `scripts/metrics-history.json`;
  then `make arch`, and commit the three. The script draws no page: its numbers are on
  `docs/arch.html`.
- Default answer to "the metric went up" is **make it smaller**, not raise the baseline. Raise
  it only as a deliberate, explained exception — in the commit that earns it (a feature and
  its cost are one reviewable change), with the cost stated in the message.

### Rule: `docs/arch.html` is drawn from the code — `make arch`
- `make arch` draws the architecture and the metrics from the code into `docs/arch.html`
  (`scripts/arch.py`, reading the gate's numbers from `scripts/code_metrics.py`): the layers as rings
  read from the arrows, with Robert C. Martin's coupling per layer; the rules the build holds itself
  to, each ✓ or ✗; health (tests, duplication, the longest and deepest production function); the
  hotspots, the ten most complex types against six measures, and the fifteen most complex functions;
  code lines and complexity over time; every type as a box in its layer and area, and what names
  what; and every file. Regenerate it with a review; `make arch-check` says when it is stale.
- The code carries no comments: what a thing is, the page and the Architecture section below say;
  why, the commit that did it, and the tests' titles, which say it as a sentence the code holds true.
  The one exception is a `WORKAROUND` block, which names the issue it waits on; `make arch-check`
  fails on any other comment.

### Rule: `Sources/Common/` stays UI-framework-free — enforced

Files under `Sources/Common/` **must not import AppKit, SwiftUI, Cocoa or UIKit**; `--check`
fails on any violation.

## Gates

- **`.githooks/pre-commit`** — the metrics guard, every commit.
- **`.githooks/pre-push`** — `make test` before every push.
- **`.github/workflows/ci.yml`** — a `macos-26` runner (Xcode 26.2) builds, tests and runs the
  same metrics guard on push/PR to `main`. Green CI is what proves `main` holds.

## Architecture

- `Sources/Common/` — **the functional core: AeroSpace's world, pure**. One layer, in four areas, each a step
  down: `Keys/` (keys, links and the strip's moves) over `Layout/` (geometry) over `AeroSpace/` (the model and
  the reading of AeroSpace), with `Visit` and `OverviewScene` at the root; `make arch-check` fails if
  two areas name each other. `Visit` is one visit of the overview as a value: every key, link, read and event
  goes in through a transition that returns the new value and its effects (`Visit.Effect`: commands to run,
  a read, and `Visit.Host` for the host). `OverviewScene` is what is drawn, derived from a `Visit`. Then
  `OverviewModel` with its queries and type-to-filter matching, the layout, the keys (`FilterKey.swift`), and the reading of AeroSpace — command argv and response decoding
  (`AerospaceCliParser.swift`, `AerospaceCommands.swift`), the `AerospaceProcessRunner` port. The app
  is an AeroSpace client; its model is the core, not an adapter. Everything outside is the shell.
- `Sources/AeroControl/` — **the app: one module around the core**, in four folders. `Adapters/`:
  `AerospaceSocketRunner` speaks the socket protocol; `NativeApiBridgeAdapter` measures and captures
  windows. `State/`: `AerospaceSync` is everything that talks to AeroSpace — the read, the event
  stream and its reconnect, the commands in order, the refresh that reads twice and is cancelled by
  the next, the issue-101 WORKAROUND; `OverviewStore` (`@MainActor @Observable`) holds the `Visit`,
  runs its commands, reads and captures, hands `Visit.Host` effects to the host, and derives the
  `OverviewScene` from the visit and the screen the host gives it; `PictureStore`, owned by it, keeps
  the windows' pictures and frames. `UI/`: SwiftUI views `AeroControlPanel → WorkspaceCard → AppTile`
  draw the scene and nothing else of the store's state. `Host/`: `OverlayWindowManager` carries out
  `Visit.Host` (show, hide, activate, quit, launch, rebuild), `OverviewWindow` is the non-activating
  panel and its key handling, `MenuBarController` the menu, `KeyHint` the mode's keys
  in a panel of their own, a picker through `HintPick` (`Keys/`) only when summoned by
  `aerocontrol://config`. Tests `@testable import` the app module itself.
- Decisions go in `Visit`, not in the store or the host. The store's size is the I/O it owns.

### The one-shot model

Summon → `reload()` reads AeroSpace's whole state → previews are captured → the overlay
appears. One subscription to AeroSpace's event stream (`subscribe`, `--no-send-initial`) lives as
long as the app. Hidden, it only keeps the order of focus, which decides where a strip opens.
**While visible** every event means "read again" (`.changed` → `.refresh`), and a focus change
moves the focus at once. **On hide** the query is cleared; the previews are kept, and the next
visit shows each one whose window still has its shape until its new picture lands. The windows
themselves always come from commands, never from an event.

### Rule: true to AeroSpace, live

The map and the strip show what AeroSpace shows, while it changes: its layouts, its windows,
its focused workspace. The strip shows only the app's windows, as AeroSpace places them when they
make one block and packed otherwise: it is a picker, the map shows the rest. A change is read again even when AeroSpace announces nothing (a layout
key: `readAgainAfter`). A key that moves the ring or the strip's marking takes AeroSpace's focus
along, so AeroSpace's own keys act on the window under it, and Escape takes the focus back to
where the visit began; pointing and typing move only the ring. A feature that would show anything AeroSpace does not, or
keep AeroSpace somewhere else than the overview shows, needs the user's decision first.
Tests hold it from the outside: `TestApp.mirrors` checks the cards against the fake AeroSpace
(their windows in the order AeroSpace lists them, by app name then title, as `list-windows` sorts; in the strip the app's; layouts and focused workspace), `mapIsAeroSpaceLive` and `stripIsAeroSpaceLive`
change AeroSpace by bound keys while the overview is up and check the mirror after each, and
`ringTakesAeroSpaceAlong` keeps AeroSpace with the ring. A scenario that changes AeroSpace ends
on the mirror.

### Load-bearing defensive code (do not delete as "paranoia")

- `AerospaceSync.refresh` cancel-and-reload: every event or completed action re-derives truth
  from AeroSpace; a newer refresh or the visit's end cancels the old one, and every step after
  an await checks `Task.isCancelled`, so a stale result is dropped. There is
  **no optimistic local state**.
- The second read, `readAgainAfter` later: AeroSpace announces a bound key (`binding-triggered`)
  before its command runs, and a new layout announces nothing, so the first read can miss it.
- Reload after reconnect in the subscribe loop, and the binding mode asked (`list-modes --current`)
  at every connection: `--no-send-initial` means a dropped stream loses whatever happened meanwhile,
  the mode included.
- `PictureStore.generation`: a capture that finishes after `clear()` is discarded.
- `AerospaceSocketRunner`: protocol-version handshake; blocking syscalls on a private queue,
  and the subscription on a thread of its own, never the cooperative pool.
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
`loadOverview`** fails loudly: the lane says `Load error` and why, and Escape closes. A failed
steady-state reload says the same until the next read lands, unknown events parse to `.other`, and there is **no runtime version check** — the
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
