import Foundation

public struct WindowInfo: Equatable, Hashable, Sendable {
    public let windowId: Int
    public let appName: String
    public let bundleId: String
    /// Whether the window sits outside the tiling flow (AeroSpace parent layout
    /// `floating`). Drives the dotted floating marker on its tile.
    public let isFloating: Bool

    public init(windowId: Int, appName: String, bundleId: String, isFloating: Bool = false) {
        self.windowId = windowId
        self.appName = appName
        self.bundleId = bundleId
        self.isFloating = isFloating
    }
}

public struct WorkspaceInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public var windows: [WindowInfo]
    public var monitorId: Int

    public init(name: String, windows: [WindowInfo], monitorId: Int = 1) {
        self.name = name
        self.windows = windows
        self.monitorId = monitorId
    }
}

public struct MonitorInfo: Equatable, Hashable, Identifiable, Sendable {
    public var id: Int { monitorId }
    public let monitorId: Int

    public init(monitorId: Int) {
        self.monitorId = monitorId
    }
}

public struct OverviewResult: Equatable, Sendable {
    public let workspaces: [WorkspaceInfo]
    public let monitors: [MonitorInfo]

    public init(workspaces: [WorkspaceInfo]) {
        self.workspaces = workspaces
        self.monitors = Array(Set(workspaces.map(\.monitorId))).sorted().map { MonitorInfo(monitorId: $0) }
    }
}

