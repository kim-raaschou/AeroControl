# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A one-shot workspace overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Summon it, see every workspace across your monitors with window previews, do one thing —
focus a window, jump to a workspace, move a window, merge two workspaces — and it is gone.

AeroSpace does the window management. AeroControl only shows you what AeroSpace has and
hands it one command, over AeroSpace's own Unix socket.

## What you get

Five things you do all day, each one summon and one key:

- **"Where did that window go?"** Press the key. Every workspace is on screen as a card,
  every window as a live picture, so you see it rather than remember it. Click it, or type
  until it is first and press Enter. Mission Control, but for AeroSpace's workspaces and
  with the windows AeroSpace has parked off-screen.
- **"Which of my Arc windows?"** One key per app (`aerocontrol://app-id=<bundle id>`, or
  `app-name=<name>`).
  With three Arc windows, only they appear, with their titles, and the ring is already on
  the one you used before — Enter goes back. Cmd-` with pictures. With one window the key just focuses
  it, and with none it starts the app.
- **"The Teams window with the meeting in it."** Press the key and type `te`: the map
  collapses to the windows whose title or app name starts with that, titles shown. Type more
  to narrow, Enter when it is first. No mouse, no reading a number off a badge.
- **"This belongs on workspace 3."** Drag the window's picture onto the other card. Or drag
  a whole card onto another to merge two workspaces into one.
- **"Close the strays."** Hover a picture for its close button, or point, type or walk until it
  wears the ring and press ⌘W to close it, ⌘Q to quit its app — the overview stays up for the next one.

What it is not: a window manager, a dock, or a permanent panel. It has no state of its own
between summons, and it asks for no permission except Screen Recording for the pictures.

## Features

- One shot, Mission-Control style: a full-screen blurred overlay on the screen under the
  mouse. Starts hidden, summoned by a key bound to `open aerocontrol://workspaces`, dismissed
  as soon as you focus a window or a workspace, or with Escape / a click on the backdrop.
  The ring starts on AeroSpace's focused window and follows every focus change AeroSpace
  reports, until you press an arrow: then it is yours, and a thin outline keeps showing where
  AeroSpace's focus is. The window under the ring is live, a stream of it rather than the
  picture taken at the summon, on the map and in the strip. See *Keyboard*.
