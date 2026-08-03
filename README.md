# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A floating workspace overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

Summon it to see all workspaces across your monitors with live app icons. Click to focus windows, click workspaces to jump, drag icons to move windows, and hover to close.

All AeroSpace calls run over the AeroSpace Unix socket path (subscribe, list, focus, move, close).

## Features

- Live workspace mirror across monitors.
- Windows shown in the order they sit on screen, not alphabetically.
- Click app icon to focus window.
- Click workspace card/badge to focus workspace.
- Drag app icon to move window between workspaces.
- Hover app icon to reveal close action.
- Single-instance toggle: launching AeroControl again toggles visibility instantly.
- Multi-screen support: one selected screen or all screens.
- Menu-bar configuration with persisted settings.
- No extra macOS privacy permissions required for AeroControl itself.

## Gallery

![AeroControl overview](docs/media/gallery-hero-top-arc-ws6.png)
*Overview overlay with live workspace/app state.*

![AeroControl menu items](docs/media/gallery-menu-items.png)
*Open menu showing screen selection, icon size, position, reset, and quit.*

## Requirements

- macOS 26+
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation) 0.21.1 or newer

```bash
brew install --cask nikitabobko/tap/aerospace
```

On-screen window ordering uses `list-windows --sort-by dfs`, which is not in a released
AeroSpace yet ([PR #2207](https://github.com/nikitabobko/AeroSpace/pull/2207)). Until it
lands, AeroControl falls back to AeroSpace's own ordering.

## Install

### Homebrew (recommended)

```bash
brew install --cask kim-raaschou/tap/aerocontrol
```

### Build from source

Requires Swift 6.2 (Xcode 26 or [swift.org](https://www.swift.org/install/macos/)) and `make`.

```bash
git clone https://github.com/kim-raaschou/AeroControl.git
cd AeroControl
make install
```

`make install` builds and installs `AeroControl.app` to `/Applications`.

## Configure it from the menu bar

Use the menu-bar icon for all in-app configuration:

- **Screen**: choose active display or **Show on All Screens**.
- **Icon Size**: 16 / 24 / 32 / 48 / 96.
- **Position**: Top / Bottom / Left / Right / Center / Menu Bar.
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
