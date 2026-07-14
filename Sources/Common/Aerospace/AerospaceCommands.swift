import Foundation

/// Aerospace CLI command definitions — domain knowledge about the aerospace binary's API.
public enum AerospaceCommand {
    /// Fields requested by `list-windows`, in the order `DecodedWindow` documents
    /// them. Also the single source the decoder keys off (see `AerospaceField`).
    public static let listWindowsFields: [AerospaceField] = [
        .windowId, .appName, .appBundleId, .workspace, .parentLayout, .monitorId,
    ]

    /// Fields requested by `list-workspaces`.
    public static let listWorkspacesFields: [AerospaceField] = [.workspace, .monitorId]

    /// Fields requested by `list-monitors`.
    public static let listMonitorsFields: [AerospaceField] = [.monitorId, .monitorName, .nsscreenId]

    public static func listWindows() -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields.formatString]
    }

    public static func listWorkspaces() -> [String] {
        ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields.formatString]
    }

    public static func listMonitors() -> [String] {
        ["list-monitors", "--json", "--format", listMonitorsFields.formatString]
    }

    public static func subscribe() -> [String] {
        ["subscribe", "--all"]
    }

    public static func focusWorkspace(_ name: String) -> [String] {
        ["workspace", name]
    }

    public static func focusWindow(_ windowId: Int) -> [String] {
        ["focus", "--window-id", String(windowId)]
    }

    public static func moveWindowToWorkspace(_ windowId: Int, workspace: String) -> [String] {
        ["move-node-to-workspace", "--window-id", String(windowId), "--focus-follows-window", workspace]
    }

    /// Gracefully close a specific window (standard window close, not a force kill —
    /// the app may prompt to save).
    public static func closeWindow(_ windowId: Int) -> [String] {
        ["close", "--window-id", String(windowId)]
    }

    /// Maps a user action to its aerospace CLI arguments.
    public static func argv(for action: AeroControlAction) -> [String] {
        switch action {
        case .focusWorkspace(let name):
            focusWorkspace(name)
        case .focusWindow(let windowId):
            focusWindow(windowId)
        case .moveWindow(let windowId, let workspace):
            moveWindowToWorkspace(windowId, workspace: workspace)
        case .closeWindow(let windowId):
            closeWindow(windowId)
        }
    }
}
