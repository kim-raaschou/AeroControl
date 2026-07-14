# AeroControl

[![CI](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml/badge.svg)](https://github.com/kim-raaschou/AeroControl/actions/workflows/ci.yml)

A small floating overview for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

> [!WARNING]
> **Beta — early stage.** AeroControl is young and under active development.
> Expect rough edges, bugs, and breaking changes. Feedback and issues are welcome.

**Summon it to see your workspaces across every monitor with live app icons, click to
focus, drag to move windows — then dismiss it and get back to work.**

> AeroControl is only a thin companion. All the hard, clever work of actually tiling
> and managing your windows is done by [AeroSpace](https://github.com/nikitabobko/AeroSpace),
> a fantastic, fast, keyboard-driven tiling window manager for macOS. Huge thanks to
> [@nikitabobko](https://github.com/nikitabobko) and its contributors — go star it.
>
> I've been a tiling-WM user for years and run AeroSpace as my daily driver. I also
> [sponsor the project financially](https://github.com/sponsors/nikitabobko) — if you
> get value out of it, please consider doing the same.

## What it does

- Shows every workspace across all monitors, with native app icons
- Click a window to focus it; click empty space to focus the workspace
- Drag a window onto another workspace to move it
- Hover an icon to close the window
- A single movable, content-sized widget showing every workspace, grouped by monitor
- Summon it for a glance, then hide it with the same keybind — it stays resident, re-shows instantly, and never reflows your tiled windows
- Public accessibility APIs only — no private APIs, no SIP tweaks

## Requirements

- macOS 26+
- [AeroSpace](https://nikitabobko.github.io/AeroSpace/guide#installation) **0.21.1-Beta or newer** — AeroControl relies on `aerospace subscribe --all` and decodes the CLI's `--format` fields (including `window-parent-container-layout` and `monitor-appkit-nsscreen-screens-id`) strictly, so it stays within about one release of AeroSpace. Install/upgrade with:

  ```
  brew install --cask nikitabobko/tap/aerospace
  ```

  AeroControl versions independently (its own SemVer, currently **v0.1.0**). It is compatible
  with **AeroSpace ≥ 0.21.1**; that range — not the version number — is what governs
  compatibility, and it is shown as a separate line in the menu.

## Install

### Homebrew (recommended)

```
brew install --cask kim-raaschou/tap/aerocontrol
```

This installs a signed `AeroControl.app` into `/Applications` and strips the Gatekeeper
quarantine (the app is ad-hoc signed, not notarized — the same model AeroSpace uses).
Before using it, launch it once to grant Accessibility permission (see
[First launch & permissions](#first-launch--permissions)).

### Build from source

Requires a Swift 6.2 toolchain (Xcode 26 or [swift.org](https://www.swift.org/install/macos/)),
plus `git` and `make`; no third-party dependencies:

```
git clone https://github.com/kim-raaschou/AeroControl.git
cd AeroControl
make install
```

`make install` builds a signed `AeroControl.app` bundle and copies it to
`/Applications`.

> Prefer not to install to `/Applications`? `make bundle` leaves the app at
> `.build/release/AeroControl.app`, and `make build` produces just the bare binary at
> `.build/release/AeroControl` — point your keybind at whichever you use.

## First launch & permissions

Before you wire AeroControl into AeroSpace, launch it **once from Finder** so macOS can
grant it Accessibility permission:

1. Open **/Applications** and double-click **AeroControl.app** (it's an accessory app —
   no Dock icon; the overlay flashes up briefly).
2. macOS prompts for **Accessibility**. Open *System Settings → Privacy & Security →
   Accessibility* and toggle **AeroControl** on (add it with `+` if it isn't listed).

Do this first because AeroSpace launches AeroControl non-interactively (`exec-and-forget`,
no window, no prompt). Without the grant it can't focus/move windows — so the permission
has to be in place before it's configured. Because the app has a stable bundle identity,
the grant survives future rebuilds; you only do this once.

## Use it

Bind a key in your `aerospace.toml` (single-instance, so the same key shows/hides it).
AeroSpace runs the command directly — no shell, so `~` and `$HOME` are **not** expanded —
so use the **absolute** path to the executable inside the installed bundle:

```toml
[mode.main.binding]
cmd-ctrl-alt-space = 'exec-and-forget /Applications/AeroControl.app/Contents/MacOS/AeroControl'
```

Icon size and position are configured **from the menu-bar icon** — click AeroControl's
menu-bar icon and pick an **Icon Size** or a **Position**. Your choice is saved and
survives relaunch, so the usual flow is: launch the widget once, set it up from the
menu, then just summon and use it. No launch flags needed.

### Configure it from the menu bar

Click AeroControl's **menu-bar icon** for the settings menu:

- **Icon Size** — Extra Small (16) · Small (24) · Medium (32) · Large (48) · Extra Large
  (96); the widget reflows live. Extra Small suits a compact, menu-bar-style overlay.
- **Position** — place the widget: **Top** · **Bottom** · **Left** · **Right** ·
  **Center**. The choice also sets the layout axis — top/bottom/center give a wide, short
  widget (cards left-to-right); left/right give a tall, narrow one (each card's app icons
  stacked into a column). **Center** floats it in the middle of the focused screen, like a
  cmd-tab HUD. Picking a position snaps the widget there and the widget re-lays-out live.
- **Reset settings** — reverts icon size + position to defaults (Medium, Top).
- **Quit**.

Selections are persisted to `UserDefaults` and reflected as checkmarks in the menu.
The menu-bar menu is the only configuration surface — there are no launch flags.

Press your bound key again to hide it; press once more to summon it back —
AeroControl stays running (single-instance) and toggles its visibility, so re-showing
is instant. Choose **Quit** from the menu-bar icon to exit fully.

The overview is a single compact, content-sized **floating widget** that shows **all**
your workspaces at once, grouped by the monitor they live on (a thin separator divides
the groups, ordered left-to-right to match your displays). It **follows the focused
monitor** — summon it and it appears on whichever screen you're working on, placed at the
**Position** you chose (top-center by default). It floats above your windows with a soft
shadow, and **never touches your `aerospace.toml`** or reflows your tiled windows.
Hide it with the same keybind you summon it with (it stays resident and re-shows
instantly), or choose **Quit** from the menu-bar icon to exit.

## Configure AeroSpace

AeroControl doesn't keep its own workspace list — it mirrors exactly what
`aerospace list-workspaces --monitor all` reports. So what shows up in the strip is
governed by a couple of AeroSpace settings in your `aerospace.toml`.

### `persistent-workspaces` — a stable, complete row

By default AeroSpace only reports workspaces that currently hold a window (plus the
focused one). Empty workspaces disappear, so the overlay row keeps shrinking and
re-ordering as you open and close windows — you never see the *whole* picture.

Declare the workspaces you always want visible to pin the row in place:

```toml
persistent-workspaces = ["1", "2", "3", "4", "5", "6", "7", "8", "9"]
```

Now 1–9 always appear — even when empty — so AeroControl becomes a consistent map of
your entire layout. Clicking an empty workspace still focuses it, so it doubles as a
launcher.

## Develop

```
make build     # release build (bare binary)
make bundle    # build a signed AeroControl.app in .build/release
make install   # build the bundle and copy it to /Applications
make run       # debug build + run
make test      # tests
make clean
```

## License

[MIT](LICENSE)
