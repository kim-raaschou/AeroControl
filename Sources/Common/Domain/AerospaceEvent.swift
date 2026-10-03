import Foundation

/// AeroSpace's events, as far as the overview takes them. Focus is the one payload taken as
/// said: AeroSpace owns the focus, its `focus-changed` names the window and the workspace
/// that took it, and the ring moves the moment the line lands, not when a read comes back.
/// Everything else the overview shows is read with a command, so every other event only
/// ever means "read again" — and that read follows a focus change too, re-deriving the focus
/// with the rest, so a dropped or out-of-order event costs latency, never correctness.
public enum AerospaceEvent: Equatable, Sendable {
    /// The focus went to this window on this workspace; no window on an empty workspace.
    case focusChanged(windowId: Int?, workspace: String)
    /// Something changed in AeroSpace.
    case changed
    /// A name we do not act on.
    case other
}
