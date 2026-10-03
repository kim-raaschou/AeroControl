# What AeroSpace exposes about layout, and what an overview can do with it

Status: investigation notes, written from four crews of models (Fable, Opus, Sonnet, Haiku)
that read the AeroSpace source and docs, from measurements on the owner's machine, and from
an implementation that was built and then thrown away. AeroSpace 0.21.3-Beta, the checkout at
`~/sources/aerospace` (main at 5f08f9c0). File and line references are the reviewers', from that
checkout; they will drift.

## The question

Can each workspace card show the workspace's windows where AeroSpace puts them, the way
krn.overview does on Hyprland, where every window's frame is available on every workspace?

Short answer: for the **visible** workspace, yes, exactly. For a **hidden** workspace nothing that
AeroSpace exposes today gives the placement, and every workaround is either a guess or a side
effect the user would feel.

## What is measured

- **Visible workspace.** `CGWindowListCopyWindowInfo` gives exact frames (bounds need no Screen
  Recording). Ids equal AeroSpace's window ids. `.optionAll` is needed: `.optionOnScreenOnly` drops
  hidden apps' windows. About 3 to 6 ms for a few hundred windows.
- **Hidden workspace.** AeroSpace never lays it out. Each window is parked at the bottom-right
  corner by a position-only Accessibility call (`hideInCorner`, `setAxFrame(p, nil)`;
  refresh.swift:190-201, MacWindow.swift:123-155), so a parked window **keeps its last applied
  size** and loses its position. Accessibility, CGWindowList and the private `SLSGetWindowBounds`
  all report the same parked frame. There is no "logical" frame outside AeroSpace's process.
- **The kept size can be stale.** A window moved to a hidden workspace is bound to the tree with
  `WEIGHT_AUTO` and has no computed layout until the workspace is first shown. Measured example:
  workspace 4 held Code 559 wide and Messages 660 wide; 559 + 660 + gap is 1231, not the 1696 area,
  because a third window had been moved away while it was hidden.
- **`aerospace list-windows` order.** Sorted by app name, then by title only if `%{window-title}` is
  in the format. Ties otherwise keep tree (depth-first) order, because the sort is stable
  (ListWindowsCommand.swift:52; verified against the source, not across versions). So the left to
  right order of windows of different apps in one container is not in the data.

## The complete inventory of what is readable about layout

21 format variables in all (ListWindowsCmdArgs.swift:179-214); the installed server's own parse error
lists exactly these. The layout ones:

| Variable | What it says |
|---|---|
| `%{window-layout}` | alias of `window-parent-container-layout` |
| `%{window-parent-container-layout}` | the window's **direct** parent only: `h_tiles`, `v_tiles`, `h_accordion`, `v_accordion`, `floating`, `macos_native_*` |
| `%{workspace-root-container-layout}` | the root container only, one string per workspace |

Nothing exposes container ids, sibling order, depth, weights, the most recently used child of an
accordion, or any rectangle. `config --get` exposes only mode bindings: gaps and `accordion-padding`
are **not readable** (`config --get gaps` fails). The socket runs CLI argv only (server.swift:71-90);
events carry ids and names only (ServerEvent.swift). `debug-windows` dumps Accessibility attributes,
not the tree. The only tree printer is test code (MoveCommandTest.swift:326-360). Every `list-*` call
runs `layoutWorkspaces()` and schedules a refresh, so none is passive (harmless, not free).

The private fields that hold the truth exist: `TreeNode.lastAppliedLayoutPhysicalRect` and
`lastAppliedLayoutVirtualRect` (TreeNode.swift:14,20; set in layoutRecursive.swift:40) and the
weights (`adaptiveWeight`, private). Only mouse code reads them.

## The one path that lays out every workspace: `enable off`

