import Foundation

/// Domain vocabulary for things that change in the AeroSpace world.
/// Parsing from the CLI's JSON output lives in `Aerospace/AerospaceEventParser.swift`.
public enum AerospaceEvent: Equatable, Sendable {
    case focusChanged(windowId: Int?, workspace: String)
    case workspaceChanged(workspace: String, prevWorkspace: String)
    case monitorChanged(workspace: String, monitorId: Int?)
    case windowDetected(windowId: Int, workspace: String?, appBundleId: String?, appName: String?)
    case bindingTriggered
    case appTerminated
    /// A window closed without any focus change to observe (e.g. closing a
    /// background window with the mouse). Stock AeroSpace emits no event for this,
    /// so it is surfaced by the native close doorbell; once AeroSpace ships its own
    /// `window-closed` event it maps here too. Either way: reconcile against reality.
    case windowClosed
    case other
}

