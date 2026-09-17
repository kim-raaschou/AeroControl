import Foundation

public enum AerospaceCommand {
    /// The `--format` for a read is its decoder's own coding keys, in declaration order.
    /// Asking for exactly what we decode makes drift between the two impossible.
    static func format<K: CodingKey & CaseIterable>(_ keys: K.Type) -> String {
        K.allCases.map { "%{\($0.stringValue)}" }.joined(separator: " ")
    }

    public static let listWindowsFields = format(DecodedWindow.CodingKeys.self)
    public static let listWorkspacesFields = format(WorkspaceMonitor.CodingKeys.self)

    public static func listWindows() -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields]
    }

    public static func listWorkspaces() -> [String] {
        ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields]
    }

    /// `--focused` answers with at most one row, and none when nothing is focused.
    public static func listFocusedWindow() -> [String] {
        ["list-windows", "--focused", "--json", "--format", listWindowsFields]
    }

    public static func listFocusedWorkspace() -> [String] {
        ["list-workspaces", "--focused", "--json", "--format", listWorkspacesFields]
    }

    /// `--no-send-initial`: AeroSpace otherwise replays the current focus/workspace/monitor
    /// state on every connect, which would fire three redundant reloads right after the
    /// summon load has already read everything.
    public static func subscribe() -> [String] {
        ["subscribe", "--all", "--no-send-initial"]
    }

    public static func focusWorkspace(_ name: String) -> [String] {
        ["workspace", name]
    }

    public static func focusWindow(_ windowId: Int) -> [String] {
        ["focus", "--window-id", String(windowId)]
    }

    public static func moveWindowToWorkspace(_ windowId: Int, workspace: String, followFocus: Bool = true) -> [String] {
        ["move-node-to-workspace", "--window-id", String(windowId)]
            + (followFocus ? ["--focus-follows-window"] : [])
            + [workspace]
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
        case .moveWindowQuietly(let windowId, let workspace):
            moveWindowToWorkspace(windowId, workspace: workspace, followFocus: false)
        case .mergeWorkspace(_, let target):
            // Expanded by the reducer into a runSequence of quiet moves; only the final
            // focus switch remains if this argv is ever requested directly.
            focusWorkspace(target)
        case .closeWindow(let windowId):
            closeWindow(windowId)
        }
    }
}
