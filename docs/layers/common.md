# Common

The functional core: AeroSpace's world as values and pure functions. Nothing here imports AppKit or SwiftUI, touches a socket or a clock, or holds a reference; `make test` fails if it does. Everything outside is a shell around it.

**Three areas, each a step down:** `Keys` over `Layout` over `AeroSpace`, and the theme, which none of them names, at the root; `make arch-check` fails if two name each other.

**What it holds.** The model AeroSpace is read into (`WindowInfo`, `WorkspaceInfo`, `OverviewModel`), the reducer `updateOverview` that takes a model and an input and returns the next model and the effects to run, the reading of AeroSpace (`loadOverview`, `parseWindows`, `AerospaceCommand`, `AerospaceEvent`), and the rules the overview lives by: the layout of cards and tiles (`AeroControlLayout`, `CardGrid`, `TilePacker`, `WorkspaceTree`), the keys (`FilterKey`, `GridWalk`, `Strip`, `AppStripModel`) and what one key on an app does (`Summon`, `AppSummon`).

**Rules.** AeroSpace is the source of truth: the reducer never guesses a state, it asks for a read. A tiled window is drawn at its slot, whatever its app made of it; a stack is drawn as all its windows, since this is an overview. The marking is one value, `Strip`, for the map and the strip alike; every change is a new value.

**Decisions.** The read asks for `%{window-layout-rect}`, the owner's AeroSpace branch, and falls back to the plain read on a release. Layout is reconstructed from AeroSpace's rects only. The two reads are sequential on purpose: AeroSpace serialises commands, and concurrent reads cost more.
