# Kit · State

The stores: the imperative shell around the core, one per concern, all on the main actor.

**`OverviewStore`** owns the model and the visit. It reads AeroSpace (`reload`), listens to its events (`startListening`), runs the reducer on every input (`send`) and carries out its effects: commands in order, then a read. It holds what is the user's, not AeroSpace's — the query (`filter`), the marking, the pointer — and, given the screen, derives the layout: `shown`, `cards`, `stripLayout`, `drawn`. The views read it; nothing flows back up. It also re-asks a focus AeroSpace did not carry out (issue 101, a WORKAROUND).

**`PictureStore`** owns one visit's pictures: sizes measured first, pictures landed a card at a time, taken again where a tile draws one larger or a window changed shape, dropped when the visit ends. `PictureResampler` scales a capture once to the pixels it is drawn at.

**`SettingsStore`** is the one setting, the theme, in `UserDefaults`.

**`NativeApiBridge`** is the port to macOS the stores need — icons, sizes, pictures, the live window, Screen Recording — owned here, implemented in Adapters, faked in tests.

**Rules.** The model changes in one step, from the reducer only. A refresh reads 20 ms after the event (`binding-triggered` comes before the commands run), lands the layout at once, and lets the sizes and pictures follow together once the windows stand still. A generation number guards every late answer.
