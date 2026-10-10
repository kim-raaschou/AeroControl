# App / Entry

The AppKit host: what needs `NSApp`, a panel, a menu or a link from Launch Services. No layout, no rules, no AeroSpace parsing.

**`AppDelegate`** is the composition root. It builds the runner, the bridge, the stores and the two controllers, keeps the app an accessory, and turns a reopen or an `aerocontrol://` link into a summon. **`OverlayWindowManager`** runs the visit: a summon reads AeroSpace, measures, builds the window on the screen under the mouse, hands the store the screen, reveals the overview a moment after the pictures start landing, and ends it when a focus is sent, Escape is pressed or the strip's app loses focus. It also starts an app that has no window and quits or closes the one under the ring. **`OverviewWindow`** is the borderless, non-activating panel that owns the keyboard while the overview is up: Escape, the arrows, typing and ⌘ keys become `FilterKey`s, ⌘Q and ⌘W are taken before the menu can. **`MenuBarController`** is the status-bar menu: the theme, Screen Recording, Quit. **`OverviewRoot`** is the SwiftUI root with the backdrop.

**Rules.** Summoning never activates the overview's app in the user's sense: the panel is non-activating, and the keyboard goes back to the app under the focused window when the overview closes. The window is rebuilt per summon and released when hidden, its pictures with it.
