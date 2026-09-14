# Kick-off prompt: AeroControl 2 — one-shot overview with window thumbnails

Paste this as the first message of a new session in `~/sources/AeroControl`.

---

You are joining AeroControl (`~/sources/AeroControl`), a floating workspace overview for the
AeroSpace tiling window manager on macOS. Read `AGENTS.md` first and work **the crew way** it
describes: discuss non-trivial choices with an advocate and a skeptic, verify against the real
code and the AeroSpace source, review every change independently, one reviewable change at a
time. Then read `docs/plan.md` (open work) and `README.md`.

## Where we are

- The repo is at the 2026-08-03 state on `main`; later local work was lost in a macOS
  reinstall. Treat GitHub `main` as the only truth.
- The machine runs macOS 26 with Command Line Tools Swift 6.4 / macOS 27 SDK. `swift build -c
  release` currently **fails** in `Sources/AeroControlKit/UI/AeroControlWorkspaceCard.swift`
  ("cannot assign to property: 'self' is immutable", around line 41). Fixing the build is
  step zero; keep `swift test` green (102 tests).
- All AeroSpace traffic already goes over the unix socket (`AerospaceSocketRunner`,
  `subscribe` for events, `list-*`/`focus`/`move-node-to-workspace`/`close` for actions).
  AeroSpace 0.21.3 is installed. The wire protocol is documented in the AeroSpace guide,
  section "Socket protocol". Note the guide's caveat: there is **no window-closed event**;
  `docs/plan.md` §3 describes the chosen doorbell fix.
- The user's bar (SketchyBar, `~/.config/sketchybar`) already shows workspaces and the
  AeroSpace mode from the same socket. AeroControl must not duplicate that; it is the
  *on-demand* overview, the bar is the *always-on* strip.

## The product: a one-shot overview

Summon → see everything → do one thing → it's gone. No persistent panel, no switcher, no
trackpad gestures (AeroKit, https://github.com/jomatsu/aerokit, MIT, covers those and is a
useful reference for how it captures previews — read its capture code before designing ours).

1. **Summon/dismiss.** An AeroSpace binding launches the app; launching it again toggles it
   (the existing single-instance guard). Esc, clicking the backdrop, or completing an action
   dismisses it. Appears on the screen with the mouse (existing setting kept).
2. **Layout.** One card per workspace, in AeroSpace order, across all monitors as today.
   Inside a card: the workspace's windows as **live thumbnails** (not just icons) in on-screen
   order (`list-windows --sort-by dfs` when available, fallback as today), each with the app
   icon and a truncated title. Focused workspace and focused window are marked with the macOS
   accent color, matching the bar. Empty workspaces are shown (they are drop targets).
3. **Thumbnails.** Captured with ScreenCaptureKit **only at summon time**, one capture per
   window, including windows AeroSpace has parked off-screen (they still have content).
   Requires the Screen Recording permission; **degrade to app icons** when it is missing, and
   say so once in the menu-bar menu. No background refreshing, no caching across summons in
   v1. Apps can be excluded from capture via a small denylist in settings (password managers).
   This deliberately breaks AeroControl's old "no privacy permissions" line — call that out in
   README and the menu.
4. **Actions.**
   - Click thumbnail → `focus --window-id` → dismiss.
   - Click workspace badge → `workspace <name>` → dismiss.
   - Drag thumbnail onto another card → `move-node-to-workspace <ws> --window-id <id>`.
     The overview stays open and re-renders from the socket events; it does not guess.
   - **Merge:** drag a workspace *badge* onto another card → move every window of the source
     workspace to the target (`move-node-to-workspace` per window, in on-screen order so the
     tiling order survives), then focus the target. Ask for confirmation only when the source
     has more than N windows (crew decides N, default 3). No undo in v1; document it.
   - Hover thumbnail → close affordance → `close --window-id` (existing behavior).
5. **Non-goals for v1:** keyboard navigation inside the overview beyond Esc, window
   resizing, layout changes, persistent previews, a Cmd-Tab style switcher, swipe.

## Constraints (inherited, non-negotiable unless the crew explicitly re-decides)

- Socket only; no `aerospace` CLI spawning in steady state. No polling.
- KISS/YAGNI. Every new type, setting and permission must earn its place in the debate.
- `Sources/Common/` stays UI-framework-free.
- The code-metrics ceiling (`scripts/code_metrics.py --check`) will be exceeded by
  thumbnails + drag targets. Re-anchoring the baseline is allowed **once**, as a deliberate,
  reviewed commit that states the new size and why.
- Tests first where it bites: the merge sequencing, the capture fallback, the drop-target
  mapping from screen point to workspace.

## Order of work

0. Fix the build on Swift 6.4; run the test suite; commit.
1. Crew design round on thumbnails: capture API, sizing, permission fallback, denylist.
   Output: a short design note in `docs/` and the decision on N for merge confirmation.
2. Thumbnails in the cards (replace icon tiles), with icon fallback.
3. Drag window → workspace (already partially there: `WindowDragData`), verified against
   AeroSpace's real behavior for `--focus-follows-window` off.
4. Merge workspace → workspace.
5. README, menu wording for the permission, release via `make release`.

Report after each step with what was verified and how, not what should work.
