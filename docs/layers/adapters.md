# Kit · Adapters

What AeroControl asks of the machine: AeroSpace's socket, and macOS for icons, window sizes, pictures and the live window. Each adapter is behind a protocol the core or the stores own, so a test can stand a fake in its place.

**`AerospaceSocketRunner`** speaks AeroSpace's wire protocol over a Unix socket: a version handshake, then length-prefixed JSON. Every `run` is a fresh connection; `subscribe` streams events on a thread of its own. Blocking calls never run on the Swift cooperative pool, since a hung daemon would park it. The socket is trusted: a transport failure is an error, not a fallback.

**`NativeApiBridgeAdapter`** implements State's `NativeApiBridge`: app icons kept at one large size, window sizes read from the window server each time, pictures taken with ScreenCaptureKit a few at a time, and the live window as a view, `LiveWindowView`, that streams the window under the ring and stops itself when it leaves its window.

**Rules.** Nothing here decides what is drawn; it answers questions. Screen Recording is asked for once, and without it every tile is a plate. The system-wide window enumeration is started before AeroSpace is read, so the two overlap.

**Decisions.** Sixteen captures in flight at once: measured, more gives nothing. The enumeration is kept for the visit and refreshed only when a window's size says it is stale.
