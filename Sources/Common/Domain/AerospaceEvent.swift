import Foundation

public enum AerospaceEvent: Equatable, Sendable {
    case focusChanged(windowId: Int?, workspace: String)
    case workspaceChanged(workspace: String, prevWorkspace: String)
    case monitorChanged(workspace: String, monitorId: Int?)
    case windowDetected(windowId: Int, workspace: String?, appBundleId: String?, appName: String?)
    case bindingTriggered
    case localWindowClosed
    case other
}

