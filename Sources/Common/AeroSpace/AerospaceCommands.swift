import Foundation

public enum AerospaceCommand {
    static func format<K: CodingKey>(_ keys: [K]) -> String {
        keys.map { "%{\($0.stringValue)}" }.joined(separator: " ")
    }

    public static let listWindowsFields = format(DecodedWindow.CodingKeys.allCases.filter { $0 != .windowLayoutRect })
    static let layoutRectField = format([DecodedWindow.CodingKeys.windowLayoutRect])
    public static let listWorkspacesFields = format(WorkspaceMonitor.CodingKeys.allCases)

    public static func listWindows(layoutRects: Bool = false) -> [String] {
        ["list-windows", "--all", "--json", "--format", listWindowsFields + (layoutRects ? " " + layoutRectField : "")]
    }

    public static let listWorkspaces = ["list-workspaces", "--monitor", "all", "--json", "--format", listWorkspacesFields]

    public static let listFocusedWindow = ["list-windows", "--focused", "--json", "--format", listWindowsFields]

    public static let modes = ["config", "--get", "mode", "--json"]

    public static let subscribe = ["subscribe", "--all", "--no-send-initial"]

    public static let currentMode = ["list-modes", "--current"]

    public static func triggerBinding(_ binding: KeyBinding) -> [String] { ["trigger-binding", "--mode", binding.mode, binding.keys] }

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

    public var isFocus: Bool {
        switch self {
        case .focusWindow, .focusWorkspace: true
        default: false
        }
    }
}
