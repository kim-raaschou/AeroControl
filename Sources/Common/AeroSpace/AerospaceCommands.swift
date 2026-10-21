import Foundation

public enum AerospaceCommand {
    static func format<K: CodingKey>(_ keys: [K]) -> String {
        keys.map { "%{\($0.stringValue)}" }.joined(separator: " ")
    }

    static let listWindowsFields = format(DecodedWindow.CodingKeys.allCases.filter { $0 != .windowLayoutRect })
    static let layoutRectField = format([DecodedWindow.CodingKeys.windowLayoutRect])
    static let listWorkspacesFields = format(WorkspaceMonitor.CodingKeys.allCases)

    static func listWindows(layoutRects: Bool = false) -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields + (layoutRects ? " " + layoutRectField : "")]
    }

    static let listWorkspaces = ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields]

    static let listFocusedWindow = ["list-windows", "--focused", "--json", "--format", listWindowsFields]

    public static let subscribe = ["subscribe", "--all", "--no-send-initial"]

    public static func argv(for action: AeroControlAction) -> [String] {
        switch action {
        case .focusWorkspace(let name): ["workspace", name]
        case .focusWindow(let id): ["focus", "--window-id", String(id)]
        case .moveWindow(let id, let workspace): ["move-node-to-workspace", "--window-id", String(id), "--focus-follows-window", workspace]
        case .moveWindowQuietly(let id, let workspace): ["move-node-to-workspace", "--window-id", String(id), workspace]
        case .closeWindow(let id): ["close", "--window-id", String(id)]
        case .setLayout(let layout): ["layout", layout]
        }
    }
}

public enum AeroControlAction: Equatable, Sendable {
    case focusWorkspace(String)
    case focusWindow(Int)
    case moveWindow(windowId: Int, toWorkspace: String)
    case closeWindow(Int)
    case moveWindowQuietly(windowId: Int, toWorkspace: String)
    case setLayout(String)

    var isFocus: Bool {
        switch self {
        case .focusWindow, .focusWorkspace: true
        default: false
        }
    }
}