- A grid that spends the screen on the windows: one card per workspace, in AeroSpace's
  order, every card the same size and the shape of its screen, as GNOME and KWin shape their
  workspace cells. Cards hold still through window churn. Inside a card every window is drawn
  where AeroSpace put it, at its own shape, or packed at one height when AeroSpace has not said, in
  AeroSpace's order. Where AeroSpace put a window is `%{window-layout-rect}`, which no AeroSpace
  release has yet (it is a branch of the author's); with a released AeroSpace every card is packed.
  The layout engine is shared with
  [krn.overview](https://github.com/kim-raaschou/krn.overview), the same author's overview
  for Omarchy/Hyprland.
- **Type to filter**: start typing and the grid collapses to the windows whose title, app
  name or workspace name has a word starting with what you typed — `te` finds Teams, `toml`
  finds `aerospace.toml`, `lars teams` finds a chat, `code main` Code's window "main", `2 saf`
  Safari on workspace 2. Each match shows its full title, the focus ring
  marks the first one, Enter focuses it: type until the one you want is first. See *Keyboard*.
- **One key per app**: `open aerocontrol://app-id=<bundle id>` (or `app-name=<name>`) opens the overview
  already filtered to that app — three Arc windows, nothing else — with the ring on the one
  you used before, so Enter alone goes back to it and the arrows walk the rest. One line under the
  cards names the app and the marked window's title; point at a window to read its title
  there. With a single window the key focuses it.
- **Floating windows** are marked by a raised shadow, so a window that is not part of the
  tiling layout reads as lying on top of it.
- **Window previews**: each window is captured once per summon (ScreenCaptureKit, works for
  windows AeroSpace has parked off-screen). The overview appears first, in its final shape,
  and the pictures land in it as they are taken — about 170 ms to the overview and another
  ~300 ms until the last of twenty pictures. Needs the Screen Recording permission; without
  it the tiles are plates with their app's icon and the window's title — the overview is built
  around the pictures — and the menu offers to request it.
- Click a tile to focus the window; click a workspace badge to focus the workspace.
- Drag a tile onto another workspace to move the window there.
- **Merge**: drag a workspace card (grab it anywhere outside a tile) onto another workspace to
  move all of its windows there, in on-screen order, then focus the target. AeroSpace moves
  windows one by one into the target's root, so into an empty workspace the source's layout
  comes along — a stack stays a stack — while into one with windows they tile beside what is
  there. No undo — drag them back.
- Hover a tile on the map to reveal the close action; the strip has no close button, ⌘W does it there.
- Multi-monitor aware: every workspace is listed, whichever monitor AeroSpace put it
  on, and the overlay itself always opens on the one screen under the mouse. With more
  than one display each card names its own; with a single display nothing is shown.
- Menu-bar configuration with persisted settings.

## Requirements

- macOS 26+
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation) 0.21.0-Beta or newer:
  that release introduced the `subscribe` command and made the socket protocol public, which
  is everything AeroControl talks to.
- Optional: Screen Recording permission for AeroControl (window previews). Everything else
  works without any privacy permission.

```bash
brew install --cask nikitabobko/tap/aerospace
```

## Install

### Homebrew cask (preferred)

```bash
brew install --cask kim-raaschou/tap/aerocontrol
```

### Build from source

Requires Swift 6.2+ and `make`. Plain Command Line Tools work: the Makefile builds against
the bundled macOS 26 SDK (CLT 27's macOS 27 SDK needs Xcode's SwiftUI macro plugin) and
points `swift test` at the Swift Testing plugin. Set `SDKROOT` yourself to override.

```bash
git clone https://github.com/kim-raaschou/AeroControl.git
cd AeroControl
make install
```

`make install` builds `AeroControl.app`, installs it to `/Applications` and relaunches it.
To keep the Screen Recording grant across rebuilds, run `script/sign-identity.sh` once first.

### Summon it from AeroSpace

Two kinds of summon: the map, and one key per app. Both reach the running instance through
Launch Services — no second process, no signal — and start it when it is not running. Bind
them to whatever keys you like in your AeroSpace config (`~/.aerospace.toml` or
`~/.config/aerospace/aerospace.toml`):

```toml
<your key>      = ['exec-and-forget open aerocontrol://workspaces']               # the map
<a key per app> = ['exec-and-forget open aerocontrol://app-id=com.apple.Safari']  # that app, by bundle id
<another>       = ['exec-and-forget open aerocontrol://app-name=Safari']          # or by name, spaces as %20
```

`aerospace list-apps` prints every running app's bundle id beside its name.

`workspaces` closes the overview when it is already up; an app's key while it is up is that app's flow again, its strip
taking over from whatever was showing. The strip is not a third view: it is the part of the app rule that cannot be
settled without you (see *The map and the strip*). The rule:

| Windows of the app | What happens |
|---|---|
| none | the app starts; an id or name no app has is said on the strip's lane, and Escape closes it |
| one | that window is focused |
| two, and you are in one | the other one is focused — a toggle |
| two from elsewhere, or more | the strip opens with just them, ring on the one you used last — pick |

Bundle ids of everything open: `aerospace list-windows --all --format '%{app-bundle-id} %{app-name}'`.

`open -a AeroControl` toggles the map too (a reopen event), and is the one command that works
before the URL scheme is registered — Launch Services learns it on the app's first launch.

## The map and the strip

Two surfaces, two rules.

**The map follows AeroSpace.** The overview is a picture of what AeroSpace has, and nothing
in it is chosen until you point, type or press an arrow. Until then the ring is AeroSpace's
focus: it moves the moment AeroSpace reports a focus change — switch workspace with your
AeroSpace key while the map is up and the ring is on the new window before the pictures have
settled. The arrows take the ring over: ← and → through each workspace's windows as they are
drawn, which AeroSpace's order within a workspace does not give, then on to the next; ↑ and ↓
straight up and down as the windows are drawn; from then on AeroSpace's focus is the thin
outline, as in the strip, and nothing goes to AeroSpace until Enter. Find a window by pointing
at it, by typing until it is first, or by walking to it.

**The strip is a picker.** The per-app keys settle three of their
four cases from AeroSpace's state alone, at once and without a word (none: start; one: focus;
two and you are in one: the other). The fourth case — two windows from another app, or three
or more — has no answer without you, and that is the strip: a row of the app's workspaces, a
marking on the most likely answer (the app's window you used last other than the one you are
in, or else the one after it), and keys to move it and confirm. The marking is your choice in the making, so it lives
in the strip, not in AeroSpace, until Enter makes it AeroSpace's focus. Two truths are on
screen: the ring is the marking, the thin outline is where AeroSpace's focus is now.

A strip is opened only by its app's key. While it is up AeroSpace still decides: move the focus
within the app and the strip stands; move it anywhere else with an AeroSpace key, another app or
an empty workspace, and the choice was made there: the strip closes and you are where AeroSpace
put you. For another app's strip, press that app's key.

