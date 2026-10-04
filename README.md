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
- **"Which of my Arc windows?"** One key per app (`aerocontrol://<bundle id>`).
  With three Arc windows, only they appear, with their titles, and the ring is already on
  the next one — Enter switches. Cmd-` with pictures. With one window the key just focuses
  it, and with none it starts the app.
- **"The Teams window with the meeting in it."** Press the key and type `te`: the map
  collapses to the windows whose title or app name starts with that, titles shown. Type more
  to narrow, Enter when it is first. No mouse, no reading a number off a badge.
- **"This belongs on workspace 3."** Drag the window's picture onto the other card. Or drag
  a whole card onto another to merge two workspaces into one.
- **"Close the strays."** Hover a picture for its close button, or point at a window and press
  ⌘Q to quit that app — the overview stays up for the next one.

What it is not: a window manager, a dock, or a permanent panel. It has no state of its own
between summons, and it asks for no permission except Screen Recording for the pictures.

## Features

- One shot, Mission-Control style: a full-screen blurred overlay on the screen under the
  mouse. Starts hidden, summoned by a key bound to `open aerocontrol://workspaces`, dismissed
  as soon as you focus a window or a workspace, or with Escape / a click on the backdrop.
  The focus ring is AeroSpace's: it sits on the focused window and follows every focus change
  AeroSpace reports, the moment it reports it. Nothing in the overview walks it. See *Keyboard*.
