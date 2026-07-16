import Foundation

/// Domain vocabulary for things that change in the AeroSpace world.
/// Parsing from the CLI's JSON output lives in `Aerospace/AerospaceEventParser.swift`.
public enum AerospaceEvent: Equatable, Sendable {
    case focusChanged(windowId: Int?, workspace: String)
    case workspaceChanged(workspace: String, prevWorkspace: String)
    case monitorChanged(workspace: String, monitorId: Int?)
    case windowDetected(windowId: Int, workspace: String?, appBundleId: String?, appName: String?)
    case bindingTriggered
    /// AeroControl's OWN, locally-emulated close signal — never parsed from AeroSpace's
    /// stream. Stock AeroSpace emits no event when a window closes or an app quits, so we
    /// detect it ourselves via two native macOS taps that both funnel into this one case:
    ///   • the global left-mouse-up doorbell (a background window closed with the mouse) —
    ///     the same trick AeroSpace uses internally for unreliable close-button detection,
    ///   • `NSWorkspace` app-termination (an app quit, taking all its windows at once).
    /// Both mean the same thing: reconcile against reality by reloading the full list.
    case localWindowClosed
    case other
}

