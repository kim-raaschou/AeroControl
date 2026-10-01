# The outer grid, judged against the literature

How the workspace cards should be placed on the screen. Four independent reviews (Fable, Opus, Sonnet, Haiku;
all read-only) were asked the same question: which of the candidates below can be grounded in published work or
in shipped overviews, and what does each cost in picture size on this owner's real inputs. This document records
what they agreed on, where they split, and what was actually checked against a primary source. Nothing here has
been built. Written 2026-09-30.

## Candidates

- **A** today: `CardGrid.layout` (exhaustive row breaks for n ≤ 10, weights 0/1/2 by window count, max-min
  picture height) followed by `CardGrid.hug`, which narrows each card to what its pictures need and recentres the
  row. **A0** is the same without `hug`.
- **B** the krn.overview rule as DESIGN.md describes it: three weight steps, a card that stops growing at the
  monitor's shape, the surplus given back to the cards that can still use it.
- **C** one identical monitor-shaped cell per workspace, empties included, in an r × c lattice (GNOME Shell,
  KWin, niri, hyprexpo).
- **D** as C, but the cell shape may leave the monitor's shape within a band (half to double) so the lattice
  fills the box; last row at least half full.
- **E** an ordered quantum strip treemap: one picture size for every window on the screen, rows flush, card
  widths follow their content.

## What was verified, and by whom

Confirmed against the primary source by at least two reviewers working independently:

- **Bederson, Shneiderman & Wattenberg, ACM ToG 2002.** Quantum treemaps "always produce layouts where elements
  are the same size and are aligned on a single global grid"; ordered layouts are more stable than squarified
  (their Table I: squarified change 10.10 against strip 4.98). The "elements" are the pictures, not the cards.
- **Felsner, Nathenson & Tóth, arXiv:2112.03242, Theorem 2.** A layout is weakly aspect-ratio universal iff it is
  sliceable. Every candidate here is sliceable (rows), so the theorem excludes none of them; it says only that a
  non-sliceable treemap would be the wrong tool.
- **GNOME Shell `workspace.js`.** The workspace container's preferred width is the height times the work area's
  aspect ratio; `_createBestLayout(this._workarea)` lays out the windows inside that cell. Window count never
  changes the cell.
- **KWin overview `Main.qml`.** `gridSize = max(rows, columns)`, `yScale: xScale`; every desktop cell is the same
  size and shape.