- A grid that spends the screen on the windows: one card per workspace, in AeroSpace's
  order, every card the same size and the shape of its screen, as GNOME and KWin shape their
  workspace cells. Cards hold still through window churn. Inside a card every window is drawn
  where AeroSpace put it, at its own shape, or packed at one height when AeroSpace has not said, in
  AeroSpace's order. The layout engine is shared with
  [krn.overview](https://github.com/kim-raaschou/krn.overview), the same author's overview
  for Omarchy/Hyprland.
- **Type to filter**: start typing and the grid collapses to the windows whose title or app
  name has a word starting with what you typed — `te` finds Teams, `toml` finds
  `aerospace.toml`, `lars teams` finds a chat. Each match shows its full title, the focus ring
  marks the first one, Enter focuses it: type until the one you want is first. See *Keyboard*.
- **One key per app**: `open aerocontrol://<bundle id>` opens the overview
  already filtered to that app — three Arc windows, nothing else — with the ring on the next
  one, so Enter alone switches instance and Tab walks the rest. Under the cards a legend lists
  the windows, key and title each, so a window is read there when its picture is a sliver on
  a crowded workspace. With a single window the key focuses it.
- **Floating windows** are marked by a raised shadow, so a window that is not part of the
  tiling layout reads as lying on top of it.
- **Window previews**: each window is captured once per summon (ScreenCaptureKit, works for
  windows AeroSpace has parked off-screen). The overview appears first, in its final shape,
  and the pictures land in it as they are taken — about 170 ms to the overview and another
  ~300 ms until the last of twenty pictures. Needs the Screen Recording permission; without
  it the tiles are empty plates — the overview is built around the pictures — and the menu
  offers to request it.
- Click a tile to focus the window; click a workspace badge to focus the workspace.
- Drag a tile onto another workspace to move the window there.
- **Merge**: drag a workspace card (grab it anywhere outside a tile) onto another workspace to
  move all of its windows there, in on-screen order, then focus the target. No undo — drag
  them back.
- Hover a tile to reveal the close action.
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
<your key>      = ['exec-and-forget open aerocontrol://workspaces']      # the map
<a key per app> = ['exec-and-forget open aerocontrol://<bundle id>']     # that app, e.g. aerocontrol://com.apple.Safari
```

`workspaces` closes the overview when it is already up; an app's key while it is up is that app's flow again, its strip
taking over from whatever was showing. The strip is not a third view: it is the part of the app rule that cannot be
settled without you (see *The map and the strip*). The rule:

| Windows of the app | What happens |
|---|---|
| none | the app starts |
| one | that window is focused |
| two, and you are in one | the other one is focused — a toggle |
| two from elsewhere, or more | the strip opens with just them, ring on the next — pick |

Bundle ids of everything open: `aerospace list-windows --all --format '%{app-bundle-id} %{app-name}'`.

`open -a AeroControl` toggles the map too (a reopen event), and is the one command that works
before the URL scheme is registered — Launch Services learns it on the app's first launch.

## The map and the strip

Two surfaces, two rules.

**The map follows AeroSpace.** The overview is a picture of what AeroSpace has, and nothing
in it is chosen until you point or type. The ring is AeroSpace's focus: it moves the moment
AeroSpace reports a focus change — switch workspace with your AeroSpace key while the map is
up and the ring is on the new window before the pictures have settled. No key walks it; a
map with its own cursor would be a state AeroSpace does not have. Find a window by pointing
at it, or by typing until it is first.

**The strip is a picker.** The per-app keys settle three of their
four cases from AeroSpace's state alone, at once and without a word (none: start; one: focus;
two and you are in one: the other). The fourth case — two windows from another app, or three
or more — has no answer without you, and that is the strip: the app's windows in a row, a
marking on the most likely answer (the window after the one you are in, or the one you used
last), and keys to move it and confirm. The marking is your choice in the making, so it lives
in the strip, not in AeroSpace, until Enter makes it AeroSpace's focus. Two truths are on
screen: the ring is the marking, the thin outline is where AeroSpace's focus is now.

The cards are true to AeroSpace's geometry, and on a crowded workspace that is slivers under
slivers: eighteen windows in `h_tiles` get 82 points each, and no picture of that is readable.
So the strip carries a legend under the cards, one line per window — its key, its title, its
workspace when the app spans more than one — with the marked line in the accent. The cards say
where a window is; the legend says which it is, and the key on its line picks it.

Built for two to five windows of an app: there the strip is a confirm step with a picture, and
Tab is the exception. It handles more — the row turns into a carousel when it does not fit,
⌘1–⌘9 and ⌘a–⌘f reach the first fifteen, Tab the rest, and the legend stays readable throughout.

## Keyboard

On the map:

| Key | Does |
|---|---|
| letters, digits, space | filter; the grid narrows from the second character |
| Enter | focus the window under the ring: the first match, or the focused window |
| Escape | clear the query; on an empty query, dismiss |
| ⌘W | dismiss |
| ⌘Q | quit the app under the pointer — the overview stays up, Mission-Control style |

Matching is word-prefix, case- and diacritic-insensitive: every word you type must start a
word in the window's title or app name. A query that matches nothing leaves the full map
standing and says so. Without a query the ring is on AeroSpace's focused window: the map is
read, not steered.

In the strip:

| Key | Does |
|---|---|
| Tab, → / Shift-Tab, ← | move the marking to the next / previous window, wrapping |
| ⌘1 – ⌘9, ⌘a – ⌘f | focus that window: the keys the windows carry, fifteen in all |
| the app's own key again | move the marking on, as Cmd-` does |
| Enter | focus the marked window |
| Escape | dismiss, back on the window you came from |

There is no typing in the strip; the app is already chosen. Pointing marks a window too.

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration:

- **Theme**: **System** follows macOS (your accent color, light/dark, frosted cards), or one
  of the built-in palettes — Tokyo Night, Catppuccin Mocha, Catppuccin Latte, Nord, Gruvbox
  Dark, Dracula, Rosé Pine, Solarized Dark — each shown with a colour swatch. A fixed palette
  looks the same whatever the system appearance is.
- **Backdrop**: how much of the desktop shows through behind the cards, 100 % down to 70 %
  in steps of 5. Below that the desktop competes with the cards.
- **Animation**: Off, Fast, Normal or Slow. One scale on every motion — the reveal, the grid
  reflowing under a query, a picture landing.
- **App picker**: On shows the strip — one row of the app's windows, like macOS's own
  switcher, and two windows toggle. Off, those rules are off and the key passes through: an
  app key with more than one window just brings the app forward. No windows (start it) and
  one window (focus it) work either way.
- **Window Previews**: grant Screen Recording when it is missing.
- **Reset settings** and **Quit**.

Selections persist automatically (`UserDefaults`).

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
