import Foundation

public enum AerospaceCommand {
    /// The `--format` for a read is its decoder's own coding keys, in declaration order.
    /// Asking for exactly what we decode makes drift between the two impossible.
    static func format<K: CodingKey>(_ keys: [K]) -> String {
        keys.map { "%{\($0.stringValue)}" }.joined(separator: " ")
    }

    /// The fields every AeroSpace has; the layout rect is asked for separately, see `listWindows(layoutRects:)`.
    public static let listWindowsFields = format(DecodedWindow.CodingKeys.allCases.filter { $0 != .windowLayoutRect })
    static let layoutRectField = format([DecodedWindow.CodingKeys.windowLayoutRect])
    public static let listWorkspacesFields = format(WorkspaceMonitor.CodingKeys.allCases)

    /// `layoutRects`: also ask where the layout last put each window. `%{window-layout-rect}` is
    /// the owner's AeroSpace branch, not in any release; a release answers "Can't parse" and the
    /// caller falls back to the plain read.
    public static func listWindows(layoutRects: Bool = false) -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields + (layoutRects ? " " + layoutRectField : "")]
    }

    public static let listWorkspaces = ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields]

    /// `--focused` answers with at most one row, and none when nothing is focused.
    public static let listFocusedWindow = ["list-windows", "--focused", "--json", "--format", listWindowsFields]
    public static let listFocusedWorkspace = ["list-workspaces", "--focused", "--json", "--format", listWorkspacesFields]

    /// `--no-send-initial`: AeroSpace otherwise replays the current focus/workspace/monitor
    /// state on every connect, which would fire three redundant reloads right after the
    /// summon load has already read everything.
    public static let subscribe = ["subscribe", "--all", "--no-send-initial"]

    public static func argv(for action: AeroControlAction) -> [String] {
        switch action {
        // A merge is expanded by the reducer into quiet moves and a focus; asked for directly, only the focus is left.
        case .focusWorkspace(let name), .mergeWorkspace(_, let name): ["workspace", name]
        case .focusWindow(let id): ["focus", "--window-id", String(id)]
        case .moveWindow(let id, let workspace): ["move-node-to-workspace", "--window-id", String(id), "--focus-follows-window", workspace]
        case .moveWindowQuietly(let id, let workspace): ["move-node-to-workspace", "--window-id", String(id), workspace]
        case .closeWindow(let id): ["close", "--window-id", String(id)]
        }
    }
}
