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
- **"Close the strays."** Hover a picture for its close button, or walk until it wears the ring
  and press ⌘W, the app's own: the overview stays up for the next one.
- **"Another Ghostty, while I'm here."** Hold ⌘ and the keyboard is the app's under the ring:
  ⌘N, ⌘T, ⌘W act in it, and the map shows what they did. Let go and the keys are AeroControl's.

What it is not: a window manager, a dock, or a permanent panel. It has no state of its own
between summons, and it asks for no permission except Screen Recording for the pictures.

## Features

- One shot, Mission-Control style: a full-screen blurred overlay on the screen under the
  mouse. Starts hidden, summoned by a key bound to `open aerocontrol://workspaces`, dismissed
  as soon as you focus a window or a workspace, or with Escape / a click on the backdrop.
  The ring starts on AeroSpace's focused window and follows every focus change AeroSpace
  reports, until you press an arrow: then it is yours, and AeroSpace's focus goes with it, so
  AeroSpace's own keys act on the window under the ring; Escape takes the focus back. The window under the ring is live, a stream of it rather than the
  picture taken at the summon, on the map and in the strip. See *Keyboard*.
- A grid that spends the screen on the windows: one card per workspace, in AeroSpace's
  order, every card the same size and the shape of its screen, as GNOME and KWin shape their
  workspace cells. Cards hold still through window churn. Inside a card every window is drawn
  where AeroSpace put it, at its own shape, or packed at one height when AeroSpace has not said, in
  the order `list-windows` gives them, by app and then title. Where AeroSpace put a window is `%{window-layout-rect}`, which no AeroSpace
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
  you used before, so Enter alone goes back to it and the arrows walk the rest. Each window's
  title sits on its picture; one line under the cards names the app, and the marked window's
  workspace when the app spans more than one. With a single window the key focuses it.
- **Floating windows** are marked by a raised shadow, so a window that is not part of the
  tiling layout reads as lying on top of it.
- **Window previews**: each window is captured when the overview opens (ScreenCaptureKit, works
  for windows AeroSpace has parked off-screen), at the pixels its tile draws, and again only when
  its tile grows or its window changes shape. The overview shows at once, about 80 ms after the
  key, with the last visit's picture of every window that still has its shape; the new ones replace
  them card by card, about 25 ms a window (fifty windows: just over a second). A picture fades in
  once; one taken again takes the old one's place. Needs the Screen Recording permission; without
  it the tiles are plates with their app's icon and the window's title — the overview is built
  around the pictures — and the menu offers to request it.
- Click a tile to focus the window; click a workspace badge to focus the workspace.
- A card's icon says whether its workspace is tiles or an accordion; AeroSpace's own layout key changes it, and the card follows.
- Drag a tile onto another workspace to move the window there.
- **Merge**: drag a workspace card (grab it anywhere outside a tile) onto another workspace to
  move all of its windows there, in on-screen order, then focus the target. AeroSpace moves
  windows one by one into the target's root, so into an empty workspace the source's layout
  comes along — a stack stays a stack — while into one with windows they tile beside what is
  there. No undo — drag them back.
- Hover a tile on the map to reveal the close action; the strip has no close button, the app's ⌘W does it there.
- **AeroSpace's keys**: when AeroSpace enters a mode other than main (`mode service`, …), a small
  hint shows that mode's keys, app keys by the app's icon and name, and goes when you are back in
  main; a mode left again within the delay set in the menu shows nothing. Pointing at a row marks
  it, a click does what its key does (`trigger-binding`); shown so, it never takes the keyboard.
  `open aerocontrol://config` shows or hides it for the mode you are in, main too, and summoned so
  it holds the keyboard when the mode leaves the arrows and Enter free: a ring starts on the first
  key, ↑ ↓ ← → move it, Enter does what the key does, Escape puts it away. A mode that binds an
  arrow or Enter keeps them, and the hint is pointed and clicked there, as a passive one is. The
  keys are read from AeroSpace (`config --get mode --json`),
  never from your config file, and the mode is asked (`list-modes --current`) whenever AeroControl
  connects, so a mode entered before it started or while it was disconnected is shown too. Where it
  shows, or off, is set in the menu.
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

Start AeroControl with AeroSpace, so the strip knows from the first summon which window you used
last:

```toml
after-startup-command = ['exec-and-forget open -g -a AeroControl']
```

`-g` keeps the launch from taking the keyboard. On an AeroControl already running the same command
opens the map, so it belongs in `after-startup-command` and nowhere else.

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
in it is chosen until you point, type or press an arrow. Each window is drawn where AeroSpace put
it and as big as it is: an app that will not shrink to its slot, Mail or Messages in a narrow
column, sticks out over its neighbour on the card as it does on the screen. Until then the ring is AeroSpace's
focus: it moves the moment AeroSpace reports a focus change — switch workspace with your
AeroSpace key while the map is up and the ring is on the new window before the pictures have
settled. The arrows take the ring over: ← and → through each workspace's windows as they are
drawn, which AeroSpace's order within a workspace does not give, then on to the next; ↑ and ↓
straight up and down as the windows are drawn. AeroSpace's focus goes along with every step,
so AeroSpace's own keys act on the window under the ring, and Escape takes it back to the
window you came from. Find a window by pointing
at it, by typing until it is first, or by walking to it.

