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
  (column count chosen for the largest tiles), in the order they sit on screen.
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

## Gallery

![AeroControl overview](docs/media/gallery-hero-top-arc-ws6.png)
*Overview overlay with live workspace/app state.*

![AeroControl menu items](docs/media/gallery-menu-items.png)
*Open menu showing theme, the Screen Recording prompt, reset, and quit.*

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

`make install` builds `AeroControl.app`, installs it to `/Applications` and relaunches it.

macOS ties the Screen Recording grant to the app's code signature, and an ad-hoc
signature changes with every build. To keep the grant across rebuilds, create a
self-signed code-signing certificate named `AeroControl Dev` once; the Makefile picks it
up automatically (no trust settings needed):

```bash
T=$(mktemp -d) && cd "$T" && printf '[req]\ndistinguished_name=dn\nx509_extensions=v3\nprompt=no\n[dn]\nCN=AeroControl Dev\n[v3]\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,codeSigning\nbasicConstraints=critical,CA:false\n' > ext.cnf && \
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -keyout key.pem -out cert.pem -config ext.cnf && \
openssl pkcs12 -export -inkey key.pem -in cert.pem -name "AeroControl Dev" -out dev.p12 -passout pass:x && \
security import dev.p12 -k ~/Library/Keychains/login.keychain-db -P x -T /usr/bin/codesign && cd - && rm -rf "$T"
```

After switching signatures, re-grant Screen Recording once (System Settings ▸ Privacy &
Security ▸ Screen & System Audio Recording) and relaunch AeroControl.

### Summon it from AeroSpace

Opening AeroControl while it runs toggles the overview: Launch Services hands the running
instance a reopen event, no second process is started. When it is not running the same command
starts it. Bind a key to it:

```toml
cmd-ctrl-alt-space = ['exec-and-forget open -a AeroControl']
```

`open -n` (a forced second instance, which signals the first with SIGUSR1 and exits) still
works but costs about 200 ms more.

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

Builds a version-stamped bundle signed with the `AeroControl Dev` certificate (see *Build
from source*; the script refuses to run without it, because an ad-hoc release would revoke
every user's Screen Recording grant on upgrade), publishes the GitHub Release, and writes
a Homebrew cask to `.release/aerocontrol.rb`. Copy that cask to
[kim-raaschou/homebrew-tap](https://github.com/kim-raaschou/homebrew-tap) as
`Casks/aerocontrol.rb` and commit it. Omit `PUBLISH=1` for a dry run.

## License

[MIT](LICENSE)
