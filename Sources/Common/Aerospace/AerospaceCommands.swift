import Foundation

public enum AerospaceCommand {
    public static let listWindowsFields: [AerospaceField] = [
        .windowId, .appName, .appBundleId, .workspace, .parentLayout, .monitorId,
    ]

    public static let listWorkspacesFields: [AerospaceField] = [.workspace, .monitorId, .nsScreenId]

    public static func listWindows() -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields.formatString]
    }

    public static func listWorkspaces() -> [String] {
        ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields.formatString]
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

    public static func closeWindow(_ windowId: Int) -> [String] {
        ["close", "--window-id", String(windowId)]
    }

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
