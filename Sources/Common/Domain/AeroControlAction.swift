import Foundation

public enum AeroControlAction: Equatable, Sendable {
    case focusWorkspace(String)
    case focusWindow(Int)
    case moveWindow(windowId: Int, toWorkspace: String)
    case closeWindow(Int)
}
