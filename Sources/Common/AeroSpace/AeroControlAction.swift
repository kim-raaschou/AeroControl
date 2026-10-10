import Foundation

public enum AeroControlAction: Equatable, Sendable {
    case focusWorkspace(String)
    case focusWindow(Int)
    case moveWindow(windowId: Int, toWorkspace: String)
    case closeWindow(Int)
    case moveWindowQuietly(windowId: Int, toWorkspace: String)
    case mergeWorkspace(source: String, into: String)
    case setLayout(String)

    public var isFocus: Bool {
        switch self {
        case .focusWindow, .focusWorkspace: true
        default: false
        }
    }
}
