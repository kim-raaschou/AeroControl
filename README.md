# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A one-shot workspace overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Summon it, see every workspace across your monitors with window previews, do one thing —
focus a window, jump to a workspace, move a window, merge two workspaces — and it is gone.

All AeroSpace calls run over the AeroSpace Unix socket path (subscribe, list, focus, move, close).

## Features

- One shot, Mission-Control style: a full-screen blurred overlay on the screen under the
  mouse. Starts hidden, summoned by launching it again (bind that to a key), dismissed as
  soon as you focus a window or a workspace, or with Escape / a click on the backdrop.
- One equal-sized card per workspace, laid out in a near-square grid (5 workspaces → 3 on
  top, 2 below, centered). Inside a card the windows sit in a grid of 3:2 tiles sized to
  fill the card, in the order they sit on screen.
- **Window previews**: each window is captured once when the overview opens (ScreenCaptureKit,
  works for windows AeroSpace has parked off-screen). Needs the Screen Recording permission;
  without it the overview shows app icons instead, and the menu offers to request it.
- Click a tile to focus the window; click a workspace badge to focus the workspace.
- Drag a tile onto another workspace to move the window there.
- **Merge**: drag a workspace *badge* onto another workspace to move all of its windows there,
  in on-screen order, then focus the target. No undo — drag them back.
- Hover a tile to reveal the close action.
- Multi-screen support: one selected screen or all screens.
- Menu-bar configuration with persisted settings.

## Gallery

![AeroControl overview](docs/media/gallery-hero-top-arc-ws6.png)
*Overview overlay with live workspace/app state.*

![AeroControl menu items](docs/media/gallery-menu-items.png)
*Open menu showing screen selection, icon size, position, reset, and quit.*

## Requirements

- macOS 26+
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation) 0.21.1 or newer
- Optional: Screen Recording permission for AeroControl (window previews). Everything else
  works without any privacy permission.

```bash
brew install --cask nikitabobko/tap/aerospace
```

On-screen window ordering uses `list-windows --sort-by dfs`, which is not in a released
AeroSpace yet ([PR #2207](https://github.com/nikitabobko/AeroSpace/pull/2207)). Until it
lands, AeroControl falls back to AeroSpace's own ordering.

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

`make install` builds and installs `AeroControl.app` to `/Applications`.

### Summon it from AeroSpace

Launching AeroControl while it runs toggles the overview, so bind a key to a new launch:

```toml
cmd-ctrl-alt-space = ['exec-and-forget open -n /Applications/AeroControl.app']
```

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration:

- **Screen**: choose active display or **Show on All Screens**.
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

Builds a version-stamped, ad-hoc signed bundle, publishes the GitHub Release, and writes
a Homebrew cask to `.release/aerocontrol.rb`. Copy that cask to
[kim-raaschou/homebrew-tap](https://github.com/kim-raaschou/homebrew-tap) as
`Casks/aerocontrol.rb` and commit it. Omit `PUBLISH=1` for a dry run.

## License

[MIT](LICENSE)
