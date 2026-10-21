# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A one-shot overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace). Press a key,
see every workspace with live pictures of its windows, do one thing, and it is gone.

AeroSpace manages the windows. AeroControl only shows what AeroSpace has and hands it one
command over its socket. It is not a window manager, a dock or a panel; it keeps no state
between summons and asks for one permission, Screen Recording, for the pictures.

<!-- GIF: docs/media/map.gif — summon the map, type "te", Enter -->

## Two things it does

### 1. The map

`open aerocontrol://workspaces`

Every workspace is a card, every window a picture, laid out as AeroSpace laid it out. The
window AeroSpace has focused wears the ring, and its card names it at the top, between the
workspace and its layout. Click a window, or type until the one you want is
first and press Enter. Drag a picture onto another card to move the window there; drag a whole
card onto another to merge the two workspaces.

<!-- GIF: docs/media/move.gif — drag a picture onto another card, then a card onto a card -->

### 2. One key per app

`open aerocontrol://app-id=<bundle id>` or `open aerocontrol://app-name=<name>`

The key does what the app's windows allow, at once:

| Windows of the app | What happens |
|---|---|
| none | the app starts |
| one | it is focused |
| some, and you are in another app | the one you used last is focused, as ⌘Tab does |
| two, and you are in one | the other is focused: a toggle |
| three or more, and you are in one | the strip opens: only that app's windows, the ring on the one you used last before |

The strip is ⌘` with pictures. Enter takes the marked window, the arrows walk the rest.

<!-- GIF: docs/media/strip.gif — the app key with three Ghostty windows, →, Enter -->

## Install

```bash
brew install --cask kim-raaschou/tap/aerocontrol
```

Or from source, with Swift 6.2+ and `make`:

```bash
git clone https://github.com/kim-raaschou/AeroControl.git
cd AeroControl
make install
```

`make install` builds, installs to `/Applications` and relaunches. Run `script/sign-identity.sh`
once first to keep the Screen Recording grant across rebuilds.

Requires macOS 26 and AeroSpace 0.21.0-Beta or newer.

## Bind the keys

In your AeroSpace config (`~/.aerospace.toml` or `~/.config/aerospace/aerospace.toml`):

```toml
<your key>      = ['exec-and-forget open aerocontrol://workspaces']               # the map
<a key per app> = ['exec-and-forget open aerocontrol://app-id=com.apple.Safari']  # that app, by bundle id
<another>       = ['exec-and-forget open aerocontrol://app-name=Safari']          # or by name, spaces as %20

after-startup-command = ['exec-and-forget open -g -a AeroControl']
```

`aerospace list-apps` prints every running app's bundle id. Starting AeroControl with AeroSpace
lets the strip know from the first summon which window you used last; `-g` keeps the launch
from taking the keyboard.

The map's key closes the map when it is up. An app's key while the map is up opens that app's
strip when it has two windows or more, unless you are in one of two: then the other is focused. `open -a AeroControl` toggles the map too, and works before the URL scheme is registered.

## Keys

The ring is the window a key acts on. It starts on AeroSpace's focused window and follows
AeroSpace's focus until an arrow moves it; then AeroSpace's focus follows the ring, so
AeroSpace's own keys act on the window under it.

Hold ⌘ and the keyboard is the app's under the ring: ⌘N, ⌘W, ⌘Q act in that window, the
overview stays and shows what they did. Let go and the keys are AeroControl's again. A tap of
⌘ alone hands AeroSpace the window under the ring, as an arrow does.

On the map:

| Key | Does |
|---|---|
| letters, digits, space | filter: every word you type must start a word in a window's title, app name or workspace name |
| ← → ↑ ↓ | move the ring through the windows as drawn, on to the next workspace |
| ⏎ | focus the window under the ring; on an empty workspace, switch to it |
| Esc | clear the filter; with none, close, back on the window you came from |

In the strip:

| Key | Does |
|---|---|
| ← → ↑ ↓ | move the ring through the app's windows, on to the next workspace |
| a workspace's name | move the ring to that workspace: 3 for 3, 0 for 10 |
| the app's key again | move the ring on, as ⌘` does |
| ⏎ | focus the marked window |
| Esc | close, back on the window you came from |

There is no typing in the strip. Pointing at a window marks it, here and on the map.

## Menu

- **Show overview**: the map, now, with the line to bind under it.
- **Borders: match the accent**, shown while [JankyBorders](https://github.com/FelixKratz/JankyBorders)
  runs: the active border takes your accent colour. AeroControl does this once at start too.
- **Window Previews**: grant Screen Recording when it is missing.
- **Quit**.

AeroControl writes no config. The overview follows macOS's appearance and accent colour, and
moves in one frame when **Reduce motion** is on.

## Good to know

- **Where a window is drawn** comes from `%{window-layout-rect}`, which no AeroSpace release
  has yet; it is a branch of the author's, not yet published. With a released AeroSpace every
  card packs its tiled windows at one height instead of mirroring the screen; floating windows
  still lie where they stand.
- **Without Screen Recording** the tiles are plates with the app's icon and the window's title.
  The menu offers to request it; once refused, it opens the Screen Recording settings instead.
- **A stable row of workspaces**, empty ones included:
  `persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]` in the AeroSpace config.
- **Arc, and other Chromium and Electron apps**, stop drawing a window macOS calls hidden, and a
  window AeroSpace has parked on a hidden workspace is hidden. Resized there, it keeps its old,
  smaller picture until it is shown again. Start Arc with Chromium's switch and it keeps drawing:

  ```bash
  open -a Arc --args --disable-backgrounding-occluded-windows
  ```

  Arc has to be quit first, and a start from the Dock or at login does not carry the switch.
- **Multiple monitors**: every workspace is listed, whichever monitor it is on; each card names
  its own. The overlay opens on the screen under the mouse.
- How the map and the strip decide what they show, and how fast: [docs/design.md](docs/design.md).

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
