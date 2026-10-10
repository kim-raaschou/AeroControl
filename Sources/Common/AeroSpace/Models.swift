import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    public let isFloating: Bool
    public let isFullscreen: Bool
    public let isHidden: Bool
    public let title: String
    public let layoutRect: CGRect?

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false,
                isFullscreen: Bool = false, isHidden: Bool = false, title: String = "", layoutRect: CGRect? = nil) {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.isFullscreen = isFullscreen
        self.isHidden = isHidden
        self.layoutRect = layoutRect
        self.title = title
    }

    public var caption: String {
        let text = title.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return appName }
        for separator in [" — ", " – ", " - ", " | "] {
            let tail = separator + appName
            if text.count > tail.count, text.suffix(tail.count).lowercased() == tail.lowercased() {
                let head = text.dropLast(tail.count).trimmingCharacters(in: .whitespaces)
                return head.isEmpty ? appName : head
            }
        }
        return text
    }
}

public struct WorkspaceInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let windows: [WindowInfo]
    public let monitorId: Int
    public let monitorName: String
    public let screenIndex: Int
    public let rootLayout: String

    public var monitorShortName: String {
        String(monitorName.split(separator: " ").first ?? "")
    }

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "", screenIndex: Int = 0, rootLayout: String = "") {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
        self.screenIndex = screenIndex
        self.rootLayout = rootLayout
    }

    public func with(windows: [WindowInfo]) -> WorkspaceInfo {
        WorkspaceInfo(name: name, windows: windows, monitorId: monitorId, monitorName: monitorName, screenIndex: screenIndex, rootLayout: rootLayout)
    }
}

public struct Focus: Equatable, Sendable {
    public let windowId: Int
    public let workspace: String

    public init(windowId: Int = 0, workspace: String = "") {
        self.windowId = windowId
        self.workspace = workspace
    }
}

public struct OverviewResult: Equatable, Sendable {
    public let workspaces: [WorkspaceInfo]
    public let focus: Focus?
    public init(workspaces: [WorkspaceInfo], focus: Focus? = nil) {
        self.workspaces = workspaces
        self.focus = focus
    }
}

public struct ParsedWindow: Equatable {
    public let window: WindowInfo
    public let workspace: String

    public init(window: WindowInfo, workspace: String) {
        self.window = window
        self.workspace = workspace
    }
}
