import Foundation

public enum AerospaceEvent: Equatable, Sendable {
    case focusChanged(windowId: Int?, workspace: String)
    case changed
}
