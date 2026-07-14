import Foundation

/// Domain vocabulary for things that change in the AeroSpace world.
/// Parsing from the CLI's JSON output lives in `Aerospace/AerospaceEventParser.swift`.
public enum AerospaceEvent: Equatable {
    case focusChanged(windowId: Int?, workspace: String)
    case workspaceChanged(workspace: String, prevWorkspace: String)
    case monitorChanged(workspace: String, monitorId: Int?)
    case windowDetected(windowId: Int, workspace: String?, appBundleId: String?, appName: String?)
    case bindingTriggered
    case appTerminated
    case other
}

