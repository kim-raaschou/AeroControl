# Review of the overview

Status: notes from four independent reviews (Fable, Opus, Sonnet, Haiku) of the map as it looked in the
owner's screenshot on a 1728 x 1117 built-in display, plus a second look by Fable comparing two screenshots.
Read together with `docs/outer-grid-literature.md` (when written), which asks what the outer grid should be.

## What the reviewers agreed to keep

- The two pure layout engines, `CardGrid` (outer) and `TilePacker` (inner), and the split between them. Fable
  and Opus each re-ran the engine on the screenshot's inputs and reproduced the row breaks exactly
  ([1 2 3] / [4 5] / [7 9 10]). Of five alternative breaks the chosen one was best on both the smallest
  picture and the total picture area; changing `rowGain` to 1.0 changes nothing. The row search is right:
  leave its objective alone.
- Every window at its own shape, one shared picture height inside a card.
- The focus read: accent ring, filled badge, the frame round the window you came from; hover-only close; the
  grid revealed in its final shape before pictures land. (The three weight steps and the empty workspace as a
  narrow strip were kept at the time; both went with the lattice, see below.)
- Captions with window titles **only while filtering**. Three reviewers called titles on the whole map a bad
  idea: they cost 38 points per tile and every picture shrinks. (One reviewer recommended it and was out-voted.)

## What was found weak

1. **Space.** A card with one window was drawn small in a wide card (about a quarter filled). Single-window
   cards in tall rows had empty room under the picture. On a card with five windows the short second row hugged
   the left and left a hole at the bottom right.
2. **Recognition.** Dark terminals and IDEs looked alike; the app icon on a picture was 16 points; a dark
   picture on a dark card had no edge; no title on the map.
3. **The layout symbol** (`square.stack` for accordion, 13 points, 70 % opacity) read as a trash can to three
   reviewers and was invisible to a fourth; it sits where a close button usually goes.
4. **Focus** on the card level depends on a 24-point badge once the ring moves away.
5. **Scale cliffs.** `CardGrid.layout` searches row breaks only for up to 10 workspaces; at 11 it silently uses
   the default columns. `weight(forCount:)` caps at 2, so a card with twelve windows drags the shared height down.

## What was done (uncommitted)

- **One lattice of identical, screen-shaped cells** (`CardGrid.lattice`), the row count that gives the largest cell,
  centred, last row left-aligned. Each card packs its own pictures as large as its cell allows, centred in it.
  Decided 2026-09-30 after the literature review; `CardGrid.hug`, the row-break search, the three weight steps and
  the narrow empty strip are gone. One picture height for the whole screen was tried the same day and dropped: a
  single six-window workspace shrank every picture on the map to about 70 points.
- **The workspace as AeroSpace laid it out**: from `%{window-layout-rect}` when the AeroSpace has it (the owner's
  branch), asked for on every load; otherwise packed tiles. The engine that read a tree from window sizes was
  built, verified against the owner's workspace 7, and removed again on 2026-10-03 after review: it inferred what
  AeroSpace had not said. See docs/aerospace-layout-data.md, "AeroSpace gives the rects" and "Review and cut".
- **Pictures sized to the screen and kept true while the overview is open** (2026-10-01). A picture is taken as large
  as a card can draw a window on the screen the overview is on, in its pixels (`AeroControlLayout.captureSize`), so a
  34-inch screen at 1x is not a blur; the fixed 720 × 480 is now the floor. After every refresh while the overview is
  on screen (a move, a close, an AeroSpace event) all sizes are read again and only the windows that changed size or
  appeared get a new picture (`OverviewStore.refreshChangedPictures`). A refresh now also keeps what was learned about
  `%{window-layout-rect}` instead of asking again.
- **Short rows centred** in `TilePacker.packRows`.
- **A hairline round every picture** and a **larger app icon** (`AeroControlMetrics.badgeSize`: a ninth of the
  picture's width, clamped to 22 to 36 points).
- **A layout symbol** in each card header (root layout as row, column or stack), also for a single window, with a
  tooltip. Nothing for an empty workspace. Needs `workspace-root-container-layout` in the list-workspaces read.

Tests: 133 green at the time of writing; 165 after the work recorded below.

## Judged and not done

- Vertical centring of pictures in a card was first left out (the owner had wanted windows hung from the top), then
  done on 2026-09-30 once every cell was the same size: a card with two windows under a busy neighbour read as a
  top-heavy box otherwise (`AeroControlLayout.tileOrigin`).
- The accordion glyph is now `rectangle.on.rectangle`; `square.stack` read as a trash can to three of four reviewers.
- Screen-shaped cards: one reviewer against (eight cards would be about 430 x 270 points), one for. Now under
  literature review; see `docs/outer-grid-literature.md`.
- A window-style setting (screenshots or icons) was built and removed at the owner's request.
- A `windows` picker that is not the strip, and the `aerocontrol://open` link, were built and removed earlier.

## Second look: two screenshots compared

The owner's screenshot showed the hint line at the bottom edge partly cut off; a screenshot taken on the same
machine minutes later did not. Fable compared the two and concluded it is **a cropped screenshot, not a layout
bug**: every fixed-size element in the owner's image is about 7 % larger than in the other (an empty strip 75
pixels against 70; rows 505/290/290 against 469/271/271), and `CardGrid` run on the owner's counts reproduces both
at 1.235 and 1.157 pixels per point. The owner's image therefore covers only about 1619 x 1050 of the 1728 x 1117
points, and the screen-recording dot at the top right is missing. The panel is 94 % of the screen height,
centred, so the hint sits 46 points clear of the bottom edge on the real screen. Not verified by seeing the
owner's screen.

