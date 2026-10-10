# Kit · State

The stores: the imperative shell around the core, one per concern, all on the main actor.

**`OverviewStore`** owns the model and the visit. It reads AeroSpace (`reload`), listens to its events for as long as the app runs (`startListening`), runs the reducer on every input (`send`) and carries out its effects: commands one after another, a read after. It holds what is the user's and not AeroSpace's — the query (`filter`), the marking, the pointer — and, given the screen by the host, derives the layout: `shown`, `cards`, `stripLayout`, `drawn`. The views read it; nothing flows back up. It also knows the window AeroSpace focused is not always the one asked for (issue 101, a WORKAROUND).

**`PictureStore`** owns the pictures of one visit: sizes measured before any picture, pictures landed a card at a time, taken again where a tile draws one larger or a refresh changed a window's shape, and dropped when the visit ends. `PictureResampler` scales a capture once to the pixels it is drawn at, so a picture is sharp and the memory is one bitmap.

**`SettingsStore`** is the one setting, the theme, in `UserDefaults`.

**Rules.** The model changes in one step, from the reducer only. A refresh reads 20 ms after the event — AeroSpace's `binding-triggered` comes before the commands run — lands the layout at once, and waits for the windows to stand still before the sizes and pictures follow together. A generation number guards every late answer.