Each card is a workspace in its screen's shape, true to AeroSpace's geometry where AeroSpace says
where the windows are, and on a crowded workspace that is slivers: eighteen windows in `h_tiles`
get 82 points each. A window on a visible workspace is drawn at its own size, as on the screen; on
a hidden one at its slot, since in the corner it still has the size it last had. Where it does not (an accordion, a released AeroSpace) the app's windows are
packed in the card as on the map. One workspace all but fills the screen; several are each at
most a third of it high. One line under the cards, as high as the map's, names
the app, how many windows, and the marked window's title, with its workspace when the app spans
more than one. Every window's key is on its card; pointing at a window marks it, so a sliver is
read by pointing at it.

Built for two to five windows of an app: there the strip is a confirm step with a picture, and
the arrows are the exception. It handles more — a row that does not fit slides to keep the marked
workspace whole in the middle, up to its ends, the workspaces the edges cut dimmed; ⌘→ and ⌘← a
workspace along, ⌘1–⌘9 and ⌘a–⌘f reach the first fifteen, the arrows the rest.

## Keyboard

On the map:

| Key | Does |
|---|---|
| letters, digits, space | filter; the grid narrows from the second character |
| ← → | move the ring through a workspace's windows in reading order, then on to the next workspace, round the map; an empty workspace is one stop, its card wearing the ring |
| ↑ ↓ | move the ring straight up / down as drawn, to the nearest window over / under it, into the card over or under |
| ⌘→ / ⌘← | move the ring to the next / previous workspace's first window, or onto it when it is empty |
| ⌘↓ / ⌘↑ | move the ring to the first window of the workspace below / above |
| Enter | focus the window under the ring: where the keys put it, the first match, or the focused window; on an empty workspace, switch to it |
| Escape | clear the query; on an empty query, dismiss |
| ⌘W | close the window under the ring, as its × does — the overview stays up |
| ⌘Q | quit the app under the ring — the overview stays up |
| ⇧⌘ + a workspace's name | move the window under the ring to that workspace: ⇧⌘3 to 3, ⇧⌘0 to 10 — the overview stays up. A name no workspace has yet creates it, as AeroSpace does: ⇧⌘q is a new workspace q with that window |

Matching is word-prefix, case- and diacritic-insensitive: every word you type must start a
word in the window's title, app name or workspace name, taken together. A query that matches nothing leaves the full map
standing and says so. Without a query the ring is on AeroSpace's focused window until a key
moves it.

In the strip the keys move the marking as they move the ring on the map, the strip being one row of cards:

| Key | Does |
|---|---|
| ← → ↑ ↓ | as on the map: through a workspace's windows and on to the next, or straight up / down |
| ⌘→ / ⌘← | move the marking to the next / previous workspace, the row sliding with it |
| a workspace's name | move the marking to that workspace: 3 for workspace 3, 0 for 10 |
| ⌘1 – ⌘9, ⌘a – ⌘f | focus that window: the keys the windows carry, fifteen in all |
| ⌘W / ⌘Q | close the marked window / quit the app, as on the map; the marking goes on to the next |
| ⇧⌘ + a workspace's name | move the marked window to that workspace, as on the map; a new name creates the workspace |
| the app's own key again | move the marking on, as Cmd-` does |
| Enter | focus the marked window |
| Escape | dismiss, back on the window you came from |

There is no typing in the strip; the app is already chosen, and a key that names a workspace goes there. Pointing marks a window, here and on the map.

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration. Motion is macOS's to set: with
**Reduce motion** on (System Settings → Accessibility → Display) the overview moves in one frame.

- **Theme**: **System** follows macOS (your accent color, light/dark, frosted cards), or one
  of the built-in palettes — Tokyo Night, Catppuccin Mocha, Catppuccin Latte, Nord, Gruvbox
  Dark, Dracula, Rosé Pine, Solarized Dark — each shown with a colour swatch. A fixed palette
  looks the same whatever the system appearance is.
- **Window Previews**: grant Screen Recording when it is missing.
- **Quit**.

The theme persists (`UserDefaults`). AeroControl writes no config: the key lines above are
yours to paste.

## Optional AeroSpace setting

For a stable full row of workspaces (including empty ones), set:

```toml
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
```

## Develop

```bash
make build
make bundle
make install
make run
make test
make clean
```

## Release

```bash
make release VERSION=0.1.2 PUBLISH=1
```

Builds a version-stamped bundle signed with the `AeroControl Dev` certificate
(`script/sign-identity.sh`; the release refuses to run without it, because an ad-hoc release
would revoke every user's Screen Recording grant on upgrade), publishes the GitHub Release,
and writes a Homebrew cask to `.release/aerocontrol.rb`. Copy that cask to
[kim-raaschou/homebrew-tap](https://github.com/kim-raaschou/homebrew-tap) as
`Casks/aerocontrol.rb` and commit it. Omit `PUBLISH=1` for a dry run.

## License

[MIT](LICENSE)
