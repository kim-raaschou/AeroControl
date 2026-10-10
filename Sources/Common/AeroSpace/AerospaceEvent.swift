import Foundation

/// AeroSpace's events, as far as the overview takes them.
public enum AerospaceEvent: Equatable, Sendable {
    /// The focus went to this window on this workspace; no window on an empty workspace.
    case focusChanged(windowId: Int?, workspace: String)
    /// Something changed in AeroSpace.
    case changed
}