Opinion on the newest look against the previous one:

- Better: one-window cards no longer sit in empty boxes; badges legible; the hairline gives dark windows an edge;
  centred rows tidy.
- Worse: the rows now form a ragged pyramid with dead zones at the sides; a card with two pictures is as tall as
  its neighbour that needs two rows (about 45 % of it empty); picture heights differ between cards.
- Suggested next change at the time: weight cards with one to three windows by count inside a row (2 : 3
  instead of 1 : 1) in `AeroControlLayout.weight(forCount:)`, and replace the `square.stack` glyph (for example
  `rectangle.on.rectangle`). The weight suggestion is superseded by the literature review below: all three
  counted reviewers measured that `hug` alone causes the pyramid and changes no picture size.

## Open

Which outer grid to aim for: the owner prefers a regular, flush grid. See `docs/outer-grid-literature.md`.
Unanimous first step there: remove `hug`. Note that the krn.overview rule this document earlier took as a
candidate (cards capped at the monitor's shape, surplus redistributed) no longer ships: the plugin removed it in
commit 3d0c78b on 2026-09-21, and its DESIGN.md paragraph "How big a card is" is stale. What ships there is the
same brute-force row-break search as `CardGrid.layout`.

## The strip, rebuilt on krn.overview's (2026-10-01)

The app picker now follows krn.overview's strip, with three decisions by the owner: the marking only chooses (focus on
Enter, a key or a click, as macOS's Cmd-Tab, so stepping never switches AeroSpace's workspace behind the strip); the
windows carry keys 1–9 then a–f and there is no typing in the strip (search belongs to the map); the summon key again
moves the marking on, as Cmd-` does.

- `AppStripModel` (Common) is a port of the plugin's `AppStripModel.js` and its tests: the first marking on the window
  after the one you are in, stepping with wrap-round, Home/End, the marking handed on when its window closes, card
  height between a fifth and half the panel, the ring when the cards do not fit, the frames, the keys.
- The strip has its own state in the store (`OverviewStore.Strip`: bundle id, origin, marking) instead of borrowing the
  filter, so a window of another app whose title names this one is no longer in it.
- Each workspace is a card of the map's in its screen's shape at one height (`AeroControlLayout.stripLayout`):
  AeroSpace's rects or the tree read from sizes, the whole workspace (`OverviewStore.stripWorkspaces`), the other
  apps' windows grey at 0.3, outlined, with their icons and out of reach (`AeroControlAppTile.faded`): 0.45 drew the
  eye, krn.overview's 0.15 vanished on a dark card. The window you came from wears the same outline at full strength. A card
  whose layout cannot be read packs only the app's windows. Each card is the map's card (`AeroControlCardFace`).
- Pictures are taken at one size, a strip card's at its largest (`AeroControlLayout.captureSize`); a tile that draws
  one larger asks for it again at its size (`OverviewStore.wantPicture`), once. The strip takes only its workspaces'
  windows. A visit's pictures are held back until the capture is in, or 120 ms have passed, then land together;
  closing drops them. A picture taken again fades in over the one it replaces (`FadingPicture`).

Verified on screen with Ghostty on two workspaces: screen-shaped cards, labels, keys on every window, the marking on the
first window when coming from another app, and the summon link stepping it. The ring (cards wider than the view) is
seen on screen with Ghostty on four workspaces. As in krn.overview, keys move the carousel's centre and the pointer does not (`Strip.centre`): pointing marks a
window, but the row stays put under the hand. Pointing marks only when the mouse has moved (`pointStrip`): cards that
slide under a resting mouse, as the strip opens or the carousel turns, would otherwise take the marking from the keys.
From three workspaces the strip is always a carousel (`carouselFrom`, the owner's choice over krn.overview's measured
"stand still when it fits"): the marked workspace's card in the middle, centred on the card rather than the window, so
stepping within a workspace moves only the marking and the row turns a whole card at a time.

The carousel is a ring drawn whole (`AeroControlLayout.stripPlacements`): the cards repeat every ring's width and each
is shown where it shows, once when it shows whole, else every piece the edges leave, so with four cards the one across
the ring is cut by both edges and the row is symmetric. It turns: the store counts the times the keys take it past the
last card (`Strip.turns`), so it moves on one card the same way rather than jumping back, animated over 0.4 s. The
copies a card beyond either edge are placed too, unseen, so a turn slides them in instead of making them appear at the
edge — the jolt the owner saw at the outer cards. krn.overview's `ringShifts`, which gave each card one place and left
the card across always on the left, is gone.

## Navigation follows the layout (2026-10-01)

AeroSpace lists a workspace's windows by app name, then title. With rects, `buildOverviewResult` now orders each
workspace's windows by the layout (`WorkspaceTree.order`): the rects are cut along lines that cross no window, columns
before rows, and read left to right and top to bottom, which is AeroSpace's own tree order for a tiling layout. The
first match, the strip's steps and its keys all follow it. Found on the owner's workspace 4, Mail on the left and
Ghostty on the right: Tab from workspace 3 went to Ghostty first (the map's Tab has since been removed, 2026-10-03). Overlapping rects (an accordion) and windows without
a rect keep the listing's order, the latter after the placed ones.