While AeroSpace is disabled, the refresh un-hides and lays out **all** workspaces (refresh.swift:157-162).
We built a probe (cover the screen with a still screenshot, `aerospace enable off --fail-if-noop`, poll
CGWindowList until the frames settle, `enable on`, with a 12 s dead-man's switch) and ran it once on a
single monitor with 11 windows:

- `enable off` returned in 0.06 s, frames settled after about 0.31 s; `enable on` returned in 0.13 s,
  settled after about 0.31 s. About 0.7 s in all.
- Every workspace's windows were at their real positions; after `enable on` all 11 windows were back at
  exactly their previous frames; focused workspace and window unchanged. The owner saw nothing.

Four reviewers judged it **not sustainable as a default for a published app**, only as an opt-in
experimental switch with hard safeguards:

1. AeroSpace is dark for about 0.7 s: the server rejects every command (server.swift:72-77) and hotkeys
   are unregistered, so a chord typed then lands in the focused app.
2. A crash or force-quit while disabled strands the window manager off and the windows piled on screen.
   Needs a flag file, a watchdog child that re-enables on any death of the parent, and a launch-time check.
3. `on-mode-changed` fires twice; sketchybar, JankyBorders and similar react; `enable on` returns the user
   to the main mode.
4. Windows move and resize twice (SIGWINCH for terminals, Electron relayout, video calls); stale-size
   windows are resized for good; floating windows drift (MacWindow.swift:131, issues #642 and #1519).
5. A cover must be an opaque still image on every display, with mouse and keyboard swallowed. The overview's
   translucent, blurred backdrop would show the windows jumping.
6. It relies on a side effect of a convenience feature, not an API (issue #705 asks for
   `enable off --keep-windows-hidden`; a future default change would silently break the scan).

Visiting workspaces with `workspace N` was rejected too: focus history is overwritten, bars and borders react
on every hop, apps are activated (messages can be marked read), and frames land asynchronously.

## What was built and thrown away

Two pure engines plus their wiring were built with tests (190 tests green at the peak) and then discarded on
the owner's decision, because the result was heuristic:

- `FrameCache`: real frames recorded while a workspace is visible, reused for a hidden one only while window
  ids, order, a layout signature and the parked sizes still matched.
- `AeroLayout`: infers the container tree from the parent layouts and parked sizes and replays AeroSpace's
  own `layoutTiles` arithmetic (weights plus a share of the gaps, equal delta, oversized windows share what
  the others leave). On the owner's measured workspace it reproduced the real slots to about a point, and it
  said what it doubted (`sumsFail`, `ambiguous`, `orderApproximate`, `orderRemembered`, `clamped`).

What no such approach can know: the order of windows of different apps in one container (the owner's real
workspace had Spotify left of IntelliJ; the alphabetical guess had them the other way), which accordion child
is in front, stale sizes, and the gaps. Remembering the order from the last time a workspace was visible
narrows it but cannot prove it: a swap after the last summon leaves no trace.

The code is kept outside the repository, in the session scratchpad; nothing of it is committed.

## What the source reviewers proposed

Three reviewers converged on a small change to AeroSpace itself, exposing what it already holds:

- A **workspace tree** variable (Fable): a recursive JSON string of the root container with layout, ordered
  children, window ids, normalised weights, the accordion's most recently used index, and the gaps and padding
  resolved for the workspace's monitor. About 45 lines in format.swift plus docs and a `FormatTest`.
  AeroControl would replay `layoutTiles`/`layoutAccordion` (pure arithmetic, layoutRecursive.swift:107-175) on
  the true tree, which gives the layout AeroSpace **will** apply, not a guess from stale sizes.
- A **per-window tree path** (Opus): layout, index, pixel weight and a most-recently-used mark per level.
  About 40 lines.
- **Rect variables** from `lastAppliedLayoutPhysicalRect` (Sonnet): about 25 lines, but stale for a workspace
  edited while hidden and nil before the first layout, and no tree.

Route: CONTRIBUTING.md asks for a Discussion under "feature ideas". Outside pull requests are labelled
"not-actionable" automatically (`.github/workflows/label-incoming-prs.yml`). Precedent exists for outsiders'
format-variable commits (4e43d0b3, 33 lines in 4 files, shipped in v0.20.0; 930222a5, 6 lines). Release
timing is **disputed** between the reviewers (one said every 1 to 8 weeks, another 4 to 7 months); unverified.
AeroControl can feature-detect a new variable, because an unknown variable makes the whole call fail with a
parse error.

## Prior art found in AeroSpace Discussions

- **`mthines/AeroSpace`, branch `feat/workspace-overview`** (discussion 2087, May 2026, no maintainer reply).
  A Mission-Control-style grid command inside AeroSpace. It adds `layoutWorkspace(dryRun: true)`, which
  computes fresh `lastAppliedLayoutPhysicalRect` values and normalises weights **without moving windows**
  (conditional checks around the frame-setting calls, roughly five places). That is exactly the dry run the
  reviewers thought did not exist; it is a small precedent for the upstream change. The overview itself moves
  the real windows into the grid and changes focus, so it is not a companion-app design.
  Sources read as summaries, not line by line.
- **AeroKit, `jomatsu/aerokit`** (discussion 2187, MIT). A companion app like AeroControl: a Cmd-Tab style
  workspace switcher, Exposé and App Exposé, trackpad swipe. Talks to AeroSpace over the server socket. Keeps
  **per-window JPEG snapshots** and a manifest of titles per workspace, taken without switching workspaces
  (`CGWindowListCreateImage`, about 9 ms per window, falling back to ScreenCaptureKit at about 105 ms), refreshed
  by a scheduler with settle intervals, a minimum interval and back-off after failure; snapshot exclusions;
  user-defined workspace order. It reads the same three layout variables and does not use them. It does not draw
  windows where they lie either.
- Discussions 2059 (a workspace-overview HUD command), 2047 (a switcher with search and preview), 1154
  (side-by-side spaces in Mission Control).

## Tree order: where AeroSpace loses it, and what AeroControl does (2026-09-30)

*Superseded the same evening: the `--sort-by dfs` probe, `TreeOrder` and the ordered parser described here were
removed when `%{window-layout-rect}` made the order moot. Kept for the reasoning; see "AeroSpace gives the rects".*

`ListWindowsCommand.swift` collects the windows with `workspaces.flatMap(\.allLeafWindowsRecursive)`, a
depth-first walk of the tree in child order: left to right and top to bottom. Nine lines later
`_list.sortedBy([app name, title])` throws that order away. The line dates from April 2025. Nothing in the
maintainer's branches touches it; the only related WIP is "Decouple layout calculation from 'drawing'"
(bobko/backlog, 2025-04-18, dormant).

Upstream state: issue 491 (2024-09, nikitabobko asked for `list-windows --sort dfs`, later `--sort-by`), PR 2207
(the owner's, 2026-08, implements exactly that), PR 1958 (`get-tree`, glassbe, 2026-02), PR 1932 (`--sort`, waj,
2026-02). 78 PRs open; four external PRs merged in 2026, none since April; 47 new in the last three months. Not a
rejection, a queue.

What AeroControl does: it asks for tree order when AeroSpace can give it and never otherwise.

- `AerospaceCommand.listWindows(treeOrder: true)` is the plain read plus `--sort-by dfs`.
- `loadOverview(using:treeOrder:)` learns the capability from AeroSpace itself (`TreeOrder`: unknown, present,
  absent). While unknown, the sorted read is tried; only when it fails *and* the plain read then succeeds in the
  same load is the flag marked absent, so an AeroSpace that is down teaches nothing. Once present, the sorted read
  is the read. Once absent, the plain read, and no further asking for the life of the process.
- `OverviewStore.treeOrder` keeps what was learned. Every release so far answers "Unknown flag '--sort-by'" and
  costs one failed call on the first load, about 2 ms; the owner's fork build answers in tree order.
- No version parsing, no inference, no reading of the user's config.

With tree order in hand, the parked sizes give both the structure and the order of a hidden workspace; only the
weight of a window opened while the workspace was hidden is unknown until it is visited.

## The tree, drawn (2026-09-30, later the same day)

*The ordered reading below was removed later that evening; only the forced, unordered reading remains, as the
fallback for an AeroSpace without `%{window-layout-rect}`.*

`WorkspaceTree` (Common/Domain) rebuilds a tiles workspace from the windows' sizes and the root's axis. In a tiles
container every child spans the container across its axis and the children's sizes along it add up to the
container's, so the sizes decide the tree. Ordered (dfs from the fork): children are consecutive runs, read with
backtracking, nesting to any depth; more than one tree that fits means no tree. Unordered (every release): only a
forced reading, windows that span the area plus one column per distinct width, children in the order first
listed. Accordions, single windows, filtered cards and anything the sizes do not decide fall back to packed tiles.
Never a guessed tree. `AeroControlLayout.treeLayout` fits the result into the card in the screen's own shape;
the layout symbol fades when the shape is drawn but AeroSpace did not say the order.

Checked against the owner's workspace 7 that afternoon, read from the window server while it was visible: a
column of four terminals (842 × 257/251/251/257) at the left, one 842 × 1052 terminal at the right. The sizes
alone reproduce it (`WorkspaceTreeTests.ownersWorkspace7`), and the installed card draws it that way on the
release AeroSpace, where the listing order happened to be the real one.

Review (Opus, read-only, same day) found one real fault and the fix changed what the engine claims. A child slab's
width was taken as its widest window, but a column made of rows alone is wider than any window in it, so a 2 × 2
grid beside a tall window was read as two columns and called certain. Now a slab's candidate widths are each
window's own and each sum of same-height neighbours, every candidate is parsed, and distinct trees are counted.
That makes the honest answer visible: a 2 × 2 grid of equal cells beside a tall window is *ambiguous* from sizes
alone (two columns of two, or two rows of two, both add up), and the engine returns no tree for it. Columns whose
rows differ in height, and a column of a row plus a window, stay unique. The same review pruned the search (a
spanning window is a child of the container and of nothing inside it; a running sum over the container stops the
branch), which removes the pathological case of an accordion nested in tiles, where every window has the same
size and nothing adds up. And the flag is learned absent only when AeroSpace's error names `sort-by`; a dropped
socket throws as before and the next load asks again.

Drawing at true scale (same day, on the owner's note that the column's heights did not add up). The first
drawing shared the card's screen-shaped box among the children by weight, so the column, which really spans
1052 of the 1084-point screen, was stretched to all of it, and each picture, keeping its own shape, showed a band.
Now every window is drawn at its own size, the tiled area is scaled as a whole into the box and centred, and the
gap AeroSpace keeps between windows is read off the tree: a nested container runs its parent's full width, its
children's sizes add up to less, and the difference shared by the gaps between them is the gap. Workspace 7 gives
(1052 − 1016) / 3 = 12, the owner's `inner.vertical`. The gap is one setting for the whole AeroSpace, so it is read
once per overview (`AeroControlLayout.innerGap`, the median over every workspace with a nested container) and
every card uses it, a flat tree too: two windows side by side get the gap that workspace 7 showed. Only when no
workspace shows it do the windows sit edge to edge. The outer gaps are never computed: the tiled area is drawn at
the screen's own scale, centred in the screen-shaped box, so the margin around it is the outer gap. (A lone tiled window
is still packed as a tile, edge to edge in its card; `treeLayout` wants at least two windows.) A fullscreen ghost is still the whole screen box, outer gaps included, as on the screen. Nothing of
this reads the user's config.

Floating and fullscreen windows (same day, on the owner's note that they were still open). They are not in the
tree: `treeLayout` keeps them out of `reconstruct`, so a workspace with a float still gets its tree, and draws
them over it as ghosts, at their own scale, cut to the screen, faint (0.7) and on top, as krn.overview draws a
float "where it lies, see-through over the tiling". One thing krn.overview has that we do not: where the float
lies. AeroSpace keeps a hidden float's proportional position in `prevUnhiddenProportionalPositionInsideWorkspaceRect`
(MacWindow.swift) and exposes nothing of it, so a ghost is centred over the tiling. That is the one guessed
place in the card, and the see-through is what says so. A fullscreen window's size is the screen, so its ghost
is the whole box. A lone tiled window under a float is still a tree, whatever the root's layout says.

Two corrections from that check. The parent layouts (`window-parent-container-layout`) are not a reliable guide
to structure: two full-width rows in the column reported `h_tiles`, most likely single-child containers AeroSpace
had not flattened, and they were 6 points shorter than their siblings, like an inner gap. The sizes are the
reliable source. And Swift's stable sort does not preserve dfs among windows with equal app name and title in
practice: the listing had two of the four rows swapped. The order comes from `--sort-by dfs` or not at all.

Compared: yabai has none of this problem. It uses macOS Spaces, so windows on other Spaces keep their true frames,
and `yabai -m query --windows` returns `frame`, `split-type`, `split-child` and `stack-index` for every window
(`window.c`, `window_serialize`). YabaiIndicator and YabaiSpaces draw window outlines for every Space from those
frames. Focusing a Space, focusing a window and moving a window to a Space need no SIP change (yabai.asciidoc: the
SIP notes sit on create/destroy/move/swap space, `--switch`, opacity, layers, sticky, scratchpad).

## AeroSpace gives the rects: `%{window-layout-rect}` (2026-09-30, evening)

The owner's question was whether a slim change in AeroSpace would make the overview exact. It does, and the
change is one format variable. AeroSpace already keeps `lastAppliedLayoutPhysicalRect` on every window
(TreeNode.swift:20): the rect the layout put it in last time its workspace was laid out, real gaps included, used
by the mouse code for moving and resizing. It exists for hidden workspaces too, from the last time they were
visible. The branch `feature/list-windows-layout-rect` in ~/sources/aerospace (uncommitted, unpushed) adds
`%{window-layout-rect}` printing it as `x,y,width,height` in points, top-left origin, empty for floating
windows and for a fullscreen window in front, whose frame the layout does not decide. Six files, seventeen
lines: an enum case, a three-line resolver, a docs line, three tests. Built with the repo's own recipe
(`generate.sh`, `xcodebuild`, universal binary, `aerospace-codesign-certificate`), which needed Xcode; AeroSpace's
tests need Xcode's XCTest and were not run here. Installed as the owner's AeroSpace; a restart puts every window
back on workspace 1, as AeroSpace restarts always do.

What AeroControl does with it, in place of the sort-by probe, which the rects supersede:

- `AerospaceCommand.listWindows(layoutRects: true)` appends the variable to the read; `LayoutRects` is learned once
  per process exactly as `TreeOrder` was: only "Can't parse 'window-layout-rect'" followed by a successful plain
  read teaches absent; a dropped socket throws and the next load asks again.
- `WindowInfo.layoutRect` carries the rect; `AeroControlLayout.treeLayout` draws the rects directly when every
  tiled window has one, in the screen's own coordinates (the panel now passes each screen's visible frame with a
  top-left origin, converted from AppKit's bottom-left), at the screen's scale, centred in the card. Rects that
  overlap, an accordion's, pack as tiles instead: a map of them would show only the front window. Floats and fullscreen stay ghosts: their rect
  is empty by design. A tiled window without a rect, opened while its workspace was hidden, sends the card back
  to the engine until the workspace is next shown.
- The engine keeps only its forced reading (`parseUnordered`); the backtracking parser for dfs order and the
  `--sort-by dfs` probe are gone. Nobody runs that fork, and the rects make the order moot.
- The layout symbol is full when the card is exact and fades when it is the engine's reading.

One more cut the same evening, on the owner's eye: the lattice cell had the screen's shape, but the card's inner
box, the cell less header and padding, was wider than the screen, so a drawn screen was letterboxed with air at
the sides. `CardGrid.lattice` now takes the card's chrome and shapes the *inner* box like the screen, so the
drawing fills the card.

And a fact the rects taught us the same evening: `lastAppliedLayoutPhysicalRect` is what AeroSpace *asked* for,
not what the window *is*. Claude has a minimum width; AeroSpace laid it at 418 points in a row of four, the window
server reports 600, and on the screen it stands 180 points over its neighbour. AeroSpace does not correct for
that, so neither does the card: a window is drawn where AeroSpace put it and as big as the window server says,
overlap included. The overlap test that sends accordions to tiles looks at the rects, not the sizes.

Hidden windows sized for their slot (2026-10-03). The tree-only layout gave hidden workspaces true rects, but
their windows kept the size they had when parked, so a picture of Safari at its old 574 points was fitted into
a 333-point slot and shrank. The branch now also sizes a hidden window for its slot, in the corner where it is
parked, and only when the slot changed, so a refresh that changes nothing sends nothing. The app lays its content
out for the slot it will get, and the picture is what one sees when the workspace is shown. AeroControl then
draws every window, hidden or not, at the size the window server reports; the earlier special case for hidden
workspaces is gone. A window with a minimum size still stands over its neighbour, there as on the screen.

The first attempt sized hidden windows from `layoutRecursive` and only the first placement took: `MacApp.setAxFrame`
cancels a window's pending job when a new one arrives, and `hideInCorner` runs right after the layout to set the
corner position, so the size job died unborn (the very first time an `await` in `hideInCorner` let it run). The
test that found it: five windows moved one by one to a hidden workspace, each keeping the slot width of the
moment it arrived, 1696, 842, 559, 418, and only the last one right. Now `hideInCorner` applies the slot's size
and the corner position in one call.

The gap is remembered (2026-10-03). The owner toggled workspace 4 between tiles and accordion while on it and
saw workspace 1's card change too. AeroSpace was innocent: a before-and-after of every workspace's tree and every
window's frame showed only workspace 4's windows moving. The card changed because the gap was read anew on every
draw from whatever the workspaces showed at that moment: as a row, workspace 4 had neighbouring rects 12 points
apart; as an accordion it had none, no other workspace had tiles, and the packed cards fell back to their own
spacing. The gap is one setting in AeroSpace, so `OverviewStore.innerGap` now keeps it once any load has shown
it, for the process. A load that shows no gap teaches nothing, as with the capability probe.

The comma matters: in plain-text `--format` output fields are space-separated, so a rect with spaces was four
columns. The first build used spaces and was replaced the same evening.

## Review and cut (2026-10-03)

A four-model review against AGENTS.md and the owner's own rule — workspace data is immutable, nothing remembered
that could drift from what AeroSpace says — found, and the owner decided:

- **The sizes engine is gone.** `WorkspaceTree.reconstruct`, `frames`, `innerGap` and their tests: about 250 lines.
  It drew only what the sizes forced, but the order was always the listing's, marked by a faded glyph nobody
  reads. It was the one place the overview inferred what AeroSpace had not said. On a release AeroSpace every
  card now packs tiles, as v0.2.1 did; the map is AeroSpace's rects or nothing. `WorkspaceTree.order` stays:
  the layout's order from the rects, for the ring, the keys and the strip.
- **No remembered gap.** `OverviewStore.innerGap` and `screenFrames` are out. Two bugs went with them: the store
  learned the gap before the host had given it the screens, so on a release AeroSpace the first summon drew one
  spacing and the second another; and a refresh never learned at all. Packed tiles now stand one constant apart,
  `AeroControlLayout.packedGapOnScreen` (12 points at the screen's scale), the one assumption in the overview.
  Cards drawn from rects carry the real gap in the rects.
- **No remembered capability.** `LayoutRects` is out: every load asks with `%{window-layout-rect}` and reads again
  without it when AeroSpace cannot parse the variable. One failed call, about 2 ms, per load on a release
  AeroSpace, and nothing stuck when the AeroSpace build is swapped.
- **`WorkspaceInfo.isVisible` was dead**, and with it the `workspace-is-visible` field in the read. `WorkspaceInfo`'s
  fields are `let` now; the filter builds a new value instead of mutating a copy.
- **A ghost without a size** (no Screen Recording) no longer sends an exact card to tiles; it takes the screen's box.
- `Tests/Live` runs against the real AeroSpace on request and stays outside the metrics gate, like Benchmarks.
- The AeroSpace branch: `hideInCorner` sizes a hidden window only when its slot changed since it was last hidden,
  and the bottom-left corner parks a window by the width the app actually has, so a minimum width no longer pokes
  onto the screen. Earlier text in this document saying the resize already happened "only when the slot changed"
  described an intention, not the code, until this fix.

The gate after the cut: 5904 code lines against a baseline of 6211.

## Presentation options that follow

Honest about what is known, cheapest first:

1. Visible workspace mirrored from real frames; hidden workspaces as the packed picture grid. The difference
   is itself information: a hidden workspace has not been laid out.
2. A **layout symbol** on each card for the root layout (row, column, stack). Says what AeroSpace does with the
   windows, claims no placement. Implemented and uncommitted; three of four reviewers found the `square.stack`
   glyph reads as a trash can at that size.
3. A **wireframe** view on a held key: proportional rectangles with icons, uncertain order dashed.
4. The last **screenshot of the whole screen** taken while the workspace was visible, with its age (a recording,
   not a guess, but stale content).
5. The upstream variable, feature-detected, plus a locally built AeroSpace from `~/sources/aerospace` to develop
   the exact renderer against.

## Corrections to earlier claims

- "Hidden workspaces expose nothing" was too strong: layout kinds and parked sizes are readable; only placement
  and order are lost.
- One reviewer claimed `list-windows` only shows visible workspaces (ListWindowsCommand.swift:34). Wrong: it lists
  every window, hidden workspaces included.
- Gaps and `accordion-padding` cannot be read with `config --get`; measure gaps from a visible workspace.
