import Foundation

public enum AeroControlAction: Equatable, Sendable {
    case focusWorkspace(String)
    case focusWindow(Int)
    case moveWindow(windowId: Int, toWorkspace: String)
    case closeWindow(Int)
    /// Move without `--focus-follows-window`; used for bulk moves where focus must not jump.
    case moveWindowQuietly(windowId: Int, toWorkspace: String)
    /// Move every window of `source` into `into` (on-screen order preserved), then focus `into`.
    case mergeWorkspace(source: String, into: String)

    /// A focus is the visit's end: the window or workspace asked for takes the keyboard.
    public var isFocus: Bool {
        switch self {
        case .focusWindow, .focusWorkspace: true
        default: false
        }
    }
}
