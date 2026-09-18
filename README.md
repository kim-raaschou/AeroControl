# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A one-shot workspace overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Summon it, see every workspace across your monitors with window previews, do one thing —
focus a window, jump to a workspace, move a window, merge two workspaces — and it is gone.

All AeroSpace calls run over the AeroSpace Unix socket path (subscribe, list, focus, move, close).

## Features

- One shot, Mission-Control style: a full-screen blurred overlay on the screen under the
  mouse. Starts hidden, summoned by opening it again (bind that to a key), dismissed as
  soon as you focus a window or a workspace, or with Escape / a click on the backdrop.
- A predictable grid, Mission-Control style: one card per workspace, in rows of as equal
  length as possible. Every row is the same height and every card that holds windows is the
  same width, so a workspace sits in the same place whatever it happens to contain; empty
  workspaces shrink to a badge. Inside a card the windows fill it as a grid of 3:2 tiles
  (column count chosen for the largest tiles), in AeroSpace's order.
- **Type to filter**: start typing and the grid collapses to the windows whose title or app
  name has a word starting with what you typed — `te` finds Teams, `toml` finds
  `aerospace.toml`, `lars teams` finds a chat. Each match shows its full title, the focus ring
  marks the first one, Tab moves it, Enter focuses it. See *Keyboard*.
- **This app's windows**: a second summon, `open aerocontrol://app`, opens the overview
  already filtered to the app you are in — three Arc windows, nothing else — with the ring
  on the next one, so Enter alone switches instance and Tab walks the rest.
- **Floating windows** are marked by a raised shadow, so a window that is not part of the
  tiling layout reads as lying on top of it.
- **Window previews**: each window is captured once when the overview opens (ScreenCaptureKit,
  works for windows AeroSpace has parked off-screen). Needs the Screen Recording permission;
  without it the overview shows app icons instead, and the menu offers to request it.
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
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation) 0.21.1 or newer
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

Opening AeroControl while it runs toggles the overview: Launch Services hands the running
instance a reopen event, no second process is started. When it is not running the same command
starts it. Bind a key to it:

```toml
cmd-ctrl-alt-space = ['exec-and-forget open -a AeroControl']
```

`open -n` (a forced second instance, which signals the first with SIGUSR1 and exits) still
works but costs about 200 ms more.

For the overview of the focused app's windows only, bind a second key to the URL:

```toml
cmd-ctrl-alt-a = ['exec-and-forget open aerocontrol://app']
```

## Keyboard

| Key | Does |
|---|---|
| letters, digits, space | filter; the grid narrows from the second character |
| Tab, → / Shift-Tab, ← | move the focus ring to the next / previous match |
| Enter | focus the window under the ring |
| Escape | clear the query; on an empty query, dismiss |
| ⌘W | dismiss |
| ⌘Q | quit the app under the pointer — the overview stays up, Mission-Control style |

Matching is word-prefix, case- and diacritic-insensitive: every word you type must start a
word in the window's title or app name. A query that matches nothing leaves the full map
standing and says so.

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration:

- **Theme**: **System** follows macOS (your accent color, light/dark, frosted cards), or one
  of the built-in palettes — Tokyo Night, Catppuccin Mocha, Catppuccin Latte, Nord, Gruvbox
  Dark, Dracula, Rosé Pine, Solarized Dark — each shown with a colour swatch. A fixed palette
  looks the same whatever the system appearance is.
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