**The strip is a picker.** The per-app keys settle three of their
four cases from AeroSpace's state alone, at once and without a word (none: start; one: focus;
two and you are in one: the other). The fourth case — two windows from another app, or three
or more — has no answer without you, and that is the strip: a row of the app's workspaces, a
marking on the most likely answer (the app's window you used last other than the one you are
in, or else the one after it), and keys to move it and confirm. AeroSpace's focus follows the marking from the moment the strip
opens, so AeroSpace's own keys act on the marked window; Enter keeps it there, Escape takes the
focus back to the window you came from.

A strip is opened only by its app's key. While it is up AeroSpace still decides: move the focus
within the app and the strip stands; move it anywhere else with an AeroSpace key, another app or
an empty workspace, and the choice was made there: the strip closes and you are where AeroSpace
put you. For another app's strip, press that app's key.

Each card is one of the app's workspaces and holds the app's windows on it, no other app's: the
strip asks only which of them, and the map is where a window's neighbours are seen. Where they are
all tiled and make one block on the screen, no other app's window among them, they stand as AeroSpace
has them, the card as wide as that block; otherwise (an accordion, a float, another app between them)
they are packed large, each in its window's own shape, two always in one row, and the card takes the
width the row gives it. A card is at most 45% of the panel high, one workspace or many. Each window's
title sits on its picture, one line, so three terminals can be told apart. One line under the cards, as
high as the map's, names the app, how many windows, and the marked window's workspace when the app
spans more than one. Pointing at a window marks it.

Built for two to five windows of an app: there the strip is a confirm step with a picture, and
the arrows are the exception. It handles more — a row that does not fit slides to keep the marked
workspace whole in the middle, up to its ends, the workspaces the edges cut dimmed; a workspace's
name goes straight to it.

## Keyboard

On the map:

| Key | Does |
|---|---|
| letters, digits, space | filter; the grid narrows from the second character |
| ← → ↑ ↓ | move the ring through the windows as drawn, on to the next workspace, AeroSpace's focus going along; an empty one is a stop |
| ⏎ | close on the window under the ring; on an empty workspace, switch to it |
| ⌘ held | the keyboard is the app's under the ring: its own shortcuts, ⌘N, ⌘W, ⌘Q, act on that window and the overview stays; let go and the keys are AeroControl's again; a tap alone hands AeroSpace the window under the ring, as an arrow does, so a typed match becomes its focus |
| Esc | clear the query; on an empty query, dismiss, back on the window you came from |

Matching is word-prefix, case- and diacritic-insensitive: every word you type must start a
word in the window's title, app name or workspace name, taken together. A query that matches nothing leaves the full map
standing and says so. Without a query the ring is on AeroSpace's focused window until a key
moves it. A key that moves the ring takes AeroSpace's focus along, so AeroSpace's own keys, a
layout or a move key say, act on the window under the ring. Pointing and typing move only the ring.

In the strip the keys move the marking as they move the ring on the map, the strip being one row of cards:

| Key | Does |
|---|---|
| ← → ↑ ↓ | move the marking through the app's windows, on to the next workspace, AeroSpace's focus going along |
| a workspace's name | move the marking to that workspace: 3 for 3, 0 for 10 |
| the app's key again | move the marking on, as ⌘` does |
| ⏎ | close on the marked window |
| ⌘ held | the keyboard is the app's under the ring: its own shortcuts, ⌘N, ⌘W, ⌘Q, act on that window and the overview stays; let go and the keys are AeroControl's again; a tap alone hands AeroSpace the window under the ring, as an arrow does, so a typed match becomes its focus |
| Esc | dismiss, back on the window you came from |

There is no typing in the strip; the app is already chosen, and a key that names a workspace goes there. Pointing marks a window, here and on the map.

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration. Motion is macOS's to set: with
**Reduce motion** on (System Settings → Accessibility → Display) the overview moves in one frame.

- **Show overview**: the map, now; under it, the line to bind to a key.
- **AeroSpace key hint**: **Show now** toggles the hint for the mode you are in, with the keyboard
  when the mode leaves the arrows free (bind `exec-and-forget open aerocontrol://config` to a key for
  it); and **Where**, one of six spots on the screen, or Off. A mode must last 400 ms before the
  hint shows, so a quick mode-and-key never flashes it.
- **Theme**: **System** follows macOS (your accent color, light/dark, frosted cards), or one
  of the built-in palettes — Tokyo Night, Catppuccin Mocha, Catppuccin Latte, Nord, Gruvbox
  Dark, Dracula, Rosé Pine, Solarized Dark — each shown with a colour swatch. A fixed palette
  looks the same whatever the system appearance is.
- **Window Previews**: grant Screen Recording when it is missing; once refused, the item opens
  the Screen Recording settings instead, since macOS asks only once.
- **Quit**.

The theme persists (`UserDefaults`). AeroControl writes no config: the key lines above are
yours to paste.

## Optional AeroSpace setting

For a stable full row of workspaces (including empty ones), set:

```toml
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
```

## Arc, and other Chromium and Electron apps

Chromium, and Electron with it, stops drawing a window macOS calls hidden, and to macOS a window AeroSpace has parked in
the corner of a hidden workspace is hidden. When AeroSpace gives such a window a new size, Arc does
not draw it at that size until it is shown again, so its picture is the old, smaller one. Start Arc
with Chromium's switch and it keeps drawing:

```bash
open -a Arc --args --disable-backgrounding-occluded-windows
```

Arc has to be quit first, and a start from the Dock or at login does not carry the switch: start
it this way, for instance from AeroSpace's `after-startup-command`. Hidden Arc windows then use a
little more power, since they go on drawing.

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
