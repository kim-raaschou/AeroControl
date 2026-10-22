# How the map and the strip decide

Two surfaces, two rules. This is the reasoning the README leaves out.

## The map follows AeroSpace

The overview is a picture of what AeroSpace has, and nothing in it is chosen until you point,
type or press an arrow. Each window is drawn where AeroSpace put it and as big as it is: an app
that will not shrink to its slot, Mail or Messages in a narrow column, sticks out over its
neighbour on the card as it does on the screen. Until then the ring is AeroSpace's focus: it
moves the moment AeroSpace reports a focus change. Switch workspace with your AeroSpace key
while the map is up and the ring is on the new window before the pictures have settled.

The arrows take the ring over: ← and → through each workspace's windows as they are drawn,
which AeroSpace's order within a workspace does not give, then on to the next; ↑ and ↓ straight
up and down as the windows are drawn. AeroSpace's focus goes along with every step, so
AeroSpace's own keys act on the window under the ring, and Escape takes it back to the window
you came from. Pointing and typing move only the ring.

Matching is word-prefix, case- and diacritic-insensitive: every word you type must start a word
in the window's title, app name or workspace name, taken together. `te` finds Teams, `toml`
finds `aerospace.toml`, `lars teams` finds a chat, `2 saf` Safari on workspace 2. A query that
matches nothing leaves the full map standing and says so.

### The grid

One card per workspace, in AeroSpace's order, every card the same size and the shape of its
screen, as GNOME and KWin shape their workspace cells. Cards hold still through window churn.
Inside a card every window is drawn where AeroSpace put it, at its own shape, or packed at one
height when AeroSpace has not said, in the order `list-windows` gives them, by app and then
title. The layout engine is shared with
[krn.overview](https://github.com/kim-raaschou/krn.overview), the same author's overview for
Omarchy/Hyprland. The card the ring is in names the ring's window at its top, its app's icon, name
and title, centred between the workspace and its layout; the line under the cards keeps the keys
and what is typed. Floating windows are always floats: they lie over the card where they stand on
the screen, faint, packed tiles or not, a workspace of floats only too; on a hidden workspace, where AeroSpace has parked them in a
corner, where AeroSpace will put them back, as its rect says, so a float holds still as the
focus comes and goes. Without that rect (a released AeroSpace), in the middle of the card at
their own size. Only
while a query is typed is every window packed as a tile. A card's icon says whether its
workspace is tiles or an accordion; AeroSpace's own layout key changes it, and the card follows.

### Merge

Drag a workspace card, grabbed anywhere outside a tile, onto another workspace: all of its
windows move there, in on-screen order, and the target is focused. AeroSpace moves windows one
by one into the target's root, so into an empty workspace the source's layout comes along, a
stack stays a stack, while into one with windows they tile beside what is there. No undo: drag
them back.

## The strip is a picker

The per-app keys settle four of their five cases from AeroSpace's state alone, at once and
without a word: none, start; one, focus; from another app, the app's window you used last, as
⌘Tab does; two and you are in one, the other. The fifth case, three or more and you are in one,
has no answer without you, and that is the strip, as ⌘` is the second step after ⌘Tab: a row
of the app's workspaces, a marking on the most likely answer (the app's window you used last
other than the one you are in, or else the one after it), and keys to move it and confirm.
AeroSpace's focus follows the marking from the moment the strip opens; Enter keeps it there,
Escape takes the focus back to the window you came from. From the map an app's key is a question
already: there two windows from elsewhere open the strip too.

A strip is opened only by its app's key. While it is up AeroSpace still decides: move the focus
within the app and the strip stands; move it anywhere else, with an AeroSpace key, another app
or an empty workspace, and the strip closes and you are where AeroSpace put you.

Each card is one of the app's workspaces and holds the app's windows on it, no other app's: the
strip asks only which of them, and the map is where a window's neighbours are seen. Where they
are all tiled and side by side, they stand in AeroSpace's arrangement, other apps' windows
between them left out, side by
side, stacked, a column beside a pair, every window at its own shape and the parts of a split
sharing the side across it: a column beside two stacked windows is as high as the two together,
and each of the two as wide and as high as it is. The card is as wide as that makes the block.
Where the app's windows fill their block this is AeroSpace's own layout; where other apps'
windows leave holes in it, the parts close up, each at its shape, so a picker sees every picture
whole and legible. Every picture is the
whole window in its own shape, as large as its tile allows, never cut. Otherwise (an accordion, a float) they are packed
large, each in its window's own shape, two always in one row. A card is at most 45 % of the
panel high. Each window's title sits on its picture, one line, so three terminals can be told
apart. The card the marking is in names the marked window at its top, as the map does; one line
under the cards names the app, how many windows, and the marked window's workspace when the app
spans more than one.

Built for two to five windows of an app: there the strip is a confirm step with a picture, and
the arrows are the exception. It handles more: a row that does not fit slides to keep the
marked workspace whole in the middle, the workspaces the edges cut dimmed; a workspace's name
goes straight to it.

## Pictures and speed

Each window is captured when the overview opens (ScreenCaptureKit, which reaches windows
AeroSpace has parked off-screen), at the pixels its tile draws, and again only when its tile
grows or its window changes shape. The overview shows at once, about 80 ms after the key, with
the last visit's picture of every window that still has its shape; the new ones replace them
card by card, about 25 ms a window (fifty windows: just over a second). A picture fades in once;
one taken again takes the old one's place. The window under the ring is live, a stream rather
than a picture, on the map and in the strip.

Both summons reach the running instance through Launch Services: no second process, no signal.
On an AeroControl already running, `open -a AeroControl` is a reopen event and toggles the map,
which is why it belongs in `after-startup-command` and nowhere else.