- **krn.overview `CardGeometry.js`.** Candidate B does **not** ship. Commit 3d0c78b (2026-09-21, "Fast plads til
  alle påkrævede workspaces, og udlign flisestørrelsen") removed the screen-shaped cap because it coupled width to
  row height and, in a fuzz over 200 000 layouts, gave the busy card under half the tile height in 71.8 % of
  pairs. What ships is a brute-force row-break search with max-min tile height, the same rule as the Swift port.
  DESIGN.md's paragraph "How big a card is" is stale. Verified by me against the commit message and the code.

Confirmed by one reviewer from the primary source:

- niri: `workspace_size = view_size.upscale(zoom)` (monitor-shaped cell). hyprexpo: `tileSize = m_size /
  SIDE_LENGTH`, read from a mirror because the original path is gone from `hyprland-plugins` main.
- Felsner et al. Lemma 6: a sliceable layout's realization is unique up to scale, so the bounding box's shape is
  determined by the tree.

Confirmed only from abstracts or secondary citations (treat as indicative):

- Tak, Cockburn et al., INTERACT 2009/2011 (SCOTZ): spatially stable switcher layouts are significantly faster
  than recency layouts (1.2 s against 2.1 s reported by one reviewer).
- Scarr et al., CHI 2012: spatially stable flat layouts 25 to 34 % faster.
- Kaasten, Greenberg & Edwards 2002: thumbnails need more than 96 px for recognition; 208 px for 80 %.
- Bui, Vidal & Hà 2019 (sum of perimeters O(n log n); minimax variants NP-hard); de Berg et al. (aspect ratio
  cannot be bounded with rectangular regions).

Not verified by anyone: Bruls et al. Squarified Treemaps (PDF returned 503 twice), Mo & Walrand, Kelly, COSMIC
source (only the design issue), any GNOME design rationale text.

Haiku's report recommended D but repeated unverified quotes as "confirmed" and mis-stated numbers, as in earlier
rounds. It is not counted below.

## Measurements

All three counted reviewers compiled the real `CardGrid`, `CardGrid.hug` and `TilePacker` code into a scratch
harness and reproduced the owner's screenshots exactly (row breaks and row heights). Every window was given the
shape 1.547; box 1624 × 994 points. "Picture" is the smallest drawn window in points. "Ragged" is how far the
rows' left and right edges disagree. "Moves" is how many other cards shift when one window is added.

Where two reviewers measured the same case they agree to within a few points, with one exception noted below.

| candidate | smallest picture, 7 ws [0,2,3,1,4,1,1] | 8 ws | 16 ws | ragged | moves |
|---|---|---|---|---|---|
| A today (with hug) | 159 | 137–149 | 93 | 170–820 | 3–7 |
| A0 (no hug) | 159 | 137–149 | 93 | ≤ 1 | 3–5 |
| B (stale plugin rule) | 112–159 | 80–137 | 9–93 | up to 1250 | 5–8 |
| C monitor-shaped cells | 112 | 74–91 | 45 | 0 (holes in last row) | 0 |
| D banded cells | 109–112 | 99 | 50 | 0 | 0 |
| E quantum strip | 197 (Opus, Sonnet); 124 (Fable) | 175 | 118 | ≤ 3 (Opus, Sonnet); 782 (Fable) | 3–10 |

Two facts every counted reviewer measured independently:

- **`hug` changes no picture size.** It only narrows cards, which is what turns flush rows into the pyramid
  (ragged 1 → 410 on the owner's screenshot) and doubles the spread of card sizes.
- **B never binds on these inputs**, and where it does bind (16 workspaces) it inverts the distribution, exactly
  the fault the plugin removed it for.

The exception: E was constructed differently. Opus and Sonnet built it as "one picture size everywhere, rows
flush, widths follow content" and both got 197 points. Fable built a plain strip treemap and got 124, ragged.
The two numbers are for two different algorithms under one letter; the 197 figure is the one that matches the
description of E above.

## Where the reviews split

All three counted reviews say the same first thing: **remove `hug`**. It is the sole cause of the pyramid, it buys
no picture size, and A0 is already flush.

After that:

- **Fable → C.** Every shipped overview that could be read (GNOME, KWin, niri, hyprexpo) uses identical
  monitor-shaped cells sized by count alone. The stability literature (Tak, Scarr) rewards a layout where nothing
  moves. Price: pictures about 30 % smaller than today; at 16 workspaces 45 points, below Kaasten's threshold;
  two holes in a 3 × 3 for seven workspaces.
- **Opus → D.** Same reasoning, but lets the cell shape leave the monitor's within a band so the lattice fills
  the box and the last row is at least half full. Price: 27 to 46 % smaller pictures; a lone busy workspace
  shrinks 62 %. Opus notes the band and the half-full rule are its own, not the literature's.
- **Sonnet → E.** Reads Bederson et al. literally: the quantum treemap makes the *pictures* equal and aligned,
  which is what a "perfect grid" of windows means, and it is the only candidate that makes pictures larger
  (+19 to 27 %). Price: 3 to 10 cards move when a window is added.

The split is not about facts; it is about what "a regular grid" refers to. C and D make the **cards** a lattice
and let the pictures inside vary. E makes the **pictures** a lattice and lets the cards vary. Bederson's quantum
treemap is the published form of E. GNOME and KWin are the shipped form of C.

## Judgement

1. **Remove `hug` now.** Unanimous, measured, and it restores flush rows at zero cost in picture size.
2. **If regularity of cards is the goal** (what every shipped overview does, and what the stability studies
   measure): C, with D as a variant that trades a little shape fidelity for a fuller box. Expect pictures a
   third smaller and, at seven workspaces, holes.
3. **If regularity of pictures is the goal** (the quantum treemap, and the only route to larger pictures): E.
   Expect card widths to vary and cards to move when windows come and go.

The owner has said they prefer a "perfect" grid. Which of 2 and 3 that means is the one decision the literature
cannot make.

**Decision (owner, 2026-09-30):** weight Fable and Opus over Sonnet, so identical cards; and identical pictures too.
Built as C (Fable's monitor-shaped lattice, `CardGrid.lattice`). `hug` and the row-break search were removed
first, as all three reviews asked. One picture height for the whole screen was built on top and reverted the same
day: with one six-window workspace every picture on the map fell to about 70 points, and cards with two windows
were 85 % air. What stands is C as Fable and Opus measured it: identical cells, each card's pictures as large as
its cell allows, centred in the cell. Verified on screen.

## Sources

- B. Bederson, B. Shneiderman, M. Wattenberg. Ordered and Quantum Treemaps. ACM ToG 21(4), 2002.
- M. Bruls, K. Huizing, J. van Wijk. Squarified Treemaps. VisSym 2000. (Not reached.)
- S. Felsner, A. Nathenson, C. Tóth. Aspect Ratio Universal Rectangular Layouts. arXiv:2112.03242.
- M. de Berg, B. Speckmann, V. van der Weele. Treemaps with bounded aspect ratio. Comput. Geom. 2014.
- Q.-H. Bui, T. Vidal, M. H. Hà. On three soft rectangle packing problems with guillotine constraints. 2019.
- S. Tak, A. Cockburn et al. Satisficing and the use of keyboard shortcuts / SCOTZ. INTERACT 2009, 2011.
- J. Scarr, A. Cockburn, C. Gutwin, A. Bunt. Improving command selection with CommandMaps. CHI 2012.
- S. Kaasten, S. Greenberg, C. Edwards. How people recognize previously seen web pages from titles, URLs and
  thumbnails. HCI 2002.
- GNOME Shell `js/ui/workspace.js`; KWin `src/plugins/overview/qml/main.qml`; niri overview; hyprexpo.
- krn.overview `CardGeometry.js` and commit 3d0c78b; `docs/LAYOUT.md`; `docs/DESIGN.md` ("How big a card is",
  stale).
