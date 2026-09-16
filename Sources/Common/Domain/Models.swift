import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    public let isFloating: Bool
    public let title: String

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false, title: String = "") {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
        self.title = title
    }
}

public struct WorkspaceInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public var windows: [WindowInfo]
    public var monitorId: Int
    /// The display AeroSpace put this workspace on, e.g. "BenQ RD280U"; shown only when
    /// there is more than one.
    public var monitorName: String

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1, monitorName: String = "") {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
        self.monitorName = monitorName
    }
}


public struct OverviewResult: Equatable, Sendable {
    public let workspaces: [WorkspaceInfo]

    public init(workspaces: [WorkspaceInfo]) {
        self.workspaces = workspaces
    }
}

